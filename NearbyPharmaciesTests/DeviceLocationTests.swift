import CoreLocation
import PharmacyCore
import Testing

@testable import NearbyPharmacies

@MainActor
struct DeviceLocationTests {
  @Test func aSuccessfulRequestCancelsItsTimeoutBeforeTheNextRequest() async throws {
    let firstManager = StubLocationManager()
    let secondManager = StubLocationManager()
    var managers = [firstManager, secondManager]
    let timeouts = ManualTimeouts()
    let locator = DeviceLocation(
      makeManager: { managers.removeFirst() }, waitForTimeout: timeouts.wait)
    let first = Task { await locator.currentLocation() }
    try await waitUntil { timeouts.count == 1 }
    firstManager.deliver(accuracy: 25)
    #expect(try await first.value.get() == Coordinate(lat: 61.4983, lon: 23.7732))

    let second = Task { await locator.currentLocation() }
    try await waitUntil { timeouts.count == 2 }
    // Let the first timeout return even though its task was cancelled.
    timeouts.elapse(0)
    try await waitUntil { timeouts.cancellations.count == 1 }
    #expect(timeouts.cancellations == [true])
    #expect(secondManager.stops == 0)

    secondManager.deliver(accuracy: 500)
    #expect(try await second.value.get() == Coordinate(lat: 61.4983, lon: 23.7732))
    timeouts.elapse(1)
  }

  @Test func aNegativeAccuracyFixFails() async throws {
    let manager = StubLocationManager()
    let locator = DeviceLocation(makeManager: { manager })
    let request = Task { await locator.currentLocation() }
    try await waitUntil { manager.requests == 1 }
    manager.deliver(accuracy: -1)
    #expect(await request.value == .failure(.unavailable))
  }

  @Test func timingOutStopsTheOneShotAndLateCallbacksCannotCompleteARetry() async throws {
    let firstManager = StubLocationManager()
    let secondManager = StubLocationManager()
    var managers = [firstManager, secondManager]
    let timeouts = ManualTimeouts()
    let locator = DeviceLocation(
      makeManager: { managers.removeFirst() }, waitForTimeout: timeouts.wait)
    let first = Task { await locator.currentLocation() }
    try await waitUntil { timeouts.count == 1 }
    timeouts.elapse(0)
    #expect(await first.value == .failure(.timeout))
    #expect(firstManager.stops == 1)
    #expect(firstManager.delegate == nil)

    let second = Task { await locator.currentLocation() }
    try await waitUntil { timeouts.count == 2 }
    locator.locationManager(firstManager, didFailWithError: CLError(.denied))
    secondManager.deliver(accuracy: 0)
    #expect(try await second.value.get() == Coordinate(lat: 61.4983, lon: 23.7732))
    timeouts.elapse(1)
  }

  @Test func authorizationWaitRejectsOverlapAndStartsOnlyOneFixWhenGranted() async throws {
    let manager = StubLocationManager()
    manager.status = .notDetermined
    let timeouts = ManualTimeouts()
    let locator = DeviceLocation(makeManager: { manager }, waitForTimeout: timeouts.wait)
    let request = Task { await locator.currentLocation() }
    try await waitUntil { manager.authorizationRequests == 1 }
    manager.reportAuthorization(.notDetermined)
    #expect(manager.requests == 0)
    #expect(timeouts.count == 0)
    #expect(await locator.currentLocation() == .failure(.unavailable))

    manager.reportAuthorization(.authorizedWhenInUse)
    manager.reportAuthorization(.authorizedWhenInUse)
    #expect(manager.requests == 1)
    try await waitUntil { timeouts.count == 1 }
    manager.reportAuthorization(.denied)
    #expect(await request.value == .failure(.denied))
    #expect(manager.stops == 1)
    timeouts.elapse(0)
  }

  @Test func cancellingDuringAuthorizationAllowsAnImmediateRetry() async throws {
    let firstManager = StubLocationManager()
    firstManager.status = .notDetermined
    let secondManager = StubLocationManager()
    var managers = [firstManager, secondManager]
    let locator = DeviceLocation(makeManager: { managers.removeFirst() })
    let first = Task { await locator.currentLocation() }
    try await waitUntil { firstManager.authorizationRequests == 1 }
    locator.cancelLocation()

    let second = Task { await locator.currentLocation() }
    try await waitUntil { secondManager.requests == 1 }
    firstManager.status = .authorizedWhenInUse
    locator.locationManagerDidChangeAuthorization(firstManager)
    #expect(firstManager.requests == 0)
    #expect(await first.value == .failure(.unavailable))

    locator.cancelLocation()
    #expect(secondManager.stops == 1)
    #expect(await second.value == .failure(.unavailable))
  }

  @Test func aLocationUnknownErrorEndsTheOneShotImmediately() async throws {
    let manager = StubLocationManager()
    let timeouts = ManualTimeouts()
    let locator = DeviceLocation(makeManager: { manager }, waitForTimeout: timeouts.wait)
    let request = Task { await locator.currentLocation() }
    try await waitUntil { timeouts.count == 1 }
    manager.delegate?.locationManager?(manager, didFailWithError: CLError(.locationUnknown))
    #expect(manager.stops == 1)
    timeouts.elapse(0)
    #expect(await request.value == .failure(.timeout))
    try await waitUntil { timeouts.cancellations.count == 1 }
    #expect(timeouts.cancellations == [true])
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition())
  }
}

private final class StubLocationManager: CLLocationManager {
  var status: CLAuthorizationStatus = .authorizedWhenInUse
  private(set) var authorizationRequests = 0
  private(set) var requests = 0
  private(set) var stops = 0

  override var authorizationStatus: CLAuthorizationStatus { status }
  override func requestWhenInUseAuthorization() { authorizationRequests += 1 }
  override func requestLocation() { requests += 1 }
  override func stopUpdatingLocation() { stops += 1 }

  func reportAuthorization(_ status: CLAuthorizationStatus) {
    self.status = status
    delegate?.locationManagerDidChangeAuthorization?(self)
  }

  func deliver(accuracy: Double) {
    let location = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 61.4983, longitude: 23.7732),
      altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: .now)
    delegate?.locationManager?(self, didUpdateLocations: [location])
  }
}

@MainActor
private final class ManualTimeouts {
  private var waits: [CheckedContinuation<Void, Never>] = []
  private(set) var cancellations: [Bool] = []
  var count: Int { waits.count }

  func wait() async {
    await withCheckedContinuation { waits.append($0) }
    cancellations.append(Task.isCancelled)
  }

  func elapse(_ index: Int) {
    waits[index].resume()
  }
}
