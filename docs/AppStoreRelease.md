# App Store release checklist

Last reviewed: 2026-11-11

## Current release: iPhone 1.1.14 (build 20), 11 Nov 2026

iPhone only. The Mac targets stay at 1.0 (1).

- 1.1.13 (19) was in App Review when 1.1.14 (20) was built (11 Nov 2026).
- 1.1.14 (20) was uploaded to App Store Connect on 11 Nov 2026 with `xcodebuild -exportArchive` (method `app-store-connect`, destination `upload`, symbols included). The upload succeeded and was processing. Not submitted for review.
- Archive: `~/Library/Developer/Xcode/Archives/2026-11-11/UnderBlue 1.1.14 (20).xcarchive`. Checked: app and share extension are both 1.1.14 (20); iPhone only (device family 1); both have the App Group `group.com.underblue.app`; dSYMs for both.
- New since 1.1.13 (`Roadmap.md` section 8): the video preview zooms like the photo preview (pinch, double tap, pan while zoomed, up to 4x), also while it plays. No zoom and no playback while the scene is analysed.
- Release note: not chosen yet. Jake enters it in App Store Connect.
- Tests (11 Nov 2026, iPhone 17 simulator, iOS 27.2): 333 iOS unit tests, 13 skipped, 2 failed.
  - Known: JPEG colour resolution.
  - `BatchTests` summary: the simulator returned the Korean text, the test expects English. Batch code did not change.
  - `PurchaseTests` not run: it hung for 30 minutes and was stopped.
  - The 4 new `CustomPresetUITests` pass. The Mac app builds. Mac tests not run.

## iPhone 1.1.13 (build 19), 10 Nov 2026 (history)

iPhone only. The Mac targets stay at 1.0 (1).

- The App Store still showed 1.1.11 on 10 Nov 2026 (App Store lookup). 1.1.12 (18) was uploaded on 9 Nov 2026; whether it went to App Review was not checked here.
- 1.1.13 (19) was uploaded to App Store Connect on 10 Nov 2026 with `xcodebuild -exportArchive` (method `app-store-connect`, destination `upload`, symbols included). The upload succeeded and was processing.
- 1.1.13 (19) was submitted for App Review on 10 Nov 2026 (Jake).
- Archive: Xcode 27.2 (27B52), iOS SDK 27.2, `~/Library/Developer/Xcode/Archives/2026-11-10/UnderBlue 1.1.13 (19).xcarchive`. Checked: app and share extension are both 1.1.13 (19); iPhone only (device family 1); both have the App Group `group.com.underblue.app`; dSYMs for both; the new strings are in all six `Localizable.strings`.
- Release note: `AppStoreMetadata.md`, "What's New (1.1.13)": the general note, as in 1.1.11 (Jake, 10 Nov 2026).
- Tests (10 Nov 2026): 332 iOS unit tests on the iPhone 18 Pro simulator (iOS 27.2): 1 known failure (JPEG colour resolution), 13 skipped probes. `PurchaseTests` not run (decision). `ExportSheetTests` UI test passes on the iPhone 17 simulator (iOS 27.2). The Mac app builds. Mac tests not run.
- Device checks (iPhone 17, Debug build): see `Verification.md`, "Export: Quick, quality levels, estimate".

New since 1.1.12 (`Roadmap.md` section 7):
- Video export: Original / 1080p / Quick (at most 720p, 30 fps). A quality level for each: High / Standard / Small. Defaults: Original High, 1080p Standard, Quick Small. Free: 1080p Standard only.
- The bitrate never goes above the source's average bitrate × the level.
- The time estimate uses this device's saved speed, so it shows at once. One 1080p probe runs only when no speed is saved yet.
- The export options refuse a choice the user may not make. Before, a free user could pick Pro-only choices, and anyone could pick HDR for an SDR video.
- The batch screens now export videos at High.

## iPhone 1.1.12 (build 18), 9 Nov 2026 (history)

iPhone only. The Mac targets stay at 1.0 (1).

