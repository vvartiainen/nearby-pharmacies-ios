import MapKit
import PharmacyCore
import SwiftUI

/// The full-screen map: the origin marker, a pin per result and, for a selection, a dashed straight
/// line from the origin to the selected pin. Pins are buttons that select their pharmacy.
struct PharmacyMap: View {
  let finder: PharmacyFinder
  @Binding var position: MapCameraPosition

  var body: some View {
    let localization = finder.localization
    Map(position: $position) {
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
          .accessibilityLabel("\(localization.originCaption): \(finder.originLabel)")
          .accessibilityIdentifier("map.origin")
      }
      .annotationTitles(.hidden)
      if let selected = finder.selected {
        pin(for: selected, isSelected: true)
      }
    }
    // Apple's own pharmacy places would look like results that are not in the ranking.
    .mapStyle(.standard(pointsOfInterest: .excluding([.pharmacy])))
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .accessibilityLabel(localization.mapLabel)
  }

  private func pin(for result: PharmacyResult, isSelected: Bool) -> some MapContent {
    Annotation(result.name, coordinate: result.pharmacy.pinCoordinate.location, anchor: .bottom) {
      Button {
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
