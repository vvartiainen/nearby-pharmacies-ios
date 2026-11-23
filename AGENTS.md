# Nearby Pharmacies iOS

A native SwiftUI app that finds the nearest mapped pharmacies in Finland. Product
decisions are summarised in `README.md`; the ADRs and the data importer live in the web
repository (`nearby-pharmacies-web`), and the shared design spec is `docs/design/design-spec.md`. The app shows a full-screen MapKit map with a native results
sheet with three detents: closed (the search field only), medium (where it opens) and large.
It ranks the bundled snapshot from the labeled default origin, Helsinki Central
Railway Station, and shows the 20 nearest. The origin marker, pins, rows and details stay in
sync: selecting a row or a pin selects both, draws a dashed line from the origin and shows
the name, distance, address and opening hours (or their fallbacks) centred in the sheet, which
keeps a medium detent (a closed or full sheet comes to medium). The starting point can also come from a submitted city or address search
(public Nominatim, with the bundled Finnish and Swedish place names as fallback), the device
location (asked for only after the Helsinki results show) or a point chosen on the map, with
outside-Finland and land-border notices.

## Origin search and location

- Search sends only the submitted text, the interface language and the `fi` country filter
  to the geocoder in `NearbyPharmacies/Resources/geocoder.json` (a copy of the web app's
  `public/geocoder.json`). There is no autocomplete and no retry; `NominatimGeocoder` keeps at
  most one request in flight, at most one a second, and a session cache. Device coordinates
  never leave the device.