- 1.1.11 (17) is on the App Store since 5 Nov 2026 at 17:35 UTC (App Store lookup, 9 Nov 2026).
- 1.1.12 (18) was uploaded to App Store Connect on 9 Nov 2026 with `xcodebuild -exportArchive` (method `app-store-connect`, destination `upload`, symbols included). The upload succeeded and was processing.
- Archive: Xcode 27.2 (27B52), iOS SDK 27.2, `~/Library/Developer/Xcode/Archives/2026-11-09/UnderBlue 1.1.12 (18).xcarchive`. Checked: app and share extension are both 1.1.12 (18); iPhone only (device family 1); both have the App Group `group.com.underblue.app`; dSYMs for both.
- Release note: `AppStoreMetadata.md`, "What's New (1.1.12)". It names the fix (Jake, 9 Nov 2026).
- Tests (9 Nov 2026): 318 iOS unit tests on the iPhone 18 Pro simulator (iOS 27.2): 1 known failure (JPEG colour resolution), 13 skipped probes. `PurchaseTests` not run (decision). `ExportSheetTests` UI test passes on the iPhone 17 simulator (iOS 27.2). Mac tests not run (no Mac change).
- Device check (iPhone 17, Debug build, 9 Nov 2026): the editor estimate with a 1182 × 2560 120 fps HEVC clip. With 333 MB free it ran no probe and the app stayed alive. With 888 MB free it showed both estimates.

New since 1.1.11:
- The export time estimate no longer ends the app when memory is low. The estimate runs a real 1 s export for each size. A 1182 × 2560 120 fps probe took 370-570 MB on an iPhone 17. Started with 344 MB free, it ended the app process. Now a size is measured only when its export could start (the same memory check as Export).
- A free user gets no estimate for an original above 1080p. That choice is disabled for free users anyway.
- On the simulator, free memory is read from the Mac. `os_proc_available_memory` returned 0 there, so the memory check always reported a shortage.

## iPhone 1.1.11 (build 17), 5 Nov 2026 (history)

iPhone only. The Mac targets stay at 1.0 (1).

- 1.1.10 (16) is on the App Store since 3 Nov 2026 at 16:57 UTC.
- 1.1.11 (17) was submitted for App Review on 5 Nov 2026 (Jake). It was released on 5 Nov 2026 at 17:35 UTC (App Store lookup, 9 Nov 2026).
- Archive: Xcode 27.2 (27B52), iOS SDK 27.2, `~/Library/Developer/Xcode/Archives/2026-11-05/UnderBlue 1.1.11 (17).xcarchive`. Checked: app and share extension are both 1.1.11 (17); iPhone only (device family 1); both have the App Group `group.com.underblue.app`; dSYMs for both.
- Release note: `AppStoreMetadata.md`, "What's New (1.1.11)". Jake, 5 Nov 2026: say only that usability and stability improved.
- App Review notes: paste them again (`AppStoreMetadata.md`, "App Review notes"). Changed on 4 Nov 2026: the free trial opens its 3 welcome photos together.
- Tests (5 Nov 2026): 315 iOS unit tests on the iPhone 18 Pro simulator (iOS 27.2): 1 known failure (JPEG colour resolution), 13 skipped probes. `PurchaseTests` not run (decision). Mac: 30 unit tests pass, 2 skipped (4 Nov, no Mac change since). UI tests: 4 Nov, see `Verification.md`.
- Device checks: open in `Verification.md`. On Jake's iPhone 17 only the two denied-access UI tests ran (4 Nov 2026, Debug build).

New since 1.1.10 (flow review in `Roadmap.md` section 6):
- A swipe no longer deletes a finished export; Discard asks first; a free export uses the trial only when saved (6.1).
- Cancel while importing (6.3).
- The look controls wait for the analysis (6.4).
- Batch: Photos access is checked before any render (6.5); the summary names save failures and why it stopped (6.9).
- After buying Pro in the editor, the export options come back to the full choice (6.6).
- A first install takes its 3 free photos in one batch (6.10).
- A failed open shows the reason and Try again (6.11).
- Custom Reset asks first (6.12).
- The Pro screen drops the wait line and the pending line once Pro unlocks (6.13).
- A Photos permission error offers Open Settings (6.14); a failed save no longer deletes the finished file (6.16).
- A share cancelled during its last copy no longer opens later (6.15).

## iPhone 1.1.10 (build 16), 3 Nov 2026 (history)

iPhone only. The Mac targets stay at 1.0 (1).

