import Foundation

enum DistanceFormatting {
  /// Formats a distance in kilometers with one decimal place, using the given locale's number
  /// conventions, for example "0.4 km" in English and "0,4 km" in Finnish.
  static func kilometers(meters: Double, locale: Locale) -> String {
    Measurement(value: meters / 1_000, unit: UnitLength.kilometers)
      .formatted(
        .measurement(
          width: .abbreviated,
          usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(1))
        )
        .locale(locale)
      )
  }
}
