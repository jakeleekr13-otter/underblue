#!/usr/bin/env python3
"""Neutral patches of the colour chart in AquaColorFix pair 6 (O6/A6, added 25 Oct 2026).

The chart's top row is a grey step from white to mid grey. Every patch should come out colourless, so it is a
stricter neutral check than the sand and manta boxes in tune_report.py. Boxes are inner parts of each patch
(fractions of the 750 x 562 frame), checked by eye on O6 and A6. The sixth patch touches the chart frame and is left out.
Usage: chart_check.py <aquacolorfix_eval output folder>
"""
import math
import sys

import numpy as np
from PIL import Image

PATCHES = [(0.465, 0.825, 0.476, 0.858), (0.483, 0.825, 0.493, 0.858), (0.500, 0.825, 0.510, 0.858),
           (0.518, 0.825, 0.528, 0.858), (0.536, 0.825, 0.546, 0.858)]


def lch(rgb):
    a = np.asarray(rgb, dtype=np.float64) / 255
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    l = np.cbrt(lin @ np.array([0.4122214708, 0.5363325363, 0.0514459929]))
    m = np.cbrt(lin @ np.array([0.2119034982, 0.6806995451, 0.1073969566]))
    s = np.cbrt(lin @ np.array([0.0883024619, 0.2817188376, 0.6299787005]))
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return float(L), math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360


def main():
    out = sys.argv[1]
    files = [("original", f"{out}/sheet/p6__original.jpg"), ("ours", f"{out}/sheet/p6__combined.jpg"),
             ("ours (video path)", f"{out}/sheet/p6__uniform.jpg"), ("AquaColorFix", f"{out}/ref/p6.png")]
    print("chart neutral patches (pair 6), OKLab L / chroma / hue; 0 chroma = colourless")
    print("| patch | " + " | ".join(n for n, _ in files) + " |")
    means = {n: [] for n, _ in files}
    for i, (x0, y0, x1, y1) in enumerate(PATCHES, 1):
        cells = []
        for n, p in files:
            im = Image.open(p).convert("RGB"); w, h = im.size
            box = np.asarray(im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))).reshape(-1, 3)
            L, C, H = lch(np.median(box, axis=0)); means[n].append(C)
            cells.append(f"{L:.2f} / {C:.3f} / {H:.0f}")
        print(f"| {i} | " + " | ".join(cells) + " |")
    print("| mean chroma | " + " | ".join(f"{np.mean(v):.3f}" for v in means.values()) + " |")


if __name__ == "__main__":
    main()
