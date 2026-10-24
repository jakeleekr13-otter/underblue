# App Store screenshots and header

All App Store images live here. Store text for every language is in `docs/AppStoreMetadata.md`.

## What to upload (24 Oct 2026)

| Folder | What | Size | Captions | Phone screens | Upload state |
|---|---|---|---|---|---|
| `en-US/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | English | English | 01 changed on 24 Oct (mirrored fish). Upload 01 again. |
| `ko/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Korean | Korean | Not recorded. All 5 changed on 24 Oct (Korean UI). |
| `ja/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Japanese | Japanese | Not uploaded. |
| `zh-Hans/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Simplified Chinese | Simplified Chinese | Not uploaded. |
| `zh-Hant/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Traditional Chinese | Traditional Chinese | Not uploaded. |
| `es-ES/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Spanish (Spain) | Spanish (app catalog `es`) | Not uploaded. Needs a build with Spanish (branch `spanish`, ae26f3c). |
| `header/universal-5244x2950.png` | Product page header and search results, one file for both | 5244 × 2950 PNG | None, so every language uses it | — | Jake uploaded the first version on 23 Oct. Mirrored on 24 Oct, so upload it again. |
| `mac-en-US/final` | 5 Mac screenshots | 2560 × 1600 JPEG | English | English | Not recorded. |
| `iphone-duo-en-US` | iPhone Duo screens | — | — | — | Not needed yet; kept in case App Store Connect asks for Duo sizes. See `docs/AppStoreRelease.md`. |

All files are RGB without alpha. Upload screenshots in file order, 01 to 05, to the iPhone 6.9" slot of the matching language.

Nobody on the team reads Japanese, Chinese or Spanish. An independent reviewer checked that copy against the English and the app's own UI terms.

## iPhone captions

| File | English caption |
|---|---|
| `01-before-after.jpg` | Bring back the real colour. |
| `02-photo.jpg` | Reef colour, restored. |
| `03-video.jpg` | Video, fixed too. |
| `04-looks.jpg` | Pick a look. Set the strength. |
| `05-private.jpg` | Stays on your iPhone. |

Other languages: `scripts/app_store_screenshots/captions.json`.

Store copy uses the app's own UI words. The app translates "Look" as 効果 (ja), 效果 (zh) and Efecto (es). The Korean UI says 효과, but the Korean captions and description still say 룩.

## Regenerate

From the repo root:

```sh
npm i --no-save playwright
node scripts/app_store_screenshots/render.js            # en-US
node scripts/app_store_screenshots/render.js ko         # or ja, zh-Hans, zh-Hant, es-ES (needs <locale>/source)
node scripts/app_store_screenshots/creative_render.js   # header
node scripts/app_store_screenshots/mac_render.js        # Mac
```

- iPhone layout: `scripts/app_store_screenshots/screens.html`. Every caption has a `data-t` key.
- Header layout: `scripts/app_store_screenshots/creative.html`. Details in `header/README.md`.
- Mac layout: `scripts/app_store_screenshots/mac.html`. Mac sources: `mac-en-US/source`, real 1920 × 1200 window captures.
- The header needs ImageMagick (`magick`). Japanese line breaking needs a current Chromium (Playwright).

## Device captures per language

Each language has its own `<locale>/source`: home, photo and video screens captured on an iPhone 17 in that language.
Capture them again after any UI change:

```sh
zsh scripts/app_store_screenshots/capture_device.sh <device id> ko ja zh-Hans zh-Hant es-ES
```

- `UnderBlueUITests/LocalizedScreenshotTests` drives the app. It never opens the photo picker, so no photo library appears. The script copies the photo and video into the app's Documents, and the Debug-only `--ui-test-open` argument opens them.
- `compose_sources.py` keeps only the UI from each capture. The photo and video areas and the status bar come from `en-US/source`, so every language shows the same pictures and clock. It writes `layout.json` with where the media sits.
- Hand-set positions per language are in `scripts/app_store_screenshots/layout_overrides.json`. Korean moves the screen 05 "On-device" badge up, because its 3-line home title would sit under it.
- Turn on Do Not Disturb first. On 24 Oct a notification banner landed in one capture, and that screen was captured again.
- The video frame pair (`en-US/source/video_frame_*.HEIC`) has no UI, so every language uses it. render.js and creative_render.js mirror it, so the clownfish faces right: tail on the "before" side, head on the "after" side (Jake, 24 Oct 2026).

## Media rules

The UIEB files in the local developer fixtures are academic, non-commercial benchmark data. They must not appear in App Store assets or be shared. Use only developer-owned media and real UnderBlue output.