- 1.1.9 (15) was released on 1 Nov 2026 at 21:53 UTC (App Store lookup, 3 Nov 2026).
- 1.1.10 (16) is on the App Store. It was released on 3 Nov 2026 at 16:57 UTC (App Store lookup, 4 Nov 2026). New since 1.1.9:
  - Free trial: 3 photo exports, then 1 photo every 24 hours. 1 video export (first 10 s) every 24 hours.
  - Every free export carries a small UnderBlue watermark. Pro exports have none.
- Archive: Xcode 27.2 (27B52), `~/Library/Developer/Xcode/Archives/2026-11-03/UnderBlue 1.1.10 (16).xcarchive`. Checked: app and share extension are both 1.1.10 (16); iPhone only (device family 1); both have the App Group `group.com.underblue.app`; dSYMs for both.
- Release note: `AppStoreMetadata.md`, "What's New (1.1.10)". The description sections and the App Review notes also describe the new trial. Paste them with this version.
- Tests (3 Nov 2026): 311 iOS unit tests on the iPhone 18 Pro simulator (iOS 27.0): 1 known failure (JPEG colour resolution), 13 skipped probes. 24 Mac unit tests: no failure, 2 skipped. `PurchaseTests` not run (decision). UI tests not run.
- Checks: `Verification.md`, "Free trial with watermark". The device checks are open. Jake, 4 Nov 2026: they wait.
- Landing pages: rebuilt on 4 Nov 2026, after the release (`underblue-support` 3aa32ac). Only the trial text changed, on the six home pages.
- The IAP description now names the watermark in all six languages (`AppStoreMetadata.md`). Submit the IAP change with 1.1.10.
- Jake approved the IAP description and the What's New text in all six languages on 3 Nov 2026. The ja, zh and es lines were also checked by a reviewer agent.

## iPhone 1.1.9 (build 15), 1 Nov 2026 (history)

iPhone only. The Mac targets stay at 1.0 (1).

- 1.1.8 (14) is on the App Store. It was released on 31 Oct 2026 at 17:10 UTC (Jake; App Store lookup, 1 Nov 2026). Its release note is in `AppStoreMetadata.md`.
- 1.1.9 (15) is submitted for App Review (Jake, 1 Nov 2026). New since 1.1.8:
  - Video: no light detail. Dark fish in bright water no longer get a thin white ring in 4K exports.
- Archive: Xcode 27.2 (27B52), iOS SDK 27.2. The unit tests and the iPhone 17 check ran on the 27.1 SDK, before Xcode updated during the session. Xcode 27.2 needed the Metal Toolchain again.
- Release note: `AppStoreMetadata.md`, "What's New (1.1.9)", written on 1 Nov 2026. The text Jake entered in App Store Connect was not checked here.
- Checks: `Verification.md`, "Video: no light detail" (1 Nov 2026). Jake checked the fix on the iPhone 17.
- Known test failures: the JPEG colour resolution test fails on the iOS 27.1 simulator, also before these changes (`Verification.md`, 31 Oct). On the iOS 26.5 simulator, one subject picker test fails because it needs iOS 27 (`Verification.md`, 1 Nov).
- Not fixed: the first 2 s of the napoleon clip stay pink (`Roadmap.md` 3.5).

## iPhone 1.1.4 (build 10), 23 Oct 2026 (history)

iPhone only. The Mac targets stay at 1.0 (1) and were not checked for this build.

New since 1.1.3: the camera JPEG reef colour, and the Icon Composer app icon (`IconComposer.md`,
step 3). The video work of 22 Oct 2026 shipped in 1.1.3. The subject picker and subject emphasis are
not in it; they live on branch `subject-picker`.

Release note: "More natural reef colours in JPEG photos." It does not mention the new icon.

Checks run for it are in `Verification.md`, "Camera JPEG reef colour".

Store page work for 1.1.4 (23 Oct 2026). Jake submitted the app the same day.

- New app icon: `UnderBlue/Resources/AppIcon.icon` (Icon Composer), in build 10. See `docs/IconComposer.md`.
- Product page header: `AppStoreAssets/Screenshots/header/universal-5244x2950.png`, uploaded by Jake.
- Search results (same file), Korean metadata (`docs/AppStoreMetadata.md`) and Korean screenshots (`AppStoreAssets/Screenshots/ko/final`): prepared. The Korean app information was already in App Store Connect before 1.1.5 (Jake, 24 Oct 2026); the screenshot upload is not recorded.
- Product Page Optimization: not used (Jake, 23 Oct 2026).

