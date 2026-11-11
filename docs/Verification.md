# Pending verification

This page lists the checks that are still open. The product owner decided to finish the implementation first and run every check in one final round (25 Sep 2026). Each change already has its own unit tests.

## Export: Quick, quality levels, estimate (10 Nov 2026, iPhone 1.1.13 (19), in App Review)

What changed (Jake, 10 Nov 2026; [Roadmap](Roadmap.md) 7.1, 7.4, 7.6, 7.7):
- Resolution: Original / 1080p / Quick. Quick is at most 720p and 30 fps.
- Quality: High / Standard / Small for each resolution. Defaults: Original High, 1080p Standard, Quick Small. Free: 1080p Standard only.
- The bitrate never goes above the source's average bitrate × the level.
- The estimate is the frame count × this device's saved time per frame. With no saved value, one 1080p probe runs first.
- Sheet lock: a free user could pick Quick, High or Small, and anyone could pick HDR for an SDR video. The rows had `.disabled`, which did not stop the tap. The pickers now refuse those values, and locked rows show a lock.
- New strings in six languages: "Quick" (the Korean label says "Quick mode", Jake), "Quality", "High", "Standard", "Small" and two footnotes. A reviewer agent checked ja, zh-Hans, zh-Hant and es.

Checked:
- Unit tests: `ExportQualityTests` (sizes, frame steps, the frame grid, bitrate levels and cap, defaults, trial, estimate, saved speed, three real exports), `ExportSizeTests`, `VideoTests`, `BatchTests` on the iPhone 18 Pro simulator (iOS 27.2). The Mac app builds.
- `ExportSheetTests` (UI, iPhone 17 simulator, free user): estimates show, Standard is selected, and taps on High, Quick and HDR change nothing. With the old HDR picker the HDR tap selected HDR (the test failed).
- iPhone 17: Quick from 120 fps gave 30 fps, 760 frames, 590 × 1280. A 60 fps 10-bit HLG clip with Quick gave 30 fps, 60 frames, HLG, 10-bit.
- iPhone 17: the first estimate ran one probe (4.85 s). The second came from the saved speed at once.
- iPhone 17: the bitrate cap on two VBR clips. SSIM against an uncapped export was 0.961-0.998 at Standard. See Roadmap 7.7 notes.
- iPhone 17: Quick at Small, Standard and High on three real underwater clips (4K 60 fps × 2, 1080p 60 fps). Small came out at 3.05-3.08 Mbps. See Roadmap 7.6 notes.
- One run of `testSmallMakesASmallerFileThanHigh` hung for 3 minutes and was ended (SIGTERM) while a device build ran. Three reruns passed in about 17 s. The cause was not found.

Open:
- Long exports take 1.1-4.5x the estimate as the phone heats up (Roadmap 7.8).
- The saved speed after a real export from the editor was not checked on a device. The test called the exporter directly.
- Pro on a device: the quality control, Quick and HDR on an HDR video. Purchases are checked by hand only.
- Before this fix, a Pro user could pick HDR for an SDR video. The export then throws `unsupported` (`VideoExporter.swift`, the HDR guard). This is read from the code; it was not run.
- The batch screens now export at High. File size and time were not measured.
- The user's report (9 Nov 2026) was a screen recording. It shows a 1520 × 2704 SDR HEVC original, with the estimate still running. The original file was not received.

## iPhone batch: the summary says what failed and why it stopped (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026):
- New line "Couldn’t save: n" for photos that failed to render or save. Before, only the tile badges showed them.
- A Cancel adds "Cancelled". The end of the background time adds "Saving stopped because UnderBlue went into the background. Keep the app open and try again." Before, both showed only "Saved to Photos: n of m".
- A stop reason shows only when photos were left, so a Cancel after the last photo does not mark a full run.
- New strings in six languages: "Couldn’t save: %lld" and the background line. "Cancelled" already existed. No reviewer has checked the new text yet.

Why: finding 6.9 of the flow review (`Roadmap.md`).

Checked: `BatchTests.testSummaryNamesSaveFailuresAndWhyItStopped` and the other 3 `BatchTests` pass on the iPhone 18 Pro simulator (iOS 27.2). The Mac app builds. Not run: Save All itself (it needs Pro), and a real Cancel on a device. A device run would save real photos to the library.

## Share extension: Cancel during the last copy (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026): the share checks for Cancel once more after the last copy, before it marks the folder complete. A cancelled share is deleted. Before, a Cancel during the last copy still finished the share, and it opened on the next launch if the extension was still alive. The iPhone and Mac extensions share this code.

Why: finding 6.15 of the flow review (`Roadmap.md`).

Checked on the Mac: new `ShareFlowTests.testCancelDuringTheLastCopyLeavesNoShare` (a provider that takes 0.5 s, Cancel after 0.1 s). Before the fix it failed: the state was "done(saved: 1, total: 1)" and a complete share waited in the inbox. After the fix: 30 Mac unit tests pass, 2 skipped. The iOS app builds. Not run: the real share sheet (it needs a signed build), and how fast iOS ends the extension after Cancel.

## Save alerts offer Open Settings; a failed save keeps the file (4 Nov 2026, merged to `main`)

What changed:
- Jake, 4 Nov 2026 (flow review 6.14): when a save fails for Photos permission, "Couldn’t save" also has "Open Settings". It opens the iOS Settings page of UnderBlue. Single export and batch. New string in six languages; no reviewer has checked it yet.
- New finding 6.16, fixed: the editor had a second alert on the same error. During "Ready to save" it closed that sheet, and closing the sheet deleted the finished file. The editor alert now waits while the sheet is up.

Checked on Jake's iPhone 17 (Debug build, sandbox Pro):
- `BatchFlowTests.testSaveAllWithPhotosAccessDeniedStopsBeforeRendering` passes with the new Open Settings check.
- New `BatchFlowTests.testSingleSaveWithPhotosAccessDeniedOffersSettings`: export one photo, deny access at Save to Photos. Before the 6.16 fix, the screen recording shows "Couldn’t save" with Open Settings, then about 1 s later the alert and the sheet are gone (the test failed). After the fix it passes: the alert has Open Settings, and Save to Photos is still there after OK. Discard then asks and closes.
- Both tests reset Photos access at the end, so the next save asks. Nothing was saved to the library.

## Pro screen: no stale text after a purchase (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026):
- The orange wait line ("Your next free photo is ready in …") hides once Pro is unlocked. Before, it stayed next to "Pro is unlocked".
- An Ask to Buy approval that arrives while the Pro screen is open replaces "pending approval" with "UnderBlue Pro is unlocked." (existing string).

Why: finding 6.13 of the flow review (`Roadmap.md`).

Checked: the iOS and Mac apps build. Not run: it needs a purchase (no StoreKit tests), and the sandbox account on Jake's iPhone already owns Pro.

## Custom Reset asks first (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026): Reset in the Custom sliders opens "Reset all Custom sliders to 0?" with a Reset button. The sliders save at once, so before, a stray tap set the saved look to 0 for every later photo and batch. The control is shared, so this covers the iPhone editor, the iPhone batch screen and the Mac inspector. New string in six languages; no reviewer has checked it yet.

Why: finding 6.12 of the flow review (`Roadmap.md`).

Checked on the iPhone 18 Pro simulator (iOS 27.2): both `CustomPresetUITests` pass. The photo test now taps Reset, closes the dialog without confirming and sees the value kept, then confirms and sees 0. On iOS 27 the dialog is a popover over Reset with no Cancel; a tap outside closes it. Not run against the old control (its dialog title does not exist there). The Mac app builds; the Mac dialog was not run.

Test fixes in the same change:
- `adjust` does not scroll the capped controls area, so the tests drag the label row above a visible slider until the slider is on screen. This also fixed the older `testVideoCustomSliders` failure.
- The picker wait is 30 s in `CustomPresetUITests` too.

## iPhone editor: a failed open says why and offers Try again (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026): when a photo or video cannot be opened, the preview area shows a warning, the reason and "Try again". Try again runs the whole open again. The look controls stay disabled. Before, an alert came once, then a black preview stayed with working controls and no retry. A photo whose first preview failed now counts as a failed open too.

Why: finding 6.11 of the flow review (`Roadmap.md`).

Checked on the iPhone 18 Pro simulator (iOS 27.2):
- New `EditorLoadTests.testFailedOpenShowsTheReasonAndTryAgainOpens`: a missing file sets the reason and no alert; after the file exists, Try again opens it. `CustomPresetTests` and `PhotoFormatTests` pass, except the known JPEG colour resolution failure.
- By eye: a broken JPEG opened through `--ui-test-open` shows "This media couldn’t be opened. Try another photo or video." with Try again. Compare and Export are dimmed.

## Free trial: one run takes the free exports left (4 Nov 2026, merged to `main`)

Rules (Jake, 4 Nov 2026, flow review 6.10):
- Without Pro, a queue or a batch takes the free exports left: the welcome photos (3 on a first install, else 1) and 1 video. At least 1 of each, so a person who waits can still look at a file.
- Mac: more files are not added, and the paywall says why. One Correct runs them all. Each saved file uses one free export; a failed one uses nothing.
- iPhone: "Select Photos" takes up to 3 photos on a first install and opens the batch screen. Save All runs as the free trial: SDR, with the mark, one free photo per saved photo. After that, Home offers one photo again.
- `TrialStore` now reserves several exports at once ("photo:3,video:1"). The old value "photo" still reads as one. A new launch still clears a reservation.

Checked:
- `TrialTests` (12, 2 new), `BatchTests` (4), `WatermarkTests` (5) pass on the iPhone 18 Pro simulator (iOS 27.2).
- New UI test `testFreeFirstInstallSavesThreePhotosInOneBatch` passes: a fresh trial picks 3 photos, Save All gives "Saved to Photos: 3", and Home then shows "Select Photo".
- `UnderBlueUITests` (5), `AppStoreScreenshotTests` (2) and `testPhotoCustomSlidersPersistAndReset` pass. The tests now find "Select Photo" or "Select Photos" and tap Add when the picker takes several photos.
- Mac: 29 unit tests pass, 2 skipped. New: `testFreeQueueKeepsTheAllowanceOfEachKind`, `testSavedKindsCountOnlyThisRun`.
- New strings in six languages (three keys). No reviewer has checked them yet.

