import SwiftUI

/// The content of the results sheet: the origin search and summary, notices and the list, or the
/// details of the selection with "Back to results". VoiceOver reads the origin, the notices, then
/// the results.
struct ResultsSheet: View {
  let controller: OriginController
  /// Reports whether the search field has focus, so the sheet can make room for the keyboard.
  var onSearchFocusChange: (Bool) -> Void = { _ in }
  @AccessibilityFocusState private var focus: FocusTarget?
  @FocusState private var searchFocused: Bool
  @State private var draft = ""
  @State private var showsLocationOffer = false

  private var finder: PharmacyFinder { controller.finder }

  private enum FocusTarget: Hashable {
    case detailsName
    case row(String)
  }

  var body: some View {
    Group {
      if finder.showsDetails, let selected = finder.selected {
        details(selected)
      } else {
        list
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.surfaceDefault)
    .onChange(of: searchFocused) { onSearchFocusChange(searchFocused) }
    .onChange(of: controller.isLocating) {
      if controller.isLocating {
        AccessibilityNotification.Announcement(finder.localization.locationPending).post()
      }
    }
    // The offer follows the first results, and the system prompt only follows the offer.
    .task {
      try? await Task.sleep(for: .seconds(1))
      if controller.offersLocation { showsLocationOffer = true }
    }
    .alert(
      finder.localization.locationPromptTitle,
      isPresented: Binding(
        get: { showsLocationOffer },
        set: { showsLocationOffer = $0 }
      )
    ) {
      Button(finder.localization.locationPromptAccept) {
        controller.requestLocation()
      }
      Button(finder.localization.locationPromptDismiss, role: .cancel) {
        controller.dismissLocationOffer()
      }
    } message: {
      Text(finder.localization.locationPromptBody)
    }
  }

  // MARK: - List

  private var list: some View {
    let localization = finder.localization
    return ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
          header
          CoverageNotice(controller: controller)
          resultsHeading
          LazyVStack(spacing: Spacing.sm) {
            ForEach(finder.results) { result in
              ResultRow(result: result, isSelected: result.id == finder.selectedID) {
                finder.select(result.id)
              }
              .id(result.id)
              .accessibilityFocused($focus, equals: .row(result.id))
            }
          }
          Text(localization.mapAttribution)
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("attribution")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
      }
      .scrollBounceBehavior(.basedOnSize)
      .onAppear {
        // Returning from the details: show and focus the selected row.
        guard let id = finder.selectedID else { return }
        proxy.scrollTo(id)
        focus = .row(id)
      }
      .onChange(of: finder.originChangeCount) {
        // New results start from the top, below the origin.
        withAnimation { proxy.scrollTo(Self.topID, anchor: .top) }
      }
    }
  }

  private static let topID = "sheet.top"

  private var header: some View {
    let localization = finder.localization
    return VStack(alignment: .leading, spacing: Spacing.md) {
      OriginSearch(controller: controller, draft: $draft, focus: $searchFocused)
      HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
        Circle()
          .fill(Color.originMarker)
          .frame(width: 10, height: 10)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
          Text(localization.originCaption)
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
          Text(finder.originTitle)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .accessibilityIdentifier("origin.label")
          if let context = finder.originContext {
            Text(context)
              .font(.footnote)
              .foregroundStyle(Color.textSecondary)
          }
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("origin")
    }
    .id(Self.topID)
    .fixedSize(horizontal: false, vertical: true)
    // Like a navigation bar, the header stops growing at the largest standard size so the medium
    // detent still shows a full result at accessibility sizes. Rows and details scale fully.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private var resultsHeading: some View {
    let localization = finder.localization
    return VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(localization.resultsTitle)
        .font(.title3.weight(.semibold))
        .foregroundStyle(Color.textPrimary)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("results.title")
      Text(localization.scopeAndCount(finder.datasetCount))
        .font(.footnote)
        .foregroundStyle(Color.textSecondary)
        .accessibilityIdentifier("results.scope")
    }
    .fixedSize(horizontal: false, vertical: true)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  // MARK: - Details

  private func details(_ selected: PharmacyResult) -> some View {
    let localization = finder.localization
    return VStack(spacing: 0) {
      HStack {
        Button {
          finder.backToResults()
        } label: {
          Label(localization.backToResults, systemImage: "chevron.backward")
            .font(.body.weight(.medium))
            .frame(minHeight: minimumHitTarget)
        }
        .tint(Color.interactivePrimary)
        .accessibilityIdentifier("details.back")
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.top, Spacing.md)

      ScrollView {
        PharmacyDetails(result: selected, localization: localization)
          .padding(.horizontal, Spacing.lg)
          .padding(.top, Spacing.sm)
          .padding(.bottom, Spacing.xl)
          .accessibilityFocused($focus, equals: .detailsName)
      }
      .scrollBounceBehavior(.basedOnSize)
      // Selecting another pharmacy replaces the details and starts from the top.
      .id(selected.id)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(localization.detailsLabel)
    .accessibilityIdentifier("details")
    .onAppear { focus = .detailsName }
    .onChange(of: selected.id) { focus = .detailsName }
  }
}

/// One result: a single button read as "{name}, {distance} straight line" that exposes its
/// selected state. The name wraps; it is never truncated.
struct ResultRow: View {
  let result: PharmacyResult
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(result.name)
          .font(.headline)
          .foregroundStyle(Color.textPrimary)
        Text(result.straightLine)
          .font(.subheadline)
          .foregroundStyle(Color.textSecondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, minHeight: minimumHitTarget, alignment: .leading)
      .padding(.vertical, Spacing.md)
      .padding(.horizontal, Spacing.lg)
      .background(
        isSelected ? Color.selectionSurface : Color.surfaceDefault,
        in: .rect(cornerRadius: Radius.md)
      )
      .overlay {
        RoundedRectangle(cornerRadius: Radius.md)
          .strokeBorder(
            isSelected ? Color.selectionBorder : Color.borderSubtle, lineWidth: isSelected ? 2 : 1)
      }
      .contentShape(.rect(cornerRadius: Radius.md))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(result.accessibilityLabel)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("row.\(result.id)")
  }
}
