import Foundation
import PharmacyCore

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
  private static let contactURL = "https://github.com/vvartiainen/nearby-pharmacies-ios"
  // The published source repository serves the switchable configuration for reviewer builds.
  private static let remoteConfigURL = URL(
    string:
      "https://raw.githubusercontent.com/vvartiainen/nearby-pharmacies-ios/main/NearbyPharmacies/Resources/geocoder.json"
  )!

  private let session: URLSession
  private let bundledConfig: GeocoderConfig?
  private var configRequest: Task<GeocoderConfig?, Never>?
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
      "User-Agent": "NearbyPharmacies/\(version) (\(Self.contactURL))"
    ]
    session = URLSession(configuration: configuration)
    bundledConfig =
      bundle.url(forResource: "geocoder", withExtension: "json")
      .flatMap { try? Data(contentsOf: $0) }
      .flatMap(GeocoderConfig.decode)
  }

  func search(_ query: String, language: String) async throws -> [PlaceMatch] {
    guard let config = await loadConfig() else { return [] }
    try Task.checkCancellation()
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

  private func loadConfig() async -> GeocoderConfig? {
    if let configRequest { return await configRequest.value }
    let requestTask = Task { [session, bundledConfig] in
      var request = URLRequest(
        url: Self.remoteConfigURL, cachePolicy: .reloadIgnoringLocalCacheData)
      request.timeoutInterval = 3
      guard let (data, response) = try? await session.data(for: request),
        (response as? HTTPURLResponse)?.statusCode == 200
      else { return bundledConfig }
      // A local provider or invalid online configuration leaves search on the bundled index.
      return GeocoderConfig.decode(data)
    }
    configRequest = requestTask
    return await requestTask.value
  }
}