## Release decision for 1.0 (history, 29 Sep 2026)

The current source colour pipeline changed after the last App Store Connect archive and screenshot capture.
Do not submit the existing archive or the old `final-v2` screenshots as the final 1.0 assets.
The change improves the m5 photo and its colour panel, but it does not yet pass every colour-quality
criterion: several individual panel patches and evaluation images regress, Sea-thru subjects remain
too cyan/bright, and the constant-depth video proxy still has sand/noise and shadow regressions.

Evidence and scope are recorded in [the m5 evaluation](M5ColorEvaluation.md) and
[the additional Sea-thru/AquaColorFix review](AdditionalReferenceReview.md). Before release, either:

1. accept these documented limits as the 1.0 colour behavior, rerun the physical-device matrix and
   capture a fresh archive and screenshots from exactly that source; or
2. continue colour work, then repeat the same evaluation and release checks.

An App Store Connect form being complete does not override this local release gate.

## Xcode configuration

- Product: `UnderBlue`
- Bundle ID: `com.underblue.app`
- Version: `1.0`
- Build: `1`
- Minimum OS: iOS 26.0
- Signing: Automatic, team `M3HJ7YK7N7`
- Share extension: `UnderBlueShare`, bundle ID `com.underblue.app.share`, embedded in the app
- App Group: `group.com.underblue.app`, in both the app and the extension entitlements. Automatic signing registered both on 28 Sep 2026. The old App Store profile has no App Group, so the next archive creates a new one.
- App icon: 1024×1024 PNG without alpha
- Release debug information: DWARF with dSYM
- Release validation, whole-module optimization and dead-code stripping: enabled
- Non-exempt encryption: `NO` (the app contains no proprietary encryption)
- App category in the generated Info.plist: `public.app-category.photography`

All four targets—`UnderBlue`, `UnderBlueShare`, `UnderBlueTests` and `UnderBlueUITests`—are explicitly limited to:

- Supported platforms: `iphoneos iphonesimulator`
- Targeted device family: iPhone (`1`)
- Mac Catalyst: disabled
- Designed for iPhone/iPad on Mac: disabled
- Designed for iPhone/iPad on Apple Vision: disabled

The latest device build was verified with `UIDeviceFamily = [1]`, `CFBundleSupportedPlatforms = ["iPhoneOS"]` and `LSRequiresIPhoneOS = true`. Xcode may still list iPad simulators as run destinations because iPhone-only apps can run in iPadOS compatibility mode. This does not enable native iPad support and does not require iPad screenshots.

The add-only Photos usage description is localised through `InfoPlist.xcstrings`. The privacy manifest declares no tracking and lists required-reason API usage for disk space, file timestamps and app-only UserDefaults. The share extension calls none of the required-reason APIs; its code was checked on 28 Sep 2026. So it has no privacy manifest of its own. UnderBlue has no automatic analytics or diagnostic upload.

## Prepared App Store Connect values

- App name: `UnderBlue` (availability must be confirmed in App Store Connect)
- Platform: iOS
- Primary language: English (U.S.)
- Suggested SKU: `UNDERBLUE-IOS-001`
- Subtitle: `Underwater colour, restored`
- Primary category: Photo & Video
- Secondary category: None
- App price: Free
- Distribution: Public
- Version release: Manual release recommended for 1.0
- Content rights: no bundled or streamed third-party content
- Sign-in/demo account: not required
- Regulated medical device: No
- Custom EULA: use Apple's standard EULA

The complete English and Korean descriptions, promotional text, keywords and review notes are in `AppStoreMetadata.md`.

## Public support and privacy pages

- Support URL: <https://jakeleekr13-otter.github.io/underblue-support/support/>
- Privacy Policy URL: <https://jakeleekr13-otter.github.io/underblue-support/privacy/>
- Public website repository: <https://github.com/jakeleekr13-otter/underblue-support>
- Support email: `support@enheart.me`
- Privacy email: `privacy@enheart.me`

## Website and Google Search Console (28 Oct 2026)

