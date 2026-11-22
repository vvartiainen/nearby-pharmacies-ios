# Nearby Pharmacies iOS

A native SwiftUI app that will find the nearest mapped pharmacy in Finland. Product
decisions live in the planning documents outside this repository. This repository has
the runnable skeleton only. The app shows one localized screen: a heading, a caption
saying the distance is an illustrative example, and a fixed 0.4 km straight-line
distance. There is no map, location, geocoding or pharmacy data yet.

## Layout

| Path | Contents |
| --- | --- |
| `NearbyPharmacies.xcodeproj` | Project with the shared `NearbyPharmacies` scheme. Folders are synchronized groups, so new files under the three source folders join their target automatically. |
| `NearbyPharmacies/` | App sources and `Localizable.xcstrings` (English and Finnish). |
| `NearbyPharmaciesTests/` | Swift Testing unit tests, hosted in the app. |
| `NearbyPharmaciesUITests/` | XCUITest launch smoke tests in English and Finnish. |
| `scripts/style.sh` | swift-format check and format commands. |
| `scripts/agent-stop-hook.sh` | Agent stop hook that checks changed Swift files. |
| `.swift-format` | swift-format configuration (the tool's defaults, pinned). |
| `.build/` | Ignored. All build output, results and screenshots from the commands below. |

Requirements: Xcode 16 or later with an iOS 18 or later simulator runtime. The repo was
set up and built with Xcode 27.2. It has no package dependencies. swift-format ships
with Xcode.

Run every command from the repository root. Commands that use `xcodebuild` or `simctl`
need CoreSimulator, which agent sandboxes usually block. Run them outside the sandbox,
with approval.

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
the window, run `open -a Simulator`. Agent sandboxes block `open`, so ask the user to
run it.

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

The screenshot shows a large bold heading at the top left, a secondary caption
and a larger distance line.

| Language | Heading | Caption | Distance |
| --- | --- | --- | --- |
| Finnish (`fi_FI`) | Lähin apteekki | Havainnollistava esimerkkietäisyys | 0,4 km linnuntietä |
| English (`en_GB`) | Nearest pharmacy | Illustrative example distance | 0.4 km straight line |

## Tests

xcodebuild refuses to overwrite a result bundle, so each command deletes its old bundle
first.

Unit tests (Swift Testing: language selection, English fallback, distance formatting
and the string catalog):

```sh
rm -rf .build/results/unit.xcresult && xcodebuild test -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' -derivedDataPath .build/DerivedData -resultBundlePath .build/results/unit.xcresult -only-testing:NearbyPharmaciesTests
```

UI tests (XCUITest launch smoke tests in English and Finnish, each attaching a
screenshot):

```sh
rm -rf .build/results/ui.xcresult && xcodebuild test -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' -derivedDataPath .build/DerivedData -resultBundlePath .build/results/ui.xcresult -only-testing:NearbyPharmaciesUITests
```

Export the UI test screenshots:

```sh
xcrun xcresulttool export attachments --path .build/results/ui.xcresult --output-path .build/results/ui-attachments
```

Compile the app and both test bundles without a simulator:

```sh
xcodebuild build-for-testing -project NearbyPharmacies.xcodeproj -scheme NearbyPharmacies -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData
```

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

## Agent stop hook

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
- **Codex** reads `.codex/hooks.json` only for a trusted project, and only after you
  review and trust this exact hook definition in `/hooks`. Any change to the definition
  needs review again. Hooks are on by default; `[features] hooks = false` disables
  them.

## Localization

- Add every user-facing string to `NearbyPharmacies/Localizable.xcstrings` with both
  `en` and `fi` translations. Do not translate pharmacy names from data.
- `AppLocalization` picks the first preferred language the app supports, falling back
  to English. It reads strings from that language's bundle. It formats numbers with a
  locale that combines that language with the device region. An English interface on a
  Finnish-region device therefore shows "0,4 km". Unit tests cover this case.
- Distances are shown in kilometers with one decimal place. Task 5 will define the final
  rounding rule.
