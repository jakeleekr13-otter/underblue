# Camera JPEG input — plan

Status: J1 to J5 done, 23 Oct 2026. iPhone 1.1.4 (build 10) ships the J3 change plus v2 from J5, which fixes the reef on the iPhone too. Agreed with Jake: this ships before the subject work.

## The problem

The same frame gives two different results. It depends on whether the app is handed the camera JPEG or the Sony ARW. The RAW result is the good one. Most people will hand it a JPEG.

Measured on an iPhone 17, commit `5096422`, Natural Dive at intensity 0.8, no subject lift. The region is the non-water part of the frame, the reef or the wreck. Red covers OKLab hue 15 to 70 at chroma 0.05 or more.

| photo | hue, from RAW | hue, from JPEG | red share, from RAW | red share, from JPEG |
|---|---|---|---|---|
| DSC03545 | 113 | 5 | 0.015 | 0.030 |
| DSC03656 | 80 | 52 | 0.111 | 0.405 |
| DSC03687 | 88 | 56 | 0.098 | 0.511 |
| DSC03696 | 71 | 50 | 0.228 | 0.353 |

DSC03545 is a wreck. Its chroma is near zero either way, so its hue reading is noise. The three reefs agree. From a JPEG the result is 20 to 32 degrees warmer. It also holds three to five times as many red pixels.

Jake looked at both and called the RAW result natural.

## Why it happens

The camera applies its own white balance before it writes the JPEG. That pulls the water from teal toward blue. Our pipeline then measures that water and classifies the scene from it.

| photo | input | source water (R, G, B) | G/B | `waterType` | `waterTone` |
|---|---|---|---|---|---|
| DSC03545 | RAW | (0.041, 0.128, 0.313) | 0.410 | 0.133 | (1.174, 1.012, 0.804) |
| DSC03545 | JPEG | (0.098, 0.178, 0.827) | 0.215 | 0.000 | (1.000, 1.194, 0.509) |
| DSC03546 | RAW | (0.037, 0.112, 0.286) | 0.392 | 0.091 | (1.152, 1.022, 0.782) |
| DSC03546 | JPEG | (0.075, 0.129, 0.650) | 0.198 | 0.000 | (0.999, 1.248, 0.466) |
| DSC03656 | RAW | (0.071, 0.220, 0.321) | 0.686 | 0.769 | (1.288, 0.946, 1.074) |
| DSC03656 | JPEG | (0.126, 0.266, 0.607) | 0.439 | 0.130 | (1.104, 1.028, 0.765) |
| DSC03687 | RAW | (0.058, 0.190, 0.316) | 0.601 | 0.579 | (1.280, 0.958, 0.999) |
| DSC03687 | JPEG | (0.114, 0.235, 0.650) | 0.362 | 0.000 | (1.076, 1.058, 0.694) |
| DSC03696 | RAW | (0.047, 0.159, 0.277) | 0.574 | 0.523 | (1.270, 0.961, 0.990) |
| DSC03696 | JPEG | (0.095, 0.194, 0.595) | 0.326 | 0.000 | (1.050, 1.078, 0.665) |

Four readings follow.

- The JPEG's water holds about twice the blue of the RAW's. Red and green move far less.
- So G/B falls, on every pair. The drop runs from 0.195 to 0.248.
- `waterType` follows G/B. It reads 0 on four of the five JPEGs. The pipeline then calls them clear blue water. The RAW of the same frame reads 0.09 to 0.77.
- `waterTone` then takes a different shape. On a JPEG it cuts blue, to 0.47 or 0.51 on the two wrecks. On a RAW it raises red instead, to about 1.28.

Cutting blue is what turns the reef red. The reef holds blue, and removing it leaves the warm part standing.

`waterType` is documented as 0 for blue water and 1 for green or teal (`ColorAlgorithm.md:77`). It feeds `baseCastGains` and `waterRules`. The green-to-blue shift scales with it, so at 0 that shift does nothing.

## The target

The RAW result is the reference. For each pair, a JPEG input should land near the same place as its RAW.

