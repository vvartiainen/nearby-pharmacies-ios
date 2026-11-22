import Foundation

/// The simplified Finnish boundary and its land borders, `coverage.fi.json` from the web importer.
/// Coordinates are `[lon, lat]` pairs.
public struct CoverageGeometry: Hashable, Sendable, Decodable {
  public var rings: [[[Double]]]
  public var landBorders: [[[Double]]]

  public init(rings: [[[Double]]], landBorders: [[[Double]]]) {
    self.rings = rings
    self.landBorders = landBorders
  }

  public enum Classification: Hashable, Sendable {
    case covered
    /// Within about 5 km of a land border: pharmacies across it may be nearer.
    case border
    case outside
  }

  public func classify(_ point: Coordinate) -> Classification {
    var inside = false
    for ring in rings {
      for (a, b) in zip(ring, ring.dropFirst()) where a.count >= 2 && b.count >= 2 {
        let (lonA, latA, lonB, latB) = (a[0], a[1], b[0], b[1])
        if (latA > point.lat) == (latB > point.lat) { continue }
        let intersection = lonA + (lonB - lonA) * (point.lat - latA) / (latB - latA)
        if point.lon < intersection { inside.toggle() }
      }
    }
    guard inside else { return .outside }

    // An equirectangular projection centred on the point is enough for the 5 km notice.
    let radians = Double.pi / 180
    let scaleX = radians * Haversine.earthMeanRadiusMeters * cos(point.lat * radians)
    let scaleY = radians * Haversine.earthMeanRadiusMeters
    let limit = 5_000.0 * 5_000.0
    for line in landBorders {
      for (a, b) in zip(line, line.dropFirst()) where a.count >= 2 && b.count >= 2 {
        let ax = (a[0] - point.lon) * scaleX
        let ay = (a[1] - point.lat) * scaleY
        let dx = (b[0] - a[0]) * scaleX
        let dy = (b[1] - a[1]) * scaleY
        let lengthSquared = dx * dx + dy * dy
        let fraction =
          lengthSquared == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
        let x = ax + fraction * dx
        let y = ay + fraction * dy
        if x * x + y * y <= limit { return .border }
      }
    }
    return .covered
  }
}

extension PharmacyDataLoader {
  public var coverageFileName: String { "coverage.\(region).json" }

  /// The coverage geometry, or nil when the import wrote none (the interim Overpass build).
  public func loadCoverage() throws -> CoverageGeometry? {
    guard let data = try? data(named: coverageFileName) else { return nil }
    return try JSONDecoder().decode(CoverageGeometry.self, from: data)
  }
}
