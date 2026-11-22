import XCTest

/// Location, search and map picking with scripted geocoder and location answers. No test
/// contacts the geocoder or Core Location.
final class OriginJourneyTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  /// Nominatim's answer for "Kauppakatu 1": five municipalities, as in the web journey test.
  static let kauppakatu = """
    [
      {"lat":"61.49819","lon":"23.75937","address":{"road":"Kauppakatu","housenumber":"1","city":"Tampere","country":"Finland","country_code":"fi"}},
      {"lat":"60.98155","lon":"25.6648","address":{"road":"Kauppakatu","housenumber":"1","city":"Lahti","country":"Finland","country_code":"fi"}},
      {"lat":"62.89265","lon":"27.69587","address":{"road":"Kauppakatu","housenumber":"1","city":"Kuopio","country":"Finland","country_code":"fi"}},
      {"lat":"60.46609","lon":"26.94612","address":{"road":"Kauppakatu","housenumber":"1","city":"Kotka","country":"Finland","country_code":"fi"}},
      {"lat":"62.59518","lon":"29.75543","address":{"road":"Kauppakatu","housenumber":"1","city":"Joensuu","country":"Finland","country_code":"fi"}}
    ]
    """
  static let tampere = "61.4983,23.7732"
  static let haparanda = "65.8281312,24.1308946"

  @MainActor
  private func waitForLabel(
    _ element: XCUIElement, _ predicate: String, _ value: String, timeout: TimeInterval = 5,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label \(predicate) %@", value), object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
      "Expected label \(predicate) \(value), got \(element.label)", file: file, line: line)
  }

  /// Waits until the idle search field shows `origin` as the starting point.
  @MainActor
  private func waitForOrigin(
    _ app: XCUIApplication, _ origin: String, timeout: TimeInterval = 5,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let shown = NSPredicate { _, _ in JourneyApp.originText(app) == origin }
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: timeout),
      .completed, "Expected \(origin), got \(JourneyApp.originText(app))", file: file, line: line)
  }

  @MainActor
  func testOfferAfterResultsThenGrantedLocationReranksFromTampere() {
    let app = JourneyApp.launch(
      language: "en", locale: "en_GB",
      environment: ["UITEST_LOCATION_PROMPT": "1", "UITEST_LOCATION": Self.tampere])
    // The Helsinki results show first, then the offer; the app asks only after "Use location".
    let first = JourneyApp.firstRow(app)
    XCTAssertTrue(first.waitForExistence(timeout: 15))
    waitForLabel(first, "BEGINSWITH", "Steissin Apteekki")
    let offer = app.alerts["Show pharmacies nearest to you?"]
    XCTAssertTrue(offer.waitForExistence(timeout: 5))
    XCTAssertTrue(
      offer.staticTexts["Your location is used only on this device to calculate distances."].exists)
    attachScreenshot(app, name: "Location offer (en)")
    offer.buttons["Use location"].tap()

    waitForLabel(first, "BEGINSWITH", "Tullintorin apteekki")
    // The bundled address index names the nearest street address, as on web.
    waitForOrigin(app, "Near Rautatienkatu 25, Tampere")
    attachScreenshot(app, name: "Ranked from the device location (en)")

    // Pins and rows stay in sync for the new results.
    let id = first.identifier.replacingOccurrences(of: "row.", with: "")
    first.tap()
    XCTAssertTrue(app.staticTexts["details.name"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["details.name"].label, "Tullintorin apteekki")
    XCTAssertTrue(app.buttons[JourneyApp.pin(id)].isSelected)
  }

  @MainActor
  func testLocateButtonLeavesTheSheetInPlace() {
    let app = JourneyApp.launch(
      language: "en", locale: "en_GB", environment: ["UITEST_LOCATION": Self.tampere])
    let field = app.textFields["search.field"]
    let location = app.buttons["search.location"]
    XCTAssertTrue(location.waitForExistence(timeout: 15))
    let fieldTop = field.frame.minY
    location.tap()
    waitForLabel(JourneyApp.firstRow(app), "BEGINSWITH", "Tullintorin apteekki")
    sleep(1)
    // The list returns to the top with the space above the field kept, and no keyboard opens.
    // The new label can need a different number of lines than the default, which moves the
    // centred text a few points. Losing the space above the field would move it about 28.
    XCTAssertEqual(field.frame.minY, fieldTop, accuracy: 12)
    XCTAssertFalse(field.hasFocus)
    XCTAssertEqual(app.keyboards.count, 0)
  }

  @MainActor
  func testDeniedLocationKeepsHelsinki() {
    let app = JourneyApp.launch(
      language: "en", locale: "en_GB", environment: ["UITEST_LOCATION": "denied"])
    let location = app.buttons["search.location"]
    XCTAssertTrue(location.waitForExistence(timeout: 15))
    XCTAssertFalse(app.alerts.firstMatch.exists, "No offer once permission was answered")
    XCTAssertEqual(location.label, "Use my location")
    location.tap()
    let message = app.staticTexts["origin.message"]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    XCTAssertTrue(message.label.hasPrefix("Location permission was denied."))
    XCTAssertEqual(JourneyApp.originText(app), "Helsinki Central Railway Station (default)")
    waitForLabel(JourneyApp.firstRow(app), "BEGINSWITH", "Steissin Apteekki")
    attachScreenshot(app, name: "Location denied (en)")
  }

  @MainActor
  func testLocationTimeoutInFinnish() {
    let app = JourneyApp.launch(
      language: "fi", locale: "fi_FI", environment: ["UITEST_LOCATION": "timeout"])
    let location = app.buttons["search.location"]
    XCTAssertTrue(location.waitForExistence(timeout: 15))
    XCTAssertEqual(location.label, "Käytä sijaintiani")
    location.tap()
    let message = app.staticTexts["origin.message"]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    XCTAssertTrue(message.label.hasPrefix("Sijainnin haku kesti liian kauan."))
    XCTAssertEqual(JourneyApp.originText(app), "Helsingin päärautatieasema (oletus)")
  }

  @MainActor
  func testAmbiguousAddressListsMunicipalitiesAndChoosingOneReranks() {
    let app = JourneyApp.launch(
      language: "en", locale: "en_GB",
      environment: ["UITEST_GEOCODER": "fixture", "UITEST_GEOCODER_RESPONSE": Self.kauppakatu])
    let field = app.textFields["search.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    XCTAssertEqual(JourneyApp.originText(app), "Helsinki Central Railway Station (default)")
    let peekTop = field.frame.minY
    field.tap()
    XCTAssertEqual(field.placeholderValue, "City or street address")
    field.typeText("Kauppakatu 1")
    XCTAssertTrue(app.staticTexts["search.privacy"].exists)
    XCTAssertEqual(
      app.staticTexts["search.privacy"].label,
      "Search text is sent to OpenStreetMap’s Nominatim service. Enter a public place or address.")
    app.buttons["search.submit"].tap()

    XCTAssertTrue(app.staticTexts["matches.heading"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["matches.heading"].label, "Choose a match")
    XCTAssertEqual(app.buttons["match.0"].label, "Kauppakatu 1 · Tampere, Finland")
    XCTAssertEqual(app.buttons["match.1"].label, "Kauppakatu 1 · Lahti, Finland")
    XCTAssertTrue(app.buttons["match.4"].exists)
    XCTAssertFalse(app.buttons["match.5"].exists)
    XCTAssertTrue(app.links["matches.attribution"].exists)
    attachScreenshot(app, name: "Address matches (en)")

    app.buttons["match.0"].tap()
    XCTAssertFalse(app.buttons["match.0"].waitForExistence(timeout: 1))
    XCTAssertEqual(JourneyApp.originText(app), "Kauppakatu 1 · Tampere, Finland")
    XCTAssertEqual(app.staticTexts["search.origin"].exists, false, "The summary is not read twice")
    waitForLabel(JourneyApp.firstRow(app), "BEGINSWITH", "Yliopiston Apteekki")
    // The sheet returns to the detent it had before the search.
    let returned = NSPredicate { _, _ in abs(field.frame.minY - peekTop) < 40 }
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: returned, object: nil)], timeout: 5),
      .completed)
    attachScreenshot(app, name: "Ranked from Kauppakatu 1, Tampere (en)")
  }

  @MainActor
  func testEmptyReplyKeepsTheOriginInFinnish() {
    let app = JourneyApp.launch(
      language: "fi", locale: "fi_FI",
      environment: ["UITEST_GEOCODER": "fixture", "UITEST_GEOCODER_RESPONSE": "[]"])
    let field = app.textFields["search.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    field.tap()
    field.typeText("Kuvitteellinen 123\n")
    let message = app.staticTexts["origin.message"]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    XCTAssertEqual(
      message.label,
      "Hakusanalla ”Kuvitteellinen 123” ei löytynyt paikkoja Suomesta. Tarkista kirjoitusasu tai valitse kohta kartalta."
    )
    // The field keeps the text for a correction; the origin stays.
    XCTAssertEqual(JourneyApp.originText(app), "Kuvitteellinen 123")
    XCTAssertEqual(
      app.descendants(matching: .any)["map.origin"].label,
      "Lähtöpiste: Helsingin päärautatieasema (oletus)")
    attachScreenshot(app, name: "No matches (fi)")
  }

  @MainActor
  func testUnavailableGeocoderFallsBackToBundledSwedishNames() {
    let app = JourneyApp.launch(
      language: "en", locale: "en_GB", environment: ["UITEST_GEOCODER": "unavailable"])
    let field = app.textFields["search.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    field.tap()
    field.typeText("Tammerfor\n")
    XCTAssertTrue(app.staticTexts["matches.local"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["matches.local"].label, "Matches from the bundled place index.")
    XCTAssertFalse(app.links["matches.attribution"].exists)
    XCTAssertEqual(app.buttons["match.0"].label, "Tampere · Finland")
    attachScreenshot(app, name: "Bundled place matches (en)")
    app.buttons["match.0"].tap()
    waitForOrigin(app, "Tampere · Finland")

    // An address still needs the online service.
    field.tap()
    field.typeText("Kauppakatu 1\n")
    let message = app.staticTexts["origin.message"]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    XCTAssertTrue(message.label.hasPrefix("Address search is unavailable right now."))
  }

  @MainActor
  func testMapPickWinsOverALateGeocoderReply() {
    let app = JourneyApp.launch(
      language: "en", locale: "en_GB",
      environment: [
        "UITEST_GEOCODER": "fixture", "UITEST_GEOCODER_RESPONSE": Self.kauppakatu,
        "UITEST_GEOCODER_DELAY": "4", "UITEST_ADDRESS_INDEX": "none",
      ])
    let field = app.textFields["search.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    field.tap()
    field.typeText("Kauppakatu 1\n")
    XCTAssertEqual(app.buttons["search.submit"].label, "Searching…")
    XCTAssertFalse(app.buttons["search.submit"].isEnabled)

    JourneyApp.collapseSheet(app, topElement: field)
    JourneyApp.mapPoint(app).press(forDuration: 1)
    waitForOrigin(app, "Dropped pin")
    XCTAssertTrue(app.descendants(matching: .any)["map.origin"].label.hasSuffix("Dropped pin"))
    XCTAssertFalse(app.staticTexts["details.name"].exists, "A touch and hold does not select a pin")
    let reranked = JourneyApp.firstRow(app).label

    // The reply arrives after the pick and is ignored.
    sleep(5)
    XCTAssertFalse(app.staticTexts["matches.heading"].exists)
    XCTAssertEqual(JourneyApp.originText(app), "Dropped pin")
    XCTAssertEqual(JourneyApp.firstRow(app).label, reranked)
    attachScreenshot(app, name: "Dropped pin after a late reply (en)")
  }

  @MainActor
  func testChooseOnMapWinsOverALateLocationFixInFinnish() {
    let app = JourneyApp.launch(
      language: "fi", locale: "fi_FI",
      environment: [
        "UITEST_LOCATION": Self.tampere, "UITEST_LOCATION_DELAY": "15",
        "UITEST_ADDRESS_INDEX": "none",
      ])
    let location = app.buttons["search.location"]
    XCTAssertTrue(location.waitForExistence(timeout: 15))
    location.tap()
    XCTAssertFalse(location.isEnabled, "Busy while locating")

    // Panning alone only moves the map.
    let searchHere = app.buttons["map.searchHere"]
    let chooseOnMap = app.buttons["map.chooseOnMap"]
    XCTAssertEqual(chooseOnMap.label, "Valitse kartalta")
    JourneyApp.mapPoint(app, y: 0.35).press(
      forDuration: 0.05, thenDragTo: JourneyApp.mapPoint(app, x: 0.3, y: 0.2))
    XCTAssertFalse(searchHere.waitForExistence(timeout: 1))

    // "Choose on map", at the top centre, turns into "Search from here" in place, with
    // "Cancel" beside it.
    let window = app.windows.firstMatch.frame
    XCTAssertEqual(chooseOnMap.frame.midX, window.midX, accuracy: 2)
    let controlTop = chooseOnMap.frame.minY
    chooseOnMap.tap()
    XCTAssertTrue(searchHere.waitForExistence(timeout: 5))
    XCTAssertEqual(searchHere.label, "Hae tästä kohdasta")
    let cancel = app.buttons["map.cancelPick"]
    XCTAssertEqual(cancel.label, "Peruuta")
    sleep(1)
    XCTAssertEqual(searchHere.frame.minY, controlTop, accuracy: 1)
    XCTAssertEqual(
      (searchHere.frame.minX + cancel.frame.maxX) / 2, window.midX, accuracy: 2,
      "The pair stays centred")
    cancel.tap()
    XCTAssertTrue(chooseOnMap.waitForExistence(timeout: 5))
    XCTAssertFalse(searchHere.exists)

    chooseOnMap.tap()
    JourneyApp.mapPoint(app, x: 0.3, y: 0.2).press(
      forDuration: 0.05, thenDragTo: JourneyApp.mapPoint(app, y: 0.35))
    XCTAssertTrue(searchHere.waitForExistence(timeout: 5))
    attachScreenshot(app, name: "Choose on map (fi)")
    searchHere.tap()
    waitForOrigin(app, "Kartalta valittu kohta")
    XCTAssertFalse(searchHere.exists)

    // The fix arrives 15 s after the request, after the pick.
    sleep(10)
    XCTAssertEqual(JourneyApp.originText(app), "Kartalta valittu kohta")
    XCTAssertTrue(location.isEnabled)
  }

  @MainActor
  func testOutsideFinlandShowsFinnishResultsAndReturnsToHelsinki() {
    let app = JourneyApp.launch(
      language: "en", locale: "en_GB", environment: ["UITEST_LOCATION": Self.haparanda])
    let location = app.buttons["search.location"]
    XCTAssertTrue(location.waitForExistence(timeout: 15))
    location.tap()
    let notice = app.staticTexts["notice.outside"]
    XCTAssertTrue(notice.waitForExistence(timeout: 5))
    XCTAssertEqual(
      notice.label,
      "This starting point is outside Finland. Only pharmacies in Finland are shown.")
    waitForLabel(JourneyApp.firstRow(app), "BEGINSWITH", "Tornion I Apteekki")
    attachScreenshot(app, name: "Outside Finland (en)")

    app.buttons["notice.returnToHelsinki"].tap()
    waitForLabel(JourneyApp.firstRow(app), "BEGINSWITH", "Steissin Apteekki")
    XCTAssertEqual(JourneyApp.originText(app), "Helsinki Central Railway Station (default)")
    XCTAssertFalse(notice.exists)
  }
}