This is a measurable goal. Five pairs of the same frames now sit in `DeveloperMedia/subjectpicker/`.

## Candidates

| # | Idea | Risk |
|---|---|---|
| A | Make the water estimate, and `waterType` with it, less sensitive to a camera's white balance. | It has to hold on every existing set, not only these five. |
| B | Limit how far `waterTone` may cut one channel. | It presses on the symptom. The scene is still classified wrong. |
| C | Detect that the input is a camera JPEG and adjust before the analysis. | Guesswork about what each camera did. |

A is the one to try. B is the fallback if A cannot be made safe.

## Stages

Each stage ends with one artefact that can fail.

| # | Stage | Artefact |
|---|---|---|
| J1 | Reproduce the gap in the harness and record it. The harness reads ARW since 23 Oct 2026. | A table: the five pairs, their water estimate, `waterType` and output reef hue |
| J2 | Find what in the water estimate carries the camera's white balance. | A named quantity, with its RAW and JPEG values on all five pairs |
| J3 | Build candidate A. | The JPEG `waterType` lands within 0.15 of its RAW on four of five pairs |
| J4 | Check the whole gate. | AquaColorFix gate and `m5_eval.sh` run, with the before and after numbers |
| J5 | Check on the device, both inputs. | Screenshots, and a line in `Verification.md` |

## J1 result — the gap is reproduced in the harness

The Mac harness repeats the device gap. Commands: the eval at `HT_EVAL_MAXDIM=4000`,
`HT_EVAL_P3=1`, `HT_EVAL_INTENSITY=0.8`, `HT_EVAL_LOG=1`, Natural Dive, on
`DeveloperMedia/subjectpicker/`. Reef hue and red share are read inside a hand-drawn non-water
mask. DSC03546 has no such mask, so its two output cells are `unmeasured`.

| photo | input | source water (R, G, B) | `waterType` | reef hue | reef red share |
|---|---|---|---|---|---|
| DSC03545 | RAW | (0.041, 0.128, 0.313) | 0.133 | 113 | 0.014 |
| DSC03545 | JPEG | (0.098, 0.178, 0.827) | 0.000 | 197 | 0.009 |
| DSC03546 | RAW | (0.037, 0.112, 0.286) | 0.091 | unmeasured | unmeasured |
| DSC03546 | JPEG | (0.075, 0.129, 0.650) | 0.000 | unmeasured | unmeasured |
| DSC03656 | RAW | (0.071, 0.220, 0.321) | 0.769 | 81 | 0.112 |
| DSC03656 | JPEG | (0.126, 0.266, 0.607) | 0.130 | 59 | 0.433 |
| DSC03687 | RAW | (0.058, 0.190, 0.316) | 0.579 | 90 | 0.088 |
| DSC03687 | JPEG | (0.114, 0.235, 0.650) | 0.000 | 49 | 0.545 |
| DSC03696 | RAW | (0.047, 0.159, 0.277) | 0.523 | 70 | 0.232 |
| DSC03696 | JPEG | (0.095, 0.194, 0.595) | 0.000 | 50 | 0.422 |

Four readings follow.

- The water estimates repeat the first table to three decimal places. The harness and the device
  agree on the input.
- The `waterTone` column of that table is the no-plan path, which the harness logs as `current`. The
  harness repeats all ten of its rows exactly. The photo export uses the restored path, where the
  same gains land within 0.10. `waterType` is the same on both paths.
- On the three reefs the harness reef hue is within 7 degrees of the device, and the red share
  within 0.07. So the Mac may be used to tune this.
- DSC03545 reads hue 197 from its JPEG and 113 from its RAW, but its mask chroma is only 0.011 to
  0.013. That hue is noise, as the first table already said. The wreck is not evidence either way.

## J2 result — the named quantity is the water's OKLab hue

The carrier is the hue of `analysis.waterColor`, in OKLab.

| photo | water hue, from RAW | water hue, from JPEG | shift |
|---|---|---|---|
| DSC03545 | 234.1 | 256.9 | +22.8 |
| DSC03546 | 235.8 | 258.3 | +22.4 |
| DSC03656 | 211.7 | 240.7 | +29.0 |
| DSC03687 | 217.8 | 246.7 | +28.9 |
| DSC03696 | 219.5 | 249.2 | +29.7 |

