import MapKit
import PharmacyCore
import SwiftUI

/// The full-screen map: the origin marker, a pin per result and, for a selection, a dashed straight
/// line from the origin to the selected pin. Pins are buttons that select their pharmacy.
/// Touching and holding the map chooses a new starting point. "Choose on map" shows a target at
/// the centre of the visible map; the user pans under it and confirms with "Search from here".
/// Panning or zooming alone never offers a starting point.
struct PharmacyMap: View {
  let finder: PharmacyFinder
  @Binding var position: MapCameraPosition
  /// The centre of the part of the map the sheet leaves visible, in the map's coordinates.
  var pickPoint: CGPoint
  /// The status bar height: the map buttons sit below it.
  var topInset: CGFloat
  var onPick: (Coordinate) -> Void = { _ in }
  /// Reports the visible map rect when the camera stops moving.
  var onCameraChange: (MKMapRect) -> Void = { _ in }
  /// From "Choose on map" until "Search from here", "Cancel", a new origin or a selection.
  @State private var isPicking = false
  /// A touch and hold on a pin chooses the point, so the tap that ends it must not also select
  /// the pharmacy.
  @State private var lastPick: ContinuousClock.Instant?

  var body: some View {
    MapReader { proxy in
      map
        .gesture(MapLongPress { point in pick(point, proxy) })
        .onChange(of: finder.originChangeCount) { setPicking(false) }
        .onChange(of: finder.selectionCount) { setPicking(false) }
        .overlay {
          if isPicking { target }
        }
        .overlay(alignment: .top) { pickControl(proxy) }
        .accessibilityAction(named: finder.localization.searchFromHere) {
          pick(pickPoint, proxy)
        }
        .accessibilityHint(finder.localization.mapPickHint)
    }
  }

  private func pick(_ point: CGPoint, _ proxy: MapProxy) {
    guard let coordinate = proxy.convert(point, from: .local) else { return }
    setPicking(false)
    lastPick = .now
    onPick(Coordinate(lat: coordinate.latitude, lon: coordinate.longitude))
  }

  private func setPicking(_ picking: Bool) {
    guard picking != isPicking else { return }
    withAnimation(.snappy(duration: 0.25)) { isPicking = picking }
  }

  /// One capsule at the top centre, below the status bar: "Choose on map" turns into
  /// "Search from here", and a round Cancel button slides in beside it.
  private func pickControl(_ proxy: MapProxy) -> some View {
    let localization = finder.localization
    return HStack(spacing: Spacing.sm) {
      Button {
        if isPicking { pick(pickPoint, proxy) } else { setPicking(true) }
      } label: {
        Label(
          isPicking ? localization.searchFromHere : localization.chooseOnMap,
          systemImage: isPicking ? "scope" : "mappin.and.ellipse"
        )
        .contentTransition(.opacity)
        .padding(.horizontal, isPicking ? Spacing.lg : Spacing.md)
        .frame(minHeight: minimumHitTarget)
        .foregroundStyle(isPicking ? Color.interactiveOnPrimary : Color.interactivePrimary)
        .background(isPicking ? Color.interactivePrimary : Color.surfaceDefault, in: .capsule)
        .overlay(Capsule().strokeBorder(isPicking ? Color.clear : Color.borderStrong))
        .contentShape(.capsule)
      }
      .accessibilityIdentifier(isPicking ? "map.searchHere" : "map.chooseOnMap")
      if isPicking {
        Button {
          setPicking(false)
        } label: {
          Image(systemName: "xmark")
            .font(.body.weight(.semibold))
            .frame(width: minimumHitTarget, height: minimumHitTarget)
            .foregroundStyle(Color.textPrimary)
            .background(Color.surfaceDefault, in: .circle)
            .overlay(Circle().strokeBorder(Color.borderStrong))
            .contentShape(.circle)
        }
        .accessibilityLabel(localization.cancelMapPick)
        .accessibilityIdentifier("map.cancelPick")
        .transition(.scale(scale: 0.5).combined(with: .opacity))
      }
    }
    .buttonStyle(.plain)
    .font(.subheadline.weight(.semibold))
    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    .padding(.top, topInset + Spacing.sm)
    .padding(.horizontal, Spacing.md)
  }

  /// The target at the point "Search from here" uses.
  private var target: some View {
    Image(systemName: "plus.circle")
      .font(.title2.weight(.light))
      .foregroundStyle(Color.selectionLine)
      .background(Circle().fill(.white.opacity(0.7)))
      .position(pickPoint)
      .accessibilityHidden(true)
      .allowsHitTesting(false)
      .transition(.scale(scale: 0.6).combined(with: .opacity))
  }

