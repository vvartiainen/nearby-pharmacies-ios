import Foundation
import Observation
import PharmacyCore

/// Chooses the starting point from a search, the device location or the map, and applies it to
/// the finder. Only the newest request may publish a result: choosing any origin cancels the
/// pending search and makes a late location fix or geocoder reply irrelevant.
@MainActor
@Observable
final class OriginController {
  enum SearchState: Hashable {
    case idle
    case pending
    /// Matches to choose from. `local` when they come from the bundled place index.
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
  /// Whether the app still offers to use the device location, after the first results show.
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

  /// Runs one geocoder request for the submitted text. The bundled place index answers city
  /// searches when the geocoder fails or finds nothing. The origin stays until a match is chosen.
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

  /// Closes the matches or the search message and ignores a pending reply.
  func cancelSearch() {
    searchTask?.cancel()
    searchTask = nil
    search = .idle
  }

  func choose(_ match: PlaceMatch) {
    apply(.match(match))
  }

  /// A point chosen on the map. The viewport stays where the user put it.
  func choosePoint(_ coordinate: Coordinate) {
    apply(Origin(kind: .pin, coordinate: coordinate), fitMap: false)
    lookUpAddress(near: coordinate, accuracy: 0)
  }

  func returnToHelsinki() {
    apply(.helsinkiCentral)
  }

  /// Asks for the device location. A fix replaces the origin unless the user chose another one
  /// while waiting.
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

  /// Labels a device fix or a chosen point with a nearby street address from the bundled index,
  /// as on web. A newer origin makes the answer irrelevant.
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
