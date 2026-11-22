// Shapes of the bundled data files written by the web repository's `pnpm run data:import`. They
// mirror its `src/data/schema.ts`. Optional fields are omitted from the JSON when OpenStreetMap
// has no value; they are never null.

public struct PharmacyAddress: Hashable, Sendable, Codable {
  public var street: String?
  public var housenumber: String?
  public var postcode: String?
  public var city: String?
}

public struct Pharmacy: Hashable, Sendable, Codable, Identifiable, Rankable {
  /// Stable OSM ID: "node/123", "way/123" or "relation/123".
  public var id: String
  public var name: String?
  /// Point used for distance: the node, or the bounding-box centre of an area (ADR 0001).
  public var lat: Double
  public var lon: Double
  /// Interior point for the map pin of an area; absent for nodes (use `lat` and `lon`).
  public var pin: Coordinate?
  public var address: PharmacyAddress?
  public var openingHours: String?
  public var dispensing: String?
  public var phone: String?
  public var website: String?
  public var wheelchair: String?

  public var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
}

public struct PharmacySnapshot: Hashable, Sendable, Codable {
  public var schemaVersion: Int
  public var region: String
  public var pharmacies: [Pharmacy]
}

public enum PlaceType: String, Hashable, Sendable, Codable {
  case municipality, city, town, village
}

public struct Place: Hashable, Sendable, Codable, Identifiable {
  /// OSM ID of the place node, or of the boundary relation for a municipality.
  public var id: String
  public var name: String
  public var nameSv: String?
  public var type: PlaceType
  public var lat: Double
  public var lon: Double
  /// Name of the containing municipality (admin boundary); absent when not resolved.
  public var municipality: String?
}

public struct PlaceIndex: Hashable, Sendable, Codable {
  public var schemaVersion: Int
  public var region: String
  public var places: [Place]
}

/// `manifest.<region>.json`: source, checksums, counts, dropped duplicates and the review list.
public struct DataManifest: Hashable, Sendable, Codable {
  public struct Source: Hashable, Sendable, Codable {
    public var url: String
    public var filename: String
    public var sha256: String
    public var bytes: Int
    /// ISO 8601 UTC time of the OSM data; null when the source had none.
    public var dataTimestamp: String?
    public var replicationSequence: Int?
    public var query: String?
  }

  public struct Importer: Hashable, Sendable, Codable {
    public var script: String
    public var version: String
  }

  public struct Licence: Hashable, Sendable, Codable {
    public var name: String
    public var attribution: String
    public var url: String
    public var notice: String
  }

  public struct Ranking: Hashable, Sendable, Codable {
    public var formula: String
    public var earthRadiusMeters: Double
    public var tieBreak: String
    public var fixture: String
  }

  public struct File: Hashable, Sendable, Codable {
    public var path: String
    public var sha256: String
    public var bytes: Int
    public var records: Int?
  }

  public struct Files: Hashable, Sendable, Codable {
    public var pharmacies: File
    /// Absent (null) in the interim Overpass build, which has no place index.
    public var places: File?
    public var notice: File
  }

  public struct DroppedDuplicate: Hashable, Sendable, Codable {
    public var id: String
    public var keptId: String
    public var reason: String
    public var distanceMeters: Double?
  }

  public struct SameNamePair: Hashable, Sendable, Codable {
    public var name: String
    public var ids: [String]
    public var distanceMeters: Double
  }

  public var schemaVersion: Int
  public var region: String
  /// "osm-pbf" or "overpass-interim".
  public var kind: String
  public var interim: Bool
  public var notes: [String]
  public var source: Source
  public var generatedAt: String?
  public var generatedAtFrom: String
  public var importer: Importer
  public var licence: Licence
  public var regionFilter: [String: String]
  public var ranking: Ranking
  public var files: Files
  public var counts: [String: Int]
  public var droppedDuplicates: [DroppedDuplicate]
  public var sameNamePairs: [SameNamePair]
  public var outsideRegion: [String]
  public var warnings: [String]
}
