/// Something that can be ranked by distance: an `id` for exact ties and a point for distance.
public protocol Rankable {
  var id: String { get }
  var coordinate: Coordinate { get }
}

public struct RankedPharmacy<Item: Rankable> {
  public let pharmacy: Item
  /// Unrounded straight-line distance in metres. Round only for display.
  public let distanceMeters: Double
}

extension RankedPharmacy: Sendable where Item: Sendable {}

/// Plain UTF-16 code-unit order, the same as JavaScript's `<` on strings. Swift's `<` on `String`
/// compares Unicode scalars after canonical equivalence, which can differ, so ranking uses this.
public func idPrecedes(_ lhs: String, _ rhs: String) -> Bool {
  lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
}

/// Ranks pharmacies by unrounded haversine distance from the origin, then by `id` in UTF-16
/// code-unit order for exact ties. Returns every pharmacy, so the nearest available result is
/// present even far from any pharmacy.
public func rankPharmacies<Item: Rankable>(
  origin: Coordinate, pharmacies: some Sequence<Item>
) -> [RankedPharmacy<Item>] {
  pharmacies
    .map {
      RankedPharmacy(
        pharmacy: $0, distanceMeters: Haversine.distanceMeters(from: origin, to: $0.coordinate))
    }
    .sorted { lhs, rhs in
      if lhs.distanceMeters != rhs.distanceMeters {
        return lhs.distanceMeters < rhs.distanceMeters
      }
      return idPrecedes(lhs.pharmacy.id, rhs.pharmacy.id)
    }
}
