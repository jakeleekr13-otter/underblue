# Icon Composer app icon

Goal: replace the flat PNG icon with a layered Liquid Glass icon (`.icon` file). One file serves iPhone, Mac and the App Store.

Source: Apple, "Creating your app icon using Icon Composer" (Xcode documentation).

## Current state (23 Oct 2026)

- iPhone: `AppIcon.appiconset`, one 1024 px PNG drawn by `scripts/make_icon.py`. Build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- Mac: `AppIconMac.appiconset`, a draft from `scripts/make_mac_icon.py`. Build setting `AppIconMac`.
- iOS minimum: 26.0. Xcode makes fallback images for releases before 27 from the `.icon` file.

## Plan, one step per session

| Step | What | Done when |
|---|---|---|
| 1 | Build `AppStoreAssets/IconComposer/AppIcon.icon` from the SVG layers. Match the current icon. | The file is saved and looks like the PNG in Default, Dark and Mono previews. |
| 2 | Tune Liquid Glass: specular, shadow, translucency. Set Dark and Mono variants. | Every preview is readable at the smallest size. |
| 3 | iPhone target: move the file to `UnderBlue/Resources/`, remove `AppIcon.appiconset`. | The app builds. The icon shows on the device Home Screen. |
| 4 | Mac target: use the same file. Remove the `make_mac_icon.py` draft. | The Mac app builds. The icon shows in the Dock. |
| 5 | Upload a build. Check the icon in App Store Connect and TestFlight. | The icon on the store page matches the device. |

Keep the `.icon` file outside `UnderBlue/` until step 3. `UnderBlue/` is a synced folder, so any file there joins the build.

## Layers

`scripts/make_icon_layers.py` writes three SVG files to `AppStoreAssets/IconComposer/Waves/`. One file per wave, 1024 × 1024, transparent.

- Same curve as `make_icon.py`. Stroke width is 44 (not 48), because the old script measured thickness vertically.
- Overlap with the current PNG: IoU 0.942 (Quick Look render, 23 Oct 2026). The only visible change is round wave ends.
- The background is not a layer. Set it in Icon Composer: solid fill `#081C22`.
- ImageMagick draws these SVG files as empty images. Use Quick Look (`qlmanage -t -s 1024`) to preview them.
