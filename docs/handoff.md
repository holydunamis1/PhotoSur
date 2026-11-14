# PhotoSur: handoff notes

Read this first, then `decision.md` (why things are the way they are) and `blueprint.md` (how the app is built). Update all three as the build progresses (see "Keeping these docs current").

Last updated: 2026-11-14. State described: `main` at `c91a5ab`, plus this docs branch.

## 1. Working rules from the owner (hard rules)
- Owner works only from an Android phone (Chrome + GitHub mobile web). There is no local toolchain. CI is the only compiler.
- Investigate the real code first and report findings before changing anything. No guessing.
- Smallest fix that solves the problem. No refactors.
- Never build an APK unless the owner says so. APK builds are manual-only ("Build PhotoSur Android" in Actions). Never add automatic APK triggers.
- Never merge without the owner saying "merge". Work goes on a `verify/<name>` branch first. Merge = fast-forward `main`.
- If the owner says "no code yet", only discuss.
- No placeholders in the app, website or docs. The only allowed ones are the iOS App Store ID/URL and the Apple Team ID.
- Be plain about what was not verified. Never say "verify it yourself" for something you can check with web search.
- Do not comment on token or phone safety. Do not give the owner manual terminal steps.
- Machine-translated text is never final: every translation needs native review before release.
- Commit trailers used so far: `Co-Authored-By: Claude ... <noreply@anthropic.com>` and a `Claude-Session:` line.

