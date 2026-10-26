# Manual subject — research plan

Status: research done (R1-R8) and built (U1-U5), 25 Oct 2026, branch `manual-subject`. Jake still checks it on the iPhone (U6). Nothing here is decided unless a line says "Jake".

## Goal

The user presses and holds on any subject. That subject is picked, with precise edges. The user also sets how strongly the subject lift applies.

- Edges must be precise. Water between fingers and inside a hose loop stays out of the mask.
- The lift strength is a user control. Today it is a fixed recipe.

## Modes (Jake, 25 Oct 2026)

| Mode | What the user does | State |
|---|---|---|
| Auto | Nothing. The app uses every subject it finds. | Built |
| Semi-auto | Taps groups and tier pieces that the app found, to turn them on or off. | Built. The app calls it "Manual" today. |
| Manual | Presses and holds on any subject to pick it. Sets the lift strength. | This plan |

Semi-auto can only pick what Vision found. Manual can pick what Vision missed.

## Decisions (Jake, 25 Oct 2026)

- Press and hold to pick. No hand-drawn outline.
- Precise edges are required: finger gaps, hose gaps.
- The subject lift strength must be adjustable.
- The known limits stay: iOS 27 and macOS 27, Labs switch, a single photo, no video.
- Research first. The build waits for the results below.

## Facts this plan rests on

| Fact | Source |
|---|---|
| The precise model can start from one point (`seedPoint`), not only a box. The app uses that form only to read the model status and to download it. | `SubjectMask.swift:155`, `:175` |
| Groups today start from a box. The box comes from the coarse Vision mask. | `SubjectMask.swift:183`, `:213` |
| The lift recipe is fixed: "nobody tunes them per photo". Strength 0.18, tier two 0.2, tier three 0.1. | `SubjectMask.swift:7-8`, `:17`, `:22`, `:26` |
| The lift has more parts than strength: clarity 0.6, detail 0.6, contrast 0.15, chroma cap 1.3. | `SubjectMask.swift:19`, `:35`, `:43`, `:51` |
| The picker handles a single tap only. It has no press-and-hold. | `SubjectPicker.swift:78` |
| A double tap zooms the preview. | `SubjectPicker.md`, facts table (`ZoomablePreview.swift:73`) |
| The lift runs once, on the blended output. | `SubjectEmphasis.md`, "Where the lift must run" |
| iPhone 17, box seed: 116-214 ms a call after the first. The first call, with the model load, took 11 s. | memory `precise-subject-mask`, 24 Oct 2026 |
| Vision finds nothing in fish schools (O1, r01). Semi-auto cannot pick them. | `SubjectEmphasis.md`, E1 |
| VisionKit subject lifting (the iPhone Photos press-and-hold) keeps small gaps. | memory `precise-subject-mask`, dead ends |

## Dead ends, do not retry

From the 24 Oct mask work: Vision scaled mask, person segmentation, VisionKit subject lifting, water share / depth / guided filter / local water colour as gap cues, closed-form matting with colour seeds. The coarse 512 mask is not used for the lift (E23).

## Questions the research answers

1. Which inputs does the precise model accept? One point, several points, points to exclude, a previous mask?
2. Does one press give the whole subject, or only the part under the finger (a fin, a hose, one diver of two)?
3. Does a point seed keep the finger and hose gaps out, as well as a box seed does?
4. Can a second press fix a wrong mask (add a part, remove a part)?
5. Does a press work on what Vision missed: the O3 bannerfish, a school?
6. What does the strength control scale: only `strength`, or the whole recipe? Which range still looks natural?
7. One strength for all picked subjects, or one per subject?

## Stages

Each stage ends with one artifact that can fail.

| # | Stage | Artifact |
|---|---|---|
| R1 | Read the precise model's inputs from the SDK interface. Answers Q1. | Table of its initializers and properties, with file and line |
| R2 | Mac probe: point seed against box seed, on r15 (hose, hand), DSC03545 (two divers), O3 (bannerfish). Answers Q3. | Spill metric as in E24 (OKLab L x100, 2-40 px outside), and 100% crops for Jake |
| R3 | Press location: 3 to 5 points per subject (body, fin, hose, edge). Answers Q2. | IoU between the masks of one subject, and crops of the worst case |
| R4 | Fix-up: test what R1 allows (more points, exclude points, a previous mask). If none, test union and subtraction of two masks. Answers Q4. | Before and after crops on the worst R3 case |
| R5 | Missed subjects: press on the O3 bannerfish and on O1. Answers Q5. | Mask share and crops |
| R6 | Strength: render r15 and DSC03545 at 0, 0.5x, 1x, 1.5x, 2x, two ways (strength only, whole recipe). Answers Q6. | Crops. Jake picks the way and the range |
| R7 | UI draft: hold against tap, pinch and double tap; feedback while the model runs; where the slider sits; one or many strengths. Answers Q7. | A written draft for Jake. No code |
| R8 | iPhone 17: one press, time and peak memory, on 2 photos. | Table. One call each, no long runs |

