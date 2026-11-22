import XCTest

/// Launches the app in each supported language and checks the first screen.
final class LaunchSmokeTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunchInEnglish() {
    assertFirstScreen(
      language: "en",
      locale: "en_GB",
      heading: "Nearest pharmacy",
      note: "Illustrative example distance",
      distance: "1.7 km straight line"
    )
  }

  @MainActor
  func testLaunchInFinnish() {
    assertFirstScreen(
      language: "fi",
      locale: "fi_FI",
      heading: "Lähin apteekki",
      note: "Havainnollistava esimerkkietäisyys",
      distance: "1,7 km linnuntietä"
    )
  }

  @MainActor
  private func assertFirstScreen(
    language: String,
    locale: String,
    heading: String,
    note: String,
    distance: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
    app.launch()

    let headingElement = app.staticTexts["heading"]
    XCTAssertTrue(headingElement.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertEqual(headingElement.label, heading, file: file, line: line)
    XCTAssertEqual(app.staticTexts["illustrativeNote"].label, note, file: file, line: line)
    XCTAssertEqual(
      normalizingSpaces(app.staticTexts["distance"].label), distance, file: file, line: line)

    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Launch (\(language))"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func normalizingSpaces(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{00A0}", with: " ")
      .replacingOccurrences(of: "\u{202F}", with: " ")
  }
}
