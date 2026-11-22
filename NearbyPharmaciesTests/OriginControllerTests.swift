import Foundation
import PharmacyCore
import Testing

@testable import NearbyPharmacies

/// A geocoder that answers only when the test releases it, and counts its requests.
final class GatedGeocoder: Geocoding, @unchecked Sendable {
  private let lock = NSLock()
  private var waiting: [CheckedContinuation<Result<[PlaceMatch], any Error>, Never>] = []
  private(set) var queries: [String] = []

  func search(_ query: String, language: String) async throws -> [PlaceMatch] {
    let result = await withCheckedContinuation { continuation in
      lock.withLock {
        queries.append(query)
        waiting.append(continuation)
      }
    }
    return try result.get()
  }

  var pending: Int { lock.withLock { waiting.count } }

  func answer(_ result: Result<[PlaceMatch], any Error>) {
    let continuation = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
    continuation?.resume(returning: result)
  }
}

@MainActor
final class GatedLocation: LocationProviding {
  var needsPermission = true
  private var waiting: CheckedContinuation<Result<LocationFix, LocationFailure>, Never>?
  private(set) var requests = 0
  private(set) var cancellations = 0

  func currentLocation() async -> Result<LocationFix, LocationFailure> {
    requests += 1
    return await withCheckedContinuation { waiting = $0 }
  }

  func cancelLocation() {
    cancellations += 1
  }

  func answer(_ result: Result<LocationFix, LocationFailure>) {
    waiting?.resume(returning: result)
    waiting = nil
  }
}

/// Lets the controller's tasks run until `condition` holds.
@MainActor
private func settle(_ condition: () -> Bool) async {
  for _ in 0..<200 where !condition() {
    try? await Task.sleep(for: .milliseconds(5))
  }
}

private let tampere = Coordinate(lat: 61.4983, lon: 23.7732)
private let kauppakatu = PlaceMatch(
  coordinate: Coordinate(lat: 61.49819, lon: 23.75937), title: "Kauppakatu 1",
  contextParts: ["Tampere", "Finland"])

@MainActor
struct OriginControllerTests {
  let geocoder = GatedGeocoder()
  let location = GatedLocation()
  let defaults: UserDefaults = {
    let name = "OriginControllerTests.\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
  }()
  let places: [Place] = (try? PharmacyDataLoader(bundle: .main).loadPlaceIndex())?.places ?? []

  private func controller(_ language: String = "en") -> OriginController {
    let localization = AppLocalization(preferredLanguages: [language], region: .finland)
    return OriginController(
      finder: PharmacyFinder(localization: localization), geocoder: geocoder, locator: location,
      places: places, defaults: defaults)
  }

  @Test func offersLocationUntilDismissedAndNeverAsksByItself() {
    let controller = controller()
    #expect(controller.offersLocation)
    #expect(location.requests == 0)
    controller.dismissLocationOffer()
    #expect(!controller.offersLocation)
    #expect(!self.controller().offersLocation, "The dismissal is remembered")
  }

  @Test func aGrantedFixReranksFromTampere() async {
    let controller = controller()
    controller.finder.select("node/1369465553")
    controller.requestLocation()
    await settle { location.requests == 1 }
    #expect(controller.isLocating)
    #expect(controller.finder.results.first?.name == "Steissin Apteekki")

    location.answer(.success(LocationFix(tampere, accuracy: 10)))
    await settle { !controller.isLocating }
    #expect(controller.finder.origin.kind == .device)
    #expect(controller.finder.originLabel == "Your location")
    #expect(controller.finder.results.first?.name == "Tullintorin apteekki")
    #expect(controller.finder.selectedID == nil)
    #expect(controller.finder.fitsMapToOrigin)

    await settle { controller.finder.originAddress != nil }
    #expect(controller.finder.originTitle == "Near Rautatienkatu 25")
    #expect(controller.finder.originContext == "Tampere")
    #expect(controller.finder.originFieldLabel == "Near Rautatienkatu 25, Tampere")
    #expect(controller.finder.originLabel == "Your location", "The map marker keeps its label")
  }

  @Test func anImpreciseFixKeepsYourLocation() async {
    let controller = controller()
    controller.requestLocation()
    await settle { location.requests == 1 }
    location.answer(.success(LocationFix(tampere, accuracy: 500)))
    await settle { !controller.isLocating }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(controller.finder.originAddress == nil)
    #expect(controller.finder.originTitle == "Your location")
  }

  @Test func aChosenPointShowsANearbyAddress() async {
    let controller = controller()
    controller.choosePoint(tampere)
    await settle { controller.finder.originAddress != nil }
    #expect(controller.finder.originTitle == "Near Rautatienkatu 25")
    #expect(controller.finder.originLabel == "Dropped pin")

    controller.returnToHelsinki()
    #expect(controller.finder.originAddress == nil)
    #expect(controller.finder.originTitle == "Helsinki Central Railway Station (default)")
  }

  @Test(arguments: [LocationFailure.denied, .timeout, .unavailable])
  func aFailedRequestKeepsHelsinki(_ failure: LocationFailure) async {
    let controller = controller()
    controller.requestLocation()
    await settle { location.requests == 1 }
    location.answer(.failure(failure))
    await settle { !controller.isLocating }
    #expect(controller.location == .failed(failure))
    #expect(controller.finder.origin == .helsinkiCentral)
    #expect(controller.finder.results.first?.name == "Steissin Apteekki")
  }