The shift is +22 to +30 degrees on all five pairs. `ColorMath.waterHueGoal` is 240, and it sits
inside that gap. Every RAW water hue is below 240. Four of five JPEG water hues are above it, and
the fifth is 0.7 above.

`waterTarget` moves the water hue to that goal. So the move changes direction with the input. From a
RAW it pushes the water up, away from green, which raises red. From a JPEG it pulls the water down,
toward green, which cuts blue. That is the sign flip in the `waterTone` table above.

### Candidate A does not survive the measurement

Candidate A wanted a water estimate that a camera's white balance cannot move. A camera's white
balance is close to a per-channel gain, so a ratio against another part of the same frame should
cancel it. Four normalisers of the water's green/blue were measured on all five pairs.

| normaliser | cancels a per-channel gain | RAW-to-JPEG gap | keeps blue water apart from teal |
|---|---|---|---|
| none, the raw water green/blue | no | -0.194 to -0.248 | yes |
| the scene mean's green/blue | yes | -0.040 to -0.066 | no |
| the white reference's green/blue (`neutralColor`) | yes | -0.217 to +0.105 | no |
| the reddest third's green/blue | yes | -0.111 to -0.149 | inverted |

No row holds both columns. The reason is in the frame: open water fills most of a dive photo, so the
scene mean is mostly water, and dividing by it removes the signal as well as the gain. The other two
references are small parts of the frame whose own colour varies for its own reasons, so they add
noise instead.

The untouched water green/blue does keep the two water kinds apart, on both inputs. From a RAW blue
water reads 0.39 to 0.41 and teal water 0.57 to 0.69. From a JPEG blue water reads 0.20 to 0.22 and
teal water 0.33 to 0.44. The order survives; only the scale moves. A fixed threshold is what breaks.

### The water already lands in the same place

The output water was then measured, inside the same masks inverted. Natural Dive, intensity 0.8.
DSC03546 has no mask, so it is not in this table.

| photo | water hue out, from JPEG | water hue out, from RAW |
|---|---|---|
| DSC03545 | 242 | 226 |
| DSC03656 | 236 | 233 |
| DSC03687 | 235 | 229 |
| DSC03696 | 237 | 229 |

The input hues are in the J2 table above. They stand 22 to 30 degrees apart. The outputs stand 3 to 16 degrees apart, and all eight sit
near azure. So the water correction already does what Jake asked for: one look from either input.
Only the reef is wrong, and it is wrong in one direction, too warm.

### What carries the reef gap: three transplants

Each row renders the camera JPEG and takes one part of the pipeline from the ARW of the same frame.
Nothing else changes. Reef red share, on the three reefs.

| what came from the ARW | DSC03656 | DSC03687 | DSC03696 | water hue out, same order |
|---|---|---|---|---|
| nothing, the JPEG as it is now | 0.433 | 0.545 | 0.422 | 236 / 235 / 237 |
| the plan's water model only | 0.437 | 0.541 | 0.418 | 236 / 234 / 236 |
| the `WaterAnalysis` only | 0.228 | 0.226 | 0.305 | 263 / 263 / 264 |
| both of those | 0.229 | 0.251 | 0.306 | 263 / 262 / 264 |
| the ARW itself, for reference | 0.112 | 0.088 | 0.232 | 233 / 229 / 229 |

Three readings follow.

- The plan's water model moves nothing. Its `backscatterInfinity` differs by up to 13 times in red,
  and the reef still lands within 0.005 of where it was. Size is not effect.
- The analysis moves about half of the gap, and breaks the water while doing it.
- Part of the gap survives both transplants. With the ARW's analysis and the ARW's water model,
  DSC03687 still reads 0.251 against the ARW's 0.088. That part is the image itself.

### The carrier is the white reference

The analysis was then transplanted one group of fields at a time.

