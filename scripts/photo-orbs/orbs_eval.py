"""D3 evaluation. Step "fill": detect on each original, write filled sources. Step "score": compare our output of the
original with our output of the filled source.
  orbs left: detect() on each output's luma (same rules, water and not subject from the original's maps).
  safety: mean |difference| (8-bit, all channels) between the two outputs inside the subject mask (> 0.5) and inside
  bubble clusters (pixels within 24 px of 6+ bright small peaks of the original), and the share of pixels changed > 3.
Usage: orbs_eval.py fill <sheetDir> <outDir> <keys...> | score <sheetDir> <filledSheetDir> <keys...>
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, sys.path[0])
from orbs2 import detect, fill, subtract
import os
FILL = subtract if os.environ.get('ORB_FILL') == 'subtract' else fill


def luma(a): return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
def load(p): return np.asarray(Image.open(p).convert("RGB"), dtype=np.float64)
def mp(D, k, n, shape):
    try: return np.asarray(Image.open(f"{D}/{k}__map_{n}.png").convert("L").resize(shape[::-1], Image.BILINEAR), dtype=np.float64) / 255
    except FileNotFoundError: return None


def trust_of(depth, share):
    """RestorationEngine.depthTrust: correlation of depth and colour share, 0.45 none to 0.6 full (smoothstep)."""
    if depth is None or share is None: return 0.0
    r = np.corrcoef(depth.ravel()[::7], share.ravel()[::7])[0, 1]
    t = min(1, max(0, (r - 0.45) / 0.15)); return t * t * (3 - 2 * t)


mode, D = sys.argv[1], sys.argv[2]
if mode == "fill":
    out = sys.argv[3]
    for k in sys.argv[4:]:
        src = load(f"{D}/{k}__original.png"); Y = luma(src)
        share, depth = mp(D, k, "share", Y.shape), mp(D, k, "depth", Y.shape)
        trust = trust_of(depth, share)
        spots = detect(Y, share, mp(D, k, "subject", Y.shape), depth, trust)
        print(f"{k}: depth trust {trust:.2f}")
        Image.fromarray(np.clip(FILL(src, spots) + 0.5, 0, 255).astype(np.uint8)).save(f"{out}/{k}.png")
        print(f"{k}: filled {len(spots)} spots (sizes {dict(zip(*np.unique([s[4] for s in spots], return_counts=True))) if spots else {}})")
else:
    F = sys.argv[3]
    print("photo | orbs left: ours -> ours with fill | changed > 3 | subject |diff| | bubble-cluster |diff|")
    for k in sys.argv[4:]:
        o = load(f"{D}/{k}__original.png"); a = load(f"{D}/{k}__combined.png")
        b = load(f"{D}/{k}__altcombined.png") if F == "alt" else load(f"{F}/{k}__combined.png")
        share, subj = mp(D, k, "share", o.shape[:2]), mp(D, k, "subject", o.shape[:2])
        depth = mp(D, k, "depth", o.shape[:2]); trust = trust_of(depth, share)
        na, nb = len(detect(luma(a), share, subj, depth, trust)), len(detect(luma(b), share, subj, depth, trust))
        Y = luma(o)
        band = ndimage.gaussian_filter(Y, 1.5) - ndimage.gaussian_filter(Y, 5)
        pk = (band == ndimage.maximum_filter(band, size=5)) & (band > 6)
        dens = ndimage.uniform_filter(pk.astype(np.float64), 49) * 49 ** 2
        bubbles = dens >= 6
        d = np.abs(a - b).max(-1)
        sub = f"{d[subj > 0.5].mean():.2f}" if subj is not None and (subj > 0.5).any() else "no mask"
        bub = f"{d[bubbles].mean():.2f} ({100 * bubbles.mean():.1f}% of frame)" if bubbles.any() else "none"
        print(f"{k} | {na} -> {nb} | {100 * np.mean(d > 3):.2f}% | {sub} | {bub}")