R1 comes first: its answer shapes R3 and R4. R8 runs after the method is chosen.

## Rules for this work

- Three test photos (r15, DSC03545, O3), plus O1 for R5. No extra review agents.
- Media stays in `DeveloperMedia/`. Update its `INDEX.md` with any new file.
- Mac first. The iPhone check comes at R8. Run `devicectl install` first.
- Work on a branch, not on `main`. Commit only when Jake asks.
- The base correction always applies. Manual picking changes only what counts as a subject and how strong the lift is.

## Out of scope

Video, hand-drawn outlines, batch, below iOS 27 / macOS 27.

## Results

### R1 result, 25 Oct 2026

Source: Xcode SDK, `Vision.swiftmodule` interface and its doc comments. Line numbers are from `arm64e-apple-ios.swiftinterface`. The macOS interface has the same members (lines 1737-1739 and on).

| Member | What it does | Line |
|---|---|---|
| `init(seedPoint:)` | Starts the mask from one point. The point counts toward the point limit. | 458 |
| `init(seedBox:)` | Starts the mask from a box. The app uses this today. | 459 |
| `init(seedScribbleBuffer:)` | Starts the mask from a scribble image. | 460 |
| `addIncludedPoint(_:)` | Adds a point that must be inside the mask. | 471 |
| `addExcludedPoint(_:)` | Adds a point that must be outside the mask. | 472 |
| `regionOfInterest` | Limits the search area. A seed outside it gives no result. | interface |
| `qualityLevel` | `fast`, `balanced`, `accurate`. Higher is smoother and larger, and slower. | interface |

Doc comment: "Initialize with a seed … to generate the initial segmentation mask. Then add points to iteratively refine the segmentation mask." The limit is 13 points with a point or scribble seed, and 11 with a box seed.

What follows for the plan:

- Q1 answered. A press can be the seed point. Later presses can add or remove parts (R4).
- There is no previous-mask input. A fix-up re-runs the request with all points so far. R4 measures the cost of that re-run.
- The result is one mask per request. Two subjects need two requests.

### R2-R5 result, 25 Oct 2026, Mac

Probe: `scripts/manual-subject/probe.swift`. It calls Vision only, not the app's lift. Quality `accurate`, mask on a 2048 grid as in the app. Box = the app's seed box from the foreground instances. Press points are top-left 0-1 and were picked by eye. Crops: `DeveloperMedia/eval/manual-subject/`.

| Photo | Press | Mask share | IoU with box | ms |
|---|---|---|---|---|
| r15 | box | 0.1144 | 1 | 82 |
| r15 | face 0.483,0.682 | 0.1148 | 0.998 | 81 |
| r15 | hand 0.644,0.761 | 0.1148 | 0.999 | 77 |
| r15 | hose 0.333,0.812 | 0.1141 | 0.998 | 91 |
| r15 | regulator 0.497,0.830 | 0.1143 | 0.996 | 78 |
| r15 | suit 0.578,0.929 | 0.1102 | 0.968 | 77 |
| DSC03545 | box (both divers) | 0.0251 | 1 | 90 |
| DSC03545 | left diver 0.567,0.333 | 0.0118 | 0.462 | 89 |
| DSC03545 | right diver 0.708,0.300 | 0.0135 | 0.521 | 93 |
| DSC03545 | left diver's fin 0.475,0.339 | 0.0120 | 0.465 | 90 |
| DSC03545 | white fish 0.342,0.156 | 0.0021 | 0 | 92 |
| DSC03545 | wreck 0.500,0.833 | 0.4546 | 0 | 93 |
| O3 | box (sunfish) | 0.1753 | 1 | 123 |
| O3 | sunfish body 0.467,0.550 | 0.1754 | 1.000 | 84 |
| O3 | dorsal fin 0.250,0.200 | 0.1754 | 1.000 | 83 |
| O3 | bannerfish on the body 0.328,0.380 | 0.0021 | 0.005 | 79 |
| O3 | bannerfish in water 0.561,0.225 | 0.0048 | 0 | 84 |
| O1 | box | no Vision instance | - | - |
| O1 | one small fish 0.239,0.202 | 0.0012 | - | 88 |
| O1 | reef 0.944,0.652 | 0.1004 | - | 102 |

