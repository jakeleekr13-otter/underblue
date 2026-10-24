# Restoration experiments — plan

Status: plan, 24 Oct 2026. Nothing is built yet.

This page plans three experiments. The ideas come from three public guides by the Five Meters photo editor (see [Sources](#sources)). We take general ideas only. We do not copy code, models or coefficients.

## Goal

| ID | Question | Why it matters |
|---|---|---|
| C | Do we measure the failures a diver sees first? | Without it, A and B cannot be judged. |
| A | Can a cross-channel red estimate give better subject colour than `redRebuild`? | Some subjects stay olive or grey (m6 reef). |
| B | Can one water matte from transmission replace several colour-based water tests? | Halos and rings form where these tests disagree. |

Order: C, then A1, then B, then A2. Each stage has a go/no-go rule.

## Decisions that limit this plan

- Green water is corrected toward cyan or blue (Jake, 24 Oct 2026). Five Meters keeps green water green. We do not.
- Plants are not water. A check in C still guards seagrass and weed from turning grey or yellow.
- Our own logic only. A matrix fitted to a reference image is a diagnostic. It never ships.
- Few images per check: best, middle and worst. Full verification runs once, at the end.
- No long performance runs while the algorithm changes. Each stage states its cost on iPhone.
- Video rules: no per-frame statistics in the kernel. A local, per-pixel map is allowed, like `liftDark`.
- The subject lift on `subject-picker` is still under experiment (Jake, 24 Oct 2026). So the baseline is the `combined` render without the lift. Check the lift's effect on a result as a separate step.

## Optics and estimates

Only one part of the pipeline is optics: the restoration kernel. It inverts `observed = clear x exp(-beta z) + B_inf x (1 - exp(-beta z))` per channel. It is the same on `main` and `subject-picker`.

- Attenuation acts on each channel alone. If no red light reached the sensor, no optical step can bring it back.
- So any red made from green or blue is an estimate, not a restoration. `redRebuild` is one. Stage A is one too.
- In optics, "water" is a pixel with low transmission `t = exp(-betaDirect x depth)`. A colour test is only a guess of that. Stage B uses `t`.

Each stage below says which kind of step it is.

## What Five Meters does (as the guides state it)

| Step | Their method | Our nearest part |
|---|---|---|
| Restoration | A model makes a restored image. A full 3×3 cross-channel transform is derived from it and applied at full resolution. One global matrix cannot follow distance, so this is not range-based optics. | Per-channel gains in `UnderBlueRestoration`, plus `redRebuild` (red from green) in finishing. |
| Haze | Dehaze reads a spatial transmission estimate. | The local veil (`broadSample`, `veilLevel`) and the depth map. |
| Water | Hue, saturation and luminance change only inside a feathered water matte. | Per-pixel colour tests: `waterLike`, `neutralWeight`, `calmWeight`, `waterShare`. |
| Stop signs | Sand or bubbles turn pink. Black gear turns brown. Kelp loses its green. Water turns grey. Silhouettes get hard halos. | Scorecard: pink and violet shares, water hue bands, neutral boxes. |
| Backscatter | A capture problem. No slider fixes it. | The particle filter stays a prototype. This plan does not change that. |

The guides give no measurements. Each claim above is the vendor's own statement.

## Stage C — new scorecard checks

The harness checks neutral surfaces with fixed boxes (`NEUTRAL` in `scripts/color-eval/tune_report.py`). C adds two more box checks in the same way.

| Check | Pass rule (first draft) | Images |
|---|---|---|
| Black gear stays black | Box median: OKLab L below 0.35 and chroma below 0.04. Hue is not orange-brown (OKLab hue 40 to 90) when chroma is 0.02 or more. | Not chosen. Candidates: the wreck and diver frames in `DeveloperMedia/subjectpicker/`, r15. |
| Plants keep their colour | Box median chroma stays at 0.6 × source chroma or more. Hue stays inside 90 to 160 (yellow-green to green). | Not chosen. No image with weed or seagrass is known yet. |

Steps:

1. C0: find two or three images for each check. Add them to `DeveloperMedia/INDEX.md` if they are new.
2. C1: add the boxes and the report lines. Run them on `main`. Record the baseline here.
3. The pass rules are a draft. Set them after the baseline, before A or B runs.

Go rule: both checks print a value for every chosen image.

Cost on iPhone: none. Harness only.

## Stage A — cross-channel red estimate

Kind: estimate, not optics. It guesses subject red from the other channels. It cannot restore red light that never arrived.

### What we know

- Restoration multiplies each channel by its own gain. This is correct optics. It cannot make red from green or blue.
- `redRebuild` adds red as a share of green. A hue gate (`redGateLow`, `redGateHigh`) keeps it out of water.
- The benchmark already fits a global quadratic RGB map (`global_mapping_rmse` in `aquacolorfix_benchmark.py`). It found that a global map explains most of AquaColorFix's output.
- Known limit: the m6 reef is olive-green on our photo path. On Sea-thru it is brown.
- r15's grey-blue diver is accepted (Jake, 20 Oct 2026). It is not a target here.
- The 22 Oct two-layer water on the thresher clip came from highlight protection, not from the red gate. It is fixed (7040d4f). A does not target it.

### A1 — ceiling test (diagnostic only)

Question: can a linear 3×3 map with an offset, from source to a reference, get closer than our full pipeline?

1. For m5, m6 (Sea-thru) and the five AquaColorFix pairs, fit source → reference. Use the existing 70/30 split.
2. Report the CIE76 error of the fit against our `HEAD` error. Report the subject red/green (`nearRG`) and the m6 reef box too.
3. Fit source → our own output too. A small error means our pipeline is close to global already.

Go rule: the 3×3 fit beats `HEAD` by 3 CIE76 or more on at least two images. It must also move the m6 reef toward brown. Otherwise stop A here and record the result.

### A2 — our own estimate rule (only if A1 passes)

It replaces or extends `redRebuild`. It does not go into the restoration kernel, because the kernel is the optical step.

1. Read the off-diagonal terms of the A1 fits. Which terms matter (red from green, red from blue)? How do they change with the cast?
2. Derive them from the analysis values we already have: cast, `waterType`, red survival. Put the rule in `ColorCorrection.make`, as a named value.
3. Keep red out of the water. The estimate alone adds red to water, which makes it grey or violet. Weight it by the water matte from B, or by `neutralWeight` until B exists.
4. Check on the guards: violet share, pale surface pink, black gear, plants, the neutral ramp.

Go rule: the m6 reef moves toward brown. No guard gets worse by more than its current tolerance.

Cost on iPhone: about 9 multiply-adds per pixel in an existing kernel. No new pass, no new buffer.

Risk: shadow colour noise. An estimate that takes red from green also takes green's noise. Check the O3 noise masks (`hydrotone-eval-tools/noise`).

## Stage B — one water matte from transmission

Kind: optics on photos. The matte is `1 - t`, with `t = exp(-betaDirect x depth)` from the plan. Video has one constant depth per scene, so it has no optical matte.

### What we know

Several parts decide "water or subject" on their own, per pixel:

| Part | Where | Known failure |
|---|---|---|
| `waterLike`, `neutralWeight` | `FinishingMath`, `UnderBlueFinishColor` | A pale body lit by blue water reads as water. |
| `calmWeight`, `openWaterRed` | `FilterEngine` | Grey ring around fish, fixed by a 3% blur (2c55acc). |
| `SubjectMask` (Vision) | `RestorationEngine`, photos only | Returns nil above 25% of the frame. Video has none. |
| `liftDark` | `RestorationEngine`, video only | Built for the hammerhead halo. Flicker is unmeasured. |
| `subjectTone` | finishing | Pale ring around fish (E18 in [SubjectEmphasis](SubjectEmphasis.md)). Colour cannot tell a glow from a white belly. |

All five parts above test colour. None reads transmission.

What exists for `t`:

- `main`: the plan holds `depth` and `betaDirect`. Nothing computes `t` as an image yet.
- `subject-picker`: `UnderBlueContrastTransmission` computes `luma x exp(-betaDirect x depth)` for the lift tiers (E17 in [SubjectEmphasis](SubjectEmphasis.md)). B needs `t` without the `luma` term.
- The same branch has a colour-based share (`FilterEngine.waterShare`). B uses it only as a fallback where depth is missing.

### B1 — build the matte, change nothing

1. Compute `1 - t` at depth-map resolution. Upsample it to the image. Depth edges follow the depth model, so feather with a small blur.
2. Where the Vision mask exists, set the matte to 0 inside it. The mask fixes depth errors on a subject.
3. Write it out as an image. Compare it with each part in the table above on the same frames.
4. Video: write out the colour share on the same clips. This shows how far the video path stays from the photo matte.

Go rule: on the halo and ring frames, the matte separates subject from water where the colour tests disagree. Judge by eye on the sheets.

Known risk: E17 found that the plan's veil can sit between bright surface water and a dark diver (DSC03687, DSC03656). Check that `1 - t` does not read surface water as subject on those photos.

### B2 — switch one rule at a time

Order: `openWaterRed`, then the water tone, then the white reference weight, then the local veil.

1. Switch one rule to the matte. Run the guards and the three test frames.
2. Keep the switch only when it passes. Then go to the next rule.

Test frames:

- The hammerhead clip and the thresher clip (`DeveloperMedia/tune/video/Tune_22_Oct/`, the two `instagram-media` files).
- The whale shark clip. Always include an open-water clip; the 22 Oct grey ring showed only there. Its folder is not checked yet.
- Photo r13 (shark in bright open water) and an E18 pale-ring fish.

Go rule: no new halo or ring. The neutral surfaces and the AquaColorFix gate stay inside tolerance.

Cost on iPhone: one map at depth-map resolution and one small blur. The depth map and the Vision mask already exist, so there is no new model call. Video keeps its colour tests unless B finds a cheap per-frame substitute; that cost is unmeasured.

## Not in this plan

- Backscatter removal. It is a capture problem.
- Keeping green water green. Rejected above.
- A learned restoration model. It breaks the own-logic rule.
- Changes to the subject lift. It has its own track in [SubjectEmphasis](SubjectEmphasis.md).

## Sources

- Five Meters, "Underwater photo colour correction", fivemeters.app/guides/underwater-photo-color-correction (read 24 Oct 2026).
- Five Meters, "Fixing a blue or green cast", fivemeters.app/guides/blue-green-underwater-color-casts (read 24 Oct 2026).
- Five Meters, "Underwater haze vs backscatter", fivemeters.app/guides/underwater-haze-vs-backscatter (read 24 Oct 2026).
- Akkaynak et al., CVPR 2017 and 2018. The guides cite these papers. We did not read them for this plan.
