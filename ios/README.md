# TasteTrace iOS

Native SwiftUI app (iOS 17+) for the TasteTrace API in `../api`. The Xcode
project is generated from `project.yml`; the screens, models and logic live in
local Swift packages so most of the code builds and tests without Xcode.

```
ios/
  TasteTrace.xcworkspace      # open this — the app project plus the packages
  project.yml                 # XcodeGen spec (the .xcodeproj is not committed)
  Config/*.xcconfig           # API_BASE_URL per configuration
  TasteTrace/                 # thin app target: @main, assets, privacy manifest
  Packages/
    TasteTraceAPI/            # URLSession client + Codable models mirroring the API
    TasteTraceCore/           # session/keychain, JSON file cache, repositories, domain helpers
    TasteTraceUI/             # design tokens and components from the mockups
    TasteTraceFeatures/       # every screen and view model (UIKit-free)
```

`ios/` is not a Swift package. It holds the workspace, the app target and four
independent packages, each with its own `Package.swift` under `Packages/`.

## Building and running (needs Xcode)

1. Install Xcode from the App Store, then:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -runFirstLaunch
   xcodebuild -downloadPlatform iOS
   brew install xcodegen
   ```
2. Generate the project, then open the workspace:
   ```sh
   xcodegen generate && open TasteTrace.xcworkspace
   ```
   The workspace is committed; the `.xcodeproj` it references is not, so
   `xcodegen generate` has to run once after a fresh clone or the project
   reference shows up missing. Regenerating it does not disturb the workspace.

   From the command line, build against the workspace rather than the project:
   ```sh
   xcodebuild -workspace TasteTrace.xcworkspace -scheme TasteTrace \
     -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```
3. Debug and Release builds both talk to the deployed Python backend
   (`https://tastetrace-api-production.up.railway.app`), so a phone works out
   of the box. To develop against a local server instead, edit
   `Config/Debug.xcconfig`: `http://localhost:8000` for the simulator, or this
   Mac's LAN address for a phone on the same Wi-Fi. Then:
   ```sh
   cd ../api && uv run uvicorn app.main:app --port 8000
   ```
   A phone also needs the server bound with `--host 0.0.0.0`.

### Schemes

`TasteTrace` builds and runs the app and hosts the XCTest target. Xcode also
creates a scheme per package plus `apismoke`, so package tests can run in the
IDE; `swift test` inside each `Packages/*` directory does the same thing
without opening Xcode.

## Without Xcode

The command-line toolchain can compile every package (`swift build` in each
`Packages/*` directory) and run the API smoke check against a live backend:

```sh
cd Packages/TasteTraceAPI && swift run apismoke http://localhost:8000
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
- Sign-in is form-encoded against `/api/auth/bearer/login`; the bearer token
  lives in the keychain (`KeychainTokenStore`) and a 401 signs the user out.
  Passwords need 8 characters.
- Read data is cached as JSON files under Application Support/TasteTrace so
  Today and History render offline; writes require a connection.
