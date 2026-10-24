# Icon Composer app icon

Goal: replace the flat PNG icon with a layered Liquid Glass icon (`.icon` file). One file serves iPhone, Mac and the App Store.

Source: Apple, "Creating your app icon using Icon Composer" (Xcode documentation).

## Current state (23 Oct 2026)

- iPhone: `UnderBlue/Resources/AppIcon.icon` since step 3. Build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. The old PNG set and `scripts/make_icon.py` are removed.
- Mac: the same `UnderBlue/Resources/AppIcon.icon` since step 4 (24 Oct 2026). The `UnderBlueMac` target syncs the `UnderBlue/` folder, so only the build setting changed to `AppIcon`. The draft `AppIconMac.appiconset` and `scripts/make_mac_icon.py` are removed.
- iOS minimum: 26.0. Xcode makes fallback images for releases before 27 from the `.icon` file.

## Plan, one step per session

| Step | What | Done when |
|---|---|---|
| 1 | Build `AppStoreAssets/IconComposer/AppIcon.icon` from the SVG layers. Match the current icon. | Done 23 Oct 2026. `icon.json` was written by hand (Liquid Glass defaults). `ictool` renders iOS Default, Dark, ClearLight, TintedDark and macOS Default with all three waves. |
| 2 | Tune Liquid Glass: specular, shadow, translucency. Set Dark and Mono variants. | Every preview is readable at the smallest size. |
| 3 | iPhone target: move the file to `UnderBlue/Resources/`, remove `AppIcon.appiconset`. | 23 Oct 2026: iOS and Mac Debug builds pass. The iOS `Assets.car` holds the `AppIcon` stack with the Waves group and three vector layers. Installed on iPhone 17. Jake accepted the Home Screen look. Ships in 1.1.4 (10). |
| 4 | Mac target: use the same file. Remove the `make_mac_icon.py` draft. | 24 Oct 2026: the Mac Debug build passes. `CFBundleIconName = AppIcon`; the bundle has `AppIcon.icns` and the Waves stack in `Assets.car`. ComplianceTests pass. The Dock look is not checked. |
| 5 | Upload a build. Check the icon in App Store Connect and TestFlight. | The icon on the store page matches the device. |


## Layers

`scripts/make_icon_layers.py` writes three SVG files to `AppStoreAssets/IconComposer/Waves/`. One file per wave, 1024 × 1024, transparent.

- Same curve as the removed `make_icon.py`. Stroke width is 44 (not 48), because the old script measured thickness vertically.
- Overlap with the current PNG: IoU 0.942 (Quick Look render, 23 Oct 2026). The only visible change is round wave ends.
- The background is not a layer. Set it in Icon Composer: solid fill `#081C22`.
- ImageMagick draws these SVG files as empty images. Use Quick Look (`qlmanage -t -s 1024`) to preview them.
- `UnderBlue/Resources/AppIcon.icon/Assets/` holds copies of the SVG files. After you change a layer, copy it there again.

## Render without the app

`ictool` ships inside Icon Composer. It renders any appearance to a PNG:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  UnderBlue/Resources/AppIcon.icon --export-image --output-file out.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Renditions used: Default, Dark, ClearLight, TintedDark.
