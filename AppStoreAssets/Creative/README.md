# App Store creative assets

`universal-5244x2950.png` is one 16:9 image for both the product page header and search results (iOS 27 and later). RGB PNG, no alpha.

- Key art sits in Apple's "Art Safe Area" from the Photoshop universal template: x 1921–3323, y 660–1622.
- No text, so every language uses this file.
- Source: the en-US video frame pair (`Screenshots/en-US/source/video_frame_*.HEIC`), the same media as screenshot 01.

Regenerate from the repo root:

```sh
npm i --no-save playwright && node scripts/app_store_screenshots/creative_render.js
```

The layout is `scripts/app_store_screenshots/creative.html`. It needs ImageMagick (`magick`) to remove the alpha channel.

Other accepted sizes (not made): header 21:9 3840 × 1646; search results 3:2, 1920 × 1280 to 3840 × 2560. Specs: Apple, "App Store Creative Asset Specifications".