| fields taken from the ARW | DSC03656 | DSC03687 | DSC03696 | water hue out, same order |
|---|---|---|---|---|
| `waterRed`, `waterGreen`, `waterBlue` | 0.361 | 0.508 | 0.374 | 264 / 264 / 265 |
| `meanRed`, `meanGreen`, `meanBlue` | 0.428 | 0.544 | 0.419 | 236 / 235 / 237 |
| `neutralRed/Green/Blue`, `neutralShare` | 0.239 | 0.302 | 0.299 | 235 / 235 / 236 |
| `redLoss`, `cyanDominance` | 0.435 | 0.546 | 0.427 | 237 / 235 / 237 |
| `contrast`, `saturation`, `exposure`, `midLuminance` | 0.425 | 0.475 | 0.420 | 236 / 236 / 237 |
| `highShare`, `lightShare` | 0.417 | 0.545 | 0.422 | 235 / 235 / 237 |

One group does nearly all of it, and leaves the water where it was: the white reference. The water
colour moves the reef too, but it is the group that throws the water to indigo.

The gains say the same thing. `ColorCorrection.whiteReference` builds `neutralGains` from
`analysis.neutralColor`.

| photo | `neutralGains` from the JPEG | from the RAW |
|---|---|---|
| DSC03656 | (1.161, 0.993, 0.852) | (1.000, 1.000, 1.000) |
| DSC03687 | (1.194, 0.986, 0.871) | (1.000, 1.000, 1.000) |
| DSC03696 | (1.238, 0.979, 0.870) | (1.000, 1.000, 1.000) |

From a RAW the solver lands on one: the white reference does nothing. From a JPEG it raises red by
16 to 24 per cent and cuts blue by 13 to 15 per cent.

The reason is in the input. A camera JPEG arrives white balanced already, and its bright surfaces
keep a blue tint that the water correction does not remove. The white reference then removes that
tint the only way it can, by adding red. The reef is where those bright surfaces are.

| photo | `neutralColor` from the JPEG | from the RAW | its chroma, JPEG / RAW |
|---|---|---|---|
| DSC03656 | (0.370, 0.713, 1.131) | (0.401, 0.688, 0.777) | 0.67 / 0.48 |
| DSC03687 | (0.310, 0.575, 1.044) | (0.306, 0.451, 0.424) | 0.70 / 0.32 |
| DSC03696 | (0.296, 0.565, 1.045) | (0.326, 0.428, 0.371) | 0.72 / 0.24 |

Not measured: the path from `neutralGains` through `FinishingMath.neutralWeight` onto reef pixels.
That part is read from the code, not isolated by a run.

## J3 target

Jake looked at the three reefs rendered with the ARW's white reference and said that level is good
enough (23 Oct 2026). So the stage builds a white reference that holds on a camera JPEG, with no ARW
to copy from.

The earlier criterion, `waterType` within 0.15 of the RAW, is dropped. `waterType` is not where the
reef gap lives.

| what | pass |
|---|---|
| the reef, from a JPEG | red share at or below 0.35 on DSC03656, DSC03687 and DSC03696 |
| the water, from either input | output hue within 240 plus or minus 15 |
| the RAW path | its `neutralGains` stay at one on these three photos |

## J3 result — one line in the white reference's candidate test

`FilterEngine.analyze` picks the white reference's candidate pixels. Its own comment says they must
be "no more colourful than" the water. The code allowed 10 per cent more.

```
- ColorCorrection.oklch(c).y <= min(0.2, waterChroma * 1.1)
+ ColorCorrection.oklch(c).y <= min(0.2, waterChroma)
```

A camera JPEG's water is more saturated, so that slack widened on a JPEG and let blue-lit coral in
as a white surface. The white reference then greyed the coral by adding red.

### How the lever was found

Knobs were added to the sources, swept, and removed again. Each one switched off one step. The
numbers are reef red share.

| what was switched off | DSC03656 | DSC03687 | DSC03696 |
|---|---|---|---|
| nothing | 0.433 | 0.545 | 0.422 |
| `referenceAdaptation` | 0.433 | 0.470 | 0.422 |
| `whiteReference` | 0.239 | 0.535 | 0.298 |
| both | 0.239 | 0.244 | 0.298 |

