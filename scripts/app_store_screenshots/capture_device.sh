#!/bin/zsh
# Captures the App Store source screens on a connected iPhone 17 (1206 x 2622) in each given language,
# then builds AppStoreAssets/Screenshots/<locale>/source with compose_sources.py.
# Usage, from the repo root: zsh scripts/app_store_screenshots/capture_device.sh <device id> ko ja zh-Hans zh-Hant
#
# Before you run it:
# - iPhone: Settings > Developer > Enable UI Automation on. Keep the iPhone unlocked. Turn on Do Not Disturb,
#   because a notification banner lands in the capture.
# - The photo and video are the developer-owned files the en-US screenshots use (DeveloperMedia, local only).
# The test never opens the photo picker, so no photo library appears. It copies the two files into the app's
# Documents and opens them with --ui-test-open (Debug builds only).
# After it runs: check the top of each capture for a banner, then node scripts/app_store_screenshots/render.js <locale>.
set -u
DEV="$1"; shift
ROOT="$PWD"
WORK="$(mktemp -d -t underblue-capture)"
PHOTO="DeveloperMedia/subjectpicker/DSC03656.JPG"
VIDEO="DeveloperMedia/tune/video/Tune_20_Oct/2017-01-08 01.21.36.MOV"

xcodebuild -project UnderBlue.xcodeproj -scheme UnderBlue -destination "id=$DEV" -derivedDataPath "$WORK/dd" \
  -allowProvisioningUpdates build-for-testing > "$WORK/build.log" 2>&1 || { echo "build failed: $WORK/build.log"; exit 1; }
RUN=$(ls "$WORK"/dd/Build/Products/*.xctestrun)

for pair in "$PHOTO:photo.jpg" "$VIDEO:video.mov"; do
  xcrun devicectl device copy to --device "$DEV" --source "${pair%%:*}" --destination "Documents/${pair##*:}" \
    --domain-type appDataContainer --domain-identifier com.underblue.app > "$WORK/copy.log" 2>&1 \
    || { echo "copy failed: $WORK/copy.log"; exit 1; }
done

for lang in "$@"; do
  for t in testHome testPhoto testVideo; do
    TEST_RUNNER_SCREENSHOT_LANGUAGE=$lang xcodebuild test-without-building -xctestrun "$RUN" -destination "id=$DEV" \
      -resultBundlePath "$WORK/$lang-$t.xcresult" -only-testing:UnderBlueUITests/LocalizedScreenshotTests/$t \
      > "$WORK/$lang-$t.log" 2>&1
    RC=$?
    echo "$lang $t rc=$RC"
    xcrun xcresulttool export attachments --path "$WORK/$lang-$t.xcresult" --output-path "$WORK/$lang/$t" > /dev/null 2>&1
  done
  python3 -I - "$WORK/$lang" "$WORK/$lang/captures" <<'EOF'
import json, shutil, sys
from pathlib import Path
src, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for test in ['testHome', 'testPhoto', 'testVideo']:
    for record in json.load(open(src / test / 'manifest.json')):
        for attachment in record['attachments']:
            name = attachment['suggestedHumanReadableName']
            if name.endswith('.png') and '_0_' in name:
                shutil.copy(src / test / attachment['exportedFileName'], out / (name.split('_0_')[0] + '.png'))
EOF
  python3 scripts/app_store_screenshots/compose_sources.py "$lang" "$WORK/$lang/captures"
done
echo "captures and logs: $WORK"
