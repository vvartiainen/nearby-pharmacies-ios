import PharmacyCore
import SwiftUI

struct ResultsSheet: View {
  let controller: OriginController
  var onSearchFocusChange: (Bool) -> Void = { _ in }
  var onClosedHeightChange: (CGFloat) -> Void = { _ in }
  var isClosed = false
  var onOpen: () -> Void = {}
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
        if isClosed {
          closedSelection(selected)
        } else {
          details(selected)
        }
      } else {
        list
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.surfaceDefault)
    .onChange(of: searchFocused) {
      // Leaving the field without a search in progress shows the starting point again, as on web.
      if !searchFocused, controller.search == .idle { draft = "" }
      onSearchFocusChange(searchFocused)
    }
    .onChange(of: finder.originChangeCount) {
      draft = ""
      searchFocused = false
    }
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
        .padding(.top, Self.topPadding)
        .padding(.bottom, Spacing.lg)
        // The scroll target is the padded content, so scrolling to it keeps the space above the
        // search field.
        .id(Self.topID)
      }
      .scrollBounceBehavior(.basedOnSize)
      .onAppear {
        guard let id = finder.selectedID else { return }
        proxy.scrollTo(id)
        focus = .row(id)
      }
      .onChange(of: finder.originChangeCount) {
        withAnimation { proxy.scrollTo(Self.topID, anchor: .top) }
      }
    }
  }

  private static let topID = "sheet.top"
  static let topPadding = Spacing.xl
  private static let detailsMaxWidth: CGFloat = 448

  private var header: some View {
    OriginSearch(controller: controller, draft: $draft, focus: $searchFocused) { fieldHeight in
      onClosedHeightChange(Self.topPadding + fieldHeight + Spacing.lg)
    }
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

  private func closedSelection(_ selected: PharmacyResult) -> some View {
    Button(action: onOpen) {
      HStack(alignment: .center, spacing: Spacing.md) {
        Text(selected.name)
          .font(.headline)
          .foregroundStyle(Color.textPrimary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(selected.distance)
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .foregroundStyle(selected.band.color)
          .fixedSize()
        Image(systemName: "chevron.up")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color.textSecondary)
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.top, Self.topPadding)
      .padding(.bottom, Spacing.lg)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(selected.rowAccessibilityLabel)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("details.summary")
  }

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

      // As in the narrow web drawer, the details form a block sized to its content, at most
      // 28rem wide, centred in the space below "Back to results" when it fits and scrolling from
      // the top when it is taller.
      GeometryReader { space in
        ScrollView {
          PharmacyDetails(result: selected, localization: localization)
            .frame(maxWidth: Self.detailsMaxWidth)
            .accessibilityFocused($focus, equals: .detailsName)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: space.size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
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

struct ResultRow: View {
  let result: PharmacyResult
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: Spacing.md) {
        Text(result.name)
          .font(.headline)
          .foregroundStyle(Color.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(result.distance)
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .foregroundStyle(result.band.color)
          .fixedSize()
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(.vertical, Spacing.md)
      .padding(.horizontal, Spacing.lg)
      .frame(maxWidth: .infinity, minHeight: minimumHitTarget, alignment: .leading)
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
    .accessibilityLabel(result.rowAccessibilityLabel)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("row.\(result.id)")
  }
}

extension DistanceFormatting.Band {
  var color: Color {
    switch self {
    case .near: .distanceNear
    case .medium: .distanceMedium
    case .far: .distanceFar
    }
  }
}
