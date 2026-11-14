# PhotoSur: blueprint (reconstructed from the code, 2026-11-14)

NOTE: the original master blueprint from the start of the project is not stored in the repo or project docs. This file was rebuilt from the code on `main` (c91a5ab). If the owner supplies the original, merge it here. Paths are under `app/` unless stated.

## Stack
Flutter (Dart), provider, go_router, sqflite, tflite_flutter (on-device), google_mobile_ads, in_app_purchase, flutter_local_notifications, gal (gallery save), share_plus ^13, image_picker, camera, crop widget, crypto (HD model SHA-256). 43 locales via ARB. Plugin pins: shared_preferences_android <2.5.0, path_provider_android <2.3.0.

## Layout of `lib/`
- `main.dart`: startup (storage, theme/settings, runApp first; ads, notifications, ATT, HD model init after first frame with time limits). Provider check disabled for ValueNotifier providers.
- `app.dart`, `router.dart`: MaterialApp.router, locale resolution, routes: onboarding, home, camera, crop, editor, batch, exports, viewer, settings, help, paywall, unsupported.
- `core/models`: `editable_image_state.dart` (BackgroundType, layout, base mask), `export_job.dart`.
- `core/providers`: `image_edit_provider.dart` (editor state, undo/redo replay from base mask, auto cut-out, HD redo), `settings_provider.dart`, `theme_provider.dart`, `ad_provider.dart`, `subscription_provider.dart`, library/HD providers.
- `core/services`: `segmentation_service.dart` (TFLite in isolate, `hdModelPath`, shared session for batch), mask refine/cleanup, `export_service.dart` (compose, flatten, size caps), `storage_service.dart` (temp/exports dirs, SQLite `export_jobs`), `export_library_service.dart`, `share_service.dart`, `model_download_service.dart` (resumable, SHA-256), marketplace presets in `core/utils/marketplace_presets.dart`, `constants.dart`.
- `platform/`: `ad_service.dart` (banner/interstitial, 7-minute gap enforced by `core/services/interstitial_gap.dart`, last-shown time saved on the phone), `batch_service.dart`, notification service, permission helpers.
- `screens/`: onboarding, home (+header strip), camera, crop_rotate, editor (tool panels, dock, top bar, canvas), export_bottom_sheet, batch, exports library, viewer, settings, help, paywall, unsupported_device.
- `widgets/`: AdBannerSlot, tool panels, swatch row, colour picker, tiles.
- `l10n/app_<lang>.arb` (264 keys); generated code in `lib/generated/l10n` (git-ignored, produced by `flutter gen-l10n`/pub get).
- `assets/`: `models/segmentation.tflite` (U2-Netp), `templates/` (23 JPG), `images/` (4 onboarding WebP), fonts (Inter).

## Key flows
1. Home -> Camera/Gallery -> Crop (Free starts on the whole photo) -> Editor.
2. Editor opens: decode (EXIF, cap 2048 px) -> infer (HD if `hdModelPath`, else bundled) -> refine/clean mask -> store base mask. First photo triggers the silent HD download if not installed; when it finishes and the cut-out is untouched, redo in HD.
3. Tools mutate state; brush strokes replay from the base mask (undo/redo/reset).
4. Export sheet: format, quality, size, marketplace preset; compose in isolate; save via gal, history row, optional share; interstitial afterwards unless ad-free.
5. Batch: up to 30 photos, one shared background + preset, one shared model session, each saved as it finishes, interstitial at the end.
6. Library: recent exports (6) on Home, See all, viewer, select/delete/share.

## Business rules
Free app with ads; $14.99 one-time removes ads only. Interstitial min interval constant `kInterstitialMinIntervalSeconds` (120 now; 420 approved). Notification 3 h after leaving an unexported edit. Photos never leave the device (only optional HD model download).

## CI and commands (dependency order for a new change)
1. `git checkout -b verify/<name>` from `main`; edit; commit with trailers; push.
2. `verify.yml` runs `flutter pub get`, `flutter gen-l10n`, `flutter analyze`, `flutter test`; read annotations with `gh api`.
3. Owner says "merge" -> fast-forward `main` (`git merge --ff-only`, push).
4. Owner triggers "Build PhotoSur Android" manually -> signed APK/AAB artifacts.
Other workflows: `emulator*.yml`, `backtranslate.yml`, `publish-hd-model.yml` (reads deleted `models-stage` branch; needs rework before reuse).

## Website
`website/` static pages (index, privacy, support) deployed by Cloudflare Workers worker `photosur`. Store badges: Google Play uses the real package link; App Store link is still a placeholder until iOS listing exists.

## Planned batches
See `handoff.md` section 5 (interstitial 7 min persisted, storage sweep, review prompt, UMP consent, tests, native review).
