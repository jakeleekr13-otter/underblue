// Render the App Store universal creative asset (product page header and search results).
// Output: AppStoreAssets/Screenshots/header/universal-5244x2950.png, RGB PNG without alpha.
// Run from the repo root: npm i --no-save playwright && node scripts/app_store_screenshots/creative_render.js
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const source = path.join(root, 'AppStoreAssets/Screenshots/en-US/source');
const out = path.join(root, 'AppStoreAssets/Screenshots/header');
const file = path.join(out, 'universal-5244x2950.png');

// Chromium cannot read HEIC, so stage the frames as JPEG next to the page.
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'underblue-creative-'));
fs.mkdirSync(path.join(work, 'assets'));
fs.copyFileSync(path.join(__dirname, 'creative.html'), path.join(work, 'creative.html'));
for (const n of ['video_frame_before', 'video_frame_after']) {
  // Mirrored, so the clownfish faces right (see creative.html).
  execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '95', '--flip', 'horizontal',
    path.join(source, n + '.HEIC'), '--out', path.join(work, 'assets', n + '.jpg')], { stdio: 'ignore' });
}

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 5244, height: 2950 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(work, 'creative.html'));
  await page.waitForLoadState('networkidle');
  await page.evaluate(() => Promise.all([...document.images].map(i => i.decode())));
  const raw = path.join(work, 'raw.png');
  await page.locator('section').screenshot({ path: raw });
  await browser.close();
  // App Store Connect rejects images with an alpha channel, and Chromium writes RGBA. Needs ImageMagick (magick).
  execFileSync('magick', [raw, '-alpha', 'off', '-define', 'png:color-type=2', file]);
  console.log('wrote', path.relative(root, file));
  fs.rmSync(work, { recursive: true, force: true });
})().catch(e => { console.error(e); process.exit(1); });