  private var map: some View {
    let localization = finder.localization
    return Map(position: $position) {
      if let selected = finder.selected {
        let line = [finder.origin.coordinate, selected.pharmacy.pinCoordinate].map(\.location)
        MapPolyline(coordinates: line)
          .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [7, 6]))
        MapPolyline(coordinates: line)
          .stroke(
            Color.selectionLine, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 6]))
      }

      // The origin draws above the pins next to it, and the selected pin above everything.
      ForEach(finder.results.filter { $0.id != finder.selectedID }) { result in
        pin(for: result, isSelected: false)
      }
      Annotation(
        localization.originCaption, coordinate: finder.origin.coordinate.location, anchor: .center
      ) {
        // Drawn above nearby pins for visibility. The annotation itself is tiny and the marker
        // overflows it, so taps around the origin reach the pin underneath.
        Color.clear
          .frame(width: 2, height: 2)
          .overlay { OriginMarker().allowsHitTesting(false) }
          .accessibilityElement()
          .accessibilityLabel(
            Text(verbatim: "\(localization.originCaption): \(finder.originLabel)")
          )
          .accessibilityIdentifier("map.origin")
      }
      .annotationTitles(.hidden)
      if let selected = finder.selected {
        pin(for: selected, isSelected: true)
      }
    }
    // Apple's own pharmacy places would look like results that are not in the ranking.
    .mapStyle(.standard(pointsOfInterest: .excluding([.pharmacy])))
    .onMapCameraChange(frequency: .onEnd) { onCameraChange($0.rect) }
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .accessibilityLabel(localization.mapLabel)
  }

  private func pin(for result: PharmacyResult, isSelected: Bool) -> some MapContent {
    Annotation(result.name, coordinate: result.pharmacy.pinCoordinate.location, anchor: .bottom) {
      Button {
        if let lastPick, ContinuousClock.now - lastPick < .seconds(1) { return }
        finder.select(result.id)
      } label: {
        PharmacyPin(isSelected: isSelected)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(result.accessibilityLabel)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityIdentifier("pin.\(result.id)")
    }
    .annotationTitles(.hidden)
  }
}

/// Touch and hold: reports the point once the press is recognized. It works alongside the map's
/// own pan and zoom gestures.
struct MapLongPress: UIGestureRecognizerRepresentable {
  let action: (CGPoint) -> Void

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

  func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
    let recognizer = UILongPressGestureRecognizer()
    recognizer.minimumPressDuration = 0.5
    recognizer.delegate = context.coordinator
    return recognizer
  }

  func handleUIGestureRecognizerAction(
    _ recognizer: UILongPressGestureRecognizer, context: Context
  ) {
    guard recognizer.state == .began else { return }
    action(context.converter.localLocation)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
  }
}

extension Coordinate {
  var location: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }
}

/// Fits points into the part of the map the sheet leaves visible.
enum MapFit {
  /// The map rect to show so that `coordinates` fit in the view area left inside `insets`.
  /// `viewSize` is the whole map view; the insets cover the status bar, the sheet and room for pins.
  /// Very close points keep at least `minimumSpanMeters` across.
  static func rect(
    fitting coordinates: [CLLocationCoordinate2D], viewSize: CGSize, insets: EdgeInsets,
    minimumSpanMeters: Double = 150
  ) -> MKMapRect? {
    guard !coordinates.isEmpty, viewSize.width > 0, viewSize.height > 0 else { return nil }
    let points = coordinates.map(MKMapPoint.init)
    var minX = points.map(\.x).min()!
    var maxX = points.map(\.x).max()!
    var minY = points.map(\.y).min()!
    var maxY = points.map(\.y).max()!

    let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    let minimumSpan = minimumSpanMeters * MKMapPointsPerMeterAtLatitude(center.coordinate.latitude)
    if maxX - minX < minimumSpan {
      minX = center.x - minimumSpan / 2
      maxX = center.x + minimumSpan / 2
    }
    if maxY - minY < minimumSpan {
      minY = center.y - minimumSpan / 2
      maxY = center.y + minimumSpan / 2
    }

    let available = CGSize(
      width: max(1, viewSize.width - insets.leading - insets.trailing),
      height: max(1, viewSize.height - insets.top - insets.bottom))
    // Map points per screen point.
    let scale = max((maxX - minX) / available.width, (maxY - minY) / available.height)
    let originX = (minX + maxX) / 2 - (insets.leading + available.width / 2) * scale
    let originY = (minY + maxY) / 2 - (insets.top + available.height / 2) * scale
    return MKMapRect(
      x: originX, y: originY, width: viewSize.width * scale, height: viewSize.height * scale)
  }
}
