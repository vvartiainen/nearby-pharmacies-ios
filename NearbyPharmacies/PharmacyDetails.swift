import PharmacyCore
import SwiftUI

/// Name, distance, address (or "Address unavailable") and opening hours of the selected pharmacy.
struct PharmacyDetails: View {
  let result: PharmacyResult
  let localization: AppLocalization

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(result.name)
          .font(.title3.weight(.semibold))
          .foregroundStyle(Color.textPrimary)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("details.name")
        Text(result.straightLine)
          .font(.body)
          .foregroundStyle(Color.textSecondary)
          .accessibilityIdentifier("details.distance")
        address
      }
      .fixedSize(horizontal: false, vertical: true)

      HoursBlock(openingHours: result.pharmacy.openingHours, localization: localization)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var address: some View {
    let lines = result.pharmacy.addressLines
    if lines.isEmpty {
      Text(localization.addressUnavailable)
        .font(.body)
        .foregroundStyle(Color.textSecondary)
        .accessibilityIdentifier("details.address")
    } else {
      Text(lines.joined(separator: "\n"))
        .font(.body)
        .foregroundStyle(Color.textPrimary)
        .accessibilityIdentifier("details.address")
    }
  }
}

/// "Opening hours", then one line per day, Monday first, or the raw value, or a notice.
struct HoursBlock: View {
  let openingHours: String?
  let localization: AppLocalization
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(localization.hoursHeading)
        .font(.body.weight(.semibold))
        .foregroundStyle(Color.textPrimary)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("details.hoursHeading")
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var content: some View {
    let value = openingHours?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if value.isEmpty {
      Text(localization.hoursUnavailable)
        .font(.body)
        .foregroundStyle(Color.noticeText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(Color.noticeSurface, in: .rect(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.noticeBorder))
        .accessibilityIdentifier("details.hoursUnavailable")
    } else {
      switch OpeningHours.interpret(value) {
      case .raw(let text):
        Text(text)
          .font(.body)
          .foregroundStyle(Color.textPrimary)
          .accessibilityIdentifier("details.hoursRaw")
      case .weekly(let days):
        week(days)
      }
    }
  }

  @ViewBuilder private func week(_ days: [[OpeningHours.TimeRange]]) -> some View {
    let names = localization.weekdays
    let rows = days.enumerated().map { index, ranges in
      (
        day: names.indices.contains(index) ? names[index] : "",
        times: ranges.isEmpty
          ? localization.closed
          : ranges.map { $0.formatted(localization.clockStyle) }.joined(separator: ", ")
      )
    }
    if dynamicTypeSize.isAccessibilitySize {
      // Too wide for two columns: the day sits above its times.
      VStack(alignment: .leading, spacing: Spacing.sm) {
        ForEach(rows, id: \.day) { row in
          VStack(alignment: .leading, spacing: 0) {
            Text(row.day).font(.body.weight(.semibold))
            Text(row.times).font(.body)
          }
          .foregroundStyle(Color.textPrimary)
          .accessibilityElement(children: .combine)
        }
      }
    } else {
      Grid(alignment: .leading, horizontalSpacing: Spacing.lg, verticalSpacing: Spacing.xs) {
        ForEach(rows, id: \.day) { row in
          GridRow {
            Text(row.day).font(.body.weight(.semibold))
            Text(row.times).font(.body)
          }
          .foregroundStyle(Color.textPrimary)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }
}
