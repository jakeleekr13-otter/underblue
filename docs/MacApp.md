# UnderBlue for Mac — plan

Status: decisions made 1 Oct 2026. Nothing built yet.

## Goal

- A separate Mac app with its own bundle ID and its own price.
- Selling point: one batch job for many photos and videos at once.
- Use the Mac's extra memory, GPU and Neural Engine for more parallel work.

## Facts this plan rests on (read 1 Oct 2026)

| Fact | Source |
|---|---|
| The project has one iPhone-only app target. Catalyst and "Designed for iPhone" are off. | `scripts/create_project.py`, `project.pbxproj` |
| Targets use synchronized folders. The project file is generated. | `create_project.py` |
| `UnderBlue/Processing/` has no UIKit. The colour harness already builds it for macOS. | `scripts/color-eval/common.sh:29-33` |
| 11 files touch platform APIs: `UIApplication` background tasks and memory warnings, `navigationBarTitleDisplayMode`, `fullScreenCover`, `PhotosPicker`, `PHPhotoLibrary`, the share inbox. Not all are iOS-only; the build in stage 1 decides. | grep on `UnderBlue/` |
| Batch takes photos only, at most 10. It exports one at a time. | `BatchModel.swift:8`, `:149` |
| `PhotoProcessor` is one actor, so all photo work runs one job at a time. | `PhotoProcessor.swift:19` |
| The performance tier stops at "memory ≥ 5 GB → high". It was tuned for iPhone. | `VideoProcessingPolicy.swift:79` |
| The same Core Image code renders differently on Mac and iOS. | memory `mac-version-plan`, commit 46958c3 |

## Structure

- Same repo, same Xcode project. A new target `UnderBlueMac` is added in `create_project.py`.
- Shared code: `UnderBlue/Processing`, `Models`, `Export`, `Diagnostics`, `Commerce`. Both targets compile it.
- Mac-only code: a new folder `UnderBlueMac/` (app entry, Mac views, file import, folder export).
- iOS-only files stay in `UnderBlue/` and are excluded from the Mac target by a per-file `membershipExceptions` list. (A folder path does not work there; see memory `synchronized-group-exclusion`.)
- Small iOS-only calls inside shared files go behind `#if os(iOS)`.
- Native macOS target with SwiftUI. Not Catalyst: Catalyst carries the iPhone layout and blocks a Mac-style batch window.

## Mac interface

SwiftUI on macOS draws native Mac controls. The Mac app gets:

- One main window: sidebar with the queue, centre with a before/after preview, right inspector with Look, preset and Custom sliders.
- Toolbar: Add, Correct, Pause, Stop, output folder.
- Drag and drop from Finder: files and whole folders.
- Menu bar commands and keyboard shortcuts (⌘O add, ⌘R correct, ⌘. stop, ⇧⌘O show results, ⌘, settings). The app menu has "UnderBlue Pro…": Buy, Restore Purchase and Redeem Code open from there at any time.
- Show in Finder: a link under the queue and a context-menu item on a finished file. With the Photos library as target it reads "Open Photos".
- A Settings window: output folder, photo format, HDR, parallel jobs.
- Progress on the Dock icon and a notification when the batch ends.

Views that can be reused after small changes: `CustomAdjustmentControls`, `ZoomablePreview`, `ProView`, `DiagnosticsView`.

## Stages

Each stage ends with one artifact that can fail.

| # | Stage | Work | Artifact |
|---|---|---|---|
| 0 | Decisions | Done 1 Oct 2026. | Decisions table below |
| 1 | Target | Add the `mac` scope to `create_project.py`: `SDKROOT macosx`, Mac bundle ID, App Sandbox entitlements. Empty window. | `xcodebuild` build passes for `UnderBlueMac` and for `UnderBlue` (iOS) |
| 2 | Platform seams | Put background task and memory warning behind one small lifecycle type. Split iOS-only modifiers. | Both builds pass; `git diff --stat` shows no change in `Processing/` |
| 3 | Batch engine (shared) | Stage pipeline (see "Batch engine design"): photos and videos mixed, no 10-item cap, per-item state, cancel, resume, name clashes through `ExportNaming`. | Mac unit test: 3 photos + 2 videos → 5 files, each passes `OutputValidator`, finished in queue order |
| 4 | Mac UI | Window, sidebar, inspector, toolbar, drop, menus, Settings, security-scoped bookmark for the output folder. | Screenshot of the app running a 20-item mixed batch |
| 5 | Commerce | Mac price model and product IDs. Own StoreKit config. Own trial key. | Manual sandbox check (no StoreKit tests, memory `no-storekit-tests`) |
| 6 | Mac colour numbers | Run the gate and m5 as Mac product numbers. Compare one Mac app export with the harness render. Decide on Mac-only reference smoothing. | Gate and m5 output lines; ΔE of app export vs harness |
| 7 | Performance | Mac tier in `VideoProcessingPolicy`: parallel job count, memory limit, encoder sessions. Only after the algorithm is final (memory `algorithm-before-performance`). | Timing table on one fixed set: photos per minute, video speed vs real time, before and after |
| 8 | Release | New App Store Connect app, Mac screenshots, metadata, privacy manifest, sandbox review. Checklist: [MacAppStoreRelease.md](MacAppStoreRelease.md). | Build accepted in App Store Connect |

