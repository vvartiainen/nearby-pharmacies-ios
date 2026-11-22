import PharmacyCore
import SwiftUI

struct OriginSearch: View {
  let controller: OriginController
  @Binding var draft: String
  var focus: FocusState<Bool>.Binding
  /// Reports the height of the field and the Search button, which the closed sheet shows.
  var onFieldHeight: (CGFloat) -> Void = { _ in }

  private var localization: AppLocalization { controller.finder.localization }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.sm) {
        field
        submitButton
      }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        onFieldHeight($0)
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

  private var showsOrigin: Bool { !focus.wrappedValue && draft.isEmpty }

  private var field: some View {
    let finder = controller.finder
    return HStack(spacing: Spacing.xs) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Color.textSecondary)
        .accessibilityHidden(true)
      ZStack(alignment: .leading) {
        TextField(
          localization.searchLabel, text: $draft,
          prompt: showsOrigin ? Text(verbatim: "") : Text(localization.searchLabel)
        )
        .focused(focus)
        .submitLabel(.search)
        .onSubmit(submit)
        .autocorrectionDisabled()
        .foregroundStyle(Color.textPrimary)
        .accessibilityValue(showsOrigin ? finder.originFieldLabel : draft)
        .accessibilityIdentifier("search.field")
        if showsOrigin {
          VStack(alignment: .leading, spacing: 0) {
            // Two lines at most, so the closed sheet stays small on narrow screens. The full
            // label stays available to VoiceOver through the field's value.
            Text(finder.originTitle)
              .font(.body)
              .foregroundStyle(Color.textPrimary)
              .lineLimit(2)
              .minimumScaleFactor(0.85)
            if let context = finder.originContext {
              Text(context)
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(Color.textSecondary)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.pageBackground)
          .accessibilityHidden(true)
          .allowsHitTesting(false)
          .accessibilityIdentifier("search.origin")
        }
      }
      .padding(.vertical, Spacing.sm)
      locationButton
    }
    .padding(.leading, Spacing.md)
    .frame(minHeight: minimumHitTarget)
    .background(Color.pageBackground, in: .rect(cornerRadius: Radius.md))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.md)
        .strokeBorder(focus.wrappedValue ? Color.focusRing : Color.borderSubtle)
    }
    // The summary can be taller than the text line, so the whole field focuses the text.
    .contentShape(.rect(cornerRadius: Radius.md))
    .onTapGesture { focus.wrappedValue = true }
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
