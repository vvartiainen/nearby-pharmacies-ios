import Foundation
import PharmacyCore
import Testing

struct DistanceFormattingTests {
  @Test("Formats every fixture display case", arguments: fixture.displayCases)
  func displayCase(_ displayCase: RankingFixture.DisplayCase) {
    let en = DistanceFormatting.distance(
      meters: displayCase.meters, locale: Locale(identifier: "en"))
    let fi = DistanceFormatting.distance(
      meters: displayCase.meters, locale: Locale(identifier: "fi"))
    #expect(normalizingSpaces(en) == displayCase.en)
    #expect(normalizingSpaces(fi) == displayCase.fi)
  }

  @Test func coversAllFixtureDisplayCases() {
    #expect(fixture.displayCases.count == 19)
  }

  /// The exact characters, before the fixture's space normalization. They match the web app's
  /// `Intl.NumberFormat` output: Finnish groups with U+00A0, and both languages put U+0020
  /// between the number and the unit.
  @Test(
    "Uses the same characters as the web app's Intl output",
    arguments: [
      (1_234_000.0, "en", "1,234 km"),
      (1_234_000.0, "fi", "1\u{00A0}234 km"),
      (1_700.0, "en", "1.7 km"),
      (1_700.0, "fi", "1,7 km"),
      (50.4, "fi", "50 m"),
    ]
  )
  func exactCharacters(meters: Double, language: String, expected: String) {
    let formatted = DistanceFormatting.distance(
      meters: meters, locale: Locale(identifier: language))
    #expect(Array(formatted.unicodeScalars) == Array(expected.unicodeScalars))
  }

  @Test(
    "Follows the locale's number conventions, including language and region combinations",
    arguments: [
      ("en_GB", "1.7 km"),
      ("en_FI", "1,7 km"),
      ("fi_FI", "1,7 km"),
    ]
  )
  func localeConventions(identifier: String, expected: String) {
    let formatted = DistanceFormatting.distance(
      meters: 1_700, locale: Locale(identifier: identifier))
    #expect(normalizingSpaces(formatted) == expected)
  }

  @Test func sampleDistanceLabels() {
    #expect(straightLineLabel(meters: 1_700, language: "en") == "1.7 km straight line")
    #expect(straightLineLabel(meters: 1_700, language: "fi") == "1,7 km linnuntietä")
  }
}
