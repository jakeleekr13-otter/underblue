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
node scripts/app_store_screenshots/render.js
```

The layout is `scripts/app_store_screenshots/screens.html`.

`en-US-outdated` keeps the older sets for comparison only.

The UIEB files under the local developer fixtures are academic/non-commercial benchmark data and must not appear in App Store assets or be redistributed. Use only developer-owned photo/video fixtures and actual UnderBlue output.

Korean caption copy and full App Store metadata are in `docs/AppStoreMetadata.md`.

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