Open:
- `CustomPresetUITests.testVideoCustomSliders` failed at the Temperature value check, also on `main` from the morning of 4 Nov (8bdbf4f). Cause: Temperature sat below the capped controls area, and XCUITest `adjust` does not scroll. Fixed in the test later the same day (see "Custom Reset asks first"); it passes now.
- Not run in the signed Mac app. Not run on a device.
- The App Review notes (iPhone and Mac) and `MacApp.md` now describe these rules. Jake has not reviewed the new sentences.

## Mac: a share during a batch is added when it ends (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026):
- When a run ends, the app adds a share that waited in the inbox. "Added n from the share menu." goes below the Done line, so both stay visible. Before, the share waited until the app became active again.
- When the share extension opens the app during a batch, the notice says "Shared files will be added when the batch ends." New string in six languages; no reviewer has checked it yet. A share found only by becoming active gives no notice, because the app cannot tell a share is waiting.

Why: finding 6.8 of the flow review (`Roadmap.md`).

Checked on the Mac: 27 unit tests pass, 2 skipped probes. New: `ShareFlowTests.testShareAfterABatchKeepsTheDoneLine`. Not run: the real share menu needs a signed build.

## Mac: save place locked during a run (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026): in Settings, "Save results to" (Place and Choose…) is disabled while a batch runs, like the toolbar folder button. Before, a change there made Show in Finder open the new place, while the run still saved to the old one.

Why: finding 6.7 of the flow review (`Roadmap.md`). Format, Keep HDR and Speed stay enabled: a run reads them when it starts.

Checked: the Mac app builds. Not run: there is no Mac UI test target. On the Mac: start a batch, open Settings (⌘,). Place and Choose… should be dimmed until the batch ends.

## Export options after buying Pro (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026): the free limits remember the resolution and range they replace. When Pro starts in the same editor, both come back. Before, a purchase after a free Export left the options at 1080p SDR, also for a 4K or HDR source.

Why: finding 6.6 of the flow review (`Roadmap.md`).

Checked: `WatermarkTests.testOnlyFreeExportsGetTheMark` now also checks Pro after free, and a second free call (the export applies the limits again to its copy). The 5 `WatermarkTests` pass on the iPhone 18 Pro simulator (iOS 27.2). With the old `ExportOptions.swift`, the two new checks fail ("hd" not "source", "sdr" not "hdr"). The Mac app builds.

Open: not run as a real purchase. On a device: as a free user, tap Export on an HDR photo, close, buy Pro (sandbox), tap Export. HDR and Original resolution should be selected.

## iPhone batch: Photos access before any render (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026):
- Save All asks for add-only Photos access before it renders anything. Denied access shows one alert, and nothing runs.
- A permission error during the run stops the rest. Before, every photo rendered, every save failed, and a "Saved to Photos: 0 of n" summary followed.

Why: finding 6.5 of the flow review (`Roadmap.md`).

Checked on Jake's iPhone 17 (Debug build, sandbox Pro, `BatchFlowTests.testSaveAllWithPhotosAccessDeniedStopsBeforeRendering`):
- The test resets Photos access, picks 3 photos, taps Save All and denies the system prompt. The prompt came before any render. "Couldn’t save" followed, and no summary appeared in 20 s. Passed twice (47 s, 44 s).
- With the old `BatchModel.swift` the same test fails ("The batch ran after access was denied").
- The test resets Photos access again at the end, so the next save asks. It uses its own trial Keychain, so the real trial state is not touched.
- iOS unit tests `BatchTests`, `PhotoFormatTests`, `CustomPresetTests`: 30 run, 1 known failure (JPEG colour resolution). The Mac app builds.

## iPhone: look controls wait for the analysis (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026: block preset changes during the analysis):
- The presets, Intensity, the Custom sliders, Compare and the subject bar are disabled while the editor loads or analyses. Export and 3s Preview already were.
- Photo: this covers the analysis and the first preview. Before, a preset tapped during the first render stayed selected, but the image kept the old look.
- Video: this covers the scene analysis. The preview shows the original until then, so a change showed nothing.

Why: finding 6.4 of the flow review (`Roadmap.md`).

Checked on the iPhone 18 Pro simulator (iOS 27.2), all in `UnderBlueUITests` and `AppStoreScreenshotTests`: 6 UI tests pass.
- New check in `testPhotoImportPresetsCompareExportSaveAndTrialGate`: a preset is never enabled while Export is not. It fails with the old controls ("A preset was enabled during the analysis").
- The tests now wait until Export is enabled before they tap a preset or Compare.
- The App Store screenshots still show Deep Dive at 100% (photo and video, checked by eye).
- `AppStoreScreenshotTests` had an old failure: it looked for the preview as an Image, but it is an Other element. Fixed.

## iPhone: Cancel while importing (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026):
- The "Importing…" box has a Cancel button. Before, it had none, and the whole home screen stayed locked until the import ended.
- Cancel frees the screen at once. Each import has a number, and Cancel moves it on. A late result of the cancelled import is deleted and never opens the editor.
- A finished old import no longer resets the screen state or the picker selection of a newer import.

Why: finding 6.3 of the flow review (`Roadmap.md`). An iCloud-only file with no network had no way out.

Checked: the two photo UI tests pass on the iPhone 18 Pro simulator (iOS 27.2), so a normal import still works.

Open:
- Cancel itself was not run. A simulator import ends in under a second, so there is no time to tap it.
- On a device: pick an iCloud-only video in airplane mode, then tap Cancel. The home screen should work at once.
- A Files import in iCloud Drive cannot stop part way. Its copy goes on in the background and is then deleted.

## Mac: a free run counts only its own items (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026):
- The trial is used only when an item of this run is saved. Before, any finished item in the queue counted. So a free run that failed still used the trial when an older item was done.
- "Done: n saved, n failed" counts only this run.
- The run is the items that passed the free-trial check. A file added during the awaits before the start waits for the next run. Before, the engine ran every queued item, so a free run could take more than one file.

Why: finding 6.2 of the flow review (`Roadmap.md`).

Checked on the Mac: 26 unit tests pass, 2 skipped probes. New: `MacModelTests.testRunResultCountsOnlyThisRun` and `BatchEngineTests.testStartOnlyRunsTheGivenItems`. The iOS app builds (`BatchEngine` is shared).

Open: not run in the signed app. The Mac 1.0 build in review does not have it.

## "Ready to save" keeps the file (4 Nov 2026, merged to `main`)

What changed (Jake, 4 Nov 2026):
- A swipe no longer closes the "Ready to save" sheet. Before, a swipe deleted the finished file at once.
- Discard moved to the top-left corner, away from Save to Photos. It asks first.
- A free export uses the trial only when the file is saved to Photos. Discard and closing the editor give the trial back. Before, the trial was used when the render ended.

Why: finding 6.1 of the flow review (`Roadmap.md`). A swipe lost a long export, and a free user then waited 24 hours.

Checked on the iPhone 18 Pro simulator (iOS 27.2):
- `testReadySheetIgnoresSwipeAndDiscardKeepsTrial` passes. It drags the sheet down, discards, and sees "3 of 3" free photos again.
- The same test fails on the old sheet ("A swipe closed the sheet"). A plain `swipeDown` did not close even the old sheet, so the test drags the title bar instead.
- `testPhotoImportPresetsCompareExportSaveAndTrialGate` passes. A save still uses one free photo ("2 of 3").
- Unit tests `TrialTests`, `CustomPresetTests`, `PhotoFormatTests` (iOS 27.0 simulator): 37 run, 1 known failure (JPEG colour resolution).
- The Mac app builds. The Mac app does not use this sheet.

UI test fixes in the same change:
- The picker wait is 30 s, not 8 s. A freshly booted simulator showed "Loading…" for longer.
- The tests wait until the editor's Export is enabled. A tap during the analysis did nothing.
- The tests tap `export-confirm` in the options sheet. `matching(identifier: "Export")` hit the editor's Export behind the sheet.

Open:
- Not checked on a device.
- New strings in six languages: "Discard", "Discard this export?", "Your trial won’t be used." No reviewer has checked the ko, ja, zh and es text yet.

## Free trial with watermark (2 Nov 2026, iPhone 1.1.10 (16), on the App Store since 3 Nov 2026)

Rules (Jake, 2 Nov 2026): 3 free photos, then 1 photo every 24 hours. 1 free video (first 10 s, 1080p SDR) every 24 hours. Every free export has the icon and "UnderBlue" in the bottom-right corner. The wait counts from the last free export in absolute time, so a clock set back gives nothing.

Automated: `TrialTests` (10) and `WatermarkTests` (5) pass on the iPhone 18 Pro simulator. `BatchEngineTests` (6) pass on the Mac. The UI test was updated but not run.

Full run on 3 Nov 2026 (iPhone 18 Pro simulator, iOS 27.0): 311 iOS unit tests, 1 known failure (JPEG colour resolution, see 31 Oct below), 13 skipped probes. Mac: 24 unit tests, no failure, 2 skipped probes. `PurchaseTests` not run (decision).

