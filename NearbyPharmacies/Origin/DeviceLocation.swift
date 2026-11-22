import CoreLocation
import Foundation
import PharmacyCore

enum LocationFailure: Error, Hashable {
  case denied
  case timeout
  case unavailable
}

@MainActor
protocol LocationProviding: AnyObject {
  /// True until the user has answered the system permission prompt.
  var needsPermission: Bool { get }
  func currentLocation() async -> Result<Coordinate, LocationFailure>
  func cancelLocation()
}

@MainActor
final class DeviceLocation: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
  private struct Request {
    let manager: CLLocationManager
    let continuation: CheckedContinuation<Result<Coordinate, LocationFailure>, Never>
    var timeout: Task<Void, Never>?
  }

  private let makeManager: () -> CLLocationManager
  private let waitForTimeout: @MainActor () async throws -> Void
  private var request: Request?

  init(
    makeManager: @escaping () -> CLLocationManager = { CLLocationManager() },
    waitForTimeout: @escaping @MainActor () async throws -> Void = {
      try await Task.sleep(for: .seconds(10))
    }
  ) {
    self.makeManager = makeManager
    self.waitForTimeout = waitForTimeout
  }

  var needsPermission: Bool {
    (request?.manager ?? makeManager()).authorizationStatus == .notDetermined
  }

  func currentLocation() async -> Result<Coordinate, LocationFailure> {
    guard request == nil else { return .failure(.unavailable) }
    return await withCheckedContinuation { continuation in
      // Each attempt has its own delegate source, so a queued callback can't affect a retry.
      let manager = makeManager()
      request = Request(manager: manager, continuation: continuation)
      manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
      manager.delegate = self
      if manager.authorizationStatus == .notDetermined {
        manager.requestWhenInUseAuthorization()
      } else {
        locationManagerDidChangeAuthorization(manager)
      }
    }
  }

  func cancelLocation() {
    finish(.failure(.unavailable))
  }

  private func finish(_ result: Result<Coordinate, LocationFailure>) {
    guard let request else { return }
    self.request = nil
    request.manager.delegate = nil
    if let timeout = request.timeout {
      timeout.cancel()
      request.manager.stopUpdatingLocation()
    }
    request.continuation.resume(returning: result)
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let request, request.manager === manager else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      guard request.timeout == nil else { return }
      self.request?.timeout = Task { [weak self, waitForTimeout] in
        do {
          try await waitForTimeout()
        } catch {
          return
        }
        guard !Task.isCancelled, self?.request?.manager === manager else { return }
        self?.finish(.failure(.timeout))
      }
      manager.requestLocation()
    case .denied, .restricted:
      finish(.failure(.denied))
    case .notDetermined:
      if request.timeout != nil { finish(.failure(.unavailable)) }
    @unknown default:
      finish(.failure(.unavailable))
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard request?.manager === manager, request?.timeout != nil else { return }
    guard
      let location = locations.last(where: {
        $0.horizontalAccuracy.isFinite && $0.horizontalAccuracy >= 0
          && CLLocationCoordinate2DIsValid($0.coordinate)
      })
    else {
      finish(.failure(.unavailable))
      return
    }
    finish(
      .success(
        Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    guard request?.manager === manager, request?.timeout != nil else { return }
    switch (error as? CLError)?.code {
    case .denied: finish(.failure(.denied))
    // For requestLocation(), this error ends the one-shot request.
    case .locationUnknown: finish(.failure(.timeout))
    default: finish(.failure(.unavailable))
    }
  }
}
