import SwiftUI

struct ContentView: View {
  /// A fixed sample distance shown until real pharmacy data is available.
  static let illustrativeDistanceMeters = 400.0

  let localization: AppLocalization

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(localization.heading)
        .font(.largeTitle.bold())
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("heading")

      Text(localization.illustrativeNote)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("illustrativeNote")

      Text(localization.straightLineDistance(meters: Self.illustrativeDistanceMeters))
        .font(.title2)
        .accessibilityIdentifier("distance")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding()
  }
}

#Preview("English") {
  ContentView(localization: AppLocalization(preferredLanguages: ["en"], region: .finland))
}

#Preview("Finnish") {
  ContentView(localization: AppLocalization(preferredLanguages: ["fi"], region: .finland))
}
