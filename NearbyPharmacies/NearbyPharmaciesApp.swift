import PharmacyCore
import SwiftUI

@main
struct NearbyPharmaciesApp: App {
  private let localization: AppLocalization
  @State private var controller: OriginController

  init() {
    let localization = AppLocalization()
    self.localization = localization
    let finder = PharmacyFinder(localization: localization)
    // UI tests launch with -UITesting and get scripted answers instead of the network and
    // Core Location.
    let scripted = ScriptedServices.isActive
    let places = (try? PharmacyDataLoader(bundle: .main).loadPlaceIndex())?.places ?? []
    _controller = State(
      initialValue: OriginController(
        finder: finder,
        geocoder: scripted ? ScriptedServices.geocoder() : NominatimGeocoder(),
        locator: scripted ? ScriptedServices.locator() : DeviceLocation(),
        places: places,
        defaults: scripted ? ScriptedServices.defaults() : .standard))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(controller: controller)
        .environment(\.locale, localization.locale)
    }
  }
}
