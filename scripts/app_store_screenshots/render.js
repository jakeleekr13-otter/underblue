// Render App Store screenshots from AppStoreAssets/Screenshots/<locale>/source.
// Output: AppStoreAssets/Screenshots/<locale>/final, 1320 x 2868 JPEG, no alpha.
// The locale defaults to en-US. Other locales take their captions from captions.json.
// A capture missing from <locale>/source falls back to en-US/source, with a warning.
// Run from the repo root: npm i --no-save playwright && node scripts/app_store_screenshots/render.js [locale]
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const locale = process.argv[2] || 'en-US';
const shots = path.join(root, 'AppStoreAssets/Screenshots');
const out = path.join(shots, locale, 'final');
const names = ['01-before-after', '02-photo', '03-video', '04-looks', '05-private'];
const captions = locale === 'en-US' ? {} : JSON.parse(fs.readFileSync(path.join(__dirname, 'captions.json'), 'utf8'))[locale];
if (!captions) throw new Error(`no captions for ${locale} in captions.json`);

function sourceFile(file) {
  const own = path.join(shots, locale, 'source', file);
  if (fs.existsSync(own)) return own;
  console.warn(`warning: ${locale}/source/${file} missing, using en-US`);
  return path.join(shots, 'en-US/source', file);
}
// Where the photo and video sit on this language's edit screens (compose_sources.py writes it).
const layoutFile = path.join(shots, locale, 'source', 'layout.json');
const layout = fs.existsSync(layoutFile) ? JSON.parse(fs.readFileSync(layoutFile, 'utf8')) : {};

// Chromium cannot read HEIC, so stage every source as PNG or JPEG next to the page.
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'underblue-shots-'));
const assets = path.join(work, 'assets');
fs.mkdirSync(assets);
fs.copyFileSync(path.join(__dirname, 'screens.html'), path.join(work, 'screens.html'));
for (const n of ['home', 'photo_before', 'photo_after', 'video_before', 'video_after']) {
  fs.copyFileSync(sourceFile(n + '.PNG'), path.join(assets, n + '.png'));
}
// The video frame pair has no UI, so every language uses en-US. Mirrored, so the clownfish in
// screenshot 01 faces right (see screens.html).
for (const n of ['video_frame_before', 'video_frame_after']) {
  execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '95', '--flip', 'horizontal',
    path.join(shots, 'en-US/source', n + '.HEIC'), '--out', path.join(assets, n + '.jpg')], { stdio: 'ignore' });
}

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1320, height: 2868 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(work, 'screens.html'));
  await page.waitForLoadState('networkidle');
  // lang picks the right CJK glyphs (Japanese and Chinese share code points).
  const missing = await page.evaluate(([lang, t, vars]) => {
    document.documentElement.lang = lang;
    for (const [name, value] of Object.entries(vars)) document.documentElement.style.setProperty('--' + name, value);
    if (lang === 'en-US') return [];
    const keys = [];
    for (const el of document.querySelectorAll('[data-t]')) {
      if (el.dataset.t in t) el.innerHTML = t[el.dataset.t]; else keys.push(el.dataset.t);
    }
    return keys;
  }, [locale, captions, layout]);
  if (missing.length) throw new Error(`captions.json ${locale} lacks: ${[...new Set(missing)].join(', ')}`);
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