- Landing page: <https://jakeleekr13-otter.github.io/underblue-support/>. It is not the Marketing URL yet (4 Nov 2026: the live App Store page links only support/ and privacy/). Set the Marketing URL with the next version. The per-language list is in `AppStoreMetadata.md`, "Public URLs".
- Languages: English at the root, then `/ko/`, `/ja/`, `/zh-hans/`, `/zh-hant/` and `/es/`.
- The pages are generated. Do not edit them by hand. Edit the store copy in `AppStoreMetadata.md` or `captions.json`, then run this from the `underblue-support` clone:
  `python3 -I _build/build_landing.py <path to this repo>`
  - Page titles and the Mac text are in the script itself.
  - The script also rewrites `sitemap.xml`.
  - GitHub Pages does not publish `_build/`.
  - Since 2 Nov 2026 the description sections describe the watermark trial. 1.1.10 has that trial. The script ran on 4 Nov 2026, after its release.
- The App Store badge links to the iPhone app (`id6815881625`). The Mac section says "coming soon" until `MAC_APP_STORE` is set in the script.
- Since 5 Nov 2026 every landing page ends with an "Also by Enheart" card for Bubbly Dive Logbook (`id6813368660`, same seller). Its link and text are `SISTER_APP` and `sister_h`/`sister_p` in the script (Jake). The root hub links it too.
- Search Console:
  - The property is the URL prefix above. A Domain property is not possible on github.io.
  - It is verified by `google98d8e981a7645ba2.html` at the site root. Never delete that file.
  - The sitemap was submitted on 28 Oct 2026. After the submit, the status read "Couldn't fetch".
  - 4 Nov 2026: Google had still crawled nothing on the site. The sitemap still read "Couldn't fetch" and the root was unknown to Google.
  - Same day, a root site was added: repo `jakeleekr13-otter/jakeleekr13-otter.github.io`. It serves `robots.txt` (with a `Sitemap:` line for this sitemap), a small hub page with links, and a copy of the verification file.
  - A second Search Console property, `https://jakeleekr13-otter.github.io/`, verified on its own with that file. It has the robots.txt and crawl stats reports. Google fetched the root robots.txt at 09:41 CST on 4 Nov.
  - The indexing-request quota is not per property. About 12 requests a day in total.
  - `support/` and `privacy/` are hand-written, not generated. Since 4 Nov their footers link to the landing page, because the App Store links only to these two pages.
  - 5 Nov 2026: indexing is now requested for all 21 guide URLs (the last 9 today, all "색인 생성 요청됨").
  - 5 Nov 2026, landing property: the sitemap still reads "가져올 수 없음" with 0 pages. The Pages report still says it is processing data. The landing root is still unknown to Google.
  - 5 Nov 2026, root property: the root hub `https://jakeleekr13-otter.github.io/` is indexed. Google crawled it on 4 Nov at 10:31 CST (Googlebot smartphone). Indexing was requested again. Crawl stats (updated 3 Nov): 5 requests, no host problems. The only 404 is `/favicon.ico`, because the root site has none.

Both pages are publicly available over HTTPS. Their email addresses are clickable `mailto:` links. The repository's `main` branch blocks force pushes and deletion and needs a linear history (no merge commits); only the owner has direct repository access.

## App Privacy declaration

App Store Connect is intentionally configured conservatively as collecting diagnostics because a user may explicitly email a generated report to the developer.

- Data collection: Yes
- Crash Data: collected only when the user explicitly shares a report
- Performance Data: collected only when the user explicitly shares a report
- Other Diagnostic Data: collected only when the user explicitly shares a report
- Purpose: App Functionality (customer support and reliability)
- Linked to the user: No. Set in App Store Connect on 29 Sep 2026 (all four types: App Functionality only). This needs the support process below that keeps a report apart from the sender's email.
- Tracking: No
- Advertising or marketing use: No
- Photos or Videos: collected only when the user explicitly emails a photo or video to support (added 29 Sep 2026)
- Location: Not collected
- Device ID: Not collected
- Automatic upload: No

If a diagnostic attachment is retained together with the sender's email address, mark it as linked to the user. Mark it as not linked only if the support process separates the report from the sender identity and does not attempt to reconnect them. Keep the App Store Connect response and the public privacy policy consistent with the actual support workflow.

