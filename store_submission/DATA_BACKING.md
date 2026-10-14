# Data Safety / App Privacy Backing — PhotoSur

Reference document for filling out Play Console's Data Safety form and
App Store Connect's App Privacy questionnaire. Not the disclosures
themselves — those live in `website/privacy.html` and each store's own
console.

## Architecture summary

Zero backend (Section 1). No user accounts. No server-side storage of
any kind. All image processing happens on-device. The only network
calls the app makes are: (1) AdMob ad requests, (2) StoreKit/Play
Billing purchase verification (handled by the OS, not our code — see
`iap_service.dart`'s on-device-trust design decision).

## Permissions and their justification

| Permission | Why | Where |
|---|---|---|
| `CAMERA` | Feature 12, in-app photo capture | Android manifest, iOS `NSCameraUsageDescription` |
| Photo library read | Gallery picker (image_picker) | iOS `NSPhotoLibraryUsageDescription` |
| Photo library write | Save export to gallery (gal) | iOS `NSPhotoLibraryAddUsageDescription`, Android `WRITE_EXTERNAL_STORAGE` (API ≤29 only) |
| `INTERNET` | Ad requests, IAP verification | Android manifest |
| `AD_ID` | AdMob (Android 13+) | Android manifest |
| ATT (iOS) | Ad personalization consent | `NSUserTrackingUsageDescription` |

**No SMS, call log, contacts, location, microphone, or QUERY_ALL_PACKAGES
access anywhere in the app.**

## Ad SDK disclosure (Google AdMob)

- Data collected: device identifiers (advertising ID), for ad
  personalization and frequency capping.
- Non-personalized ads served when: ATT declined (iOS), or user hasn't
  granted AD_ID-adjacent consent (Android).
- Data shared with third parties: Yes — device identifiers, for
  advertising purposes, via Google AdMob.
- Data linked to user identity: No — no account system exists to link
  to.

## In-app purchase disclosure

- Handled entirely by Apple/Google's native billing APIs
  (`in_app_purchase` package). We never see or store payment card
  details.
- No server-side receipt validation (see `iap_service.dart`'s
  documented reasoning) — validation is on-device only via StoreKit2's
  built-in cryptographic verification (iOS) / Play Billing's purchase
  acknowledgment flow (Android).

## Local-only data

- Export history (`ExportJob` records) — sqflite, on-device only.
- Settings (theme, onboarding status, language, ad-free flag) —
  SharedPreferences, on-device only.
- Exported image files — app-scoped storage + user's own photo
  gallery (if saved there).

None of the above is ever transmitted off-device by our code.
