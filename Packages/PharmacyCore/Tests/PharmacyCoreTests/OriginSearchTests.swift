import Foundation
import Testing

@testable import PharmacyCore

private func english(_ code: String) -> String {
  Locale(identifier: "en").localizedString(forRegionCode: code) ?? code
}

@Suite struct GeocoderConfigTests {
  @Test func readsTheBundledNominatimConfiguration() throws {
    let data = Data(
      #"{"provider":"nominatim","endpoint":"https://nominatim.openstreetmap.org/search","countryCode":"FI"}"#
        .utf8)
    #expect(GeocoderConfig.decode(data) == .default)
  }

  @Test(arguments: [
    #"{"provider":"nominatim","endpoint":"http://nominatim.example/search","countryCode":"fi"}"#,
    #"{"provider":"geoapify","endpoint":"https://api.geoapify.com/v1/geocode/search","countryCode":"fi"}"#,
    #"{"provider":"photon","endpoint":"https://photon.example/api","countryCode":"fin"}"#,
    #"[]"#,
  ])
  func rejectsAnInvalidConfiguration(_ json: String) {
    #expect(GeocoderConfig.decode(Data(json.utf8)) == nil)
  }

  @Test func sendsOnlyTheTextLanguageAndRegion() throws {
    let url = GeocoderConfig.default.searchURL(query: "Kauppakatu 1", language: "fi")
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "nominatim.openstreetmap.org")
    let items = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(
      items == [
        "q": "Kauppakatu 1", "format": "jsonv2", "addressdetails": "1", "accept-language": "fi",
        "countrycodes": "fi", "limit": "5",
      ])
  }

  @Test func photonUsesItsOwnParameters() throws {
    let config = GeocoderConfig(
      provider: .photon, endpoint: URL(string: "https://photon.example/api")!, countryCode: "fi")
    let url = config.searchURL(query: "Tampere", language: "en")
    #expect(url.absoluteString.hasPrefix("https://photon.example/api?"))
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(items.first { $0.name == "countrycode" }?.value == "FI")
  }
}

@Suite struct GeocoderResponseTests {
  /// Five "Kauppakatu 1" buildings, as in the web journey test.
  static let kauppakatu = Data(
    """
    [
      {"lat":"61.49819","lon":"23.75937","address":{"road":"Kauppakatu","housenumber":"1","city":"Tampere","country":"Finland","country_code":"fi"}},
      {"lat":"60.98155","lon":"25.6648","address":{"road":"Kauppakatu","housenumber":"1","city":"Lahti","country":"Finland","country_code":"fi"}},
      {"lat":"62.89265","lon":"27.69587","address":{"road":"Kauppakatu","housenumber":"1","city":"Kuopio","country":"Finland","country_code":"fi"}},
      {"lat":"60.46609","lon":"26.94612","address":{"road":"Kauppakatu","housenumber":"1","city":"Kotka","country":"Finland","country_code":"fi"}},
      {"lat":"62.59518","lon":"29.75543","address":{"road":"Kauppakatu","housenumber":"1","city":"Joensuu","country":"Finland","country_code":"fi"}}
    ]
    """.utf8)

  @Test func labelsEachMatchWithStreetMunicipalityAndCountry() throws {
    let matches = try GeocoderConfig.default.matches(from: Self.kauppakatu, countryName: english)
    #expect(
      matches.map(\.label) == [
        "Kauppakatu 1 · Tampere, Finland", "Kauppakatu 1 · Lahti, Finland",
        "Kauppakatu 1 · Kuopio, Finland", "Kauppakatu 1 · Kotka, Finland",
        "Kauppakatu 1 · Joensuu, Finland",
      ])
    #expect(matches[0].title == "Kauppakatu 1")
    #expect(matches[0].context == "Tampere, Finland")
    #expect(matches[0].coordinate == Coordinate(lat: 61.49819, lon: 23.75937))
  }

  @Test func keepsNamedPlacesAndSkipsOtherCountriesAndDuplicates() throws {
    let data = Data(
      """
      [
        {"name":"Ylioppilaskylä","lat":"60.461","lon":"22.297","address":{"quarter":"Ylioppilaskylä","city":"Turku","country":"Finland","country_code":"fi"}},
        {"display_name":"Ylioppilastalo, Turku, Finland","lat":"60.455","lon":"22.288","address":{"city":"Turku","country_code":"fi"}},
        {"name":"Ylioppilastalo","lat":"60.455","lon":"22.288","address":{"city":"Turku","country":"Finland","country_code":"fi"}},
        {"name":"Haparanda","lat":"65.83","lon":"24.13","address":{"town":"Haparanda","country":"Sweden","country_code":"se"}},
        {"name":"Broken","lat":"x","lon":"24.13","address":{"city":"Oulu","country_code":"fi"}}
      ]
      """.utf8)
    let matches = try GeocoderConfig.default.matches(from: data, countryName: english)
    #expect(
      matches.map(\.label) == [
        "Ylioppilaskylä · Turku, Finland", "Ylioppilastalo · Turku, Finland",
      ])
  }

  @Test func readsPhotonFeatures() throws {
    let config = GeocoderConfig(
      provider: .photon, endpoint: URL(string: "https://photon.example/api")!, countryCode: "fi")
    let data = Data(
      """
      {"features":[{"geometry":{"type":"Point","coordinates":[23.75937,61.49819]},
        "properties":{"street":"Kauppakatu","housenumber":"1","city":"Tampere","country":"Finland","countrycode":"FI"}}]}
      """.utf8)
    let matches = try config.matches(from: data, countryName: english)
    #expect(matches.map(\.label) == ["Kauppakatu 1 · Tampere, Finland"])
  }

  @Test func anEmptyAnswerHasNoMatchesAndAnErrorPageThrows() throws {
    #expect(try GeocoderConfig.default.matches(from: Data("[]".utf8), countryName: english).isEmpty)
    #expect(throws: (any Error).self) {
      try GeocoderConfig.default.matches(from: Data("<html>".utf8), countryName: english)
    }
    #expect(throws: GeocoderResponseError.self) {
      try GeocoderConfig.default.matches(
        from: Data(#"{"error":"busy"}"#.utf8), countryName: english)
    }
  }
}

