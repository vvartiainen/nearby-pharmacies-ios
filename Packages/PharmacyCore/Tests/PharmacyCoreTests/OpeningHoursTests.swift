import Foundation
import PharmacyCore
import Testing

/// The same cases as the web app's `openingHours.test.ts`.
struct OpeningHoursTests {
  /// Renders the weekly result as "Mo 08:00-20:00" lines for compact expectations.
  private static func lines(_ result: OpeningHours.Interpreted) -> [String] {
    guard case .weekly(let days) = result else { return ["raw"] }
    let codes = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    return days.enumerated().map { index, ranges in
      let text = ranges.map { range in
        func clock(_ minutes: Int) -> String {
          String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
        return "\(clock(range.start))-\(clock(range.end))"
      }
      .joined(separator: ",")
      return "\(codes[index]) \(text.isEmpty ? "closed" : text)"
    }
  }

  private static func week(_ days: String...) -> [String] {
    let codes = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    return days.enumerated().map { "\(codes[$0]) \($1)" }
  }

  private static func every(_ value: String) -> [String] {
    week(value, value, value, value, value, value, value)
  }

  static let weeklyCases: [(String, [String])] = [
    (
      "Mo-Fr 08:00-20:00; Sa 10:00-16:00; Su off",
      week(
        "08:00-20:00", "08:00-20:00", "08:00-20:00", "08:00-20:00", "08:00-20:00", "10:00-16:00",
        "closed")
    ),
    (
      "Mo-Fr 08:00-20:00; Sa 11:00-17:00",
      week(
        "08:00-20:00", "08:00-20:00", "08:00-20:00", "08:00-20:00", "08:00-20:00", "11:00-17:00",
        "closed")
    ),
    ("Mo-Su 08:00-22:00", every("08:00-22:00")),
    ("08:00-24:00", every("08:00-24:00")),
    ("24/7", every("00:00-24:00")),
    (
      "Mo,We 09:00-13:00",
      week("09:00-13:00", "closed", "09:00-13:00", "closed", "closed", "closed", "closed")
    ),
    (
      "Mo-We, Fr 09:00-16:00; Th 09:00-17:00",
      week(
        "09:00-16:00", "09:00-16:00", "09:00-16:00", "09:00-17:00", "09:00-16:00", "closed",
        "closed")
    ),
    (
      "Mo-Tu,Th-Fr 09:00-12:00,12:30-16:00",
      week(
        "09:00-12:00,12:30-16:00", "09:00-12:00,12:30-16:00", "closed",
        "09:00-12:00,12:30-16:00", "09:00-12:00,12:30-16:00", "closed", "closed")
    ),
    (
      "Mo-Fr 09:00-19:00, Sa 09:00-15:00",
      week(
        "09:00-19:00", "09:00-19:00", "09:00-19:00", "09:00-19:00", "09:00-19:00", "09:00-15:00",
        "closed")
    ),
    (
      "Mo-Fr 09:00-16:30; We off",
      week(
        "09:00-16:30", "09:00-16:30", "closed", "09:00-16:30", "09:00-16:30", "closed", "closed")
    ),
    (
      "Mo-Fr 08:00-21:00; Sa 09:00-19:00; Su,PH 10:00-18:00; PH off",
      week(
        "08:00-21:00", "08:00-21:00", "08:00-21:00", "08:00-21:00", "08:00-21:00", "09:00-19:00",
        "10:00-18:00")
    ),
    (
      "Su-Fr 09:00-17:00; Sa 09:00-14:00",
      week(
        "09:00-17:00", "09:00-17:00", "09:00-17:00", "09:00-17:00", "09:00-17:00", "09:00-14:00",
        "09:00-17:00")
    ),
    (
      "Mo-Sa 09:00-18:00, Sa,Su 09:00-15:00",
      week(
        "09:00-18:00", "09:00-18:00", "09:00-18:00", "09:00-18:00", "09:00-18:00", "09:00-18:00",
        "09:00-15:00")
    ),
    (
      "Mo-Fr 9:00-17:00; Sa-Su closed",
      week(
        "09:00-17:00", "09:00-17:00", "09:00-17:00", "09:00-17:00", "09:00-17:00", "closed",
        "closed")
    ),
    (
      "Mo-Th 09:00-17:00; Fr 09:00-18:00; Sa  09:00-16:00",
      week(
        "09:00-17:00", "09:00-17:00", "09:00-17:00", "09:00-17:00", "09:00-18:00", "09:00-16:00",
        "closed")
    ),
  ]

  @Test("Interprets weekly values", arguments: weeklyCases)
  func interpretsWeekly(value: String, expected: [String]) {
    #expect(Self.lines(OpeningHours.interpret(value)) == expected)
  }

  @Test(
    "Keeps uninterpretable values as raw text",
    arguments: [
      "Mo-Fr 09:00-18:00; Jun-Aug 09:00-17:00",
      "week 01-53/2 Mo-Fr 09:00-19:00; week 02-52/2 Mo-Fr 09:00-21:00",
      #"Mo-Fr 08:00-18:00; Sa 09:00-15:00; Su 11:00-16:00 || "parillisina viikkoina""#,
      "Mo-Th 09:00-17:00; Su,PH off; Jun 21,Dec 24 09:00-12:00",
      "Mo-Fr",
      "Mo-Fr 09:00-25:00",
      "Mo-Fr 09:00-09:00",
      "Mo-Fr 09:00-17:00 off",
      "PH off",
      "by appointment",
      "",
    ]
  )
  func keepsRaw(value: String) {
    #expect(OpeningHours.interpret(value) == .raw(value))
  }

  @Test func interpretsMostOfTheBundledSnapshot() throws {
    let values = try SyncedFiles.loader.loadSnapshot().pharmacies.compactMap(\.openingHours)
    let weekly = values.filter {
      if case .weekly = OpeningHours.interpret($0) { return true }
      return false
    }
    #expect(Double(weekly.count) / Double(values.count) > 0.95)
    // The web app interprets 613 of the 623 values in this snapshot; both must agree.
    #expect(values.count == 623)
    #expect(weekly.count == 613)
  }

  @Test func formatsTimesForEachLanguage() {
    let morning = OpeningHours.TimeRange(start: 7 * 60 + 30, end: 18 * 60)
    #expect(morning.formatted(.english) == "07:30–18:00")
    #expect(morning.formatted(.finnish) == "7.30–18.00")
    let allDay = OpeningHours.TimeRange(start: 0, end: 24 * 60)
    #expect(allDay.formatted(.english) == "00:00–24:00")
    #expect(allDay.formatted(.finnish) == "0.00–24.00")
  }
}

struct PharmacyFormattingTests {
  private func pharmacy(_ json: String) throws -> Pharmacy {
    try JSONDecoder().decode(Pharmacy.self, from: Data(json.utf8))
  }