Press location (R3), IoU between two presses on one subject: r15 face, hand, hose and regulator 0.996-0.999 with each other; suit against the others 0.967-0.970. DSC03545 left diver against its fin 0.990. O3 body against dorsal fin 1.000. Two touching bannerfish (0.561,0.225 and 0.600,0.297) gave one mask, IoU 0.997.

Seen in the mask crops:

- r15, face press: water between the fingers and inside the hose loop is out of the mask. The result matches the box seed. (`r15_face_crop_m.jpg`)
- r15, suit press: the lower hand that holds the yellow hose is missing. That is the 0.968. (`r15_suit_crop_m.jpg`)
- DSC03545: one press picks one diver. The box seed picks both. (`d45_diverL_crop_m.jpg`, `d45_box_crop_m.jpg`)
- DSC03545 wreck press: the wreck with its soft coral, 45% of the frame. The open sand is out. (`d45_wreck.jpg`)
- O3: the bannerfish that Vision misses can be pressed one by one. The masks show a faint glow a few pixels around the fish. Its size was not measured. (`o3_bannerA_crop_m.jpg`)
- O1: one press picks one fish of about 0.1% of the frame. Picking a school this way needs hundreds of presses. The reef press picks the reef. Its left edge fades into the hazy water. (`o1_reef.jpg`)

### R4 result, 25 Oct 2026, Mac: fix-up points

| Photo | Seed, then added points | Mask share | IoU with box | ms |
|---|---|---|---|---|
| r15 | suit, + lower hand 0.444,0.968 | 0.1150 | 0.998 | 16 |
| r15 | face, - black hose 0.333,0.812 | 0.1026 | 0.931 | 13 |
| r15 | face, - waving hand 0.644,0.761 | 0.0857 | 0.743 | 15 |
| DSC03545 | left diver, + right diver 0.708,0.300 | 0.0253 | 0.998 | 43 |
| DSC03545 | white fish, + second white fish 0.308,0.094 | 0.0028 | 0 | 22 |
| O1 | fish, + another fish 0.250,0.484 | 0.0016 | - | 14 |

Seen in the mask crops:

- An included point works cleanly. The lost hand comes back, and the two divers become one mask. (`r15_suitPlusHand_crop_m.jpg`)
- An excluded point removes more than the part under it. Excluding the black hose also dims the lower hand and the regulator. Excluding the waving hand also removes the lower hand and dims the arm. The cut is soft, not a clean edge. (`r15_faceMinusHose_crop_m.jpg`, `r15_faceMinusHand_crop_m.jpg`)
- Calls with added points took 13-43 ms; single-seed calls took 77-123 ms. The cause was not checked.

### What R2-R5 mean for the design

| Question | Answer from the probe |
|---|---|
| Q2: one press gives the whole subject? | Yes, on r15, DSC03545 and O3. One press = one object: one diver, not the pair. A suit press lost a hand once. |
| Q3: gaps stay out with a point seed? | Yes on r15. The point mask matches the box mask (IoU 0.996-0.999). |
| Q4: can a second press fix the mask? | Adding a part: yes, cleanly. Removing a part: it also removes nearby parts. |
| Q5: what Vision misses? | Single fish: yes (O3 bannerfish, DSC03545 white fish). A school: no, one fish per press. |

Open after R2-R5:

- The faint glow around small fish (O3) and the soft reef edge (O1): measure the lift spill there before the lift uses these masks. The E24 metric fits.
- An excluded point is not precise enough to be the main "remove" tool. A plain toggle (press a picked subject to drop it) may be enough. R7 decides.
- These are Mac numbers. The iPhone runs in R8.

### Decisions after R2-R5 (Jake, 25 Oct 2026)

