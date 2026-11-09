# Server model pilot (Private Cloud Compute)

Date: 9 Nov 2026
Status: research only. Nothing in the app changed.
Recommendation: do not build the Labs toggle now.

## Question

Jake asked two things:

1. Can a Labs switch use Apple's server model when the device is online?
2. Does the server model make the corrected photo better?

## Result

- **It is possible** on iOS 27 and macOS 27. The developer must qualify (see below).
- **No quality gain was shown.** Two small pilots found no visible gain.
- The model reads broad scene facts well, such as the water colour.
- Our analysis already measures those facts from pixels.
- The model failed the two questions where our analysis needs help.
  - It called sargassum "yellow-green". The plant is golden-brown.
  - It called water-lit coral a white object. That is the trap behind the white reference hue gate (docs/JpegInput.md, J5).

## What the API offers

| Item | Fact | Source |
|---|---|---|
| API | `PrivateCloudComputeLanguageModel`, passed to `LanguageModelSession(model:)` | Xcode 27.2 SDK |
| OS | iOS 27, macOS 27, watchOS 27, visionOS 27 | SDK `@available` |
| Image input | Yes. `capabilities.contains(.vision)` was true on this Mac | Apple doc + Mac probe |
| Output | Text or a `@Generable` struct. The docs describe no image output | Apple docs |
| Context | 32K tokens, reasoning levels light, moderate, deep | Apple doc |
| Offline | Does not work. Apple says to retry with the on-device model | Apple doc |
| Limit | Daily limit per person, number not published. iCloud+ gives more | Apple doc |
| Errors | `networkFailure`, `quotaLimitReached` (with `resetDate`), `serviceUnavailable` | SDK |
| Availability | `deviceNotEligible`, `systemNotReady`. The type is `Observable` | SDK |
| Cost | No cloud API cost in the App Store Small Business Program, under 2 million first-time downloads | developer.apple.com/private-cloud-compute |
| Access | A managed PCC entitlement. Apple must grant it | same page |
| OS permission | None. No permission or consent API exists in the framework | SDK search |

Apple's own advice: start with the on-device model (`SystemLanguageModel`). Move to PCC only when the feature needs more reasoning or context. The on-device model also reads images, works offline and has no limit.

Sources:

- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
- [Detecting available Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels/detecting-available-apple-foundation-models)
- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Accessing Private Cloud Compute](https://developer.apple.com/private-cloud-compute/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## Fit with the app

- The Labs section is in Help (`DiagnosticsView`). The subject picker switch already shows the pattern: `@AppStorage`, locked below 27.
- The model can only give labels. Labels may feed `ColorCorrection.make` as named inputs. The model must not choose correction values (docs/ColorAlgorithm.md, own logic).
- The switch would need these checks:
  - OS 27 or later.
  - `availability` is `.available`.
  - `quotaUsage` is below the limit.
  - A network failure falls back to the current analysis.
- Photos only. A video can have up to 120 keyframes, which fits the daily limit badly.
- Preview and export must look the same. So the label is read once per photo and kept.

Costs found:

- The store text says "Fully on-device processing with no account or cloud upload" (docs/AppStoreMetadata.md). The App Review notes say the same. So does the privacy page (underblue-support repo). With the switch on, these are not true.
- App Review Guidelines cover personal data sent to "third-party AI". They ask for disclosure and explicit permission first. The guideline does not say whether Apple's PCC counts. A first-use notice would be the safe path.
- The same photo would look different online, offline, or over the limit.

## Stage 1: label accuracy

Three photos, 1024 px long side. Both models, greedy sampling, two runs each. Photo paths in this file are under `DeveloperMedia/`.

| Photo | Question | Truth (by eye) | PCC | On-device |
|---|---|---|---|---|
| `subjectpicker/DSC03656.JPG` | Water colour | Blue | Blue ✓ | Blue ✓ |
| | Truly white object | Yes (white anemone) | Yes, "sponge" | Yes, "ring" |
| | Main subject | Reef | Coral reef ✓ | "ring" ✗ |
| | Plants or algae | No (soft coral is an animal) | Yes ✗ | Yes ✗ |
| `tune/photo/plants/sargassum_green_water.png` | Water is green | Yes | Yes ✓ | Yes ✓ |
| | Plant colour in air | Golden-brown | Yellow-green ✗ | Green ✗ |
| `licese-free-images/candidates/pexels-carlos-jamaica-173742194-11061223.jpg` | Water is green | Yes (teal) | Teal, yes ✓ | Blue, no ✗ |
| | White object, plants | None | None ✓ | None ✓ |
| All three | Brightest area | Sunlight | 3 of 3 ✓ | 3 of 3 ✓ |

- Each photo and model pair gave the same JSON in both runs (6 of 6).
- First call: 6.6 s (PCC), 9.2 s (on-device). Later calls: about 2 s. These are `fm` wall times on the Mac.
- PCC was the better model here. Only PCC read the teal water as green.

## Stage 2: one rule with a label

The rule: when the label says "truly white object", skip the white reference hue gate. A subject-mask reference already skips it. A "no" label keeps today's behaviour.

The test ran on the colour harness (`scripts/color-eval`) with a patched copy of `UnderBlue/Processing`. Renders are 960 px long side. Mac analysis values are for relative comparison only. The iPhone reads them differently (docs/JpegInput.md, J5).

| Photo | Why chosen | White reference gains, today → rule | Visible change |
|---|---|---|---|
| `eval/aquacolorfix/O4.JPG` (manta) | The gate costs the white belly | (1.051, 0.991, 1.003) → (1.083, 0.984, 1.003) | None |
| `eval/market/raw/m1.png` | The gate dulls its yellow coral | (1, 1, 1) → (1.017, 1.007, 0.889) | Coral a little yellower |
| `subjectpicker/DSC03687.JPG` | The gate exists for this photo | (1, 1, 1) → (1, 1, 1) | None on the Mac |

Measured:

- O4 belly chroma (OKLab, pixels with L above 0.80 in the manta area): 0.0181 → 0.0172. Today's code already makes the belly near white.
- m1 against its target `eval/market/ref/m1.png`: ΔE76 23.90 → 23.39. The b* value moved 6.97 → 10.30. The target has 9.41.
- DSC03687: the same code rendered twice differs by mean 0.31, max 9 (8-bit). The rule differs by mean 0.67, max 13. The reference strength rose from 0 to 0.004.
- The iPhone risk for DSC03687 was not measured. On the phone this photo's analysis differs from the Mac.

PCC labels for these three:

| Photo | Truth | PCC "truly white object" | Effect of the rule |
|---|---|---|---|
| O4 | Yes (belly) | Yes, "manta ray" ✓ | No visible gain |
| m1 | Unclear (pale sand) | No | Rule does not apply |
| DSC03687 | No (water-lit coral) | **Yes, "coral"** ✗ | Brings back the J5 risk |

So the rule gives no gain and adds one risk.

## How to repeat

- `fm` (`/usr/bin/fm`, macOS 27) runs PCC only from Apple's Terminal.app. Warp and the VS Code shell get "not available in this context".
- Run `sudo fm license` once to accept the terms.
- Apple Intelligence must be on. The Mac language and the Siri language must match. With a mismatch, PCC reports only `systemNotReady`.
- Label command:

```sh
fm respond --model pcc --greedy --no-stream --schema schema.json \
  -i 'You label unedited underwater photos for a colour correction app. Describe the scene as it really is. Do not report the water colour cast as the true colour of objects.' \
  --image photo.jpg --text 'Label this underwater photo.'
```

- Schema: `fm schema object --name SceneLabels` with these fields:
  - `waterTint` (string)
  - `waterIsGreenTinted` (boolean)
  - `plantsOrAlgaeVisible` (boolean)
  - `plantsTrueColor` (optional string)
  - `trulyWhiteObjectVisible` (boolean)
  - `whiteObjectName` (optional string)
  - `brightestAreaIs` (string)
  - `mainSubject` (string)
  - `mainSubjectTrueColor` (string)
- Rule patch, in a copy of `FilterEngine+Analysis.swift`: set `sceneTrust` to 1 when `HT_LABEL_WHITE=1`. Then run the harness with `HT_EVAL_SOURCES=<copy>`.

## When to try again

Try again only if a different use shows a gain in a small pilot first. Possible signs:

- A new failure that is clearly about what an object is.
- A newer model that tells water-lit coral from a white surface.

Test the on-device model first, as Apple advises.
