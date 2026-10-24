# LUT presets — plan

Status: idea recorded 24 Oct 2026. Nothing built. Start after the subject work (SubjectEmphasis.md, SubjectPicker.md) is done.

## Goal

A preset that picks a fitting look by itself. UnderBlue keeps a pool of LUTs made in advance. For each photo or video, it picks the LUT that fits the scene best. The user taps one preset and does nothing else.

- Not one LUT per photo. The pool is fixed and ships with the app (Jake, 24 Oct 2026).
- Reason: better UX. A known, named set of looks is easier to trust than a new look per photo.

## Terms

- **3D LUT**: a table that maps each input colour (red, green, blue) to an output colour. A common size is 17 x 17 x 17 cells. Values between cells are interpolated.
- **LUT pool**: the fixed set of LUTs that ships with the app.
- **Auto pick**: the rule that chooses one LUT from the pool for a scene.

## Facts this plan rests on

| Fact | Source |
|---|---|
| A LUT maps the same input colour to the same output colour everywhere in the frame. | Definition of a 3D LUT |
| Our correction treats the same colour differently by depth, local light and water or subject. | `RestorationEngine.combined`, `RestorationEngine.restore` (local veil) |
| So a LUT cannot replace the whole correction. It can hold a colour-only stage or a look on top. | The two rows above |
| Core Image can apply a 3D LUT on iPhone and Mac with no extra library. | `CIColorCube`, `CIColorCubeWithColorSpace` |
| Each photo already gets automatic values. | `ColorCorrection.make`, `WaterAnalysis` |
| Video already holds one value set per scene. | memory `color-algorithm-design` |
| Research has image-adaptive LUTs: a small trained network mixes basis LUTs per image. Underwater and depth-aware variants exist. | [Zeng et al.](https://ar5iv.labs.arxiv.org/html/2009.14468), [INAM](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9965914/), [DY-LUT](https://arxiv.org/pdf/2607.22801) |
| We use our own logic only. No research code, tables or trained models. Store text must not name papers. | memories `color-algorithm-design`, `app-store-nomination` |

So the pool and the pick rule are our own. The research only shows that the idea works.

## Design questions (open)

1. **Where the LUT sits.**
   - A. A look on top of our correction. The correction stays as it is. The LUT adds a style.
   - B. It replaces the colour-only part of our correction. It is faster, but the look is tied to the pool.
   - Jake decides. A is the safer first step.
2. **How the pool is made.** Our own correction on a set of representative scenes, baked into LUTs, then tuned by eye. No other app's output.
3. **What the pick reads.** Scene values we already have: water colour (`waterRed`, `waterGreen`, `waterBlue`), `redLoss`, `cyanDominance`, `exposure`, depth spread. Each LUT keeps the values of the scenes it was made for. The pick takes the nearest one.
4. **Video.** One pick per scene, with the existing 1 s cross-fade between scenes. Or one pick per clip, to avoid a look change mid-clip.
5. **Pool size.** Small enough to tune by eye. A guess of 6 to 12. Not measured.
6. **Name in the app.** For example "Auto Look". The user should see which LUT was picked, and be able to pick another.
7. **Export and import of `.cube` files.** Possible later. Not part of this plan.

## Stages

Each stage ends with one artefact that can fail.

| # | Stage | Artefact |
|---|---|---|
| L1 | Decide question 1 (A or B). | A decision line in this file |
| L2 | Choose the scene types for the pool from the eval sets (`DeveloperMedia/eval`). | A table: scene type, example photos, scene values |
| L3 | Bake one LUT from our correction on one scene. Check that applying it matches the correction it came from, for the colour-only part. | Mean OKLab difference on that scene |
| L4 | Build the pool and the pick rule. | Pick results on the eval sets: chosen LUT per photo |
| L5 | Jake judges the picks by eye on a few best, middle and worst photos. | A decision line |
| L6 | App: the preset on iPhone and Mac, photo and video. | Screenshots. Tests: same scene gives the same pick on both platforms |

## Rules for this work

- Own logic only. The pool comes from our correction, not from other apps.
- Few test photos. No extra review agents (memory `test-scale-preference`).
- No speed runs before the method is chosen (memory `algorithm-before-performance`).
- Work on a branch. Commit only when Jake asks.
