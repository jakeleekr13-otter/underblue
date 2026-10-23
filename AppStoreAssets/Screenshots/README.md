# App Store screenshots and header

All App Store images live here. Store text for every language is in `docs/AppStoreMetadata.md`.

## What to upload (24 Oct 2026)

| Folder | What | Size | Captions | Phone screens | Upload state |
|---|---|---|---|---|---|
| `en-US/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | English | English | 01 changed on 24 Oct (mirrored fish). Upload 01 again. |
| `ko/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Korean | English (Korean captures on hold) | Not recorded. 01 changed on 24 Oct. |
| `ja/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Japanese | English | Not uploaded. |
| `zh-Hans/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Simplified Chinese | English | Not uploaded. |
| `zh-Hant/final` | 5 iPhone screenshots | 1320 × 2868 JPEG | Traditional Chinese | English | Not uploaded. |
| `header/universal-5244x2950.png` | Product page header and search results, one file for both | 5244 × 2950 PNG | None, so every language uses it | — | Jake uploaded the first version on 23 Oct. Mirrored on 24 Oct, so upload it again. |
| `mac-en-US/final` | 5 Mac screenshots | 2560 × 1600 JPEG | English | English | Not recorded. |
| `iphone-duo-en-US` | iPhone Duo screens | — | — | — | See `docs/AppStoreRelease.md`. |
| `en-US-outdated` | Old sets | — | — | — | Do not upload. |

All files are RGB without alpha. Upload screenshots in file order, 01 to 05, to the iPhone 6.9" slot of the matching language.

Nobody on the team reads Japanese or Chinese. An independent reviewer checked that copy against the English and the app's own UI terms.

## iPhone captions

| File | English caption |
|---|---|
| `01-before-after.jpg` | Bring back the real colour. |
| `02-photo.jpg` | Reef colour, restored. |
| `03-video.jpg` | Video, fixed too. |
| `04-looks.jpg` | Pick a look. Set the strength. |
| `05-private.jpg` | Stays on your iPhone. |

Other languages: `scripts/app_store_screenshots/captions.json`.

Store copy uses the app's own UI words. The app translates "Look" as 効果 (ja) and 效果 (zh). The Korean UI says 효과, but the Korean captions and description still say 룩.

## Regenerate

From the repo root:

```sh
npm i --no-save playwright
node scripts/app_store_screenshots/render.js            # en-US
node scripts/app_store_screenshots/render.js ko         # or ja, zh-Hans, zh-Hant
node scripts/app_store_screenshots/creative_render.js   # header
node scripts/app_store_screenshots/mac_render.js        # Mac
```

- iPhone layout: `scripts/app_store_screenshots/screens.html`. Every caption has a `data-t` key.
- Header layout: `scripts/app_store_screenshots/creative.html`. Details in `header/README.md`.
- Mac layout: `scripts/app_store_screenshots/mac.html`. Mac sources: `mac-en-US/source`, real 1920 × 1200 window captures.
- The header needs ImageMagick (`magick`). Japanese line breaking needs a current Chromium (Playwright).

## Device captures per language

A language reads `<locale>/source` and writes `<locale>/final`. A missing capture falls back to `en-US/source`, with a warning. That is why the ko, ja and zh sets show English phone screens.

To replace them, capture the five screens on the iPhone with the app language set to that language (Settings → Apps → UnderBlue → Language). Use the same states as `en-US/source`:

| File | Screen |
|---|---|
| `home.PNG` | Home screen |
| `photo_after.PNG` | Same reef photo, Natural Dive, Intensity 80% |
| `photo_before.PNG` | Same state, Compare held, so the label reads Original |
| `video_after.PNG` | Same reef video, Natural Dive, Intensity 80% |
| `video_before.PNG` | Same state, Compare held |

The video frame pair (`video_frame_*.HEIC`) has no UI, so every language reuses `en-US`. render.js and creative_render.js mirror it, so the clownfish faces right: tail on the "before" side, head on the "after" side (Jake, 24 Oct 2026).

## Media rules

The UIEB files in the local developer fixtures are academic, non-commercial benchmark data. They must not appear in App Store assets or be shared. Use only developer-owned media and real UnderBlue output.
