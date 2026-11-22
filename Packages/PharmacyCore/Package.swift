// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "PharmacyCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "PharmacyCore", targets: ["PharmacyCore"])
  ],
  targets: [
    .target(name: "PharmacyCore"),
    // The tests read the synced data and ranking fixture from the app and unit-test folders of
    // this repository, so the package keeps no second copy of them. See AGENTS.md.
    .testTarget(name: "PharmacyCoreTests", dependencies: ["PharmacyCore"]),
  ]
)
