# Subject emphasis — plan

Status: revised 23 Oct 2026. Built on the branch, not in the app yet. Numbers above E15 predate the 1.1.4 merge and are superseded. See "The track on 1.1.4".

The manual subject picker ([SubjectPicker.md](SubjectPicker.md)) is on hold. Stage E2 decides whether it comes back.

## Goal

Make the main subject of a photo bright, vivid and natural. Water stays as it is.

- No colour that the source does not hold. A grey reef stays grey (see [Rejected](ColorAlgorithm.md#rejected)).
- Photos first. Video later, if the photo method works.
- "Water stays as it is" is a measured number, not a judgement. See E3 and E4.

## Why this plan exists

Jake tested the picker on an iPhone on 22 Oct 2026. He saw almost no change after selecting or clearing a subject.

| Fact | Source |
|---|---|
| The subject mask only leaves the subject out of the local veil's broad light. | `RestorationEngine.swift:223` |
| It changes the water beside a subject, not the subject. | same code; test `testSubjectMaskKeepsABrightSubjectFromDarkeningTheWaterBesideIt` |
| Photos have a water-like test per pixel. It decides which pixels are subject for tone, light removal and detail. | `ColorAlgorithm.md`, "Subject light removal" |
| Hue rotation of subjects failed. Warm colour cannot be made on grey reefs. | memory `subject-hue-findings` |
| The product look is our tone with the vivid m5 look. Only awkward parts are removed. | memory `aquacolorfix-gate` |

## What the mask can and cannot do

| Fact | Source |
|---|---|
| `SubjectMask.estimate` returns nil when the mask covers more than 25% of the frame. | `SubjectMask.swift:78`, `:110` |
| That share adds every Vision instance together. | `SubjectMask.swift:95`, `:109` |
| The cap exists because a large mask is a reef or a scene. The m5 reef block was 31%. | `SubjectMask.swift:76` |
| The picker splits instances into groups. A user pick may cover 50%. | `SubjectCandidates.swift:61`, `:121` |

A close-up subject therefore gets no mask at all. A turtle or a shark shot from close by passes 25% easily. Those are the photos that need the lift most.

Raising the cap is not safe. The m5 reef would then count as a subject. The cap does two jobs today. It keeps the veil off subjects. It also rejects whole scenes. The lift needs its own rule.

## Where the lift must run

`RestorationEngine.combined` finishes two images and blends them.

| Step | Code |
|---|---|
| Finishing on the source path | `RestorationEngine.swift:286` |
| Finishing on the restored path | `:288` |
| Blend by depth and confidence | `:303` |
| Violet calm, once, on the blended output | `:299` and `:306` |

Four rules follow from this.

- The lift runs once, on the blended output. A step inside the finishing kernel runs twice, and the blend then dilutes it. Violet calm was wrong per path for the same reason (see [Rejected](ColorAlgorithm.md#rejected)).
- The lift goes after the blend and before the violet calm. Violet calm then removes violet that the lift made.
- The lift needs its own highlight cap. The highlight shoulder runs per path, before the blend (`FilterEngine.swift:268`).
- `combined` returns in two places, `RestorationEngine.swift:299` and `:306`. One private helper, `lifted` (`:305`), serves both.

The mask goes in as a `CIImage` argument. `calmWeight` is the precedent (`FilterEngine.swift:107`). `ColorCorrection.make` holds only the strength. It makes scene-level numbers, not per-pixel weights.

## Ideas from outside (general, not copied)

| Idea | Source |
|---|---|
| Edit the subject through a mask: exposure, contrast and colour inside it only. | [Adobe tutorial](https://www.adobe.com/learn/lightroom-cc/web/underwater-photo-editing) |
| Change luminance only, so hue shifts stay small. | [local tone mapping study](https://infoscience.epfl.ch/record/52170?ln=fr) |
| A brighter pixel looks less saturated. Scale chroma by the cube root of the brightness ratio, with a cap. | [pixls.us thread](https://discuss.pixls.us/t/oklab-cielab-linear-cielab-tonemapping/28767) |
| Work per pixel. Blur-based shadow lift draws dark outlines at edges. | [pixls.us thread](https://discuss.pixls.us/t/what-do-people-use-to-get-the-most-detail-out-of-the-shadows-in-images-with-large-differences-between-highlights-and-shadows/37465/42) |

Neural methods are out. The rule is our own simple logic ([ColorAlgorithm.md](ColorAlgorithm.md)).

## Candidates

All three raise Oklab L inside the mask. They scale chroma to match, cap the gain and keep a soft edge. They differ only in where the mask comes from.

| # | Mask source | Risk |
|---|---|---|
| A | The combined Vision mask, as built today | Chosen. The 0.25 cap is raised for the lift path only |
| B | The largest Vision group | Dropped by the E1 result: it equals A on all five photos |
| C | The user's pick, through the picker | Not needed for coverage after the E2 decision |

The earlier candidate that read the per-pixel water-like test is dropped. That test counts sand as subject (`ColorAlgorithm.md:82`), so the whole sea floor would brighten. A colour test cannot separate sand from a subject. On m5 the sand is 13.6 times redder than the water. The coral is 5.5 times redder (see [Rejected](ColorAlgorithm.md#rejected)).

## Stages

Seven stages. Each one ends with one artefact that can fail.

| # | Stage | Artefact |
|---|---|---|
| E1 | Pick the photos. Measure the subject share of each. | Done: see the E1 result below |
| E2 | Choose the mask source from A, B and C. E1's shares decide it. | Done: see the E2 decision below |
| E3 | Add mask-based metrics to `scripts/color-eval`. | Done: see the E3 result below |
| E4 | Prototype the lift. 4 variants: strength, chroma cap, noise guard. | Done: see the E4 result below |
| E5 | Jake picks one variant by eye. | Done: exponent 3.0 rejected. See E5 below |
| E6 | Move the chosen method into the app, at the blended output. | Tests: the order holds, both return paths apply it, the controls do not change, gate and `m5_eval.sh` run |
| E7 | iPhone and Mac check on the same photos. | Screenshots. A line in `Verification.md` |

### E1 result, 22 Oct 2026

Jake named five photos. Measured on macOS with `SubjectMask.estimate` and `SubjectCandidates.estimate`.

| id | Photo | Vision | Combined share | Auto mask | Picker |
|---|---|---|---|---|---|
| O1 | A cloud of small fish, reef at the right edge | no observation | unmeasured | nil | nil |
| O4 | One manta | 1 instance | 0.143 | mask | 1 group |
| m5 | One coral block on sand | 1 instance | 0.312 | nil, over the 0.25 cap | 1 group, pickable under 0.5 |
| r13 | One shark in deep blue water | 1 instance | 0.014 | mask | 1 group |
| r01 | A school of silver fish | no observation | unmeasured | nil | nil |

Three results follow.

- Candidate B is dropped. Every photo with a subject holds exactly one Vision instance. The largest group is then the combined mask, so B equals A.
- Candidate A covers 2 of the 5. The picker adds m5 and covers 3 of the 5.
- O1 and r01 return no Vision observation at all. The picker sends the same request, so it fails on them too. Both photos are fish schools.

Vision is the limit, not the 0.25 cap. The cap blocks only m5. There the coral block is the subject.

#### The per-pixel test, measured

The pipeline holds a second subject test that needs no Vision. The colour kernel reads `waterLike` per pixel (`FinishingKernels.metal:28`). It drives the subject tone, the light removal, the detail layer and the water calm. The table gives the mean of `1 - waterLike` on the same five photos.

| id | Per-pixel subject share | Pixels with `waterLike` below 0.5 |
|---|---|---|
| O1 | 0.068 | 0.062 |
| O4 | 0.208 | 0.180 |
| m5 | 0.473 | 0.497 |
| r13 | 0.001 | 0.000 |
| r01 | 0.022 | 0.000 |

- This test does not separate the schools either. r01 holds no pixel below 0.5. A silver fish under blue water reads as water.
- The two tests cover different photos. Vision gives the r13 shark 0.014. The colour test gives it 0.001.
- m5 confirms the sand problem. Almost half the frame reads as subject.

So no path in the app today treats a fish school as a subject.

### E2 decision, 22 Oct 2026

Jake took the recommendation.

- The mask source is the combined Vision mask, candidate A.
- Fish schools are out of scope. O1 and r01 get no lift. Nothing in them changes.
- The lift path gets its own share cap. The veil path keeps 0.25.

The lift cap is 0.5 for now. It matches `SubjectCandidates.maximumPickedShare`, where a user pick already gets more room (`SubjectCandidates.swift:61`). The cap lets m5 through, and the m5 coral block is the subject. E4 checks the value.

Candidate C, the picker, is no longer needed for coverage. Whether it ships is a separate question.

Note for E6: run Vision once and keep one mask. The veil path then drops the mask when its share passes 0.25. A second Vision run is not needed.

### E3 result, 22 Oct 2026

`scripts/color-eval` now writes seven subject columns. `SubjectMask.estimate` takes a `cap`, so the harness builds the lift mask at 0.5. A photo with no mask writes `nan`, which the reader prints as `unmeasured`. A zero there would read as measured.

Today's numbers, before any lift. `original` is the source, `combined` is what the app ships now.

| id | subject share | subject L | outside L | subject chroma | subject violet | subject clipped |
|---|---|---|---|---|---|---|
| O1 | unmeasured | unmeasured | unmeasured | unmeasured | unmeasured | unmeasured |
| O4 | 0.143 | 62.9 to 61.1 | 50.7 to 43.5 | 0.106 to 0.043 | 0.000 | 0.006 to 0.001 |
| m5 | 0.312 | 56.0 to 32.2 | 61.4 to 38.2 | 0.092 to 0.028 | 0.000 to 0.000 | 0.000 |
| r13 | 0.014 | 37.1 to 46.9 | 32.6 to 39.7 | 0.289 to 0.128 | 0.000 | 0.579 to 0.000 |
| r01 | unmeasured | unmeasured | unmeasured | unmeasured | unmeasured | unmeasured |

Four readings follow.

- The lift cap works. m5 now holds a mask at 0.312. The veil cap had rejected it.
- The app lowers subject chroma on every masked photo. O4 drops from 0.106 to 0.043. m5 drops from 0.092 to 0.028. r13 drops from 0.289 to 0.128. The lift has to win this back before it adds anything.
- Violet is near zero today. Any violet after the lift is the lift's own.
- r13's source is 84.6% clipped. That is its saturated blue, not a fault. The app leaves it at zero.

### E4 result, 22 Oct 2026

The lift is a kernel, `UnderBlueSubjectLift`. `RestorationEngine.combined` runs it between the depth blend and the violet calm. One private helper does it, so both return points get it. It is off unless the caller passes a `SubjectLift`.

**A gain does not work.** The first form multiplied OKLab L. A bright pixel then passes white by construction. At gain 1.20 it clipped 19.0% of the O4 subject, against 0.08% today. The second form is a gamma: L becomes `pow(L, 1 - strength)`. It cannot pass white, and it moves the dark part of the subject most.

Four gamma variants, measured against today's output.

| photo | variant | subject L | subject chroma | subject clipped | outside L drift |
|---|---|---|---|---|---|
| O4 | today | 61.1 | 0.0432 | 0.0008 | - |
| O4 | strength 0.18 | 67.0 | 0.0444 | 0.0010 | +0.006 |
| m5 | today | 32.2 | 0.0280 | 0.0000 | - |
| m5 | strength 0.18 | 40.4 | 0.0289 | 0.0000 | +0.093 |
| r13 | today | 46.9 | 0.1283 | 0.0000 | - |
| r13 | strength 0.18 | 54.1 | 0.1328 | 0.0000 | +0.000 |

Strength 0.10 and 0.28 move the same way. The noise floor changed nothing here. None of these photos holds a very dark subject.

Four readings follow.

- Brightness works. The subject rises, and the clipping guard holds.
- **Chroma does not.** The cube-root rule gives O4 +2.8%, m5 +3.2% and r13 +3.5%. The pipeline itself takes 59%, 70% and 56% away. So the lift wins back almost none of it.
- The controls hold. O1 and r01 drift by 0.0000 on every variant, because they carry no mask.
- m5's outside L moves by 0.093. That is the soft mask edge. A pixel below weight 0.5 still gets part of the lift. O4 and r13 stay near zero.

#### main against the branch

Rendered on both, same six photos. With the lift off, every `combined` output is identical byte for byte. The branch changes nothing until a caller asks for a lift.

### E5, 22 Oct 2026

Jake looked at the main-against-branch pairs at strength 0.18. He said the branch is better on r13 and on m5, and called it softer. O4 and r15 looked much the same to him, so the eye control holds.

**The chroma exponent is now a parameter.** The cube root was a constant in the first draft. Chroma follows `(Lnew / L)` raised to `chromaExponent`.

| exponent | O4 chroma | m5 chroma | r13 chroma | O4 clipped | m5 clipped | r13 clipped |
|---|---|---|---|---|---|---|
| today, no lift | 0.0432 | 0.0280 | 0.1283 | 0.0008 | 0.0000 | 0.0000 |
| 0.333 | 0.0444 | 0.0289 | 0.1328 | 0.0010 | 0.0000 | 0.0000 |
| 1.5 | 0.0490 | 0.0325 | 0.1508 | 0.0010 | 0.0000 | 0.0031 |
| 3.0 | 0.0554 | 0.0374 | 0.1774 | 0.0010 | 0.0000 | 0.0224 |
| 3.5 | 0.0576 | 0.0393 | 0.1869 | 0.0011 | 0.0000 | 0.0995 |
| 4.0 | 0.0600 | 0.0411 | 0.1973 | 0.0011 | 0.0000 | 0.2396 |
| 4.5 | 0.0624 | 0.0430 | 0.2077 | 0.0012 | 0.0001 | 0.3900 |

Four readings follow.

- The knee sits just after 3.0. On r13 the subject clipping goes 0.0224, then 0.0995, then 0.3900. So 3.0 is the last safe value.
- At 3.0 the subject chroma rises 28% on O4. It rises 34% on m5 and 38% on r13.
- Against the source chroma, the subject goes from 41% to 52% on O4. m5 goes from 31% to 41%. r13 goes from 44% to 61%.
- Violet stays at or below 0.0005 at every exponent.

The water holds. Outside the mask the chroma moves by 0.3% at most. The outside L does not move. The hard controls O1 and r01 drift by 0.0000.

**The numbers passed and the picture failed.** Jake looked at the subjects cropped out of the frame. On r13 at exponent 3.0 the shark's back turns blue. The grey shark takes the water's colour.

The chroma the exponent adds is not the subject's own. It is the water cast the earlier steps left behind. Raising the exponent raises that cast with everything else.

- This breaks the first rule in Goal. A grey subject must stay grey.
- O4 and m5 show no visible change, and that is the same cause. Their subjects are near-grey, so there is no colour of their own to raise.
- The guards did not see it. They measure how much chroma there is and whether it reads violet. They do not ask whose colour it is.

So exponent 3.0 is rejected. A plain exponent cannot work. It cannot tell a subject's colour from the cast on it.

The next step is a chroma rule that fades in with the pixel's own chroma. A near-grey pixel keeps the cube root. A pixel that already holds colour gets more. The pipeline already works this way elsewhere: greyer pixels keep their hue (`ColorAlgorithm.md:98`).

A new guard comes with it. Measure the share of subject pixels whose hue sits near the water's hue. If the lift raises that share, it is raising the cast.

### E5b, subject contrast, 22 Oct 2026

Jake asked about contrast, saturation and colour temperature.

- Colour temperature is a rejected path. Warmth, subject hue rotation and source-redness warmth all failed before. See [Rejected](ColorAlgorithm.md#rejected) and memory `subject-hue-findings`.
- Saturation is the chroma rule above. It is rejected in its plain form.
- Contrast was untested. It moves luminance only, so it cannot raise the water cast.

The kernel now takes a contrast and a pivot. The curve is per pixel, around a fixed L. It keeps no per-frame statistic and draws no halo.

| photo | contrast | subject L | subject chroma | subject clipped | local contrast |
|---|---|---|---|---|---|
| O4 | today, no lift | 61.1 | 0.0432 | 0.0008 | 4.363 |
| O4 | 0 | 67.0 | 0.0444 | 0.0010 | 4.340 |
| O4 | 0.15 | 70.7 | 0.0450 | 0.0036 | 4.469 |
| O4 | 0.30 | 74.3 | 0.0455 | 0.1275 | 4.591 |
| m5 | today, no lift | 32.2 | 0.0280 | 0.0000 | 8.760 |
| m5 | 0 | 40.4 | 0.0289 | 0.0000 | 9.130 |
| m5 | 0.15 | 40.2 | 0.0287 | 0.0000 | 9.611 |
| m5 | 0.30 | 39.9 | 0.0281 | 0.0100 | 10.094 |
| r13 | today, no lift | 46.9 | 0.1283 | 0.0000 | 0.323 |
| r13 | 0 | 54.1 | 0.1328 | 0.0000 | 0.361 |
| r13 | 0.15 | 55.8 | 0.1339 | 0.0000 | 0.384 |
| r13 | 0.30 | 57.7 | 0.1350 | 0.0014 | 0.408 |

Local contrast is the whole-frame number, the same one `m5_eval.sh` reports.

Four readings follow.

- Contrast 0.15 is safe on all three. At 0.30 the O4 subject clipping jumps to 0.1275.
- m5 gains the most. Its local contrast goes 8.760 today, 9.130 with the lift, then 9.611 at contrast 0.15. The target in `ColorAlgorithm.md` is 9.79.
- Chroma barely moves, and the outside chroma does not move at all. Contrast touches luminance only, as expected.
- m5's subject L stays near 40. The curve turns around a fixed pivot, so it does not brighten on its own.

### Video, planned for 23 Oct 2026

Nothing in video has changed yet. This is the plan Jake asked for.

What the code does today.

| Fact | Source |
|---|---|
| Only the photo path builds a subject mask. | `PhotoProcessor.swift:173`, `:200` |
| The video frame entry forwards to the same `combined`, with no lift. | `VideoRestorationAnalysis.swift:368` |
| The video dark-lift runs only while the mask is nil. | `RestorationEngine.swift:210` |
| Today's video output is unchanged. | `uniform`, `current` and `restoration` renders are identical byte for byte against main, on all six photos |

Checks for tomorrow, analysis side.

- Decide whether video gets the lift at all. The plan says photos first.
- If it does, say where the mask comes from. Vision runs once per photo today. Per frame is a cost nobody has measured. Per scene may drift inside a scene.
- Check the dark-lift clash. The video dark-lift turns itself off as soon as a mask exists. So giving video a mask changes the look that ships now.
- Check the scene mix. `ColorCorrection.mixedScalars` lists every value that must blend at a scene change. A `SubjectLift` is not a `ColorCorrection`, so it is not in that list. A lift that differs between scenes would jump at the cut.

Checks for tomorrow, export side.

- Measure one more kernel pass per frame. Memory `video-export-speed-4k` says 4K export is bound by memory, not maths.
- Measure the preview budget again. Memory `preview-stutter-budget` sets the preview scale from 30 M pixels per second.
- Run a real export on the device, not the simulator.

### E5c, the other knobs, 22 Oct 2026

Jake asked which other adjustments could help. Each one, against what the code and the measurements already say.

| Knob | Verdict | Why |
|---|---|---|
| Exposure | Done | This is the gamma lift. The multiply form was measured and rejected: it clipped 19% of the O4 subject. |
| Luminance | Done | Same as above. |
| Saturation | Rejected | This is the chroma exponent. It raised the water cast, not the subject's colour. |
| Vibrance | Rejected | Lightroom vibrance raises the least saturated pixels most. Those are the near-grey subjects carrying the cast, so it makes today's failure worse. |
| Tint | Rejected | The hue family failed three times: warmth, subject hue rotation, and redness-based warmth. |
| Black point | Partly covered | The contrast curve already darkens below its pivot. A global black point was rejected: shadows fell 8 to 10 L* under AquaColorFix. |
| Contrast | Adopted at 0.15 | See E5b. |
| Sharpness | Adopted at 0.6 | See below. |
| Highlights | Open, untried | `ColorAlgorithm.md:200` says our highlights sit 5 to 10 L* above the market look. Nobody has tried pulling them inside a mask. |
| Clarity | Open, untried | `clarity` and `definition` were both scaled to 0.6 on 28 Sep 2026 (`ColorAlgorithm.md:223`). That is measured headroom, the same shape as the detail cut below. |

**Sharpness inside the mask.** The global detail band was narrowed on 20 Oct 2026 to stop halos everywhere. It cost m5 local contrast: 9.09 to 8.76, against a target of 9.79 (`ColorAlgorithm.md:578`). The mask says where a subject is, so inside it the band can be wider.

| photo | detail | subject local contrast | subject overshoot | subject clipped |
|---|---|---|---|---|
| O4 | today, no lift | 6.293 | 25.00 | 0.0008 |
| O4 | 0, lift and contrast only | 6.452 | 25.13 | 0.0034 |
| O4 | 0.6 | 7.051 | 28.80 | 0.0106 |
| O4 | 1.2 | 7.689 | 32.50 | 0.0278 |
| m5 | today, no lift | 17.018 | 65.93 | 0.0000 |
| m5 | 0, lift and contrast only | 19.520 | 73.83 | 0.0000 |
| m5 | 0.6 | 21.844 | 80.20 | 0.0062 |
| m5 | 1.2 | 24.403 | 86.07 | 0.0187 |
| r13 | today, no lift | 5.845 | 23.82 | 0.0000 |
| r13 | 0, lift and contrast only | 7.158 | 28.21 | 0.0000 |
| r13 | 0.6 | 7.968 | 32.02 | 0.0019 |
| r13 | 1.2 | 8.871 | 36.72 | 0.0224 |

Both columns are new and subject-only. Overshoot is how far a 16-pixel window's brightest and darkest pixels sit from its mean. It is this harness's own number, not the high-pass figures in `ColorAlgorithm.md`.

Four readings follow.

- 0.6 is the level to keep. The m5 coral separates and no halo shows at 100%.
- 1.2 is too much. The coral turns gritty and the white highlights blow out. That is the complaint from 28 Sep 2026, where contrast meant sharp boundaries.
- A number alone could not call this. Overshoot rises smoothly through both, so the picture decided it.
- The outside chroma stays at 0.0% at every level. Sharpening moves luminance only.

The recipe now stands at strength 0.18, chroma exponent 0.333, contrast 0.15 and detail 0.6.

### E5d, clarity and highlights, 22 Oct 2026

Two more knobs went into the lift. Clarity is the same high-pass at a wider radius, so it shapes the big forms. The highlight pull compresses the subject's range above a knee.

Each one alone, on top of the base recipe with detail 0.6.

| photo | variant | subject local contrast | subject clipped | subject L |
|---|---|---|---|---|
| O4 | today, no lift | 6.293 | 0.0008 | 61.1 |
| O4 | base, detail 0.6 | 7.051 | 0.0106 | 70.6 |
| O4 | clarity 0.6 | 8.587 | 0.0635 | 70.4 |
| O4 | highlights 0.5 | 5.982 | 0.0006 | 70.6 |
| m5 | today, no lift | 17.018 | 0.0000 | 32.2 |
| m5 | base, detail 0.6 | 21.844 | 0.0062 | 37.0 |
| m5 | clarity 0.6 | 26.881 | 0.0354 | 33.4 |
| m5 | highlights 0.5 | 21.023 | 0.0000 | 37.0 |
| r13 | today, no lift | 5.845 | 0.0000 | 46.9 |
| r13 | base, detail 0.6 | 7.968 | 0.0019 | 55.7 |
| r13 | clarity 0.6 | 10.072 | 0.0737 | 55.7 |
| r13 | highlights 0.5 | 7.650 | 0.0012 | 55.7 |

Clarity buys local contrast and pays in clipping. The highlight pull does the reverse. So they pair.

| photo | clarity 0.6 + highlights 0.25 | clarity 0.6 + highlights 0.4 |
|---|---|---|
| O4 | 7.925, clipped 0.0079 | 7.517, clipped 0.0028 |
| m5 | 26.015, clipped 0.0041 | 25.469, clipped 0.0007 |
| r13 | 9.740, clipped 0.0253 | 9.506, clipped 0.0088 |

Four readings follow.

- Clarity 0.6 with highlights 0.4 beats detail alone on both axes. On m5 it reaches 25.5 against 21.8, and it clips less.
- The picture agrees. The m5 coral mounds read as forms, not only texture. The O4 manta keeps its white.
- Clarity darkens the subject. m5 goes from 37.0 to 33.4 L*. The wide high-pass runs negative inside a large dark shape.
- The outside chroma stays at 0.0%. Every knob here moves luminance only.

The recipe now stands at six values. Strength 0.18, chroma exponent 0.333, contrast 0.15. Detail 0.6, clarity 0.6, highlights 0.4.

Open: whether to raise the strength. Clarity takes 3.6 L* off m5. Jake judges it.

### E5e, original resolution, 22 Oct 2026

Jake asked for the five test photos at their own resolution, main against the branch. Every run above used the harness default of 640 on the long side.

**The recipe behaves differently at full size.**

| photo | subject L at 640 | subject L at full size | subject clipped at 640 | subject clipped at full size |
|---|---|---|---|---|
| O4 | 70.4 | 70.5 | 0.0028 | 0.0065 |
| m5 | 33.4 | 28.5 | 0.0007 | 0.0027 |
| r13 | 55.7 | 55.4 | 0.0088 | 0.0170 |

Four readings follow.

- m5 lands 4.9 L* darker at full size. The clipping roughly doubles on all three.
- The cause is the sharpening, not the mask. The blur radii scale with the short side. But a native photo holds fine texture that a 640 copy has averaged away. So the same relative radius picks up more.
- The mask itself is steady. The shares read 0.1434, 0.3120 and 0.0136 at both sizes. Vision always scales its input to 1024.
- With the lift off, main and the branch stay identical byte for byte. That holds at full size, on all six photos.

**Rule from this.** Tune at the photo's own resolution. The app renders at full size. A recipe judged at 640 then ships stronger than the one judged. Set `HT_EVAL_MAXDIM=4000`.

The six values above are now provisional again. They were chosen at 640.

### E5f, the halo at the outline, 22 Oct 2026

Jake saw a weak halo around the subject at full size. Measured on O4. The number is the mean absolute change against main, by distance from the outline.

| Band | Change |
|---|---|
| water, 4 to 10 px out | 0.00236 |
| water, 0 to 4 px out | 0.01549 |
| subject, 0 to 4 px in | 0.05928 |
| subject, 4 to 10 px in | 0.06805 |
| subject, 10 to 20 px in | 0.06159 |
| subject, more than 20 px in | 0.07248 |

Three readings follow.

- There is no overshoot ring. The change is largest deep inside the subject and falls toward the outline. An unsharp halo would peak at the edge.
- What shows is the water. Within 4 px of the outline the water changes by 0.0155. Water further out changes by 0.0024. The lift reaches into the water by a few pixels.
- The cause is the mask edge, not the sharpening. Vision builds the mask at 1024 on the long side. Stretching it to 2048 or 3840 spreads the edge over several pixels. The lift follows that soft ramp into the water.

**A fix was tried and reverted.** The blurs were rebuilt from subject-only content, the mirror of the veil's subject-free light. It cut the change just inside the outline by about 20%, from 0.0593 to 0.0469. But the divide by a near-zero weight raised the water band from 0.0155 to 0.0207. The water side is the one that reads as a halo. So the change made the complaint worse. The revert is exact: all three bands returned to their first values.

**The next thing to try.** Stop the lift from touching water at all. Shrink the lift mask by a few pixels, or harden its edge. The weight must be zero outside the outline. Nobody has measured this yet.

### E6, the mask edge, 23 Oct 2026

The halo came from the mask edge, not the sharpening. The lift now reads the mask through a ramp. Its weight is then zero in the water. `maskLow` and `maskHigh` set the ramp.

Measured on O4, mean absolute change against main, by distance from the outline.

| Band | raw mask | 0.5 to 0.8 | 0.6 to 0.9 | 0.75 to 0.95 |
|---|---|---|---|---|
| water, 4 to 10 px out | 0.00236 | 0.00162 | 0.00142 | 0.00129 |
| water, 0 to 4 px out | 0.01549 | 0.00359 | 0.00312 | 0.00281 |
| subject, 0 to 4 px in | 0.05928 | 0.05698 | 0.04317 | 0.02609 |
| subject, 4 to 10 px in | 0.06805 | 0.06882 | 0.06881 | 0.06831 |
| subject, more than 20 px in | 0.07248 | 0.07248 | 0.07248 | 0.07248 |

Three readings follow.

- 0.5 to 0.8 cuts the water band by 77%, from 0.0155 to 0.0036. The subject keeps its change.
- Pushing further costs the subject edge. At 0.75 to 0.95 the first 4 px inside drop to 0.0261.
- So 0.5 to 0.8 is the setting. It is the default in `SubjectLift`.

### E7, is the right subject chosen, 23 Oct 2026

Jake doubted the selection itself and added four photos in `DeveloperMedia/subjectpicker/`.

| Photo | What fills the frame | What Vision returns | Share |
|---|---|---|---|
| DSC03545 | A wreck across the left half, two divers | The divers only | 0.025 |
| DSC03546 | A wreck, two divers | The wreck and the divers, as one | 0.166 |
| DSC03656 | A soft-coral reef, one white anemone | The anemone only | 0.014 |
| DSC03696 | A reef, a diver, an orange anemone | The diver and the anemone | 0.107 |

Jake's reading: the anemone is a subject, and the whole reef is a second one. The same holds for the DSC03545 wreck and the DSC03696 reef.

So Vision is not wrong. It returns object-like things and stops there. The reef or the wreck is a subject too. It only appears when it sits clear of the frame edge, as in DSC03546.

**A second tier already exists in the pipeline.** The colour kernel's per-pixel `waterLike` separates open water from everything else, with no Vision. Its complement was rendered on the three photos.

| Photo | Mean of 1 - waterLike | What it covers |
|---|---|---|
| DSC03656 | 0.533 | The reef, cleanly. The water above stays out. |
| DSC03545 | 0.288 | The wreck, cleanly. |
| DSC03696 | 0.494 | The reef along the bottom. |

Three readings follow.

- The complement of `waterLike` gives the second subject on all three photos.
- It is a layer, not an object. It has no instances, so the picker cannot offer it as something to tap.
- It was rejected earlier as the only mask, and that still holds. On m5 it reads 0.473 and takes in the sand. As a weaker second tier its errors cost less.

The shape that follows has two tiers. Tier one is the Vision mask at full strength. Tier two is the non-water weight, weaker. Neither is built yet.

Open: what tier two does with sand. Also with the sun glare DSC03656 shows at the top.

### E8, tier two, 23 Oct 2026

Tier two is built. The lift's weight becomes `w + tier2 x (1 - w) x (1 - waterShare)`. A Vision subject keeps full strength. Everything that is not open water gets `tier2` of it.

The water share costs nothing extra. `combined` already builds it. `UnderBlueCalmShare` holds the raw per-pixel value, before the calm chain spreads it.

A fifth photo arrived, DSC03687: a plate-coral reef with a diver. Vision returned the diver alone, share 0.022. The non-water weight covered the reef at 0.463. That is five photos out of five with the same split.

| photo | tier2 | mean L | local contrast | clipped, whole frame |
|---|---|---|---|---|
| DSC03545 | today, no lift | 46.6 | 4.553 | 0.0008 |
| DSC03545 | 0 | 46.5 | 4.668 | 0.0009 |
| DSC03545 | 0.5 | 48.3 | 6.433 | 0.0019 |
| DSC03545 | 1.0 | 50.2 | 7.807 | 0.0027 |
| DSC03687 | today, no lift | 48.7 | 8.966 | 0.0012 |
| DSC03687 | 0 | 48.7 | 9.064 | 0.0020 |
| DSC03687 | 0.5 | 49.6 | 11.170 | 0.0874 |
| DSC03687 | 1.0 | 50.6 | 12.339 | 0.1104 |
| DSC03696 | today, no lift | 45.5 | 6.850 | 0.0006 |
| DSC03696 | 0 | 46.0 | 7.230 | 0.0291 |
| DSC03696 | 0.5 | 47.5 | 9.283 | 0.0606 |
| DSC03696 | 1.0 | 48.8 | 10.681 | 0.0730 |

Four readings follow.

- It works on the picture. The reef gains shape and separation, and the water does not move.
- Local contrast rises by about half. DSC03545 goes 4.67 to 6.43 at tier2 0.5.
- **The clipping is the problem.** DSC03687 goes from 0.0020 to 0.0874 at tier2 0.5. The highlight pull of 0.4 does not hold the reef highlights.
- Tier2 1.0 is too strong by eye on DSC03687. The reef turns crunchy.

So tier two is not ready to ship. The next round has to hold the highlights before the strength is chosen.

**Tier three is possible.** The pipeline already builds a per-pixel depth map for photos. Near non-water is the reef in front, far non-water is the background. Splitting tier two by depth would let the near reef lead. The far reef would sit back. Nothing is built, and nothing is measured.

### E9, tier three and ranked highlights, 23 Oct 2026

Jake shared a reference edit. Its masking step makes four separate moves, not one.

| Reference move | Where it lands here |
|---|---|
| Brighten the upper water, for a light gradient | `ColorCorrection.lightGradient` exists, scene-wide. The mask split is still open (memory `light-gradient`). |
| Darken the deep water below | The other half of the same gradient. Not a lens vignette: the label sits on the deep water, not the frame corners. |
| Enhance the background: contrast, keep the deep blue | Tier three. |
| The subject: texture, clarity, contrast, less blue cast | Tier one, plus the subject light removal we already ship. |

**The tiers must not do the same job.** The reference brightens the subject and gives the background contrast alone. So the brightness and the chroma now follow the near weight. Contrast, clarity and sharpening use all three tiers. The background keeps its deep blue.

Tier three splits tier two by depth, at `depthSplit`. Depth 0 is nearest. Each tier carries its own highlight pull. The pulls are weighted by how much of the pixel each tier owns.

| photo | variant | local contrast | clipped, whole frame |
|---|---|---|---|
| DSC03545 | today, no lift | 4.553 | 0.0008 |
| DSC03545 | tier one only | 4.668 | 0.0009 |
| DSC03545 | tier2 0.5 | 6.384 | 0.0017 |
| DSC03545 | plus tier3 0.3 | 6.279 | 0.0015 |
| DSC03545 | plus pulls at 0.85 | 6.221 | 0.0012 |
| DSC03687 | today, no lift | 8.966 | 0.0012 |
| DSC03687 | tier one only | 9.064 | 0.0020 |
| DSC03687 | tier2 0.5 | 11.088 | 0.0787 |
| DSC03687 | plus tier3 0.3 | 10.919 | 0.0733 |
| DSC03687 | plus pulls at 0.85 | 10.818 | 0.0522 |
| DSC03696 | today, no lift | 6.850 | 0.0006 |
| DSC03696 | tier one only | 7.230 | 0.0291 |
| DSC03696 | tier2 0.5 | 9.212 | 0.0514 |
| DSC03696 | plus pulls at 0.85 | 8.833 | 0.0384 |

Four readings follow.

- The ranked pulls work, but not enough. DSC03687 goes 0.0787, then 0.0733, then 0.0522. Today it is 0.0012.
- Local contrast holds while the clipping falls. DSC03687 keeps 10.82 against 8.97 today.
- DSC03696 already clips at 0.0291 with tier one alone. Its orange anemone is bright, so this is not a tier-two fault.
- The likely cause is clarity. On O4 it alone took the subject clipping to 0.0635. Tier two now spreads it over the whole reef.

Open: make clarity tier-aware, the same way the brightness now is.

### E10, the clipping, and what the lift does not do, 23 Oct 2026

**A bug in the kernel.** The tier weights were composed first. Then `wv`, `wNear` and `wTex` were taken from the result. Only after that did the noise and highlight guards reach `w`. So the brightness and the sharpening never saw either guard. The guards now run first and scale every tier by the same factor.

| photo | today | before the fix | after the fix |
|---|---|---|---|
| DSC03545 | 0.0008 | 0.0014 | 0.0009 |
| DSC03656 | 0.0866 | 0.0730 | 0.0714 |
| DSC03687 | 0.0012 | 0.0557 | 0.0422 |
| DSC03696 | 0.0006 | 0.0338 | 0.0328 |

**A guard that did not earn its place.** A second guard on the brightest channel was tried and dropped. It took DSC03687 only to 0.0338, and it made DSC03656 worse, 0.0714 to 0.0905. Cutting the weight also cuts the highlight pull. That pull was recovering DSC03656's blown sun.

**The scale was misread.** The source photos clip far more than anything downstream.

| photo | source | current app | with the lift |
|---|---|---|---|
| DSC03545 | 0.2732 | 0.0008 | 0.0009 |
| DSC03656 | 0.2198 | 0.0866 | 0.0714 |
| DSC03687 | 0.1780 | 0.0012 | 0.0422 |
| DSC03696 | 0.1561 | 0.0006 | 0.0328 |

The camera JPEGs already hold 15% to 27% of their pixels at the ceiling. The pipeline recovers nearly all of it. The lift gives a quarter of that back on the two bright reefs. At 100% on DSC03687 the bright coral and fish still hold their shape. So this is a trade, not a cliff, and the picture decides it.

**The lift does not change colour.** Jake asked whether the reef reads too red. Measured inside the non-water region, as mean OKLab hue.

| photo | source | current app | with the lift | grey-world reference |
|---|---|---|---|---|
| DSC03687 | 108 | 49 | 48 | 72 |
| DSC03656 | 126 | 59 | 58 | 60 |
| DSC03696 | 83 | 49 | 49 | 65 |
| DSC03545, a wreck | 249 | 197 | 196 | 89 |

Three readings follow.

- The lift moves the hue by one degree at most, on all four. The warmth is not its doing.
- The pipeline takes the reef from about 108 to about 49. On DSC03687 it raises the chroma by 68%.
- On two reefs our result sits 16 to 23 degrees warmer than grey-world. On DSC03656 the two agree, 59 against 60.

Grey-world is a crude reference. The wreck row shows its limit: it reads 89 where ours reads 197. So this opens a question about the colour algorithm. It is not a defect proved here.

**Tier one can hold several subjects.** `SubjectCandidates` already splits Vision instances into groups, at most `maximumGroups`, which is 6 (`SubjectCandidates.swift:55`). Each group carries its own mask and share. `mask(picking:)` builds a mask from any set of them (`:121`). Today `SubjectMask.estimate` merges every instance into one mask, so the lift sees one tier one. What is missing is a rank among the groups and a strength per rank.

### E11, the recipe, 23 Oct 2026

Jake looked at the branch beside main and said main reads natural. The hue is the same in both, 49 against 48. The difference is brightness and local contrast. On an orange reef, more contrast reads as more colour. The chroma does not have to move.

**The product is one touch.** So there is no slider for this. The values are the product. Picking them is the work, not something to hand over.

Tier two at 0.5 reads as processed: the reef darkens and the orange runs hot. Tier two at 0.2 keeps the natural read and still separates the corals. Tier three has to stay under tier two. Otherwise the background leads the foreground. At tier two 0.2 it is 0.1.

| photo | local contrast, main | with the lift | clipped, main | with the lift |
|---|---|---|---|---|
| DSC03545 | 4.553 | 5.165 | 0.0008 | 0.0009 |
| DSC03656 | 6.380 | 7.180 | 0.0866 | 0.0818 |
| DSC03687 | 8.966 | 9.641 | 0.0012 | 0.0066 |
| DSC03696 | 6.850 | 7.660 | 0.0006 | 0.0285 |

Three readings follow.

- Local contrast rises 7% to 13%, and the mean L barely moves.
- DSC03656 clips less than main, 0.0818 against 0.0866. Its highlight pull recovers the blown sun.
- DSC03696 reaches 0.0285, and tier one alone was already 0.0291. That is its bright orange anemone, not the reef tiers.

The defaults in `SubjectLift` are now this recipe, with a note that says why. The numbers live in the code, not only here.

| Value | Setting |
|---|---|
| strength | 0.18 |
| contrast | 0.15 |
| detail | 0.6 |
| clarity | 0.6 |
| highlights | 0.4 |
| chromaExponent | 1/3 |
| maskLow, maskHigh | 0.5, 0.8 |
| tier2, tier3 | 0.2, 0.1 |
| depthSplit | 0.4 |
| highlights2, highlights3 | 0.85 |
| textureFalloff | 0.8 |

Still off by default: nothing passes a `SubjectLift` in the app yet. E6 turns it on.

### E12, the red reef is main's, 23 Oct 2026

Jake said the reef reads much redder than main and than Natural Dive. The harness renders Natural Dive already: `FilterSettings.preset` defaults to `.natural`.

Measured inside the non-water region on DSC03687. Red covers OKLab hue 15 to 70 with chroma at or above 0.05. Strong red asks for chroma at or above 0.10.

| version | mean hue | red share | red chroma | strong red |
|---|---|---|---|---|
| source | 108 | 0.055 | 0.0698 | 0.005 |
| main, Natural Dive | 49 | 0.553 | 0.1107 | 0.336 |
| branch, tier2 0.2 | 48 | 0.552 | 0.1111 | 0.335 |
| branch, tier2 0.5 | 48 | 0.551 | 0.1105 | 0.333 |

Three readings follow.

- The lift is not the cause. It moves every one of these by 0.003 or less, at either strength.
- Main turns 5.5% of the reef red into 55.3%. That is a ten-fold rise, and it is the shipped look.
- Strong red goes from 0.005 to 0.336 the same way.

Taking a blue-green cast off a reef has to warm it. The question is how far is right, and nothing here answers that. The work belongs to the cast gains and the subject light removal. It is not the subject lift's.

### E13, the harness is a Mac, the app is a phone, 23 Oct 2026

Jake sent the app's own output for DSC03687. It is main at commit `5096422`, Natural Dive, intensity 80. Its reef is cream and tan with yellow fish. Every harness render of the same photo is orange.

The code is the same. My main worktree sits on `5096422` too. These were checked and ruled out:

| Candidate | Result |
|---|---|
| Preset | The harness defaults to `.natural`, which is Natural Dive. |
| Intensity | `FilterSettings.defaultIntensity` is 0.8, and the harness does not override it. |
| Output colour space | The harness wrote sRGB, the app writes Display P3. `HT_EVAL_P3=1` now matches it. The reef stayed orange. |
| Resolution | Rendered at the photo's own 5472 by 3648. Still orange. |
| Source profile | The JPEG is sRGB IEC61966-2.1, so nothing is being misread. |

What is left is the platform, and the project already knows it.

- "The same Core Image code renders differently on Mac and iOS" (`docs/MacApp.md:22`).
- "Mac and iOS render differently. Every colour change needs one check on each platform" (`docs/MacApp.md:150`).

The harness is a Mac tool. The app Jake looked at is an iPhone.

What this costs, stated exactly.

- Still good: every main-against-branch comparison here. Both sides came from the same Mac harness. So the lift adding almost no red still holds.
- Not good: every absolute colour claim. "The pipeline takes the reef red share from 5.5% to 55.3%" is a Mac number. E12 cannot say what the phone does.
- Unknown: whether the recipe in E11 looks right on a phone. It was chosen by eye on Mac renders.

So the recipe stays provisional until it runs on the device. `MacApp.md:150` already asks for that check on every colour change. This work did not do it.

### E14, the device check, and why the two pictures differed, 23 Oct 2026

The branch went on an iPhone 17. It ran through `PhotoParityTests`, the path this project already uses for device checks.

**The lift is not the cause of the red reef.** Four runs on the device, each measured inside the non-water region of DSC03687.

| run | hue | red share |
|---|---|---|
| Jake's app export | 88 | 0.099 |
| device, lift on | 56 | 0.511 |
| device, tiers two and three off | 56 | 0.511 |
| device, chroma scale off | 56 | 0.511 |
| device, lift not wired at all | 56 | 0.511 |

The control with no lift reads the same as the lift build. Debug and Release read the same too. So nothing in this branch moved it.

**The two pictures came from different files.** Jake's export started from a Sony ARW. Every render here started from the camera JPEG of the same frame. The same device, build and settings, with only the input changed:

| DSC03545, no lift | water hue | water chroma |
|---|---|---|
| from the ARW | 240 | 0.055 |
| from the camera JPEG | 260 | 0.081 |

The JPEG result is deeper, warmer and higher in contrast. A camera JPEG already carries the camera's own tone, sharpening and saturation. The same pipeline then lands further along on it.

Two things follow.

- The red reef was a comparison of a RAW export against a JPEG render. It was not a defect.
- The five photos in `DeveloperMedia/subjectpicker` are camera JPEGs. If people shoot RAW, the recipe has to be judged on RAW as well.

**Mac against iOS, measured.** Same commit, same photo, no lift. The Mac harness reads hue 49 and the device reads 56. The gap `MacApp.md:150` warns about is real, and it is smaller than the RAW-against-JPEG gap.

### The track on 1.1.4, 23 Oct 2026

Main shipped 1.1.4 today. Jake asked for three things on top of it:

- finish the subject work,
- redesign the tiers from optics,
- fix what 1.1.4 left open (`JpegInput.md`, "Next").

The branch merged main at `287743d`. Every number above E15 predates that merge. Those numbers are superseded.

| # | Stage | Artefact | Result |
|---|---|---|---|
| E15 | Make the Vision input the same at every size | Mask share of one photo at four sizes | Done |
| E16 | Trust a white reference on a subject | Unit test, gate, analysis on 31 photos | Done |
| E17 | Split the tiers by the water, not by a depth cut | Transmission maps, metrics, full-size crops | Adopted (Jake, 23 Oct 2026) |
| E18 | Find the cause of the pale ring around fish | Ring chroma with each stage switched off | Cause: the subject light removal. Fix needs Jake |
| E19 | Device check of E15 to E17 | Parity analysis and export on the iPhone | Done: the phone agrees with the Mac |
| E20 | Green cast check on r14 and r15 | Sand colour, gate, m5, 25 video frames | r14 fixed. The iPhone agrees with the Mac |
| E21 | Give Vision the whole image | Mask share of 36 photos at three sizes, device time and memory | r14 gets its mask back. One Vision call, faster |
| E22 | Read the water share from alpha in the lift | notWater on open water, gate on the lift render, 8 photos on Mac and iPhone | Fixed. Changes are small. Jake judges by eye |
| E23 | Why the lift looks foreign at the mask edge | Lift terms switched off, a brightening cap, four mask cues, 100% crops | Jake: no lift beats every variant with the Vision mask |
| E24 | A precise mask from Vision iterative segmentation (iOS 27, macOS 27) | 14 photos, leak check, lift spill, 100% crops, a 4K clip, iPhone probe | Spill outside the subject falls 2 to 90 times. The iPhone matches the Mac. Jake: "surprisingly much better" |
| E25 | One tier map for the outline and the lift | Map overlays, strength sheet on 4 photos, gate on the lift render, iPhone regression export | The lift now skips sand, glow and bubbles. Strengths wait for Jake |
| E27 | The dark band around fish (E18 again, photos only) | Lightness by distance from the fish, every stage switched off, 100% crops, gate, m5, video path diff | Cause: the light detail. A water-only edge guard removes it. Video unchanged. iPhone check open |

### E15, the Vision input, 23 Oct 2026

The mask of one photo came and went with the input size. `SubjectMask.visionInput` scaled with a plain transform. The default sampler then reads only a few source pixels per output pixel. 1.1.4 fixed the same problem in the analysis sample (`JpegInput.md`, J5).

| DSC03545 camera JPEG, input size | plain transform | Lanczos |
|---|---|---|
| 5472 px (the file) | share 0.0250 | 0.0259 |
| 4000 px | no mask | 0.0257 |
| 2000 px | no mask | 0.0258 |
| 1024 px | 0.0254 | 0.0254 |

`visionInput` now uses Lanczos. The harness renders at 4000 px, so before this change it saw no mask on this photo. The app reads the full file, so it did. The two disagreed.

On the AquaColorFix gate, E15 alone changes nothing: 11.33, the same as main. The ARW of DSC03545 still gets no mask at any size.

E21 replaced this Lanczos input. It took r14's mask away.

### E16, a white reference on a subject, 23 Oct 2026

1.1.4 ignores a white reference whose hue sits within 25 degrees of the water. That stops water-lit coral from being greyed. It also drops the white belly of the manta in AquaColorFix pair 4 (23.5 degrees).

Hue cannot tell the two apart. The subject mask can. `FilterEngine.analyze` now takes the photo's mask, the one with the 0.25 cap. Each candidate pixel is split by its mask weight:

- the part on a subject is trusted, whatever its hue;
- the rest goes through the hue gate, as in 1.1.4.

Without a mask the result is exactly 1.1.4. Video has no mask, so video is unchanged. `PhotoProcessor` now builds the mask before the analysis.

Analysis at 1600 px, 31 photos. 15 changed. These are the ones that matter:

| photo | white reference share, 1.1.4 | with E16 | subject chroma, 1.1.4 | with E16 |
|---|---|---|---|---|
| AquaColorFix pair 4 (manta) | 0 | 0.0307 | 0.0524 | 0.0495 |
| m6 (the same manta) | 0 | 0.0307 | 0.0534 | 0.0505 |
| DSC03687 JPEG and ARW | 0 | 0 | unchanged | unchanged |
| m1 | 0 | 0.0003 | 0.0333 | 0.0333 |

- The manta belly gets its reference back, and its tint drops.
- The DSC03687 coral is not on a subject, so its red-reef fix stays.
- m1 does not improve. Its yellow coral is not on a subject either. This rule cannot fix m1.
- 12 more photos moved their share. Their mean L and subject chroma did not move at the printed precision (0.01 and 0.0001).

Gate: mean 11.33 to 11.23, gate pairs 13.58 to 13.41, pair 4 12.49 to 11.98. The other four pairs did not move. m5 did not move, because m5 has no mask under the 0.25 cap.

The harness `uniform` row also improves (pair 4 14.16 to 13.28). That row is not what the app's video does: the harness hands it the photo's analysis, mask included.

Test: `testWhiteReferenceOnASubjectSkipsTheHueGate`. The simulator ran `RestorationTests`, `SubjectCandidatesTests` and `PhotoTests`: 102 tests, 0 failures, 1 skipped.

### E17, the tiers by the water, 23 Oct 2026

Two numbers in the E11 recipe were picked by eye:

- `depthSplit` 0.4, where the reef becomes the background;
- `textureFalloff` 0.8, how fast sharpening fades with depth.

Neither one knows the water. Optics gives the rule. Against a water background, an object's apparent contrast falls as exp(-beta z) (Duntley's law). This holds whatever the object's own brightness. The plan already fits beta on the same normalised depth the restoration uses.

So `UnderBlueContrastTransmission` computes, per pixel, t = luma · exp(-betaDirect · depth). Then:

| Weight | Before (E11) | Now |
|---|---|---|
| tier two | tier2 · not water · (1 - step at depth 0.4) | tier2 · not water · t |
| tier three | tier3 · not water · step at depth 0.4 | tier3 · not water · (1 - t) |
| sharpening and clarity | w · (1 - 0.8 · depth) | w · t |

Why t for sharpening: the restoration divides by t, so a far pixel carries 1/t of a near pixel's noise. Sharpening by t keeps the added noise the same at every depth. `depthSplit` and `textureFalloff` are gone. `HT_EVAL_LIFT` now takes 15 numbers.

A first version used the share of the pixel's light that is not veil. It failed. On DSC03687 and DSC03656 the plan's veil sits below the bright water near the surface and above the dark diver. So that version read open water as object and the diver as veil.

Transmission on the test set, linear:

| photo | t, 10th percentile | median | 90th percentile |
|---|---|---|---|
| Jake's five, JPEG | 0.72 to 0.77 | 0.75 to 0.80 | 0.93 to 0.99 |
| Jake's five, ARW | 0.64 to 0.78 | 0.72 to 0.81 | 0.94 to 0.99 |
| m5 | 0.46 | 0.72 | 0.93 |
| pair 4 (manta) | 0.50 | 0.53 | 0.89 |
| pair 1 | 0.38 | 0.39 | 0.63 |

Jake's five are clear water: green beta is about 0.2, so the far reef keeps about 75% of its contrast. E11's fall to 0.2 at the far end took away much more than the water does. The new rule gives the background reef more sharpening than E11 did. In murky water (pair 1) it gives less.

Measured at 1600 px, E11 against E17, both with the lift:

| photo | local contrast, E11 | E17 | far local contrast, E11 | E17 | clipped, E11 | E17 |
|---|---|---|---|---|---|---|
| DSC03687 JPEG | 10.65 | 10.89 | 3.647 | 3.834 | 0.0054 | 0.0069 |
| DSC03656 JPEG | 7.686 | 7.868 | 1.754 | 1.823 | 0.1432 | 0.1405 |
| DSC03696 JPEG | 8.639 | 8.933 | 2.304 | 2.414 | 0.0236 | 0.0238 |
| m5 | 9.979 | 10.05 | 0.984 | 1.010 | 0.0003 | 0.0003 |
| pair 4 | 3.943 | 3.987 | 0.940 | 0.960 | 0.0004 | 0.0005 |

- Local contrast rises 0.7% to 3.4% over E11 on these photos. r13 falls 2%. The far reef gains most.
- On DSC03687, pixels with L from 0.1 to 0.3 get 0.01 darker than with E11. They are the reef's shadows, under more clarity.
- Clipping on DSC03687 rises from 0.0054 to 0.0069. Main is 0.0031.
- Outside chroma changes by 0.0003 or less, except r13 (+0.0013).

Jake looked at full-size crops of main, E11 and E17 side by side. He saw no clear difference and adopted E17, because the measured contrast is better (23 Oct 2026).

### E18, the pale ring around fish, 23 Oct 2026

`JpegInput.md` asked whether the ring sits on the subject mask's edge. It does not. On DSC03545 the Vision mask holds the two divers only. The two fish with the ring are outside it.

Ring chroma: the water 8 to 40 px from the fish, over the water 100 to 160 px out. Fish mask made by hand from the source. 4000 px render, camera JPEG.

| what is switched off | near over far chroma |
|---|---|
| nothing, source | 0.967 |
| nothing, result | 0.939 |
| subject-free broad light, or the whole mask | 0.939 |
| local veil | 0.942 |
| shadow and highlight filter | 0.940 |
| clarity and definition | 0.939 |
| light detail | 0.939 |
| fine detail layer | 0.939 |
| water calm | 0.941 |
| calm keep | 0.938 |
| violet calm | 0.939 |
| saturation control | 0.939 |

No stage that reads a neighbourhood causes it. The fine detail layer, the second suspect in `JpegInput.md`, changes nothing. The ARW shows the same: 0.989 in the source, 0.959 in the result.

By path: the restoration alone keeps the ratio (0.962). The finishing path alone drops it (0.924).

The cause is per pixel. The source already has a pale glow around each fish. Light scatters off a sunlit fish into the water around it. 87% of the near pixels have a colour that also occurs in the far water. Those come out the same as far water (C 0.1062 against 0.1065). The other 13% are the glow:

| pixels | source L | source C | result L | result C |
|---|---|---|---|---|
| far water | 0.672 | 0.1829 | 0.685 | 0.1065 |
| near, colour also found far | 0.673 | 0.1817 | 0.679 | 0.1062 |
| near, the glow | 0.693 | 0.1450 | 0.695 | 0.0577 |

The glow holds 79% of the water's chroma in the source and 54% in the result. So the finishing path takes more chroma from a pale pixel than from the water, per pixel.

Which step does it is not known. These were switched off in the colour kernel and ruled out:

| switched off | near over far chroma |
|---|---|
| water test, chroma term | 0.936 |
| water test, redness term | 0.936 |
| water test, both (every pixel counts as water) | 0.941 |
| uncast, the surface-light rule | 0.939 | The cast gains alone are ruled out too. Applied by hand to the source, they move the glow's share of the water's chroma only from 0.79 to 0.77, against 0.54 in the result.

**The cause.** 2000 glow pixels and 2000 far-water pixels went through `FinishingMath.color`, the CPU mirror of the colour kernel. One field was set to neutral at a time:

| colour kernel | glow chroma over water chroma |
|---|---|
| source, no kernel | 0.792 |
| full kernel | 0.630 |
| cast gains 1 | 0.652 |
| water tone 1 | 0.641 |
| water saturation 1 | 0.622 |
| neutral gains 1 | 0.630 |
| red rebuild 0 | 0.641 |
| tone curve and mid lift 0 | 0.626 |
| reference 0 | 0.630 |
| **subject tone 1** | **0.999** |

The subject light removal (`subjectTone`) makes the ring. The glow is a pale blue between the water and a subject. The water test gives it some subject weight, so the removal takes the water's colour out of it.

Treating it as water does not help either. With the water test forced to 1 on the GPU (the table above, 0.941), the glow gets the water tone. Its hue moves from 248 to 209 and its chroma stays at 0.051.

A pale, water-lit white belly is the same colour class, and there the removal is wanted. Colour alone cannot tell a glow from a belly. Only position can: the belly sits on the Vision mask, the glow does not. A fix would weaken the removal off the mask for pale pixels at the water's hue. That changes pale sand and pale coral too, so it needs Jake's decision. Not fixed.

### E19, the device check, 23 Oct 2026

iPhone 17, `PhotoParityTests`, Natural Dive at 0.8. White reference share from the analysis:

| photo | iPhone | Mac harness |
|---|---|---|
| AquaColorFix pair 4 (manta) | 0.0317 | 0.0307 |
| DSC03545 ARW | 0.0775 | 0.0779 |
| DSC03545 camera JPEG | 0.00001 | 0.0003 |
| DSC03687 camera JPEG | 0.0000002 | 0.000000001 |

- The manta gets its reference back on the phone too.
- The DSC03687 coral stays out on the phone, so the red-reef fix holds.
- The exports of all four photos were looked at. No halo, no red reef. On the phone the manta belly reads a little whiter than the Mac render.

### E20, the green cast check, 23 Oct 2026

r15 (teal water) is as Jake accepted it on 20 Oct. The lift only brightens the diver: mean L 46.5 to 48.0.

r14 (blue water, sand lit green) kept mint sand. The sand had no white reference: its chroma, 0.133, sat above the water's, and the chroma ceiling dropped it. 1.1.3 renders the same mint, so this is old, not a 1.1.4 regression.

Change: a bright candidate above the water's chroma still counts when its hue is at least 35 degrees from the water's. The chroma ceiling lost its slack in J3 because blue-lit coral got in. That coral sits at the water's hue, so the hue gate now keeps it out.

| r14 sand, 4000 px | L | chroma | hue | mean RGB |
|---|---|---|---|---|
| source | 0.825 | 0.1328 | 185 | 61, 225, 209 |
| 1.1.3 | 0.871 | 0.0745 | 167 | 165, 229, 202 |
| main (1.1.4) | 0.872 | 0.0745 | 167 | 166, 229, 203 |
| E20 | 0.885 | 0.0295 | 156 | 203, 223, 210 |

- r14's white reference share goes from 0 to 0.20.
- 3 more photos of 31 move: DSC03696 ARW, m2, r10. None moved its far hue, and mean L moved by 0.05 or less.
- The AquaColorFix gate and m5 do not move.
- 25 frames from 9 test clips: no frame changes its analysis.
- Test: `testGreenLitSandIsAWhiteReferenceUnderBlueWater`. The simulator ran `RestorationTests`, `PhotoTests`, `PresetTests` and `VideoRestorationTests`: 120 tests, 0 failures, 2 skipped.

#### The iPhone check, 24 Oct 2026

iPhone 17, `PhotoParityTests`, Natural Dive at 0.8. The Mac column is the harness at 4000 px. r14 has no subject mask, so its `combined` render is the app's path.

| r14 | iPhone | Mac harness |
|---|---|---|
| white reference share | 0.2001 | 0.2001 |
| neutral gains | 1.1976, 0.9678, 1.0004 | 1.1981, 0.9677, 1.0004 |
| sand L, chroma, hue | 0.908, 0.0237, 166 | 0.908, 0.0237, 165 |

- Mean OKLab distance x100 between the two exports: 0.31 for the whole frame, 0.26 on the sand.
- The sand here is a different mask from the table above: source pixels with L above 0.75, hue 165 to 205 and chroma above 0.08 (22% of the frame). So its numbers do not match that table.
- By eye the two exports look the same. The sand is near neutral on both.

main (`e244636`) on the same iPhone, same photos:

| r14 | main, iPhone | branch, iPhone |
|---|---|---|
| white reference share | 0 | 0.2001 |
| sand L, chroma, hue | 0.893, 0.0663, 172 | 0.908, 0.0237, 166 |
| sand mean RGB | 175, 235, 215 | 211, 230, 221 |

- Mean OKLab distance x100, main to branch: 1.72 for the whole frame, 4.66 on the sand. Mac to iPhone on the branch was 0.31.
- By eye: main keeps mint sand and a green batfish. The branch makes the sand near white, the fish less green, and the top water a little bluer.
- r15: whole frame 1.12. The branch diver is brighter (the lift). The water looks the same.
- The Mac harness at 4000 px finds a subject mask on r14 with main (share 0.0172) and none with the branch. The cause is not checked. The parity test does not print the mask, so the phone was not checked for it.

### E21, the whole image to Vision, 24 Oct 2026

The E20 device check compared the branch with main. With main, the Mac harness found a subject mask on r14 (share 0.0172). With the branch it found none.

Cause: Vision reads a borderline subject differently when its input is one pixel larger or smaller. E15 scaled the image to 1024 px and rounded the size down.

| Vision input | r14 (3140 x 2354) | DSC03545 camera JPEG (3648 x 5472) |
|---|---|---|
| E15: Lanczos to 1024, size rounded down | none (1024 x 767) | 0.0259 (682 x 1024) |
| Lanczos to 1024, size rounded up | 0.0172 (1024 x 768) | 0.0019 (683 x 1024) |
| main: plain transform, not cropped | 0.0172 | 0.0250 |
| E21: the whole image | 0.0171 | 0.0254 |

No rounding rule keeps both. Three repeated runs gave the same answer, so Vision is not random here.

Change: `SubjectMask.visionInput` gives Vision the whole image, moved to the origin. Vision scales it to its own model size, 512 x 512. The mask comes from `generateMask` at that size, which is the frame stretched to a square. `SubjectMask.grid` resamples it (bilinear) to the old grid: long side 1024, the frame's aspect. No mask is built at the photo's own size. `SubjectCandidates` uses the same input and the same grid.

- The 512 mask stretched back matches the full-size mask from `generateScaledMaskForImage`: mean absolute difference 0.0004 to 0.0082 on 31 photos.
- 36 photos (real, market, AquaColorFix sources, subject photos): the same photos have a mask as with main. Shares move by 0.004 or less.
- At the file size, 4000 px and 2000 px from the harness's `fit`, the shares agree within 0.004. A Lanczos copy that ends in a part pixel still moved DSC03545 (0.0077 at 4000 px). The app and the harness never give Vision such an edge.
- The AquaColorFix gate does not move: 13.41 before and after, every pair the same. m5: no patch moves, and the noise and black shares are the same.
- Simulator: `RestorationTests`, `PhotoTests`, `PresetTests`, `VideoRestorationTests`, `SubjectCandidatesTests`: 134 tests, 0 failures, 2 skipped.

#### Time and memory on the iPhone

iPhone 17, Release build. The first call per photo. Peak memory is sampled every 2 ms, so it is approximate. The 48 MP photo is r14 scaled up, not a camera file.

| photo | size | 32fac32 `SubjectMask.estimate` | E21 | 32fac32 `SubjectCandidates.estimate` | E21 |
|---|---|---|---|---|---|
| r15 | 3840 x 2160 | 26 ms, +67 MB | 28 ms, +0 MB | 42 ms, +63 MB | 29 ms, +26 MB |
| O1 | 3840 x 2160 | 25 ms, no mask | 20 ms, no mask | 26 ms | 18 ms |
| r14 | 3140 x 2354 | 30 ms, no mask | 24 ms, +0 MB | 25 ms, no groups | 32 ms, +9 MB |
| DSC03545 JPEG | 3648 x 5472 | 46 ms, +166 MB | 22 ms, +0 MB | 46 ms, +166 MB | 32 ms, +2 MB |
| DSC03545 ARW | 3648 x 5472 | 327 ms, +304 MB | 186 ms, +314 MB | 228 ms, +319 MB | 107 ms, +106 MB |
| 8682 | 6192 x 4128 | 83 ms, +262 MB | 31 ms, +78 MB | 70 ms, +257 MB | 35 ms, +9 MB |
| r14 at 48 MP | 8064 x 6048 | 113 ms, +255 MB | 45 ms, +90 MB | 124 ms, +248 MB | 39 ms, +8 MB |

The scale pass before Vision is gone, and so is the full-size mask. The ARW's first call is mostly the RAW decode.

#### r14 on the iPhone

| r14, `PhotoParityTests` | main | E20 | E21 |
|---|---|---|---|
| sand L, chroma, hue | 0.893, 0.0663, 172 | 0.908, 0.0237, 166 | 0.902, 0.0236, 166 |

- E20 to E21: mean OKLab distance x100 0.55 for the whole frame. The sand stays near neutral.
- The batfish now has its mask, so the lift reaches it: by eye it is whiter, with more contrast. No pale ring shows on it.
- r15: 0.03 from E20.

### E22, the lift read the wrong channel, 24 Oct 2026

Found by the picker session (code read), then measured here. `UnderBlueSubjectLift` read the water share from red. `UnderBlueCalmShare` puts gamma luminance times the share in red, and the share itself in alpha. So open water did not count as water. The bug was there since the tiers came in (`2ed30a9`, E8).

notWater before the subject term, mean over pixels whose share (alpha) is above 0.9, Mac, 1024 px:

| photo | open water, share of frame | from red (the bug) | from alpha |
|---|---|---|---|
| r14 | 4.5% | 0.589 | 0.041 |
| m5 | 47.7% | 0.342 | 0.005 |
| r15 | 84.3% | 0.335 | 0.004 |
| DSC03696 | 31.0% | 0.420 | 0.006 |

Tiers two and three reached open water at about a third to a half of their weight. Change: the kernel reads `water.a`. The white stand-in (no share image) has alpha 1, so it still turns the tiers off.

The AquaColorFix gate and `m5_eval.sh` score `combined`, `current` and `uniform`. None of them has the lift, so neither can see a lift change. A gate claim for a lift-only change (E8 to E21) is about `combined` only. Here the gate was also scored on the `lift` render with the app's defaults (`HT_EVAL_LIFT`): 13.66 before, 13.74 after. p2 moves most (17.76 to 17.98), and p2 swings with a 1 degree water hue change. p4 goes 12.53 to 12.52.

Before and after, OKLab distance x100:

| photo | Mac 4000 px: mean | Mac: pixels moved > 1 | iPhone export: mean | iPhone: pixels moved > 1 |
|---|---|---|---|---|
| DSC03545 | 0.40 | 5.4% | 0.43 | 7.1% |
| DSC03546 | 0.49 | 3.4% | 0.50 | 4.9% |
| DSC03656 | 0.19 | 1.0% | 0.20 | 1.5% |
| DSC03687 | 0.22 | 1.4% | 0.23 | 2.0% |
| DSC03696 | 0.22 | 1.8% | 0.24 | 2.5% |
| r15 | 0.45 | 0.5% | 0.45 | 0.8% |
| r14 | 0.08 | 0.0% | 0.09 | 0.0% |
| m5 | 0.10 | 0.2% | 0.14 | 0.5% |

- The iPhone builds were made from clean worktrees (`a00c7e5`, and `a00c7e5` plus this change), because the shared tree holds the picker session's uncommitted work.
- Open water changes by about 0.3 to 0.6. The densest 400 px window changes by under 1 on every photo.
- By eye at 100%: small fish and wreck edges next to open water get a little less sharpening and contrast. The water is a little smoother.
- The sunlit surface in DSC03696 does not change. It reads as not-water through alpha too, so the lift reaches it before and after. The picker session saw the same for bubbles and sand.

### E23, why the lift looks foreign, 24 Oct 2026

Jake found the r15 hose and the water between the fingers "very awkward". The Vision mask covers the water inside the hose loop and between the fingers. Inside the mask the lift raised that water.

r15, inside the mask, L change from the lift (OKLab x100, iPhone export against main):

| L before the lift | pixels | L change |
|---|---|---|
| 0.1 to 0.2 (black suit) | 659k | -0.9 |
| 0.2 to 0.5 | 243k | +3.5 to +5.8 |
| 0.5 to 0.8 (water gaps, yellow hose, hand) | 67k | +11.9 to +13.7 |
| outside the mask | | +0.00 |

The water gaps rose by 13.7. Switching off one term at a time (Mac harness, against the same run's `combined`): the gamma lift gives about +6 to +7, clarity about +4.2, contrast about +1.9, detail about +1.7.

Four cues were tried to find the gaps inside the mask. None works on r15:

| cue | gap water | the subject |
|---|---|---|
| water share (alpha) | 1.00 | 0.99 to 1.00 on the whole diver |
| plan depth | 0.11 | hose 0.05; open water 0.99 |
| guided filter on the mask | weight 0.73 to 0.84 | kept |
| colour of the local water outside the mask | weight 0.40 to 0.66 | the yellow hose drops to 0.74 at the stronger setting |

A cap on the brightening (0.08, 0.05, 0.03) was rendered too. Jake judged no lift better than every variant on the r15 hose. On DSC03545 cap 0.03 was the least bad. The cap code was removed.

### E24, a precise mask, 24 Oct 2026

Jake asked for precise masking at the photo's own resolution. It runs for one photo at a time, so it may cost more.

Methods tried on r15. Mean mask weight on the gap water; lower is better:

| method | gap water | notes |
|---|---|---|
| Vision foreground mask (512 model) | 0.98 | the current mask |
| the same, `generateScaledMaskForImage` at full size | 0.95 | Vision only scales its 512 result |
| `VNGeneratePersonSegmentationRequest`, accurate | 0.01 | loses the fingertips and all the gear |
| VisionKit subject lifting (`ImageAnalysisOverlayView`) | 0.92 | clears the loop's big hole, keeps the small gaps |
| closed-form matting, water seeds by colour | 0.20 to 0.40 | loses the hand: its colour is close to the water's |
| closed-form matting, the Vision core as subject seeds | 0.74 to 0.82 | keeps the gaps |

Adopted for the experiment: `GenerateIterativeSegmentationRequest` (Vision, iOS 27 and macOS 27). Apple downloads its model on first use (3.9 s on the Mac), so the app does not grow. `SubjectMask.estimatePrecise` seeds it with the box around the foreground instances, quality `accurate`. The result is full size. It is scaled to a 2048 grid on the GPU, so no full-size array is built. The harness uses it with `HT_EVAL_PRECISE_MASK=1`.

- r15: gap water 0.68, the hand 0.87. The water between the fingers is clear. The top of each finger is a little weak.
- Include points added after the first result (`addIncludedPoint`) take 21 ms more. Points chosen deep inside the mask did not bring the fingertips back. Before a first result they fail ("getBestMask failed with status 14").
- Quality `balanced` and `fast` leave the gaps at 0.80.

14 photos, Mac. Every photo had one Vision instance:

| photo | Vision share | precise share | precise ms |
|---|---|---|---|
| r15 | 0.1187 | 0.1149 | 107 |
| r14 | 0.0171 | 0.0173 | 98 |
| DSC03545 | 0.0254 | 0.0251 | 166 |
| DSC03546 | 0.1669 | 0.0909 | 113 |
| DSC03656 | 0.0142 | 0.0147 | 129 |
| DSC03687 | 0.0221 | 0.0212 | 121 |
| DSC03696 | 0.1073 | 0.1071 | 121 |
| m5 | 0.3118 | 0.3098 | 92 |
| m6 | 0.1428 | 0.1465 | 98 |
| O2 | 0.1476 | 0.1475 | 102 |
| O3 | 0.1808 | 0.1753 | 93 |
| O4 | 0.1434 | 0.1468 | 98 |
| r03 | 0.0806 | 0.0795 | 113 |
| r06 | 0.2201 | 0.2071 | 102 |

The precise time includes the foreground request. DSC03546 drops most: Vision filled the openings of the wreck, and the precise mask clears them. Some wreck parts come out at half weight.

Leak check, 50 rounds of both methods in one process: no growth. DSC03545 stays at 415 to 531 MB, r15 at 281 to 330 MB. The swing is one full-size mask buffer held or freed.

Lift spill: the mean L change from the lift in the ring 2 to 40 px outside the precise subject, x100. Harness, the photo's own size, app lift defaults:

| photo | old mask | precise mask |
|---|---|---|
| r15 | 1.81 | 0.02 |
| r14 | 1.88 | 0.64 |
| DSC03545 | 1.03 | 0.02 |
| DSC03546 | 5.21 | 0.12 |
| DSC03696 | 2.07 | 0.96 |
| O4 | 0.54 | 0.11 |
| m6 | 0.41 | 0.11 |

The lift on the subject itself does not change (median L change the same within 0.1). By eye at 100%: the light blue patches in the r15 hose are gone. The water between the fingers is no longer lifted. One thin bright line stays at one finger gap. The water inside the DSC03546 wreck no longer brightens. The pale rim on the hose edges is there with no lift too, so it is E18, not the lift.

A first try flipped the mask upside down (`render(toBitmap:)` already writes the top row first). Its numbers were thrown away. The table above is from the fixed code, checked by correlation with the probe's mask: 0.997 for r15, 0.973 for DSC03546.

Video, Mac, 4K thresher shark clip (`Tune_22_Oct/13832750`), 120 consecutive frames:

| | Vision | precise |
|---|---|---|
| time per frame, median | 31 ms | 135 ms |
| frames with a mask | 120 | 120 |
| mask overlap with the previous frame (IoU), median / min | 0.972 / 0.940 | 0.958 / 0.913 |

- No growth in memory over the clip: 386 to 388 MB, then 338 MB.
- The precise mask moves a little more from frame to frame. Its fine edges follow the frame.
- At 135 ms a frame, a 10 s clip at 60 fps would take about 81 s more on the Mac. Per frame it is too slow for video.
- Clip A (`VID_20230118_095241_0018`) has no Vision subject in 41 frames sampled one per second.

Jake's verdict on the 100% crops (r15 hose and hand, DSC03546), 24 Oct 2026: the lift with the precise mask is "surprisingly much better".

Jake's decision, 24 Oct 2026: the precise mask is adopted for single-photo editing only, on iOS 27 and macOS 27, as a Labs feature. Video does not get it.

#### The iPhone, 24 Oct 2026

iPhone 17, Release build, a probe test calling `SubjectMask.estimate` and `estimatePrecise` (lift cap) on each photo as the app opens it. Peak memory is sampled every 2 ms, so it is approximate.

| photo | Vision | precise, first call | precise, again |
|---|---|---|---|
| r15 3840 x 2160 | 17 ms, 0.1187 | 121 ms, +84 MB, 0.1117 | 121 ms, +11 MB |
| r14 3140 x 2354 | 16 ms, 0.0171 | 124 ms, +41 MB, 0.0143 | 119 ms, +2 MB |
| DSC03545 JPEG | 31 ms, 0.0255 | 139 ms, +277 MB, 0.0238 | 149 ms, +98 MB |
| DSC03546 | 25 ms, 0.1690 | 201 ms, +183 MB, 0.0708 | 142 ms, +121 MB |
| DSC03696 | 20 ms, 0.1073 | 145 ms, +222 MB, 0.1034 | 138 ms, +272 MB |
| r14 at 48 MP (synthetic) | 27 ms, 0.0172 | 214 ms, +245 MB, 0.0144 | 199 ms, +3 MB |
| DSC03545 ARW | 316 ms, no mask | 11165 ms, no mask | 473 ms, no mask |

- The ARW ran first. Its first call holds the model download and the RAW decode. The probe gives Vision the RAW rendering, not the embedded preview the picker session now uses (`c89b881`), so no mask is expected there.
- iPhone against Mac, the same function on the same photos: correlation 1.000 (three decimals) on all six, and no pixel differs by more than 0.5. The iPhone's share is 3 to 6% higher, in the soft edges.
- Leak loop, 20 rounds on the 48 MP photo: footprint 902 MB, then 847 MB. No growth.
- Video, 10 consecutive 4K frames of the shark clip: precise 116 to 128 ms a frame (324 ms the first), +87 MB peak a call. Vision 14 to 18 ms. Leak loop: 531 MB, then 525 MB.

The E21 ARW numbers predate the picker session's RAW change.

### E25, one tier map for the outline and the lift, 24 Oct 2026

Jake asked the lift session and the picker session to agree on tiers 1 to 3 and their strengths. Agreed:

- Tier 1 is the precise mask (E24): the picked groups, or all of them in Auto.
- Tiers 2 and 3 come from one soft map per photo. The picker's outline is that map cut at 0.5. The lift reads the same map. Before this, the outline had depth and texture tests and the lift had none. So the lift brightened sand, the sunlit surface and bubbles that the outline left out.
- The map: notWater (1 - water share, alpha) ramp 0.4 to 0.6, times "in front" (full at the open water's depth - 0.15, none at - 0.05), times texture (ramp 0.025 to 0.045), times (1 - every Vision group). Tier 2 = that x t, tier 3 = that x (1 - t). The outline's cleaning (small pieces out, holes filled) multiplies it, feathered by a 5 x 5 box. The ramps are soft, so the lift makes no step at an edge (E23).
- It is built once per photo with Natural's correction, so a preset change does not move it. The picker session caches it in PhotoProcessor.
- Below iOS 27 and macOS 27, or with Labs off, there is no lift. The veil mask stays as main has it.

Code (lift session): `SubjectTierMap` (red tier 2, green tier 3) and `SubjectLift.tiers`. `UnderBlueSubjectLift` uses the map when `tier.w` is 1. Without a map it behaves as before. The harness builds the same map with `HT_EVAL_TIER_MAP=1` (a copy of the formula, using `SubjectTiers.channel`, `texture`, `waterDepth` and `cleaned`). `HT_EVAL_TIER_DUMP=<dir>` writes it.

Map checks by eye: m5, the coral block is tier 1; small coral and rubble are tier 2; most of the sand is out; a shadow band at the block's foot is in. DSC03545, the wreck and the front white fish are in; the bubbles are out. r07 (barracuda) has no tier 2 or 3.

Strength sheet: precise mask, the map, the photo's own size. Median L change x100 in the tier 2 area (map red 0.5 or more), against no lift:

| photo | tier 2 / tier 3 = 0 / 0 | 0.1 / 0.1 | 0.2 / 0.1 (now) | 0.3 / 0.1 | 0.2 / 0 | 0.2 / 0.2 |
|---|---|---|---|---|---|---|
| DSC03545 | +0.0 | +0.3 | +0.6 | +0.8 | +0.6 | +0.6 |
| DSC03696 | +0.0 | -0.3 | -0.4 | -0.6 | -0.4 | -0.5 |
| DSC03687 | +0.0 | -0.3 | -0.4 | -0.6 | -0.4 | -0.5 |
| m5 | +0.0 | +0.3 | +0.7 | +1.0 | +0.7 | +0.7 |

- Open water (map below 0.02, outside tier 1) does not move in any variant: median 0.00.
- Tiers 2 and 3 work mostly through contrast, clarity and sharpening, not brightness. By eye, a higher tier 2 makes the reef and wreck texture a little crisper.
- AquaColorFix gate on the lift render (precise mask, 960 px): 13.70 without the map, 13.68 with it. p4 12.45 to 12.41.

The picker session's check of the app path (Mac, Debug, Labs on with Auto against Labs off), mean |difference| on 13 x 13 patches, 8-bit. It used the old tier 1 mask, before it switched tier 1 to the precise mask:

| photo | should not change | should change |
|---|---|---|
| m5 | sand 0.02, water 0.01 | coral (tier 1) 22.9, rubble 6.3 |
| DSC03696 | surface glow 0.03, water 0.04 | reef 5.6 and 4.3 |
| DSC03545 | bubbles 0.05, water 0.01 | wreck 5.8, front fish 1.1 |

A second m5 sand patch near the rubble edge moved 1.45. Nobody has looked at it by eye.

iPhone regression: HEAD (`5c58979`) plus only the lift session's changes, no map. `PhotoParityTests` exports of 8 photos are pixel-identical to the E22 exports (largest difference 0). So the kernel change and E24 do not change the default output.

The Labs path on the iPhone 17, Release build. The shared tree at that time held both sessions' uncommitted work: tier 1 from the precise mask per group, and the tier map. A temporary test called PhotoProcessor on 6 photos:

| photo | preview, Labs off | candidates (Vision + precise) | tier map | first preview, Labs on | again |
|---|---|---|---|---|---|
| DSC03545 ARW | 503 ms | 311 ms | 807 ms | 607 ms | 556 ms |
| DSC03545 JPEG | 66 ms | 215 ms | 99 ms | 92 ms | 61 ms |
| DSC03696 | 75 ms | 219 ms | 127 ms | 81 ms | 74 ms |
| r15 | 59 ms | 144 ms | 86 ms (no map) | 75 ms | 38 ms |
| r07 | 54 ms | 148 ms | 115 ms (no map) | 82 ms | 44 ms |
| m5 | 73 ms | 142 ms | 102 ms | 95 ms | 66 ms |

- So the first Labs-on preview costs about 0.3 to 0.45 s more than Labs off for a JPEG, and about 1.7 s for the ARW. The phone already had the segmentation model from earlier runs, so the first download is not in these numbers.
- The picker session measured 6 to 24 s on the Mac in a Debug build. Most of that is Debug, not the work.
- The test process footprint reached 1200 MB after the 20 MP photos. It holds a new PhotoProcessor and its caches per photo. The app's own peak was not measured.
- The r15 export by eye (hose and hand, 100%): no light blue patches, and the water between the fingers is not lifted, as on the Mac. One thin bright line stays at one finger gap.

r07: Vision groups the middle of the barracuda school, with the water between the fish. The precise mask cuts each fish out, but some come out at half weight. With either mask, some fish in the school get the lift and their neighbours do not. Jake decides whether that is acceptable.

The harness has no RAW preview path, so an ARW gets no Vision mask there. The sheet uses camera JPEGs.

#### A silent fallback, and r07 with the precise mask, 24 Oct 2026

After `SubjectMask.precise` stopped downloading, it returns nil while the model reads `notReady`. That is every new process until the model has run once. The harness had no loader, so `HT_EVAL_PRECISE_MASK=1` fell back to the old Vision mask without a word. Three experiments ran on the old mask: an r07 render, an edge-feather test and a mask-ramp test. Their conclusions are withdrawn. The harness now calls `preciseModelUsable()` once, and prints a warning when a precise mask is nil. Check: r07 uses a 2048 x 1535 grid at share 0.0730 (precise), not 1024 x 767 at 0.1048 (old).

With the precise mask, r07's lifted barracuda looks natural at 100%: a little more definition, and no white band. The 99th percentile L rise in the crop is 6.7, against 12.0 with the old mask. The white band along the fish's back came from the old mask.

How sure the precise mask is, by its values (share of mask pixels above 0.02):

| photo | partial, 0.1 to 0.9 | 0.95 or more |
|---|---|---|
| r07 (soft, moving barracuda) | 75.7% | 1.0% |
| DSC03546 (wreck) | 54.5% | 4.1% |
| DSC03545 (divers) | 24.6% | 58.7% |
| r15 (diver) | 15.3% | 66.6% |

Not acted on: on r07 the lift with this soft mask already looks natural.

#### The model download, 24 Oct 2026

Jake: the first launch, before the model is on the device, may need its own UX.

- The model sits in the system's shared assets, not in the app: `ViSam_v2_5_image_encoder` 49 MB and `ViSam_v2_5_mask_decoder` 5.3 MB on the Mac. Apple's catalog lists several variants (download sizes from 4 MB to 113 MB). Which one an iPhone gets is not known.
- Only `GenerateIterativeSegmentationRequest` uses it. No other Vision request downloads it, and an app cannot load the files itself.
- `assetStatus` reads `notReady` in every new process, even with the files on disk. `downloadAssets()` then returns in 5 to 9 ms and the status turns `ready` (Mac, two runs). So the status cannot tell "never downloaded" from "downloaded". The first real download took 3.9 s on the Mac.
- So `SubjectMask.precise` no longer downloads. It returns nil until the model is ready, and the photo then gets no lift. It never falls back to the old 512 mask. `SubjectMask.downloadPreciseModel(progress:)` and `preciseModelStatus()` are for the UI, which starts the download when Labs is turned on.
- Not tested: a first download on the iPhone, and no network.
- Jake's decision, 24 Oct 2026: a photo cannot be saved until the model is confirmed ready. Proposed scope, not yet confirmed by Jake: only with Labs on, since Labs off needs no model. Proposed way out with no network: the blocked state shows the download progress and offers to save without subject emphasis or to turn Labs off.
- Jake's decision, 24 Oct 2026: if Labs is turned on with no network and no model on the device, the app says a network is needed and keeps the subject features blocked. The base correction still works. When a network comes back, it downloads the model and turns them on.

### E27, the dark band around fish, 24 Oct 2026

Jake: the video halo is already much better, so this is for photos only. Video output must not change.

E18 measured chroma only. A 100% crop of the DSC03545 front fish shows what the eye sees: a darker blue band, 8 to 40 px wide, around the fish. The source has none. Lightness by distance from the fish (OKLab L x100, minus the water 130 to 200 px out; camera JPEG at full size, fish mask made by hand):

| render | 4-8 px | 8-14 | 14-20 | 20-30 | 30-40 | 40-60 |
|---|---|---|---|---|---|---|
| source | +4.02 | +1.65 | +1.06 | +0.62 | +0.29 | +0.43 |
| before (HEAD `c616ee5`) | +2.87 | -1.13 | -1.99 | -1.76 | -0.59 | +0.16 |
| light detail off | +3.79 | +0.93 | +0.51 | +0.06 | -0.17 | +0.24 |
| edge guard 0.04 to 0.08, water only (adopted) | +3.97 | +0.94 | +0.29 | -0.27 | -0.36 | +0.17 |

How the cause was found:
- Clarity, definition, fine detail, shadows, tone, vibrance, saturation, the white reference and the water calm, each switched off by its values: the band stays. All of them together, with the calm off too: it stays.
- The colour kernel's CPU mirror maps the band's source colours to the same lightness as the far water. So the kernel is not the cause.
- Light detail off (a build with `lightDetailAmount` 0): the band is gone.

Why: the light detail is an unsharp mask, 0.018 of the short side (66 px on this photo), gain 1.3, where the broad light is bright. Next to a bright fish the blur takes in the fish. So the water reads darker than its broad light, and the detail makes it darker still. The kernel already skips a strong edge, but not the water around it.

The fix (`FilterEngine.finishing`, photos only): a new kernel `UnderBlueLightEdge` gives the size of the light detail's difference. It is blurred over half the radius. From 0.04 to 0.08 the pixel goes back to its value before the light detail, but only in water (1 - calm.b, the source's own subject test). The light detail kernel itself has no new input.

| guard | DSC03545 band, worst | IMG_7400 light detail kept in the light |
|---|---|---|
| 0.02 to 0.04, all pixels | -0.19 | 31% |
| 0.04 to 0.08, all pixels | -0.35 | 58% |
| 0.06 to 0.12, all pixels | -1.09 | 84% |

On all pixels, the guard also took the detail off dark rock beside bright sand (IMG_7262): the rock went pale and soft. Limited to water, IMG_7262 changes by at most 4 levels of 255, and the IMG_7400 light rays look as before. At 100% the bright rims around the dark fish in the IMG_7400 light stay as before.

Checks on the Mac:
- AquaColorFix gate 13.42 to 13.41. Detail per pair within 0.01.
- m5: full dE 13.22 to 13.21. One panel patch is worse by more than 1 dE: r2c2, the blue chip, 17.57 to 19.40. It is water-coloured between strong edges, so it keeps less of the light detail's darkening.
- O4: 0.29% of pixels change by more than 10 levels, in the manta's fold shadows. Hard to see at 100%.
- Video path (`combined` with `video: true`) on IMG_7262, O4, m5 and IMG_7400: byte-identical to HEAD. Video passes `edgeGuard: false`, also in its no-plan fallbacks.

Not adopted: turning the light removal (`subjectTone`) off on pale water-hue pixels. With it off, the ring's chroma ratio goes 0.863 to 0.898 (source 0.948), but it does not touch the dark band. A colour rule also catches the pale wreck in DSC03545 (10% of the pixels changed), and the fish are not in the Vision mask, so the mask cannot protect or find them.

Open: the iPhone. The new kernel and the blend need a check on the device, because an extra kernel input once broke iOS rendering (see the comment in `FilterEngine.colorStage`).

### The control photos

| Photo | Kind | Rule |
|---|---|---|
| O1, r01 | Hard control | They carry no mask, so every number must stay the same. E4 measured 0.0000 drift. |
| r15 | Eye control | Jake accepted its result on 20 Oct 2026 (memory `teal-diver-accepted`). It holds a diver, so the lift does change it. At strength 0.18 its mean L rises by 0.70. Jake judges it, and no number fails it. |

A hard control that moves fails the stage.

### The metrics E3 adds

The harness measures a near depth band, not the subject. `nearA` and `nearRG` read the nearest 30% of depth values (`scripts/color-eval/main.swift:114`). Subject L, subject chroma and clipping are not measured at all.

| Metric | Why it is needed |
|---|---|
| Subject L, median, inside the mask | It is the lift's own strength |
| Outside-mask L, median | It proves the water did not move |
| Subject chroma, median | A brighter pixel looks less saturated |
| Subject violet share, OKLab hue 282 and above | A brightness lift made violet before. The Tropical offset +0.012 took r05 from 9.9% to 15.6% ([Rejected](ColorAlgorithm.md#rejected)) |
| Clipped pixels, inside the mask | The highlight shoulder runs before the blend, so the lift has none |
| Clipped pixels, whole frame | Context only. A saturated source already clips: r13 reads 0.846 |
| Outside-mask chroma | The lift scales chroma, so the water guard has to watch chroma, not only L |

`toneMetrics` takes the mask as one more argument (`main.swift:105`). `SubjectMask.estimate` takes a `cap`, so the harness can ask for the lift mask at 0.5.

The violet bands are already defined in `scripts/color-eval/README.md`. The existing violet number reads the water. These read the subject.

## Rules for this work

- Algorithm first. No performance runs until the method is chosen (memory `algorithm-before-performance`).
- Five photos, listed in the E1 result. The control set is still open. No extra review agents.
- The lift is a kernel input image plus a strength. No per-frame statistics in the kernel (memory `color-algorithm-design`).
- Run the gate and `m5_eval.sh` on every colour change. When they disagree, m5 wins (memory `aquacolorfix-gate`).
- The simulator is for layout only, not colour.
- Work on a branch. Commit only when Jake asks.

## Open items

- How much brighter is "natural". E5 sets it by eye. The metrics are guards, not targets.
- How to raise a subject's own chroma without raising the water cast on it. E5 rejected the plain exponent.
- Whether the 0.5 lift cap is right. E4 checks it on m5.
- Which photos are the controls. Jake's five hold none.
- The picker code sits on branch `subject-picker` as commit `2c593b7`, marked WIP and on hold.
