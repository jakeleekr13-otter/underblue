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
| E17 | Split the tiers by the water, not by a depth cut | Transmission maps, metrics, full-size crops | Built. Jake judges the look |
| E18 | Find the cause of the pale ring around fish | Ring chroma with each stage switched off | Narrowed to a per-pixel step. Not fixed |
| E19 | Device check of E15 to E17 | Parity export on the iPhone | Not done: the phone was locked |

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

Whether the sharper background reads natural is Jake's call. The full-size crops are main, E11 and E17 side by side.

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
| uncast, the surface-light rule | 0.939 | The cast gains alone are ruled out too. Applied by hand to the source, they move the glow's share of the water's chroma only from 0.79 to 0.77, against 0.54 in the result. Next to test, one at a time: the water tone and water saturation, the tone curve, vibrance. Not fixed.

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
