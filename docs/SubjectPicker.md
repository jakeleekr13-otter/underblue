# Subject picker — plan

**ON HOLD (Jake, 22 Oct 2026).** The picker is paused. First find a way to make subjects bright, vivid and natural. That plan is [SubjectEmphasis.md](SubjectEmphasis.md). The mask alone only reduces the halo beside a subject. It does not change the subject.

Status (22 Oct 2026): code written on branch `subject-picker`, not committed. Not checked on a real photo or a device yet. See "Progress" below.

## Goal

The user picks which subjects the correction protects. It works on one photo at a time, on iPhone and on Mac.

- Default is Auto: the current automatic mask, unchanged.
- Manual is opt-in, per photo.

## Decisions (Jake, 22 Oct 2026)

- Single photo only. The iPhone batch screen stays Auto.
- Mac: picks are stored per queue item. Only an item with picks changes. Other items stay Auto.
- The user picks groups, not Vision instances. Close instances merge into one group.
- A school of fish is one group. One fish at a time is not possible.
- The user sees the whole group area. The processing removes water pixels inside it.
- Both iPhone and Mac must be verified.

## Facts this plan rests on

| Fact | Source |
|---|---|
| Mac does not use `EditorView`. It is excluded from the Mac target. | `project.pbxproj`, `membershipExceptions` |
| Mac preview and Mac export use different `PhotoProcessor` instances. | `MacModel.swift:402`, `BatchEngine.swift:202` |
| iPhone editor and iPhone batch use different `PhotoProcessor` instances. | `EditorModel.swift:70`, `BatchModel.swift:59` |
| The subject mask is built once per photo in `prepare()` and cached by URL. | `PhotoProcessor.swift:180`, `:28` |
| Preview and export both call `processed()`. | `PhotoProcessor.swift:64`, `:81` |
| `liftDark` is true for video only. A photo with no mask is not routed differently. | `RestorationEngine.swift:280` |
| The mask is stored in 0 to 1 coordinates, so it fits any render size. | `SubjectMask.image(matching:)` |
| Vision gave no mask on O1, O5 and the challenge video at 36 s. | memory `vision-subject-mask-probe`, 30 Sep 2026 |
| Vision split a manta group into 2 and 3 instances. | same |
| `ZoomablePreview` has a double tap that zooms. | `ZoomablePreview.swift:73` |
| The phone controls panel is at most 350 pt high and scrolls. | `EditorView.swift:27` |

## Design

### Choice value

`SubjectChoice` is `.auto` or `.picked(SubjectMask?)`. `picked(nil)` means no subject.

- `PhotoProcessor.preview` and `export` take a `SubjectChoice`. The default is `.auto`.
- The choice is passed as a value, not stored in the processor. Mac preview and Mac export use different processors, so a stored choice would not reach the export.
- `processed()` is the one place that applies it. Preview and export get the same mask.

### Groups

- Vision instances that are close to each other merge into one group.
- The distance limit is a share of the photo's long side. S1 sets the value.
- At most about 6 groups are shown. Small groups merge first when there are more.
- One outline and one badge per group. A tap toggles the whole group.
- No split into single instances in version 1.

### Water inside a group

- Effective mask = the picked area × (1 − water likeness).
- Water likeness is the colour test that decides if a pixel is water. S1 finds where it lives in the current code.
- This is the processing's job. The picker and `SubjectChoice` only carry the area.

### Mode and state

- Per photo, two parts: mode (Auto or Manual) and the picks.
- Switch to Auto: the auto mask applies, the overlay hides, the picks stay in memory.
- Switch back to Manual: the picks return.
- Reset: the only action that clears the picks. It restores the auto selection.
- The next photo always starts in Auto. Nothing is saved in app settings.
- iPhone: the state lives in `EditorModel`, one model per photo.
- Mac: the state lives per queue item.

### Look of the picker

Colour is not the only signal.

| State | Outline | Inside | Badge |
|---|---|---|---|
| Selected | Thick white line, thin black line outside it | Light white fill, about 15% | Check mark |
| Not selected | Thin dashed line, half clear | No fill | Empty circle |

- The overlay shows only in Manual mode.
- A Done button hides the overlay and keeps Manual. A pencil button shows it again.
- Compare hides the overlay.
- Small groups get a larger tap area around the badge.
- While the overlay is on, double tap zoom is off. Pinch still zooms.
- VoiceOver label: "Subject group 1, selected, 3 included".

### Where it sits

| Platform | Place |
|---|---|
| iPhone | A "Subjects" row in the controls: Auto or Manual. Only for photos where Vision found a subject. |
| Mac | At the top of the preview pane, beside the Corrected or Original picker. |

A shared view `SubjectPicker` draws the overlay and maps taps. It lives in `UnderBlue/Views/` and builds for both targets.

## Stages

Each stage ends with one artifact that can fail.

