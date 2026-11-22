import PharmacyCore

struct Origin: Hashable {
  enum Kind: Hashable {
    case `default`
    case device
    case pin
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
