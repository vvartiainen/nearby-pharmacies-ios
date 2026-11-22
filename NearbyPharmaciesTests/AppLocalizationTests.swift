import Foundation
import PharmacyCore
import Testing

@testable import NearbyPharmacies

struct LanguageSelectionTests {
  @Test(
    "Follows the first supported preferred language",
    arguments: [
      (["fi-FI"], AppLocalization.Language.finnish),
      (["fi"], .finnish),
      (["en-GB"], .english),
      (["sv-FI", "fi-FI", "en-US"], .finnish),
      (["en-US", "fi-FI"], .english),
    ]
  )
  func selectsPreferredSupportedLanguage(
    preferred: [String], expected: AppLocalization.Language
  ) {
    #expect(AppLocalization.resolveLanguage(preferredLanguages: preferred) == expected)
  }

  @Test(
    "Falls back to English when no preferred language is supported",
    arguments: [[], ["sv-SE"], ["de-DE", "ja-JP"], ["not a language"]]
  )
  func fallsBackToEnglish(preferred: [String]) {
    #expect(AppLocalization.resolveLanguage(preferredLanguages: preferred) == .english)
  }

  @Test func combinesLanguageWithDeviceRegion() {
    let finnish = AppLocalization.makeLocale(language: .finnish, region: .finland)
    #expect(finnish.language.languageCode == .finnish)
    #expect(finnish.region == .finland)

    let english = AppLocalization.makeLocale(language: .english, region: .finland)
    #expect(english.language.languageCode == .english)
    #expect(english.region == .finland)

    let noRegion = AppLocalization.makeLocale(language: .english, region: nil)
    #expect(noRegion.region == nil)
  }
}

/// The rounding rule itself is tested in PharmacyCore (`swift test --package-path
/// Packages/PharmacyCore`). These cases check the locale the app passes to it.
struct DistanceFormattingTests {
  @Test(
    "Formats distances for the active locale",
    arguments: [
      (1_700.0, "en_GB", "1.7 km"),
      (1_700.0, "en_US", "1.7 km"),
      // English text with Finnish regional number conventions.
      (1_700.0, "en_FI", "1,7 km"),
      (1_700.0, "fi_FI", "1,7 km"),
      (295.96, "fi_FI", "300 m"),
      (1_234_000.0, "fi_FI", "1 234 km"),
      (0.0, "fi_FI", "0 m"),
    ]
  )
  func formatsDistance(meters: Double, localeIdentifier: String, expected: String) {
    let formatted = DistanceFormatting.distance(
      meters: meters, locale: Locale(identifier: localeIdentifier))
    #expect(normalizingSpaces(formatted) == expected)
  }
}

/// These tests read the compiled string catalog from the host app bundle.
struct LocalizedStringTests {
  @Test func englishStrings() {
    let localization = AppLocalization(preferredLanguages: ["en-GB"], region: .unitedKingdom)
    #expect(localization.language == .english)
    #expect(localization.resultsTitle == "Nearest pharmacies")
    #expect(localization.defaultOrigin == "Helsinki Central Railway Station (default)")
    #expect(localization.scopeAndCount(784) == "Mapped pharmacies in Finland · 784")
    #expect(localization.weekdays == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    #expect(localization.weeklyHoursHeading == "Usual weekly hours")
    #expect(localization.holidayHoursNote == "Holiday hours may differ.")
    #expect(localization.hoursUnavailable == "Hours unavailable")
    #expect(localization.addressUnavailable == "Address unavailable")
    #expect(
      normalizingSpaces(localization.straightLineDistance(meters: 1_700)) == "1.7 km straight line")
  }

  @Test func finnishStrings() {
    let localization = AppLocalization(preferredLanguages: ["fi-FI"], region: .finland)
    #expect(localization.language == .finnish)
    #expect(localization.resultsTitle == "Lähimmät apteekit")
    #expect(localization.defaultOrigin == "Helsingin päärautatieasema (oletus)")
    #expect(
      normalizingSpaces(localization.scopeAndCount(1_234))
        == "Kartoitetut apteekit Suomessa · 1 234")
    #expect(localization.weekdays == ["ma", "ti", "ke", "to", "pe", "la", "su"])
    #expect(localization.weeklyHoursHeading == "Tavalliset aukioloajat")
    #expect(localization.holidayHoursNote == "Pyhinä aukioloajat voivat poiketa.")
    #expect(localization.hoursUnavailable == "Aukioloajat eivät saatavilla")
    #expect(localization.addressUnavailable == "Osoite ei saatavilla")
    #expect(
      normalizingSpaces(localization.straightLineDistance(meters: 1_700)) == "1,7 km linnuntietä")
  }

  @Test func unsupportedLanguageUsesEnglishStrings() {
    let localization = AppLocalization(preferredLanguages: ["sv-SE"], region: .sweden)
    #expect(localization.language == .english)
    #expect(localization.resultsTitle == "Nearest pharmacies")
  }
}

/// Checks the string catalog's straight-line message against every label in the shared ranking
/// fixture, which `pnpm run data:sync-ios` copies into `Fixtures/` of this test bundle.
struct FixtureLabelTests {
  private struct Fixture: Decodable {
    struct Origin: Decodable {
      struct Expected: Decodable {
        struct Label: Decodable {
          let en: String
          let fi: String
        }
        let id: String
        let distanceMeters: Double
        let label: Label
      }
      let expected: [Expected]
    }
    let origins: [Origin]
  }

  @Test func catalogLabelsMatchTheFixture() throws {
    let url = try #require(
      Bundle(for: TestBundleToken.self).url(forResource: "ranking-v1", withExtension: "json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    let english = AppLocalization(preferredLanguages: ["en"], region: nil)
    let finnish = AppLocalization(preferredLanguages: ["fi"], region: nil)
    for result in fixture.origins.flatMap(\.expected) {
      #expect(
        normalizingSpaces(english.straightLineDistance(meters: result.distanceMeters))
          == result.label.en, "\(result.id)")
      #expect(
        normalizingSpaces(finnish.straightLineDistance(meters: result.distanceMeters))
          == result.label.fi, "\(result.id)")
    }
  }
}

/// The app bundle carries the synced data from `NearbyPharmacies/Resources/Data`.
struct BundledDataTests {
  @Test func appBundleHasTheSyncedData() throws {
    let loader = PharmacyDataLoader(bundle: .main)
    let manifest = try loader.loadManifest()
    #expect(try loader.loadSnapshot().pharmacies.count == manifest.counts["pharmacies"])
    if manifest.files.places != nil {
      #expect(try loader.loadPlaceIndex()?.places.count == manifest.counts["places"])
    }
    #expect(Bundle.main.url(forResource: "ODbL-NOTICE", withExtension: "txt") != nil)
  }
}

private final class TestBundleToken {}

/// Formatters may use a no-break space between the number and the unit.
private func normalizingSpaces(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{00A0}", with: " ")
    .replacingOccurrences(of: "\u{202F}", with: " ")
}
