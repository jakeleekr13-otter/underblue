# UnderBlue roadmap

Status: draft, updated 28 Oct 2026 (website); 27 Oct 2026 for iPhone 1.1.7 (13). Nothing here is decided unless a line says "Jake".

This page only collects open work. Each row points to the document that holds the details.

## Where we are (27 Oct 2026)

- iPhone 1.1.6 (12) shipped on 26 Oct 2026 (Jake). 1.1.7 (13) is uploaded (Jake, 27 Oct 2026).
- `main` is pushed. Changes since 1.1.6:
  - camera colour and brightness pulses in video ([ColorAlgorithm](ColorAlgorithm.md))
  - even water in murky open water photos
  - the engine file split and the concurrency rules ([Architecture](Architecture.md))
  - the reader/writer move to the receiver API
- The Mac app 1.0 (1) is in App Review: rejected on 27 Oct 2026 for "for Mac" in the name (Guideline 5.2.5), resubmitted on 28 Oct 2026 with the same build and a new name ([MacAppStoreRelease](MacAppStoreRelease.md)).
- The restoration run is done for photos ([RestorationExperiments](RestorationExperiments.md)).
- 28 Oct 2026: the website has landing pages in six languages, and Google Search Console is set up ([AppStoreRelease](AppStoreRelease.md#website-and-google-search-console-28-oct-2026)).

## 1. Ship iPhone 1.1.7 (now)

| # | Work | State | Source |
|---|---|---|---|
| 1.1 | Release notes for 1.1.7: only the changes since 1.1.6 | Jake approved the English text (27 Oct). | [AppStoreMetadata](AppStoreMetadata.md) |
| 1.2 | Upload the 1.1.7 archive | Done (Jake, 27 Oct 2026). | — |
| 1.3 | Press-and-hold subject pick on the iPhone (U6) | Open. Jake checks. | [ManualSubject](ManualSubject.md) |
| 1.4 | Labs orb switch: export takes about 4.5 s longer when on | Measured, not explained. Labs only, off by default. | [Verification](Verification.md) |
| 1.5 | Jake's iPhone checks: jellyfish legs and fins clip 31% (source 23.6%); napoleon clip at 6.7 s, the red rise is smaller, not gone; shallow-water shark photo (3 Oct); subject strength slider drag | Open. Jake checks. If the slider still lags, cache the frame before the lift. | [Verification](Verification.md), [ManualSubject](ManualSubject.md) |
| 1.6 | Offer code redemption: in the app, by URL while the app is closed, and an invalid code | Open. By hand with a sandbox offer code. | [Verification](Verification.md) |

## 2. Mac app 1.0 release (next)

Order matters. The hardening changes the binary, so it comes before the archive and the checks.

| # | Work | State | Source |
|---|---|---|---|
| 2.1 | Hardening: archive, measure `strings`/`nm`/metallib, turn off Swift reflection names, rename Metal kernels | Jake: do it before the next Mac build. The iPhone 1.1.7 archive is measured: the archive strips symbols; field names and Metal names stay. | [MacAppStoreRelease](MacAppStoreRelease.md#hardening) |
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
| 3.1 | m6 reef stays olive in video (photo is brown) | Fixed on branch `video-reef-colour` (29 Oct): each scene fits the video rule to the photo rule on its keyframe. Video reef hue 132 → 98 (photo 93). Not merged. Open: a real reef clip and the cost on the iPhone. | [RestorationExperiments](RestorationExperiments.md) |
| 3.2 | Apple Log: real clips (Log ProRes, Log 2 ProRes and HEVC), look of mid-tones | Generated clips only. Needs footage. | [Verification](Verification.md) |
| 3.3 | Preview and export use different gamma (1.961 and 2.4) | The same frame reads 0.31 and 0.38. Not checked on a display. | [Verification](Verification.md) |
| 3.4 | Particle filter for video | Off by default. Jake: record only for now. Turn on at about +20% time and +100 MB. | [RestorationExperiments](RestorationExperiments.md) D2 |
| 3.5 | Napoleon clip, first 2 s: the fish is pink, then grey at 1.5 s | Jake saw it (27 Oct). Old behaviour. The clip starts facing the surface, and the water holds red until 1.4 s. The analysis made two one-keyframe scenes (0 s, 1.06 s). The colour track cannot fix a start state. Jake: ship 1.1.7 without it. | [ColorAlgorithm](ColorAlgorithm.md) |
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

## Recommended order

1. Section 1: ship 1.1.7. Most of it is Jake's steps.
2. Section 2: the Mac release. The app is built, and the Mac price is the higher one ([MacApp](MacApp.md)).
3. Section 3, starting with 3.3: users see one picture and save another. It needs only a check on a display. 3.2 waits for real Log clips.
4. Sections 4 and 5 only when a real photo or a user asks for it.
