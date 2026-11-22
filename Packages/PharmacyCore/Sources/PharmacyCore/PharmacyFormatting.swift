import Foundation

extension Pharmacy {
  /// The point where the pharmacy's pin is drawn: the interior point of an area, else its location.
  public var pinCoordinate: Coordinate { pin ?? coordinate }

  /// The name from the data with surrounding whitespace removed, or nil when it has none, so the
  /// caller can use its localized "Unnamed pharmacy".
  public var displayName: String? {
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
  }

  /// Address lines from the OSM address fields, "Street 3" and "00100 Helsinki", as in the web
  /// app's `addressLines`. Empty when there is nothing to show, so the caller can say "Address
  /// unavailable". A house number without a street is not shown.
  public var addressLines: [String] {
    let street = address?.street.flatMap(nonEmpty)
    let first = [street, street == nil ? nil : address?.housenumber.flatMap(nonEmpty)]
      .compactMap { $0 }.joined(separator: " ")
    let second = [address?.postcode, address?.city].compactMap { $0.flatMap(nonEmpty) }
      .joined(separator: " ")
    return [first, second].filter { !$0.isEmpty }
  }
}

private func nonEmpty(_ value: String) -> String? {
  value.isEmpty ? nil : value
}