- Two sliders. The existing Intensity stays. A new "subject strength" slider controls the lift on the picked subjects.
- The two are independent. Intensity sets the base correction. Subject strength sets only the lift.
- One subject strength for all picked subjects, not one per subject.
- Fact behind this: Intensity does not scale the lift today. `lifted` takes no intensity (`RestorationEngine.swift:314`). Intensity 0 skips the whole correction, so the lift too (`:278`). Custom has no Intensity slider; it has five sliders.

### Branch and tools

- Worktree `../hydrotone-manual-subject`, branch `manual-subject`, made from `restoration-experiments` at ca75540. Not committed.
- `SubjectMask.precise(_:point:included:context:)`: the press seed, with included points.
- Harness: `HT_EVAL_PRESS="x,y[+x,y...]"` (top left, 0-1) makes the lift mask from a press. `HT_EVAL_MASK_DUMP=<dir>` writes that mask at the render size.

### Trap: added points reuse the previous image

A request with added points (`addIncludedPoint`) uses the image of the request before it, in the whole process. Measured with a test tool, DSC03545, left diver plus an included point on the right diver:

| Request before it | Mask share |
|---|---|
| A box on a 64 x 64 grey image (the model check) | 1.0000 |
| A press on another photo (O3) | 0.7861 |
| The same press without the added point, on DSC03545 | 0.0250 (correct) |

A seed-only request is not affected. The fix: when there are added points, `precise(point:included:)` first runs the seed alone on the same image. With the fix, the harness mask is 0.0228. The R6 DSC03545 renders made before the fix covered 97% of the frame and were thrown away.

### Spill result, 25 Oct 2026, Mac

Lift spill as in E24: the OKLab L change from the lift (x100) in the ring 2-40 px outside the press mask. App lift defaults, tiers two and three off, the photo's own size.

| Photo, press | Mask share | Ring 2-40 px mean | Ring 2-40 px p99 | Ring 2-10 px mean |
|---|---|---|---|---|
| r15, face | 0.1129 | -0.00 | 0.06 | -0.01 |
| O3, bannerfish in water | 0.0031 | -0.01 | 0.04 | -0.01 |
| O1, reef | 0.0961 | -0.00 | 0.22 | -0.01 |

- The faint glow around small fish (R2) does not get the lift. Its mask values are under 0.5, and the lift starts at `maskLow` 0.5.
- The shares differ a little from R2. The harness reads the app's SDR source, not the file.

### R6 result, 25 Oct 2026, Mac: strength

Two ways to scale the lift by a factor k. Tiers two and three are off, so only the subject changes. k = 0 is the image with no lift.

- A, strength only: `strength` = 0.18 k. Contrast, detail and clarity stay at their defaults.
- B, whole recipe: `strength` 0.18 k, `contrast` 0.15 k, `detail` 0.6 k, `clarity` 0.6 k. The chroma cap and the highlight pull stay.

OKLab L change inside the mask (x100), against no lift:

| Photo | Way | x0.5 mean | x1 mean | x1.5 mean | x2 mean | x2 p10 / p90 |
|---|---|---|---|---|---|---|
| r15 (no-lift L 0.213) | A | -4.80 | -1.27 | +3.08 | +8.15 | -2.75 / +16.15 |
| r15 | B | -1.06 | -1.27 | +0.15 | +2.87 | -15.58 / +17.24 |
| DSC03545, both divers (no-lift L 0.220) | A | -5.89 | -2.16 | +2.25 | +7.36 | +0.46 / +12.19 |
| DSC03545 | B | -1.54 | -2.16 | -1.69 | -0.03 | -11.39 / +8.82 |

Spill outside the mask stays at -0.005 or less (ring mean) for every k and both ways.

What the numbers and the sheets show:

- On these dark divers the default lift (x1) makes the subject darker on average, not brighter. Its contrast turns around L 0.5, and the suits sit near L 0.21, so they go down.
- Way A works like a subject brightness control. The mean rises with k. But A at a low k is not "off": contrast and detail stay at full, so x0 to x0.5 is the largest step.
- Way B goes smoothly to "off" at k = 0. It mostly adds punch: the dark parts go darker and the bright parts brighter. The mean barely moves.
- By eye, at 50% scale: at x2 the r15 hand turns grey-green and grainy, more with B. At x2 the DSC03545 suits turn a flat blue-grey with A.
- Sheets: `DeveloperMedia/eval/manual-subject/r6_r15.jpg` and `r6_d45.jpg`. Rows are A and B; columns are x0, x0.5, x1, x1.5, x2.

