import SwiftUI

@main
struct NearbyPharmaciesApp: App {
  private let localization = AppLocalization()

  var body: some Scene {
    WindowGroup {
      ContentView(localization: localization)
        .environment(\.locale, localization.locale)
    }
  }
}
