import Foundation
import Observation
import PharmacyCore

struct PharmacyResult: Identifiable, Hashable {
  let pharmacy: Pharmacy
  /// Unrounded straight-line distance in metres.
  let distanceMeters: Double
  let name: String
  let distance: String
  let straightLine: String
  let band: DistanceFormatting.Band

  var id: String { pharmacy.id }
  var accessibilityLabel: String { "\(name), \(straightLine)" }
  var rowAccessibilityLabel: String { "\(name), \(distance)" }
}

@MainActor
@Observable
final class PharmacyFinder {
  static let resultLimit = 20

  let localization: AppLocalization
  let datasetCount: Int
  private let pharmacies: [Pharmacy]
  let coverageGeometry: CoverageGeometry?

  private(set) var origin: Origin
  private(set) var originAddress: AddressIndex.Address?
  private(set) var results: [PharmacyResult] = []
  private(set) var selectedID: String?
  private(set) var showsDetails = false
  /// Increments with each selection so the map refits when the same pharmacy is chosen again.
  private(set) var selectionCount = 0
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
    originAddress = nil
    selectedID = nil
    showsDetails = false
    fitsMapToOrigin = fitMap
    originChangeCount += 1
    rank()
  }

  var selected: PharmacyResult? {
    selectedID.flatMap { id in results.first { $0.id == id } }
  }

  func setOriginAddress(_ address: AddressIndex.Address?) {
    switch origin.kind {
    case .device, .pin: originAddress = address
    case .default, .search: break
    }
  }

  func select(_ id: String) {
    guard results.contains(where: { $0.id == id }) else { return }
    selectedID = id
    showsDetails = true
    selectionCount += 1
  }

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

  var originLabel: String {
    switch origin.kind {
    case .default: localization.defaultOrigin
    case .device: localization.yourLocation
    case .pin: localization.droppedPin
    case .search(let title, let context): context.isEmpty ? title : "\(title) · \(context)"
    }
  }

  var originTitle: String {
    if case .search(let title, _) = origin.kind { return title }
    if let originAddress { return localization.nearAddress(originAddress.street) }
    return originLabel
  }

  var originContext: String? {
    if case .search(_, let context) = origin.kind, !context.isEmpty { return context }
    if let city = originAddress?.city, !city.isEmpty { return city }
    return nil
  }

  var originFieldLabel: String {
    guard originAddress != nil else { return originLabel }
    return [originTitle, originContext].compactMap { $0 }.joined(separator: ", ")
  }
}
