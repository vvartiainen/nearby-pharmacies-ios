import XCTest

/// Launches the app in each supported language and checks the default results from Helsinki
/// Central Railway Station.
final class LaunchSmokeTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunchInEnglish() {
    let app = JourneyApp.launch(language: "en", locale: "en_GB")
    assertDefaultResults(
      app,
      title: "Nearest pharmacies",
      scope: "Mapped pharmacies in Finland · 784",
      origin: "Helsinki Central Railway Station (default)",
      firstRow: "Steissin Apteekki, 50 m straight line"
    )
    attachScreenshot(app, name: "Launch (en)")
  }

  @MainActor
  func testLaunchInFinnish() {
    let app = JourneyApp.launch(language: "fi", locale: "fi_FI")
    assertDefaultResults(
      app,
      title: "Lähimmät apteekit",
      scope: "Kartoitetut apteekit Suomessa · 784",
      origin: "Helsingin päärautatieasema (oletus)",
      firstRow: "Steissin Apteekki, 50 m linnuntietä"
    )
    attachScreenshot(app, name: "Launch (fi)")
  }

  @MainActor
  private func assertDefaultResults(
    _ app: XCUIApplication, title: String, scope: String, origin: String, firstRow: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let titleElement = app.staticTexts["results.title"]
    XCTAssertTrue(titleElement.waitForExistence(timeout: 15), file: file, line: line)
    XCTAssertEqual(titleElement.label, title, file: file, line: line)
    XCTAssertEqual(
      normalizingSpaces(app.staticTexts["results.scope"].label), scope, file: file, line: line)
    XCTAssertTrue(
      app.descendants(matching: .any)["origin"].label.hasSuffix(origin), file: file, line: line)

    let first = app.buttons[JourneyApp.row(JourneyApp.steissin)]
    XCTAssertTrue(
      first.isHittable, "The nearest row shows at the peek detent", file: file, line: line)
    XCTAssertEqual(normalizingSpaces(first.label), firstRow, file: file, line: line)
    XCTAssertFalse(first.isSelected, file: file, line: line)
    XCTAssertTrue(
      app.buttons[JourneyApp.pin(JourneyApp.steissin)].waitForExistence(timeout: 10),
      file: file, line: line)
  }
}

/// Selecting rows and pins keeps the pin, the row and the details in sync.
final class SelectionTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testRowSelectionShowsDetailsAndKeepsTheDetent() {
    let app = JourneyApp.launch(language: "en", locale: "en_GB")
    let row = app.buttons[JourneyApp.row(JourneyApp.steissin)]
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    let sheetTop = app.staticTexts["results.title"].frame.minY

    row.tap()

    let name = app.staticTexts["details.name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertEqual(name.label, "Steissin Apteekki")
    XCTAssertEqual(
      normalizingSpaces(app.staticTexts["details.distance"].label), "50 m straight line")
    XCTAssertEqual(app.staticTexts["details.address"].label, "Elielinaukio 3\n00100 Helsinki")
    // The sheet keeps the peek detent: the details start where the list header was.
    let back = app.buttons["details.back"]
    XCTAssertEqual(back.label, "Back to results")
    XCTAssertEqual(back.frame.minY, sheetTop, accuracy: 40)
    XCTAssertTrue(name.isHittable)

    let pin = app.buttons[JourneyApp.pin(JourneyApp.steissin)]
    XCTAssertTrue(pin.isSelected)
    XCTAssertEqual(normalizingSpaces(pin.label), "Steissin Apteekki, 50 m straight line")
    attachScreenshot(app, name: "Row selected, peek (en)")

    // Expanded, the details show the opening hours, Monday first.
    JourneyApp.expandSheet(app, topElement: app.buttons["details.back"])
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "07:30–18:00")).firstMatch
        .waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Opening hours"].exists)
    attachScreenshot(app, name: "Details with hours (en)")

    back.tap()
    let selectedRow = app.buttons[JourneyApp.row(JourneyApp.steissin)]
    XCTAssertTrue(selectedRow.waitForExistence(timeout: 5))
    XCTAssertTrue(selectedRow.isSelected, "Returning to the list keeps the selection")
    attachScreenshot(app, name: "Back to results with selection (en)")
  }

  @MainActor
  func testPinSelectionShowsMissingAddressAndHoursInFinnish() {
    let app = JourneyApp.launch(language: "fi", locale: "fi_FI")
    let pin = app.buttons[JourneyApp.pin(JourneyApp.kaarti)]
    XCTAssertTrue(pin.waitForExistence(timeout: 15))
    XCTAssertEqual(normalizingSpaces(pin.label), "Kaartin Apteekki, 820 m linnuntietä")
    XCTAssertFalse(pin.isSelected)

    pin.tap()

    let name = app.staticTexts["details.name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertEqual(name.label, "Kaartin Apteekki")
    XCTAssertEqual(app.staticTexts["details.address"].label, "Osoite ei saatavilla")
    XCTAssertTrue(app.buttons["details.back"].isHittable)
    XCTAssertEqual(app.buttons["details.back"].label, "Takaisin tuloksiin")
    XCTAssertTrue(app.buttons[JourneyApp.pin(JourneyApp.kaarti)].isSelected)
    attachScreenshot(app, name: "Pin selected, peek (fi)")

    // Selecting another pin replaces the details in place and keeps the detent.
    app.buttons[JourneyApp.pin(JourneyApp.steissin)].tap()
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label == %@", "Steissin Apteekki")).firstMatch
        .waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["details.name"].label, "Steissin Apteekki")
    XCTAssertTrue(app.buttons[JourneyApp.pin(JourneyApp.steissin)].isSelected)
    // The map zooms to the new selection, so the Kaartin pin may be off-screen and absent.
    let kaartiPin = app.buttons[JourneyApp.pin(JourneyApp.kaarti)]
    XCTAssertFalse(kaartiPin.exists && kaartiPin.isSelected)
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "7.30–18.00")).firstMatch
        .exists)

    // Choose Kaartin Apteekki again from its row in the expanded list.
    app.buttons["details.back"].tap()
    XCTAssertTrue(app.staticTexts["results.title"].waitForExistence(timeout: 5))
    JourneyApp.expandSheet(app, topElement: app.staticTexts["results.title"])
    let kaartiRow = app.buttons[JourneyApp.row(JourneyApp.kaarti)]
    XCTAssertTrue(kaartiRow.waitForExistence(timeout: 5))
    XCTAssertFalse(kaartiRow.isSelected)
    kaartiRow.tap()
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label == %@", "Kaartin Apteekki")).firstMatch
        .waitForExistence(timeout: 5))
    let missing = app.staticTexts["details.hoursUnavailable"]
    XCTAssertTrue(missing.waitForExistence(timeout: 5))
    XCTAssertTrue(missing.isHittable)
    XCTAssertEqual(missing.label, "Aukioloajat eivät saatavilla")
    attachScreenshot(app, name: "Missing address and hours, large (fi)")

    app.buttons["details.back"].tap()
    XCTAssertTrue(kaartiRow.waitForExistence(timeout: 5))
    XCTAssertTrue(kaartiRow.isSelected)
    XCTAssertFalse(app.buttons[JourneyApp.row(JourneyApp.steissin)].isSelected)
    attachScreenshot(app, name: "Back to results, large (fi)")
  }
}

