import CoreLocation
import Foundation
import PharmacyCore

enum LocationFailure: Error, Hashable {
  case denied
  case timeout
  case unavailable
}

/// A device position and its horizontal uncertainty in metres.
struct LocationFix: Hashable, Sendable {
  let coordinate: Coordinate
  let accuracy: Double

  init(_ coordinate: Coordinate, accuracy: Double) {
    self.coordinate = coordinate
    self.accuracy = accuracy
  }
}

@MainActor
protocol LocationProviding: AnyObject {
  /// True until the user has answered the system permission prompt.
  var needsPermission: Bool { get }
  func currentLocation() async -> Result<LocationFix, LocationFailure>
}

@MainActor
final class DeviceLocation: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
  static let timeout: Duration = .seconds(10)

  private let manager = CLLocationManager()
  private var authorization: CheckedContinuation<Void, Never>?
  private var fix: CheckedContinuation<Result<LocationFix, LocationFailure>, Never>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  var needsPermission: Bool { manager.authorizationStatus == .notDetermined }

  func currentLocation() async -> Result<LocationFix, LocationFailure> {
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

  private func finish(_ result: Result<LocationFix, LocationFailure>) {
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
    // A negative accuracy marks an invalid horizontal position.
    finish(
      .success(
        LocationFix(
          Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
          accuracy: location.horizontalAccuracy < 0 ? .infinity : location.horizontalAccuracy)))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    let code = (error as? CLError)?.code
    // `locationUnknown` is temporary: Core Location keeps trying until the timeout.
    if code == .locationUnknown { return }
    finish(.failure(code == .denied ? .denied : .unavailable))
  }
}
