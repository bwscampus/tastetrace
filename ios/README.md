# TasteTrace iOS

Native SwiftUI app (iOS 17+) for the TasteTrace API in `../app`. The Xcode
project is generated from `project.yml`; the screens, models and logic live in
local Swift packages so most of the code builds and tests without Xcode.

```
ios/
  project.yml                 # XcodeGen spec (the .xcodeproj is not committed)
  Config/*.xcconfig           # API_BASE_URL per configuration
  TasteTrace/                 # thin app target: @main, assets, privacy manifest
  Packages/
    TasteTraceAPI/            # URLSession client + Codable models mirroring the API
    TasteTraceCore/           # session/keychain, JSON file cache, repositories, domain helpers
    TasteTraceUI/             # design tokens and components from the mockups
    TasteTraceFeatures/       # every screen and view model (UIKit-free)
```

## Building and running (needs Xcode)

1. Install Xcode from the App Store, then:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -runFirstLaunch
   xcodebuild -downloadPlatform iOS
   brew install xcodegen
   ```
2. Debug and Release builds both talk to the deployed backend
   (`https://tastetrace-app.up.railway.app`), so a phone works out of the box.
   To develop against a local server, edit `Config/Debug.xcconfig`: use
   `http://localhost:5000` for the simulator, or your Mac's LAN address for a
   phone on the same Wi-Fi, then `cd ../app && npm run dev`.
3. Generate and open the project:
   ```sh
   xcodegen generate && open TasteTrace.xcodeproj
   ```
   or from the command line:
   ```sh
   xcodebuild -project TasteTrace.xcodeproj -scheme TasteTrace \
     -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
   Package tests (XCTest) run with `swift test` inside each package once Xcode
   is installed, or through the TasteTrace scheme.

## Without Xcode

The command-line toolchain can compile every package (`swift build` in each
`Packages/*` directory) and run the API smoke check against a live backend:

```sh
cd Packages/TasteTraceAPI && swift run apismoke http://localhost:5000
```

It registers a throwaway user, logs entries, reads them back and revokes its
token. XCTest and the simulator need Xcode.

## What's built

Sign in / sign up · Today (7-day hero, coverage ring, timeline) · Daily
Logging Coverage · Log a Meal (tiles, ingredients + cook methods, save dish)
· Quick Log symptoms · History (week strip, edit/delete) · Weekly Digest
(Trends, Symptoms, Suspects with AI synthesis and watchlist) · Trigger
Insights · Profile (tracking rules, reminders, watchlist) · Exports (CSV,
three PDF reports). Every screen calls the real API; see
`../docs/ios-build-plan.md` for the endpoint map.

## Conventions

- Timestamps are ISO-8601 UTC; calendar days are computed in the device
  timezone and sent as `tz` so the server buckets days the same way.
- The bearer token lives in the keychain (`KeychainTokenStore`); a 401 signs
  the user out.
- Read data is cached as JSON files under Application Support/TasteTrace so
  Today and History render offline; writes require a connection.
