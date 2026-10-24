"""Builds AppStoreAssets/Screenshots/<locale>/source from device captures in that language.

The captures come from UnderBlueUITests/LocalizedScreenshotTests (see capture_device.sh). They give the UI text
in the language. The photo and video areas and the status bar are copied from en-US/source, so every language
shows the same pictures and the same clock. The media area can sit at a different height in a newer app build,
so this script finds it in each capture, pastes the en-US area there, and writes layout.json for render.js.
Hand-set positions per language (for example the screen 05 badge) come from layout_overrides.json.
Run from the repo root: python3 scripts/app_store_screenshots/compose_sources.py <locale> <captures folder>
The captures folder holds home.png, photo_after.png, photo_before.png, video_after.png and video_before.png.
"""
import json
import sys
from pathlib import Path
from PIL import Image

SHOTS = Path('AppStoreAssets/Screenshots')
OVERRIDES = Path(__file__).with_name('layout_overrides.json')
STATUS_BAR = 170  # rows; the clock, signal and battery, above the back button
EDIT_SCREENS = {'photo': ('photo_after', 'photo_before'), 'video': ('video_after', 'video_before')}


def media_rows(image: Image.Image) -> tuple[int, int]:
    """The longest run of non-black rows between the top bar and the controls: the photo or video."""
    gray = image.convert('L')
    width, _ = gray.size
    pixels = gray.load()
    bright = [sum(pixels[x, y] for x in range(0, width, 6)) / len(range(0, width, 6)) > 18 for y in range(1600)]
    best, y = (0, 0), 250
    while y < 1600:
        if bright[y]:
            start = y
            while y < 1600 and bright[y]:
                y += 1
            if y - start > best[1] - best[0]:
                best = (start, y)
        y += 1
    return best


def main(locale: str, captures: Path) -> None:
    english = SHOTS / 'en-US/source'
    out = SHOTS / locale / 'source'
    out.mkdir(parents=True, exist_ok=True)
    layout = {}
    for name in ['home', *[n for pair in EDIT_SCREENS.values() for n in pair]]:
        shot = Image.open(captures / f'{name}.png').convert('RGB')
        source = Image.open(english / f'{name}.PNG').convert('RGB')
        assert shot.size == source.size == (1206, 2622), (name, shot.size, source.size)
        shot.paste(source.crop((0, 0, 1206, STATUS_BAR)), (0, 0))
        kind = next((k for k, pair in EDIT_SCREENS.items() if name in pair), None)
        if kind:
            top, bottom = media_rows(shot)
            source_top, source_bottom = media_rows(source)
            height = min(bottom - top, source_bottom - source_top)
            assert abs((bottom - top) - (source_bottom - source_top)) <= 2, (name, top, bottom, source_top, source_bottom)
            shot.paste(source.crop((0, source_top, 1206, source_top + height)), (0, top))
            h = shot.size[1]
            area = {f'{kind}-top': f'{top / h * 100:.3f}%', f'{kind}-bottom': f'{(h - top - height) / h * 100:.3f}%',
                    f'{kind}-mid': f'{(top + height / 2) / h * 100:.3f}%'}
            assert layout.get(f'{kind}-top', area[f'{kind}-top']) == area[f'{kind}-top'], (name, 'after and before differ')
            layout.update(area)
            print(f'{name}: media rows {top}-{top + height} (en-US {source_top}-{source_top + height})')
        shot.save(out / f'{name}.PNG')
    layout.update(json.loads(OVERRIDES.read_text()).get(locale, {}) if OVERRIDES.exists() else {})
    (out / 'layout.json').write_text(json.dumps(layout, indent=2) + '\n')
    print('wrote', out)


if __name__ == '__main__':
    main(sys.argv[1], Path(sys.argv[2]))
