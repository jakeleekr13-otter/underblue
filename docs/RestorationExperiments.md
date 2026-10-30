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
  - Update 26 Oct 2026: the m6 reef box now reads hue 93 on the photo path (A2, C 0.049; Sea-thru 65, source 160), brown-gold by eye. The video path still reads 133 (`videoa2`; 140 without the video step): video has only step 2, and step 2 alone moves it 7 degrees. Step 1 stays off in video (it greyed v5_70).
  - Tried 26 Oct 2026: step 1 in video for scenes whose keyframe depth can be trusted. Reverted. m6 and O4 get no gains (strength 0): the photo's brown comes from step 2's red by depth, which video cannot do without per-pixel depth. v5_30 and v5_70 count as trusted and got strong gains (1.6, 0.89, 0.63), the greying seen before. Video m6 stays olive for now.
  - Update 29 Oct 2026: video m6 reads hue 98 with the scene fit (see "Video reef colour: the scene fit" below).
#### A2 step 2: red from green on near subjects (25 Oct 2026)

Jake asked whether O4 can improve. O4 is the m6 scene (the bench maps pair 4 to `market/ref/m6.png`), so it has two independent references: AquaColorFix and Sea-thru. Both agree on three gaps (OKLab L / chroma / hue):

| Box | Ours | AquaColorFix | Sea-thru |
|---|---|---|---|
| Reef | 0.46 / 0.061 / 127 | 0.38 / 0.057 / 84 | 0.34 / 0.035 / 66 |
| Manta belly (white) | 0.71 / 0.049 / 177 | 0.70 / 0.011 / 239 | 0.69 / 0.062 / 229 |
| Water, right | 0.47 / 0.070 / 232 | 0.46 / 0.091 / 238 | 0.42 / 0.136 / 255 |

Rule tried (`a2_proto.red_from_green`): red += k0 × redLoss × green excess × nearness, with green excess e = max(0, G − (R + B)/2) and luminance kept. Plain G instead of the excess turned m5's sand pink (hue 9 at k0 1.0); the excess leaves neutral surfaces alone.

| Run | m5 dE | m6 dE | O4 reef | O4 belly | O6 chart | Sargassum | Kelp | m5 sand |
|---|---|---|---|---|---|---|---|---|
| Ours | 12.6 | 27.4 | 0.061 / 127 | 0.049 / 177 | 0.076 | 0.101 / 83 | 0.031 / 110 | 0.015 / 220 |
| Step 1 (try 8) | 12.6 | 27.4 | 0.061 / 127 | 0.049 / 177 | 0.030 | 0.101 / 83 | 0.031 / 110 | 0.015 / 220 |
| Step 2, k0 3 | 11.4 | 26.4 | 0.057 / 82 | 0.018 / 139 | 0.055 | 0.101 / 83 | 0.031 / 110 | 0.007 / 247 |
| Steps 1 + 2 | 11.4 | 26.4 | 0.057 / 82 | 0.018 / 139 | 0.009 | 0.101 / 83 | 0.031 / 110 | 0.007 / 247 |

- Seen by eye: O4's reef turns brown and its small fish orange; m5 looks the same; O6's green feather coral turns golden (AquaColorFix also shows it orange); the kelp photo's gorgonians get more golden.
- First fade (full at depth 0.2, none at 0.7): the O4 reef's far left changed less (hue 119 against 82 in the centre), so a green-to-brown change showed across the reef (Jake asked to fix it).
- Fix: water sits at depth 0.97 or more in every test photo, and the O4 reef spans 0 to 0.96 (left part about 0.5). The fade now runs from 0.6 (full) to 0.9 (none). O4 reef left / centre / right: 0.052/81, 0.057/82, 0.036/149 (was 119, 82, 169). By eye the reef is one brown; O6's far sand is an even beige. Side effects: O4 belly 0.016/85 (a faint warm white), kelp 0.032/89 (olive-brown, inside the band), m6 dE 26.9 (was 26.4), m5 11.3.
- Seagrass check (Jake gave `tune/photo/plants/RCA_9472.JPG` and its AquaColorFix output, 25 Oct 2026; now `pl3` in the guard set). Plant pixels, OKLab L / chroma / hue:

| Box | Original | Ours before A2 | Ours with A2 | AquaColorFix |
|---|---|---|---|---|
| Seagrass near | 0.63 / 0.061 / 122 | 0.62 / 0.062 / 93 | 0.62 / 0.063 / 88 | 0.51 / 0.026 / 96 |
| Seagrass mid | 0.64 / 0.063 / 141 | 0.62 / 0.054 / 104 | 0.62 / 0.054 / 99 | 0.51 / 0.019 / 134 |
| Water | 0.63 / 0.070 / 213 | 0.59 / 0.063 / 233 | 0.59 / 0.063 / 233 | 0.54 / 0.079 / 241 |

  - Our pipeline already turned the green seagrass yellow-olive before A2 (hue 122-141 to 93-104). Taking the teal cast away pushes the hue about 30 degrees toward yellow. A2 adds about 5 more (redLoss is only 0.19 here).
  - This misses Jake's rule (24 Oct 2026): plants keep their green. The 60-160 band does not catch it; it was set for brown algae. A green plant needs its own check: hue about 110 or more.
  - AquaColorFix keeps more of the hue (96-134) but drops the chroma to about 0.02 (greyish).
  - Open: protect green plants. A2 step 2 should not add red to a green plant; the cast step before A2 needs a look too.
- The O4 water gap (grey, chroma 0.070) is left: Jake said on O6 that water need not be blue.

#### A2 in the app (25 Oct 2026): photos only
- Code: `RestorationEngine.objectColourValues` (named values) and the `UnderBlueObjectColour` kernel. It runs after the violet calm, on the depth path only, so video is unchanged.
- Gates, so photos without the tint stay as they are:
  - Step 1 runs only when the near and far means are 0.10 to 0.14 apart in OKLab (smoothstep). Without this, open-water photos (r01, r07, r10-r13) got full strength and grey water.
  - Step 2 subtracts the far water's own green excess (after the step 1 gains), so the water gets no red.
  - Both steps skip when the near or far side has 100 pixels or fewer.