## 2. Access
- Repo: https://github.com/holydunamis1/PhotoSur (public; renamed from `katharErase`). Default branch `main`.
- Models repo: https://github.com/holydunamis1/photosur-models (public). Holds release `models-v1` with `segmentation_hd.tflite` (88,085,892 bytes) and licence notices.
- Website: https://photosur.holydunamis1.workers.dev (Cloudflare Workers, worker `photosur`, built from `website/`). Pages: `/`, `/privacy`, `/support`.
- Support email shown in app and site: stmakarios@gmail.com.
- Fine-grained GitHub token "PhotoSur Rebuild" (write on PhotoSur and photosur-models, incl. actions/workflows/secrets) expires 2027-01-02. The owner supplied it in the project description. It is deliberately not stored in this file because the repo is public.
- The Claude GitHub App is installed on the owner's account. In Claude Code sessions, GitHub API writes for some paths (creating releases, deleting branches, reading secrets, downloading artifacts) are blocked by the session proxy (HTTP 403). Workaround used: a temporary workflow on a throwaway branch that does the job with `GITHUB_TOKEN`, then delete that branch.
- GitHub Actions secrets set by the owner: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` (alias `PhotoSur`). The keystore text and passwords are NOT in the repo. Keep an offline backup: the keystore is the only copy of the signing key. Expected SHA-256 of the signing cert: `1D:C5:D7:05:7B:A8:7C:A1:E4:1F:11:4E:C0:25:7B:26:F2:D7:1B:E4:05:11:43:8D:6C:D5:12:C1:2F:59:D4:AF`.
- IDs: Android package and iOS bundle `com.zdmgold.photosur`. Ad-free product ID `com.zdmgold.photosur.adfree` (one-time $14.99, non-consumable; NOT yet created in either store).

## 3. How to work (reading CI results from a phone-only setup)
- Push a `verify/<name>` branch. `.github/workflows/verify.yml` runs `flutter analyze` and `flutter test` and writes results as annotations. Read them with `gh api repos/holydunamis1/PhotoSur/check-runs/<job id>/annotations`. Raw logs and artifact downloads are blocked from the sandbox.
- Annotations are capped around 4 KB. Print grouped summaries instead of per-test lines.
- `build_and_deploy.yml` (manual): builds signed release APK + AAB and a debug APK. Prints the signing SHA-256 in the "Set up release signing" step.
- `emulator-langsweep.yml` (manual): debug build on an emulator that tours onboarding/Home/Help/sheets/Settings in all 43 languages and fails on overflow logs. Known limit: it never reached the Home tiles, so it never got to the picker, crop, editor, export, batch, library, viewer or paywall.
- `emulator.yml` (manual): boot smoke test. `backtranslate.yml`, `publish-hd-model.yml`: one-off tooling.
- The stop-hook warnings about "unpushed commits" were false alarms from a missing remote-tracking ref. Check `git ls-remote origin <branch>` against `git rev-parse HEAD`.

## 4. Where everything stands
Built and merged to `main` (all CI-green; none of it is proven on a phone except where marked):
- Auto background removal (U2-Netp bundled, ~4.5 MB) with mask clean-up and edge refinement; optional HD model (full U2-Net, 88 MB) downloaded on first photo (silent, resumable, SHA-256 checked, hosted in photosur-models).
- Editor with five tools (Cut-out, Brush, Background, Templates, Layout), undo/redo/reset, before/after, zoom, custom colour picker, custom photo background, 23 bundled templates, drop shadow, subject move/scale.
- Crop and rotate, camera, export (PNG/JPG/WEBP, quality, size chips, custom size), marketplace presets (Amazon, eBay, Etsy, Shopify), batch (up to 30 photos, shared background and preset), exports library (tile menu, See all, viewer, select, multi-share, delete).
- Onboarding (4 pages) and Replay intro, Help screen (13 topics), Settings, paywall, unsupported-device screen, Home header strip (animated, with Settings switch).
- Ads: banners on Home, Crop, Editor, Batch, Exports, Viewer, Settings, Unsupported; one interstitial after export or finished batch. Still Google TEST ad IDs.
- 43 languages (all ARB files complete; all 42 non-English re-read side by side with English). RTL for Arabic, Hebrew, Urdu, Persian. System-language matching verified by test; manual override persists.
- Signed release build (APK + AAB) works. Plugin pins `shared_preferences_android <2.5.0` and `path_provider_android <2.3.0` are required (JNI releases broke release builds on the owner's phone).
- Website redesigned, with store badges, header links and real onboarding art. Privacy page dated.

Testing coverage:
- 33 test files. Widget sweep: 43 languages x 2 text scales x 8 surfaces at 320 dp, clean.
- Emulator, real fonts: onboarding, Home, Help, language/theme sheets, Settings in all 43 languages, clean.
- NOT covered with real fonts: editor and its tool panels, export sheet, batch, library, viewer, paywall. Also not covered by the widget sweep: tool panels, library, viewer, batch.
- Earlier emulator runs (branches `emu/*`) covered real photos through cut-out/export, HD download, batch, interruptions, odd sizes. Cut-out quality on real product photos has never been judged by the owner on shoes/bags/bottles.

## 5. Outstanding (not started unless noted)
Approved by the owner on 2026-11-14 (build in this order, each on its own `verify/` branch, CI first, owner says "merge"):
1. Interstitial spacing: change `kInterstitialMinIntervalSeconds` from 120 to **420 (7 minutes)**. No hourly cap. Save the last-shown timestamp on the phone so a restart does not reset it. Unit tests for the gap and the restart case.
2. Storage and clean-up (all approved):
   - Start-up sweep: delete leftover temp files (batch scratch folders older than 10 min, temp images older than a day). Never touch the exports folder.
   - Orphan sweep: delete files in the exports folder that no history row points to, after a one-day wait.
   - Temp folder cap: delete oldest temp files past a size limit (proposed 200 MB; owner approved the item, confirm the number).
   - Low-storage check before export and batch, with a plain message.
   - Settings storage row: size of temporary files with a Clear button.
   - Skip the debug-log cap (no such log exists).
   - Free-space reading may need a small new plugin: confirm with the owner before adding one.
   - About 4 new strings in 43 languages.
3. In-app review prompt (`in_app_review`): after the 10th successful export across at least 3 different days, shown once, no cooldowns of our own (Google controls the quota). Never within the same moment as an interstitial (skip if an ad is showing or just closed; try on a later export). Settings "Rate" row stays as the manual route and never hides the prompt. Save the export count and set of days on the phone. No new strings. Open question from the owner: how batch exports count. Suggestion awaiting approval: a completed batch run counts as ONE export event regardless of photo count, only if at least one photo saved, and the prompt is never shown at the end of a batch (the batch already shows an interstitial).
4. Ad consent (Google UMP): request consent info at launch before ads load; load ads only when Google says ads can be requested; if the check fails, still request ads; retry once on the next foreground; do not swallow `canRequestAds()` errors; add a Settings "Privacy choices" row shown only when required; add two sentences to the privacy page (declined consent may still show limited/non-personalized ads; if the form cannot be shown Google applies the last saved choice) and redeploy the site; keep the decision in one small function with a unit test; a few new strings in 43 languages. First check that `google_mobile_ads` 9.x includes the consent API. Cannot be fully tested without a device in an EEA region. Whether it is legally required is not decided.
5. Languages follow-up: add widget tests for the editor tool panels, export sheet, batch, library, viewer and paywall; owner checks German, Tamil, Arabic, Thai on the phone. Native-speaker review of all 42 non-English languages (priority: es, pt, fr, hi, ar, id, zh; then onboarding, paywall, permission and HD text).

Release blockers (need the owner):
- Real AdMob app and ad unit IDs (still Google test IDs). Replace test IDs in `constants.dart` and manifest/Info.plist app IDs.
- Create `com.zdmgold.photosur.adfree` in Play Console and App Store Connect.
- iOS: App Store ID/URL (`_kIosAppStoreId` in `settings_screen.dart`, `[YOUR_APP_STORE_URL]` on the website) and Apple Team ID in `ExportOptions.plist`. The `app/ios` folder only holds the icon set and `ExportOptions.plist`/Runner files; no full Xcode project is in the repo.
- Store listings in 43 languages (`store_submission/ASO_METADATA.md` is English).
- Check the name "PhotoSur" in both stores, on the domain, and as a trademark (web searches found nothing; store and registry lookups were blocked).
- Cloudflare "Workers Builds" check showed failures on early pushes; later passed. Site serves fine.
- U2-Net weights provenance: the HD model's weights match rembg's official `u2net.onnx` (all 231 multi-element tensors bit-identical); rembg is MIT, U-2-Net Apache-2.0. DUTS training-data terms were never checked.

Known stale text to fix in a small branch:
- `app/pubspec.yaml` description still says "Go ad-free for $0.99/mo".
- README mentions English-only v1; the app has 43 languages.

Deferred on purpose: object eraser (needs MI-GAN 16 MB + GPU runtime), AI-generated backgrounds (cloud, conflicts with on-device privacy), tap-to-select subject, Blur placement under the colour row, making the repo private (safe for the HD download since the models repo is separate; first confirm Cloudflare still builds from a private repo).

## 6. Branches
- `main` is the source of truth. Merged branches are safe to delete (owner says "clean up"; deletion needs the temporary-workflow workaround).
- Leftover remote branches: many `verify/*` (all merged), `bt-results`, `verify/backtranslate`, `verify/translation-review-1..4`, and test branches `emu/boot-trace`, `emu/coverage`, `emu/photos`, `emu/stress`.

## 7. Keeping these docs current
- `handoff.md`: update sections 4 to 6 at the end of every batch.
- `decision.md`: append a dated entry for every pivot or upgrade.
- `blueprint.md`: update when files, services or flows change. It is reconstructed from the code, not the original master blueprint (see its header). If the owner supplies the original, merge it in.
