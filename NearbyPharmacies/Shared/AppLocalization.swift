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

  private func text(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: bundle, locale: locale)
  }

  var resultsTitle: String { text("Nearest pharmacies") }
  var originCaption: String { text("Starting point") }
  var defaultOrigin: String { text("Helsinki Central Railway Station (default)") }
  var addressUnavailable: String { text("Address unavailable") }
  var unnamedPharmacy: String { text("Unnamed pharmacy") }
  var hoursHeading: String { text("Opening hours") }
  var weeklyHoursHeading: String { text("Usual weekly hours") }
  var holidayHoursNote: String { text("Holiday hours may differ.") }
  var hoursUnavailable: String { text("Hours unavailable") }
  var closed: String { text("Closed") }
  var backToResults: String { text("Back to results") }
  var detailsLabel: String { text("Pharmacy details") }
  var mapLabel: String { text("Map of pharmacies") }
  var mapAttribution: String { text("© OpenStreetMap contributors") }

  var searchLabel: String { text("City or street address") }
  var searchButton: String { text("Search") }
  var searchPending: String { text("Searching…") }
  var searchPrivacy: String {
    text(
      "Online search sends text to a geocoding service. Enter a public place or address.")
  }
  var searchAttribution: String { text("Search © OpenStreetMap contributors") }
  var chooseMatch: String { text("Choose a match") }
  var localMatches: String { text("Matches from the bundled place index.") }
  var searchUnavailable: String {
    text(
      "Address search is unavailable right now. City search and choosing a point on the map still work."
    )
  }
  var useMyLocation: String { text("Use my location") }
  var locationPromptTitle: String { text("Show pharmacies nearest to you?") }
  var locationPromptBody: String {
    text("Your location is used only on this device to calculate distances.")
  }
  var locationPromptAccept: String { text("Use location") }
  var locationPromptDismiss: String { text("Not now") }
  var locationPending: String { text("Finding your location…") }
  var yourLocation: String { text("Your location") }
  var droppedPin: String { text("Dropped pin") }
  var chooseOnMap: String { text("Choose on map") }
  var searchFromHere: String { text("Search from here") }
  var cancelMapPick: String { text("Cancel") }
  var mapPickHint: String { text("Touch and hold the map to choose a starting point.") }
  var outsideFinland: String {
    text("This starting point is outside Finland. Only pharmacies in Finland are shown.")
  }
  var returnToHelsinki: String { text("Return to Helsinki") }
  var borderNotice: String { text("Pharmacies across the border may be nearer but are not shown.") }

  func noMatches(_ query: String) -> String {
    text(
      "No places in Finland match “\(query)”. Check the spelling or choose a point on the map.")
  }

  func locationFailure(_ failure: LocationFailure) -> String {
    switch failure {
    case .denied:
      text(
        "Location permission was denied. Search for a city or address, or choose a point on the map."
      )
    case .timeout:
      text("Finding your location took too long. Try again or choose a starting point.")
    case .unavailable:
      text("Location is unavailable. Search for a city or address, or choose a point on the map.")
    }
  }

  /// Short weekday names, Monday first: "Mon" … "Sun" or "ma" … "su".
  var weekdays: [String] {
    text("Mon Tue Wed Thu Fri Sat Sun").split(separator: " ").map(String.init)
  }

  /// "Mapped pharmacies in Finland · 784", with the count in the active locale's digits.
  func scopeAndCount(_ count: Int) -> String {
    let formatted = count.formatted(.number.locale(locale))
    return text("Mapped pharmacies in Finland · \(formatted)")
  }

  var clockStyle: OpeningHours.TimeRange.ClockStyle {
    language == .finnish ? .finnish : .english
  }

  func name(of pharmacy: Pharmacy) -> String {
    pharmacy.displayName ?? unnamedPharmacy
  }

  func distance(meters: Double) -> String {
    DistanceFormatting.distance(meters: meters, locale: locale)
  }

  func straightLineDistance(meters: Double) -> String {
    let distance = DistanceFormatting.distance(meters: meters, locale: locale)
    return String(localized: "\(distance) straight line", bundle: bundle, locale: locale)
  }
}