Stages 1–2 change only build setup and seams. Stages 3 and 4 can run in parallel after stage 2.

## Shared with the iPhone app

The Mac app reuses the iPhone code wherever the behaviour is the same:
- Processing, export, models, commerce, diagnostics: the same files.
- Screens: `CustomAdjustmentControls`, `ZoomablePreview`, `LicensesView`, and the Help view (`DiagnosticsView`) and the Pro screen (`ProView`) with `#if os(...)` for the few differences.
- Text: one string catalog (`UnderBlue/Resources/Localizable.xcstrings`) for both apps. Mac text reuses the iPhone keys where the meaning is the same.
- Only the window layout (queue, preview, look panel, Settings, menus) is Mac-only.

## Same look as the iPhone app

Decision (Jake, 20 Oct 2026): the Mac app must correct to about the same level as the iPhone app. So there is one colour algorithm for both. No Mac-only branch.
- The reference smoothing (a slightly blurred copy of the image as the colour kernel's reference input) stays off on both. It broke the iPhone render (commit 46958c3). Turning it on for the Mac only would reduce Mac colour noise (m5 sand 0.40 to 0.77 when it was dropped) but would make the two apps differ.
- Measured on 20 Oct 2026, same six photos, default look (Natural Dive, 0.8), Mac app export against an iPhone 17 (real device) export, CIE76 after conversion to sRGB:

| Photo | mean dE | 95% of pixels below |
|---|---|---|
| IMG_7255 | 1.75 | 4.09 |
| O2 | 1.92 | 3.61 |
| O3 | 1.39 | 2.82 |
| O4 | 0.70 | 1.99 |
| O5 | 0.68 | 2.10 |
| m5 | 4.61 | 13.68 |
| Mean of six | 1.84 | |

- m5 differs most. The difference is smooth and sits in the far water (top right cells 13 to 16 against 2 to 3 elsewhere) and near the horizon. It looks the same by eye. Cause not checked; a different result of the depth model on each chip is the guess.
- The iOS **simulator is not a stand-in for the iPhone**: it differed from the device by 7.79 on average (m5 14.26). Always use the device.
- How to repeat: `UnderBlueTests/PhotoParityTests` exports a folder of photos with the app's photo path. On the device, copy the photos to `Documents/parity-in` of the app container with `xcrun devicectl device copy to ... --domain-type appDataContainer --domain-identifier com.underblue.app`, run the test with `-destination id=<device>`, and copy `Documents/parity-out` back. On the Mac, run the Mac app with `--ui-demo-folder <dir> --ui-demo-output <dir> --ui-demo-pro --ui-demo-start`.
- Not measured: videos, HDR photos, the Custom look, other iPhone models.

## Progress (20 Oct 2026)

| # | Stage | State | Evidence |
|---|---|---|---|
| 1 | Target | Done, with the share extension `UnderBlueMacShare` | Both builds pass. The share menu itself is not run: it needs a signed build. |
| 2 | Platform seams | Done | `BackgroundTask`, `#if os(iOS)` in two shared files. `Processing/` unchanged. |
| 3 | Batch engine | Done, plus `MemoryGovernor` | `BatchEngineTests`, `MemoryGovernorTests` |
| 4 | Mac UI | Built: window, queue, preview, look controls, Settings, Help, About, drop, menus, Dock count, notification. Added 20 Oct: "UnderBlue Pro…" menu item, Show in Finder / Open Photos (link also shows after a relaunch), Start renamed Correct, notice bar moved to the preview column (it covered the queue summary). | A 20-item mixed batch ran in the app. A 6-item mixed batch ran again on 20 Oct. Not clicked through: menu shortcuts, drop, Settings. |
| 5 | Commerce | Done except three checks: product ID, paywall (the shared `ProView`, with Redeem Code), trial reuse, local StoreKit file `StoreKit/UnderBlueMac.storekit` (test price 19.99). Price is 19.99 USD. | Sandbox check on 20 Oct: the product loaded (1 product), a sandbox purchase gave `entitlements=1 owned=true`, and the export ran. Not checked: Pro after a relaunch, Restore Purchase, a refund, Redeem Code against the store. |
| 6 | Mac colour numbers | Measured on the Mac harness, which compiles the app's own `Processing` sources. After the fine-detail edge fix `ad6ab7f` (20 Oct, other session): gate **13.03** (was 13.02; allowed rise 0.1); m5 `combined` full image dE **12.98** (was 13.26), panel 21.63, sand 15.37, coral 15.58, water 10.20 (CIE76). Before that fix: gate (pairs 2, 4, 5, photo path) 13.02; mean of all five pairs 10.91. The Mac app's export of m5 matches the harness `combined` render: mean dE 0.97, 95% of pixels below 2.58, max 7.24. | `aquacolorfix_eval.sh` and `m5_eval.sh` on 20 Oct 2026. The app-against-harness comparison (mean dE 0.97) was made before `ad6ab7f`; one photo (m5) only. |
| 7 | Performance | Memory only. Speed tuning waits for the algorithm. | Memory peak table in the `MemoryGovernor` commit message |
| 8 | Release | Checklist in `MacAppStoreRelease.md`. Icon is the shared Icon Composer icon (24 Oct 2026). Copyright is `2026 Enheart`. IAP `com.underblue.mac.pro` is in App Store Connect (Prepare for Submission). Five captioned screenshots (2560×1600) and the IAP review screenshot are made. App Review Guidelines were checked against the code on 20 Oct. | `UnderBlue/Resources/AppIcon.icon`; `AppStoreAssets/Screenshots/mac-en-US/final`; `AppStoreAssets/IAP/Mac` |

Open items:
- The Mac icon is the iPhone's Icon Composer file, `UnderBlue/Resources/AppIcon.icon` (24 Oct 2026).
- Signed-build checks: sandbox bookmark after relaunch, app group, share menu, Pro after a relaunch, Restore Purchase.
- Photo edges: the fine detail layer still draws thin bright or dark lines on some edges (turtle, clownfish) after `ad6ab7f`. They are softer, not gone. The screenshots avoid the turtle.
- The screenshots were taken from an unsigned Debug build of the same sources. Retake them if the release build changes the look.
- Long 4K video and 8 GB Macs are not measured for memory.

## Batch engine design (stage 3)

Facts from the code (1 Oct 2026):
- `VideoExporter.export` handles one frame at a time: read, Core Image render, append. Each step waits for the one before it.
- Video work has two phases. Analysis is mostly CPU: on iPhone 17, 24.9 s, of which depth on the Neural Engine was about 0.6 s (Debug build, memory `video-open-trace`). Export is GPU render plus the hardware encoder.
- `VideoExporter` and `PhotoProcessor` are actors, so one instance runs one job at a time.

Design: a stage pipeline, not a free-for-all.
- Each item goes through `analyze → export → save`.
- Each stage has its own job limit. Default: analysis 1, video export 1, photo export N (limited by memory).
- So while video 1 exports on the GPU, video 2 analyses on the CPU. Results still finish one by one, in order.
- The limits are numbers in the Mac performance tier. Stage 7 sets them from measurement: 1 vs 2 video exports at once, on the same set of clips.
- Memory is the hard limit: a job starts only if its estimated memory fits.

Why not "all videos at once": the first result comes late, a cancel loses more work, and memory use grows with the count.
Why not "strictly one at a time": the CPU idles during export, and the GPU idles during analysis.

## Decisions (Jake, 1 Oct 2026)

| # | Question | Answer |
|---|---|---|
| 1 | Bundle ID | `com.underblue.mac` |
| 2 | Price model | Free download + in-app purchase. Proposed product ID `com.underblue.mac.pro`. Trial: yes, same as iOS — reuse `TrialStore` (one free photo export, one 10 s video export, per device). No batch in the trial: batch is Pro only, and the paywall says so. |
| 3 | Lowest macOS | macOS 26, Apple silicon only. Depth estimation stays. |
| 4 | Store | Mac App Store only (sandboxed) |
| 5 | Save target | User chooses: a folder or the Photos library. Setting in Settings, default open. |
| 6 | Share extension | Yes, like the iPhone app: share from Photos and Finder into UnderBlue. |

Effects on the stages:
- Stage 1 adds the sandbox entitlements: user-selected files (read-write), Photos library, app group.
- Stage 1 also adds the Mac share extension target `UnderBlueMacShare`.
- Stage 4 adds the save-target choice. The Photos library path reuses `PhotoLibrarySaver`.
- Stage 5 uses the new product ID. The Mac paywall names batch (many photos and videos at once) as the Pro feature.

## Risks

- Mac and iOS render differently. Every colour change needs one check on each platform.
- Sandbox: the output folder needs a security-scoped bookmark, or writes fail after a relaunch.
- Memory: many 4K/HDR videos at once can exhaust memory. The queue must limit by memory, not only by count.
- A shared batch engine also changes the iPhone batch. iOS keeps its own limits.
