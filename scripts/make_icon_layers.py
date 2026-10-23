"""Write the app icon's three waves as SVG layers for Icon Composer.

The waves use the same curve as make_icon.py: y = offset + 45 sin(2 pi (x - 240) / 540), x from 230 to 794.
Each wave is its own 1024 x 1024 SVG with a transparent background, so Icon Composer keeps its position.
Drag the Waves folder into the Icon Composer sidebar: the folder becomes a group, each file a layer.
The background is not a layer. Set it in Icon Composer as a fill: #081C22.
Run from the repo root: python3 scripts/make_icon_layers.py
"""
import math
from pathlib import Path

OUT = Path('AppStoreAssets/IconComposer/Waves')
WAVES = {'wave-1-top': 342, 'wave-2-middle': 502, 'wave-3-bottom': 662}
COLOR, WIDTH = '#6AE6C8', 44  # 44, not 48: make_icon.py measures thickness vertically, so its slopes are thinner


def wave_path(offset):
    points = [(x, offset + 45 * math.sin((x - 240) * 2 * math.pi / 540)) for x in range(230, 795, 2)]
    return 'M' + ' L'.join(f'{x},{y:.2f}' for x, y in points)


OUT.mkdir(parents=True, exist_ok=True)
for name, offset in WAVES.items():
    (OUT / f'{name}.svg').write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
        f'  <path d="{wave_path(offset)}" fill="none" stroke="{COLOR}" stroke-width="{WIDTH}" '
        'stroke-linecap="round" stroke-linejoin="round"/>\n'
        '</svg>\n')
