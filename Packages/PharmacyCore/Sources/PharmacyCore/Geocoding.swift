import Foundation

/// A place a search returned: "{title} · {context}", for example "Kauppakatu 1 · Tampere, Finland".
public struct PlaceMatch: Hashable, Sendable {
  public let coordinate: Coordinate
  /// A named feature, street address, area or municipality.
  public let title: String
  /// Neighbourhood, municipality and country, as available, without repeating the title.
  public let context: String

  public init(coordinate: Coordinate, title: String, contextParts: [String]) {
    self.coordinate = coordinate
    self.title = title
    var seen = Set<String>()
    self.context =
      contextParts
      .filter { !$0.isEmpty && $0 != title && seen.insert($0).inserted }
      .joined(separator: ", ")
  }

  public var label: String { context.isEmpty ? title : "\(title) · \(context)" }
}

public struct GeocoderConfig: Hashable, Sendable, Decodable {
  public enum Provider: String, Hashable, Sendable, Decodable {
    case nominatim
    case photon
  }

  public let provider: Provider
  public let endpoint: URL
  /// Lowercase ISO 3166-1 alpha-2 code of the region filter, for example "fi".
  public let countryCode: String

  public static let `default` = GeocoderConfig(
    provider: .nominatim, endpoint: URL(string: "https://nominatim.openstreetmap.org/search")!,
    countryCode: "fi")

  public init(provider: Provider, endpoint: URL, countryCode: String) {
    self.provider = provider
    self.endpoint = endpoint
    self.countryCode = countryCode.lowercased()
  }

  private enum CodingKeys: String, CodingKey {
    case provider, endpoint, countryCode
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let endpoint = try container.decode(URL.self, forKey: .endpoint)
    let countryCode = try container.decode(String.self, forKey: .countryCode)
    guard endpoint.scheme == "https", endpoint.host() != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .endpoint, in: container, debugDescription: "The endpoint must use HTTPS")
    }
    guard countryCode.count == 2, countryCode.allSatisfy({ $0.isASCII && $0.isLetter }) else {
      throw DecodingError.dataCorruptedError(
        forKey: .countryCode, in: container, debugDescription: "Expected a two-letter code")
    }
    self.init(
      provider: try container.decode(Provider.self, forKey: .provider), endpoint: endpoint,
      countryCode: countryCode)
  }

  /// Reads `geocoder.json`, or returns nil when it is invalid, like the web app.
  public static func decode(_ data: Data) -> GeocoderConfig? {
    try? JSONDecoder().decode(GeocoderConfig.self, from: data)
  }

  /// The search request for submitted text: five matches in the region, labelled in `language`.
  /// Only the text, the language and the region filter are sent, never a coordinate.
  public func searchURL(query: String, language: String) -> URL {
    let parameters: [(String, String)] =
      switch provider {
      case .nominatim:
        [
          ("q", query), ("format", "jsonv2"), ("addressdetails", "1"),
          ("accept-language", language), ("countrycodes", countryCode), ("limit", "5"),
        ]
      case .photon:
        [
          ("q", query), ("lang", language), ("limit", "5"),
          ("countrycode", countryCode.uppercased()),
        ]
      }
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems =
      (components.queryItems ?? []).filter { item in !parameters.contains { $0.0 == item.name } }
      + parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
    return components.url!
  }

  /// Up to five distinct matches in the configured country, in the provider's order.
  /// `countryName` names a region code when the response has no country, for example "Finland".
  /// Throws when the response is not a geocoder answer.
  public func matches(from data: Data, countryName: (String) -> String) throws -> [PlaceMatch] {
    let payload = try JSONSerialization.jsonObject(with: data)
    let entries: [Any]
    switch provider {
    case .nominatim:
      guard let array = payload as? [Any] else { throw GeocoderResponseError.invalid }
      entries = array
    case .photon:
      guard let features = (payload as? [String: Any])?["features"] as? [Any] else {
        throw GeocoderResponseError.invalid
      }
      entries = features
    }

    var matches: [PlaceMatch] = []
    var labels = Set<String>()
    for case let entry as [String: Any] in entries {
      let nominatim = provider == .nominatim
      let address = (nominatim ? entry["address"] : entry["properties"]) as? [String: Any] ?? [:]
      func field(_ keys: String...) -> String {
        keys.lazy.map { string(address[$0]) }.first { !$0.isEmpty } ?? ""
      }
      let code = field("country_code", "countrycode").lowercased()
      guard code == countryCode else { continue }

      let latitude: Double?
      let longitude: Double?
      if nominatim {
        latitude = number(entry["lat"])
        longitude = number(entry["lon"])
      } else {
        let coordinates = (entry["geometry"] as? [String: Any])?["coordinates"] as? [Any] ?? []
        longitude = coordinates.count == 2 ? number(coordinates[0]) : nil
        latitude = coordinates.count == 2 ? number(coordinates[1]) : nil
      }
      guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
        abs(latitude) <= 90, abs(longitude) <= 180
      else { continue }

      let road = field("road", "street")
      let houseNumber = field("housenumber", "house_number")
      let street =
        road.isEmpty ? "" : [road, houseNumber].filter { !$0.isEmpty }.joined(separator: " ")
      let municipality = field("city", "town", "municipality", "village")
      let area = field(
        "neighbourhood", "quarter", "suburb", "city_district", "district", "hamlet", "village")
      let name = string(nominatim ? entry["name"] : address["name"])
      let featureName = [road, street, municipality].contains(name) ? "" : name
      let displayName =
        string(entry["display_name"]).split(separator: ",", maxSplits: 1).first
        .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
      guard
        let title = [featureName, street, area, displayName, municipality].first(where: {
          !$0.isEmpty
        })
      else { continue }
      let country = field("country")
      let match = PlaceMatch(
        coordinate: Coordinate(lat: latitude, lon: longitude), title: title,
        contextParts: [
          street, area, municipality, country.isEmpty ? countryName(code.uppercased()) : country,
        ])
      if labels.insert(match.label).inserted { matches.append(match) }
      if matches.count == 5 { break }
    }
    return matches
  }
}

public enum GeocoderResponseError: Error {
  case invalid
}

private func string(_ value: Any?) -> String {
  (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func number(_ value: Any?) -> Double? {
  if let string = value as? String {
    let trimmed = string.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : Double(trimmed)
  }
  if value is Bool { return nil }
  return (value as? NSNumber)?.doubleValue
}
