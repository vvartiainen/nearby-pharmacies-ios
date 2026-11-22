import Foundation
import PharmacyCore
import Testing

/// The synced street address index and the lookup rules shared with the web app.
@Suite struct AddressIndexTests {
  private let tampere = Coordinate(lat: 61.4983, lon: 23.7732)

  private func shards(near point: Coordinate) throws -> [AddressIndex.Shard] {
    try AddressIndex.cells(near: point).sorted().compactMap { cell in
      let url = SyncedFiles.addressIndexDirectory.appending(path: "\(cell).json.gz")
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      return try AddressIndex.decodeShard(Data(contentsOf: url))
    }
  }

  @Test func namesCellsAsTheWebAppDoes() {
    #expect(AddressIndex.cell(lat: 61.4983, lon: 23.7732) == "122-23")
    #expect(AddressIndex.cell(lat: 60.1720965, lon: 24.9412486) == "120-24")
    #expect(AddressIndex.cells(near: tampere) == ["122-23"])
    // Within 120 m of a cell edge, the neighbouring cell is read too.
    #expect(AddressIndex.cells(near: Coordinate(lat: 60.4995, lon: 24.9995)).count == 4)
  }

  @Test func findsTheSameAddressAsTheWebAppForTampere() throws {
    let address = AddressIndex.nearest(to: tampere, in: try shards(near: tampere))
    #expect(address == AddressIndex.Address(street: "Rautatienkatu 25", city: "Tampere"))
  }

  @Test func findsNothingFartherThan120Metres() throws {
    // Open sea south of Helsinki.
    let sea = Coordinate(lat: 60.05, lon: 24.9)
    #expect(AddressIndex.nearest(to: sea, in: try shards(near: sea)) == nil)
  }

  @Test func skipsAddressesTheCoverageRejects() throws {
    let address = AddressIndex.nearest(to: tampere, in: try shards(near: tampere)) { _ in true }
    #expect(address == nil)
  }

  @Test(arguments: [(0.0, true), (120, true), (121, false), (-1, false), (.infinity, false)])
  func acceptsOnlyFixesWithin120Metres(accuracy: Double, accepted: Bool) {
    #expect(AddressIndex.accepts(accuracy: accuracy) == accepted)
  }

  @Test func readsEveryShardListedInTheIndex() throws {
    let index = try JSONDecoder().decode(
      [String].self,
      from: Data(contentsOf: SyncedFiles.addressIndexDirectory.appending(path: "index.json")))
    #expect(index.count > 100)
    for cell in index {
      let data = try Data(
        contentsOf: SyncedFiles.addressIndexDirectory.appending(path: "\(cell).json.gz"))
      #expect(try !AddressIndex.decodeShard(data).streets.isEmpty, "\(cell)")
    }
  }
}
