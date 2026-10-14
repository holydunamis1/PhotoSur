# Screenshot Strategy — PhotoSur

## Required sizes

- **iOS**: 6.7" (iPhone 15 Pro Max class) minimum, 6.5" if targeting
  older devices too. iPad screenshots only if iPad is a supported
  device (Section 1 doesn't specify iPad support explicitly — confirm
  before generating iPad-sized assets, since generating a set that
  isn't needed wastes the pre-submission checklist's time).
- **Android**: Phone screenshots (16:9 or 9:16), Play Console will
  accept a range of resolutions — use a real device or emulator at a
  common resolution (1080×1920 or similar) rather than an arbitrary size.

## Screenshot sequence (5-8 screenshots, in this order)

1. **"1-tap remove"** — editor_screen.dart mid-segmentation or
   just-completed, showing the Auto tab, a clean before/after split.
2. **"Manual brush"** — editor_screen.dart's Manual tab, brush controls
   visible, zoomed-in edge detail showing the restore/erase toggle.
3. **"No watermark"** — export_bottom_sheet.dart open, or a clean
   final exported image with no overlay/badge on it at all.
4. **"Exact-size export"** — export_bottom_sheet.dart's resize chips
   visible (1:1/4:5/9:16/Custom), framed as "perfect for Depop,
   Instagram, and more."
5. **"Free to use"** — paywall_screen.dart's comparison card, framed
   to emphasize both tiers have identical features.
6. *(Optional)* Background replace — background_selector.dart with
   the blur or solid-color option visibly applied.
7. *(Optional)* Onboarding — a friendly first-run screen for App
   Store's "what is this app" instant-read value.

## Device frame notes

- Use each store's own official device-frame templates rather than
  hand-drawn frames — App Store and Play Console both reject or flag
  screenshots with inaccurate/unofficial device chrome.
- Keep captions short (3-5 words) and consistent with the callouts
  above — these match the four feature bullets already used in
  `ASO_METADATA.md`'s description, so the store listing reads as one
  coherent pitch rather than mismatched messaging.

## What NOT to include

- No fabricated review quotes or star ratings overlaid on screenshots.
- No competitor comparisons (both stores' review guidelines restrict this).
- No claims not actually true of this build — e.g. don't show a
  feature (like Tap-to-Select, deferred to Phase 2/post-launch) that
  isn't in the v1 feature set (Section 2).