  @Test func aLateFixDoesNotReplaceAPointChosenMeanwhile() async {
    let controller = controller()
    controller.requestLocation()
    await settle { location.requests == 1 }
    let point = Coordinate(lat: 60.2, lon: 24.9)
    controller.choosePoint(point)
    #expect(location.cancellations == 1)
    #expect(controller.finder.origin == Origin(kind: .pin, coordinate: point))
    #expect(!controller.finder.fitsMapToOrigin, "A point on the map keeps the viewport")

    location.answer(.success(LocationFix(tampere, accuracy: 10)))
    try? await Task.sleep(for: .milliseconds(50))
    #expect(controller.finder.origin.kind == .pin)
    #expect(controller.finder.originLabel == "Dropped pin")
    #expect(controller.location == .idle)
  }

  @Test func choosingAPointBeforeLocationStartsSkipsTheRequest() async {
    let controller = controller()
    controller.requestLocation()
    controller.choosePoint(tampere)
    // The scheduled location task and this continuation both run on the main actor.
    await Task { @MainActor in }.value
    #expect(location.requests == 0)
    #expect(controller.location == .idle)
  }

  @Test func aSubmittedAddressListsMatchesAndChoosingOneReranks() async {
    let controller = controller()
    controller.submitSearch("  Kauppakatu   1 ")
    #expect(controller.isSearching)
    controller.submitSearch("Kauppakatu 1")  // Ignored while a search runs.
    await settle { geocoder.pending == 1 }
    #expect(geocoder.queries == ["Kauppakatu 1"])
    #expect(controller.finder.origin == .helsinkiCentral, "The origin waits for a choice")

    geocoder.answer(.success([kauppakatu]))
    await settle { !controller.isSearching }
    #expect(controller.search == .matches([kauppakatu], local: false))

    controller.choose(kauppakatu)
    #expect(controller.search == .idle)
    #expect(controller.finder.originLabel == "Kauppakatu 1 · Tampere, Finland")
    #expect(controller.finder.originTitle == "Kauppakatu 1")
    #expect(controller.finder.originContext == "Tampere, Finland")
    #expect(controller.finder.results.first?.name == "Yliopiston Apteekki")
  }

  @Test func theBundledPlacesAnswerWhenTheGeocoderFails() async {
    let controller = controller()
    controller.submitSearch("Tammerfor")
    await settle { geocoder.pending == 1 }
    geocoder.answer(.failure(GeocodingError.unavailable))
    await settle { !controller.isSearching }
    guard case .matches(let matches, local: true) = controller.search else {
      Issue.record("Expected local matches, got \(controller.search)")
      return
    }
    #expect(matches.first?.label == "Tampere · Finland")
  }

  @Test func theBundledPlacesAlsoAnswerAnEmptyReplyInFinnish() async {
    let controller = controller("fi")
    controller.submitSearch("Helsingfors")
    await settle { geocoder.pending == 1 }
    geocoder.answer(.success([]))
    await settle { !controller.isSearching }
    guard case .matches(let matches, local: true) = controller.search else {
      Issue.record("Expected local matches, got \(controller.search)")
      return
    }
    #expect(matches.first?.label == "Helsinki · Suomi")
  }

  @Test func reportsNoMatchesAndAnUnavailableService() async {
    let controller = controller()
    controller.submitSearch("Kuvitteellinen 123")
    await settle { geocoder.pending == 1 }
    geocoder.answer(.success([]))
    await settle { !controller.isSearching }
    #expect(controller.search == .empty(query: "Kuvitteellinen 123"))

    controller.submitSearch("Kuvitteellinen 124")
    await settle { geocoder.pending == 1 }
    geocoder.answer(.failure(GeocodingError.rateLimited))
    await settle { !controller.isSearching }
    #expect(controller.search == .unavailable)
    #expect(controller.finder.origin == .helsinkiCentral)
  }

  @Test func aLateGeocoderReplyIsIgnoredAfterAPointIsChosen() async {
    let controller = controller()
    controller.submitSearch("Kauppakatu 1")
    await settle { geocoder.pending == 1 }
    controller.choosePoint(tampere)
    #expect(controller.search == .idle)

    geocoder.answer(.success([kauppakatu]))
    try? await Task.sleep(for: .milliseconds(50))
    #expect(controller.search == .idle)
    #expect(controller.finder.origin.kind == .pin)
  }

  @Test func showsCoverageNoticesAndReturnsToHelsinki() {
    let controller = controller()
    controller.choosePoint(Coordinate(lat: 65.8457589, lon: 24.1464))  // Tornio
    #expect(controller.finder.coverage == .border)
    #expect(controller.finder.results.first?.name == "Tornion I Apteekki")

    controller.choosePoint(Coordinate(lat: 65.8281312, lon: 24.1308946))  // Haparanda
    #expect(controller.finder.coverage == .outside)
    #expect(controller.finder.results.first?.name == "Tornion I Apteekki")

    controller.returnToHelsinki()
    #expect(controller.finder.origin == .helsinkiCentral)
    #expect(controller.finder.coverage == .covered)
    #expect(controller.finder.results.first?.name == "Steissin Apteekki")
  }
}