Low Intensity with the subject lift, DSC03545, way B (mean OKLab L):

| Intensity | Subject strength | Inside the mask | Outside |
|---|---|---|---|
| 0.8 (default) | off | 0.220 | 0.545 |
| 0.8 | x1 | 0.198 | 0.545 |
| 0.3 | off | 0.303 | 0.557 |
| 0.3 | x1 | 0.319 | 0.557 |
| 0.3 | x2 | 0.373 | 0.557 |

- The lift reacts to the base. At Intensity 0.8, x1 darkens the divers. At 0.3 it brightens them.
- By eye at 50% scale, Intensity 0.3 with x2 turns the suits blue-grey and grainy. The divers do not look cut out of the water in this view. Not checked at 100%.
- Sheet: `r6_d45_intensity.jpg`.

### R6b: brighter and sharper, not foreign (Jake, 25 Oct 2026)

Jake's goal for the slider: the subject gets brighter and sharper, but it must not look foreign against the background.

Way C was added for this goal: `strength` 0.25 k, `contrast` 0.15 k around a lower pivot 0.25 (not 0.5), `clarity` 0.6 k, `detail` 0.6 x min(1, k). The low pivot stops the contrast from pushing a dark subject down. The detail stops growing above x1, because the grain at x2 came from it. The harness takes the pivot as an optional 16th value of `HT_EVAL_LIFT`.

Metrics, each against no lift, inside the press mask (`scripts/manual-subject/foreign.py`):

- dL: mean OKLab L change x100. Brighter is positive.
- Local contrast: the mean L spread in 16 x 16 windows inside the mask, as a ratio. Sharper is above 1.
- Grain: the high-pass spread (L minus a 1.5 px blur) in the flattest 30% of those windows, as a ratio. This is noise, not texture.
- Step: mean L 3-12 px inside the edge minus 3-12 px outside. It is negative when the subject is darker than the water around it. Near 0 means the subject is as bright as the water.
- Hue shift: mean change in degrees, only where the chroma is over 0.04. On r15 that is 3% of the mask, so its r15 values are weak.