| # | Stage | Artifact |
|---|---|---|
| S1 | Measure Vision on **iPhone device and Mac**: O1, O4, m5. Count instances, areas, distances, label map size. Find the water likeness code. | One table per device, then a comparison of the two |
| S1b | School experiment, no UI: on O1 and O5, compare a hand-painted area against that area × (1 − water likeness). | Images and the gate lines. Decides if a brush is built |
| S2 | `SubjectMask` keeps a label map. Add `SubjectChoice`, the grouping function, the combine function. | Unit tests: default equals the old `estimate`. A 31% instance can be picked. None selected works. Two close instances make one group. Two far ones make two. |
| S3 | `preview` and `export` take `SubjectChoice`. `processed()` applies it. | Test: the same choice gives the same mask in preview and export. A default call is byte-identical to today. |
| S4a | Shared `SubjectPicker` view: overlay, badge, coordinate map, tap or click. | Coordinate tests at 1x, zoomed and with a different aspect. Both targets build. |
| S4b | iPhone: Subjects row, Done, Reset, `EditorModel` state, double tap rule. | Device screenshot. A small iPhone simulator with Custom preset shows the Export button. |
| S4c | Mac: picker in the preview pane, per-item state, passed to export. | `BatchEngineTests`: only the picked item changes. App screenshot. |
| S4d | New strings and VoiceOver labels. | Catalog diff shows 0 deleted lines (`git diff --patience --numstat`). |
| S5 | Look at O4, m5, O1 with groups selected and not selected. Same photo and same picks on Mac and iPhone. | At most 6 captures. A line in `docs/Verification.md`. Report if the two masks differ. |

If S1b shows no gain, schools stay Auto and only tap picking ships. A brush becomes a later stage.

## Progress (22 Oct 2026)

| Stage | State | Evidence |
|---|---|---|
| S1 Vision measurement | Not done | Needs O1, O4, m5 on iPhone and Mac. The group gap 0.04 is a guess. |
| S1b School experiment | Not done | Water likeness was not built. See "Changes from the plan". |
| S2 Candidates, choice, grouping | Done | `SubjectCandidates.swift`, `SubjectSelection.swift`. 14 tests pass (`SubjectCandidatesTests`). |
| S3 `preview`/`export` take `SubjectChoice` | Done | `PhotoProcessor.applying` is the one place. Test: default keeps the plan, picked replaces the mask. No byte-compare of a real export yet. |
| S4a Shared `SubjectPicker` view | Done | Coordinate tests pass at zoom 1 and 4, three aspects. Both targets build. Not seen on screen. |
| S4b iPhone | Code done | Subjects row in `EditorView`. No screenshot. Small-iPhone Export check not done. |
| S4c Mac | Code done | `MacModel.subjectStates`, `BatchEngine.Item.subjects`. Test passes: only the picked item changes. No app screenshot. |
| S4d Strings | Not done | New strings are not in the catalog yet. List below. |
| S5 Look on O4, m5, O1 | Not done | |

### Cases the user asked for

| Case | Handling | Checked |
|---|---|---|
| Vision finds no subject | Manual shows "No subjects found. UnderBlue uses Auto." and the photo stays in Auto. | Unit test (state). Not on a real photo. |
| School of fish | Close instances merge into one group (gap 4% of the long side, chains merge). | Unit test with a 10-fish chain. Not on a real school. |
| Too many subjects found | At most 6 groups. The smallest merges into its nearest. A note says nearby ones are grouped. | Unit test with 10 instances. |
| Too much selected | The picks may cover at most 50% of the frame. A tap past that is refused with a message. A single group over 50% shows "too large". | Unit test. |

### Changes from the plan

- Outline is the group's bounding box, not its exact area. The fill shows the real mask.
- Water likeness was not built. The mask is the union of the picked Vision masks, so water between fish stays out only as far as Vision leaves it out. S1b decides if more is needed.
- Vision for the groups runs when the user first taps Manual, not on load. The row is always shown for a photo.
- First time in Manual, the picks equal what Auto would use. Reset returns to that.
- Pick cap 50% is new (Auto allows 25%). Provisional.

### Strings to add (S4d)

Subjects, Auto, Manual, Edit, Done, Reset, Auto subjects, Pick subjects, "Looking for subjects…", "No subjects found. UnderBlue uses Auto.", "Auto protects the main subjects it finds.", "No subject selected. Tap a subject to protect it.", "%lld of %lld selected. Tap a subject to change it.", "Too much of the photo is selected. Deselect a subject first.", "This area is too large to be a subject.", "Many subjects were found. Nearby ones are grouped.", "Subject group %lld, selected, %lld included", "Subject group %lld, not selected, %lld included". Some may already exist (Done, Reset). Check the catalog first.

### Next session

1. Add the strings (insert keys, check 0 deleted lines).
2. Run `SubjectCandidates.estimate` on O1, O4, m5 on Mac, then on the iPhone. Record instance and group counts. Set the gap (S1).
3. Look at the picker on the Mac app and on the iPhone. Check a small iPhone with Custom preset shows Export.
4. Check a no-subject photo (O1, O5) and a school.
5. S5, then `docs/Verification.md`.

## Rules for this work

- No performance runs. S1 records only Vision time.
- Three test photos. No extra review agents.
- iPhone: run `devicectl install` first. The share extension can stay old otherwise.
- The iOS simulator is for layout only. It is not a stand-in for colour.
- Mac screenshots: confirm the app is in front first.
- Work on a branch, not on `main`. Commit only when Jake asks.
- Strings go in the one shared catalog. Edit it by the method in `docs/MacApp.md` notes (insert keys, check 0 deletions).

## Out of scope

Video, brush, changes to the colour and detail kernels, iPhone batch.

## Open items

- The group distance limit. S1 sets it.
- How many instances a photo gives. Too many means a lower group cap.
- Whether Vision gives the same masks on Mac and iPhone. S1 and S5 compare them.
- Whether water likeness drops blue-lit fish. S1b checks it.