Two functions read `analysis.neutralColor`, and which one fires depends on the photo. On DSC03656
and DSC03696 only `whiteReference` is active. On DSC03687 both are, and neither alone does much:
0.535 and 0.470 on their own, 0.244 together. Looked at one at a time, neither reads as the cause.

Two narrower fixes were measured first and dropped.

- A ceiling on how far the white reference may raise red. It moved DSC03656 and DSC03696 and left
  DSC03687 at 0.535, because there the damage is the blue cut, not the red rise.
- A threshold on how colourful the reference is. The existing photos sit on both sides of every
  threshold: the reference's chroma runs 0.00 to 0.85 across `eval/real`, `eval/market` and
  `eval/aquacolorfix`, and the three JPEGs sit at 0.67 to 0.72, inside that range.

### What it does

Reef red share, inside the hand-drawn non-water masks.

| photo | from the JPEG, before | from the JPEG, after | from the ARW, before | from the ARW, after |
|---|---|---|---|---|
| DSC03656 | 0.433 | 0.240 | 0.112 | 0.111 |
| DSC03687 | 0.545 | 0.244 | 0.088 | 0.092 |
| DSC03696 | 0.422 | 0.298 | 0.232 | 0.231 |

Output water hue, inside the same masks inverted.

| photo | from the JPEG, before | from the JPEG, after | from the ARW, before | from the ARW, after |
|---|---|---|---|---|
| DSC03656 | 236 | 235 | 233 | 233 |
| DSC03687 | 235 | 235 | 229 | 229 |
| DSC03696 | 237 | 236 | 229 | 229 |

Against the pass marks in J3 target: the reef passes on all three, and the water passes on both
inputs. The third mark does not pass as written. The ARW's `neutralGains` were to stay at one, and
DSC03687 reads 1.009 and DSC03696 1.004. The ARW results moved by 0.004 in red share and one degree
in hue, so the intent holds, but the number does not.

### What else it changes

The change is not local to these three photos. Across the 36 photos in `eval/real`, `eval/market`,
`eval/aquacolorfix` and the five pairs, 15 come out with different `neutralGains` or reference
strength. The three JPEGs lose both, which is the point. m5 keeps both, which matters because m5 is
the vividness reference. Some photos lose a correction they had: O3 goes from 1.301 to 1.000 in red,
m2 from 1.063 and 0.686 to one, O1 from 1.141 and 0.952 to 1.032 and 0.894.

So J4 is the real gate for this change, not J3.

All numbers in this section are from the Mac harness. The iPhone reads differently: see J5.

## J4 result — m5 does not move; the gate moves on two pairs

m5 (`m5_eval.sh`, against a render of `main` at `1bcbbc7`) is identical to every digit: whole-image,
panel, sand, coral and water dE on all four paths, all 18 panel patches, and the noise and black
figures. The two builds were different binaries (their md5 differ), so this is a result, not a rerun.

AquaColorFix gate, mean dE from our output to AquaColorFix's:

| path | mean | p1 | p2 | p3 | p4 | p5 |
|---|---|---|---|---|---|---|
| photo, before | 10.92 | 9.14 | 17.39 | 6.37 | 11.01 | 10.69 |
| photo, after | 11.16 | 9.14 | 17.39 | 6.95 | 11.64 | 10.69 |
| video, before | 10.61 | 8.32 | 16.11 | 6.21 | 11.76 | 10.66 |
| video, after | 10.87 | 8.30 | 16.11 | 6.60 | 12.67 | 10.66 |

p3 and p4 are the two photos whose white reference changed most. Jake looked at both and called the
result better than before. One cost is known: the manta belly in p4 keeps more tint, OKLab chroma
0.023 before and 0.030 after. AquaColorFix reaches 0.011 there.

Trap: `aquacolorfix_eval.sh` cannot score from a git worktree. Its benchmark finds `DeveloperMedia`
from its own path and calls `relative_to(repo)`. Render from the worktree, then run the benchmark
from the clone that holds `DeveloperMedia`, with `--underblue-files`.