| Photo | Way | k | dL | Local contrast | Grain | Step (no lift) | Step | Hue shift |
|---|---|---|---|---|---|---|---|---|
| r15 | B (today's recipe) | 1 | -1.27 | 2.14 | 2.65 | -0.277 | -0.374 | 1.4 |
| r15 | C | 0.5 | +2.07 | 1.56 | 1.65 | -0.277 | -0.297 | 0.4 |
| r15 | C | 1 | +5.73 | 2.10 | 2.41 | -0.277 | -0.301 | 0.5 |
| r15 | C | 1.5 | +11.85 | 2.37 | 2.82 | -0.277 | -0.270 | 0.5 |
| r15 | C | 2 | +20.54 | 2.51 | 3.18 | -0.277 | -0.215 | 0.4 |
| DSC03545 | B (today's recipe) | 1 | -2.16 | 1.87 | 2.17 | -0.257 | -0.322 | 1.3 |
| DSC03545 | C | 0.5 | +1.56 | 1.44 | 1.62 | -0.257 | -0.266 | 0.5 |
| DSC03545 | C | 1 | +4.73 | 1.84 | 2.23 | -0.257 | -0.261 | 0.5 |
| DSC03545 | C | 1.5 | +10.64 | 2.00 | 2.59 | -0.257 | -0.224 | 0.5 |
| DSC03545 | C | 2 | +18.99 | 2.00 | 2.90 | -0.257 | -0.166 | 0.6 |
| O3 sunfish | B (today's recipe) | 1 | +1.67 | 1.70 | 1.93 | -0.183 | -0.205 | 9.3 |
| O3 sunfish | C | 0.5 | +3.27 | 1.34 | 1.43 | -0.183 | -0.171 | 2.3 |
| O3 sunfish | C | 1 | +7.52 | 1.62 | 1.81 | -0.183 | -0.146 | 4.2 |
| O3 sunfish | C | 1.5 | +13.00 | 1.68 | 1.86 | -0.183 | -0.102 | 4.4 |
| O3 sunfish | C | 2 | +19.10 | 1.61 | 1.77 | -0.183 | -0.044 | 4.0 |

The table shows B only at x1. The other A and B rows are in the R6 table above (dL only). `foreign.py` prints every column for every row. Highlights over L 0.97 stay at 0.9% of the O3 mask or less in every row.

What the numbers and the sheets show:

- Today's recipe (B at x1) darkens the two dark subjects and more than doubles their grain (2.17-2.65).
- C brightens all three subjects at every k, and it keeps the hue (shift 0.4-4.4 degrees; B at x2 shifts O3 by 15.4).
- C at x0.5 to x1 keeps the step close to the no-lift value. The subject stays darker than the water by about as much as before, so it keeps its place in the scene.
- C at x1.5 to x2 moves the step toward 0. By eye (50% scale) this is where it turns foreign: the sunfish glows a pale cyan and the suits turn a milky blue-grey.
- Grain still grows with C: 1.4-1.7 at x0.5 and 1.8-2.4 at x1. A grain limit is still open.
- Sheets (rows A, B, C; columns x0 to x2): `DeveloperMedia/eval/manual-subject/r6abc_r15.jpg`, `r6abc_d45.jpg`, `r6abc_o3.jpg`.

Decision (Jake, 25 Oct 2026, from the sheets): C is rejected. A and B look alike; B is a little better. So the slider scales today's whole recipe (way B): x1 is today's lift, and 0 is off. The range is not decided yet.

- The metrics favoured C at x0.5 to x1, and Jake's eye did not. The step and hue metrics do not measure what he judges. Do not pick a variant by these metrics alone.

Earlier proposal, now replaced: the slider runs C from x0 (off) to x1. Above x1 the step test fails on the sunfish. A guard can hold the step: stop the lift where the subject's edge band comes within a set distance of the water's brightness. Not built or measured yet.

Jake (25 Oct 2026), on the Intensity table: Intensity 0.8 with subject strength x1 is the cleanest. That is today's default pair. Range (Jake, confirmed under Q-c): 0 to x1.5, default x1.

### R7: UI draft, 25 Oct 2026 (not built; Q-a to Q-d decided)

Facts it rests on:

| Fact | Source |
|---|---|
| The preview pinches and drags to zoom. Double tap zooms, but not while the picker overlay is on. | `ZoomablePreview.swift:69`, `:84` |
| The picker reads single taps only. | `SubjectPicker.swift:78` |
| The iPhone subjects bar is a two-part control: Auto, Manual. Done or Edit, and Reset, sit under it. | `EditorView.swift:165-190` |
| The Mac uses the same `SubjectPicker` view in its preview pane. | `UnderBlueMac/PreviewPane.swift:47` |
| Picks may cover at most half the frame. | `SubjectCandidates.maximumPickedShare` |
| A press anywhere on one object gives the whole object; two presses on two parts give the same mask. | R2, R3 |
| Excluded points also remove nearby parts. | R4 |

Draft:

1. Mode bar: Auto / Semi-auto / Manual. Today's "Manual" becomes "Semi-auto".
2. Manual starts with no picks and the hint "Press and hold a subject to pick it."
3. Press and hold, 0.5 s, on an unpicked spot: a ring shows at the finger while the model runs. The new subject gets the mint outline and a badge, as in Semi-auto.
4. Press and hold on a picked subject: that pick is removed. Excluded points are not used (R4).
5. A part the mask missed: press and hold on that part. Its mask is added to the picks (union). On r15 a press on the hand gave the whole diver (IoU 0.999). So a second press usually completes the mask with no included points. Included points stay for a later version, if union is not enough.
6. A single tap does nothing in Manual, so a tap meant for zoom or scroll picks nothing. Pinch and drag still zoom. The hold allows about 10 pt of finger movement.
7. Subject strength slider: under the subjects bar, in Semi-auto and Manual, shown when at least one subject is picked. 0 to 150%, default 100%. It scales the whole lift recipe (way B). It is separate from Intensity, and it shows with Custom too.
8. Mac: in Manual a click is the press. A click on a picked subject removes it.
9. The picks and the strength belong to one photo. The next photo starts in Auto, as today.
10. Implementation: each press runs `SubjectMask.precise(point:)` once, with no added points, so the added-points trap does not apply. The lift mask is the maximum over the press masks.

Open, for Jake:

- Q-a: decided (Jake, 25 Oct 2026). Today's "Manual" becomes "Semi-auto". The bar has three parts: Auto / Semi-auto / Manual. New strings need English and Spanish.
- Q-b: decided (Jake, 25 Oct 2026, revised the same day). The strength slider shows in Semi-auto and Manual. Auto keeps the fixed lift (x1) and shows no slider.
- Q-c: decided (Jake, 25 Oct 2026). Range 0-150%, default 100%. 0% is no lift; 100% is today's lift, the same as Auto.
- Q-d: decided (Jake, 25 Oct 2026). The strength belongs to one photo. Each new photo starts at 100%. Nothing is saved in app settings.
- VoiceOver: a press and hold is hard to do. A VoiceOver way to pick a subject is not designed yet.

### R8 result, 25 Oct 2026: iPhone 17

Release build from the `manual-subject` worktree, a temporary test (`UnderBlueTests/PressProbeTests.swift`, not committed). Photos in `Documents/press-in` of the app container. The model was already on the device; `preciseModelUsable()` ran first, so no row includes the model load. Peak memory is sampled every 2 ms, so it is approximate. Three rounds per press, in this order.

| Photo | Press | Requests | Time, rounds 1 / 2 / 3 | Peak memory over start | Mask share |
|---|---|---|---|---|---|
| DSC03545, 3648 x 5472 | left diver | 1 | 231 / 158 / 146 ms | +334 / +156 / +85 MB | 0.0105 |
| DSC03545 | left diver, + right diver | 2 (seed, then with the added point) | 165 / 159 / 154 ms | +188 / +116 / +77 MB | 0.0239 |
| r15, 3840 x 2160 | face | 1 | 111 / 116 / 120 ms | +0 / +0 / +6 MB | 0.1119 |
| r15 | hand | 1 | 119 / 103 / 101 ms | +10 / +0 / +0 MB | 0.1119 |

- One press takes about 0.1-0.25 s on the phone. A ring at the finger for that time is enough feedback; no progress bar is needed.
- The fix-up press with two requests did not take twice as long (154-165 ms).
- The added-point mask is right on the phone too (0.0239; Mac probe 0.0253).
- On r15 the hand press gives the same mask as the face press, as on the Mac.
- The log also showed `mdb_txn_commit error: MDB_MAP_FULL`. Its source was not checked.
- The two photos stay in `Documents/press-in` on the phone. The app on the phone is now this worktree's Release build.

Not measured: the first press after the app starts (model load: 11 s in E24 with the download), a 48 MP photo, an ARW.

## Build, 25 Oct 2026 (Jake: "implement, commit, merge")

| # | Stage | Artifact |
|---|---|---|
| U1 | `SubjectChoice.picked` carries `strength`. `SubjectLift.scaled(k)` scales strength, contrast, detail and clarity (way B); 0 is no lift. `PhotoProcessor.pressMask(_:at:)` runs one press. `SubjectSelection` has three modes: auto, semiAuto (the old manual) and manual, with the presses, their union, a press in progress and the strength. | `ManualSubjectTests` (6) and `SubjectCandidatesTests` (25) pass on the iOS simulator |
| U2 | iPhone: the bar is Auto / Semi-auto / Manual. In Manual a 0.5 s press and hold (10 pt of movement allowed) adds the subject, or removes a picked one. A ring shows while the model runs. A single tap does nothing in Manual. Pinch and pan still work: the hold is a simultaneous gesture. | Builds; not seen on a device yet |
| U3 | "Subject strength" slider, 0-150 %, step 5 %, in Semi-auto and Manual once something is picked. Per photo: Reset and a new photo return it to 100 %. | `ManualSubjectTests` |
| U4 | Mac: the same bar; a click is the press; the strength slider sits beside the bar. Debug launch arguments `--ui-demo-subjects manual`, `--ui-demo-press x,y`, `--ui-demo-strength k`. | `BatchEngineTests` (5) pass. The demo run could not read a photo: the sandboxed app cannot read the scratchpad, and its container refused a copy. Not seen on screen |
| U5 | 7 new keys in 6 languages. A reviewer agent changed 3 values (es "Semiauto" for width, zh-Hant 長按 twice). | `git diff --patience --numstat`: 287 added, 0 deleted |
| U6 | Jake checks on the iPhone. | Open |

Choices made while building (not asked):

- Manual draws no tier lines, and every tier piece stays on, as in Auto.
- Semi-auto and Manual share one strength value per photo.
- Strength 0 keeps the picked mask for the local veil and drops only the lift.
- Intensity 0 used to skip the lift too, so the strength slider did nothing there (Jake, iPhone, 25 Oct 2026). Now Intensity 0 leaves the photo untouched but still applies the lift to the picked subjects. This holds in Auto too. Original stays untouched. Test: `testSubjectLiftWorksAtIntensityZero`.
- A press that would push the picks over half the frame is refused with the Semi-auto messages. A press that finds nothing says "No subject found there. Try another spot."

Fixes after Jake's iPhone check, 25 Oct 2026:

- Pan did not work while the picker showed (Semi-auto and Manual). The overlay's gestures took the touch before the preview's `.gesture`. Pinch and pan are now simultaneous gestures. The Manual press and hold moved from the overlay into `ZoomablePreview` (`onHold`): in the overlay's space the image moves with a pan, so a panning finger looked still. Test: `testAHoldInTheFrameMapsToTheImageAtAnyZoom`. Not checked on the device yet.
- The strength slider felt slow (Jake: about 3 s). Measured on the iPhone 17 (`PressProbeTests.testPreviewTimeWithSubjectStrength`), one preview render at 1600 px:

| Photo | No lift | Picked, 0 % | Picked, 100 % | Picked, 120 % |
|---|---|---|---|---|
| DSC03545 (20 MP) | 103-139 ms | 164-184 ms | 235-338 ms | 214-219 ms |
| r15 (8 MP) | 69-94 ms | 87-93 ms | 91-183 ms | 95-99 ms |

  One render is far below 3 s on these photos. Jake then said the delay shows while the slider keeps moving: each step starts a new render, and a render that has started runs to its end. Not measured: the photo Jake used, a zoomed preview (3200 px), 48 MP or HEIC sources.
- A spinner now shows over the preview while a render runs (`PreviewRenderingIndicator`), after 0.3 s, on the iPhone and the Mac (Jake's request).
- Next: make dragging cheaper, for example a smaller preview while the finger is on the slider and the full one on release. Not designed yet.

Whole-photo colour jump at a high subject strength (Jake, squid photo, Intensity 10 %, 26 Oct 2026):

- Seen: around 120-140 % the colour around the squid changed. Measured with the colour harness at the photo's own size: up to 137.5 % only the squid changes. From 140 % every water pixel changes (mean sRGB of the water 62/143/188 to 77/139/157, a warm, murky shift). Same result on a second run.
- Cause: the object colour step (A2, `RestorationEngine.objectColour`, from restoration-experiments) runs after the lift. It measures the near and far mean colours of the finished frame and sets one gain for the whole photo. Its strength is cut to 0 below `objectTintFloor`. The lift moved the near mean, so near 140 % the step switched on for the whole photo.
- Fix: the step now measures the frame before the lift (`objectColour(_:measuredOn:...)`) and applies its gains to the lifted frame. Checked: no lift, 100 % and 135 % are pixel-identical to before; at 140 % and 145 % the water differs from the no-lift image by at most 1 in 8-bit RGB, and the squid brightens smoothly (mean 169.7, 170.5, 171.4).
- Also seen before the fix (25 Oct): at 100 % to 130 % the translucent fins brighten. Their colour comes from the water behind them, so this can read as the water changing. Not changed.
- The device check was not possible on 26 Oct: the iPhone was not connected.
- Tests: `testFullSubjectStrengthLeavesEverythingOutsideTheMask` (whole photo path, strength 100 % and 150 %: pixels outside the subject must not move by more than 0.001) and `testObjectColourStepTakesItsValuesFromTheMeasuredFrame`. The scene came from a sweep of near and water colours with the fix reverted: 40 scenes moved the water. In the chosen one (blue water, a dark subject, Intensity 10 %) the water moved by 0.057 already at 100 %. So the bug could also hit the fixed lift in Auto and Semi-auto. With the fix reverted the test fails; with it, it passes.

Tools in `scripts/manual-subject/`: `probe.swift` (R2-R5, Vision only), and `run.sh`, `specs.sh`, `spill.py`, `foreign.py`, `sheet.py` (R6). The R6 tools expect the harness binary in `bin/` and write to `out/` beside themselves; build it with `build_eval` from `scripts/color-eval/common.sh`.

`UnderBlueTests/PressProbeTests.swift` repeats R8 on a device. It is skipped unless `Documents/press-in` exists in the app container.

