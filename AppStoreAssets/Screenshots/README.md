# App Store screenshots

`en-US/final` contains the current five upload-ready 6.9-inch iPhone screenshots at 1320 × 2868 pixels. They are RGB JPEG files without alpha.

Upload order and captions:

1. `01-before-after.jpg` — Bring back the real colour.
2. `02-photo.jpg` — Reef colour, restored.
3. `03-video.jpg` — Video, fixed too.
4. `04-looks.jpg` — Pick a look. Set the strength.
5. `05-private.jpg` — Stays on your iPhone.

`en-US/source` contains the real device captures and the video frame pair used by the generator. Regenerate the final set from the repo root:

```sh
npm i --no-save playwright
node scripts/app_store_screenshots/render.js          # en-US
node scripts/app_store_screenshots/render.js ko       # Korean
```

The layout is `scripts/app_store_screenshots/screens.html`. Every caption has a `data-t` key. Other languages take their captions from `scripts/app_store_screenshots/captions.json`.

## Other languages

A language uses `<locale>/source` for its device captures and writes `<locale>/final`. A missing capture falls back to `en-US/source`, and the script prints a warning. A set that printed a warning shows English phone screens under translated captions.

Capture the five screens on the iPhone with the app language set to that language (Settings → Apps → UnderBlue → Language). Use the same states as `en-US/source`:

| File | Screen |
|---|---|
| `home.PNG` | Home screen |
| `photo_after.PNG` | Same reef photo, Natural Dive, Intensity 80% |
| `photo_before.PNG` | Same state, Compare held, so the label reads Original |
| `video_after.PNG` | Same reef video, Natural Dive, Intensity 80% |
| `video_before.PNG` | Same state, Compare held |

The video frame pair (`video_frame_*.HEIC`) has no UI, so every language reuses `en-US`.

Status (23 Oct 2026): `ko/final` is committed. Its captions are Korean, but its phone screens are the en-US captures, because the Korean captures are on hold. Whether this set was uploaded for 1.1.4 is not recorded. `ja/final` (24 Oct 2026) is the same kind of set: Japanese captions over the en-US captures. An independent reviewer checked the Japanese copy, because Jake cannot review it. `zh-Hans` and `zh-Hant` need captions and full App Store metadata first.

The app UI translates "Look" as 効果 (ja) and 효과 (ko). The Japanese store copy uses 効果 to match. The Korean captions and description still say 룩.

`en-US-outdated` keeps the older sets for comparison only.

The UIEB files under the local developer fixtures are academic/non-commercial benchmark data and must not appear in App Store assets or be redistributed. Use only developer-owned photo/video fixtures and actual UnderBlue output.

The Korean store text is in `docs/AppStoreMetadata.md`. The Korean screenshot captions are in `scripts/app_store_screenshots/captions.json`.

## Mac

`mac-en-US/final` has the five Mac screenshots at 2560 × 1600 (JPEG, no alpha). They use the same look as the iPhone set.

1. `01-batch.jpg` — Fix a whole dive in one batch.
2. `02-before-after.jpg` — Bring back the real colour.
3. `03-folders.jpg` — Drop in a folder. Walk away.
4. `04-video.jpg` — Video, fixed too.
5. `05-looks.jpg` — Pick a look. Set the strength.

`mac-en-US/source` has the real 1920 × 1200 window captures and the before/after images. Regenerate from the repo root:

```sh
npm i --no-save playwright && node scripts/app_store_screenshots/mac_render.js
```

The layout is `scripts/app_store_screenshots/mac.html`.
