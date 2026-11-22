import CryptoKit
import Foundation
import PharmacyCore
import Testing

struct BundledDataTests {
  private let loader = SyncedFiles.loader

  @Test func decodesTheSnapshot() throws {
    let snapshot = try loader.loadSnapshot()
    let manifest = try loader.loadManifest()
    #expect(snapshot.schemaVersion == 1)
    #expect(snapshot.region == "fi")
    #expect(snapshot.pharmacies.count == manifest.counts["pharmacies"])
    #expect(snapshot.pharmacies.count > 700)
    #expect(Set(snapshot.pharmacies.map(\.id)).count == snapshot.pharmacies.count)
  }

  @Test func snapshotIsSortedByID() throws {
    let ids = try loader.loadSnapshot().pharmacies.map(\.id)
    #expect(zip(ids, ids.dropFirst()).allSatisfy { idPrecedes($0, $1) })
  }

  @Test func decodesTheManifest() throws {
    let manifest = try loader.loadManifest()
    #expect(manifest.region == "fi")
    #expect(manifest.files.pharmacies.path == loader.snapshotFileName)
    #expect(manifest.files.pharmacies.records == manifest.counts["pharmacies"])
    #expect(manifest.interim == (manifest.kind == "overpass-interim"))
    // A PBF import carries the place index; the interim Overpass build does not.
    #expect((manifest.files.places != nil) == !manifest.interim)
    #expect(manifest.ranking.earthRadiusMeters == Haversine.earthMeanRadiusMeters)
    #expect(manifest.licence.notice == "ODbL-NOTICE.txt")
  }

  @Test func filesMatchTheManifestChecksums() throws {
    let manifest = try loader.loadManifest()
    for file in [manifest.files.pharmacies, manifest.files.notice]
      + [manifest.files.places]
      .compactMap({ $0 })
    {
      let data = try loader.data(named: file.path)
      #expect(data.count == file.bytes, "\(file.path)")
      #expect(sha256Hex(data) == file.sha256, "\(file.path)")
    }
  }

  @Test func placeIndexMatchesTheManifest() throws {
    let manifest = try loader.loadManifest()
    let index = try loader.loadPlaceIndex()
    if let places = manifest.files.places {
      let index = try #require(index)
      #expect(index.places.count == places.records)
      #expect(index.places.count == manifest.counts["places"])
    } else {
      #expect(index == nil)
    }
  }

  @Test func licenceNoticeNamesOpenStreetMap() throws {
    let notice = String(decoding: try loader.data(named: "ODbL-NOTICE.txt"), as: UTF8.self)
    #expect(notice.contains("OpenStreetMap"))
  }

  @Test func reportsAMissingFile() {
    let empty = PharmacyDataLoader(directory: SyncedFiles.repositoryRoot, region: "xx")
    #expect(throws: PharmacyDataLoader.LoadError.missingFile("pharmacies.xx.json")) {
      try empty.loadSnapshot()
    }
  }

  private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

struct PharmacyDecodingTests {
  @Test func decodesARecordWithoutNameAddressOrHours() throws {
    let json = Data(#"{"id":"node/7","lat":61,"lon":25}"#.utf8)
    let pharmacy = try JSONDecoder().decode(Pharmacy.self, from: json)
    #expect(pharmacy.id == "node/7")
    #expect(pharmacy.coordinate == Coordinate(lat: 61, lon: 25))
    #expect(pharmacy.name == nil)
    #expect(pharmacy.address == nil)
    #expect(pharmacy.openingHours == nil)
    #expect(pharmacy.pin == nil)
  }

  @Test func fixtureRecordsWithMissingFieldsDecode() throws {
    let byID = Dictionary(uniqueKeysWithValues: fixture.pharmacies.map { ($0.id, $0) })
    let unnamed = try #require(byID["node/7"])
    #expect(unnamed.name == nil && unnamed.address == nil && unnamed.openingHours == nil)
    #expect(try #require(byID["node/11771777459"]).address == nil)
    #expect(try #require(byID["way/402056943"]).openingHours == nil)
  }

  @Test func decodesAFullRecord() throws {
    let json = Data(
      #"""
      {"id":"way/1","name":"Apteekki","lat":60.5,"lon":25.5,"pin":{"lat":60.4,"lon":25.4},
       "address":{"street":"Katu","housenumber":"1","postcode":"00100","city":"Helsinki"},
       "openingHours":"Mo-Fr 09:00-17:00","dispensing":"yes","phone":"+358 1","website":"https://example.org",
       "wheelchair":"yes"}
      """#.utf8)
    let pharmacy = try JSONDecoder().decode(Pharmacy.self, from: json)
    #expect(pharmacy.pin == Coordinate(lat: 60.4, lon: 25.4))
    #expect(pharmacy.address?.city == "Helsinki")
    #expect(pharmacy.address?.housenumber == "1")
    #expect(pharmacy.wheelchair == "yes")
  }

  @Test func decodesAPlaceIndex() throws {
    let json = Data(
      #"""
      {"schemaVersion":1,"region":"fi","places":[
        {"id":"relation/1","name":"Helsinki","nameSv":"Helsingfors","type":"municipality","lat":60.17,"lon":24.94},
        {"id":"node/2","name":"Ivalo","type":"village","lat":68.66,"lon":27.54,"municipality":"Inari"}]}
      """#.utf8)
    let index = try JSONDecoder().decode(PlaceIndex.self, from: json)
    #expect(index.places.map(\.type) == [.municipality, .village])
    #expect(index.places[0].nameSv == "Helsingfors")
    #expect(index.places[0].municipality == nil)
    #expect(index.places[1].nameSv == nil)
  }
}
