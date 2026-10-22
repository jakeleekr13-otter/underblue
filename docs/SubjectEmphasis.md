# Subject emphasis — plan

Status: plan draft 22 Oct 2026. Nothing built. Not yet agreed by Jake.

The manual subject picker ([SubjectPicker.md](SubjectPicker.md)) is on hold until this plan finds a method that works.

## Goal

Make the main subject of a photo bright, vivid and natural. Water stays as it is.

- No colour that the source does not hold. A grey reef stays grey (see [Rejected](ColorAlgorithm.md#rejected)).
- Photos first. Video later, if the photo method works.
- Auto first: the user does nothing. Manual picking comes back only if Auto is not enough.

## Why this plan exists

Jake tested the picker on an iPhone on 22 Oct 2026. He saw almost no change after selecting or clearing a subject.

| Fact | Source |
|---|---|
| The subject mask only leaves the subject out of the local veil's broad light. | `RestorationEngine.swift:221` |
| It changes the water beside a subject, not the subject. | same code; test `testSubjectMaskKeepsABrightSubjectFromDarkeningTheWaterBesideIt` |
| Photos have a water-like test per pixel. It decides which pixels are subject for tone, light removal and detail. | `ColorAlgorithm.md`, "Subject light removal" |
| Hue rotation of subjects failed. Warm colour cannot be made on grey reefs. | memory `subject-hue-findings` |
| The product look is our tone with the vivid m5 look. Only awkward parts are removed. | memory `aquacolorfix-gate` |

## Ideas from outside (general, not copied)

| Idea | Source |
|---|---|
| Edit the subject through a mask: exposure, contrast and colour inside it only. | [Adobe tutorial](https://www.adobe.com/learn/lightroom-cc/web/underwater-photo-editing) |
| Change luminance only, so hue shifts stay small. | [local tone mapping study](https://infoscience.epfl.ch/record/52170?ln=fr) |
| A brighter pixel looks less saturated. Scale chroma by the cube root of the brightness ratio, with a cap. | [pixls.us thread](https://discuss.pixls.us/t/oklab-cielab-linear-cielab-tonemapping/28767) |
| Work per pixel. Blur-based shadow lift draws dark outlines at edges. | [pixls.us thread](https://discuss.pixls.us/t/what-do-people-use-to-get-the-most-detail-out-of-the-shadows-in-images-with-large-differences-between-highlights-and-shadows/37465/42) |

Neural methods are out. The rule is our own simple logic ([color-algorithm-design](ColorAlgorithm.md)).

## Candidates

| # | Method | Subject weight from | Risk |
|---|---|---|---|
| A | Raise Oklab L inside the weight. Scale chroma to match. Cap the gain. Soft edge. | Vision mask | Noise in very dark pixels |
| B | Same as A | The existing water-like test | Pale subjects (manta, mola) read as water |
| C | A, on the Auto Vision mask. Manual picking refines it later. | Vision mask | Photos where Vision finds nothing (O1, O5) get no change |

Plan: build A with the Vision mask. Compare B as the fallback where Vision finds nothing.

## Stages

Each stage ends with one artefact that can fail.

| # | Stage | Artefact |
|---|---|---|
| E1 | Pick 3 test photos with a dark or dull subject. Include one where Vision finds nothing. | A table: photo, subject share, Vision result |
| E2 | Prototype A in the eval harness (`scripts/color-eval`), not in the app. 3 to 4 variants: lift strength, chroma scale, noise guard. | Side-by-side images: source, today, each variant |
| E3 | Jake picks by eye. Check subject chroma and noise on the chosen one. | Numbers beside the images. A decision line in this file |
| E4 | Move the chosen method into `ColorCorrection.make` and the finishing kernel. | Tests: Natural Dive pins unchanged outside the mask; gate and m5 run |
| E5 | iPhone and Mac check on the same 3 photos. | Screenshots. A line in `Verification.md` |
| E6 | Decide on the picker. Resume `SubjectPicker.md` only if Auto is not enough. | A decision line |

## Rules for this work

- Algorithm first. No performance runs until the method is chosen (memory `algorithm-before-performance`).
- Three test photos. No extra review agents.
- Every new rule goes into `ColorCorrection.make` or a helper. No per-frame statistics in the kernel (memory `color-algorithm-design`).
- Run the gate and `m5_eval.sh` on every colour change. When they disagree, m5 wins (memory `aquacolorfix-gate`).
- The simulator is for layout only, not colour.
- Work on a branch. Commit only when Jake asks.

## Open items

- Which 3 photos. Jake may name them.
- How much brighter is "natural". E3 sets it by eye.
- Whether a dark subject has enough colour left to look vivid. E2 measures subject chroma before and after.
- Whether the lift should also apply when Vision finds nothing (candidate B).
- What happens to the picker code on `subject-picker`. It stays uncommitted for now.