@Suite struct LocalPlacesTests {
  let places: [Place] = {
    do {
      return try #require(try SyncedFiles.loader.loadPlaceIndex()).places
    } catch {
      return []
    }
  }()

  @Test func matchesSwedishNamesWithATypo() {
    let matches = LocalPlaces.matches(for: "Tammerfor", in: places, country: "Finland")
    #expect(matches.first?.label == "Tampere · Finland")
    #expect(
      LocalPlaces.matches(for: "helsingfors", in: places, country: "Suomi").first?.label
        == "Helsinki · Suomi")
  }

  @Test func ignoresAccentsAndCase() {
    #expect(
      LocalPlaces.matches(for: "  HAMEENLINNA ", in: places, country: "Finland").first?.title
        == "Hämeenlinna")
  }

  @Test(arguments: ["Kauppakatu 1", "Tampere, Pirkanmaa", "", "   "])
  func leavesAddressesToTheGeocoder(_ query: String) {
    #expect(LocalPlaces.matches(for: query, in: places, country: "Finland").isEmpty)
  }

  @Test func returnsAtMostFiveDistinctMatches() {
    let matches = LocalPlaces.matches(for: "Kylä", in: places, country: "Finland")
    #expect(matches.count <= 5)
    #expect(Set(matches.map(\.label)).count == matches.count)
  }

  @Test func countsEditsLikeTheWebApp() {
    func distance(_ a: String, _ b: String) -> Int {
      LocalPlaces.editDistance(Array(a.unicodeScalars), Array(b.unicodeScalars))
    }
    #expect(distance("tammerfor", "tammerfors") == 1)
    #expect(distance("abo", "turku") == 5)
    #expect(distance("", "oulu") == 4)
  }
}

@Suite struct CoverageTests {
  let coverage: CoverageGeometry? = try? SyncedFiles.loader.loadCoverage()

  @Test func isBundledWithTheApp() throws {
    let coverage = try #require(coverage)
    #expect(!coverage.rings.isEmpty)
    #expect(!coverage.landBorders.isEmpty)
  }

  @Test func distinguishesAFinnishBorderTownFromTheSwedishSide() throws {
    let coverage = try #require(coverage)
    let tornio = Coordinate(lat: 65.8457589, lon: 24.1464)
    let haparanda = Coordinate(lat: 65.8281312, lon: 24.1308946)
    #expect(coverage.classify(tornio) == .border)
    #expect(coverage.classify(haparanda) == .outside)
  }

  @Test(arguments: [
    Coordinate(lat: 60.1720965, lon: 24.9412486),  // Helsinki Central
    Coordinate(lat: 59.8245, lon: 22.9687),  // Hanko, south coast
    Coordinate(lat: 60.0973, lon: 19.9348),  // Mariehamn, Åland
    Coordinate(lat: 61.4983, lon: 23.7732),  // Tampere
  ])
  func coversFinlandWithoutABorderNotice(_ point: Coordinate) throws {
    #expect(try #require(coverage).classify(point) == .covered)
  }

  @Test func treatsTallinnAsOutside() throws {
    #expect(try #require(coverage).classify(Coordinate(lat: 59.437, lon: 24.7536)) == .outside)
  }
}
