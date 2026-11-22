import Foundation
import PharmacyCore

/// Reads the street address index bundled in `AddressIndex.bundle`, synced from the web app, and
/// keeps the shards it has decoded. Lookups run on the device only.
actor AddressLookup {
  static let bundled = AddressLookup(
    directory: Bundle.main.url(forResource: "AddressIndex", withExtension: "bundle"))

  private let directory: URL?
  /// Decoded shards by cell, including cells without a usable file.
  private var shards: [String: AddressIndex.Shard?] = [:]

  init(directory: URL?) {
    self.directory = directory
  }

  /// The nearest mapped address within 120 m of `point` that lies inside the coverage.
  func nearest(to point: Coordinate, coverage: CoverageGeometry?) -> AddressIndex.Address? {
    let loaded = AddressIndex.cells(near: point).sorted().compactMap(shard)
    return AddressIndex.nearest(to: point, in: loaded) { coverage?.classify($0) == .outside }
  }

  private func shard(_ cell: String) -> AddressIndex.Shard? {
    if let cached = shards[cell] { return cached }
    // Cells without addresses, such as the sea, have no file.
    let shard =
      directory
      .flatMap { try? Data(contentsOf: $0.appendingPathComponent("\(cell).json.gz")) }
      .flatMap { try? AddressIndex.decodeShard($0) }
    shards[cell] = .some(shard)
    return shard
  }
}
