# TasteTrace iOS

Native SwiftUI app (iOS 17+) for the TasteTrace API in `../api`. The Xcode
project is generated from `project.yml` by XcodeGen and committed, so a clone
opens and builds with no setup. The screens, models and logic live in local
Swift packages, so most of the code builds and tests without Xcode.

```
ios/
  TasteTrace.xcworkspace      # open this — the app project plus the packages
  TasteTrace.xcodeproj        # generated from project.yml, committed
  project.yml                 # XcodeGen spec — the source of truth for the project
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
   ```
   XcodeGen is not needed to build, only to change the project; see below.
2. Open the workspace:
   ```sh
   open TasteTrace.xcworkspace
   ```
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

### Changing the project

`project.yml` is the source of truth. The `.xcodeproj` is committed for
convenience, not edited by hand, so anything structural — a new target, a
source folder, a build setting, a package — goes in the spec:

```sh
brew install xcodegen      # once
xcodegen generate          # rewrites TasteTrace.xcodeproj
```

Commit the spec and the regenerated project together, or the two drift apart.
Per-user state inside the project (window layout, scheme ordering, the nested
`project.xcworkspace`) is ignored, so it never shows up in a diff.

`DEVELOPMENT_TEAM` is empty in the spec. Simulator builds do not care; setting
a team for device signing in Xcode writes into the project file, so either put
your team ID in `project.yml` and regenerate, or leave that change uncommitted.
## TestFlight from GitHub (no Mac needed)

`.github/workflows/ios-testflight.yml` builds the app on GitHub's Macs on every
push to `main` or `taylor` that touches `ios/`, and uploads it to TestFlight.
Each upload's build number is the workflow run number. Until the secrets below
exist, a run only checks that the app compiles.

One-time setup (needs the paid Apple Developer account):

1. **Register the bundle ID.** developer.apple.com → Certificates, IDs &
   Profiles → Identifiers → **+** → App IDs → App → Bundle ID (explicit)
   `app.tastetrace.ios`, description "TasteTrace".
2. **Create the app.** appstoreconnect.apple.com → Apps → **+** → New App →
   iOS, name "TasteTrace", bundle ID `app.tastetrace.ios`, any SKU.
3. **Create an API key.** App Store Connect → Users and Access →
   Integrations → App Store Connect API → Team Keys → **+**, access **Admin**
   (automatic signing needs it to create the distribution certificate).
   Download the `.p8` file (it can only be downloaded once) and note the Key ID
   and the Issuer ID shown above the list.
4. **Find the Team ID.** developer.apple.com → Account → Membership details.
5. **Add four repository secrets** on GitHub: Settings → Secrets and
   variables → Actions → New repository secret:
   - `APP_STORE_CONNECT_KEY_ID`: the Key ID
   - `APP_STORE_CONNECT_ISSUER_ID`: the Issuer ID
   - `APP_STORE_CONNECT_KEY`: the whole contents of the `.p8` file, including
     the `BEGIN`/`END` lines
   - `APPLE_TEAM_ID`: the Team ID
6. Re-run the workflow (Actions → iOS → TestFlight → Run workflow). After
   Apple processes the build, install **TestFlight** on the phone, sign in with
   the same Apple ID, and install TasteTrace from there. Later builds show up
   as updates.

### Schemes

`TasteTrace` builds and runs the app and hosts the XCTest target. Xcode also
creates a scheme per package plus `apismoke`, so package tests can run in the
IDE; `swift test` inside each `Packages/*` directory does the same thing
without opening Xcode.

## TasteTrace Plus (subscriptions)

Logging is free; insights are paid. The app uses StoreKit 2 (`Plus/PlusStore.swift`)
and nothing works for real until these exist in App Store Connect:

1. **Agreements**: the Paid Apps agreement, with banking and tax filled in.
2. **Subscription group** "TasteTrace Plus" with two auto-renewable subscriptions:
   | Product ID | Period | Price |
   | --- | --- | --- |
   | `app.tastetrace.ios.plus.monthly` | 1 month | $5.00 |
   | `app.tastetrace.ios.plus.annual` | 1 year | $30.00 (the paywall shows it as about $2.50/month and selects it by default) |
3. **Offer codes** on the annual subscription, as custom codes (an App Store
   offer code belongs to one subscription, so both sit on the annual plan):
   | Code | Who | Offer |
   | --- | --- | --- |
   | `TASTETRACE20` | friends, family, beta testers | pay up front, 1 year, $24.00 (20% off) |
   | `TTWAITLIST` | waitlist | pay up front, 1 year, $27.00 (10% off) |
   The paywall recognises these names (`PromoCode.all`) and shows the discounted
   price; Apple applies the actual discount when the code is redeemed. To add a
   code, create it in App Store Connect and add it to `PromoCode.all`.
4. Set `APP_STORE_ID` in `Config/*.xcconfig` to the app's numeric Apple ID so
   "Redeem" opens Apple's sheet with the code filled in. Until then the user
   types the code into Apple's blank redeem sheet.

What Plus unlocks (free in brackets): history older than 14 days (last 14
days), every trigger insight (one preview after 7 days of logging), the
Symptoms and Suspects digest pages and older weeks (Trends), PDF reports
(CSV stays free), custom nudge time and meal check-ins (the default nudge).
Free users see the paywall when they tap one of those, and once when their
account turns 14 days old. The entitlement is checked on the device; the API
does not know about Plus yet.

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
