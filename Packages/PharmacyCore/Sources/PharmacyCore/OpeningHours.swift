import Foundation

/// A small interpreter for the common weekly forms of the OSM `opening_hours` tag, enough to show
/// one line per weekday in the details. It follows the web app's `interpretOpeningHours`. Anything
/// it does not understand (months, weeks, dates, comments, `||` fallbacks, open-ended times) makes
/// the whole value uninterpretable, so the UI shows the raw text instead of a guess. Public holiday
/// (`PH`) selectors are ignored: the weekly view describes an ordinary week.
public enum OpeningHours {
  /// A time range in minutes after midnight. `end` may be 1 440 ("24:00"), or earlier than `start`
  /// for a range past midnight.
  public struct TimeRange: Hashable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
      self.start = start
      self.end = end
    }
  }

  public enum Interpreted: Hashable, Sendable {
    /// Seven entries, Monday first. An empty list means closed that day.
    case weekly([[TimeRange]])
    case raw(String)
  }

  public static func interpret(_ value: String) -> Interpreted {
    var week = [[TimeRange]](repeating: [], count: 7)
    var applied = false
    for part in value.split(separator: ";", omittingEmptySubsequences: false) {
      if part.allSatisfy(\.isWhitespace) { continue }
      guard let rules = parseRules(part) else { return .raw(value) }
      for rule in rules {
        // A selector naming only public holidays ("PH off") does not describe an ordinary week.
        if let days = rule.days, days.isEmpty { continue }
        for day in rule.days.map({ $0.sorted() }) ?? Array(0..<7) {
          if rule.off {
            week[day] = []
          } else {
            week[day] = rule.additional ? week[day] + rule.ranges : rule.ranges
          }
        }
        applied = true
      }
    }
    return applied ? .weekly(week.map(mergeRanges)) : .raw(value)
  }

  // MARK: - Parsing

  private struct Rule {
    /// Weekday indexes; nil when the rule has no day selector (every day).
    var days: Set<Int>?
    var ranges: [TimeRange] = []
    var off = false
    /// Later rules in the same part add to earlier ones; rules after a semicolon replace them.
    var additional: Bool
  }

  private enum Token {
    case day(String, String?)
    case range(String, String)
    case off
    case always
    case comma
  }

  private static let dayCodes = ["mo", "tu", "we", "th", "fr", "sa", "su"]

  private static func parseRules(_ part: Substring) -> [Rule]? {
    var rules: [Rule] = []
    var rule = Rule(additional: false)
    var hasSelector = false
    var scanner = Tokenizer(part)
    while !scanner.isAtEnd {
      guard let token = scanner.next() else { return nil }
      switch token {
      case .day(let day, let dayEnd):
        if !rule.ranges.isEmpty || rule.off {
          rules.append(rule)
          rule = Rule(additional: true)
          hasSelector = false
        }
        hasSelector = true
        guard addDays(to: &rule, day: day, dayEnd: dayEnd) else { return nil }
      case .range(let start, let end):
        guard !rule.off, let range = parseRange(start, end) else { return nil }
        rule.ranges.append(range)
      case .off:
        guard rule.ranges.isEmpty else { return nil }
        rule.off = true
      case .always:
        guard !hasSelector, rule.ranges.isEmpty, !rule.off else { return nil }
        rule.ranges.append(TimeRange(start: 0, end: 24 * 60))
      case .comma:
        break
      }
    }
    // A selector without times ("Mo-Fr") means open all day in OSM; too rare to trust here.
    if rule.ranges.isEmpty && !rule.off { return nil }
    rules.append(rule)
    return rules
  }

  private static func addDays(to rule: inout Rule, day: String, dayEnd: String?) -> Bool {
    var days = rule.days ?? []
    defer { rule.days = days }
    if day.lowercased() == "ph" { return dayEnd == nil }
    guard let first = dayCodes.firstIndex(of: day.lowercased()) else { return false }
    guard let last = dayEnd.map({ dayCodes.firstIndex(of: $0.lowercased()) }) ?? first else {
      return false
    }
    // Ranges may wrap past Sunday, as in "Su-Fr" or "Fr-Mo".
    var index = first
    while true {
      days.insert(index)
      if index == last { return true }
      index = (index + 1) % 7
    }
  }

  private static func parseRange(_ start: String, _ end: String) -> TimeRange? {
    guard let from = parseTime(start), let to = parseTime(end), from < 24 * 60, from != to else {
      return nil
    }
    return TimeRange(start: from, end: to)
  }

  private static func parseTime(_ text: String) -> Int? {
    let parts = text.split(separator: ":")
    guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]), minutes <= 59
    else { return nil }
    let total = hours * 60 + minutes
    return total <= 24 * 60 ? total : nil
  }

  private static func mergeRanges(_ ranges: [TimeRange]) -> [TimeRange] {
    var merged: [TimeRange] = []
    for range in ranges.sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, range.end > range.start, last.end > last.start,
        range.start <= last.end
      {
        if range.end > last.end { merged[merged.count - 1].end = range.end }
      } else if !merged.contains(range) {
        merged.append(range)
      }
    }
    return merged
  }

  /// Splits one semicolon-separated part into tokens. Matches the web app's token pattern:
  /// day codes with an optional day range, `H:MM-H:MM`, `off` or `closed`, `24/7` and commas,
  /// each with optional surrounding whitespace, case-insensitive.
  private struct Tokenizer {
    private let characters: [Character]
    private var index = 0

    init(_ text: Substring) {
      characters = Array(text)
    }

    var isAtEnd: Bool { index >= characters.count }

    mutating func next() -> Token? {
      skipSpaces()
      let token: Token
      if let day = readDay() {
        let save = index
        skipSpaces()
        if consume("-") {
          skipSpaces()
          if let dayEnd = readDay(allowPH: false) {
            token = .day(day, dayEnd)
          } else {
            index = save
            token = .day(day, nil)
          }
        } else {
          index = save
          token = .day(day, nil)
        }
      } else if let start = readTime() {
        skipSpaces()
        guard consume("-") else { return nil }
        skipSpaces()
        guard let end = readTime() else { return nil }
        token = .range(start, end)
      } else if consumeWord("off") || consumeWord("closed") {
        token = .off
      } else if consumeWord("24/7") {
        token = .always
      } else if consume(",") {
        token = .comma
      } else {
        return nil
      }
      skipSpaces()
      return token
    }

    private mutating func skipSpaces() {
      while index < characters.count, characters[index].isWhitespace { index += 1 }
    }

    private mutating func consume(_ character: Character) -> Bool {
      guard index < characters.count, characters[index] == character else { return false }
      index += 1
      return true
    }

    private mutating func consumeWord(_ word: String) -> Bool {
      let end = index + word.count
      guard end <= characters.count,
        String(characters[index..<end]).lowercased() == word
      else { return false }
      index = end
      return true
    }

    private mutating func readDay(allowPH: Bool = true) -> String? {
      let end = index + 2
      guard end <= characters.count else { return nil }
      let code = String(characters[index..<end])
      let lower = code.lowercased()
      guard OpeningHours.dayCodes.contains(lower) || (allowPH && lower == "ph") else { return nil }
      index = end
      return code
    }

    /// `\d{1,2}:\d{2}`
    private mutating func readTime() -> String? {
      let start = index
      var hourDigits = 0
      while index < characters.count, characters[index].isASCII, characters[index].isNumber,
        hourDigits < 2
      {
        index += 1
        hourDigits += 1
      }
      guard hourDigits > 0, consume(":") else {
        index = start
        return nil
      }
      for _ in 0..<2 {
        guard index < characters.count, characters[index].isASCII, characters[index].isNumber
        else {
          index = start
          return nil
        }
        index += 1
      }
      return String(characters[start..<index])
    }
  }
}

extension OpeningHours.TimeRange {
  /// The clock time style for a language: English "07:30", Finnish "7.30" (period separator and
  /// no leading zero, as recommended by the Institute for the Languages of Finland).
  public enum ClockStyle: Sendable {
    case english
    case finnish
  }

  public func formatted(_ style: ClockStyle) -> String {
    "\(Self.clock(start, style))–\(Self.clock(end, style))"
  }

  static func clock(_ minutes: Int, _ style: ClockStyle) -> String {
    let hours = minutes / 60
    let remainder = String(format: "%02d", minutes % 60)
    switch style {
    case .english: return String(format: "%02d", hours) + ":" + remainder
    case .finnish: return "\(hours).\(remainder)"
    }
  }
}
