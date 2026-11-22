import Foundation

/// The bundled OSM street address index: regional shards that label a device fix or a point
/// chosen on the map with the nearest mapped address. The same files and rules as the web app's
/// `findNearbyAddress`, so both platforms show the same "Near …" label. Everything runs on the
/// device; no coordinates leave it.
public enum AddressIndex {
  /// Shard coordinates are integers in units of 1/100 000 degree.
  public static let coordinateScale = 100_000.0
  /// Addresses farther than this are not "near", and fixes less accurate than this get none.
  public static let radiusMeters = 120.0

  public struct Address: Hashable, Sendable {
    /// Street or place name and house number, for example "Rautatienkatu 25".
    public let street: String
    /// Municipality, possibly empty.
    public let city: String

    public init(street: String, city: String) {
      self.street = street
      self.city = city
    }
  }

  /// One shard: names referenced by index, and points sorted by latitude.
  public struct Shard: Decodable, Sendable {
    public let streets: [String]
    public let cities: [String]
    let points: [Point]

    struct Point: Decodable, Sendable {
      let lat: Int
      let lon: Int
      let street: Int
      let number: String
      let city: Int

      /// A point is the array `[lat, lon, street, number, city]`.
      init(from decoder: any Decoder) throws {
        var values = try decoder.unkeyedContainer()
        lat = try values.decode(Int.self)
        lon = try values.decode(Int.self)
        street = try values.decode(Int.self)
        number = try values.decode(String.self)
        city = try values.decode(Int.self)
      }
    }
  }

  public enum DecodingError: Error {
    case invalidGzip
  }

  /// The shard name for a point: half a degree of latitude by one degree of longitude, for
  /// example "122-23" for Tampere.
  public static func cell(lat: Double, lon: Double) -> String {
    "\(Int((lat * 2).rounded(.down)))-\(Int(lon.rounded(.down)))"
  }

  /// The shards that can hold an address within `radiusMeters` of `point`.
  public static func cells(near point: Coordinate) -> Set<String> {
    let radiusDegrees = radiusMeters / Haversine.earthMeanRadiusMeters * (180 / .pi)
    let longitudeRadius = radiusDegrees / cos(point.lat * .pi / 180)
    var cells = Set<String>()
    for lat in [point.lat - radiusDegrees, point.lat + radiusDegrees] {
      for lon in [point.lon - longitudeRadius, point.lon + longitudeRadius] {
        cells.insert(cell(lat: lat, lon: lon))
      }
    }
    return cells
  }

  /// Whether a fix with this uncertainty, in metres, can be labelled. A chosen point has 0.
  public static func accepts(accuracy: Double) -> Bool {
    accuracy.isFinite && accuracy >= 0 && accuracy <= radiusMeters
  }

  /// The closest address within `radiusMeters` of `point`, skipping addresses that `isOutside`
  /// rejects (outside the bundled coverage).
  public static func nearest(
    to point: Coordinate, in shards: [Shard], isOutside: (Coordinate) -> Bool = { _ in false }
  ) -> Address? {
    // Check latitude first to avoid measuring every address in the shard.
    let latitudeWindow =
      radiusMeters / Haversine.earthMeanRadiusMeters * (180 / .pi) * coordinateScale
    let originLatitude = point.lat * coordinateScale
    var closest = radiusMeters
    var address: Address?
    for shard in shards {
      for entry in shard.points {
        let lat = Double(entry.lat)
        if lat < originLatitude - latitudeWindow { continue }
        if lat > originLatitude + latitudeWindow { break }
        let candidate = Coordinate(
          lat: lat / coordinateScale, lon: Double(entry.lon) / coordinateScale)
        let distance = Haversine.distanceMeters(from: point, to: candidate)
        if distance > closest || isOutside(candidate) { continue }
        guard shard.streets.indices.contains(entry.street) else { continue }
        closest = distance
        address = Address(
          street: "\(shard.streets[entry.street]) \(entry.number)",
          city: shard.cities.indices.contains(entry.city) ? shard.cities[entry.city] : "")
      }
    }
    return address
  }

  /// Decodes a shard file, gzip-compressed (`.json.gz`) or plain JSON.
  public static func decodeShard(_ data: Data) throws -> Shard {
    try JSONDecoder().decode(Shard.self, from: isGzip(data) ? gunzip(data) : data)
  }

  private static func isGzip(_ data: Data) -> Bool {
    data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
  }

  /// Strips the gzip header and trailer (RFC 1952) and inflates the raw deflate stream.
  private static func gunzip(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    guard bytes.count >= 18, bytes[2] == 8 else { throw DecodingError.invalidGzip }
    let flags = bytes[3]
    var offset = 10
    if flags & 0x04 != 0 {
      guard offset + 2 <= bytes.count else { throw DecodingError.invalidGzip }
      offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
    }
    for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {
      // A zero-terminated file name or comment.
      while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
      offset += 1
    }
    if flags & 0x02 != 0 { offset += 2 }
    guard offset <= bytes.count - 8 else { throw DecodingError.invalidGzip }
    let deflated = Data(bytes[offset..<(bytes.count - 8)])
    // Apple's zlib algorithm is the raw deflate format.
    return try (deflated as NSData).decompressed(using: .zlib) as Data
  }
}
