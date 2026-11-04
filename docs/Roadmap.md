# UnderBlue roadmap

Status: draft, updated 4 Nov 2026 (iPhone 1.1.10 on the App Store). Nothing here is decided unless a line says "Jake".

This page only collects open work. Each row points to the document that holds the details.

## Where we are (4 Nov 2026)

- iPhone 1.1.10 (16) is on the App Store. It was released on 3 Nov 2026 at 16:57 UTC (App Store lookup, 4 Nov 2026). New: the free trial with a watermark (row 1.7).
- The landing pages describe the new trial since 4 Nov 2026 (`underblue-support` 3aa32ac).
- iPhone 1.1.9 (15) was released on 1 Nov 2026 at 21:53 UTC (App Store lookup, 3 Nov 2026).
- iPhone 1.1.8 (14) was released on 31 Oct 2026 at 17:10 UTC (Jake; App Store lookup, 1 Nov 2026). New since 1.1.7 ([AppStoreRelease](AppStoreRelease.md)):
  - each video scene fits its reef colour to the photo rule
  - the restored path no longer takes the cast off twice
  - SDR video export matches the preview; the preview shows the original until the analysis is done
  - a video export pauses in the background and goes on when the app is back
  - a rating prompt from the 10th save, only online
- The 1.1.8 code is on `main` and pushed.
- The Mac app 1.0 (1): App Review rejected it on 27 Oct 2026 for "for Mac" in the name (Guideline 5.2.5). It was resubmitted on 28 Oct 2026 with the same build and a new name ([MacAppStoreRelease](MacAppStoreRelease.md)). Jake, 3 Nov 2026: the review is still in progress. An App Store lookup by bundle ID on 4 Nov 2026 found no Mac app.
- The restoration run is done for photos ([RestorationExperiments](RestorationExperiments.md)).
- 28 Oct 2026: the website has landing pages in six languages, and Google Search Console is set up ([AppStoreRelease](AppStoreRelease.md#website-and-google-search-console-28-oct-2026)).

## 1. iPhone device checks (on hold)

Most rows are Jake's checks on the iPhone. Jake, 3 Nov 2026: not now. Jake, 4 Nov 2026: still later.

| # | Work | State | Source |
|---|---|---|---|
| 1.1 | Video export pause: lock the screen, take a phone call, a 4K and an HDR export | Open. Checked only with Settings in front for 16 s and 120 s. | [Verification](Verification.md) |
| 1.2 | Rating prompt on a device: the sheet from the 10th save; no second sheet in the same version; no sheet in airplane mode | Open. Unit tests only. | [Verification](Verification.md) |
| 1.3 | Press-and-hold subject pick on the iPhone (U6) | Open. Jake checks. | [ManualSubject](ManualSubject.md) |
| 1.4 | Labs orb switch: export takes longer when on | 26 Oct: about 4.5 s longer. After the 48 MP fix: 4.2-4.4 s off, 5.1-5.8 s on (20 MP). Not explained. Labs only, off by default. | [Verification](Verification.md) |
| 1.5 | Jake's iPhone checks: jellyfish legs and fins clip 31% (source 23.6%); napoleon clip at 6.7 s, the red rise is smaller, not gone; shallow-water shark photo (3 Oct); subject strength slider drag | Open. Jake checks. If the slider still lags, cache the frame before the lift. | [Verification](Verification.md), [ManualSubject](ManualSubject.md) |
| 1.6 | JPEG colour resolution test fails on the simulator (2x2 sampling) | Open. It also fails before the 31 Oct changes. Not checked on a device. | [Verification](Verification.md) |
| 1.7 | Free trial with watermark: 3 photos, then 1 photo every 24 hours; 1 video every 24 hours; a mark on every free export (Jake, 2 Nov) | In iPhone 1.1.10 (16), on the App Store since 3 Nov 2026. Device checks are open. Store text and What's New are in [AppStoreMetadata](AppStoreMetadata.md). Landing pages updated on 4 Nov 2026 ([AppStoreRelease](AppStoreRelease.md)). The Mac 1.0 build in review has the old trial; the next Mac build gets the new one. | [Verification](Verification.md) |

## 2. Mac app 1.0 release (after the first review)

Order matters. The hardening changes the binary, so it comes before the archive and the checks.

| # | Work | State | Source |
|---|---|---|---|
| 2.1 | Hardening: archive, measure `strings`/`nm`/metallib, turn off Swift reflection names, rename Metal kernels | Jake: do it before the next Mac build. Jake, 3 Nov 2026: start after the first Mac review ends. The iPhone 1.1.7 archive is measured: the archive strips symbols; field names and Metal names stay. | [MacAppStoreRelease](MacAppStoreRelease.md#hardening) |
| 2.2 | Mac archive, then signed-build checks: folder write after relaunch, Finder share menu, Pro after relaunch, Restore Purchase | Open. | [MacAppStoreRelease](MacAppStoreRelease.md) |
| 2.3 | Labs orb switch redraws the Mac preview | Jake: check before the Mac archive. | [Verification](Verification.md) |
| 2.4 | Metadata parts 2 and 3, IAP display name and description | Waits for Jake's review. | [MacAppStoreRelease](MacAppStoreRelease.md) |
| 2.5 | Japanese and Chinese text: ship as is, or get a native review | Jake decides. | [MacAppStoreRelease](MacAppStoreRelease.md) |
| 2.6 | Thin bright or dark lines on some edges (turtle, clownfish) | Softer since `ad6ab7f`, not gone. | [MacApp](MacApp.md) |
| 2.7 | Memory on 8 GB Macs and long 4K video | Not measured. | [MacApp](MacApp.md) |
| 2.8 | After the release: Mac App Store link on the website (`MAC_APP_STORE`) | Open. The site says "coming soon" until then. | [MacAppStoreRelease](MacAppStoreRelease.md) |

## 3. Video quality (after the Mac release)

| # | Work | State | Source |
|---|---|---|---|
| 3.1 | m6 reef stays olive in video (photo is brown) | Fixed in 1.1.8 (Jake, 29 Oct): each scene fits the video rule to the photo rule on its keyframe. Video reef hue 132 → 98 (photo 93). Open: a real reef clip and the cost on the iPhone. | [RestorationExperiments](RestorationExperiments.md) |
| 3.2 | Apple Log: real clips (Log ProRes, Log 2 ProRes and HEVC), look of mid-tones | Generated clips only. Needs footage. | [Verification](Verification.md) |
| 3.3 | Preview and export use different gamma (1.961 and 2.4) | Fixed in 1.1.8: the SDR export now encodes like the preview. Jake checks on the iPhone. | [Verification](Verification.md) |
| 3.4 | Particle filter for video | Off by default. Jake: record only for now. Turn on at about +20% time and +100 MB. | [RestorationExperiments](RestorationExperiments.md) D2 |
| 3.5 | Napoleon clip, first 2 s: the fish is pink, then grey at 1.5 s | Closed (Jake, 3 Nov 2026): the pink is in the source, so it stays. The correction makes the step 1.85x bigger. The only fix found changes every photo. | [ColorAlgorithm](ColorAlgorithm.md) |
| 3.6 | Preview speed on older iPhones and on a hot iPhone (thermal state 2 or higher) | Not measured. The 30 M px/s budget comes from one iPhone 17. | [Verification](Verification.md) |

## 4. Photo quality (open, no plan yet)

| # | Work | State | Source |
|---|---|---|---|
| 4.1 | Green seagrass shifts 10-32 degrees toward yellow | Studied, not adopted. Colour alone cannot tell olive reef from seagrass. | [RestorationExperiments](RestorationExperiments.md) |
| 4.2 | Bright sand grain on m5: 2.07x (Sea-thru 1.43x) | Better after `ca75540`, still above the reference. | [RestorationExperiments](RestorationExperiments.md) |
| 4.3 | Smaller lift on translucent parts (fins) | Jake: on hold until a real photo shows it. | [ManualSubject](ManualSubject.md) |
| 4.4 | VoiceOver way to pick a subject | Not designed. | [ManualSubject](ManualSubject.md) |

## 5. Waiting for a decision

| # | Idea | State | Source |
|---|---|---|---|
| 5.1 | LUT presets (fixed pool, auto pick) | Jake is not sure it is needed (26 Oct). Nothing built. | [LUTPresets](LUTPresets.md) |
| 5.2 | iPhone Duo, stage 2 | Waits for Xcode 27.1. | [iPhoneDuoSupportPlan](iPhoneDuoSupportPlan.md) |
| 5.3 | ProRAW 48 MP and many 48 MP photos in one batch | Jake: accepted as open (26 Oct). | [Verification](Verification.md) |
| 5.4 | "Changes waiting for the final round" (5 commits) | The list dates from 29 Sep. Not updated since. Jake: run the round, or close the list. | [Verification](Verification.md) |

Decided against for now (Jake): finishing an export in the background, a call during export (follows the background rule), and Android.

Kept as is (Jake, 4 Nov 2026): the player's own play button plays the whole video, also for free users. Only the 3s Preview button stops after 3 s. A screen recording of the preview has no watermark, and Jake accepts this. A screenshot of a photo preview is the same.

## 6. Flow review findings (4 Nov 2026)

A static code review of the user flows on iPhone and Mac. Each row was confirmed by reading the code. Jake reviews them one at a time. 16 more candidates are not listed: 12 need a run before they count, and 4 were not checked again (mostly Labs subject picking).

| # | Area | Finding | Code | State |
|---|---|---|---|---|
| 6.1 | iPhone export | A swipe on "Ready to save" deleted the file; the trial was already used | `EditorView.swift:46` | Fixed (Jake, 4 Nov). See [Verification](Verification.md) |
| 6.2 | Mac trial | A failed run uses the trial when an earlier item in the queue is done | `MacModel.swift:391` | Fixed (Jake, 4 Nov). In the next Mac build. See [Verification](Verification.md) |
| 6.3 | iPhone import | "Importing…" has no Cancel, and the home screen is locked | `HomeView.swift:56` | Fixed (Jake, 4 Nov). Cancel not run yet. See [Verification](Verification.md) |
| 6.4 | iPhone editor | A preset change during the first photo render does not show | `EditorView.swift:36` | Fixed (Jake, 4 Nov): the look controls wait for the analysis. See [Verification](Verification.md) |
| 6.5 | iPhone batch | With Photos access denied, every photo renders, then each save fails | `BatchModel.swift:131` | Waits for Jake |
| 6.6 | iPhone purchase | After buying Pro in the same editor, the options stay at 1080p SDR | `ExportOptions.swift:36` | Waits for Jake |
| 6.7 | Mac settings | The save place can change during a run; "Show in Finder" then opens the wrong place | `SettingsView.swift:10` | Waits for Jake |
| 6.8 | Mac share | A share that arrives during a batch is not added after it, with no notice | `MacModel.swift:200` | Waits for Jake |
| 6.9 | iPhone batch | The summary leaves out save failures, Cancel and a background stop | `BatchModel.swift:131` | Waits for Jake |
| 6.10 | Mac free | Many files give only the paywall; no way to correct only the selected one | `MacModel.swift:357` | Waits for Jake |
| 6.11 | iPhone editor | A failed open leaves a black screen with no Retry | `EditorModel.swift:180` | Waits for Jake |
| 6.12 | iPhone Custom | Reset sets the saved sliders to 0 at once, with no undo | `CustomAdjustmentControls.swift:53` | Waits for Jake |
| 6.13 | iPhone purchase | After a purchase, the Pro screen still shows the wait for the next free photo | `ProView.swift:17` | Waits for Jake |
| 6.14 | iPhone save | The Photos permission alert has no "Open Settings" button | `ExportView.swift:151` | Waits for Jake |
| 6.15 | Share extension | Cancel during the last copy can still finish the share; the effect needs a run | `ShareModel.swift:28` | Waits for Jake |

## Recommended order

1. Wait for the Mac 1.0 review. Section 1 device checks are on hold (Jake, 3 and 4 Nov 2026).
2. Section 2, after the Mac review ends: the Mac release, hardening first. The app is built, and the Mac price is the higher one ([MacApp](MacApp.md)).
3. Section 3: 3.1 and 3.3 shipped in 1.1.8 and wait for Jake's check on the iPhone. 3.2 waits for real Log clips.
4. Sections 4 and 5 only when a real photo or a user asks for it.
5. Section 6 runs beside these: Jake reviews one finding at a time.