- The geocoder User-Agent identifies the app with its GitHub repository URL. See the
  [reviewer demo](README.md#reviewer-demo) for provider configuration and fallback behavior.
- Location uses foreground Core Location (When In Use) with a 10 second timeout. The app offers
  it once after the first results; the system prompt follows only "Use location" or "Use my
  location". Choosing another origin while a request runs makes its fix irrelevant.
- A device fix is labelled "Your location" and a point chosen on the map is labelled
  "Dropped pin". The app ranks from those coordinates on the device.
- Touch and hold the map to choose a point. Panning or zooming only moves the map. "Choose on
  map" shows a target at the centre of the map above the sheet, with "Search from here" and
  "Cancel"; a new origin or a selection also ends it. VoiceOver users get "Search from here" as
  a map action.
- Map fits (the first results, a new origin, a selection) frame the points inside the map's
  safe area, which the sheet already shortens through `safeAreaPadding`, so the sheet height is
  not subtracted twice.
- UI tests launch with `-UITesting` and scripted answers (`NearbyPharmacies/Testing/ScriptedServices.swift`); the app
  then never contacts the geocoder or Core Location.

## Layout

| Path | Contents |
| --- | --- |
| `NearbyPharmacies.xcodeproj` | Project with the shared `NearbyPharmacies` scheme. Folders are synchronized groups, so new files under the three source folders join their target automatically. |
| `NearbyPharmacies/App/` | SwiftUI entry point, `ContentView` for map and sheet coordination, and shared `PharmacyFinder` state. |
| `NearbyPharmacies/Origin/` | Origin model, controller, search view, geocoding and Core Location. |
| `NearbyPharmacies/Map/`, `NearbyPharmacies/Results/` | Map and markers, results sheet, rows and details. |
| `NearbyPharmacies/Shared/` | Theme and app localization. English and Finnish strings live in `NearbyPharmacies/Localizable.xcstrings`. |
| `NearbyPharmacies/Testing/` | Scripted geocoding and location used by previews and UI tests. |
| `NearbyPharmacies/Resources/Data/` | Synced from the web repo, never edited by hand: `pharmacies.fi.json`, `places.fi.json`, `coverage.fi.json`, `manifest.fi.json`, `ODbL-NOTICE.txt`. Bundled in the app. See [Pharmacy data](#pharmacy-data). |
| `NearbyPharmaciesTests/` | Swift Testing unit tests, hosted in the app. |
| `NearbyPharmaciesTests/Fixtures/ranking-v1.json` | Shared ranking fixture, synced from the web repo. Never edit by hand. |
| `Packages/PharmacyCore/` | Local Swift package (iOS and macOS): haversine distance, ranking, distance display rounding, the `opening_hours` interpreter (the same rules as the web app), address lines, data models and the bundle loader. The app target links it. Its tests run on the Mac. |
| `NearbyPharmaciesUITests/` | XCUITest journeys: default results in English and Finnish, row and pin selection, missing address and hours, the sheet at an accessibility text size, and origin selection by location, search and map. |
| `Config/` | `Signing.xcconfig`, the app target's base configuration, optionally includes `Local.xcconfig` (ignored by Git) with the developer's own `DEVELOPMENT_TEAM`; `Local.xcconfig.example` shows the format. Never set the team in `project.pbxproj`. |
| `scripts/style.sh` | swift-format check and format commands. |
| `scripts/agent-stop-hook.sh` | Agent stop hook that checks changed Swift files. |
| `.swift-format` | swift-format configuration (the tool's defaults, pinned). |
| `.build/` | Ignored. All build output, results and screenshots from the commands below. |

Group Swift files by feature within the app target. Keep platform-independent domain logic in
`PharmacyCore`. Prefer clear names and structure over comments. Use comments for non-obvious
reasons, constraints, or workarounds, and remove comments that restate the code.

Requirements: Xcode 16 or later with an iOS 18 or later simulator runtime. The repo was
set up and built with Xcode 27.2. Its only package is the local `Packages/PharmacyCore`;
there are no remote package dependencies. swift-format ships with Xcode. The PharmacyCore
tests need only Xcode or the Swift toolchain on the Mac, no simulator runtime.

Run every command from the repository root. Commands that use `xcodebuild` or `simctl`
need CoreSimulator, which agent sandboxes usually block. Run them outside the sandbox,
with approval.

## Development shell

From the repository root, run `nix develop` with flakes enabled. With direnv and nix-direnv
configured in your shell, run `direnv allow` once to load it automatically when you enter the
directory. The shell provides Betterleaks 1.x, Git, and jq on Apple Silicon Macs.
Install Xcode and the simulator runtime separately. For the data sync, use the web repository's shell.

## Choose a simulator

1. List available simulators and copy the UDID of an iPhone:

   ```sh
   xcrun simctl list devices available
   ```

2. If no iPhone appears, check `xcrun simctl list runtimes`. If an iOS runtime is
   missing, install it in Xcode Settings → Components or run
   `xcodebuild -downloadPlatform iOS`. If the installed runtime has no iPhone
   simulator, pick a type from `xcrun simctl list devicetypes` and create one:

   ```sh
   xcrun simctl create "iPhone Test" "iPhone 17"
   ```

3. Replace `SIMULATOR_UDID` in the commands below with that UDID. A destination such as
   `-destination 'platform=iOS Simulator,name=iPhone 17'` also works when the name is
   unique.

## Launch for interactive review

Each block is standalone and repeatable.

```sh
xcrun simctl boot SIMULATOR_UDID
```

`Unable to boot device in current state: Booted` means it is already running. To see
the window, open the simulator app from Xcode → Open Developer Tool. Xcode 27 has no
`Simulator.app`; its developer tools include `DeviceHub.app`
(`open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app`). With older Xcode
versions, run `open -a Simulator`. Agent sandboxes block `open`, so ask the user to run it.

```sh
xcodebuild build -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' -derivedDataPath .build/DerivedData
xcrun simctl install SIMULATOR_UDID .build/DerivedData/Build/Products/Debug-iphonesimulator/NearbyPharmacies.app
xcrun simctl launch --terminate-running-process SIMULATOR_UDID fi.example.NearbyPharmacies -AppleLanguages '(fi)' -AppleLocale fi_FI
```

For English, launch with `-AppleLanguages '(en)' -AppleLocale en_GB`. Without the
arguments the app follows the simulator's language settings.

### Capture the screen

```sh
mkdir -p .build/screenshots
xcrun simctl io SIMULATOR_UDID screenshot .build/screenshots/launch-fi.png
```

The screenshot shows the map of central Helsinki with 20 pharmacy pins and the sheet half
open: the search field showing the starting point, the title, the dataset count and the
nearest rows, each with its distance at the right edge in green, amber or red. Dragging the
sheet down closes it to the search field alone.

| Language | Title | Count | Starting point | Nearest result |
| --- | --- | --- | --- | --- |
| Finnish (`fi_FI`) | Lähimmät apteekit | Kartoitetut apteekit Suomessa · 784 | Helsingin päärautatieasema (oletus) | Steissin Apteekki, 50 m |
| English (`en_GB`) | Nearest pharmacies | Mapped pharmacies in Finland · 784 | Helsinki Central Railway Station (default) | Steissin Apteekki, 50 m |

To try large text, add `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`
to the launch command. For dark appearance, run `xcrun simctl ui SIMULATOR_UDID appearance dark`
(and `light` to restore it).

## Tests

### Ranking and data (runs on the Mac)

The PharmacyCore package tests are the runnable check for ranking, distance formatting and
the bundled data. They need no simulator:

```sh
swift test --package-path Packages/PharmacyCore
```

The tests cover every origin of the shared fixture (order, distances within its tolerance,
English and Finnish labels), all
19 display-rounding cases, the distance colour bands, the zero distance, the exact three-way tie, two distances with the
same label, decoding of records without name, address or hours, the bundled snapshot and place
index against the manifest's counts, and the SHA-256 of each data file against the
manifest. They also run the web app's `opening_hours` cases and check that the snapshot
interprets the same 613 of 623 values, plus address lines, name trimming and pin points.
The origin tests cover the geocoder configuration and request parameters, Nominatim and Photon
answers, the bundled place fallback (Swedish names, typos, no match for addresses) and the
coverage notices for Tornio, Haparanda, Tallinn, Helsinki, Hanko, Mariehamn and Tampere.
Fixture labels are compared after its `labelComparison` rule (U+00A0 and U+202F become
spaces). A separate test pins the exact characters, which match the web app's `Intl`
output: Finnish groups with U+00A0 ("1 234 km"), and both languages put U+0020 before the
unit.

SwiftPM's build writes files atomically through a system temporary folder that agent
sandboxes deny, so run `swift test` outside the sandbox too. Build output goes to the
ignored `Packages/PharmacyCore/.build/`.

### App tests (need a simulator)

The UI suite takes about three minutes per simulator, so scope it to the change:

- While iterating, run the unit tests and only the UI test class or test that covers the
  change, on one simulator (see [Run part of the UI suite](#run-part-of-the-ui-suite)).
- Before proposing a commit, run the full UI suite once, on one iPhone simulator.
- Repeat it on iPhone SE, in dark appearance or at a large text size only when the change
  affects layout, at a checkpoint, or when asked.

xcodebuild refuses to overwrite a result bundle, so each command deletes its old bundle
first.

Unit tests (Swift Testing: language selection, English fallback, the locale passed to the
distance formatter, the string catalog against every fixture label and the journey strings,
the data files in the app bundle, the default ranking and selection in `PharmacyFinder`, the
map fit above the sheet, and `OriginController` with gated fakes: the location offer, a granted
Tampere fix (Tullintorin apteekki first), denial and timeout, late fixes and geocoder replies
after a map pick, address matches, the place fallback, no matches, an unavailable service and
the coverage notices):

```sh
rm -rf .build/results/unit.xcresult && xcodebuild test -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' -derivedDataPath .build/DerivedData -resultBundlePath .build/results/unit.xcresult -only-testing:NearbyPharmaciesTests
```

UI tests (XCUITest, about three minutes, each attaching screenshots): default results in
English and Finnish; row selection with details, hours, the kept detent and the origin and pin
centred above the sheet; the closed sheet showing only the search field, and a pin that opens
it with the details centred; a selection from the large sheet bringing it to the medium
detent, and the closed sheet then showing only the selected name and distance; pin selection with "Address unavailable" and "Hours unavailable" in
Finnish; return to the list with the selection kept; the sheet at Accessibility XXXL text,
which opens at the medium detent (large on screens shorter than 800 points, such as iPhone SE)
with a full result visible; and origin selection with scripted answers: the location offer and
a granted Tampere fix labelled "Your location", "Use my location" leaving the sheet in place, denial, a timeout in Finnish, five "Kauppakatu 1" matches, an empty
reply in Finnish, the bundled "Tammerfor" fallback, a map pick that wins over a late reply,
panning that leaves the origin alone, "Choose on map" with "Cancel" and then "Search from here"
winning over a late fix, and Haparanda outside Finland with "Return to Helsinki":

```sh
rm -rf .build/results/ui.xcresult && xcodebuild test -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' -derivedDataPath .build/DerivedData -resultBundlePath .build/results/ui.xcresult -only-testing:NearbyPharmaciesUITests
```

#### Run part of the UI suite

`-only-testing` takes a test class or a single test, and can be repeated. The classes are
`LaunchSmokeTests` (launch in both languages), `SelectionTests` (rows, pins and details),
`LargeTextTests` (Accessibility XXXL) and `OriginJourneyTests` (search, location and map
picking). For example, one class and one test together:

```sh
rm -rf .build/results/ui-part.xcresult && xcodebuild test -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' -derivedDataPath .build/DerivedData -resultBundlePath .build/results/ui-part.xcresult -only-testing:NearbyPharmaciesUITests/SelectionTests -only-testing:NearbyPharmaciesUITests/OriginJourneyTests/testChooseOnMapWinsOverALateLocationFixInFinnish
```

Add `-only-testing:NearbyPharmaciesTests` to run the unit tests in the same build.

Export the UI test screenshots:

```sh
xcrun xcresulttool export attachments --path .build/results/ui.xcresult --output-path .build/results/ui-attachments
```

Compile the app and both test bundles without a simulator:

```sh
xcodebuild build-for-testing -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData
```

## Pharmacy data

The data and the ranking fixture come from the web repository
(`nearby-pharmacies-web`), which owns the importer, the snapshot and the ranking contract.
Never edit the copies here by hand. To update them, run from the web repository root:

```sh
pnpm run data:sync-ios -- --ios-repo ../nearby-pharmacies-ios
pnpm run data:verify -- --ios-repo ../nearby-pharmacies-ios
```

The sync prints `copied …` for each file and `data:verify: 6 file(s) match`. Verify alone
exits 1 with `missing:` or `differs:` lines when a copy is stale. Commit both repositories
together.

Where the copies go and who reads them:

- `NearbyPharmacies/Resources/Data/` is inside the app's synchronized group, so Xcode copies
  the five files into the top level of `NearbyPharmacies.app`. The app reads them with
  `PharmacyDataLoader(bundle: .main)`.
- `NearbyPharmaciesTests/Fixtures/ranking-v1.json` lands in the unit-test bundle the same
  way.
- The PharmacyCore tests read both folders in place, relative to their source file
  (`Tests/PharmacyCoreTests/SyncedFiles.swift`, through `#filePath`). The package has no
  second copy and no resources, so `data:verify` covers every file the tests read.

The ranking contract: haversine distance with the mean Earth radius 6 371 008.8 m
(`Haversine.earthMeanRadiusMeters`, the only definition), ascending unrounded distance, exact
ties by `id` in UTF-16 code-unit order, and display rounding from the design spec. Change it
only together with the web repository and its fixture.

## Style

Check without changing anything. With no arguments this covers changed Swift files:
staged, unstaged and untracked. It skips deleted and ignored files.

```sh
scripts/style.sh check
```

Apply formatting to the same files:

```sh
scripts/style.sh format
```

Both accept `--all` for every Swift file, or explicit paths. Diagnostics use the form
`path:line:column: error: [Rule] message`. Formatting fixes whitespace, indentation and
line length. Fix other rules, such as naming, by hand. `format` writes through the
shell rather than with `--in-place`, so it also works in agent sandboxes. Set
`SWIFT_FORMAT` to use another swift-format binary.

## Agent stop hooks

`scripts/agent-stop-hook.sh` runs `scripts/style.sh check` when an agent finishes a
turn. If the check fails, the hook exits 2 and prints the diagnostics and fix commands
on stderr. Claude Code and Codex then continue the turn with that text as the reason.
If the check passes, the hook exits 0 with no output.

If the check fails again during a stop-hook continuation (`stop_hook_active` is true),
the hook prints a JSON `systemMessage` warning and lets the agent stop.

To try the hook by hand:

```sh
printf '%s' '{"session_id":"manual","stop_hook_active":false}' | scripts/agent-stop-hook.sh
```

Enabling:

- **Claude Code** reads `.claude/settings.json` when a session starts in this
  directory, not in a parent directory. Accept the workspace trust prompt for the
  folder, then confirm the hook in `/hooks`. `"disableAllHooks": true` in local settings
  turns it off.
- **Codex** reads `.codex/hooks.json` only for a trusted project. Review and trust each
  hook definition in `/hooks`. Changes to a definition need review again. Set `[features] hooks = false`
  to disable hooks.

### Secret scanning

Both agents run `scripts/secret-scan.sh --hook` on `Stop` alongside the style check.
Start the agent from the development shell so it inherits Betterleaks and jq on `PATH`.
You can also install Betterleaks 1.x and jq separately.

The scan checks tracked files and non-ignored untracked files in the working tree, plus
staged additions and edits from Git's index. It runs locally. A finding requests one
continuation and becomes a warning if it persists. A scan error also produces a warning.
The hook gives a summary without printing the scanner's output.

Run these from the repository root to view redacted findings and scan local Git history
before publishing:

```sh
scripts/secret-scan.sh
betterleaks git --log-opts=--all --redact=100 --verbose .
```

## Commits

Keep each commit focused on one change and write a short, imperative Conventional Commit subject
such as `docs: add agent skills`. Use `type(scope): summary` when naming the affected area adds
clarity, as in `test(locale): cover English fallback`.

## Localization

- Add every user-facing string to `NearbyPharmacies/Localizable.xcstrings` with both
  `en` and `fi` translations. Do not translate pharmacy names from data.
- `AppLocalization` picks the first preferred language the app supports, falling back
  to English. It reads strings from that language's bundle. It formats numbers with a
  locale that combines that language with the device region. An English interface on a
  Finnish-region device therefore shows "1,7 km". Unit tests cover this case.
- Format distances only with `DistanceFormatting.distance(meters:locale:)` from PharmacyCore.
  Under 1 km it rounds to the nearest 10 m, from 1 km to under 10 km to the nearest 0.1 km,
  and from 10 km to whole kilometres. A value that rounds up to the next band uses that band,
  so 995 m shows "1.0 km" and 9 950 m shows "10 km". This matches the web app.