## J5 result — the J3 change alone did not reach the iPhone

iPhone 17, `PhotoParityTests`, `PhotoProcessor.export`, Natural Dive 0.8. Both columns were measured
by the same tool on files from this session and from the session before.

| photo | from the JPEG, before | J3 change alone | with v2 (ships) | from the ARW, with v2 |
|---|---|---|---|---|
| DSC03656 | 0.405 | 0.339 | 0.336 | 0.110 |
| DSC03687 | 0.511 | 0.511 | 0.241 | 0.098 |
| DSC03696 | 0.353 | 0.324 | 0.300 | 0.231 |

With the J3 change alone, DSC03687 does not move at all on the phone. On the Mac it went from 0.545
to 0.244. The rest of this section is how v2 got there.

### Why: the Mac and the phone read a different white reference

`testPrintAnalysisForParityPhotos` prints the analysis on the device. For DSC03687 from the JPEG, with
the same code and the same file:

| value | Mac | iPhone 17 |
|---|---|---|
| water colour | (0.114, 0.235, 0.650) | (0.099, 0.204, 0.594) |
| water chroma | 0.1560 | 0.1555 |
| mid luminance | 0.2294 | 0.2274 |
| `neutralShare` | 0.0567 | 0.2001 |
| reference adaptation strength | 0.000 | 0.461 |

On the phone the white reference still closes (`neutralGains` at one), but the reference adaptation
stays open, because its evidence ramp starts at a share of 0.06. On the Mac the share fell to 0.0567,
0.0033 under that step. So the Mac result was a near miss, not a margin.

The 48 px analysis sample is drawn with a plain affine transform, a 114 times reduction of a 5472 px
photo. The default sampler reads a few source pixels per output pixel, and what it reads differs
between the two platforms.

Lesson: a rule that depends on the white reference's candidates cannot be tuned on the Mac harness.
Check it on the phone.

### What was tried after that

| attempt | result |
|---|---|
| a ceiling on how far the white reference raises red | DSC03687 did not move: there the damage is the blue cut |
| a threshold on the reference's chroma | m5's reference reads 0.112 on the Mac. DSC03687's reads 0.081 on the Mac and 0.099 on the phone. A cut that drops DSC03687 drops m5 first |
| a ceiling on the adaptation's gains | m5's red gain is 4.23 on the Mac. DSC03687's is 2.67 on the phone. A ceiling that stops DSC03687 stops m5 first |
| the reference adaptation switched off | m5 breaks: photo-path dE 12.98 to 22.73 |
| the candidate test as a smooth weight | the phone is fixed, but m5 breaks: 12.98 to 21.29 |
| Lanczos sampling and a hue trust gate (v2) | the phone is fixed, m5 holds at 13.22, but see below |

The hue trust gate uses the angle between the reference's hue and the water's hue. A surface lit by
the water has nearly the water's hue, so it is not taken as white. On the phone v2 gives 0.336, 0.241
and 0.300 for the three reefs.

v2 has two costs. In `videosim` the 4K clip `Tune_22_Oct/13832750` moves by 3.00 (mean
OKLab distance times 100): brighter, paler and bluer, and the rocks lose their warm tone. The manta
belly goes to chroma 0.043. Both have one cause: a white belly lit by the water has nearly the water's
hue too. Its angle is 23.5 degrees, against 18.6 to 20.8 for the coral. No bound fits safely in that
gap.

A third cost showed when the photos that lose their white reference were rendered. Across the 36
photos, 11 sit under 25 degrees and had a reference doing some work. Six of them were rendered against
`main` at 1600 px:

| photo | mean OKLab distance x100 | by eye |
|---|---|---|
| IMG_7259 | 0.70 | about the same |
| IMG_7256 | 1.03 | about the same; the reef at the edge a little less warm |
| IMG_7253 | 0.39 | the same |
| m1 | 1.37 | the yellow coral goes duller and the scene cools toward green |
| m6 | 0.77 | about the same |
| O1 | 0.33 | the same |