## Screenshots and promotional assets

Five uploadable English iPhone screenshots are in `AppStoreAssets/Screenshots/en-US/final`.
Each is a 1320×2868 RGB JPEG without alpha. They were rendered on 29 Sep 2026 from the device
captures in `en-US/source` by `scripts/app_store_screenshots/render.js`. The old `final-v2` set and its
generator were deleted on 24 Oct 2026; they are in git history.

1. `01-before-after.jpg`
2. `02-photo.jpg`
3. `03-video.jpg`
4. `04-looks.jpg`
5. `05-private.jpg`

The first image is an authentic same-frame before/after comparison. The source capture and the corrected capture were produced by the app from developer-owned media. UIEB benchmark images are excluded because the dataset is academic/non-commercial and forbids redistribution.

iPhone Duo screenshots are in `AppStoreAssets/Screenshots/iphone-duo-en-US` (19 Oct 2026). They are raw
captures from the iPhone Duo simulator (iOS 27.1), flattened to RGB PNG without alpha, with the clock fixed at 9:41.
Inner display, 2853×2007: `inner-1-corrected`, `inner-2-original`, `inner-3-batch`. Cover display, 1398×2034:
`outer-1-editor`, `outer-2-home`. The photos come from `DeveloperMedia/eval/real`; confirm they are developer-owned before upload.
There is no video shot: video playback fails on the Duo simulator (see `docs/iPhoneDuoSupportPlan.md`).
The need for Duo-size screenshots is from the plan document and is not checked against App Store Connect.

An App Preview video is optional and is intentionally omitted from the first submission.

The optional 1024×1024 promoted-IAP image is `AppStoreAssets/IAP/UnderBluePro-1024.png`. It is not the
IAP review screenshot. The real purchase-screen review screenshot is
`AppStoreAssets/IAP/UnderBluePro-Review-1206x2622.png`; it shows the production price, feature list,
one-time purchase wording, Restore Purchase and Redeem Code. It is RGB without alpha and matches an
accepted iPhone screenshot size.

## UnderBlue Pro In-App Purchase

- Type: Non-Consumable
- Reference name: `UnderBlue Pro`
- Product ID: `com.underblue.pro`
- English display name: `UnderBlue Pro`
- English description: `No watermark or limits, full video, 4K, HDR` (since 1.1.10; at most 45 characters)
- Availability: match the app's selected territories
- App Store Server Notifications URL: leave blank; UnderBlue has no server
- Family Sharing: leave off for the first release unless it is explicitly tested and accepted as an irreversible setting

The production price is USD 14.99 (Jake, 29 Sep 2026). The local StoreKit configuration's USD 4.99 value is test data only. The first IAP must be included in the same App Review submission as app version 1.0.

## Remaining App Store Connect work

Jake reported on 29 Sep 2026 that every App Store Connect item except the screenshots was done.
Since then, the local colour source changed; the selected build and screenshots must therefore be
replaced after the release decision above.

- [x] Confirm that the `UnderBlue` name is available and create/verify the app record.
- [x] Confirm the final SKU before creating the record; it cannot be changed afterward.
- [x] Accept the Paid Apps Agreement and complete banking and tax information.
- [x] Complete EU Digital Services Act trader status and any territory-specific compliance questions.
- [x] Choose the app territories; exclude a territory temporarily if App Store Connect requests documentation that is not ready.
- [x] Complete the age-rating questionnaire with no mature, social, advertising, gambling or unrestricted-web content; expected result is 4+.
- [x] Enter the copyright owner using the Apple Developer account's legal name.
- [x] Enter a reachable App Review contact name, email and international-format phone number.
- [x] Create `com.underblue.pro`, choose its production price and tax category, and add its localisation.
- [x] Capture and upload the real UnderBlue Pro purchase-screen review screenshot.
- [ ] Recapture and upload five iPhone screenshots from the accepted final colour source.
- [x] Paste the prepared description, promotional text, keywords and App Review notes.
- [x] Publish the App Privacy answers and verify the Product Page Preview.
- [ ] Upload and select a fresh archive built from the accepted final source. The previously selected
  archive predates the current-source colour changes.
- [x] Add both iOS app version 1.0 and UnderBlue Pro to the same draft submission.

## Before each upload

