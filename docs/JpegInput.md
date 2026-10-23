# Camera JPEG input — plan

Status: plan, 23 Oct 2026. Nothing built. Agreed with Jake: this ships before the subject work.

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