Jake looked at all three costs and chose v2 for 1.1.4 (23 Oct 2026). He called the video difference
small. v2 ships; branch `jpeg-input-v2` holds the same change as a parked copy.

The hue gate reverses a rule the code stated on purpose: "sand lit by blue water ... no colour test
tells them apart". `testAnalysisFindsBrightNeutralSurfacesAndBrightShare` encoded it, with sand 27.5
degrees from the water's hue, inside the ramp. The test now checks both sides with values clear of
it: sand 55 degrees away is a white reference, a pale surface 7 degrees away is not.

### Video

`videosim` on three clips, a frame every 2 s, against `main`. The numbers are mean OKLab distance
times 100 over all frames, with the largest frame in brackets.

| clip | the J3 change alone | with v2, which ships |
|---|---|---|
| A, `Tune_20_Oct/VID_20230118_095241_0018.MP4`, 21 frames | 0.00 (0.01) | 0.20 (0.24) |
| B, the whale shark clip in `challenge_video/video3`, 16 frames | 0.00 (0.00) | 0.32 (0.47) |
| K, `Tune_22_Oct/13832750_2160_3840_60fps.MP4`, 7 frames | 0.07 (0.08) | 3.00 (3.24) |

None of the three clips has a reef in frame, so they test that the video does not change. They do not
test the reef fix itself.

### Tests for 1.1.4

| where | tests | result |
|---|---|---|
| iPhone 17 | VideoTests, VideoRestorationTests, VideoSceneTests, LongVideoTests | 43 passed |
| iPhone 17 | RestorationTests, PhotoFormatTests, PresetTests, PhotoTests | 98 passed |
| iPhone 18 Pro simulator | all unit tests except PurchaseTests | 221 run, 7 skipped, 3 failed |

The three simulator failures:

- the old white-reference test, since rewritten; it passes on the iPhone
- `LongVideoTests` memory, 257 MB against 220 MB, with other work running; it passes on the iPhone,
  as `Verification.md` records for a run on its own
- `PhotoFormatTests` 4:4:4 JPEG, the chroma read as 2x2; it passes on the iPhone, so the simulator's
  encoder differs from the phone's

The simulator run hung after its last test, as `Verification.md` records, and was stopped by hand.

## Next

These go into the subject work, as one track (Jake, 23 Oct 2026). All three touch `SubjectMask`.

1. Find out whether the pale ring around fish on photos (`Verification.md`) sits on the subject
   mask's edge. One measurement decides it. If it does not, the ring may come from the detail layer,
   which lifts fine contrast on subjects to 1.4 to 2.1 times the source, and it can be fixed first.
2. Tie the white reference to the subject mask. A belly on a detected subject should count as white.
   A pale patch of reef should not. That separates the coral of DSC03687 from the manta belly, and the
   analysis sample alone cannot.
3. The subject emphasis itself (`SubjectEmphasis.md`).

State on 23 Oct 2026, on branch `subject-picker` (`SubjectEmphasis.md`, E15 to E18):

- Item 1: the ring is not on the mask edge and not from the detail layer. A per-pixel finishing step makes it. Not fixed.
- Item 2: done (E16). The manta gets its reference back. m1 does not improve: its coral is not on a subject.
- Item 3: the tiers now follow the water's transmission (E17). Adopted by Jake.


## Rules for this work

- Start from `main`. The subject work sits on `subject-picker` and ships later.
- Run the gate and `m5_eval.sh` on every colour change. When they disagree, m5 wins (memory `aquacolorfix-gate`).
- Mac and iOS render differently, so every colour change needs one check on each (`MacApp.md:150`).
- Tune at the photo's own resolution. Set `HT_EVAL_MAXDIM=4000`.
- The harness writes sRGB by default. `HT_EVAL_P3=1` writes the app's own space.
- Work on a branch. Commit only when Jake asks.

## Open items

- Whether the RAW rendering is the right reference, or only the one Jake prefers today.
- What other cameras do. Only one Sony body is in this set.
- Whether a JPEG that a phone wrote behaves like this Sony JPEG.
