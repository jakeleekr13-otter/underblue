# UnderBlue roadmap

Status: draft, updated 12 Nov 2026. Nothing here is decided unless a line says "Jake".

This page only collects open work. Each row points to the document that holds the details.

Device checks and reviews that wait for Jake are not listed (Jake, 12 Nov 2026). He reports a problem when he finds one.

## Where we are (12 Nov 2026)

- iPhone 1.1.14 (20) is on the App Store. It was released on 11 Nov 2026 at 16:10 UTC (App Store lookup, 12 Nov 2026). New: video preview zoom (section 8).
- 1.1.13 (19) added Quick, quality levels and the estimate without a probe (section 7). 1.1.11 (17) held the flow review fixes. 1.1.10 (16) added the free trial with a watermark.
- The Mac app 1.0 (1) was resubmitted on 28 Oct 2026 after a rejection for "for Mac" in the name ([MacAppStoreRelease](MacAppStoreRelease.md)). An App Store lookup by bundle ID on 12 Nov 2026 found no Mac app. The review result is not recorded here.
- The restoration run is done for photos ([RestorationExperiments](RestorationExperiments.md)).
- The website has landing pages in six languages ([AppStoreRelease](AppStoreRelease.md)).

## 2. Mac app 1.0 release (after the first review)

Order matters. The hardening changes the binary, so it comes before the archive.

