import MapKit
import SwiftUI
import UIKit

/// The full-screen map with the results sheet over it.
struct ContentView: View {
  let finder: PharmacyFinder

  @State private var position: MapCameraPosition = .region(
    MKCoordinateRegion(
      center: Origin.helsinkiCentral.coordinate.location,
      latitudinalMeters: 3_000, longitudinalMeters: 3_000))
  @State private var detent: PresentationDetent
  /// Size of the full-screen map and the status bar height above it.
  @State private var mapSize: CGSize = .zero
  @State private var safeAreaTop: CGFloat = 0
  /// Top edge of the sheet in screen coordinates, once it is laid out.
  @State private var sheetTop: CGFloat?
  @State private var didInitialFit = false
  @State private var didChooseInitialDetent = false
  private let accessibilityTextSize: Bool

  /// Below this screen height the medium detent cannot show the header and a full result at
  /// accessibility text sizes, for example on iPhone SE.
  private static let shortScreenHeight: CGFloat = 800

  init(finder: PharmacyFinder) {
    self.finder = finder
    // At accessibility text sizes the sheet opens at the medium detent so at least one full row
    // shows, or at the large detent on short screens. Otherwise it opens at the peek detent: the
    // header and the nearest result.
    accessibilityTextSize =
      UIApplication.shared.preferredContentSizeCategory
      .isAccessibilityCategory
    _detent = State(initialValue: accessibilityTextSize ? .medium : .peek)
  }

  var body: some View {
    GeometryReader { proxy in
      PharmacyMap(finder: finder, position: $position)
        // Keeps MapKit's legal notice and the scale above the sheet. The padding applies inside
        // the full-screen frame, so it has to come before `ignoresSafeArea`.
        .safeAreaPadding(.bottom, mapBottomInset)
        .ignoresSafeArea()
        .onChange(of: proxy.size, initial: true) {
          let insets = proxy.safeAreaInsets
          safeAreaTop = insets.top
          mapSize = CGSize(
            width: proxy.size.width + insets.leading + insets.trailing,
            height: proxy.size.height + insets.top + insets.bottom)
          chooseInitialDetent()
          fitInitially()
        }
    }
    .sheet(isPresented: .constant(true)) {
      ResultsSheet(finder: finder)
        .onGeometryChange(for: CGFloat.self) {
          $0.frame(in: .global).minY
        } action: {
          sheetTop = $0
          fitInitially()
        }
        .presentationDetents([.peek, .medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        // Like Maps: dragging the list first moves the sheet to the next detent, then scrolls.
        .presentationContentInteraction(.resizes)
        .presentationBackground(Color.surfaceDefault)
        .interactiveDismissDisabled()
    }
    .onChange(of: finder.selectionCount) { fitSelection() }
  }

  private func chooseInitialDetent() {
    guard !didChooseInitialDetent, mapSize.height > 0 else { return }
    didChooseInitialDetent = true
    if accessibilityTextSize && mapSize.height < Self.shortScreenHeight {
      detent = .large
    }
  }

  /// Fits the origin and the nearest results once the map and the sheet have their sizes.
  private func fitInitially() {
    guard !didInitialFit, let sheetTop, sheetTop > 0, mapSize.height > 0 else { return }
    didInitialFit = true
    let points =
      [finder.origin.coordinate.location]
      + finder.results.map { $0.pharmacy.pinCoordinate.location }
    fit(points, animated: false)
  }

  /// Fits the origin and the selected pin above the sheet, which keeps its detent.
  private func fitSelection() {
    guard let selected = finder.selected else { return }
    fit(
      [finder.origin.coordinate.location, selected.pharmacy.pinCoordinate.location],
      animated: true)
  }

  /// How much of the map the sheet covers from the bottom.
  private var coveredHeight: CGFloat {
    guard let sheetTop, mapSize.height > 0 else { return 0 }
    return max(0, mapSize.height - sheetTop)
  }

  /// The bottom of the map the sheet hides, for MapKit's legal notice and for fitting points.
  /// Above the medium detent the map is mostly hidden, so the inset stops growing: the notice
  /// does not climb into the status bar and fits keep a usable area.
  private var mapBottomInset: CGFloat {
    min(coveredHeight, mapSize.height * 0.6)
  }

  private func fit(_ points: [CLLocationCoordinate2D], animated: Bool) {
    // Room for a selected pin above its point and half a pin at the sides.
    let insets = EdgeInsets(
      top: safeAreaTop + 64, leading: 40, bottom: mapBottomInset + 24, trailing: 40)
    guard let rect = MapFit.rect(fitting: points, viewSize: mapSize, insets: insets) else { return }
    if animated {
      withAnimation(.easeInOut(duration: 0.35)) { position = .rect(rect) }
    } else {
      position = .rect(rect)
    }
  }
}

extension PresentationDetent {
  /// The sheet's smallest detent: the header and the nearest result.
  static let peek = Self.custom(PeekDetent.self)
}

/// The header and one result row at the current text size. The heights follow the default
/// layout at the Large text size and scale with Dynamic Type.
private struct PeekDetent: CustomPresentationDetent {
  static func height(in context: Context) -> CGFloat? {
    let category = UIContentSizeCategory(context.dynamicTypeSize)
    let traits = UITraitCollection(preferredContentSizeCategory: category)
    // Top padding and spacing do not scale; the text lines do.
    let fixed: CGFloat = 24 + 12 + 16 + 24 + 8
    let text = UIFontMetrics.default.scaledValue(for: 112, compatibleWith: traits)
    return min(fixed + text, context.maxDetentValue * 0.6)
  }
}

#Preview("English") {
  ContentView(
    finder: PharmacyFinder(
      localization: AppLocalization(preferredLanguages: ["en"], region: .finland)))
}

#Preview("Finnish") {
  ContentView(
    finder: PharmacyFinder(
      localization: AppLocalization(preferredLanguages: ["fi"], region: .finland)))
}
