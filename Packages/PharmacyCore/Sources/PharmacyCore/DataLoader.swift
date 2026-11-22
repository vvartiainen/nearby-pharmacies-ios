import Foundation

/// Reads the bundled pharmacy data. The app bundles the files from `NearbyPharmacies/Resources/Data`,
/// which `pnpm run data:sync-ios` in the web repository copies; Xcode flattens them into the
/// bundle's resource folder.
public struct PharmacyDataLoader: Sendable {
  public enum LoadError: Error, Equatable {
    case missingFile(String)
  }

  /// The region code in the file names, for example "fi" in `pharmacies.fi.json`.
  public let region: String
  private let locate: @Sendable (String) -> URL?

  /// Reads the files from a bundle's resources, such as `Bundle.main` in the app.
  public init(bundle: Bundle, region: String = "fi") {
    self.region = region
    self.locate = { name in bundle.url(forResource: name, withExtension: nil) }
  }

  /// Reads the files from a folder, for example the synced folder in tests.
  public init(directory: URL, region: String = "fi") {
    self.region = region
    self.locate = { name in
      let url = directory.appending(path: name)
      return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
  }

  public var snapshotFileName: String { "pharmacies.\(region).json" }
  public var manifestFileName: String { "manifest.\(region).json" }
  public var placesFileName: String { "places.\(region).json" }

  public func loadSnapshot() throws -> PharmacySnapshot {
    try decode(PharmacySnapshot.self, from: snapshotFileName)
  }

  public func loadManifest() throws -> DataManifest {
    try decode(DataManifest.self, from: manifestFileName)
  }

  /// The place index, or nil when the data has none (the interim Overpass build).
  public func loadPlaceIndex() throws -> PlaceIndex? {
    guard locate(placesFileName) != nil else { return nil }
    return try decode(PlaceIndex.self, from: placesFileName)
  }

  /// The raw bytes of a bundled data file, for example to check its SHA-256 against the manifest.
  public func data(named name: String) throws -> Data {
    guard let url = locate(name) else { throw LoadError.missingFile(name) }
    return try Data(contentsOf: url)
  }

  private func decode<Value: Decodable>(_ type: Value.Type, from name: String) throws -> Value {
    try JSONDecoder().decode(type, from: data(named: name))
  }
}
