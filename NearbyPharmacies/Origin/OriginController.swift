import Foundation
import Observation
import PharmacyCore

/// A late search or location response must not override a newer origin.
@MainActor
@Observable
final class OriginController {
  enum SearchState: Hashable {
    case idle
    case pending
    case matches([PlaceMatch], local: Bool)
    case empty(query: String)
    case unavailable
  }

  enum LocationState: Hashable {
    case idle
    case pending
    case failed(LocationFailure)
  }

  let finder: PharmacyFinder
  private(set) var search: SearchState = .idle
  private(set) var location: LocationState = .idle
  private(set) var offersLocation: Bool

  private let geocoder: any Geocoding
  private let locator: any LocationProviding
  private let places: [Place]
  private let addresses: AddressLookup
  private let defaults: UserDefaults
  private var searchTask: Task<Void, Never>?
  private var locationRequest: UUID?
  private var addressTask: Task<Void, Never>?

  static let offerDismissedKey = "locationOfferDismissed"

  init(
    finder: PharmacyFinder, geocoder: any Geocoding, locator: any LocationProviding,
    places: [Place], addresses: AddressLookup = .bundled, defaults: UserDefaults = .standard
  ) {
    self.finder = finder
    self.geocoder = geocoder
    self.locator = locator
    self.places = places
    self.addresses = addresses
    self.defaults = defaults
    offersLocation = locator.needsPermission && !defaults.bool(forKey: Self.offerDismissedKey)
  }

  var isSearching: Bool { search == .pending }
  var isLocating: Bool { location == .pending }

  func dismissLocationOffer() {
    offersLocation = false
    defaults.set(true, forKey: Self.offerDismissedKey)
  }

  func submitSearch(_ text: String) {
    let query = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !query.isEmpty, searchTask == nil else { return }
    dismissLocationOffer()
    search = .pending
    let language = finder.localization.language.rawValue
    let country =
      finder.localization.locale.localizedString(forRegionCode: "FI") ?? "Finland"
    let places = places
    let geocoder = geocoder
    searchTask = Task { [weak self] in
      var unavailable = false
      do {
        let matches = try await geocoder.search(query, language: language)
        guard !Task.isCancelled else { return }
        if !matches.isEmpty {
          self?.finishSearch(.matches(matches, local: false))
          return
        }
      } catch {
        guard !Task.isCancelled else { return }
        unavailable = true
      }
      let local = LocalPlaces.matches(for: query, in: places, country: country)
      guard !Task.isCancelled else { return }
      self?.finishSearch(
        !local.isEmpty
          ? .matches(local, local: true) : unavailable ? .unavailable : .empty(query: query))
    }
  }

  private func finishSearch(_ state: SearchState) {
    search = state
    searchTask = nil
  }

  func cancelSearch() {
    searchTask?.cancel()
    searchTask = nil
    search = .idle
  }

  func choose(_ match: PlaceMatch) {
    apply(.match(match))
  }

  func choosePoint(_ coordinate: Coordinate) {
    apply(Origin(kind: .pin, coordinate: coordinate), fitMap: false)
    lookUpAddress(near: coordinate, accuracy: 0)
  }

  func returnToHelsinki() {
    apply(.helsinkiCentral)
  }

  func requestLocation() {
    guard locationRequest == nil else { return }
    dismissLocationOffer()
    cancelSearch()
    let request = UUID()
    locationRequest = request
    location = .pending
    Task { [weak self, locator] in
      let result = await locator.currentLocation()
      guard let self, self.locationRequest == request else { return }
      self.locationRequest = nil
      switch result {
      case .success(let fix):
        self.apply(Origin(kind: .device, coordinate: fix.coordinate))
        self.lookUpAddress(near: fix.coordinate, accuracy: fix.accuracy)
      case .failure(let failure):
        self.location = .failed(failure)
      }
    }
  }

  private func lookUpAddress(near coordinate: Coordinate, accuracy: Double) {
    guard AddressIndex.accepts(accuracy: accuracy), finder.coverage != .outside else { return }
    let change = finder.originChangeCount
    let coverage = finder.coverageGeometry
    addressTask = Task { [weak self, addresses] in
      let address = await addresses.nearest(to: coordinate, coverage: coverage)
      guard let self, !Task.isCancelled, self.finder.originChangeCount == change else { return }
      self.finder.setOriginAddress(address)
    }
  }

  private func apply(_ origin: Origin, fitMap: Bool = true) {
    addressTask?.cancel()
    addressTask = nil
    cancelSearch()
    locationRequest = nil
    location = .idle
    dismissLocationOffer()
    finder.setOrigin(origin, fitMap: fitMap)
  }
}
