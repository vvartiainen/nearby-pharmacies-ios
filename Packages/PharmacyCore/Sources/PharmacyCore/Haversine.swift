import Foundation

/// A latitude and longitude in degrees (WGS 84).
public struct Coordinate: Hashable, Sendable, Codable {
  public var lat: Double
  public var lon: Double

  public init(lat: Double, lon: Double) {
    self.lat = lat
    self.lon = lon
  }
}

public enum Haversine {
  /// Mean Earth radius in metres (IUGG mean radius R1 = 6371.0088 km). This is the only place the
  /// iOS code defines it. The web app and the shared ranking fixture use the same value.
  public static let earthMeanRadiusMeters = 6_371_008.8

  /// Great-circle distance in metres with the haversine formula on a sphere of the mean radius.
  /// The operations follow the web app's `haversineMeters` so both give the same result.
  public static func distanceMeters(from: Coordinate, to: Coordinate) -> Double {
    let phi1 = radians(from.lat)
    let phi2 = radians(to.lat)
    let dPhi = radians(to.lat - from.lat)
    let dLambda = radians(to.lon - from.lon)
    let sinHalfDPhi = sin(dPhi / 2)
    let sinHalfDLambda = sin(dLambda / 2)
    let h = sinHalfDPhi * sinHalfDPhi + cos(phi1) * cos(phi2) * sinHalfDLambda * sinHalfDLambda
    return 2 * earthMeanRadiusMeters * asin(min(1, h.squareRoot()))
  }

  private static func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
  }
}
