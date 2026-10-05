# SwiftUI / iOS checks

## AUTH-4 / FE-7: tokens and local data

- Bearer token in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (or
  stricter). Never `UserDefaults`, never a plist or JSON file.
- **Sign-out and account deletion clear everything:** Keychain token, cached user, and every
  on-device cache (JSON stores, Core Data, SwiftData, image caches). Otherwise the next person
  to sign in on that phone sees the previous user's data.
- Files with personal or health data: write with `.completeFileProtection` (or
  `.completeUntilFirstUserAuthentication`) and consider `isExcludedFromBackup` for caches.

## AUTH-6: account deletion (App Store requirement)

Apple requires apps that support account creation to let users start account deletion inside
the app (App Store Review Guideline 5.1.1(v)). Pattern:

- Profile/Settings → "Delete account" (destructive role) → confirmation alert that asks for the
  password → `DELETE /api/users/me` → on 204, clear all local data (above) → return to sign-in.

## FE-2: secrets

Nothing secret in `Info.plist`, `.xcconfig`, or source. Everything in the app bundle is public.
AI keys stay on the server.

## OPS-5: environments

- Debug builds point at a dev or staging API, never production.
- `NSAllowsLocalNetworking` / ATS exceptions only in Debug configurations.
- Base URLs are `https://` in Release.

## FE-4

Support Dynamic Type, give images `accessibilityLabel`s, and don't lock orientation
or appearance without a reason.

## PRIV-1

App Store Connect needs a privacy-policy URL and accurate privacy "nutrition labels"; keep
`PrivacyInfo.xcprivacy` in sync with what the app actually collects.
