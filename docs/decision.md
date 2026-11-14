# PhotoSur: decision log (pivots and upgrades, in order)

Append a dated entry for every pivot or upgrade. Newest at the bottom. Dates are approximate where the original session did not record them.

1. **Repo audit.** App started as "KatharErase" (background remover). Repo had pivoted to a hybrid "Image Desk Pro" with ~129 analyzer errors. Decision: restore the last CI-green state (`a2cdb57`) instead of patching the hybrid, and drop the Resize/Passport/Watermark/EXIF stub screens (they faked success messages).
2. **Model swap.** Bundled 249 KB selfie model was person-only and the input pipeline was broken (garbled tensor, 256x256 mask never upscaled, undo/reset wrong). Replaced with U2-Netp (4.5 MB, Apache-2.0), converted to single-output TFLite, validated against ONNX on real photos. Pipeline rewritten (EXIF rotation, 320x320, upscale, base mask for undo, background isolate, 2048 px cap).
3. **CI-first workflow.** No local Flutter. Added `verify.yml` (analyze + tests on `verify/**`, results as annotations). APK builds are manual only (owner rule).
4. **Ads/IAP.** Subscription dropped; single one-time ad-free purchase $14.99 (`com.zdmgold.photosur.adfree`). Test AdMob IDs until the owner supplies real ones. Interstitial after export and after batch, non-personalized.
5. **Local notifications added** ("Your edit is waiting", 3 h after leaving an unexported edit). Time-zone database setup removed (caused startup stall).
6. **Startup freeze.** Cause was a debug-only provider check throwing on the first screen plus an error screen that crashed. Fixed (check off, self-sufficient error screen, ad/notification init after first frame with time limits).
7. **Design system.** Inter font, tested contrast palette (4.5:1), unified theme, editor redesign: fixed canvas, one tool panel (fixed height), dock. Header-tab layout replaced.
8. **Languages.** 1 -> 9 -> 27 -> 43 locales, RTL for ar/he/ur/fa, system-locale resolution fixed (unsupported languages fall back to English, zh-TW/HK/MO to Traditional). Seven top languages corrected by review, then all 42 re-read side by side with English.
9. **Features added after launch scope:** Layout tool (move/scale/shadow/gradients/custom photo), templates (23 bundled), marketplace presets (Amazon 2000 px white, eBay 1600, Etsy 2667x2000 <=1 MB, Shopify 2048 PNG), batch processing (30 photos), custom colour picker, HD model (optional download), Help screen, exports library, Replay intro.
10. **HD model hosting.** Moved from the app repo release to the separate public repo `photosur-models` so the main repo can go private. Download is silent on first photo, resumable, SHA-256 checked, auto-resumes each launch.
11. **Rename KatharErase -> PhotoSur** (display name, IDs, repo, Cloudflare worker, website). Chosen to say "photo" immediately; store subtitle carries "remove background".
12. **Release signing.** Permanent keystore, four GitHub secrets, workflow builds signed APK + AAB. Previous builds were debug-signed and could not update over each other.
13. **JNI plugin pins.** `shared_preferences_android` <2.5.0 and `path_provider_android` <2.3.0 after a release-only onboarding loop on the owner's phone.
14. **Library, not just a grid.** Recent exports: history table column bug fixed (snake_case), tile menu, See all, viewer, multi-share, delete.
15. **Onboarding rewritten to 4 pages**, no ads/payment wording; "All features free" in page 1 title; new art as small WebP (about 130 KB total).
16. **Home animated background.** Tried header strip, then section background, then back to header strip (fade-only redraw, default on, Settings switch).
17. **Diagnostics off** (`kShowExportDiagnostics=false`) after the owner confirmed export works.
18. **Emulator coverage** built and run (photos, large images, interruptions, batch, camera, languages). Found and fixed crop-default square crop, WEBP gallery save, double editor build, unsupported-device and Settings overflow.
19. **2026-11-14 approved next batches** (not started): 7-minute persisted interstitial gap (no hourly cap); storage sweep + low-storage check + Settings storage row; in-app review prompt after 10 exports on 3+ days; Google UMP ad consent; widget tests for remaining screens; native review of translations. Order: interstitial, storage, review, consent.
