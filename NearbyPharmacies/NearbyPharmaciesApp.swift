import SwiftUI

@main
struct NearbyPharmaciesApp: App {
  private let localization: AppLocalization
  @State private var finder: PharmacyFinder

  init() {
    let localization = AppLocalization()
    self.localization = localization
    _finder = State(initialValue: PharmacyFinder(localization: localization))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(finder: finder)
        .environment(\.locale, localization.locale)
    }
  }
}
