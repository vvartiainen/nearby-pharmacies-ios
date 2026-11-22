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
  /// The colour of the row's distance.
  let band: DistanceFormatting.Band

  var id: String { pharmacy.id }
  /// "{name}, {distance} straight line", read for the pin.
  var accessibilityLabel: String { "\(name), \(straightLine)" }
  /// "{name}, {distance}", read for the row, as on web.
  var rowAccessibilityLabel: String { "\(name), \(distance)" }
}

/// The active starting point and the source of its label.
struct Origin: Hashable {
  enum Kind: Hashable {
    /// Helsinki Central Railway Station, before any other choice.
    case `default`
    /// A device location fix.
    case device
    /// A point chosen on the map.
    case pin
    /// A search match: "Kauppakatu 1" in "Tampere, Finland".
    case search(title: String, context: String)
  }

  let kind: Kind
  let coordinate: Coordinate

  /// OSM node/25474663, Helsinki Central Railway Station, as in the ranking fixture and the web app.
  static let helsinkiCentral = Origin(
    kind: .default, coordinate: Coordinate(lat: 60.1720965, lon: 24.9412486))

  static func match(_ match: PlaceMatch) -> Origin {
    Origin(kind: .search(title: match.title, context: match.context), coordinate: match.coordinate)
  }
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
  private let coverageGeometry: CoverageGeometry?

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
  /// Where the origin lies relative to the bundled coverage, for the notices above the list.
  private(set) var coverage: CoverageGeometry.Classification = .covered
  /// Increments with each new origin. `fitsMapToOrigin` says whether the map should fit the
  /// origin and its results: a point chosen on the map keeps the viewport.
  private(set) var originChangeCount = 0
  private(set) var fitsMapToOrigin = true

  init(
    localization: AppLocalization, pharmacies: [Pharmacy], coverage: CoverageGeometry? = nil,
    origin: Origin = .helsinkiCentral
  ) {
    self.localization = localization
    self.pharmacies = pharmacies
    self.coverageGeometry = coverage
    self.datasetCount = pharmacies.count
    self.origin = origin
    rank()
  }

  /// Loads the snapshot bundled with the app.
  convenience init(localization: AppLocalization, bundle: Bundle = .main) {
    let loader = PharmacyDataLoader(bundle: bundle)
    let snapshot: PharmacySnapshot
    let coverage: CoverageGeometry?
    do {
      snapshot = try loader.loadSnapshot()
      coverage = try loader.loadCoverage()
    } catch {
      // The data ships in the app bundle and the unit tests check it, so this is a build error.
      fatalError("The bundled pharmacy data could not be read: \(error)")
    }
    self.init(localization: localization, pharmacies: snapshot.pharmacies, coverage: coverage)
  }

  /// Ranks from a new starting point. The old selection does not belong to the new results, so
  /// it is cleared and the sheet shows the list.
  func setOrigin(_ origin: Origin, fitMap: Bool = true) {
    self.origin = origin
    selectedID = nil
    showsDetails = false
    fitsMapToOrigin = fitMap
    originChangeCount += 1
    rank()
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
    coverage = coverageGeometry?.classify(origin.coordinate) ?? .covered
    results = rankPharmacies(origin: origin.coordinate, pharmacies: pharmacies)
      .prefix(Self.resultLimit)
      .map { ranked in
        PharmacyResult(
          pharmacy: ranked.pharmacy,
          distanceMeters: ranked.distanceMeters,
          name: localization.name(of: ranked.pharmacy),
          distance: localization.distance(meters: ranked.distanceMeters),
          straightLine: localization.straightLineDistance(meters: ranked.distanceMeters),
          band: DistanceFormatting.band(meters: ranked.distanceMeters)
        )
      }
  }

  /// The label of the active starting point, in one line.
  var originLabel: String {
    switch origin.kind {
    case .default: localization.defaultOrigin
    case .device: localization.yourLocation
    case .pin: localization.droppedPin
    case .search(let title, let context): context.isEmpty ? title : "\(title) · \(context)"
    }
  }

  /// The first line of the origin summary: the label, or a match's place or street.
  var originTitle: String {
    if case .search(let title, _) = origin.kind { return title }
    return originLabel
  }

  /// The smaller locality line under a match's title, or nil.
  var originContext: String? {
    if case .search(_, let context) = origin.kind, !context.isEmpty { return context }
    return nil
  }
}
