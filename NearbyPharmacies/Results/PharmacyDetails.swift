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
    // Sized to the content, so the parent can centre the block.
    .fixedSize(horizontal: false, vertical: true)
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

struct HoursBlock: View {
  let openingHours: String?
  let localization: AppLocalization
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let value = openingHours?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hours = value.isEmpty ? nil : OpeningHours.interpret(value)
    let heading =
      if case .weekly = hours {
        localization.weeklyHoursHeading
      } else {
        localization.hoursHeading
      }

    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(heading)
        .font(.body.weight(.semibold))
        .foregroundStyle(Color.textPrimary)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("details.hoursHeading")
      content(hours)
    }
  }

  @ViewBuilder private func content(_ hours: OpeningHours.Interpreted?) -> some View {
    switch hours {
    case nil:
      Text(localization.hoursUnavailable)
        .font(.body)
        .foregroundStyle(Color.noticeText)
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(Color.noticeSurface, in: .rect(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.noticeBorder))
        .accessibilityIdentifier("details.hoursUnavailable")
    case .raw(let text):
      Text(text)
        .font(.body)
        .foregroundStyle(Color.textPrimary)
        .accessibilityIdentifier("details.hoursRaw")
    case .weekly(let days):
      Text(localization.holidayHoursNote)
        .font(.subheadline)
        .foregroundStyle(Color.textSecondary)
        .accessibilityIdentifier("details.holidayHoursNote")
      week(days)
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
