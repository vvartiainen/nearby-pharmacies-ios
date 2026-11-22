import Foundation
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

struct DistanceFormattingTests {
  @Test(
    "Formats kilometers with one decimal for the active locale",
    arguments: [
      (400.0, "en_GB", "0.4 km"),
      (400.0, "en_US", "0.4 km"),
      // English text with Finnish regional number conventions.
      (400.0, "en_FI", "0,4 km"),
      (400.0, "fi_FI", "0,4 km"),
      (1_234.0, "en_GB", "1.2 km"),
      (1_234.0, "fi_FI", "1,2 km"),
      (0.0, "fi_FI", "0,0 km"),
    ]
  )
  func formatsKilometers(meters: Double, localeIdentifier: String, expected: String) {
    let formatted = DistanceFormatting.kilometers(
      meters: meters, locale: Locale(identifier: localeIdentifier))
    #expect(normalizingSpaces(formatted) == expected)
  }
}

/// These tests read the compiled string catalog from the host app bundle.
struct LocalizedStringTests {
  @Test func englishStrings() {
    let localization = AppLocalization(preferredLanguages: ["en-GB"], region: .unitedKingdom)
    #expect(localization.language == .english)
    #expect(localization.heading == "Nearest pharmacy")
    #expect(localization.illustrativeNote == "Illustrative example distance")
    #expect(
      normalizingSpaces(localization.straightLineDistance(meters: 400)) == "0.4 km straight line")
  }

  @Test func finnishStrings() {
    let localization = AppLocalization(preferredLanguages: ["fi-FI"], region: .finland)
    #expect(localization.language == .finnish)
    #expect(localization.heading == "Lähin apteekki")
    #expect(localization.illustrativeNote == "Havainnollistava esimerkkietäisyys")
    #expect(
      normalizingSpaces(localization.straightLineDistance(meters: 400)) == "0,4 km linnuntietä")
  }

  @Test func unsupportedLanguageUsesEnglishStrings() {
    let localization = AppLocalization(preferredLanguages: ["sv-SE"], region: .sweden)
    #expect(localization.language == .english)
    #expect(localization.heading == "Nearest pharmacy")
  }
}

/// Formatters may use a no-break space between the number and the unit.
private func normalizingSpaces(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{00A0}", with: " ")
    .replacingOccurrences(of: "\u{202F}", with: " ")
}
