import Foundation
import Observation
import PharmacyCore

/// One ranked pharmacy, with the strings the row, pin and details show.
struct PharmacyResult: Identifiable, Hashable {
  let pharmacy: Pharmacy
  /// Unrounded straight-line distance in metres.
  let distanceMeters: Double
  let name: String
  /// The rounded distance alone, for example "300 m".
  let distance: String
  /// The labeled distance, for example "300 m straight line".
  let straightLine: String

  var id: String { pharmacy.id }
  /// "{name}, {distance} straight line", read for the row and the pin.
  var accessibilityLabel: String { "\(name), \(straightLine)" }
}

/// The active starting point. This checkpoint has the labeled default only.
struct Origin: Hashable {
  enum Kind: Hashable {
    case `default`
  }

  let kind: Kind
  let coordinate: Coordinate

  /// OSM node/25474663, Helsinki Central Railway Station, as in the ranking fixture and the web app.
  static let helsinkiCentral = Origin(
    kind: .default, coordinate: Coordinate(lat: 60.1720965, lon: 24.9412486))
}

/// The app's state: the bundled data, the origin, its nearest results and the one selection that
/// drives the pin, the row and the details.
@MainActor
@Observable
final class PharmacyFinder {
  /// How many nearest pharmacies the list and the map show, as on web.
  static let resultLimit = 20

  let localization: AppLocalization
  /// Number of pharmacies in the bundled Finland snapshot.
  let datasetCount: Int
  private let pharmacies: [Pharmacy]

  private(set) var origin: Origin
  private(set) var results: [PharmacyResult] = []
  /// One selected pharmacy drives the row, the pin and the details. Selection never moves the
  /// origin.
  private(set) var selectedID: String?
  /// Whether the sheet shows the details of the selection instead of the list. Returning to the
  /// list keeps the selection.
  private(set) var showsDetails = false
  /// Increments with each selection so the map refits when the same pharmacy is chosen again.
  private(set) var selectionCount = 0

  init(localization: AppLocalization, pharmacies: [Pharmacy], origin: Origin = .helsinkiCentral) {
    self.localization = localization
    self.pharmacies = pharmacies
    self.datasetCount = pharmacies.count
    self.origin = origin
    rank()
  }

  /// Loads the snapshot bundled with the app.
  convenience init(localization: AppLocalization, bundle: Bundle = .main) {
    let snapshot: PharmacySnapshot
    do {
      snapshot = try PharmacyDataLoader(bundle: bundle).loadSnapshot()
    } catch {
      // The snapshot ships in the app bundle and the unit tests check it, so this is a build error.
      fatalError("The bundled pharmacy snapshot could not be read: \(error)")
    }
    self.init(localization: localization, pharmacies: snapshot.pharmacies)
  }

  var selected: PharmacyResult? {
    selectedID.flatMap { id in results.first { $0.id == id } }
  }

  /// Selects a pharmacy from its row or pin and shows its details.
  func select(_ id: String) {
    guard results.contains(where: { $0.id == id }) else { return }
    selectedID = id
    showsDetails = true
    selectionCount += 1
  }

  /// Returns from the details to the list; the pharmacy stays selected.
  func backToResults() {
    showsDetails = false
  }

  private func rank() {
    results = rankPharmacies(origin: origin.coordinate, pharmacies: pharmacies)
      .prefix(Self.resultLimit)
      .map { ranked in
        PharmacyResult(
          pharmacy: ranked.pharmacy,
          distanceMeters: ranked.distanceMeters,
          name: localization.name(of: ranked.pharmacy),
          distance: localization.distance(meters: ranked.distanceMeters),
          straightLine: localization.straightLineDistance(meters: ranked.distanceMeters)
        )
      }
  }

  /// The label of the active starting point.
  var originLabel: String {
    switch origin.kind {
    case .default: localization.defaultOrigin
    }
  }
}