  @Test func addressLinesJoinStreetAndLocality() throws {
    let full = try pharmacy(
      #"{"id":"node/1","lat":60,"lon":24,"address":{"street":"Elielinaukio","housenumber":"3","postcode":"00100","city":"Helsinki"}}"#
    )
    #expect(full.addressLines == ["Elielinaukio 3", "00100 Helsinki"])

    let cityOnly = try pharmacy(#"{"id":"node/2","lat":60,"lon":24,"address":{"city":"Espoo"}}"#)
    #expect(cityOnly.addressLines == ["Espoo"])

    let numberOnly = try pharmacy(
      #"{"id":"node/3","lat":60,"lon":24,"address":{"housenumber":"5"}}"#)
    #expect(numberOnly.addressLines.isEmpty)

    let none = try pharmacy(#"{"id":"node/4","lat":60,"lon":24}"#)
    #expect(none.addressLines.isEmpty)
  }

  @Test func displayNameTrimsAndOmitsBlankNames() throws {
    #expect(
      try pharmacy(#"{"id":"a","lat":0,"lon":0,"name":" Apteekki "}"#).displayName == "Apteekki")
    #expect(try pharmacy(#"{"id":"a","lat":0,"lon":0,"name":"  "}"#).displayName == nil)
    #expect(try pharmacy(#"{"id":"a","lat":0,"lon":0}"#).displayName == nil)
  }

  @Test func pinUsesTheAreaInteriorPoint() throws {
    let area = try pharmacy(#"{"id":"way/1","lat":60,"lon":24,"pin":{"lat":60.1,"lon":24.1}}"#)
    #expect(area.pinCoordinate == Coordinate(lat: 60.1, lon: 24.1))
    let node = try pharmacy(#"{"id":"node/1","lat":60,"lon":24}"#)
    #expect(node.pinCoordinate == Coordinate(lat: 60, lon: 24))
  }
}