1. Increase `CURRENT_PROJECT_VERSION` for every build previously uploaded to App Store Connect. Build `1` can be reused only if it has never been uploaded.
2. Increase `MARKETING_VERSION` only when creating a new App Store version.
   Change both numbers in the `UnderBlue` **and** `UnderBlueShare` targets. A mismatch fails App Store validation.
3. Run the physical-device matrices in `QA.md` and `VideoV2QA.md`. For the current colour candidate,
   include m5, at least one Sea-thru-like bright reef, AquaColorFix-like yellow subjects, and a real
   video with changing light. Confirm the photo result and actual video output, not only `uniform`.
4. Select **Any iOS Device (arm64)**, then Product → Archive.
5. In Organizer, run **Validate App** before **Distribute App**.
   Confirm the archive contains `PlugIns/UnderBlueShare.appex`, and that both profiles include the App Group.
6. Retain the archive and dSYM for crash symbolication.
7. Confirm the uploaded build reports iPhone-only device family and no Mac, Catalyst or Vision availability.

Do not upload the existing local archive blindly: create a fresh archive after the latest diagnostics, support-site and platform-setting changes. If build `1` has already reached App Store Connect, increment it before archiving.

## Current local verification

- Generic iOS device Debug build with code signing disabled: succeeded on 29 Sep 2026 after the latest
  colour changes. This proves compilation only; it is not a signed-device run or an archive validation.
- Native macOS colour checks: 72 passed, covering Metal/CPU agreement, reference evidence,
  Original/neutral preservation, colour separation, clipping protection and shadow-channel retention.
- Built-in presets: the tuned Natural, Tropical and Deep Dive looks from `8b9f278` were checked and
  accepted on an iPhone on 29 Sep 2026; `7b1a015` records that result. Recheck only if those values
  or the shared colour pipeline change again.
- Static image evaluation: m5 whole-image CIE76 19.71→17.25 and colour-panel mean 26.89→20.68.
  UIEB dev and holdout means improved slightly; AquaColorFix gate improved slightly.
- Known regressions remain: two m5 photo patches worsened by more than 1 CIE76; UIEB dev
  `114_img_.png` worsened by 2.12 photo / 2.17 uniform, and holdout `144_img_.png` worsened by
  1.53 uniform. Sea-thru generalization is not established.
- App/unit/UI `build-for-testing` and the 44-test functional result belong to an earlier source state.
  They must be rerun after the colour source is accepted. No simulator test was run for this colour task.
- Supported-target build settings verified for Debug; the same settings are generated for Release

## Crash and diagnostics intake

- TestFlight shares available crash reports through Xcode Organizer and App Store Connect TestFlight feedback.
- App Store crash reports appear in Organizer when customers share diagnostics with Apple.
- UnderBlue's MetricKit/error summary remains on the device until the user opens Diagnostics, prepares the JSON report and explicitly shares it.
- The local report includes privacy-safe aggregated photo/video restoration fallback events as well as common import, preview, export, save and purchase failures.
- The report excludes photos, videos, filenames, file paths, location, per-pixel data, raw error descriptions and `userInfo`.
- UnderBlue has no automatic diagnostic upload, analytics backend or automatic support-email transmission.
- Customers should email private diagnostic reports to `support@enheart.me`, not attach them to a public GitHub issue.

## Complimentary Pro access

`com.underblue.pro` is a non-consumable In-App Purchase. After the app is **Ready for Distribution** and the IAP is **Approved**:

1. App Store Connect → Apps → UnderBlue → In-App Purchases.
2. Open UnderBlue Pro and scroll to **Offer Codes**.
3. Create a **Free Offer**, select the intended eligibility groups and territories.
4. For a few friends, create a custom code with a small redemption limit and share its redemption URL. One-time-use batches currently start at 500 codes.
5. Codes can be valid for at most six months. The unlocked non-consumable itself does not expire after redemption.

Customers can redeem a code in the App Store, with its redemption URL, or in UnderBlue: Get Pro → Redeem Code opens Apple's redemption sheet (`offerCodeRedemption`, added 29 Sep 2026). A redeemed code arrives in `Transaction.updates` like a purchase.

Before release, use Sandbox offer codes or TestFlight. Production custom and one-time-use codes are not generated until both the app and IAP are approved.
