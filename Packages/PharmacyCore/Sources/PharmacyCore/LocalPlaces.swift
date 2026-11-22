import Foundation

/// City search in the bundled place index, used when the online geocoder fails or finds nothing.
/// It matches Finnish and Swedish names with a small typo tolerance, as the web app does.
public enum LocalPlaces {
  /// Up to five places whose name or Swedish name is within the tolerance of `query`, closest
  /// first and municipalities before villages of the same name. `country` ends each context, for
  /// example "Finland" or "Suomi". A query with a digit or comma is an address, so it matches
  /// nothing.
  public static func matches(for query: String, in places: [Place], country: String)
    -> [PlaceMatch]
  {
    let normalized = normalize(query)
    guard !normalized.isEmpty, normalized.count <= 60,
      !normalized.contains(where: { $0.isNumber || $0 == "," })
    else { return [] }
    let target = Array(normalized.unicodeScalars)
    let tolerance = target.count >= 8 ? 2 : target.count >= 5 ? 1 : 0

    var scored: [(place: Place, score: Int, order: Int)] = []
    for (order, place) in places.enumerated() {
      let score =
        [place.name, place.nameSv].compactMap { $0 }
        .map { name -> Int in
          let candidate = Array(normalize(name).unicodeScalars)
          return abs(candidate.count - target.count) > tolerance
            ? .max : editDistance(target, candidate)
        }
        .min() ?? .max
      if score <= tolerance { scored.append((place, score, order)) }
    }
    scored.sort { a, b in
      if a.score != b.score { return a.score < b.score }
      let aMunicipality = a.place.type == .municipality
      let bMunicipality = b.place.type == .municipality
      if aMunicipality != bMunicipality { return aMunicipality }
      return a.order < b.order
    }

    var matches: [PlaceMatch] = []
    var labels = Set<String>()
    for (place, _, _) in scored {
      let match = PlaceMatch(
        coordinate: Coordinate(lat: place.lat, lon: place.lon), title: place.name,
        contextParts: [place.municipality ?? "", country])
      if labels.insert(match.label).inserted { matches.append(match) }
      if matches.count == 5 { break }
    }
    return matches
  }

  /// Lowercase, without accents, with single spaces: "Hämeenlinna" becomes "hameenlinna".
  static func normalize(_ value: String) -> String {
    let scalars = value.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.filter {
      switch $0.properties.generalCategory {
      case .nonspacingMark, .spacingMark, .enclosingMark: false
      default: true
      }
    }
    return String(String.UnicodeScalarView(scalars))
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  static func editDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
    var previous = Array(0...b.count)
    for i in a.indices {
      var row = [i + 1]
      for j in b.indices {
        row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (a[i] == b[j] ? 0 : 1)))
      }
      previous = row
    }
    return previous[b.count]
  }
}
