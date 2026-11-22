import Foundation
import MapKit
import PharmacyCore
import SwiftUI
import Testing

@testable import NearbyPharmacies

@MainActor
struct PharmacyFinderTests {
  private func finder(_ language: String = "en") -> PharmacyFinder {
    PharmacyFinder(
      localization: AppLocalization(preferredLanguages: [language], region: .finland))
  }

  @Test func ranksTheTwentyNearestFromHelsinkiCentral() {
    let finder = finder()
    #expect(finder.origin == .helsinkiCentral)
    #expect(finder.results.count == 20)
    #expect(finder.datasetCount == 784)
    #expect(finder.results.first?.name == "Steissin Apteekki")
    #expect(finder.results.first?.id == "node/1369465553")
    #expect(
      finder.results.map(\.name).prefix(4) == [
        "Steissin Apteekki", "Apteekki CityCenter", "Yliopiston apteekki", "Kluuvin apteekki",
      ])
    let distances = finder.results.map(\.distanceMeters)
    #expect(distances == distances.sorted())
    #expect(finder.selectedID == nil)
    #expect(!finder.showsDetails)
  }

  @Test func labelsFollowTheInterfaceLanguage() {
    #expect(
      finder("en").results.first?.accessibilityLabel == "Steissin Apteekki, 50 m straight line")
    #expect(finder("fi").results.first?.accessibilityLabel == "Steissin Apteekki, 50 m linnuntietä")
    #expect(finder("fi").originLabel == "Helsingin päärautatieasema (oletus)")
  }

  @Test func selectionShowsDetailsAndSurvivesReturningToTheList() {
    let finder = finder()
    let kluuvi = "node/4727972444"
    finder.select(kluuvi)
    #expect(finder.selectedID == kluuvi)
    #expect(finder.selected?.name == "Kluuvin apteekki")
    #expect(finder.showsDetails)
    #expect(finder.selectionCount == 1)
    #expect(finder.origin == .helsinkiCentral)

    finder.backToResults()
    #expect(!finder.showsDetails)
    #expect(finder.selectedID == kluuvi)

    // Choosing the same pharmacy again still counts, so the map refits.
    finder.select(kluuvi)
    #expect(finder.selectionCount == 2)
  }

  @Test func ignoresPharmaciesOutsideTheResults() {
    let finder = finder()
    finder.select("node/does-not-exist")
    #expect(finder.selectedID == nil)
    #expect(!finder.showsDetails)
  }

  @Test func nearestResultWithoutAddressOrHours() throws {
    let kaarti = try #require(finder().results.first { $0.name == "Kaartin Apteekki" })
    #expect(kaarti.pharmacy.addressLines.isEmpty)
    #expect(kaarti.pharmacy.openingHours == nil)
  }
}

struct MapFitTests {
  @Test func fitsPointsInsideTheUncoveredArea() throws {
    let a = CLLocationCoordinate2D(latitude: 60.17, longitude: 24.93)
    let b = CLLocationCoordinate2D(latitude: 60.19, longitude: 24.96)
    let size = CGSize(width: 400, height: 800)
    let insets = EdgeInsets(top: 100, leading: 40, bottom: 300, trailing: 40)
    let rect = try #require(MapFit.rect(fitting: [a, b], viewSize: size, insets: insets))
    // The rect has the view's aspect ratio, so MapKit shows it as computed.
    #expect(abs(rect.size.width / rect.size.height - size.width / size.height) < 1e-9)
    for point in [a, b].map(MKMapPoint.init) {
      let x = (point.x - rect.minX) / rect.width * size.width
      let y = (point.y - rect.minY) / rect.height * size.height
      #expect(x >= insets.leading - 0.001 && x <= size.width - insets.trailing + 0.001)
      #expect(y >= insets.top - 0.001 && y <= size.height - insets.bottom + 0.001)
    }
  }

  @Test func keepsAMinimumSpanForOnePoint() throws {
    let a = CLLocationCoordinate2D(latitude: 60.17, longitude: 24.93)
    let rect = try #require(
      MapFit.rect(
        fitting: [a], viewSize: CGSize(width: 400, height: 800), insets: EdgeInsets(),
        minimumSpanMeters: 400))
    let meters = rect.width / MKMapPointsPerMeterAtLatitude(a.latitude)
    #expect(meters >= 399)
  }
}
