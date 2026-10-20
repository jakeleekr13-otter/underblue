"""Builds a draft macOS app icon set from the iPhone icon.

The iPhone icon is a full-bleed square. A Mac icon is a rounded shape that fills 824 of 1024 pixels, with a soft
shadow below it. This draws that shape around the same artwork. It is a draft: the final Mac icon is a design choice.
Run from the repo root: python3 scripts/make_mac_icon.py
"""
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SOURCE = Path('UnderBlue/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
OUT = Path('UnderBlueMac/Assets.xcassets/AppIconMac.appiconset')
CANVAS, BODY = 1024, 824
SCALE = 4  # draw the mask at 4x, then shrink, for smooth edges


def squircle_mask(size: int, exponent: float = 5.0) -> Image.Image:
    """A superellipse |x|^n + |y|^n = 1, close to the Mac icon outline."""
    big = size * SCALE
    mask = Image.new('L', (big, big), 0)
    pixels = mask.load()
    half = big / 2
    for y in range(big):
        dy = abs((y + 0.5 - half) / half) ** exponent
        # Scan only the span where the curve can be inside.
        limit = (1 - dy) ** (1 / exponent) if dy < 1 else 0
        if limit <= 0:
            continue
        start, end = int(half - limit * half), int(half + limit * half)
        for x in range(start, end):
            pixels[x, y] = 255
    return mask.resize((size, size), Image.LANCZOS)


def build() -> Image.Image:
    art = Image.open(SOURCE).convert('RGB').resize((BODY, BODY), Image.LANCZOS)
    mask = squircle_mask(BODY)
    canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - BODY) // 2
    # Shadow: the same shape, blurred, moved down 12 px, 35 percent dark.
    shadow = Image.new('L', (CANVAS, CANVAS), 0)
    shadow.paste(mask, (offset, offset + 12))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.35))
    canvas.paste(Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 255)), (0, 0), shadow)
    body = art.convert('RGBA')
    body.putalpha(mask)
    canvas.alpha_composite(body, (offset, offset))
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    master = build()
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            name = f'icon_{points}x{points}' + ('@2x' if scale == 2 else '') + '.png'
            master.resize((pixels, pixels), Image.LANCZOS).save(OUT / name)
            images.append({'idiom': 'mac', 'scale': f'{scale}x', 'size': f'{points}x{points}', 'filename': name})
    (OUT / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    (OUT.parent / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    print(f'wrote {len(images)} images to {OUT}')


main()
