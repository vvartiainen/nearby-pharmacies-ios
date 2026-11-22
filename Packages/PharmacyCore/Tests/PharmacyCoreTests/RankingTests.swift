import Foundation
import PharmacyCore
import Testing

struct RankingFixtureTests {
  @Test func usesTheFixtureEarthRadius() {
    #expect(fixture.schemaVersion == 1)
    #expect(Haversine.earthMeanRadiusMeters == fixture.contract.earthRadiusMeters)
  }

  @Test("Ranks every fixture pharmacy in the expected order", arguments: fixture.origins)
  func expectedOrder(origin: RankingFixture.Origin) {
    let ranked = rankPharmacies(origin: origin.coordinate, pharmacies: fixture.pharmacies)
    #expect(ranked.map(\.pharmacy.id) == origin.expected.map(\.id))
  }

  @Test("Matches the expected distances within the tolerance", arguments: fixture.origins)
  func expectedDistances(origin: RankingFixture.Origin) throws {
    let ranked = rankPharmacies(origin: origin.coordinate, pharmacies: fixture.pharmacies)
    try #require(ranked.count == origin.expected.count)
    for (result, expected) in zip(ranked, origin.expected) {
      #expect(
        abs(result.distanceMeters - expected.distanceMeters) <= fixture.distanceToleranceMeters,
        "\(expected.id): \(result.distanceMeters) m, expected \(expected.distanceMeters) m")
    }
  }

  @Test("Formats the expected en and fi row labels", arguments: fixture.origins)
  func expectedLabels(origin: RankingFixture.Origin) {
    let ranked = rankPharmacies(origin: origin.coordinate, pharmacies: fixture.pharmacies)
    for (result, expected) in zip(ranked, origin.expected) {
      let en = straightLineLabel(meters: result.distanceMeters, language: "en")
      let fi = straightLineLabel(meters: result.distanceMeters, language: "fi")
      #expect(normalizingSpaces(en) == expected.label.en, "\(expected.id)")
      #expect(normalizingSpaces(fi) == expected.label.fi, "\(expected.id)")
    }
  }
}

struct RankingEdgeCaseTests {
  private func rank(from originID: String) throws -> [RankedPharmacy<Pharmacy>] {
    let origin = try #require(fixture.origins.first { $0.id == originID })
    return rankPharmacies(origin: origin.coordinate, pharmacies: fixture.pharmacies)
  }

  @Test func zeroDistanceComesFirst() throws {
    let first = try #require(try rank(from: "synthetic-tie").first)
    #expect(first.pharmacy.id == "node/7")
    #expect(first.distanceMeters == 0)
    #expect(straightLineLabel(meters: first.distanceMeters, language: "en") == "0 m straight line")
    #expect(straightLineLabel(meters: first.distanceMeters, language: "fi") == "0 m linnuntietä")
  }

  @Test func exactThreeWayTieSortsByUTF16CodeUnits() throws {
    let tied = try rank(from: "synthetic-tie").filter {
      ["node/10", "node/9", "way/3"].contains($0.pharmacy.id)
    }
    #expect(tied.map(\.pharmacy.id) == ["node/10", "node/9", "way/3"])
    let distances = Set(tied.map(\.distanceMeters))
    #expect(distances.count == 1, "The three distances must be exactly equal: \(distances)")
  }

  @Test func tieOrderDoesNotDependOnInputOrder() throws {
    let origin = Coordinate(lat: 61, lon: 25)
    let ids = rankPharmacies(origin: origin, pharmacies: fixture.pharmacies.reversed())
      .map(\.pharmacy.id)
    let expected = try #require(fixture.origins.first { $0.id == "synthetic-tie" })
    #expect(ids == expected.expected.map(\.id))
  }

  @Test func differentDistancesWithTheSameLabelKeepDistanceOrder() throws {
    let ranked = try rank(from: "helsinki-central")
    let yliopiston = try #require(ranked.firstIndex { $0.pharmacy.id == "node/1369465698" })
    let kluuvin = try #require(ranked.firstIndex { $0.pharmacy.id == "node/4727972444" })
    #expect(yliopiston + 1 == kluuvin)
    #expect(ranked[yliopiston].distanceMeters < ranked[kluuvin].distanceMeters)
    for language in ["en", "fi"] {
      let labels = [yliopiston, kluuvin].map {
        straightLineLabel(meters: ranked[$0].distanceMeters, language: language)
      }
      #expect(labels[0] == labels[1])
    }
    #expect(
      straightLineLabel(meters: ranked[yliopiston].distanceMeters, language: "en")
        == "300 m straight line")
  }

  @Test func idOrderIsUTF16CodeUnitOrder() {
    #expect(idPrecedes("node/10", "node/9"))
    #expect(!idPrecedes("node/9", "node/10"))
    #expect(!idPrecedes("way/3", "way/3"))
    // U+FF61 is one code unit, 0xFF61. U+1F600 is the surrogate pair 0xD83D 0xDE00, so it sorts
    // first by code units although its scalar value is larger. Swift's String `<` disagrees.
    #expect(idPrecedes("\u{1F600}", "\u{FF61}"))
    #expect("\u{FF61}" < "\u{1F600}")
  }

  @Test func emptyInputGivesNoResults() {
    #expect(rankPharmacies(origin: Coordinate(lat: 60, lon: 25), pharmacies: [Pharmacy]()).isEmpty)
  }
}
