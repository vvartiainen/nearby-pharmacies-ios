import CoreLocation
import Foundation
import PharmacyCore

/// Searches submitted text in an online geocoder (ADR 0002 in the web repo).
protocol Geocoding: Sendable {
  /// Up to five matches for `query`, labelled in `language`. Throws when the service is
  /// unavailable, rate-limited or answers with something other than matches.
  func search(_ query: String, language: String) async throws -> [PlaceMatch]
}

enum GeocodingError: Error {
  case rateLimited
  case unavailable
}

/// Public Nominatim, or the provider in `geocoder.json`. It follows the usage policy: one request
/// per submitted search, at most one in flight and one a second, no retries, and a cache for the
/// session. Requests carry only the search text, the language and the region filter.
actor NominatimGeocoder: Geocoding {
  /// Set to the project's public repository or demo URL once it is published, so the operators
  /// of the geocoder can identify the app from its User-Agent.
  static let contactURL: String? = nil
  /// A deployed `geocoder.json` that can switch the provider without an app update. The app falls
  /// back to its bundled copy, which is what it uses until a deployment URL is set.
  static let remoteConfigURL: URL? = nil

  private let session: URLSession
  private let bundledConfig: GeocoderConfig
  private var config: GeocoderConfig?
  private var cache: [String: [PlaceMatch]] = [:]
  private var cacheOrder: [String] = []
  private var inFlight = false
  private var lastRequest: ContinuousClock.Instant?

  init(bundle: Bundle = .main) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 6
    let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    configuration.httpAdditionalHeaders = [
      "User-Agent": ["NearbyPharmacies/\(version)", Self.contactURL.map { "(\($0))" }]
        .compactMap { $0 }.joined(separator: " ")
    ]
    session = URLSession(configuration: configuration)
    bundledConfig =
      bundle.url(forResource: "geocoder", withExtension: "json")
      .flatMap { try? Data(contentsOf: $0) }
      .flatMap(GeocoderConfig.decode) ?? .default
  }

  func search(_ query: String, language: String) async throws -> [PlaceMatch] {
    let config = await loadConfig()
    let key = "\(language):\(query.precomposedStringWithCanonicalMapping.lowercased())"
    if let cached = cache[key] { return cached }
    let now = ContinuousClock.now
    if inFlight || lastRequest.map({ now - $0 < .seconds(1) }) == true {
      throw GeocodingError.rateLimited
    }
    inFlight = true
    lastRequest = now
    defer { inFlight = false }

    var request = URLRequest(url: config.searchURL(query: query, language: language))
    request.httpShouldHandleCookies = false
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw GeocodingError.unavailable
    }
    let names = Locale(identifier: language)
    let matches = try config.matches(from: data) { names.localizedString(forRegionCode: $0) ?? $0 }
    if cacheOrder.count >= 100 { cache[cacheOrder.removeFirst()] = nil }
    cache[key] = matches
    cacheOrder.append(key)
    return matches
  }

  private func loadConfig() async -> GeocoderConfig {
    if let config { return config }
    var loaded = bundledConfig
    if let url = Self.remoteConfigURL {
      var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
      request.timeoutInterval = 3
      if let (data, response) = try? await session.data(for: request),
        (response as? HTTPURLResponse)?.statusCode == 200,
        let remote = GeocoderConfig.decode(data)
      {
        loaded = remote
      }
    }
    config = loaded
    return loaded
  }
}

enum LocationFailure: Error, Hashable {
  case denied
  case timeout
  case unavailable
}

/// The device's current location, requested only when the user asks for it.
@MainActor
protocol LocationProviding: AnyObject {
  /// True until the user has answered the system permission prompt.
  var needsPermission: Bool { get }
  func currentLocation() async -> Result<Coordinate, LocationFailure>
}

/// Foreground Core Location: asks for When In Use permission, then for one fix within 10 seconds.
@MainActor
final class DeviceLocation: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
  static let timeout: Duration = .seconds(10)

  private let manager = CLLocationManager()
  private var authorization: CheckedContinuation<Void, Never>?
  private var fix: CheckedContinuation<Result<Coordinate, LocationFailure>, Never>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  var needsPermission: Bool { manager.authorizationStatus == .notDetermined }

  func currentLocation() async -> Result<Coordinate, LocationFailure> {
    guard fix == nil else { return .failure(.unavailable) }
    if manager.authorizationStatus == .notDetermined {
      await withCheckedContinuation { continuation in
        authorization = continuation
        manager.requestWhenInUseAuthorization()
      }
    }
    switch manager.authorizationStatus {
    case .denied, .restricted: return .failure(.denied)
    case .notDetermined: return .failure(.unavailable)
    default: break
    }
    return await withCheckedContinuation { continuation in
      fix = continuation
      manager.requestLocation()
      Task { [weak self] in
        try? await Task.sleep(for: Self.timeout)
        self?.finish(.failure(.timeout))
      }
    }
  }

  private func finish(_ result: Result<Coordinate, LocationFailure>) {
    guard let fix else { return }
    self.fix = nil
    fix.resume(returning: result)
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager.authorizationStatus != .notDetermined, let authorization else { return }
    self.authorization = nil
    authorization.resume()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    finish(
      .success(
        Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    let code = (error as? CLError)?.code
    // `locationUnknown` is temporary: Core Location keeps trying until the timeout.
    if code == .locationUnknown { return }
    finish(.failure(code == .denied ? .denied : .unavailable))
  }
}
