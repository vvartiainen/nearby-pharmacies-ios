import PharmacyCore
import SwiftUI

/// "City or street address" with the location control and Search, then the search or location
/// message and the matches to choose from.
struct OriginSearch: View {
  let controller: OriginController
  @Binding var draft: String
  var focus: FocusState<Bool>.Binding

  private var localization: AppLocalization { controller.finder.localization }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.sm) {
        field
        submitButton
      }
      if focus.wrappedValue || controller.search != .idle {
        Text(localization.searchPrivacy)
          .font(.footnote)
          .foregroundStyle(Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("search.privacy")
      }
      message
      matches
    }
    .onChange(of: draft) {
      // Editing the text closes the matches of the previous search.
      switch controller.search {
      case .matches, .empty, .unavailable: controller.cancelSearch()
      case .idle, .pending: break
      }
    }
  }

  private var field: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Color.textSecondary)
        .accessibilityHidden(true)
      TextField(localization.searchLabel, text: $draft)
        .focused(focus)
        .submitLabel(.search)
        .onSubmit(submit)
        .autocorrectionDisabled()
        .foregroundStyle(Color.textPrimary)
        .accessibilityIdentifier("search.field")
      locationButton
    }
    .padding(.leading, Spacing.md)
    .frame(minHeight: minimumHitTarget)
    .background(Color.pageBackground, in: .rect(cornerRadius: Radius.md))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.md)
        .strokeBorder(focus.wrappedValue ? Color.focusRing : Color.borderSubtle)
    }
  }

  private var locationButton: some View {
    Button {
      focus.wrappedValue = false
      controller.requestLocation()
    } label: {
      Group {
        if controller.isLocating {
          ProgressView()
        } else {
          Image(systemName: "location")
            .font(.body.weight(.medium))
        }
      }
      .frame(width: minimumHitTarget, height: minimumHitTarget)
      .contentShape(.rect)
    }
    .tint(Color.interactivePrimary)
    .disabled(controller.isLocating)
    .accessibilityLabel(localization.useMyLocation)
    .accessibilityValue(controller.isLocating ? localization.locationPending : "")
    .accessibilityIdentifier("search.location")
  }

  private var submitButton: some View {
    Button(action: submit) {
      Text(controller.isSearching ? localization.searchPending : localization.searchButton)
        .font(.body.weight(.semibold))
        .frame(minHeight: minimumHitTarget - 10)
    }
    .buttonStyle(.borderedProminent)
    .tint(Color.interactivePrimary)
    .foregroundStyle(Color.interactiveOnPrimary)
    .disabled(controller.isSearching || draft.trimmingCharacters(in: .whitespaces).isEmpty)
    .accessibilityIdentifier("search.submit")
  }

  private func submit() {
    controller.submitSearch(draft)
  }

  @ViewBuilder private var message: some View {
    let text: String? =
      switch (controller.search, controller.location) {
      case (.empty(let query), _): localization.noMatches(query)
      case (.unavailable, _): localization.searchUnavailable
      case (_, .failed(let failure)): localization.locationFailure(failure)
      default: nil
      }
    if let text {
      Text(text)
        .font(.footnote)
        .foregroundStyle(Color.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("origin.message")
        .onAppear { AccessibilityNotification.Announcement(text).post() }
    }
  }

  @ViewBuilder private var matches: some View {
    if case .matches(let matches, let local) = controller.search {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(localization.chooseMatch)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.textPrimary)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("matches.heading")
        if local {
          Text(localization.localMatches)
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
            .accessibilityIdentifier("matches.local")
        }
        ForEach(Array(matches.enumerated()), id: \.element.label) { index, match in
          Button {
            draft = ""
            focus.wrappedValue = false
            controller.choose(match)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(match.title)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
              if !match.context.isEmpty {
                Text(match.context)
                  .font(.footnote)
                  .foregroundStyle(Color.textSecondary)
              }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: minimumHitTarget, alignment: .leading)
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.md)
            .background(Color.surfaceDefault, in: .rect(cornerRadius: Radius.md))
            .overlay {
              RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.borderSubtle)
            }
            .contentShape(.rect(cornerRadius: Radius.md))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(match.label)
          .accessibilityIdentifier("match.\(index)")
        }
        if !local {
          Link(
            localization.searchAttribution,
            destination: URL(string: "https://www.openstreetmap.org/copyright")!
          )
          .font(.footnote)
          .tint(Color.interactivePrimary)
          .accessibilityIdentifier("matches.attribution")
        }
      }
      .padding(.top, Spacing.xs)
    }
  }
}

/// The outside-Finland and land-border notices above the results.
struct CoverageNotice: View {
  let controller: OriginController

  var body: some View {
    let localization = controller.finder.localization
    switch controller.finder.coverage {
    case .covered:
      EmptyView()
    case .border:
      notice {
        Text(localization.borderNotice)
      }
      .accessibilityIdentifier("notice.border")
    case .outside:
      notice {
        Text(localization.outsideFinland)
          .accessibilityIdentifier("notice.outside")
        Button(localization.returnToHelsinki) { controller.returnToHelsinki() }
          .font(.body.weight(.semibold))
          .frame(minHeight: minimumHitTarget)
          .tint(Color.interactivePrimary)
          .accessibilityIdentifier("notice.returnToHelsinki")
      }
    }
  }

  private func notice(@ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      content()
    }
    .font(.subheadline)
    .foregroundStyle(Color.noticeText)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Spacing.md)
    .padding(.horizontal, Spacing.lg)
    .background(Color.noticeSurface, in: .rect(cornerRadius: Radius.md))
    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.noticeBorder))
    .accessibilityElement(children: .contain)
  }
}
