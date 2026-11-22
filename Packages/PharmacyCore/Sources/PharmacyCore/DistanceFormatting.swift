import Foundation

/// Display rounding from the design spec ("Distance format"), the same as the web app's
/// `formatDistance`.
public enum DistanceFormatting {
  /// Formats an unrounded distance for display: under 1 km to the nearest 10 m, 1 km to under
  /// 10 km to the nearest 0.1 km, 10 km and over to the nearest 1 km. Rounding is half up on the
  /// unrounded distance. A value that rounds up to the next band's threshold is shown in that
  /// band, so 995 m shows "1.0 km" (never "1,000 m") and 9.95 km shows "10 km" (never
  /// "10.0 km"). Numbers use the locale's decimal and grouping separators, for example "1,234 km"
  /// in English and "1 234 km" in Finnish. Ordering never uses these rounded values.
  ///
  /// - Precondition: `meters` is finite and not negative.
  public static func distance(meters: Double, locale: Locale) -> String {
    precondition(meters.isFinite && meters >= 0, "Invalid distance: \(meters)")
    let roundedMeters = halfUp(meters / 10) * 10
    if roundedMeters < 1_000 {
      return format(roundedMeters, unit: .meters, fractionDigits: 0, locale: locale)
    }
    let tenths = halfUp(meters / 100) / 10
    if tenths < 10 {
      return format(tenths, unit: .kilometers, fractionDigits: 1, locale: locale)
    }
    return format(halfUp(meters / 1_000), unit: .kilometers, fractionDigits: 0, locale: locale)
  }

  /// The colour band of a result row's distance: near below 500 m, medium below 1 km, far from
  /// 1 km. It uses the distance rounded to 10 m, as displayed, so rows with the same label share a
  /// colour. The same rule as the web app's `distanceBand`.
  public enum Band: Sendable, Hashable {
    case near, medium, far
  }

  /// - Precondition: `meters` is finite and not negative.
  public static func band(meters: Double) -> Band {
    precondition(meters.isFinite && meters >= 0, "Invalid distance: \(meters)")
    let rounded = halfUp(meters / 10) * 10
    if rounded < 500 { return .near }
    if rounded < 1_000 { return .medium }
    return .far
  }

  /// Half up for the non-negative values used here, the same as JavaScript's `Math.round`.
  private static func halfUp(_ value: Double) -> Double {
    value.rounded(.toNearestOrAwayFromZero)
  }

  private static func format(
    _ value: Double, unit: UnitLength, fractionDigits: Int, locale: Locale
  ) -> String {
    Measurement(value: value, unit: unit)
      .formatted(
        .measurement(
          width: .abbreviated,
          usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
        )
        .locale(locale)
      )
  }
}