Pro has no mark (Mac batch, 1200 × 800 flat photo, sum of RGB under the mark's white parts / dark icon / clear parts): Pro 1.249 / 1.257 / 1.255, free 2.825 / 0.423 / 1.255.

Open checks on the iPhone (on hold, Jake 4 Nov 2026):
- Install 1.1.9 with its free photo used, then update: 2 free photos are left, and a free video is ready.
- Export 3 free photos: each has the mark. The 4th opens the Pro screen with the wait time.
- Free video: the mark is on every frame, also at 10 s. Pro exports have no mark.
- Set the clock back 2 days after a free export: still no free export.
- Delete and reinstall the app: the trial state stays (Keychain). Not checked on a device yet.
- Mac: one free item has the mark; the paywall shows the wait time.

## Video: no light detail (1 Nov 2026, merged to `main`)

What changed: video skips the light detail and its grain map. Photos keep both, with the edge guard.

Why: a 4K export showed a thin white oval around dark fish in bright water (Jake: `tune/video/Tune_1_Nov` clip, 18.45 s, the three fish at the top). The light detail lifted the water about 25 px out from each fish. Video had no edge guard. The ring also grew with the render size, so a small preview hid it.

Checked on the Mac (videosim, the 4K frame at 18.45 s). Gamma luma x255, 24-32 px from the fish, against the far water:

| Render | Value |
|---|---|
| Source | -1.7 |
| Before | +6.3 |
| After | +0.4 |

- Photos: 21 PNG renders of DSC03545, IMG_7400 and r15 are byte-identical to `main`.
- Unit tests on the iPhone Air simulator (iOS 26.5): 300 run, 1 failure. `SubjectCandidatesTests.testPickerSwitchIsOffByDefaultAndSavedOnTheDevice` needs iOS 27. It passes on iOS 27.1.
- The Mac app builds.
- Checked on the iPhone 17 (Jake, 1 Nov 2026, Debug build of `98380cf`): the `Tune_1_Nov` export shows no ring around the dark fish.

Still open:
- Light rays in a video: no clip with rays was checked. Rays in video now get no extra contrast.

## Video export pauses in the background (31 Oct 2026, merged to `main` 8ea5ae8)

What changed: a video export waits while the app is not active. It goes on with the same writer when the app is back. When the background time ends (about 27 s), the export is cancelled as before. Export files start with `export-`, and a new launch removes them.

Checked on the iPhone 17 with a log build:
- 16 s in Settings: the export went on and passed the output check (720p, 1736 frames).
- 120 s in Settings: cancelled at 27 s, the file was removed, free memory came back (4K).
- App killed while paused: the next launch removed its file.

Still open:
- Lock the screen during an export, then unlock within 20 s.
- Take a phone call during an export. A call banner now pauses the export too.
- A 4K and an HDR export that pause and go on.

## App Store rating prompt (31 Oct 2026, merged to `main` 1ec9ef5)

What changed: from the 10th save to Photos, the app asks for a rating once per app version. It asks only when online, after the "Saved to Photos" notice or a fully saved batch summary closes.

Checked: unit tests and the iOS and Mac builds.

Still open (the UI test runner did not start on 31 Oct):
- Launch with `-reviewPrompt.saves 10`, save one photo, tap OK: the rating sheet appears.
- Save once more in the same version: no sheet.
- Airplane mode: no sheet.

## JPEG colour resolution test fails on the simulator (31 Oct 2026)

`PhotoFormatTests.testJPEGExportKeepsFullColorResolutionAndTheCaptureDate` fails on the iPhone 17e simulator (iOS 27.1 SDK). The JPEG has 2x2 luma sampling, so colour is at half resolution. It fails the same way on `a400a74`, before the 31 Oct changes. Not checked on a device.

## Video reef colour: the scene fit (29 Oct 2026, merged to `main`)

What changed: each video scene fits its object colour values to the photo rule on its keyframe. So an olive reef turns brown in video, as in photos. Details: [RestorationExperiments](RestorationExperiments.md), "Video reef colour: the scene fit".

Checked on the Mac: 40 stills, the five Tune_25_Oct clips, and a 6 s pan made from O4.

Still open:
- A real reef clip with an olive reef. None of the test clips has one, so the strong case is checked on stills and on the O4 pan only.
- Cost on the iPhone: one more 320 px render per scene and settings. Check the first preview frame and a slider drag on a clip with several scenes.
- A seagrass clip: the plants should move no more than on the photo path.

## 48 MP photos failed to export on the iPhone (found and fixed 26 Oct 2026)

Measured on the iPhone 17 (iOS 27), Release build, with an 8064 × 6048 JPEG. It is IMG_7400 scaled up, so a synthetic file.

The failure:
- `PhotoProcessor.export` failed in under a second: "memory requirement of 399985784 too big (tile 8x12)". `main` (f71ba86) failed the same way.
- The Core Image memory target does not fix it: 768 MB broke 20 MP too; 1024 MB made 20 MP slower (13.2 s against 8.1 s) and 48 MP still failed.
- `CI_PRINT_TREE` on the device: every photo render has `intermediatesLimit=256MB`.

Causes and fixes:
1. The A2 object colour step measured the finished full-size frame shrunk to depth-map size (518 × 392). That render needed the whole pipeline at full size. Fix: measure a copy of the source at twice the depth map's size, run through the same pipeline (`combined(measuring:)`).
   - The guards are unchanged to the last digit.
   - 20 MP export: 8.1 s → 4.4 s. With the Labs orb switch on: 12.3 s → 5.1 s.
2. Even then, the full chain of wide blurs needed about 400 MB of intermediates for one tile at 48 MP. Each half of finishing alone fits. Fix: above 30 MP, finishing renders its image once into a half-float buffer before the sharpening (`FilterEngine.materializedIfLarge`).
   - Against the uncut render (Mac, threshold lowered to 1 MP, p1-p4): about 8-9% of pixels move by 1 level, 3 or more on at most 0.04%, 5 or more on 0-324 of 2.76 M pixels, mostly near the edges.
   - A 32-bit buffer was closer (largest difference 1-4), but the app was killed for memory at 48 MP. Three cut points instead of one: same differences, more memory.
   - Photos up to 30 MP keep the uncut render.
3. After one 48 MP export the memory stayed up, and the next export was killed ("signal kill"). Fix: the synchronous part of the export runs in its own `autoreleasepool`.
- Result: 48 MP exports twice in a row, 7.5 s and 6.9 s; peak +2.7 GB; footprint after about 1.7 GB.

4. Real 48 MP photos (`DeveloperMedia/licese-free-images/48mp/`, iPhone 16 Pro and 15 Pro Max, Wikimedia Commons): the second photo in a row was killed. After an export the footprint stays at 1.6-2.0 GB for about a second, and the next 48 MP export (peak +2.7 GB) went over the limit. `clearCaches` alone freed 5-50 MB. Fix: before an export above 30 MP, wait (at most 3 s) until free memory covers 56 bytes per pixel, and clear the caches after it.
- Result, three real 48 MP photos back to back, twice each: JPEG 7.0-14.6 s, HEIC with HDR 11.2-20.0 s (the MPO photo with a gain map is the slowest). All passed. The later exports include up to 3 s of waiting.

Still open:
- A 48 MP ProRAW (DNG) photo: none found with an open licence.
- A batch of many 48 MP photos on the device (the probe ran three in a row).
- Jake (26 Oct 2026): the ProRAW and batch checks are accepted as open. No sample or device run is planned.
- Preview of a 48 MP photo: not checked (it renders a 1600 px copy, below the cut threshold).
- Probe: `UnderBlueTests/PhotoCostProbeTests.swift`; inputs in Documents/cost-in and cost-48 on the device.

## Labs: remove backscatter spots (26 Oct 2026, branch `restoration-experiments`)

What changed:
- A Labs switch in Help, "Remove backscatter spots", is off by default.
- When it is on, photos lose faint round orbs before colour (`PhotoOrbs`, docs/RestorationExperiments.md, D3).

Checked so far: Mac harness, unit tests and the Mac build. The app UI was not checked.

Measured on the iPhone 17, Release build (26 Oct 2026), IMG_7400 at 20 MP, export:
- Switch off: 7.7-8.1 s, peak +1.3-1.7 GB. Switch on: 12.2-12.5 s, peak +1.3 GB, both the first export (finds the orbs) and the second (reuses them).
- So the detection is cheap, but taking the orbs off adds about 4.5 s to every export. Not explained yet.
- The water core (photos, not Labs): one finishing call 1.25 s → 2.0 s at 20 MP; a photo makes two.
- 48 MP: failed with the switch off too; see "48 MP photos failed to export".
- After the 48 MP fix (the A2 measurement on a small copy): switch off 4.2-4.4 s, switch on 5.1-5.8 s at 20 MP.
- Mac app: turn the switch on in the Help window while a photo is in the preview. The preview should redraw without the orbs (`PreviewPane` watches the switch).
  - Jake (26 Oct 2026): check this before the Mac archive.
- iPhone app: preview and saved photo match, with the switch on and off.

## Apple Log and ProRes RAW (26 Oct 2026, branch `apple-log`)

What changed:
- Apple Log and Apple Log 2 clips are decoded with the white paper curve (`AppleLog.swift`, `AppleLogKernels.metal`). Export, preview and analysis all decode. HDR export of a log clip writes HLG.
- The iPhone app refuses ProRes RAW with its own message. The Mac app lets it through: the macOS decoder runs Apple's RAW processing with default settings (VTDecompressionProperties.h).

Checked so far, on the simulator and the Mac with generated clips only:
- The curve matches Apple's `AppleLogToLin` LUT at 10 points (`Apple-log/` at the repository root, not in git).
- Every frame path (AVAssetReader, AVVideoComposition, AVAssetImageGenerator) passes the log signal through unchanged, tagged as sRGB.
- SDR export of a grey card: black 0.00, 18% grey 0.31 (Log and Log 2). Before 30 Oct 2026 grey read 0.38 and 90% white 0.71; white is unmeasured since. HDR export is HLG and passes `OutputValidator`.

Still open:
- Real clips: Apple Log ProRes (iPhone 15 Pro or later), Apple Log 2 in ProRes and in HEVC (iPhone 17 Pro). Check the tags, the look and the HDR export.
- Look: 18% grey ends at 709 code 0.39. Apple's Rec. 709 LUT puts it at 0.53, so our mid-tones are darker before the colour correction. Judge on real footage.
- ProRes RAW on the Mac: no sample yet (iPhone 17 Pro with external storage). Check that frames arrive developed, their colour tags, and the export.
- Fixed 30 Oct 2026: the preview compositor encoded Rec. 709 with gamma 1.961 and the export render with 2.4. See "Preview, still frame and export match" below.

## Preview, still frame and export match (30 Oct 2026)

Jake's rule (30 Oct 2026): the still frame before playback, the preview and the export must look the same.

What was wrong:
- SDR export was brighter than its source and the preview. Core Image read the source with gamma 1.961, and the export wrote with `CGColorSpace.itur_709` (gamma 2.4). With the Original preset, grey 0.50 came out as 0.56; every value became source^0.817.
- The still frame before playback kept the frame drawn before the analysis. That frame used the filter with no analysis: a much more saturated look than playback and export.

What changed:
- SDR export renders into the colour space CoreVideo reads the Rec. 709 tags as (`VideoColorPipeline.colorSpace`). HDR export is unchanged.
- While a video is analysed, the preview shows the original. After the analysis the paused frame is drawn again (as the Mac app already did).
- Mac: the same, with "Analyzing…" over the player. The analysis now runs in its own task. Before, `refreshPreview` cancelled it when a slider moved during the analysis, and that video's preview stayed without it (found in the code, not reproduced).

Checked:
- New test `VideoPreviewExportMatchTests`: three patches, Original and Natural. Preview and export match within 0.03. Before the fix it failed on 17 of 18 values (export brighter by up to 0.075).
- `AppleLogTests`: log grey in the SDR export now reads 0.31, as in the preview (0.39 before).

Still open:
- Jake on the iPhone: a clip's still frame, playback and an exported file look the same.
- Mac app: the original and "Analyzing…" while a video is analysed; a slider moved meanwhile keeps the analysis. Built only, not run.

## m5 white band at the top (25 Oct 2026, iPhone, `main`)

Jake saw a white band along the top of m5 (`DeveloperMedia/eval/market/raw/m5.png`). He used the iPhone app built from `main`.

The Mac harness does not show it:
- Sources from `main` (085a6f3) and from `restoration-experiments` (09abd02).
- At 960 px and at full size (1600 × 1066).
- Photo path and video path. Mean brightness of rows 0 to 40 is flat (photo 54, video 76).

On the iPhone 17 it does not show either (25 Oct 2026). A device test opened `m5.png` from the app's Documents folder and ran `PhotoProcessor.preview` and `export` (Natural, default intensity, analysis from the photo):
- `main` (085a6f3) and `restoration-experiments` (6489d23): rows 0 to 64 read 50 to 52 in both the preview and the export, with no rise at the top.

So the band does not come from the photo path with default settings on this file.

Found and fixed (25 Oct 2026, `fix/preview-whole-pixels` 9917bd6, from `main`; also on `restoration-experiments`):
- The phone's photo is the 24 MP original (6192 × 4128), not the 1600 px `m5.png`. With it the device test shows the band: at 0.5% height (0, 64, 133), at 10% (0, 3, 104).
- Only the 1600 px preview has it. A 1548 px preview (exactly a quarter, 1032 rows), the full-size preview and the export do not.
- Cause: the preview scaled both sides by one ratio, so it was 1066.67 rows high. The edge stages read the partial top row.
- Fix: `FilterEngine.downscaled` scales to whole pixels on both sides. After the fix the top reads (0, 13, 108), the same as the full-size render.

Still open:
- Jake checks m5 in the editor on the phone with the fixed build.
- The fix branch is not merged into `main` and not pushed.

## Light detail edge guard (24 Oct 2026, photos only)

Details: [SubjectEmphasis E27](SubjectEmphasis.md). A new kernel `UnderBlueLightEdge` and a blend take the light detail off water beside a strong edge. It removes the dark band around fish (DSC03545). Video passes `edgeGuard: false` and is byte-identical on the Mac.

Checked on the iPhone 17 (Jake, 24 Oct 2026): DSC03545 and IMG_7400 look fine.

Video: since 1 Nov 2026 video has no light detail at all (see "Video: no light detail" above). So the open video check of this entry is replaced by that one.

## Camera JPEG reef colour (23 Oct 2026, iPhone 1.1.4 build 10)

Commits `f96dc65`, `cca30aa`, `9e5a23b`. Details: [JpegInput](JpegInput.md).

Checked on the iPhone 17: the reef red share from the camera JPEG of DSC03656, DSC03687 and DSC03696
went from 0.405, 0.511 and 0.353 to 0.336, 0.241 and 0.300. The ARW results stayed within 0.005. The
video, photo, preset and restoration test classes pass on the phone (141 tests).

Checked on the Mac: m5 photo-path dE 12.98 to 13.22, no panel patch worse by more than 1 dE. The
AquaColorFix gate and three video clips in `videosim` are in JpegInput.

Still open:
- **The Mac app.** Not checked. Today's build is iPhone only. Mac and iPhone read different analysis
  samples from one file (JpegInput, J5), so the Mac app needs its own look.
- **Manta belly.** Chroma 0.023 before today, 0.043 now. Planned with the subject work.
- **m1 cooler.** The yellow coral is duller than before (mean OKLab distance x100 1.37).
- **Simulator JPEG chroma.** `PhotoFormatTests` reads 2x2 chroma on the iPhone 18 Pro simulator and
  passes on the iPhone 17.
  Update 11 Nov 2026: see "JPEG colour resolution: simulator only" below.

## Video preview stutter and the 3s Preview button (22 Oct 2026)

A user reported that the 3-second video preview stutters badly. The preview renders every frame live with Core Image. Cost follows the pixel count.

Measured on an iPhone 17 (Release build, thermal state 0 to 1, 3 s of playback, frames read at 60 Hz with `AVPlayerItemVideoOutput`, no visible layer). Frames delivered in 3 s, with the scene analysis done:
- 4K 60 fps, two real clips (`13832750_2160_3840_60fps`, `16893606_2160_3840_60fps`): 6 to 7 frames before the fix (about 2 fps).
- 1080p 60 fps, two clips: 69 to 98 frames before the fix (about 25 to 33 fps), uneven gaps of 33 and 50 ms.
- 720p 30 fps: 90 frames, smooth before and after.
- Locking the frame duration to 30 fps did not help. It was worse.

Fix:
- The editor preview now renders at a scale that keeps the output near 30 million pixels per second (`VideoPreview.phonePixelRateBudget`). 1080p 60 fps renders at 0.49. 4K 60 fps renders at 0.25. Export and the Mac preview are not changed.
- After the fix: the two real 4K clips gave 180 frames (60 fps) in runs 2 and 3. Run 1 gave 167 and 164 frames, with max gaps of 133 ms and 183 ms. 1080p 60 fps and a 1080p 30 fps clip held their source rate. The unit tests are in `VideoPreviewScaleTests`.
- Playback is blocked while the scene is analysed (about 15 s for 4K, 3 to 8 s for 1080p). The filter-only preview before the analysis stutters on 4K (about 10 fps, measured without the budget). The video player ignores taps and the 3s Preview button is disabled until the analysis ends.
- The button was renamed from "Play 3s" to "3s Preview" in all five languages.

Still open:
- **Look at a 4K clip on the phone.** At 0.25 scale the preview may look soft. Export quality is the same as before.
- Not measured: the filter-only path with the budget (it is now blocked), a hot phone (thermal state 2 or higher), older iPhones, the first-play gap of 133 to 183 ms (cause not checked), and the Mac preview.
- Not checked by hand: the blocked player and the disabled button on the device.
- The budget comes from one phone. Measure again when another device is available.

## Video layer edge, halo and export memory (22 Oct 2026)

Commits `7040d4f`, `23d27bc`, `2c55acc` and the export memory fix. Algorithm details: [ColorAlgorithm](ColorAlgorithm.md#video-only-steps-22-oct-2026).

Checked by eye on an iPhone 17 export (tune/video/Tune_22_Oct: thresher shark and hammerheads; whale shark first 12 s) and on the Mac render tool (`videosim`, plus the 22 tests of `UnderBlueMacTests`):
- Layer edge: gone. Change over 20 rows 50.6 to 15.9 (source 17.6). Whale shark top: 46.4 to 36.8 (source 30.4; that clip has a real light edge).
- Halo: gone beside dark fish. A numeric halo metric did not work, so this is by eye.
- Photos: colour eval report identical to before. 149 simulator tests passed.
- Export time on the iPhone 17: about 5 to 15% slower (clip B 5.0-6.5 s to 6.0-6.7 s; clip A 12.7-13.8 s to 14.4-15.8 s; 2 runs each). Mac times were too noisy (fanless Air).

**Export memory leak (fixed, 22 Oct 2026).** Before: with the restoration on, the footprint grew about 3.7 MB per frame (preset Original stayed at 127 MB). The 31 s whale shark clip (931 frames) passed 3 GB and the system ended the app on an iPhone 17. Commit `151e4f3` did the same, so it is older than the video steps. No crash log exists; the cause was found by logging the footprint in the progress callback. Fix: one `autoreleasepool` around the per-frame render in `VideoExporter` (the loop is in an async function). After: about 230 MB flat, 931 frames in 25.6 s, duration check passed. The first 12 s: 1581 MB before, 279 MB after.

The `LongVideoTests` memory failure in Known issues may have the same cause. It was not rechecked.

Still open:
- **Dark blob on photos in bright open blue water (checked 22 Oct 2026).** Photo r13: with the middle-channel highlight rule, the per-pixel depth map darkens a wide patch around the subject (centre over side brightness 0.908; one constant depth 0.999; source 0.954). The local veil is not the cause: changing its bounds did nothing. So photos keep the old rule, and the video path is safe because it uses one depth per scene (r13 as a 4 s clip: 0.998). Not done: making the middle rule safe for photos (it would need a limit on how much the depth map may change the gain in bright blue water). The photo layer edge the middle rule removes on video was not looked for in photos.
- **Pale ring around fish on photos (seen by Jake, 23 Oct 2026).** DSC03545 in
  `DeveloperMedia/subjectpicker/`, Mac render at 4000 px, Natural Dive at 0.8. The water right
  around the two fish loses chroma. Measured in a ring 8 to 40 px out against a ring 100 to 160 px
  out: the near ring holds 94 per cent of the far ring's chroma in the source and 86 per cent in the
  result from the camera JPEG, and 95 against 84 per cent for the ARW. So it is in both results and
  in neither source, and the ARW is the stronger one. It is not a camera JPEG problem. The cause was
  not looked for. It may be the same local veil as the video halo above, but on the photo path.
  **Cause found 23 Oct 2026, not fixed.** The source has a pale glow around each fish. The subject
  light removal (`subjectTone`) greys it, per pixel. It is not the local veil, the mask or the
  detail layer. See `SubjectEmphasis.md`, E18.
- Not checked: 4K and HDR clips, the whole whale shark clip by eye (only the first 12 s), the Mac app's own export output (the test sandbox hides it), the iPhone export of the red-ring fix on the whale shark clip beyond the first 12 s.

## Dark corner in video: shadow floor (22 Oct 2026)

Jake saw a black bottom-left corner (9 to 12 s) and a dark veil around a black manta (13 to 14 s) in `2025-05-03 22.12.02.MOV`.

- **Not caused by the 22 Oct video and speed changes.** `151e4f3` and HEAD gave the same corner on the Mac, the iOS simulator and an iPhone 17 export (iPhone, bottom-left 10% x 12%, luminance at 10 s: source 0.085, both builds 0.060). The old build needed the export leak fix (`9cee0d5`) to run on the iPhone.
- **Cause.** The contrast step (`UnderBlueBlackOffset`) darkens dark water. The corner is already dark without the restoration (Mac, source 0.097, colour correction only 0.041, contrast set to 1: 0.131). The shadow toe has slope 0 at black.
- **Change.** Video only: no pixel below the knee falls under 65% of its own value (`FinishingMath.videoShadowFloor`). Photos are unchanged.
- **Result (Mac videosim, same corner, 10 s):** 0.033 to 0.051. Unchanged above the knee. Tests: RestorationTests 78 and VideoRestorationTests 25 pass on the simulator.
- **iPhone 17 export with the floor (0 to 15.5 s): no change.** Bottom-left luminance at 9 to 15 s is the same to three digits as before the floor (10 s: 0.060 both, source 0.085). On the iPhone the corner is not below the knee, so the floor never acts. The darkening there (about 30%) has another cause that is not found. The Mac and the iPhone get different scene values (the iPhone runs the real depth model); the iPhone values were not printed.
- Not checked: other clips, and the dark veil around the manta by eye in motion.

## Open work (do first)

- **Done (29 Sep 2026): distinguish the three built-in presets.** Jake checked the tuned presets
  (`8b9f278`) on the iPhone and accepted them. This closes the issue first reported on 25 Sep 2026.
  - 29 Sep 2026, tuned: Tropical moves 5.4 from Natural (was 4.0), Deep Dive 5.2 (was 3.2), median CIE76 on 26 images. Natural Dive is unchanged (pin test). Values and rejected tries: [ColorAlgorithm](ColorAlgorithm.md).
  - 29 Sep 2026, before tuning: Jake sees a slight difference on the iPhone. The code reads every preset value in `ColorCorrection.make`. Tropical adds 600 K warmth, which is scaled down when the colour cast is weak, and more saturation, which is scaled down in neon water. Deep Dive adds +0.10 shadow lift, 0.85× water chroma and more clarity. The vibrance difference is almost zero on the test scenes: Natural's final vibrance is 0.005. The Tropical and Deep Dive tests in `PresetTests` pass.
- **Natural pin regenerated (29 Sep 2026).** `edcc663` added `referenceGains` and `referenceStrength` (bright-scene white reference) without updating the pin. No existing value moved; the step is active on 3 of the 18 fixtures. Jake chose to keep `edcc663`, so the pin now includes it.

- **Natural pin regenerated (3 Oct 2026).** The pale surface light rule (`keepWarmRatio`) also runs in `restoredMean`. Only the `grey` fixture's restored values moved: `waterLit` red 0.130 to 0.081 (now equal to green), `subjectRed` 1.31 to 1.0, `midLift` 0 to 0.059. Jake chose to regenerate the pin. Still open: an iPhone look at the shark photo in `DeveloperMedia/tune/photo/shallowwater/`.

## Offer code redemption (29 Sep 2026)

Get Pro → Redeem Code opens Apple's sheet. Checked on the simulator: the button shows in Korean for a non-Pro user. The sheet itself was not opened.

Closed (Jake, 30 Oct 2026): entering a code at purchase unlocks Pro.
- A code redeemed outside the app is not checked by hand. The app reads it as any purchase: `Transaction.updates` while it runs, `Transaction.currentEntitlements` at launch (PurchaseStore).
- An invalid or used code is handled by Apple's sheet.

## Changes waiting for the final round

| Commit | Change |
|---|---|
| `a439df0` | Highlight shoulder: highlights roll off instead of clipping |
| `13ffbee` | Custom user preset: five saved sliders for photo, batch and video |
| `e02c19e` | Tropical and Deep Dive tuned to match their names |
| `7651372` | Custom Saturation and Temperature made visible (wider ranges) |
| `8b9f278` | Tropical and Deep Dive made clearly distinct from Natural Dive; accepted on iPhone in `7b1a015` |

## Video haze and scene fade (20 Oct 2026, `11d3c7d`)

Two changes in the video path. Photos are unchanged.
- The black offset of a video scene stays at or below zero. Before, one scene turned hazy: saturation 0.43, against 0.62 in the source. After, about 0.6.
- The scene fade is 3 s and may be longer than the keyframe gap. The brightness jump at scene changes fell (rms 1.38 to 1.03, 1.56 to 1.17, 2.14 to 1.91 L* on three clips). Jake saw no large difference by eye.

Test clips are in `DeveloperMedia/tune/video/Tune_20_Oct`. All numbers come from the Mac simulation (`videosim`), not from an app export.

Still open:
- **Pale rim around dark subjects in video. Changed 22 Oct 2026:** the video path now lifts dark pixels before the local veil's broad blur, and the iPhone export of two clips showed no bright fog beside dark fish. See [Video layer edge, halo and export memory](#video-layer-edge-halo-and-export-memory-22-oct-2026). Original note: On `2025-05-03 22.12.02.MOV` at 14.4 s, the water beside a manta is about 2 L* brighter than the water further out. 51% of the edge rows show it. The band is 3 to 4% of the frame height at any size. The local veil causes it: with `veilLevel` set to 0 the rim is gone, but the whole clip gets 2 to 6 L* brighter and one clip loses 0.12 saturation. So do not switch it off. Video plans have no subject mask (photos only, since 1 Oct 2026). Whether that is the cause is untested. Whether photos show the same rim is unmeasured.
- **Brightness jumps at scene changes are not gone.** With every correction frozen, 5.1 and 6.1 L* of jump remain on two clips. Limiting each scene's brightness to 0.01 around the clip's value cut the largest jump (9.4 to 5.7 L*), but it gave a pale rim around a manta (`2025-05-03` at 5 s). It was removed.
- **Measuring more often did not help.** Keyframes every 0.5 s or 0.25 s made the jumps larger while the fade was tied to the keyframe gap. A scene split threshold of 0.08 gave lower numbers only because scenes merged. So no "deep scan" mode was added.
- **Not checked:** the export from the app, the analysis time on the iPhone, and an eye check of the 3 s fade at real cuts.

## Photo outlines from the fine detail layer (20 Oct 2026)

On the Mac, Natural Dive drew a bright line along the white scales of a turtle (`IMG_7255`) and a dark line around a clownfish and its anemone (`IMG_7256`). The fine detail layer caused it, not the subject mask or the local veil. It was already there on 8 Oct 2026 (`3104913`).

The detail band now ends sooner: `detailEdgeLow` 0.05 and `detailEdgeHigh` 0.12 (before 0.15 and 0.30). Medium edges get less sharpening. Measured on the Mac harness at 1200 px: turtle high-pass L* +35.7 / -28.4 to +25.3 / -22.1 (source +22.0 / -17.7); m5 full dE 13.26 to 12.98; AquaColorFix gate 13.02 to 13.03. Market pairs, real photos and the neutral ramp keep their hue and chroma. Local contrast fell a little (m5 9.09 to 8.76; its target is 9.79).

Still open:
- Look at the turtle, clownfish and a few other photos by eye on the iPhone and the Mac. The lines are softer, not gone.
- The Mac App Store screenshots must be made with this change.
- The teal diver (`IMG_20230118_093746_0014`) still turns grey-blue (mean a* -30.2 to -5.9). The colour correction does it, not the detail layer. Jake looked at the Mac export on 20 Oct 2026 and accepted it. No change is needed.

## Long-video notice (28 Sep 2026)

A video of 45 s or more shows "Analysis and correction can take longer for longer videos." above "Analyzing…" (`EditorModel.longVideoSeconds`).

Checked on the iPhone 17 simulator (iOS 27.0), in Korean, with a 50 s clip: the notice showed above "분석 중…".

Still open:
- A video shorter than 45 s shows no notice.
- The export progress box shows the same notice for a video of 45 s or more (added after the first check; build only).
- The same check on the iPhone, and in landscape.

## Share sheet opens UnderBlue (28 Sep 2026)

29 Sep 2026: Jake checked the share sheet on the iPhone.

The extension opens `underblue://share` after the copy, through the `UIApplication` object on its responder chain.

Checked on the iPhone 17 (iOS 27.0) with a temporary UI test: Photos → Share → UnderBlue.

| Shared item | UnderBlue came to the front | Editor |
|---|---|---|
| 1 video (14 s) | Yes | Opened, showed "Analyzing…" |
| 1 photo | Yes | Opened with the preview and Natural Dive selected |

Still open:
- Several photos: UnderBlue opens on the batch screen.
- A partial share: the sheet stays with the note and the Open UnderBlue button, and the button opens UnderBlue.
- Share while the editor is open: UnderBlue comes to the front on that editor, and the share opens after going back.
- App Review: Apple's extension guide lets only a Today widget open its app. If review objects, remove the open call. The share then waits for the next launch, as before.

Device check note: `xcodebuild test` on the iPhone left the old share extension installed. Install with `xcrun devicectl device install app` before a share-sheet check.

## Video export keeps the source timescale (28 Sep 2026)

The iPhone rejected the export of `problem_video/cannot export/2019-05-05 18.37.02.MOV`: "frames read back 1755 vs written 1756". The writer rounded times to 1/600 s. The last frame starts 0.63 ms before the end, so it moved onto the end of the edit. The file held that frame but never showed it. Video export now writes in the source track's timescale.

Checked:
- Simulator: `VideoTests.testLastFrameJustBeforeTheEndIsShown` failed with invalidOutput before the change and passes after it.
- Mac copy of the export path, on the real clip: 1756 frames written, 1756 decoded after the change (1755 before).

Still open:
- Export the same clip on the iPhone.

## Import, share sheet and file names (28 Sep 2026, `4aaa7cc`)

Built for the simulator. These unit tests pass: ExportNamingTests, FileImportTests, PhotoTests, LocalizationTests and BatchTests. FileImportTests uses a RAW sample from DeveloperMedia.

On the simulator, a share placed in the App Group inbox opened in the editor at launch. The extension UI itself was not run. Nothing below was checked on an iPhone yet.

- **Signing: done on 28 Sep 2026.** Automatic signing registered `com.underblue.app.share` and the App Group `group.com.underblue.app`. The device build embeds a development profile with the App Group in the app and in the extension. The App Store profile is created again at the next archive.
- **Share sheet in Photos.** UnderBlue appears in the app row for 1 photo, 10 photos and 1 video. It does not appear for 11 photos or 2 videos. After "Added to UnderBlue", UnderBlue opens by itself, and the share opens in the editor or the batch screen.
- **Share edge cases.**
  - A Live Photo opens as the still photo.
  - Share while the editor is open: nothing replaces it; the share opens after going back.
  - Free user shares 5 photos: only the first opens, with the Pro notice.
  - Share a RAW (DNG) from Photos and a file from the Files app.
- **Import from Files.** HEIC, JPEG, iPhone ProRAW DNG, one other camera RAW (ARW/CR3/NEF), MOV and MP4. Include one iCloud Drive file that is not downloaded yet.
- **File names in Photos.** Check the name in the photo's info panel after saving:
  - From Files and the share sheet: `<original>_UnderBlue_<look>.jpg` (or `.heic`).
  - From the Photos picker: it depends on the file name the picker delivers. If the picker gives a temporary name, the time-based fallback name appears. Record which one.
- **RAW on the device.** `CIRAWFilter` decodes the RAW file again for each preview render. Measure preview speed, export time and memory for a RAW of 20 MP or more.
  - Keep the RAW path on `CIRAWFilter`. On the simulator, `CIImage(contentsOf:)` returned only the 1616 px embedded preview.

## Photo output formats (28 Sep 2026)

JPEG now saves at quality 1. 10-bit HEIC is a new choice. PhotoFormatTests, PhotoTests, PhotoHDRTests, BatchTests, CustomPresetTests, ExportNamingTests and LocalizationTests pass on the simulator. PhotoFormatTests and PhotoHDRTests also pass on the iPhone 17, including the HDR HEIC gain map. Nothing below was checked by hand yet.

- **Export sheet.** The Format picker shows JPEG and HEIC. The note under it changes with the choice. The choice is kept for the next photo.
- **Batch screen.** The format menu next to Compare matches the export sheet. Save All writes the chosen type.
- **Photos.** A saved HEIC opens in Photos and the info panel shows `.heic`. An HDR photo saved as HEIC shows HDR in Photos.
- **Sharing a HEIC out.** Send one to a non-Apple app, such as a messenger. Record whether it arrives as HEIC or JPEG.
- **Size, time and memory on the iPhone.** Export a 20 MP ARW and a 48 MP iPhone photo in both formats. Record file size and export time, and watch for memory warnings. The Mac sizes are in [Architecture](Architecture.md).

## Colour tuning and m5 reference adaptation (29 Sep 2026)

The colour rules first changed to move toward the AquaColorFix look
([benchmark](AquaColorFixBenchmark.md)), then gained a bright-scene reference adaptation for m5.
Static results and known regressions are in [M5ColorEvaluation](M5ColorEvaluation.md) and
[AdditionalReferenceReview](AdditionalReferenceReview.md). Run the remaining checks before release:

- **Holdout.** Run after the final 29 Sep static candidate: 20.3411 combined and 20.3539 uniform,
  against 20.4373 and 20.4364 from the pre-change source snapshot. The mean improved, but
  `144_img_.png` regressed by 1.53 on uniform; this is not an unconditional pass.
  The UIEB set was removed on 2 Oct 2026, so this check is closed and cannot be re-run.
- **Presets on the new colour.** Done on 29 Sep: Jake checked and accepted the tuned Natural,
  Tropical and Deep Dive presets on the iPhone (`8b9f278`, recorded by `7b1a015`). The Natural Dive
  pin was regenerated for the reference-adaptation values. Repeat this check only if colour or
  preset values change again.
- **Market pairs by eye.** m1 and m4 lost about 1.5 ΔE against their targets and m2 lost 3.9 (its mid-tones are darker than the target). The AquaColorFix gate gained 8.2. Decide by eye which look the product wants on m2 (a dark, murky turtle scene).
- **Custom sliders.** The tone values under the sliders changed (shadow lift, highlight compression). Re-measure the caps in `CustomAdjustments.Caps`.
- **Real video.** The subject light removal and the trusted blue reference were not seen on video. Watch a bright fish or diver against blue water for a warm flicker.
- **Fine detail layer on the iPhone (28 Sep 2026, `07c004d`).** The harness judges a 960 px render; a full-size export has a 7.6 px blur radius. Check on a photo export at 100%: the mola or a fish body is crisper, its outline has no halo, open water shows no new grain. Check Custom Clarity at +100 on a dark, noisy photo (the noise floor does not scale with the slider). Check one real clip for shimmer in textured areas; the fix if it shows is a higher floor per clip. Export time on a 4032 px photo is unmeasured.
- **Depth model on Core AI — experiments complete, 6 Oct 2026.** V2 Small was tested on the iPhone 17, including GPU input packing, P6 compression and compute preferences. Keep Core ML: final whole-depth medians were 32.96 ms for Core ML and 40.81 ms for Core AI GPU-preferred. Neural Engine preference failed on an FP32 intermediate and fell back to GPU. [Experiment record and retained data](CoreAIExperiments.md). An ANE-compatible FP16 depth graph remains untested. Post-correction enhancement was evaluated later as a separate refiner pilot below.
- **AI refiner preset — deferred, 8 Oct 2026.** A small NAFNet-teacher-distilled refiner was converted to Core AI and reviewed against the current output on 13 photos. Eight were “no difference”; both validation photos were “no difference”; two of three refiner choices were explicitly described as barely different. Do not add the preset, model or add-on. [Pilot result](AIRefinerPilot.md).
- **Video: values that follow the light.** Today a clip gets one set of values from 10 samples. So a clip whose light changes is right in some parts and wrong in others (the product owner, 28 Sep 2026). The analysis is a 48x48 statistic and needs no model. It can run on every frame or every few frames and be smoothed over time before `make()`. Only the depth model is costly, and the record says per-pixel depth did not help video. Design this as its own step. It changes `VideoRestorationAnalysis`, not the colour rules.

## Local veil and shadow toe (30 Sep 2026)

Three changes, all on photo and video:

- **Local veil.** The restoration scales the veil by the broad light around each pixel. The broad light is a blur of 5% of the short side. The scale is its share of the scene's water level, within 0.33x to 3x. One veil per scene had left a grey-pink band in sunlit water and a hard shadow on a fish school.
- **Veil colour follows the light.** The local veil also takes the broad light's colour, at the same luminance. The scene veil was bluer than whitish surface light. Taking it away left red and blue, so surface light turned pink or violet.
- **Shadow toe.** Contrast and brightness now run in `UnderBlueBlackOffset`. Values below twice the black offset get a quadratic toe instead of a clip to black.

Measured on the Mac (harness, videosim). `292facd` has the local veil and the shadow toe; the last column adds the veil colour:

| Check | `9ee3bb6` | `292facd` | Veil colour |
|---|---|---|---|
| AquaColorFix gate, photo / video path | 12.27 / 12.82 | 11.23 / 11.01 | 12.87 / 12.96 |
| m5 full / panel dE | 17.25 / 20.68 | 14.70 / 19.65 | 13.34 / 19.98 |
| Challenge video band (OKLab C < 0.05) at 32 / 36 / 38 s | 15.1 / 28.8 / 31.4% | 1.9 / 4.2 / 18.9% | 0.4 / 3.1 / 22.7% |
| video2 pink or violet share at 0 / 5 / 20 / 32 s | 34.9 / 30.2 / 6.9 / 34.0% | 12.7 / 4.3 / 7.0 / 10.6% | 1.1 / 0.1 / 0.0 / 0.1% |
| video2 at 5 s, near-black share on the dark manta (source 11.2%) | 52.0% | 19.0% | 19.0% |

The gate got worse with the veil colour, mostly on pair 2 (12.56 to 17.06). The napoleon wrasse is cooler. m5 improved, and m5 wins when the two disagree (Jake, 30 Sep 2026).

Known gaps:

- The challenge video at 38 s keeps a beige ring around a dark blue centre, like a vignette. The frame is almost all veil. After veil removal about 30% of the light is left. That is right at the `keepHueWhereDark` threshold. A broad-light version of that rule was tried and did not remove the ring. The Help guide now says that very dark or very bright scenes may not look as expected.
- Gate pair 1 got darker (7.40 to 9.19).
- The steady part of the challenge video (8 s) looks flatter by eye, and its corners look pink-beige. Neither is measured.

Run before release:

- **iPhone photo export.** Check a full-size export of a reef and a bright blue-water photo. Look for halos where a subject meets open water. The broad blur is 5% of the short side.
- **iPhone video export.** Export `tune/video/challenge_video/original.MP4` and `tune/video/challenge_video/video2`. Check the band at 32–38 s, the pink surface light, and the manta at 5 s. Watch the fish school edge for a moving halo or flicker: the broad blur is computed per frame.
- **Export time.** The restoration now has one more blur per frame. Video export time is unmeasured.
- **Presets.** Check Tropical and Deep Dive by eye, because the restoration and the tone step changed.
- **Custom Brightness down.** Check that dark areas keep their grades at the slider's minimum.
- **Video analysis on the iPhone (1 Oct 2026).** The whale shark clip in `tune/video/challenge_video/video3` failed its whole scene analysis twice (diagnostic code 6). Then it got the neutral standard correction, which made it bluer. One unreadable keyframe stopped the analysis; an audio track longer than the video by more than 0.13 s causes that. Keyframes now stay inside the video track, and an unreadable keyframe is skipped. The file in `video3` is an UnderBlue export, not the original. Open the original from Photos again: no fallback notice, and Natural Dive removes the blue cast.
- **Video flicker at short scenes (1 Oct 2026).** `video2` pumped in brightness at 14 to 18 s. The camera turned toward the surface and back, and scenes of one or two keyframes switched the values against the light. A short scene between two held scenes (3 or more keyframes) is now skipped; its neighbours fade across the whole gap. On the Mac (videosim, 0.1 s steps): frames moving against the source 15 to 8, largest frame-to-frame change 0.0346 to 0.0157 (source 0.0147). The challenge clip is unchanged. Export `video2` on the iPhone and watch 13 to 19 s.
- **Bright exception off in the kernels (1 Oct 2026).** Sunlit water 1.3 to 1.8 times brighter than the water took the white reference as a pale subject. It turned grey, with a lavender band at the blue water (`tune/photo/doubleJ/IMG_7400` light rays). The kernels no longer apply that exception; the white reference strength still uses it. On the Mac: m5 13.34 to 13.17, AquaColorFix gate 12.87 to 13.01. IMG_7400 against AquaColorFix went 14.14 to 15.45: the light stays teal, which Jake preferred by eye. Check sunlit water and pale bellies (a manta, a sunfish) on the iPhone.
- **Bright exception back at 2.2 to 3.2 times (1 Oct 2026).** With no exception, a pale manta kept a teal tint (`O4` core chroma 0.018 to 0.034; AquaColorFix 0.014). The kernels now apply the exception again, but only from 2.2 to 3.2 times the water's luma. At 1.8 to 2.6 times the `IMG_7400` lavender edge came back; at 2.2 to 3.2 it did not. On the Mac: manta chroma 0.034 to 0.029, m5 13.30 to 13.29 (panel 23.96 to 21.32, sand colour noise 0.76 to 0.79), AquaColorFix gate 13.01 to 12.98. Video frames moved 0.5/255 or less (challenge clip, `video2`). Check a pale manta and the `IMG_7400` light rays on the iPhone.
- **Subject mask for the local veil, photos only (1 Oct 2026).** Around a bright subject the local veil read too much light and darkened the water beside it. In `O4` the water around the manta became a dark teal band: lightness against the water above went from +0.005 in the source to -0.032 (+0.010 before the local veil). Vision now finds the photo's subjects once per photo (`SubjectMask`, at most 25% of the frame). The veil's broad light leaves them out, outside the subjects only. `O4`: -0.032 to +0.013; by eye the band is gone and the manta stays white. Video is unchanged (no mask, so no frame-to-frame mask flicker). Check `O4` and a manta photo on the iPhone: no dark band beside the subject, no seam at its edge, and the time to open a photo.
- **Light rays and light gradient (2 Oct 2026).** In `IMG_7400` the light below the surface was one flat white patch with blue right beside it. Two changes:
  - Light detail: inside bright light, a pixel's difference from its blur grows (gamma luminance, x1.3). Strong edges get none. In the light, output rose 0.89 per unit of source lightness before, 1.09 after (AquaColorFix 1.34).
  - Light gradient: a scene where more than 1.2 to 3% of the pixels are 4 times brighter than the water has a strong light source. There the white reference ramps from 2.5 to 8 times the water, not 2.2 to 3.2, so the light fades from white through pale water colour to blue. Video uses the whole clip's value, so no scene switches. Source photos: `IMG_7400` 3.5%; O1 to O5, `IMG_7401` and m5 at most 1.0%. Clips: video2 21%, challenge 0.04%.
  - On the Mac: m5 13.29 to 13.33 (sand 15.27 to 15.51, no visible change), gate 13.12 to 13.14. Placed after vibrance, the light detail gave the Mac video path a vignette (frame edges up to 60 levels brighter); it now runs before the fine detail, and both clips are free of it. Check on the iPhone: `IMG_7400` rays and gradient, and the challenge clip and video2 for a vignette.
- **Open-source license notice (2 Oct 2026).** The bundled depth model is Apple's Core ML version of Depth Anything V2 Small, under the Apache License 2.0. Help now ends with "Open-source licenses": the model, its authors and the full license text (`Resources/Licenses/Apache-2.0.txt`, copied from apache.org). Checked on the simulator in English and Korean. Check once on the iPhone.
- **Video vignette, two platform causes (1 Oct 2026).** The challenge clip showed a dark ring and lavender bottom corners. The same Core Image code failed differently on each platform:
  - Mac: CIHighlightShadowAdjust changed the frame's edge band on the restored path. A clamped input fixes it (videosim corner minus mid-ring lightness at 4 / 12 / 24 s: 0.081 / 0.107 / 0.127 to 0.003 / 0.024 / 0.077; source 0.004 / 0.028 / 0.049).
  - iOS (simulator and iPhone 17): a smoothed copy of the restored image as the colour kernel's reference input broke the edge rows and darkened the output about 7%, even at a reference strength of 0.0009. The kernel now reads the same image. `VideoRestorationTests.testRestoredVideoFrameKeepsItsEdges` failed before (0.961) and passes on both.
  - Cost on the Mac harness: m5 13.17 to 13.30, colour noise on m5 sand 0.40 to 0.77 and coral 2.14 to 2.71. On iOS the smoothing never worked as intended.
  - Check on the iPhone: export the challenge clip and a bright reef photo with sand (reference adaptation), and look for corner rings and noise.

## Water calm and depth image clamp (8 Oct 2026)

See [Water calm](ColorAlgorithm.md#water-calm-8-oct-2026).

- **Done on the iPhone 17 (iOS 27.0.1).** `testRestoredVideoFrameKeepsItsEdges` and the two detail kernel tests pass. A temporary test rendered IMG_7260 and O3 at 1600 px. On IMG_7260 the water noise fell from 0.0137 to 0.0021 (gamma luma), and the brightness ratio against the old path was 1.004. The edge rows matched the old path within 0.01.
- **Full-size photo export.** The radii scale with the short side. Check a 12 MP and a 48 MP export at 100%: clean open water, no line along a subject, small bubbles kept.
- **Real video.** The weight is computed per frame. Watch open water and a fish edge for flicker in `tune/video/challenge_video/original.MP4` and `video2`.
- **Export time.** The calm adds five blurs per photo and per video frame. Export time is unmeasured.
- **Video halo, pre-existing.** The video path has no subject mask. There a bright subject has a broad dark halo: about -8 L* on IMG_7260, before and after this change.

## Violet calm (8 Oct 2026)

See [Violet calm](ColorAlgorithm.md#violet-calm-8-oct-2026).

- **iPhone.** Run `RestorationTests/testVioletCalmKernelMatchesCPUMirror` on the device. Check a reef behind blue water (O5) and a magenta anemone (r04) by eye.
- **Deep blue water.** Violet water turns back to blue at its own chroma. On r05 the water chroma stayed (23.9 to 23.7) and the hue moved from 270 to 267. Check by eye that deep water does not turn grey or indigo.
- **Real video.** The rule is per pixel. Watch a reef edge for flicker.

## HDR photo export (28 Sep 2026)

29 Sep 2026: the real HDR photo and video checks are not done. There is no HDR source yet.

Checked:
- iPhone 17, PhotoHDRTests (3 of 3 pass). A synthetic HDR photo (headroom 4) exported as a JPEG with an ISO gain map. The output headroom was 4.0 and the highlights reached 4.5. The SDR image in the file matched the normal SDR export (average and maximum).
- Simulator: 22 affected unit tests pass. The end-to-end HDR test skips there, because the simulator opens every gain-map photo with headroom 1.

Still open, on the iPhone:
- A real iPhone HDR photo: Export shows SDR/HDR with HDR selected for Pro. The saved photo looks brighter in Photos than an SDR save of the same edit. Colours match between the two saves.
- Memory and time for a 48 MP HDR photo. HDR export renders the full image twice (SDR and HDR).
- The batch screen with a mix of HDR and SDR photos.
- An iPhone without an HDR display: it is unknown whether photos read with headroom above 1 there.
- Live Photos: by decision (28 Sep 2026), a Live Photo imports and exports as its still photo. The motion is not kept, because underwater Live Photos are rare. Check that a Live Photo imports as its still photo from the picker, the share sheet and Files.

## Renamed to UnderBlue (28 Sep 2026)

The app was never uploaded, so the name and every ID changed:
- The first working name: it is a live US trademark for aquatic exercise gear (reg 1550289, class 28).
- MarineLens: a live iPhone app already uses that exact name (NEXASPHERE INC., id 6772336245).
- UnderBlue: the iTunes Search API returned 0 results for "underblue" in the US, KR, JP and GB stores.

New IDs: bundle `com.underblue.app` / `com.underblue.app.share`, App Group `group.com.underblue.app`, product `com.underblue.pro`, URL scheme `underblue://`. Folders, targets, module and kernels use UnderBlue. GitHub: `jakeleekr13-otter/underblue` and `underblue-support` (Pages: https://jakeleekr13-otter.github.io/underblue-support/).

Checked:
- The built app and share extension have those bundle IDs, display name UnderBlue, and URL scheme `underblue`.
- 86 unit tests passed (ExportNaming, Diagnostics, PhotoFormat, Preset, Restoration, Trial). 1 device-only test was skipped.
- `AppStoreAssets/Screenshots/en-US/final-v2/` was regenerated. The label reads UNDERBLUE. The source captures show no app name.

Still open:
- Trademark search for UNDERBLUE: USPTO, KIPRIS, EUIPO. These could not be searched from here.
- Create the app record in App Store Connect early, so the name is held.
- On the iPhone, the new bundle ID installs as a new app. Check that the home screen and share sheet show UnderBlue. Delete the app installed under the old bundle ID.
- The new App Group and app IDs get registered on the first device build with automatic signing.
- The screenshot source captures still show the old colour output. Capture them again after colour tuning ends.
- `scripts/generate_localizations.py` is stale. Its output differs from the catalog by about 6,000 lines. Do not run it.

## Camera colour pulse in video (26 Oct 2026)

`VideoColourTrack` takes short colour pulses of the camera out of video frames. See [ColorAlgorithm](ColorAlgorithm.md#camera-colour-pulses-26-oct-2026).

Checked:

- Napoleon clip: iPhone 17 export through `VideoParityTests`, measured and checked by eye (frames 140 to 159).
- 13 other clips: Mac render (`videosim` built from the tree), against HEAD.
- Device unit tests: `VideoColourTrackTests`, `VideoRestorationTests`, `VideoSceneTests`, `VideoTests`, `AppleLogTests`, `HDRTests`, `VideoParityTests`.

Open:

- Jake: look at the napoleon preview on the iPhone at 5 s. Frames 150 to 155 keep a faint pink.
- Time of the pass on a long 4K clip on the iPhone (measured only on 17 s of 1080p).
- An HDR or Apple Log clip with a real pulse. That path uses Core Image and was not run on such a clip.
- The largest change on the other clips (`2025-05-03 22.12.02.MOV`, 0 s, dE x100 0.52): not looked at by eye.

## Open water the veil fit cannot measure (26 Oct 2026)

See [ColorAlgorithm](ColorAlgorithm.md#open-water-the-veil-fit-cannot-measure-photos-26-oct-2026).

Checked: Mac harness on the jellyfish photo and on 57 test photos (56 byte-identical to HEAD); device unit tests `RestorationTests`, `PhotoTests`, `SubjectCandidatesTests`.

Open:

- Jake: look at the jellyfish photo on the iPhone. The legs and fins clip more than the source (31% against 23.6%).
- Jake does not remember the fin colour (pink or pale violet). The fix keeps them warm (hue 40); AquaColorFix shows pale violet.
- The subject mask misses the swimmer's torso and head (both Vision masks). Not acted on.

## Brightness pulse in video (27 Oct 2026)

`VideoColourTrack` now also takes short brightness pulses out. See [ColorAlgorithm](ColorAlgorithm.md#brightness-pulses-27-oct-2026).

Checked:

- Napoleon clip: iPhone 17 export, brightness per region over the first second; frames 140 to 159 by eye (same as before).
- 14 clips, Mac render against the colour fix only: 57 photos byte-identical; the largest frame looked at by eye.
- Unit tests: `VideoColourTrackTests` with a new brightness pulse case.
- The 2 s colour window: the napoleon clip at 5.4 to 7.0 s on the iPhone; 14 clips on the Mac against the 1 s window.
- Full test runs before the 2 s colour window: iPhone 17 unit tests 288 passed (PurchaseTests and VideoParityTests left out); Mac tests 21 passed with the Thread Sanitizer.

Open:

- Jake: look at the first second and at 6.7 s of the napoleon clip on the iPhone. The fish keeps part of its own pulse (18% against 24% in the source). The 6.7 s red rise is smaller, not gone.
- The first 2 s of the napoleon clip stay pink. Not fixed in 1.1.7 (Roadmap 3.5). 3 Nov 2026: the pink is in the source. Jake: leave it. See ColorAlgorithm.md, "The napoleon clip's first 2 s".

## Reader and writer on the receiver API (27 Oct 2026)

The video export, the output check and the colour pass read and write with the receiver API. The old calls are deprecated in iOS 27. See [Architecture](Architecture.md).

Checked on the iPhone 17 with `VideoParityTests`, against the build before the change:

- SDR exports of 4 clips (an HLG clip, the napoleon clip, a 58 s clip, a 4K 60 fps clip): decoded video frames and audio packets are identical.
- HDR export of the HLG clip: frames differ as much as two runs of the old build differ from each other (57 of 150 frames). The new run matched the second old run exactly. 10-bit HEVC encoding is not repeatable here.
- Speed, 4K 60 fps clip, 770 frames, both runs at thermal state 2: old 228.17 s, new 213.47 s. An earlier set of runs varied by about 25% from run to run.


1. **Colour scorecard.** The 29 Sep candidate was run as `m5-final2-dev-20260929`; rerun if any
   colour source changes. Check every guard in [the harness README](../scripts/color-eval/README.md#guards-used-for-tuning),
   including individual regressions that an improved mean can hide.
2. **Holdout: closed.** The 29 Sep final static candidate was checked once: 20.3411 combined and
   20.3539 uniform. The UIEB set was removed on 2 Oct 2026, so no fresh holdout can run.
3. **Presets.** The tuning round checked each preset at intensity 0.8, on photos only:
   - Tropical on shallow, bright scenes: r03, r08, r10, m5
   - Deep Dive on deep, dark-blue scenes: r02, r09, r11, r12, r13
   - Still to check:
     - intensity values other than 0.8
     - by eye: done on 29 Sep; the three presets were distinct enough to match their names and accepted on iPhone
     - Deep Dive's lavender sea fans on r11, and Tropical's peach sun core on r10
4. **Custom slider ranges.** The caps in `CustomAdjustments.Caps` were measured before the white reference and the highlight shoulder. Measure them again on the current code:
   - all five sliders at -1 and +1, at Custom strength (0.8)
   - the joint budget for Brightness, Contrast and Saturation
   - Saturation and Temperature: on 25 Sep 2026 the product owner found Saturation very weak and Temperature not visible on the iPhone. `7651372` widened both. Check on the iPhone that both are clearly visible at ±50 and ±100, that + Temperature warms and - cools, and that water never turns neon, indigo or green.
   - one SDR clip and one HDR clip
   - 20 Oct 2026: Brightness up and Contrast up were widened after a tester said they barely show (numbers in [ColorAlgorithm](ColorAlgorithm.md)). Check on the iPhone at +50 and +100: both are clearly visible. Contrast -100 should also be clearly visible, but dark areas must keep their depth: no milky haze over the whole picture (22 Oct 2026 fix, `13de04e`; render numbers not measured). Check a dark scene and a bright blue scene. Since 22 Oct the curve bends the tones above the pivot, with `contrastDown` 0.70 (the curve floor of -0.7 is the limit; -0.8 nearly flattens it): highlights and mid-tones should come down clearly while dark areas stay put. **Done 22 Oct 2026 on the iPhone 17: accepted by Jake (no haze, clearly visible).** Look at m5-like scenes (dark teal water): Contrast +100 deepens the shadows. Decide by eye if that is acceptable. Custom at 0 now equals Natural at 0.8 (it was full strength).
5. **Real video on the iPhone.** Use 2 or 3 real dive clips, including 1 SDR and 1 HDR. Check:
   - colour stays stable from frame to frame
   - bright sand and the sun do not clip (the highlight shoulder)
   - neutral surfaces look grey (the white reference)
   - the Custom sliders change the preview and the export in the same way
   - HDR highlights stay above SDR white
6. **Full unit tests.** Run `xcodebuild test -scheme UnderBlue -only-testing:UnderBlueTests -skip-testing:UnderBlueTests/PurchaseTests` on a simulator.
7. **UI tests.** Run `UnderBlueUITests`. See the known failures below.
8. **Custom UI by hand.**
   - Custom sliders on a video. The simulator has no videos, so the UI test skips it.
   - Custom on the batch screen. The UI test needs Pro.
   - VoiceOver on a device.
9. **App Store text.** Update the preset descriptions after the preset check.

## Known issues to keep in mind

- **PurchaseTests are not run** (decision, 29 Sep 2026). Purchases are checked by hand with a sandbox account instead. See `QA.md`.
  - Why they hang: storekitd rejects the test session with "com.underblue.app is not installed for development" (`SKInternalErrorDomain Code=3`).
  - StoreKit then uses the real sandbox. `purchase()` waits for a sandbox sign-in that never comes, and the test has no time limit.
  - Seen on 25 Sep and 29 Sep 2026. Why storekitd rejects the app is unknown.
- **LongVideoTests can fail under load.** In one full run, the memory growth was 424 MiB against a 220 MiB limit. Another agent was running at the same time. Run alone twice, it passed with 134 MiB and 154 MiB.
- **UI tests that already failed at `6a850b4` on this simulator:**
  - `UnderBlueUITests.testPhotoImportPresetsCompareExportSaveAndTrialGate`, lines 24–29
  - `UnderBlueUITests.testVideoImportAndLandscapeEditor`: the picker shows "No Videos"
  - `AppStoreScreenshotTests.testPhotoBeforeAndAfter`, line 35
- **`xcodebuild test` can hang after the last test.** On 28 Sep 2026 the results were complete at 07:46, but the process was still running 10 minutes later. Read the log, then stop the process.
- **A build can rewrite `Localizable.xcstrings`.** It adds a space before every colon and auto-extracts keys. If `git diff --stat` shows thousands of changed lines, restore the file.

## Done on 25 Sep 2026

- The two device-only tests passed on an iPhone 17 (iOS 27.0):
  - `testBundledDepthModelProducesCompactFiniteDepth`: one depth inference took 32.6 ms
  - `testFiveFrameAnalyzerOnPhysicalDevice`: 14.1 s in total
- Unit tests at `e02c19e`: 127 run, 2 skipped (device only), 0 failed. An earlier full run failed only the LongVideoTests memory test, under load (see above).

## Ideas, not planned

- **Mac.** Planned (Jake, 1 Oct 2026): a Mac version sold at a higher price, built around an enhanced batch job for many photos and videos at once. Core Image renders some filters differently on the Mac and iOS (see the video vignette entry above), so the Mac app needs its own gate and m5 run. Decide then whether the reference smoothing returns on the Mac only. The project is iPhone only today (`TARGETED_DEVICE_FAMILY = 1`). Mac support and Mac Catalyst are both off. The Processing code already runs on a Mac: the harness compiles it into a Mac tool. The smallest step is to run the iPhone app on Apple silicon Macs. It still needs a check of the photo picker, saving, StoreKit and video export on a Mac.

## JPEG colour resolution: simulator only (11 Nov 2026)

`PhotoFormatTests.testJPEGExportKeepsFullColorResolutionAndTheCaptureDate` failed on every simulator run since 31 Oct 2026 (2x2 sampling).

Cause, measured with a small probe that writes a 96 x 64 image:

| Writer | macOS 27.2 | iOS 27.2 simulator |
|---|---|---|
| `CIContext.writeJPEGRepresentation`, quality 1 | 1x1 | 2x2 |
| `CGImageDestination`, quality 1 | 1x1 | 1x1 |
| Both, quality 0.99 | 2x2 | 2x2 |

- On the simulator, `CIContext` wrote 2x2 with every option tried: Double, Float or NSNumber quality, no options, the software renderer, and `jpegRepresentation` (Data).
- The app writes with `CIContext` (`PhotoProcessor.swift`).
- On the iPhone 17 (iOS 27.2.1, 11 Nov 2026) all 5 `PhotoFormatTests` pass, the JPEG test included. So exported JPEGs keep full colour resolution on the device.
- Decision (Jake, 11 Nov 2026): no code change. The test skips on the simulator and runs on devices.