/// The results sheet at the largest accessibility text size.
final class LargeTextTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testSheetShowsAFullRowAtAccessibilitySize() {
    let app = JourneyApp.launch(
      language: "fi", locale: "fi_FI", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    let row = app.buttons[JourneyApp.row(JourneyApp.steissin)]
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    XCTAssertTrue(row.isHittable)
    let window = app.windows.firstMatch.frame
    XCTAssertLessThanOrEqual(row.frame.maxY, window.maxY, "The whole nearest row is visible")
    // Medium (large on short screens such as iPhone SE), never the peek.
    XCTAssertLessThan(app.staticTexts["results.title"].frame.minY, window.height * 0.6)
    attachScreenshot(app, name: "Accessibility XXXL list (fi)")

    row.tap()
    let name = app.staticTexts["details.name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertTrue(name.isHittable)
    attachScreenshot(app, name: "Accessibility XXXL details (fi)")
  }
}

enum JourneyApp {
  static let steissin = "node/1369465553"
  /// Kaartin Apteekki: no address and no opening hours in the data.
  static let kaarti = "node/12000572914"

  /// Drags the sheet by its grabber, just above `topElement`, to the large detent and checks
  /// that it got there. `topElement` is the first element in the sheet, such as the list title or
  /// the back button.
  @MainActor
  static func expandSheet(
    _ app: XCUIApplication, topElement: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let window = app.windows.firstMatch
    let origin = window.coordinate(withNormalizedOffset: .zero)
    let grabber = origin.withOffset(
      CGVector(dx: window.frame.width / 2, dy: topElement.frame.minY - 22))
    let top = origin.withOffset(CGVector(dx: window.frame.width / 2, dy: 40))
    grabber.press(
      forDuration: 0.1, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.2)
    let expanded = NSPredicate { _, _ in topElement.frame.minY < window.frame.height * 0.25 }
    let wait = XCTNSPredicateExpectation(predicate: expanded, object: nil)
    XCTAssertEqual(
      XCTWaiter.wait(for: [wait], timeout: 5), .completed, "The sheet reaches the large detent",
      file: file, line: line)
  }

  static func row(_ id: String) -> String { "row.\(id)" }
  static func pin(_ id: String) -> String { "pin.\(id)" }

  @MainActor
  static func launch(language: String, locale: String, contentSize: String? = nil)
    -> XCUIApplication
  {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
    if let contentSize {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
    }
    app.launch()
    return app
  }
}

extension XCTestCase {
  @MainActor
  func attachScreenshot(_ app: XCUIApplication, name: String) {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}

/// Formatters may use a no-break space between the number and the unit.
func normalizingSpaces(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{00A0}", with: " ")
    .replacingOccurrences(of: "\u{202F}", with: " ")
}