- Water is unchanged on all 15 real photos. O6's far water goes to chroma 0.002 (grey): water need not be blue (Jake, 25 Oct 2026).
- Guards (tune_eval, aquacolorfix_eval):

| Check | Before A2 | With A2 |
|---|---|---|
| m5 dE | 12.2 | 11.0 |
| m6 dE | 27.2 | 26.5 |
| O6 chart mean chroma | 0.076 | 0.010 |
| AquaColorFix mean dE, pairs 1-5 | unmeasured | 10.84 (10.53 after the gate fix below) |
| Grain r14 / r03 / m5 / pl1 | unmeasured | 1.72x / 1.85x / 2.05x / 1.36x |
| Neutral grey ramp max chroma | unmeasured | 0.01 |

- More seagrass (Jake gave three photos, 25 Oct 2026: `pl4` seagrass-900x500, `pl5` sgg_caro3, `pl6` TOF1). Plant pixels, OKLab hue (chroma):

| Box | Original | Before A2 | With A2 |
|---|---|---|---|
| pl3 near | 123 (0.059) | 91 (0.060) | 90 (0.060) |
| pl3 mid | 141 (0.060) | 104 (0.051) | 101 (0.050) |
| pl4 near (olive) | 99 (0.027) | 73 (0.035) | 68 (0.036) |
| pl5 near (green) | 144 (0.077) | 134 (0.059) | 128 (0.053) |
| pl5 mid (green) | 149 (0.093) | 132 (0.078) | 117 (0.066) |
| pl6 near, turtle | 133 (0.056) | 110 (0.051) | 104 (0.050) |
| pl2 kelp blades | 162 (0.061) | 110 (0.031) | 100 (0.030) |

  - The cast step before A2 causes most of the shift toward yellow: 10 to 32 degrees. A2 step 2 adds 1 to 6 more, and 15 on pl5 mid.
  - Colour alone cannot tell the olive reef (needs red) from green seagrass (keeps green). Their green excess overlaps: seagrass 0.14 to 0.89 relative, O4 reef 0.52.
  - Green plant protection: not adopted (Jake, 25 Oct 2026: today's seagrass already looks good). What was found:
    - Stage check (plant-pixel hue): the physical restoration keeps the green (pl3 mid 141 → 129). The legacy filter's cast step and red rebuild make it yellow (107). With the cast off it is 126; with the red rebuild off, 121. The same two stages turn the O4 reef brown (cast off 143, rebuild off 145, against 127).
    - Vision scene labels (VNClassifyImageRequest) separate the scenes: the plant/grass/seaweed/foliage score is 0.10-0.24 on seagrass, 0.07 on sargassum, and 0.02 or less on the other 34 images.
    - A hue floor on green plant pixels in those scenes (Python) moved pl3 92 → 110 and pl6 109 → 118, and left O4 and sargassum as they were.
    - Cost: one more model call per photo (Mac: 95 ms the first time, then 25-33 ms; iPhone unmeasured). The margin between pl3 (0.10) and sargassum (0.07) is thin.

#### A2 gate fix: open water with the sun (25 Oct 2026)
- Found with stills from the Tune_25_Oct clips (two per clip, at 30% and 70%), run as photos. Step 1 got full strength on open-water frames:
  - v1 and v3 (hammerheads, sun above): the pink ring around the sun got stronger, and the sunlit water turned cream.
  - v2 (green water, manta): the top turned lilac.
  - v4_70 (dark cave, ray): the ray turned orange.
  - Mean dE76 against pre-A2: 9 to 13 on these frames.
- The pink ring itself is older than A2: it shows in the pre-A2 output too.
- Cause: in these frames the near pixels are darker water. They pass the distance check on brightness alone.
- Fix: step 1 needs near pixels less saturated than the water (OKLab chroma / L).
  - The near/far saturation ratio gives full strength below 0.92 and none above 1.02.
  - Measured: O6 0.84; open-water frames 1.09 to 3.34.
  - A plain chroma ratio was tried first. It failed because chroma falls with brightness: v2's dark near water read 0.74.
- The far colour needs a real tint: far chroma 0.03 (none) to 0.04 (full). v4_70's cave reads 0.021.
- Tint floor 0.3 → 0.5. O1 (strength 0.35) only lost its blue water to teal, and its reef turned pink.
- Result on 40 images (real set, AquaColorFix O1-O3 and O5, guard set, m5, m6, O4, O6, 10 clip stills):
  - Under 0.5 mean dE76 from pre-A2: O1, v2, v4 and all 15 real photos except r01, r05, r07, r10, r11, r14 and r15. Those seven change by 0.6 to 4.2, from step 2 (step 1 is 0 on every real photo).
  - O6, O4, m5 and m6 keep the A2 gains.
  - The guards above are unchanged. AquaColorFix pair 1 went 10.59 → 9.05.

#### A2 for video (25 Oct 2026): step 2 only, weighted by colour
- A video frame renders with one constant depth, so step 2 cannot fade by depth.
- Prototype (`a2_video.py`, on the video-path output of the stills):
  - A plain excess baseline, with no fade, fails both ways. At the 90th percentile of the far water's excess, red lands on the water (v1_70 water p99 dE76 11). At the 98th, the water is safe, but the O4/m6 reef gets only a third of the red (hue 124; photo rule 106).
  - A colour weight works: a pixel gets red by its OKLab a,b distance from the scene's water (none at 0.05, full at 0.10). Water p99 dE76 is 1.2 at most, and the reef reaches hue 114. At 0.04 to 0.08, m5's water took red (p99 5.0).
  - Step 1 on the video path greyed v5_70, a reef-bottom clip, by eye. The photo gate blocks v5 (saturation ratio 1.09), but the video-path output passes it. So step 1 stays off in video.
- App:
  - Each scene keeps one keyframe: the middle kept keyframe with a fit, at 320 px, with its depth map at 160 px.
  - At render time, the keyframe goes through the video path with the current settings. The far pixels' mean gives the water a,b and its excess. These are made from the settings in use, so a slider that moves the water moves the reference too.
  - The values are cached per scene and settings. They mix across the scene fade like the other values.
  - Kernel `UnderBlueObjectColourVideo`; CPU mirror `FinishingMath.objectColourVideo`.
- Harness (`HT_EVAL_VIDEO_A2=1`: `videobase`, `videoa2`; the still is its own keyframe), 40 images:
  - m6 and O4 reef hue 140 → 133. By eye, the reef turns brown like the photo path, and the water is unchanged.
  - Open-water stills (v1-v3, r12, r13): mean dE76 0.0, water p99 0.3-0.8.
  - Some far non-water pixels take red: r11 (p99 16.5), pl5 (9.8), r04 (8.1). Their mean dE76 is 0.2 to 1.6. By eye, r11's fan and r04's anemone look natural; pl5's seagrass gets a little more golden (the open green-plant item).
- Clips (videosim on the Mac, the five Tune_25_Oct clips, a frame every 2 s, against 09abd02):
  - v1-v3: mean dE76 0.1 per frame, about the JPEG noise.
  - v4: up to 0.5. v5: up to 0.6 (p99 5.7).
  - Largest frame-to-frame jump in the change: 0.4, so no flicker.
  - No clip has an olive reef like O4, so the strong case is checked on stills only.

#### Video reef colour: the scene fit (29 Oct 2026, branch `video-reef-colour`)
The video m6/O4 reef stayed olive (hue 133; photo path 93). The 26 Oct note said video needs per-pixel depth. That was only part of it.

Measured on the harness (`HT_EVAL_VIDEO_A2=1`, m6 reef box, linear sRGB green excess G − (R + B)/2):

| Path | Reef excess | Water excess | Reef hue |
|---|---|---|---|
| Photo, before A2 | 0.050 | 0.016 | 127 |
| Video (`videobase`) | 0.036 | 0.035 | 140 |

- With one constant depth (0.92), the water stays greener and the reef less green. Step 2 adds red only above the water's excess, so the reef got almost none.
- The photo depth rule on the video-path colours also leaves the reef olive (hue 130). So per-pixel depth alone does not fix it.
- A softer floor per pixel (no floor where the colour is far from the water) gave the reef hue 108. But it turned the green seagrass yellow: pl5 mid 126 → 93, pl6 107 → 87. On video colours, reef and seagrass overlap (hue 140 and 127-131).

Fix: fit the video rule to the photo rule on the scene's keyframe.
- The keyframe (320 px, depth map 160 px) goes through the video path, as before, and also through the photo path: the scene plan with the keyframe's own depth, before the step.
- The photo rule on that frame gives each pixel's wanted red.
- Two values of the video rule are fitted to it, least squares over the frame:
  - the floor: 21 steps from 0 to the water's excess;
  - a gain on `redFromGreen`, 0 to 1.
- The colour weight still keeps the water out. The kernel is unchanged; only the scene values change.
- Below depth trust 0.5 there is no fit: the photo rule itself uses the colour rule there.
- Code: `RestorationEngine.fittedVideoObjectColourValues`, `videoObjectColourValues(keyframe:...)`. The harness `videoa2` calls the same function.

Results, 40 images (OKLab chroma / hue of the box median; plant boxes count only plant pixels):

| Box | Video before | Video after | Photo path |
|---|---|---|---|
| m6 reef | 0.048 / 132 | 0.040 / 98 | 0.053 / 93 |
| O4 reef | 0.047 / 131 | 0.040 / 96 | 0.055 / 93 |
| pl2 kelp blades | 0.044 / 109 | 0.044 / 101 | 0.031 / 103 |
| pl3 seagrass near | 0.068 / 94 | 0.069 / 93 | 0.062 / 92 |
| pl5 seagrass near | 0.057 / 127 | 0.056 / 125 | 0.061 / 134 |
| pl5 seagrass mid | 0.071 / 125 | 0.064 / 115 | 0.073 / 119 |
| pl6 seagrass, turtle | 0.047 / 107 | 0.045 / 101 | 0.053 / 110 |

- The plants now move about as much as on the photo path (pl5 mid: photo 132 → 119 from A2, video 125 → 115).
- Change against the video before, mean dE76 / p99 / p99 of the far pixels:
  - m6 1.73 / 11.8 / 0.0, O4 1.69 / 11.4 / 0.0.
  - m5 0.73 / 6.2 / 1.0: less red (gain 0.79). Sand and chart grey are unchanged; the sand's pink (hue 358) is older, from the video path.
  - pl2, pl5, pl6: 0.41-0.55 / 3.9-7.4 / 2.1-2.8.
  - The other 34 images: 0.30 or less. Open-water photos and clip stills (r01, r07, r10-r14, v1-v3): 0.01 or less.
- Clips (videosim, the five Tune_25_Oct clips, a frame every 2 s, against `main`): mean dE76 per frame 0.26 or less, frame p99 2.8 or less, largest jump between frames 0.12.
- O4 as a clip (6 s pan, 1080p): reef hue 127-133 → 94-102 over the clip, water hue 228-232 unchanged, largest jump 0.03. By eye the reef turns brown like the photo and the small fish more orange.
- Cost: one more 320 px render per scene and settings, cached with the values. Not measured on the iPhone.
- Tests: `RestorationTests` 89 run, 1 skipped, 0 failed (new: `testVideoSceneFitFollowsThePhotoRuleOnTheKeyframe`). The Mac app builds.

#### Keep colour: the residual cast (29 Oct 2026, merged to `main` 30 Oct after Jake's iPhone check)
Jake: Natural 80 looks a bit washed white on a green-teal clip (`tune/video/Tune_20_Oct/2017-01-08 01.21.36.MOV`).
- Not a regression: mean L* and chroma are flat from 1.1.3 to 1.1.7 (14 clips).
- Cause found on the stills: the restored path used the source cast gains. The restoration had already taken part of the cast, so the cast came off twice. c01_9 restored mean chroma: 0.053 before the cast step, 0.008 after it.
- Fix: the plan carries `residualCast`. It is the share of the source cast left in the restored image, measured on one 640 px render of restore(). The restored path takes the cast gains to this power.
  - A cast is the mean colour's log channels less their mean. The restored cast is projected on the source cast and clamped to 0-1.
  - Photos: measured once, after the subject mask. Video: each scene plan, on its kept keyframes, then the mean. One frame's share moved from 0.85 to 0.60 within one scene.
- Rejected: a fixed power 0.5 (pl1 green water hue 185 → 165, into the green band). Also a plan estimate of the restored mean instead of the render (pl1 → 172).
- Photo results (42 stills, Natural): c01_9 frame chroma 0.035 → 0.046, pl1 water hue 185 (unchanged), v2 219 → 213, m6/O4 reef hue 93 → 101. AquaColorFix O3 6.22 → 6.69, O4 9.51 → 10.33. Blue water unchanged.
- Video path on the stills (`videoa2`): c01_9 0.058 → 0.074, water hue 217 → 200. pl1 177 (unchanged), m6 reef 98 → 94.
- The clip itself (videosim, Natural 80): scene share 0.82, mean chroma 0.0527 → 0.0550, no visible change, no new flicker. The scene mean plan takes less cast than a still's own plan, so the double cast is small here. Jake accepted this result (29 Oct 2026). The clip's remaining washed look has another cause, not found yet. The candidate is redRebuild: off, c01_9 went 0.035 → 0.048.
- Cost: one 640 px restore render per photo, and one 320 px render per kept keyframe at video analysis. Not measured on the iPhone.
- Tests: `RestorationTests`, `VideoRestorationTests`, `PresetTests`: 121 run, 2 skipped, 0 failed (new: `testResidualCastKeepsTheCastFromComingOffTwice`).

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

#### B2 depth trust rule (25 Oct 2026)
- Trust = the correlation of the depth map with the colour water share (`waterShare`), at depth-map size.
- Measured on 18 photos (960 px):
  - Depth and colour agree on the layout: DSC03545 0.83, r15 0.87, DSC03687 0.87, DSC03656 0.74, m5 0.89, m6 0.86, r03 0.65, r14 0.91.
  - Open water, where depth invents a layout: r13 0.11, r01 0.36, r07 -0.20, r10 -0.04, r11 0.00, r12 0.30, O6 0.35, clip stills v1 -0.38, v2 0.27, v3 -0.40.
- So: no trust below about 0.45, full trust above 0.6. The gap is 0.36 to 0.65.

#### B2 rule 1, the subject light removal (E18 ring): no go (25 Oct 2026)
- Tried: on trusted photos, the colour step runs with and without `subjectTone`, mixed by a depth mask. Far water gets no removal. The colour kernel kept one image input (a second input broke iOS before).
- Ring metric (DSC03545 at 2000 px; water chroma 2-10 px around the two pale fish, over 25-40 px out; scale of a 1000 px image): source 0.917, ours 0.786.
  - Removal off everywhere, legacy path: 0.869. This is the ceiling.
  - Fade at depth 0.85-0.95: 0.797. At 0.78-0.88: 0.806.
- Why so little: the depth map is too coarse. The fish read 0.75 and the water 0.98, but the ring band averages 0.93 (10th percentile 0.75). The ring is only 1-4 depth pixels wide, so the upscaled map blends fish and water there.
- Other photos changed more than the target: r03 p99 dE76 14.8, DSC03656 17.3, m6 mean 1.5.
- Reverted. A fix for E18 needs a sharper subject edge than the depth map gives.

#### B2 other rules: no visible defect to fix (25 Oct 2026)
- B1 said depth beats colour on large areas: r15's diver, and the bright surface water and sun glare at the top of DSC03687 and DSC03656. Checked our output on those by eye and in numbers:
  - DSC03656 sun glare (box median, OKLab L / chroma / hue): centre 0.96/0.055/196 → 0.997/0.001/197; ring around it 0.92/0.120/197 → 0.97/0.040/197. It stays cyan-white, and white glare looks natural.
  - DSC03687: the top looks natural by eye.
  - r15: Jake accepted the diver on 20 Oct 2026.
- So the water tone, white reference and local veil switches have no visible target. B2 stops here; the depth trust rule is recorded for later use.

## Pink ring around the sun (measured 25 Oct 2026, fixed 26 Oct 2026)

Seen on the Tune_25_Oct clip stills v1 and v3 (hammerheads, sun in frame). The 25 Oct note said it was there before A2. That was wrong; see "Cause and fix" below.

Measure: median OKLab a (x1000; negative = green, toward 0 = less green, then pink) by distance from the sun, as a share of the width. A share of "pink" pixels (hue 300-40) read 0% on these frames, so it misses the faint ring. On DSC03656 it caught pink coral instead.

| v1_30 | 0.05-0.15 | 0.15-0.25 | 0.25-0.35 | 0.35-0.45 |
|---|---|---|---|---|
| original | -87 | -80 | -81 | -77 |
| physical restoration only | -86 | -77 | -78 | -74 |
| legacy filter only (`current`) | -70 | -64 | -64 | -61 |
| ours, photo (`combined`) | -13 | -35 | -43 | -46 |
| ours, video path | -61 | -55 | -54 | -51 |

- v3_30: the same pattern, weaker (photo -90 against legacy -94 at 0.05-0.15).
- Neither path alone makes it. The legacy filter with any one stage switched off stays at -68 to -70. So the shift comes from the combination: most likely the finishing step on the physically restored image (`filter.finishing(physicallyRestored, …)`), which no variant shows on its own. Not checked yet.
- Next: render that finished restored path as its own variant, and switch its stages off one at a time.

### Cause and fix (26 Oct 2026)
- Harness: `HT_EVAL_RESTORED_ABLATE=1` adds `finrest` (the finished restored path alone) and `rab_<stage>` (one stage off in the restored values). v1_30 near the sun: legacy -74, finished restored -72, combined -10. So the shift comes after the two paths meet.
- Pre-A2 sources (09c99b4): v1_30 combined -72, v1_70 -75. **A2 makes the pink on v1.** v3 reads -90 before and after, so v3's look is a separate matter (below).
- Mechanism: A2 step 2 adds red where depth reads near. In open water depth invents a layout: by the sun it read 0.69-0.77, so the sunlit water got red. The video rule (colour weight) left it as it was (-63 before and after).
- Fix: photo step 2 uses the depth trust rule (B2). Below a trust of 0.5 it takes the video rule (red by colour distance from the water) on the frame after step 1. Step 1 keeps its own gates, so O6's chart fix stays.
- Result: v1_30 -72, v1_70 -75 near the sun, as before A2. The guards are unchanged to the last digit: m5 11.0, m6 26.5, O6 chart 0.010, AquaColorFix 10.53 (pairs 1-6), grain, plants, black gear.

### The sharp edge of the bright area (Jake, 26 Oct 2026: brightness is fine, the edge is too sharp)
- First tried the brightness: our sunlit water is about +0.08 L brighter, but across the whole water, not only near the sun. The fall-off from the sun keeps the original's shape. Keeping each water pixel's luminance, then its OKLab L, after the water tone changed it by 0.02 at most. Reverted.
- The edge is a chroma step. v3_70 chroma by distance from the sun (share of width 0.10 / 0.20 / 0.25 / 0.30 / 0.40): original 0.154 / 0.152 / 0.146 / 0.145 / 0.136, ours 0.099 / 0.100 / 0.111 / 0.122 / 0.099. A pale disc inside a bluer ring. With the red rebuild off, the legacy path reads 0.124 flat.
- Cause: green and blue both clip in the blown-out disc (17-21% of v3), so their ratio reads 1 and the rebuild's hue gate opens fully there. The ratio drops quickly where the clipping ends, which draws the ring.
- Ruled out: the "brighter than the water" test (waterLit 0: no change), and the video open-water rule for photos (`openWaterRed`'s rebuild part: no change).
- Fix (`UnderBlueFinishColor`, mirror `FinishingMath.color`): the rebuild fades out as the smaller of the source's green and blue goes from 0.7 to 1.
  - Fading on the brightest channel instead put new steps into v1, whose blue clips alone (v1_70 photo 0.043 to 0.092 across the edge).
  - Fade start: 0.6 left the m5 chart a little less grey; 0.8 brought a dip back on v3. 0.7 is between.
- Result, v3_70 chroma at the same distances: photo 0.133 / 0.129 / 0.124 / 0.129 / 0.107, video 0.132 / 0.128 / 0.121 / 0.123 / 0.111. v1 is unchanged.
- Guards, against the state before: r14 sand grain 1.72x to 1.61x (video 1.59x to 1.32x); m5 chart grey row photo 0.009 to 0.010, video 0.043 to 0.055 (Sea-thru 0.079). The rest is unchanged.
- By eye: v3_70's disc is cyan like the original, with a much softer edge. A faint pinkish rim stayed at the outer edge on v3_30 (photo) and at the lower edge of v1's bright area. Fixed later the same day; see "The pink rim around the sun".
- Jake checked the clips on the iPhone (26 Oct 2026). At the default intensity (80) the sharks get a dark outline; it does not look wrong, and at 50 it looks fine. He accepts it as it is: deep water with little light. This is the known video halo from the local veil (22 Oct 2026, mitigated by `liftDark`; photos avoid it with the Vision subject mask). Not worked on.

### The pink rim around the sun: fixed (26 Oct 2026)
- Seen: a pink-beige ring at the edge of v3_30's bright disc, and a band under v1_30's bright area. Photo and video path.
- Measure: OKLab a on a 20 px wide vertical line through v1_30's sun (x 150-170, y 300-414, 960 px). Before: photo a -14 for y 312-342, then -29 by y 360. Video: -13, then -30.
- Stage sweep (`HT_EVAL_RESTORED_ABLATE`): the step goes with any one of these off on the restored path: red rebuild, cast gains, subject light removal (`subjectTone`). The legacy path has no step.
- Probe of the finishing gates on the same line:
  - The restored image (the finishing input) already has the cliff. Luminance falls 0.096 → 0.050 between y 342 and 366, while the original falls smoothly (L 55 → 51). Depth is flat there (0.95).
  - Removing the backscatter steepens the glow, because near the sun the glow is only a little above the backscatter.
  - Inside the glow the pixels read "not water" (water-like 0.23-0.33, against 0.91-0.96 outside). The subject light removal takes their blue (v1_30: blue × 0.44), so the glow turns pink. The class flips at one radius, which draws the ring.
- Fix: on the restored path, the subject light removal scales with the depth trust (`RestorationEngine.trusting`). Open water (trust 0) takes none; the legacy path still removes the subjects' cast.
  - Photos: trust from the photo's own depth.
  - Video: trust per scene, from its keyframe's own depth map (`sceneTrust`, cached). A scene without a keyframe keeps full trust.
  - A constant-depth plan with no trust given keeps full trust (it cannot tell).
- First try: video always untrusted. AquaColorFix as video went 10.98 → 11.39, so video now uses the scene trust.
- Result on the same line: photo a -35 flat; video -37 to -41. By eye, the glow stays cyan on v1_30 and v3_30, with no pink band.
- Guards against the state before:
  - AquaColorFix unchanged on both paths (10.53 photo, 10.98 video).
  - Neutral surfaces, black gear, plants, grain and the neutral ramp are unchanged.
  - Open-water photos move a little: r07 nearRG 0.38 → 0.35, far chroma 25.7 → 27.9; r10 nearRG 0.52 → 0.48; r04, r11-r13 and m3 by 0.1-0.4.

### Too-bright sunlit areas in clips (Jake, 25 Oct 2026: "the bright parts are too bright and do not blend naturally")

Measured on the same stills, 960 px. OKLab L median by distance from the sun (share of width); clipped = any channel at 250 or more.

| frame | variant | clipped | L at 0-0.05 | 0.05-0.1 | 0.1-0.15 | 0.15-0.2 | 0.2-0.3 | 0.3-0.4 | largest drop |
|---|---|---|---|---|---|---|---|---|---|
| v1_30 | original | 9.0% | 0.74 | 0.74 | 0.72 | 0.69 | 0.71 | 0.70 | 0.04 |
| v1_30 | video path | 0.0% | 0.84 | 0.83 | 0.82 | 0.77 | 0.80 | 0.79 | 0.05 |
| v1_70 | original | 15.0% | 0.76 | 0.76 | 0.75 | 0.75 | 0.74 | 0.72 | 0.02 |
| v1_70 | video path | 0.0% | 0.85 | 0.85 | 0.85 | 0.84 | 0.83 | 0.81 | 0.02 |
| v3_30 | original | 17.5% | 0.90 | 0.90 | 0.90 | 0.90 | 0.86 | 0.77 | 0.09 |
| v3_30 | video path | 17.8% | 0.92 | 0.92 | 0.92 | 0.92 | 0.87 | 0.78 | 0.09 |
| v3_70 | original | 21.5% | 0.90 | 0.90 | 0.90 | 0.90 | 0.86 | 0.79 | 0.07 |
| v3_70 | video path | 12.8% | 0.92 | 0.92 | 0.92 | 0.92 | 0.88 | 0.80 | 0.09 |

- v1: we lift the sunlit water by about 0.10 L, so the area near the sun turns flat and whitish.
- v3: the source is already blown out (17.5-21.5% clipped). We keep the flat plateau, and it ends in a 0.09 drop instead of a soft fall-off.
- The photo path (`combined`) matches the video path within 0.02 here.
- Followed up on 26 Oct 2026: see "The sharp edge of the bright area" above.

## Stage D — floating particles

Kind: measurement. No new removal step is planned yet. Jake asked for this check on 24 Oct 2026.

### What we know

- Photos have no particle step. Video has a prototype, `Prototypes/VideoCleanup/ParticleFilter.swift` (since 26 Oct 2026 `UnderBlue/Processing/ParticleFilter.swift`, wired into the exporter but off by default; see D2).
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

#### D2 result (26 Oct 2026): go

Bench: `particle-bench/chain.swift` (build `build_chain.sh`). Colour is the app's video path: `VideoRestorationAnalyzer` on the whole clip, then `combined(moment:)`, Natural Dive at 0.8. Every variant is scored after one render into 420v; motion comes from the original frames. "Removed" counts the reference's drifting specks whose peak drops below half.

| Segment | Variant | Drifting specks per frame | Removed | Small subjects kept | Dark small kept | Pixels changed > 2 |
|---|---|---|---|---|---|---|
| S3 c1 fish, 0-4 s | original | 5.47 | | | | |
| | particles on the original | 3.12 | 46.4% | 100% | 100% | 0.031% |
| | colour only | 2.41 | | | | |
| | **particles, then colour** | **1.12** | **64.6%** | **100%** | **100%** | 0.031% |
| | colour, then particles | 1.23 | 41.4% | 99.9% | 100% | 0.239% |
| S1 c3 snow, 29.5-35.5 s | original | 144.57 | | | | |
| | particles on the original | 42.17 | 65.7% | 99.2% | 99.0% | 0.098% |
| | colour only | 45.33 | | | | |
| | **particles, then colour** | **4.34** | **86.5%** | **99.9%** | **99.8%** | 0.058% |
| | colour, then particles | 12.15 | 43.4% | 99.9% | 100% | 0.029% |

- Go rule met: after colour, the planned order removes more than before colour (64.6% and 86.5%, against 46.4% and 65.7%), and small subjects stay at 99.9% or more.
- Colour alone already removes most visible specks (S1 145 to 45 per frame, S3 5.5 to 2.4): the water calm smooths them, as D1 found.
- The other order (colour first) is worse on both segments. The planned order holds.
- By eye (crops at 2x): every small dark fish in the S3 window stays; the S1 snow window has fewer specks.
- The prototype's own numbers (Mac M3): 126-204 fps at 1080p, 63-67 fps at 4K, 3 frames of lag.

#### D2 in the exporter (26 Oct 2026): wired, off by default
- `ParticleFilter.swift` moved to `UnderBlue/Processing/`. `VideoExporter` pushes each frame through it before colour and writes what it returns (3 frames later); the end of the source flushes it. SDR only (HDR unmeasured); off with the Original preset.
- iPhone 17, device test, Natural Dive 0.8, 10 s (600 frames) each:

| Clip | Filter | Export | Frames per second | Peak memory |
|---|---|---|---|---|
| 1080p60 c3 (0-10 s) | off | 32.2 s | 18.7 | 449 MB |
| 1080p60 c3 (0-10 s) | on | 54.8 s | 11.0 | 1023 MB |
| 4K60 13832750 (0-10 s) | off | 146.6 s | 4.1 | 1865 MB |
| 4K60 13832750 (0-10 s) | on | 168.0 s | 3.6 | 1882 MB |

- The filter builds on iOS (its kernels compile from source at run time). Both outputs have 600 frames. With it on, 0.02-0.08% of the pixels change, by 5-15 levels at most (this stretch has few specks).
- The added time per frame is about the same at 1080p and 4K (36 ms). So it is likely a wait for the GPU in the filter, not the pixel work. Not checked.
- Decision (Jake, 26 Oct 2026): off by default (`VideoExporter(removesParticles:)` false). Turn it on when the cost is down to about +20% time and +100 MB. Photo particles come first.
- Jake (26 Oct 2026): record only. No more video particle work for now.

### D3 — photo particles (started 26 Oct 2026)

Jake (26 Oct 2026): photo particles matter more than video. Photos he gave: `licese-free-images/candidates/pexels-carlos-jamaica-173742194-11061223.jpg` (p1, divers and bubble columns), `licese-free-images/joan-li-Cua2o7Yc8YM-unsplash.jpg` (p2, wreck in blue water), `eval/real/IMG_7260.JPG` (p3 = r08, turtle), `eval/real/IMG_7262.JPG` (p4 = r14, batfish).

What the photos show (1920 px renders, 100% crops):
- The main type is the soft round orb: out-of-focus backscatter, about 10-15 px across at 1920 px, a few levels brighter than the water. p2 and p1 have them.
- p1's bubble columns are bright, sharp, clustered groups. They must stay.
- p3 has thin diagonal streaks (about 20-30 px long, 1-2 px wide). Our output widens and softens them; about as visible.
- Our water shows a cloudy, blotchy texture on p2, p3 and p4; on p2 the blotches look like more orbs. Checked on 26 Oct 2026 (below, "Water mottling").

D1's pair measure (each isolated group of the original, its peak in our output over its peak in the original):

| Photo | Groups | Median ratio | p90 |
|---|---|---|---|
| p1 | 604 | 0.98 | 1.22 |
| p2 | 40 | 1.52 | 1.79 |
| p3 | 25 | 0.44 | 1.35 |
| p4 | 60 | 0.33 | 1.32 |

Which steps lift the orbs (p2, median ratio): ours 1.52; legacy path 1.41; physical restoration alone 1.07; finished restored path 1.75. Legacy path with one stage off: tone 1.17, water tone 1.19, cast 1.22, local stages 1.28, all finishing off 1.13. So the lift is spread over the contrast and colour steps: it is what the correction does, not one fault. Removal before colour is the way.

First prototype (Python, scratch script `orbs.py`, not kept; round 2 onward is in `scripts/photo-orbs/`): on the source luma, peaks of a band filter (Gaussian 3 px minus 10 px) above max(1, 1.2 x local noise) and below 30 levels; in water (colour share 0.6 or more), off the Vision subject mask; a flat ring at 10 px (spread below half the peak); round (half-max region fills 55% or more of its box, 320 px at most). Fill: the mean of a ring at 1.3 x the radius, blended over a soft disc. The filled photo then goes through our harness.
- Found: p1 48, p2 20, p3 9, p4 16.
- By eye: filled orbs are gone in our output (p2 upper left, p1 open water), and p1's bubble columns stay.
- Misses: several faint orbs on p2. Risks: small lone bright dots next to p1's bubble columns, one spot next to a diver's arm, one on p2's wreck.

Rounds 2-5 (26 Oct 2026, `scripts/photo-orbs/orbs2.py` and `orbs_eval.py`). Harness: `HT_EVAL_RENDER_DIR` renders an edited copy of the source with the source's own analysis and plan (`altcombined`), so only the edit differs. Without it the edited copy changed the analysis, and 45% of p2's pixels moved.

| Round | Change | Spots removed p1 / p2 / p3 / p4 | By eye |
|---|---|---|---|
| 2 | Sizes 2, 3, 4.5 px; threshold 2.5 x the local band spread; no bubble clusters | 310 / 190 / 91 / 87 | Flat patches on p1's reef, small bubbles erased |
| 3 | Sizes 3, 4.5, 6.5 px; smooth background (ring spread at most 2 x the noise) | 129 / 98 / 57 / 44 | p2's water clean; p1's reef still patched |
| 4 | Soft, not sharp (fine band at most 0.6 x the peak); depth must read far where depth is trusted | 37 / 64 / 15 / 10 | p1's bubbles all kept; one reef patch left |
| 5 | Subtract only the smooth bump (per channel, Gaussian minus the ring mean) instead of a flat fill | 37 / 64 / 15 / 10 | No patch: the texture under a spot stays. p2's visible orbs gone, one faint one left |

Round 5, scored on our output (orbs counted with the round 4 rules, water only, off the subject mask):

| Photo | Orbs in ours | With the bump subtracted | Pixels changed > 3 |
|---|---|---|---|
| p1 | 63 | 40 | 4.98% |
| p2 | 55 | 27 | 5.61% |
| p3 | 9 | 12 | 0.13% |
| p4 | 25 | 18 | 0.14% |

- "Pixels changed" is mostly a 1-3 level reshuffle of the noise by the local steps (the difference map shows it as fine grain), not visible.
- Depth trust (B2 rule) on these photos: p1 0.00, p2 0.00, p3 1.00, p4 1.00. So the depth gate protects p3 and p4 only; p1's reef is kept by the soft and smooth tests and by the bump subtraction.

Next: the app. Plan: detect on the source at 1920 px (blurs on the GPU, the spot tests on the CPU), build the bump correction at that size, scale it up and subtract it from the source before colour. The analysis and the plan stay on the original. Photos only, preview and export alike, once per photo. Then the cost on the iPhone (20 MP and 48 MP).

#### D3 in the app: a Labs switch (26 Oct 2026)

`UnderBlue/Processing/PhotoOrbs.swift` ports round 5. `PhotoProcessor` runs it only while the Labs switch "Remove backscatter spots" (Help) is on. Off by default. Detection runs once per photo, on the full source, the first time it is needed. Preview and export use the same spots. The Original preset is left as it is. Harness: `HT_EVAL_ORBS=1` adds `orbs`, and `HT_EVAL_ORB_MAXBUMP` overrides the cap.

Port fixes:
- The water share is the alpha channel of `FilterEngine.waterShare`. The first port read red (luma) and found almost nothing.
- Blurs need 32-bit float. The engine context is half float, which steps by 0.125 levels above 128. Against the 0.8-level floor it cut the finds to 30/38/6/5 (Python: 37/64/15/10). A Python check with half-float blurs gave 31/37/5/3.
- The rules read sRGB luma, as in the prototype. Removal factors stay in the working space.
- Depth trust for the far gate: the correlation of depth with the share (alpha), as in the prototype. See the next part for why the colour step's trust differs.
- After these fixes: 37/55/13/14 finds, about 0.35 s per photo on the Mac. Water orbs go; p1's reef and bubbles stay (mean change 0.11 in the subject mask, 0.20 in bubble clusters).

Depth trust reads luma, not the share (found while porting):
- `RestorationEngine.depthTrust(_:plan:correction:filter:)` correlates depth with the share kernel's luma output (channel 0), not the share (alpha). The 25 Oct table above came from the share.
- Switched to the share as a test, the guards got worse:
  - AquaColorFix pairs 1-5: 10.53 → 10.63 (p3 6.25 → 6.73); p6 12.61 → 13.02.
  - O6 chart grey (photo): 0.010 → 0.029.
  - r01 nearRG: 0.55 → 0.47.
- By eye, the O3 sunfish turned teal, and the O6 reef and sand turned cyan.
- Correlation (luma / share): O3 0.67 / 0.32, O6 0.63 / 0.35, v1_30 0.06 / -0.38, v3_30 0.08 / -0.40, m5 0.90 / 0.89.
- With the share, O3 and O6 lose trust. Luma keeps the sun stills untrusted. So luma stays, and the code comment says so.
- The sun stills read the same either way: v1_30 -72, v1_70 -75.

Small fish: the blocker, and the cap:
- On the AquaColorFix photos, the uncapped detector touched small fish. I labelled all 125 changed regions by eye:

| Photo | Changed regions | Fish faded or erased |
|---|---|---|
| O1 (fish school) | 80 | 34 |
| O3 | 12 | 1 |
| O4 | 19 | 9 |
| O5 | 14 | 0 |

- Three fish got a dark rim.
- Round 5's "good by eye" was wrong: it rested on two crops. The prototype's strongest finds on p1 were reef patches and a bubble patch.
- Tried as fish tests:
  - Size does not separate them. Median radius: fish 9.8 px, orbs 10.4 px.
  - Elongation does not separate them either: 1.36 against 1.28.
  - Edge sharpness fails too: the blurred fish are softer than the orbs.
- Brightness separates them. Bump (smooth luma at the centre over the ring around it), p10 / median / p90:
  - fish: 8.6 / 17 / 26;
  - orbs: 1.2 / 2.5 / 5.6.

| Cap | O1 fish | O4 fish | O3, O5 fish | AquaColorFix orbs removed | Bright real orbs left on p2 |
|---|---|---|---|---|---|
| none | 34 | 9 | 1 | 44 of 44 | 0 |
| 10 | 3 | 4 | 0 | 44 of 44 | 7 |
| 8 | 0 | 4 | 0 | 41 of 44 | 9 |
| 6 | 0 | 3 | 0 | 41 of 44 | 13 |

- Jake chose 8, behind a Labs switch.
- At 8, the four O4 fish are dim green fish, 18-51% fainter. By eye, the O1 school and the O4 fish look unchanged.
- The cap also drops 9 reef finds on p1.
- Finds at 8: p1-p4 20/46/13/13; O1-O6 23/0/8/12/18/1.

Open: the cost on the iPhone (20 MP and 48 MP).

### Water mottling (26 Oct 2026)

Measure: in water (share 0.8 or more, off edges), the std of the luma band Gaussian 3 px minus 12 px, as a share of the 12 px mean (1920 px). Ratio over the original.

| Path | p2 | p3 | p4 |
|---|---|---|---|
| ours (photo) | 2.16x | 1.69x | 0.75x |
| legacy path | 1.80x | 1.18x | 0.79x |
| legacy path, tone stage off | 1.07x | 0.89x | 0.92x |
| finished restored path alone | 5.83x | 2.33x | 0.53x |

- Two sources:
  - The tone stage (S-curve around the scene median) amplifies small brightness changes, because the water sits near the median.
  - The restored path makes them larger again. Removing the backscatter leaves less light, so the same unevenness becomes a larger share of it.
- p4 (deep dark water) is not mottled.
- Tried: a wider water calm blur (`calmBlurRadius` 3 → 8 or 12 / 1200 of the short side).
  - p3 1.69x → 1.01x (8) / 0.67x (12). p2 2.16x → 1.98x / 1.65x.
  - IMG_7400's rays, DSC03656 and v1_30 looked unchanged at 8.
  - But at 8 a faint distant hammerhead on v3_30 (1920 px) was blurred away: a faint silhouette passes the flatness test. Not kept.
- Band strength in the source (median / p90 / p99, % of the local mean): p3 flat water 0.50 / 1.24 / 2.15; p2 flat water 0.74 / 2.96 / 8.30; the faint v3 shark 1.12 / 5.32 / 7.85. So a soft threshold near 2-3% would take p3's blotches and keep the shark's body, but thin its faint edges.
- Next idea: shrink only the weak part of that band in water (a soft threshold, before colour). Done below.

Fix (Jake chose it, 26 Oct 2026): the water core (`UnderBlueWaterCore`, `FilterEngine.waterCore`, mirror `FinishingMath.waterCore`). Photos only; video passes `coresWater: false`.
- After the water calm and before colour, the band between a 3/1200 and a 12/1200 blur (share of the short side) comes off in water (the calm weight's water share).
- Only its weak part comes off: all of it below a relative strength of 0.04 (band luma over wide-blur luma, linear), none above 0.08.
- Mottling, ours over original: p2 2.16x → 2.09x, p3 1.69x → 0.87x, p4 0.75x → 0.43x.
- By eye: p3's clouds are gone. The faint v3_30 hammerhead stays as it was. IMG_7400's rays and DSC03656 look unchanged. p2's blotches soften a little; its orbs stay (they are the Labs switch's job).
- Guards, against the pink-rim fix:
  - AquaColorFix photo 10.53 → 10.61 (p1 +0.14, p2 +0.11, p4 +0.14); water detail 0.96 → 0.93 of ours over A on p1.
  - Local contrast falls a little where water fills the frame (r01 4.43 → 4.32, m6 4.17 → 4.04, m5 8.79 → 8.75).
  - m1 dE 24.6 → 24.5, m6 26.5 → 26.6. Neutral surfaces, black gear, plants and grain are within 0.002 / 1 degree.
  - The harness `uniform` variant also moved (10.98 → 11.04). It calls combined() without `video: true`, so it is not the real video path here.
- Cost: two more blurs per finishing call (both paths) on photos. iPhone time unmeasured.
- Edge fix (Jake, 26 Oct 2026: subjects got rims again; m5 an aura, the napoleon wrasse a dark rim, rings around small fish). Next to a subject the 12 px blur holds the subject, so the water took its light or its dark. The core now runs only where the water share blurred at 36/1200 reaches 0.9 or more.
  - Largest change against no core: O2 47 → 7, m5 255 → 132 (p99 4 → 1). O4/m6 small-fish areas: p99 9 → 7.
  - By eye, O2's fin blob is gone, and O2 matches the build from the morning of 26 Oct.
  - Mottling: p3 1.03x (no core 1.69x), p2 2.10x. AquaColorFix photo 10.61 → 10.58.
  - The manta edge's stair steps in O4 are in the source itself (JPEG blocks), not from the pipeline.

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
