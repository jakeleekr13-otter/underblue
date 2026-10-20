// Render the Mac App Store screenshots from AppStoreAssets/Screenshots/mac-en-US/source.
// Output: AppStoreAssets/Screenshots/mac-en-US/final, 2560 x 1600 JPEG, no alpha.
// Run from the repo root: npm i --no-save playwright && node scripts/app_store_screenshots/mac_render.js
const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const source = path.join(root, 'AppStoreAssets/Screenshots/mac-en-US/source');
const out = path.join(root, 'AppStoreAssets/Screenshots/mac-en-US/final');
const names = ['01-batch', '02-before-after', '03-folders', '04-video', '05-looks'];

// Stage the sources next to the page so it can load them with relative paths.
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'underblue-mac-shots-'));
const assets = path.join(work, 'assets');
fs.mkdirSync(assets);
fs.copyFileSync(path.join(__dirname, 'mac.html'), path.join(work, 'mac.html'));
for (const f of fs.readdirSync(source)) fs.copyFileSync(path.join(source, f), path.join(assets, f));

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 2560, height: 1600 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(work, 'mac.html'));
  await page.waitForLoadState('networkidle');
  await page.evaluate(() => Promise.all([...document.images].map(i => i.decode())));
  const sections = await page.locator('section').all();
  if (sections.length !== names.length) throw new Error(`expected ${names.length} sections, got ${sections.length}`);
  for (let i = 0; i < sections.length; i++) {
    const file = path.join(out, names[i] + '.jpg');
    await sections[i].screenshot({ path: file, type: 'jpeg', quality: 95 });
    console.log('wrote', path.relative(root, file));
  }
  await browser.close();
  fs.rmSync(work, { recursive: true, force: true });
})().catch(e => { console.error(e); process.exit(1); });
