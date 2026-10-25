# Restoration experiments — plan

Status: running since 24 Oct 2026 on branch `restoration-experiments`, on the Mac harness first (Jake, 24 Oct 2026). C1 and A1 are done; see their Result parts. [LUTPresets](LUTPresets.md) comes after this plan.

This page plans four experiments. The ideas for A, B and C come from three public guides by the Five Meters photo editor (see [Sources](#sources)). We take general ideas only. We do not copy code, models or coefficients.

## Goal

Overall goal (Jake, 24 Oct 2026): more natural and more vivid photo and video results. Quality is never traded for speed, and speed should still go up.

| ID | Question | Why it matters |
|---|---|---|
| C | Do we measure the failures a diver sees first? | Without it, A and B cannot be judged. |
| A | Can a cross-channel red estimate give better subject colour than `redRebuild`? | Some subjects stay olive or grey (m6 reef). |
| B | Can one water matte from transmission replace several colour-based water tests? | Halos and rings form where these tests disagree. |
| D | How well do we deal with floating particles (marine snow, backscatter)? Does our correction make them more visible? | Jake asked for this check (24 Oct 2026). A vivid look also lifts specks. |

Order: C, then D1, then A1, then B1, then the sand grain fix, then B2, then A2, then D2. Each stage has a go/no-go rule. A1 ran before D1 because D was added later. The grain fix came in from the D1 finding (Jake, 24 Oct 2026).

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
| Backscatter | A capture problem. No slider fixes it. | The video particle filter prototype (`Prototypes/VideoCleanup`). Stage D measures it. Photos have no particle step. |

The guides give no measurements. Each claim above is the vendor's own statement.

## Stage C — new scorecard checks

The harness checks neutral surfaces with fixed boxes (`NEUTRAL` in `scripts/color-eval/tune_report.py`). C adds two more box checks in the same way.

| Check | Pass rule | Images |
|---|---|---|
| Black gear stays black | Box median in OKLab. L stays below 0.35. Hue is never orange-brown (40 to 90) when chroma is 0.02 or more. Chroma rises by 0.01 at most over the baseline below. | r15 wetsuit chest (teal water), r12 BCD chest (deep blue cast), DSC03696 wetsuit torso and BCD (clear blue water). |
| Grain on flat bright sand | Std of luma minus its 4 px blur, in a box, at 1920 px with lossless PNG. The ratio over the original rises by 0.10 at most over the baseline below. Added 24 Oct 2026 after the D1 finding. | r14 teal sand, r03 white sand, m5 sand (Sea-thru output as the reference point), sand beside the sargassum. |
| Plants keep their colour | Median of the box's plant pixels (original OKLab hue below 180, so water between the leaves stays out). Hue stays inside 60 to 160: golden-brown algae to green seagrass. Chroma falls by 0.01 at most from the baseline below. The report also flags chroma below 0.6 × original as `GREY`. | Sargassum in green water (`pl1`), kelp in teal water (`pl2`). Jake gave both on 24 Oct 2026. |

Steps:

1. C0: find two or three images for each check. Add them to `DeveloperMedia/INDEX.md` if they are new.
2. C1: add the boxes and the report lines. Run them on `main`. Record the baseline here.
3. The pass rules are a draft. Set them after the baseline, before A or B runs.

Go rule: both checks print a value for every chosen image.

Cost on iPhone: none. Harness only.

### C0 and C1 result (24 Oct 2026)

- Black gear: three photos, four boxes. DSC03696 is rendered as `g1` in a small extra set (`guard`) in `tune_eval.sh`.
- Plants: no photo in `DeveloperMedia/` had weed or seagrass (all checked by eye). Jake then gave two: `tune/photo/plants/`. The yellow fans in the kelp photo look like gorgonians, which are animals, so no box sits on them.
- The boxes were drawn on the rendered outputs and checked by eye.
- C's go rule is met: both checks print a value for every chosen image.

Baseline, `main` at 085a6f3 (OKLab L / chroma / hue of the box median):

| Box | Original | Ours | Ours (video path) |
|---|---|---|---|
| r15 wetsuit chest | 0.20 / 0.021 / 185 | 0.12 / 0.012 / 210 | 0.11 / 0.011 / 196 |
| r12 BCD chest | 0.28 / 0.190 / 267 | 0.30 / 0.134 / 262 | 0.34 / 0.142 / 261 |
| DSC03696 wetsuit torso | 0.21 / 0.048 / 254 | 0.13 / 0.029 / 256 | 0.13 / 0.029 / 256 |
| DSC03696 BCD | 0.23 / 0.064 / 258 | 0.16 / 0.044 / 260 | 0.16 / 0.044 / 260 |

- No box turns brown. The residual cast is blue (hue 256 to 262) in three boxes.
- The first-draft rule (chroma below 0.04) failed on two boxes at baseline. These are r12 (0.134, a near-monochrome blue photo) and the DSC03696 BCD (0.044).
- So the rule now guards against change from this baseline. The report flags only `BROWN` and `LIGHT`. Compare chroma with this table. Jake confirmed this rule on 25 Oct 2026.

Plants baseline, same commit (median of the plant pixels, OKLab L / chroma / hue):

| Box | Plant share | Original | Ours | Ours (video path) |
|---|---|---|---|---|
| Sargassum foreground | 100% | 0.53 / 0.110 / 110 | 0.49 / 0.099 / 82 | 0.41 / 0.083 / 84 |
| Sargassum right cluster | 100% | 0.59 / 0.122 / 107 | 0.55 / 0.113 / 79 | 0.47 / 0.097 / 78 |
| Kelp blades | 75% | 0.52 / 0.061 / 162 | 0.57 / 0.030 / 107 | 0.57 / 0.030 / 107 |
| Kelp stipe | 100% | 0.45 / 0.049 / 162 | 0.48 / 0.028 / 107 | 0.49 / 0.029 / 107 |
| Green water (sargassum photo) | | 0.61 / 0.093 / 152 | 0.48 / 0.035 / 201 | 0.51 / 0.031 / 208 |
| Teal water (kelp photo) | | 0.75 / 0.118 / 209 | 0.79 / 0.085 / 234 | 0.79 / 0.090 / 233 |

Seen on the sheets and in these numbers:

- Sargassum turns golden-amber (hue 110 to 82) and keeps its chroma. It is a brown alga, so this looks natural. The first-draft band (90 to 160) assumed green plants and flagged it, so the band is now 60 to 160 (Jake confirmed, 25 Oct 2026).
- Kelp turns a dull khaki: chroma halves (0.061 to 0.030), below the 0.6 × flag. Part of the original chroma is the teal cast, so the flag may overstate it, but the sheet agrees: the kelp looks grey-olive.
- The green water moves to hue 201, short of the 215-265 target in `tune_report.py`, and its chroma falls to 0.035. It looks grey-teal, not clear cyan. This misses Jake's rule of 24 Oct 2026: green water goes cyan or blue.
- The surface highlights in the sargassum photo lean magenta (hue 315), but only at chroma 0.015. This is the known pale surface pink, at a low level.

AquaColorFix on the same two photos (Jake gave its outputs on 25 Oct 2026; not the target, for reference only), median of the same pixels:

| Box | Ours | AquaColorFix |
|---|---|---|
| Sargassum foreground | 0.49 / 0.099 / 82 | 0.42 / 0.038 / 78 |
| Sargassum right cluster | 0.55 / 0.113 / 79 | 0.49 / 0.052 / 70 |
| Green water | 0.48 / 0.035 / 201 | 0.53 / 0.046 / 239 |
| Kelp blades | 0.57 / 0.031 / 110 | 0.51 / 0.025 / 101 |
| Kelp stipe | 0.48 / 0.028 / 107 | 0.43 / 0.018 / 94 |
| Teal water | 0.79 / 0.085 / 234 | 0.77 / 0.052 / 238 |

- Our plants keep two to three times the chroma. AquaColorFix turns the sargassum a dull pink-tan.
- AquaColorFix moves the green water to blue (239); ours stops at grey-teal (201). A2's water anchor should close this.

Grain baseline, same commit (1920 px; std of luma minus a 4 px blur; ratio over the original):

| Sand | Original | Ours | Ours (video path) | Sea-thru |
|---|---|---|---|---|
| r14 teal sand | 4.38 | 12.36 (2.82×) | 11.48 (2.62×) | none |
| r03 white sand | 4.47 | 11.86 (2.65×) | 11.87 (2.65×) | none |
| m5 sand | 4.59 | 11.57 (2.52×) | 9.36 (2.04×) | 6.56 (1.43×) |
| Sand beside the sargassum | 3.75 | 5.42 (1.44×) | 5.44 (1.45×) | none |

- The grain rises on three of four sand areas by 2.5 to 2.8 times. Sea-thru adds 1.43 times on m5.
- The 1:1 crops agree: our m5 sand gets a coarse salt-and-pepper grain, while Sea-thru's stays smooth. r03 turns white with grey blotches, like r14.
- The measure cannot tell wanted detail from noise by itself. So it runs only on flat sand, and the crops are checked by eye.
- New baseline after the grain fix (25 Oct 2026): r14 1.72×, r03 1.85×, m5 2.07×, sargassum sand 1.36× (video path 1.59×, 1.86×, 1.87×, 1.37×). The guard compares with these.

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

#### A1 result (24 Oct 2026, `main` at 085a6f3): go

Script: `scripts/color-eval/a1_ceiling.py`. The fit runs in linear RGB on a random 70% of the pixels (100,000 at most). The table scores the other 30% in CIE76. The "ours" column matches the harness dE (m5 12.3, m6 27.2, p1-p5 within 0.1).

| Pair | Ours | Fit to reference | Gain | Fit to our output | Ours, a\*b\* only | Fit, a\*b\* only |
|---|---|---|---|---|---|---|
| m5 (Sea-thru) | 12.3 | 10.3 | +2.0 | 5.8 | 9.7 | 6.8 |
| m6 (Sea-thru) | 27.2 | 6.4 | +20.9 | 4.5 | 25.5 | 5.7 |
| p1 (AquaColorFix) | 9.0 | 1.8 | +7.3 | 3.2 | 6.8 | 1.4 |
| p2 | 17.5 | 1.1 | +16.4 | 4.1 | 17.2 | 1.0 |
| p3 | 6.8 | 2.3 | +4.5 | 3.8 | 5.9 | 1.4 |
| p4 | 12.1 | 2.9 | +9.2 | 4.5 | 11.1 | 2.1 |
| p5 | 10.7 | 2.5 | +8.2 | 3.1 | 8.6 | 2.2 |

m6 reef box (0.30, 0.80, 0.70, 0.95), OKLab L / chroma / hue: source 0.50 / 0.085 / 159, ours 0.47 / 0.060 / 128, fit 0.34 / 0.070 / 76, Sea-thru 0.34 / 0.034 / 64. The box was checked by eye on all four images.

Verdict: the go rule is met. The fit gains 3 or more on 6 of 7 pairs, and it moves the m6 reef into the brown band. `nearRG` of the fits is unmeasured: that metric needs the depth map, and the script has none.

Read it with care:

- The fit sees the reference. It shows what one global map can reach. It is not a rule we can compute.
- p1-p5 compare with AquaColorFix, which is not the target since 1 Oct 2026. These rows only confirm that AquaColorFix is close to one global linear map (a\*b\* error 1.0 to 2.2).
- On m6 the gap is colour, not brightness (a\*b\* 25.5 of 27.2). On m5 the fit gains only 2.0.
- Our own output is 3.1 to 5.8 from a global map of its source. So most of what we do is global too.

Leads for A2 step 1 (from the printed coefficients; not findings yet):

- Every fit to a reference takes red from green (R←G 0.30 to 2.20). Six of seven also take some red away by blue (R←B −0.08 to −0.54).
- The fits to our output differ most in blue. Ours: B←R 0.15 to 2.42, B←B 0.35 to 0.85. References: B←R −0.16 to 0.54, B←B 0.38 to 1.14. B←R is higher in ours on all 7 pairs; B←B is lower on 6 of 7. So our blue follows the red input more and the blue input less.
- R, G and B are strongly correlated in these photos, so one coefficient alone is unstable. Step 1 should apply the matrices to fixed colours (water, subject), not read single terms.

### A2 target: move our output toward Sea-thru's m6 (Jake, 25 Oct 2026)

Today, m6 (`tune_report.py`, 24 Oct): dE 27.2. Ours against Sea-thru:

| | Ours | Sea-thru |
|---|---|---|
| Water OKLab hue | 233 | 252 |
| Water chroma (Lab, far) | 21.0 | 45.3 |
| Mean L* | 45.9 | 38.7 |
| Reef box hue (A1) | 128 (olive) | 64 (brown) |
| Subject red/green (`nearRG`) | 0.79 | 0.91 |

So three gaps: the water is grey and too cyan, the reef stays olive, and the frame is 7 L* brighter. A1 showed one global 3 × 3 map closes most of it (27.2 to 6.4). But that map saw the reference.

Proposed rule (our own logic, no reference fit): build the 3 × 3 map from two anchors the analysis already has.

1. Water anchor: the estimated water colour maps to a target water: deep clear blue, OKLab hue about 245 to 255, chroma near the source's. This also turns green water cyan or blue (Jake, 24 Oct 2026).
2. Neutral anchor: the white reference maps to grey.
3. Red from green, by red survival (the A1 lead: every reference fit takes red from green).
4. Of all maps that meet the anchors, take the one closest to the current per-channel gains.

Check: m6 dE and the reef hue first, then m5 (vividness), then the guards (plants, black gear, grain, neutral ramp).

Decision (Jake, 25 Oct 2026): colour moves toward m6; brightness keeps the target look (slightly brighter).

Second check: the colour chart in AquaColorFix pair 6 (`O6.WEBP`, teal-green water; `scripts/color-eval/chart_check.py`, run by `aquacolorfix_eval.sh`). Its top row is a grey step, so every patch should come out colourless. Baseline, 25 Oct 2026 (after the grain fix):

| Grey patch | Original | Ours | Ours (video path) | AquaColorFix |
|---|---|---|---|---|
| 1 (white) | 0.91 / 0.136 / 187 | 0.89 / 0.057 / 235 | 0.90 / 0.053 / 233 | 0.87 / 0.044 / 243 |
| 2 | 0.87 / 0.151 / 181 | 0.85 / 0.084 / 225 | 0.85 / 0.089 / 225 | 0.84 / 0.021 / 239 |
| 3 | 0.83 / 0.148 / 179 | 0.84 / 0.080 / 224 | 0.84 / 0.083 / 222 | 0.79 / 0.017 / 239 |
| 4 | 0.78 / 0.141 / 179 | 0.80 / 0.081 / 223 | 0.80 / 0.082 / 222 | 0.74 / 0.016 / 242 |
| 5 | 0.69 / 0.124 / 180 | 0.71 / 0.079 / 225 | 0.70 / 0.077 / 224 | 0.63 / 0.022 / 239 |
| Mean chroma | 0.140 | 0.076 | 0.077 | 0.024 |

- Our greys stay light cyan-blue (hue about 225). By eye too: the grey step is sky blue, and the yellow and orange patches lean green. AquaColorFix's greys are neutral.
- So A2's neutral anchor has a measurable target here: mean chroma toward 0.02 to 0.03.

#### A2 prototype round (25 Oct 2026, Python, 960 px; `scripts/color-eval/a2_proto.py`)

Jake chose A2 before B2 (25 Oct 2026). Every try builds its map from the photo itself; none reads a reference.

What the analysis gives today: O6 has no white reference (neutral (0, 0, 0), share 0: the chart is about 1.5% of the frame and vanishes at the 48 × 48 analysis size). Its grey patches test as water-like (about 0.98), so they get the water tone.

| Try | m5 dE | m6 dE | O6 chart chroma | Green water C / hue | Kelp C / hue | Seen by eye |
|---|---|---|---|---|---|---|
| Ours today | 12.6 | 27.4 | 0.076 | 0.035 / 201 | 0.031 / 110 | |
| 1. Gains on the source (grey world on near pixels, or the water colour as light) | 33 to 41 | 21 to 26 | 0.11 to 0.13 | | down to 0.006 | Fails: one gain cannot replace our veil removal and tone. |
| 2. On our output: object gains (fixed s 0.7) and water gains, blended by depth | 13.6 | 25.0 | 0.041 | 0.065 / 231 | 0.032 / 147 | m5 sand too warm. |
| 3. As 2, object strength from the tint (adaptive s) | 11.3 | 23.9 | 0.030 | 0.065 / 231 | 0.033 / 151 | Jake: O6 sand-to-water boundary looks wrong. Far sand gets the water gains. |
| 4. As 3, water gains only where the colour test says water | 11.1 | 23.6 | 0.123 | 0.065 / 232 | 0.029 / 126 | O6 reads as water almost everywhere; the chart turns blue. |
| 5. As 3, water gains only on far and smooth pixels | 11.3 | 24.5 | 0.031 | 0.066 / 235 | 0.031 / 110 | Blue islands with hard edges in the hazy background. |
| 6. Object gains everywhere, then a colour-space shift of water-like colours | 11.6 to 13.1 | 24.4 to 25.6 | 0.05 to 0.11 | 0.06 to 0.09 / 220 to 230 | | O6 reef turns blue: after the neutralisation the reef is as close to the water colour as the water. |
| 7. Object gains everywhere, the veil added back by depth: out = ours × g + v × (T − W × g) | 11.3 | 23.9 | 0.030 | 0.107 / 236 | 0.020 / 168 | No seam; far O6 sand turns bluish with distance; kelp leans teal (outside the 60-160 band). |
| 8. Object gains everywhere, no water target; strength below 0.3 counts as 0 (current candidate) | 12.6 | 27.4 | 0.030 | 0.035 / 201 | 0.031 / 110 | O6: sand an even beige, chart grey, reef warm, water a hazy grey-blue. No seam. Other photos unchanged (strength 0). |

- m6's reef stays olive (124 to 130) in every try: these anchors only remove the water's tint. The brown needs red from green (the A1 lead), as a next step.
- Jake (25 Oct 2026), on O6: the water does not have to be blue. Forcing it blue (tries 2 to 7) is what made the sand-to-water seam. So try 8 drops the water target.
- Try 8 changes only photos whose near objects carry the water's tint (O6, strength 1.0). m5, m6 and the plant photos get strength 0 or 0.1 (below the 0.3 floor).
- Still open: m6's olive reef (needs red from green), and the green water of the sargassum photo (201, Jake's 24 Oct rule). Try 8 does not touch either.
- Next: put try 8 into the app as named values (ColorCorrection) and a kernel step, then run the guards. Sheets: `a2_proto.py` writes `<k>__proto.png`.

### A2 — our own estimate rule (only if A1 passes)

It replaces or extends `redRebuild`. It does not go into the restoration kernel, because the kernel is the optical step.

1. Read the off-diagonal terms of the A1 fits. Which terms matter (red from green, red from blue)? How do they change with the cast?
2. Derive them from the analysis values we already have: cast, `waterType`, red survival. Put the rule in `ColorCorrection.make`, as a named value.
3. Keep red out of the water. The estimate alone adds red to water, which makes it grey or violet. Weight it by the water matte from B, or by `neutralWeight` until B exists.
4. Check on the guards: violet share, pale surface pink, black gear, plants, the neutral ramp.

Go rule: the m6 reef moves toward brown. No guard gets worse by more than its current tolerance.

Cost on iPhone: about 9 multiply-adds per pixel in an existing kernel. No new pass, no new buffer.

Risk: shadow colour noise. An estimate that takes red from green also takes green's noise. Check the O3 noise masks (`hydrotone-eval-tools/noise`).

## Stage B — one water matte from depth (photos)

Kind: a depth-based estimate on photos. Re-scoped on 25 Oct 2026 after a code check (see "What we know").

### What we know

Several parts decide "water or subject" on their own, per pixel:

| Part | Where | Runs on | Known failure |
|---|---|---|---|
| `waterLike`, `neutralWeight` | `FinishingMath`, `UnderBlueFinishColor` | photo and video | A pale body lit by blue water reads as water. |
| `calmWeight` | `FilterEngine.waterCalmWeight` | photo and video | Grey ring around fish (2c55acc, video). |
| `openWaterRed` | `FilterEngine` | video only | Grey top layer over blue water. |
| `SubjectMask` (Vision) | `RestorationEngine` | photo only | Returns nil above 25% of the frame. |
| `liftDark` | `RestorationEngine` | video only | Built for the hammerhead halo. |
| `subjectTone` weight (1 − `waterLike`) | finishing | photo and video | Pale ring around fish (E18, DSC03545). |

Checked in code on 25 Oct 2026:

- `combined()` passes `openWaterRed: video` and `liftDark: video` (`RestorationEngine.swift:286-289`). So these two act on video only.
- Depth is relative. Each photo's depth is cut at its 5th and 95th percentile and scaled to 0...1 (`DepthEstimator.swift:100-111`). 0 is near, 1 is far.
- So `1 - t = 1 - exp(-betaDirect × z)` only redraws the depth map. It ranks pixels exactly as depth does. Its top value is about 0.64 (computed from the clamps), not 1.
- Every photo has a farthest 5% at z = 1, even a photo with no open water.
- Video holds one depth value per scene (`RestorationPlan.swift:144-149`). It has no depth map, so no matte.
- `t` already exists on `main`: `UnderBlueContrastTransmission` and `RestorationEngine.contrastTransmission`. It weights the three channels by BT.709 (green 72%). The harness writes it as variant `signal` with `HT_EVAL_SIGNAL=1`.

What this changes:

- B is for photos only. The video halos (hammerhead, thresher, whale shark) need another approach. They are out of this stage.
- B's real question: does the depth map separate subject from water better than the colour tests, on the photos where they fail?
- The whale shark clip in `DeveloperMedia` is an UnderBlue export, not the original. It is not a valid input for any video test.

### B1 — build the matte, change nothing

1. Add `HT_EVAL_MATTES=1` to the harness. It writes grey PNGs next to the outputs: depth, `1 - t`, the Vision mask, `calmWeight` (r, g, b) and the `waterShare` share. No CSV row or report changes.
2. Photos: DSC03545 (E18 pale ring, E27 band), r13 (shark in bright open water), DSC03687 and DSC03656 (E17: bright surface water), r15 (hose rim).
3. Compare the maps on one sheet per photo, by eye.

Go rule: on DSC03545 and r15, depth separates the subject from the water where the colour tests do not. On DSC03687 and DSC03656, depth does not read the bright surface water as subject.

#### B1 result (25 Oct 2026, `main` at 085a6f3): partial go

Run: `HT_EVAL_MATTES=1`, 1280 px. Sheets checked by eye: original, ours, depth, `1 - t`, Vision mask, `calm` r and b, `waterShare`.

| Photo | Depth | Colour tests | Better |
|---|---|---|---|
| r15 diver, teal water | Diver near, water far. Clean. | `waterShare` reads the diver as mostly water (light grey). `calm b` marks it weakly. | Depth |
| DSC03687 reef, surface at top | Surface water reads far, like the water. | The top band partly reads as not water. | Depth |
| DSC03656 reef, sun glare at top | Glare area reads far, like the water. | All three read the glare area as not water: a large dark blob. | Depth |
| DSC03545 white fish (E18) | Fish nearer (about 0.7 against 1.0), but blocky at 518 × 392. | `calm b` follows the fish edge closely. `share` and `calm r` spread wide around it (blurred). | Colour (`calm b`) |
| r13 shark, open water only | Invents a gradient: water near the bottom edge reads near, a bright blob reads far. | Water everywhere except the shark. Correct. | Colour |

- Depth wins where colour fails: a dark subject in teal water, and bright surface water or glare.
- Depth fails in open water with no structure (r13). The 5-95 percentile scaling stretches tiny depth steps to the full 0...1 range.
- `depthConfidence` is 0.694 on four of five photos, r13 included. It does not warn about this case.
- B1 does not show whether depth removes the E18 ring. The ring sits in the glow next to the fish; B2 tests it directly.

So B2 needs a trust rule before any switch: use the depth matte only where depth and colour can disagree for a reason. A first rule to test: when the colour share calls almost the whole frame water (r13: `waterShare` above 0.9 nearly everywhere), keep the colour test.

### B2 — switch one rule at a time (photos)

Order: the `subjectTone` weight (E18), then the water tone, then the white reference weight, then the local veil.

1. Switch one rule to the depth matte. Run the guards and the B1 photos.
2. Keep the switch only when it passes. Then go to the next rule.

Go rule: no new halo or ring. The neutral surfaces, the plant, black gear and grain guards and the AquaColorFix gate stay inside tolerance.

Cost on iPhone: one map at depth-map size and one small blur. Depth and the Vision mask already exist, so there is no new model call.

## Stage D — floating particles

Kind: measurement. No new removal step is planned yet. Jake asked for this check on 24 Oct 2026.

### What we know

- Photos have no particle step. Video has a prototype, `Prototypes/VideoCleanup/ParticleFilter.swift`. It is not wired in.
- Prototype results (Mac M3, 1080p60 clips, measured before colour correction, see its README):
  - It removes 43-71% of the drifting specks on 3 of 4 segments, and 21% on the sparse one.
  - It keeps 99-100% of small subjects and changes under 0.1% of pixels.
  - Speed: 126-204 fps at 1080p, 63-67 fps at 4K. iPhone: unmeasured.
- The speck metric is `Prototypes/VideoCleanup/particle-bench/metric.swift`. A speck is an isolated bright group of 1-12 px. Its peak is 4-30 levels above the local mean, and above 5 × the local noise. "Drifting" means it is gone in a neighbour frame after camera motion is removed.
- `ColorAlgorithm.md` puts particles before colour, because colour gains and clarity lift specks. That reason is stated, not measured.
- Clip c2 (`2019-05-05 18.37.02.MOV`) is missing, so segment S4 cannot run.

### D1 — does our correction make specks more visible?

Photos and single video frames, harness only.

1. Build a small photo tool on the single-frame part of `metric.swift` (`maps()`). No port, so the definition stays the same.
2. For original, ours and the video path, count isolated bright groups of 1-40 px at any peak. Print the median peak in levels too. A brighter speck can pass 30 levels and move from "speck" to "bright spot". A count by class alone would hide that.
3. Render at 1920 px (`HT_EVAL_MAXDIM`). The metric was set on 1080p frames; at 640 px a speck merges into its background.
4. Images: count all photos first, then keep the best, middle and worst. Video: stills from c3 S1 (snow) and c1 S3 (fish).

Go rule: every chosen image prints a value. After the baseline, set a guard for A2 and B: how much the count and the median peak may rise.

#### D1 result (24 Oct 2026, `main` at 085a6f3): go

Tool: `particle-bench` modes `photo` (census) and `pair` (same groups in original and output). Harness run with `HT_EVAL_MAXDIM=1920 HT_EVAL_PNG=1`, so no JPEG step sits between render and metric.

A raw count is a poor proxy. Crops checked by eye showed what the census finds:

- r12 (diver, deep blue): mostly sensor grain, not particles. Not used.
- r10 (sunlit boat): many real bright specks: backscatter, bubbles, surface glints.
- DSC03546: real specks, small far fish and reef texture points, mixed.
- c3 at 30 s: faint soft marine snow. c1 at 1 s: mostly highlights on fish and coral (median peak 42, above the 30-level speck limit).

So D1 uses the paired measure. It finds the isolated groups of 1-40 px in the original. Then it reads their peak at the same place in our output. A ratio above 1 means the spots stand out more.

| Image | Groups in original | Ours: median peak ratio (p10-p90) | Ours (video path) |
|---|---|---|---|
| r10 sunlit boat | 710 | 1.07 (0.42-1.66) | 1.06 |
| DSC03546 wreck | 420 | 0.48 (0.30-1.77) | 0.48 |
| r14 teal sand | 60 | 0.32 (0.27-1.44) | 0.33 |
| c3 snow still | 91 | 0.60 (0.45-1.22) | 0.79 |
| c1 fish still | 168 | 1.29 (0.69-1.45) | 1.31 |

- In open water our output makes faint specks weaker, not stronger. Crops confirm it: the water calm step smooths them.
- c1 rises, but its groups are mostly subject highlights, not particles.
- Guard for A2 and B: the median ratio may rise by 0.10 at most over this table.

#### Finding: grain on bright sand (r14)

At 1:1, our output turns the fine grain of r14's teal sand into grey-white blotches. Box (0.55, 0.70, 0.80, 0.95) at 1920 px, std of luma minus a 4 px blur:

| Output | Std | Note |
|---|---|---|
| Original | 4.38 | |
| Restoration only | 4.36 | The optical step adds none. |
| Gray-world | 4.19 | Same mean colour as ours. |
| Ours (`combined`) | 12.36 | Video path 11.48. |
| Finishing only (`current`) | 12.63 | The two rows below start from this one. |
| `current`, `detail` off | 8.43 | Largest single cause. |
| `current`, all local and tone stages off | 8.83 | The rest comes from the colour stages. Which one is not located. |

- This is not a particle. It is a quality defect in the current output.
- It holds at full export size on the Mac harness: r14 2.85× and r03 2.82× with the same 4 px blur (3140 and 3264 px wide). The iPhone is unchecked.
- A2 adds red made from green, so it adds green's grain to red. Check this box before and after A2.
- It is not r14 alone: r03 and m5 show the same rise (see the grain baseline in Stage C).
- Decision (Jake, 24 Oct 2026): guard it now in Stage C, and fix it as its own item after B1, before A2.
- Cause (25 Oct 2026, 1920 px, `current` path): two detail stages, both on bright sand.

| Sand grain | r14 | r03 | m5 |
|---|---|---|---|
| Original | 4.38 | 4.47 | 4.59 |
| `current` | 12.63 | 11.98 | 11.76 |
| Light detail off | 7.66 | 7.16 | 9.44 |
| Light detail and fine detail off | 4.66 | 4.84 | 5.97 |

  - Light detail (`FinishingMath.lightDetail`, amount 1.3) is for light rays. It acts on gamma luma 0.5 to 0.7, and bright sand is in that range. It has no noise floor.
  - Fine detail has a floor (`detailFloor` 0.004, full strength from 0.012), but the sand grain is about 0.017. So grain gets the full boost.
  - The colour stages add little: red rebuild, neutral gains and water tone off change the grain by 0.1 to 1.8.
  - Fix to test: a noise floor for both detail stages, set from the photo's own grain. Check that light rays (IMG_7400) and the m5 vividness stay.

#### Sand grain fix result (25 Oct 2026): adopted

Change: a grain map (`UnderBlueGrain`, `FilterEngine.grainMap`): each pixel against a 1 px blur, spread over 1% of the short side. The light detail fades where the grain runs from 0.0022 to 0.0032 (`FinishingMath.lightDetailGrainLow/High`). Grain at the light detail's input (1920 px): IMG_7400 rays 0.0018, DSC03656 surface 0.0011, sand 0.0035 (r03) to 0.0084 (m5).

| Try | Sand grain r14 / r03 / m5 | IMG_7400 rays kept | m5 local contrast | p4 subject detail |
|---|---|---|---|---|
| Before | 2.82× / 2.65× / 2.52× | 100% | 8.73 | 7.36 |
| Grain floor on both stages (k 2 and 1.5) | 11.05 / 11.85 / 9.61 (std) | 100% | not run | not run |
| Light detail on water only (`1 - calm.b`) | 7.12 / 7.63 / 8.12 (std) | 14% | not run | not run |
| Smooth gate 0.0022-0.0032 + fine-detail floor 1.5 | 1.63× / 1.84× / 1.76× | 87% | 8.23 | 5.77 |
| **Smooth gate 0.0022-0.0032 only (adopted)** | **1.72× / 1.85× / 2.07×** | 87% | 8.64 | 7.31 |

- The water-only gate killed the rays: the colour test reads bright ray water as subject.
- The fine-detail grain floor took 20% of the subject detail and 6% of the m5 local contrast. Dropped: m5 vividness is a goal.
- Seen at 1:1: the r03 blotches are gone; the IMG_7400 rays stay, a little softer; the DSC03656 top is near white either way.
- Guards: AquaColorFix gate 11.22 (was 11.23); black gear and neutral surfaces unchanged; plants inside tolerance. `RestorationTests` pass on the iOS simulator (80 tests, 1 skipped), with a new kernel-versus-mirror check for the gate.
- Left: m5 sand is still 2.07× (Sea-thru 1.43×). The rest is the fine detail.

### D2 — the video prototype in the full chain

1. Run particles, then our colour, on S1 and S3. Compare with colour only.
2. Measure drifting specks, small subjects kept, and pixels changed, all after colour. Check the crops by eye: fish must survive.

Go rule: removal after colour is not lower than before colour (43-71%), and small subjects kept stay at 99% or more.

Cost on iPhone: unmeasured. Measure it only after the algorithm is done.

Photos: a single photo has no neighbour frame, so the drifting test cannot work there. Decide on photo removal after D1 shows how visible the specks are.

## Not in this plan

- A particle remover for photos. D measures first.
- Keeping green water green. Rejected above.
- A learned restoration model. It breaks the own-logic rule.
- Changes to the subject lift. It has its own track in [SubjectEmphasis](SubjectEmphasis.md).

## Sources

- Five Meters, "Underwater photo colour correction", fivemeters.app/guides/underwater-photo-color-correction (read 24 Oct 2026).
- Five Meters, "Fixing a blue or green cast", fivemeters.app/guides/blue-green-underwater-color-casts (read 24 Oct 2026).
- Five Meters, "Underwater haze vs backscatter", fivemeters.app/guides/underwater-haze-vs-backscatter (read 24 Oct 2026).
- Akkaynak et al., CVPR 2017 and 2018. The guides cite these papers. We did not read them for this plan.
