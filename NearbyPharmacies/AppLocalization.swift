import Foundation
import PharmacyCore

/// The language and locale the app uses for its interface and formatting.
///
/// The app supports English and Finnish. It follows the first preferred language it supports and
/// falls back to English. Strings are read from that language's bundle and numbers are formatted
/// with a locale that combines that language with the device region.
struct AppLocalization: Sendable {
  enum Language: String, CaseIterable, Sendable {
    case english = "en"
    case finnish = "fi"

    static let fallback = Language.english
  }

  let language: Language
  let locale: Locale
  let bundle: Bundle

  init(
    preferredLanguages: [String] = Locale.preferredLanguages,
    region: Locale.Region? = Locale.current.region,
    baseBundle: Bundle = .main
  ) {
    let language = Self.resolveLanguage(preferredLanguages: preferredLanguages)
    self.language = language
    self.locale = Self.makeLocale(language: language, region: region)
    self.bundle =
      baseBundle.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
      ?? baseBundle
  }

  /// Returns the first preferred language the app supports, or English.
  static func resolveLanguage(preferredLanguages: [String]) -> Language {
    for identifier in preferredLanguages {
      guard let code = Locale.Language(identifier: identifier).languageCode?.identifier else {
        continue
      }
      if let language = Language(rawValue: code) {
        return language
      }
    }
    return .fallback
  }

  /// Combines the interface language with the device region, for example `fi_FI` or `en_FI`.
  static func makeLocale(language: Language, region: Locale.Region?) -> Locale {
    var components = Locale.Components(languageCode: Locale.LanguageCode(language.rawValue))
    components.region = region
    return Locale(components: components)
  }

  var heading: String {
    String(localized: "Nearest pharmacy", bundle: bundle, locale: locale)
  }

  var illustrativeNote: String {
    String(localized: "Illustrative example distance", bundle: bundle, locale: locale)
  }

  /// A labeled straight-line distance, for example "1.7 km straight line". The distance is
  /// rounded for display by `DistanceFormatting` from PharmacyCore, the same rule as the web app.
  func straightLineDistance(meters: Double) -> String {
    let distance = DistanceFormatting.distance(meters: meters, locale: locale)
    return String(localized: "\(distance) straight line", bundle: bundle, locale: locale)
  }
}
