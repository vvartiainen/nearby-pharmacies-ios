import Foundation
import PharmacyCore
import Testing

/// The files `pnpm run data:sync-ios` copies into this repository, read in place so the package
/// keeps no second copy. `data:verify` in the web repository checks these same paths.
enum SyncedFiles {
  /// The iOS repository root: this file is `Packages/PharmacyCore/Tests/PharmacyCoreTests/…`.
  static let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()  // PharmacyCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // PharmacyCore
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()

  static let dataDirectory = repositoryRoot.appending(path: "NearbyPharmacies/Resources/Data")
  static let fixtureURL = repositoryRoot.appending(
    path: "NearbyPharmaciesTests/Fixtures/ranking-v1.json")

  static let loader = PharmacyDataLoader(directory: dataDirectory)

  static func loadFixture() throws -> RankingFixture {
    try JSONDecoder().decode(RankingFixture.self, from: Data(contentsOf: fixtureURL))
  }
}

/// `ranking-v1.json`, the ranking contract shared with the web app.
struct RankingFixture: Decodable, Sendable {
  struct Contract: Decodable, Sendable {
    let earthRadiusMeters: Double
  }

  struct Labels: Decodable, Sendable {
    let en: String
    let fi: String
  }

  struct ExpectedResult: Decodable, Sendable {
    let id: String
    let distanceMeters: Double
    let label: Labels
  }

  struct Origin: Decodable, Sendable, CustomTestStringConvertible {
    let id: String
    let lat: Double
    let lon: Double
    let expected: [ExpectedResult]

    var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    var testDescription: String { id }
  }

  struct DisplayCase: Decodable, Sendable, CustomTestStringConvertible {
    let meters: Double
    let en: String
    let fi: String

    var testDescription: String { "\(meters) m" }
  }

  let schemaVersion: Int
  let contract: Contract
  let distanceToleranceMeters: Double
  /// Decoded with the app's own model, so extra fixture keys such as `note` are ignored.
  let pharmacies: [Pharmacy]
  let origins: [Origin]
  let displayCases: [DisplayCase]
}

/// The fixture's `labelComparison` rule: formatters differ in which space they use, so U+00A0 and
/// U+202F become U+0020 before comparing.
func normalizingSpaces(_ text: String) -> String {
  String(
    String.UnicodeScalarView(
      text.unicodeScalars.map { $0 == "\u{00A0}" || $0 == "\u{202F}" ? " " : $0 }))
}

/// The fixture's row label messages: en "{distance} straight line", fi "{distance} linnuntietä".
/// The app reads the same messages from its string catalog.
func straightLineLabel(meters: Double, language: String) -> String {
  let distance = DistanceFormatting.distance(meters: meters, locale: Locale(identifier: language))
  return language == "fi" ? "\(distance) linnuntietä" : "\(distance) straight line"
}

/// Fixture values are known at compile time only as file contents, so parameterized tests load
/// them eagerly here. A load failure fails every test that uses them.
let fixture: RankingFixture = {
  do {
    return try SyncedFiles.loadFixture()
  } catch {
    fatalError(
      "Cannot read \(SyncedFiles.fixtureURL.path): \(error). Run pnpm run data:sync-ios in the web repo."
    )
  }
}()
