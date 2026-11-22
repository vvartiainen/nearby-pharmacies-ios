import Foundation
import PharmacyCore

/// Deterministic geocoder and location for UI tests, chosen with launch environment variables.
/// A launch with `-UITesting` never contacts the geocoder or asks Core Location.
///
/// - `UITEST_GEOCODER`: `fixture` answers with `UITEST_GEOCODER_RESPONSE` (a Nominatim JSON
///   answer read by the real parser), `unavailable` fails. Unset also fails.
/// - `UITEST_GEOCODER_DELAY`: seconds before the geocoder answers.
/// - `UITEST_LOCATION`: `lat,lon` grants a fix accurate to 10 m (`lat,lon,accuracy` sets the
///   accuracy in metres), `denied`, `timeout` or `unavailable` fail. Unset fails as unavailable.
/// - `UITEST_LOCATION_DELAY`: seconds before the location answers.
/// - `UITEST_LOCATION_PROMPT=1`: permission is not determined yet, so the app offers location.
/// - `UITEST_ADDRESS_INDEX=none`: no street addresses, so a fix or a chosen point keeps its plain
///   label. By default the bundled index answers, as in the app.
enum ScriptedServices {
  static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-UITesting") }

  private static var environment: [String: String] { ProcessInfo.processInfo.environment }

  private static func delay(_ key: String) -> Duration {
    .milliseconds(Int((Double(environment[key] ?? "") ?? 0) * 1000))
  }

  /// Settings that start empty on every launch, so a test never sees an earlier dismissal.
  static func defaults() -> UserDefaults {
    let name = "UITesting"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  static func geocoder() -> any Geocoding {
    ScriptedGeocoder(
      response: environment["UITEST_GEOCODER"] == "fixture"
        ? environment["UITEST_GEOCODER_RESPONSE"].map { Data($0.utf8) } : nil,
      delay: delay("UITEST_GEOCODER_DELAY"))
  }

  static func addresses() -> AddressLookup {
    environment["UITEST_ADDRESS_INDEX"] == "none" ? AddressLookup(directory: nil) : .bundled
  }

  @MainActor
  static func locator() -> any LocationProviding {
    let script = environment["UITEST_LOCATION"] ?? "unavailable"
    let result: Result<LocationFix, LocationFailure>
    switch script {
    case "denied": result = .failure(.denied)
    case "timeout": result = .failure(.timeout)
    case "unavailable": result = .failure(.unavailable)
    default:
      let parts = script.split(separator: ",").compactMap { Double($0) }
      result =
        parts.count == 2 || parts.count == 3
        ? .success(
          LocationFix(
            Coordinate(lat: parts[0], lon: parts[1]), accuracy: parts.count == 3 ? parts[2] : 10))
        : .failure(.unavailable)
    }
    return ScriptedLocation(
      result: result, delay: delay("UITEST_LOCATION_DELAY"),
      needsPermission: environment["UITEST_LOCATION_PROMPT"] == "1")
  }
}

struct ScriptedGeocoder: Geocoding {
  let response: Data?
  let delay: Duration

  func search(_ query: String, language: String) async throws -> [PlaceMatch] {
    try await Task.sleep(for: delay)
    guard let response else { throw GeocodingError.unavailable }
    let names = Locale(identifier: language)
    return try GeocoderConfig.default.matches(from: response) {
      names.localizedString(forRegionCode: $0) ?? $0
    }
  }
}

@MainActor
final class ScriptedLocation: LocationProviding {
  let result: Result<LocationFix, LocationFailure>
  let delay: Duration
  let needsPermission: Bool

  init(result: Result<LocationFix, LocationFailure>, delay: Duration, needsPermission: Bool) {
    self.result = result
    self.delay = delay
    self.needsPermission = needsPermission
  }

  func currentLocation() async -> Result<LocationFix, LocationFailure> {
    try? await Task.sleep(for: delay)
    return result
  }

  // Keep delayed replies available to exercise the controller's stale-result guard.
  func cancelLocation() {}
}
