import SwiftUI

struct ContentView: View {
  /// A fixed sample distance shown until ranking is wired to the UI. It matches the web app's
  /// sample: "1.7 km straight line", "1,7 km linnuntietä".
  static let illustrativeDistanceMeters = 1_700.0

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
