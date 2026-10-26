# LUT presets — plan

Status: plan revised 24 Oct 2026. Nothing built. Order (Jake, 24 Oct 2026): the subject work (SubjectEmphasis.md, SubjectPicker.md), then [RestorationExperiments](RestorationExperiments.md), then this plan.

Update 26 Oct 2026: not started. Jake is not sure the presets are needed, because the restoration work went well. Decide before L2.

## Goal

A built-in preset that adds a look on top of Natural. The user drags one dot on a 2D pad to change the look. The app places the dot for each photo or video scene by itself. The user can tap the preset and do nothing else.

- The pad works like the Photographic Styles pad in the iPhone Photos app: one dot, two axes.
- It works on RAW, JPEG and video, photo and batch.
- Minimum OS stays iOS 26 and macOS 26. The APIs below exist there.

## Terms

- **3D LUT**: a table that maps each input colour (red, green, blue) to an output colour. A common size is 17 x 17 x 17 cells. Values between cells are interpolated.
- **Look function**: our own function with two parameters, one per pad axis. It turns a corrected colour into a styled colour.
- **Pad position**: the dot on the pad, two values from -1 to 1.
- **Auto position**: the pad position the app picks from the scene values.

## Facts this plan rests on

| Fact | Source |
|---|---|
| A single LUT maps the same input colour to the same output colour everywhere in the frame. | Definition of a 3D LUT |
| Our correction treats the same colour differently by depth, local light and water or subject. | `RestorationEngine.combined`, `RestorationEngine.restore` (local veil) |
| So a single LUT cannot replace the whole correction. It can hold a look on top. | The two rows above |
| Core Image applies a 3D LUT on iPhone and Mac with no extra library. `extrapolate` (values outside 0 to 1) needs iOS 16. | `CIColorCube`, `CIColorCubeWithColorSpace` (SDK headers) |
| Core Image can mix two LUTs per pixel by a mask. | `CIColorCubesMixedWithMask` (SDK header) |
| RAW, JPEG and video all pass through `RestorationEngine.combined`. | `docs/ColorAlgorithm.md`, "Purpose and product rules" |
| Photos are corrected in SDR. The HDR export re-expands the result afterwards. | `PhotoHDR.swift` |
| HDR video reaches the colour engine with values up to 8. | `RestorationEngine.swift:53` (`maximumOutput`) |
| Each photo already gets automatic values. | `ColorCorrection.make`, `WaterAnalysis` |
| Video holds one value set per scene, with a 3 s cross-fade between scenes. | `docs/ColorAlgorithm.md`, "Pipeline overview" (`sceneFade`) |
| Research has image-adaptive LUTs: a small trained network mixes basis LUTs per image. | [Zeng et al.](https://ar5iv.labs.arxiv.org/html/2009.14468), [INAM](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9965914/), [DY-LUT](https://arxiv.org/pdf/2607.22801) |
| We use our own logic only. No research code, tables or trained models. Store text must not name papers. | memories `color-algorithm-design`, `app-store-nomination` |

So the look function and the auto position rule are our own. The research only shows that the idea works.

## Decisions (Jake, 24 Oct 2026)

| # | Question | Decision |
|---|---|---|
| 1 | Where the LUT sits | A look on top of Natural. It is a built-in preset. |
| 2 | What the user controls | A 2D pad only. No intensity slider. No list of looks. |
| 3 | How the look is made | One look function. The app computes a 17 x 17 x 17 LUT for each pad position. |
| 4 | Overlap with Custom | Allowed. Custom and this preset are a matter of taste. They are not combined. |
| 5 | Pad axes | Chosen by experiment (L3). |
| 6 | HDR video | Tone-map to SDR, apply the LUT, re-expand. The same structure as the photo HDR export. |
| 7 | Water and subject looks | v1 uses one LUT. Two LUTs mixed by a water matte is a later experiment (L8). |
| 8 | Saved user change | An offset from the auto position, not a fixed position. |
| 9 | Video | One auto position per scene. It follows the existing scene cross-fade. |

### Rejected: the LUT replaces the colour part of our correction

- `ColorCorrection.make` already computes values per photo, on a continuous scale. A fixed set of LUTs can only pick the nearest one. The fit gets worse.
- The spatial parts (depth blend, local veil) cannot go into a LUT.
- The speed gain was never measured.

### Rejected: a fixed pool of LUTs with auto pick

- Mixing two neighbour LUTs makes a look that is not in the pool.
- A slider cannot order the pool, because the looks have no natural order.
- The pad gives the same choice on a continuous scale.

## Where the look runs

Current photo order:

1. Finishing per path. It ends with the highlight shoulder.
2. The depth blend.
3. The subject lift (branch `subject-picker` only).
4. Violet calm.

- The LUT runs once, after the blend. A LUT is not linear. Applying it per path and then blending gives a different result.
- It runs before violet calm. Violet calm then removes violet that the look made.
- The highlight shoulder ran before the blend. So the look must not push highlights back up. First choice: the look function is the identity near white. Fallback: a cap after the LUT. L4 decides.
- HDR video: tone-map, apply the LUT in SDR, re-expand by the source's brightness ratio. Photos already work this way (`PhotoHDR.reexpand`).

## Stages

Each stage ends with one artefact that can fail.

| # | Stage | Artefact |
|---|---|---|
| L1 | Record the decisions. | The Decisions table above. Done 24 Oct 2026. |
| L2 | Choose test scenes from `DeveloperMedia/eval` and `tune/`. Include RAW, JPEG and one multi-scene video. | A table: scene type, files, scene values |
| L3 | Axis experiment. Pick 2 or 3 candidate axis pairs, for example tone and colour (as Apple does), or water hue and subject warmth. Render a 5 x 5 pad grid on a best, a middle and a worst scene. | Grid sheets. A decision line from Jake |
| L4 | Build the look function for the chosen axes. Render the 4 pad corners and the grid on the L2 scenes. Run the guards: violet share, neon, pale surface pink, neutral ramp chroma, clipping. | A guard table. A corner that fails shrinks the pad range |
| L5 | Auto position. Jake places the dot by eye on a few scenes first. Then a rule from the scene values (`waterRed`, `waterGreen`, `waterBlue`, `redLoss`, `cyanDominance`, `exposure`, depth spread) tries to match. | Count of scenes where the rule lands near Jake's dot |
| L6 | HDR video path. | An HDR clip export. Highlight check against the same clip without the look. iPhone time and memory |
| L7 | App: the preset tile and the pad on iPhone and Mac, for RAW, JPEG, video and batch. New UI strings in every app language. | Screenshots. Tests: the same scene gives the same auto position on both platforms |
| L8 | Later: two LUTs mixed by the transmission matte (`RestorationExperiments.md`, Stage B). One pad axis moves the water LUT, the other the subject LUT. Video has no optical matte, so check the photo and video looks against each other. | Halo check on the B test frames. Decision line |

## Open items

- The pad axes (L3).
- The auto position rule (L5).
- Highlight handling: identity near white, or a cap (L4).
- The pad range limits (L4). A user must not be able to ruin a good correction.
- The HDR video cost on iPhone (L6). Not measured.
- The name in the app, for example "Auto Look".
- Export and import of `.cube` files. Possible later. Not part of this plan.

## Rules for this work

- Own logic only. The look comes from our function, not from other apps.
- Few test photos. No extra review agents (memory `test-scale-preference`).
- No speed runs before the method is chosen (memory `algorithm-before-performance`).
- Work on a branch. Commit only when Jake asks.