| # | Work | State | Source |
|---|---|---|---|
| 2.1 | Hardening: archive, measure `strings`/`nm`/metallib, turn off Swift reflection names, rename Metal kernels | Jake: do it before the next Mac build. Jake, 3 Nov 2026: start after the first Mac review ends. The iPhone 1.1.7 archive is measured: the archive strips symbols; field names and Metal names stay. | [MacAppStoreRelease](MacAppStoreRelease.md#hardening) |
| 2.2 | Mac archive with the work on `main` since 1.0 (1): the new free trial, the Mac flow fixes of 4 Nov 2026, and video preview zoom | Open. The build in review has the old trial. | [MacAppStoreRelease](MacAppStoreRelease.md) |
| 2.4 | Metadata parts 2 and 3, IAP display name and description | Drafts not finished. | [MacAppStoreRelease](MacAppStoreRelease.md) |
| 2.5 | Japanese and Chinese text: ship as is, or get a native review | Jake decides. | [MacAppStoreRelease](MacAppStoreRelease.md) |
| 2.6 | Thin bright or dark lines on some edges (turtle, clownfish) | Softer since `ad6ab7f`, not gone. | [MacApp](MacApp.md) |
| 2.7 | Memory on 8 GB Macs and long 4K video | Not measured. | [MacApp](MacApp.md) |
| 2.8 | After the release: Mac App Store link on the website (`MAC_APP_STORE`) | Open. The site says "coming soon" until then. | [MacAppStoreRelease](MacAppStoreRelease.md) |

## 3. Video quality (after the Mac release)

| # | Work | State | Source |
|---|---|---|---|
| 3.2 | Apple Log: real clips (Log ProRes, Log 2 ProRes and HEVC), look of mid-tones | Generated clips only. Needs footage. | [Verification](Verification.md) |
| 3.4 | Particle filter for video | Off by default. Jake: record only for now. Turn on at about +20% time and +100 MB. | [RestorationExperiments](RestorationExperiments.md) D2 |

## 4. Photo quality (open, no plan yet)

| # | Work | State | Source |
|---|---|---|---|
| 4.1 | Green seagrass shifts 10-32 degrees toward yellow | Studied, not adopted. Colour alone cannot tell olive reef from seagrass. | [RestorationExperiments](RestorationExperiments.md) |
| 4.2 | Bright sand grain on m5: 2.07x (Sea-thru 1.43x) | Better after `ca75540`, still above the reference. | [RestorationExperiments](RestorationExperiments.md) |
| 4.3 | Smaller lift on translucent parts (fins) | Jake: on hold until a real photo shows it. | [ManualSubject](ManualSubject.md) |
| 4.4 | VoiceOver way to pick a subject | Not designed. | [ManualSubject](ManualSubject.md) |
| 4.5 | Labs orb switch: export takes longer when on | After the 48 MP fix: 4.2-4.4 s off, 5.1-5.8 s on (20 MP). Not explained. Labs only, off by default. | [Verification](Verification.md) |

## 5. Waiting for a decision

| # | Idea | State | Source |
|---|---|---|---|
| 5.1 | LUT presets (fixed pool, auto pick) | Jake is not sure it is needed (26 Oct). Nothing built. | [LUTPresets](LUTPresets.md) |
| 5.2 | iPhone Duo | Stage 2 (fold split) built on 19 Oct 2026. Open: video preview fails on the iOS 27.1 Duo simulator; rotation while folded not checked. | [iPhoneDuoSupportPlan](iPhoneDuoSupportPlan.md) |
| 5.3 | ProRAW 48 MP and many 48 MP photos in one batch | Jake: accepted as open (26 Oct). | [Verification](Verification.md) |
| 5.4 | "Changes waiting for the final round" (5 commits) | The list dates from 29 Sep. Not updated since. Jake: run the round, or close the list. | [Verification](Verification.md) |

Decided against for now (Jake): finishing an export in the background, a call during export (follows the background rule), and Android.

Kept as is (Jake, 4 Nov 2026): the player's own play button plays the whole video, also for free users. Only the 3s Preview button stops after 3 s. A screen recording of the preview has no watermark, and Jake accepts this. A screenshot of a photo preview is the same.

## 7. Video export speed (Jake, 9-10 Nov 2026)

Built on 10 Nov 2026: 7.1, 7.4, 7.6 and 7.7. Shipped in iPhone 1.1.13 (19). No open rows; the notes stay as the record. Checks are in [Verification](Verification.md), "Export: Quick, quality levels, estimate". Times are in [PerformanceMeasurement](PerformanceMeasurement.md), "Estimate against real exports".

The export sheet now offers Original / 1080p / Quick, and a quality level for each (Jake, 10 Nov 2026).

| # | Work | State | Source |
|---|---|---|---|
| 7.1 | Quick: at most 720p and 30 fps | Built 10 Nov 2026. Pro only. HDR allowed. | `ExportOptions.swift`, `VideoExporter.swift` |
| 7.2 | A 30 fps choice for the 1080p export | Dropped. Jake chose Original / 1080p / Quick (10 Nov 2026). | — |
| 7.3 | Estimate probe: a fixed frame count in place of 1 s | Replaced by 7.4. | — |
| 7.4 | Estimate with no probe: frame count × this device's time per frame | Built 10 Nov 2026. | `ExportSpeed.swift`, `EditorModel.swift` |
| 7.5 | Remove the 1080p choice | Dropped. Jake kept 1080p (10 Nov 2026). | — |
| 7.6 | Quality levels: High / Standard / Small | Built 10 Nov 2026. | `ExportOptions.swift` |
| 7.7 | Bitrate cap: the source's average bitrate × the level | Built 10 Nov 2026, after the VBR check. | `VideoExporter.bitrate` |
| 7.8 | Long exports take longer than the estimate (heat) | Closed. Jake, 10 Nov 2026: keep it as it is; an estimate is only an estimate. | Notes for 7.8 |

Notes for 7.1 (Quick):

- Frames are kept on a time grid (`FrameRateLimiter`), so variable source timing stays. 60 fps keeps every 2nd frame, 120 fps every 4th, 50 fps every 2nd (25 fps). A source at 30 fps or less keeps every frame.
- The reader still decodes the dropped frames. Only the filter, render and encode are saved.
- The bitrate and the encoder frame rate use the output rate. `OutputValidator` needed no change: the session still ends at the source end.
- The particle filter sees only the kept frames. It is off by default (row 3.4).
- A tall source fits the 1280 × 720 frame by its long side: 1182 × 2560 becomes 590 × 1280. The row says "720p · 30 fps".
- Measured on the iPhone 17, 25 s 1182 × 2560 120 fps clip: Quick took 16.4 s, run right after two long exports. 1080p took 134 s, started cool.

Notes for 7.4 (estimate):

- The frame count, size and length come from import (`VideoMetadata`). The device speed is saved on the device (`ExportSpeedStore`).
- One saved value per kind: restoration on or off, SDR or HDR. A new iOS major version starts over.
- A finished export saves its time per frame. Not after a pause, and not for Quick from a faster source (it decodes frames it drops).
- No saved value: one 1080p probe when its export would pass the memory check. Otherwise no time shows.
- Other sizes: 40% of the time per frame is fixed and 60% grows with the pixel count. From 886 × 1920 to 1182 × 2560 the pixels grew 1.78x and the time 1.39-1.55x (9 Nov probes), so 29-50% did not grow.
- Quick's dropped frames are not in the model. Measured: Quick estimate 19.9 s, real 16.4 s.

Notes for 7.6 and 7.7 (quality):

- Standard is the bitrate rule from before: 0.12 bits per pixel per frame, 6 to 100 Mbps. High is 1.5x, Small 0.5x. The 100 Mbps cap stays.
- Each resolution starts at its own level: Original High, 1080p Standard, Quick Small. Pro can change all three. A new resolution goes back to its default.
- Free: 1080p at Standard only. The sheet locks the other rows and the quality control.
- The bitrate never goes above the source's average bitrate × the level (`estimatedDataRate`). A 0.1 Mbps source no longer becomes a 6 Mbps file.
- VBR check (iPhone 17, 10 Nov 2026): the encoder still gives more bits to busy scenes under the cap. A clip with a calm half and a noisy half got 0.29 and 2.56 Mbps at Standard. SSIM against an uncapped export: 0.961-0.998 at Standard. The lowest was 0.942 (Small, first half of the 292 × 632 clip).
- The batch screens use Original, so they now export at High. Not measured.
- Quick at Small (3 Mbps, 720p, 30 fps), iPhone 17, three real clips with High (9 Mbps) as the reference: SSIM 0.957-0.969, PSNR 35.7-39.0 dB. Standard (6 Mbps): SSIM 0.971-0.982. At 2x zoom Small softens coral branches, rock texture and bubbles a little. No blocks or banding were seen in the frames checked. High is not lossless, so these numbers understate the full loss.

Notes for 7.8 (heat):

- iPhone 17, 1182 × 2560 120 fps clip, 1080p. Started cool: 134 s against an estimate of 119 s. Thermal state rose from 0 to 2, and the last 5% steps took about 25% longer than the first.
- Run straight after a 13-minute export: 373 s against 119 s.
- Original right after the probe: 780 s against 175 s. The thermal state was not logged in that run.
- The estimate saves the speed of each finished export, so the next estimate includes the slowdown of the last one.
- Options were a heat factor that grows with the export length, or a note that long exports can take longer. Jake chose neither (10 Nov 2026).

## 8. Video preview zoom (Jake, 10 Nov 2026)

| # | Work | State | Source |
|---|---|---|---|
| 8.1 | Zoom on the video preview, while paused and while playing | Shipped in iPhone 1.1.14 (20). The Mac code is on `main`, for the next Mac build. | `ZoomableVideoPreview.swift` |
| 8.2 | Mac: no playback and no zoom during the scene analysis, as on the iPhone | On `main`, for the next Mac build. Before, the Mac played the original during the analysis. | `PreviewPane.swift` |

Decided (Jake, 10 Nov 2026):

- The same gestures as the photo preview: pinch, double tap, and pan while zoomed.
- No zoom during analysis. The player takes no touches then.
- Mac gets the same zoom, and the same lock during analysis (Jake, 11 Nov 2026).

Notes for 8.1:

- `PreviewZoom` already holds the photo limits: up to 4x, double tap to 2.5x.
- The preview can render below full size to stay inside the pixel-rate budget (`VideoPreview.swift:75`). So a zoomed frame can look softer than the export.
- How it works: the player view keeps its controls. While zoomed, a second `AVPlayerLayer` of the same player draws the zoomed frame in the player's video overlay, under the controls.

## Recommended order

1. Section 2, after the Mac review ends: the Mac release, hardening first. The app is built, and the Mac price is the higher one ([MacApp](MacApp.md)).
2. Section 3: 3.2 waits for real Log clips.
3. Sections 4 and 5 only when a real photo or a user asks for it.
