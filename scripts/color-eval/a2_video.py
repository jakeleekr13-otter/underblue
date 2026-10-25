#!/usr/bin/env python3
"""Stage A2 for video, prototype (docs/RestorationExperiments.md). Diagnostic only; nothing here ships.

Video frames render with one constant depth, so the app's photo step (RestorationEngine.objectColour) cannot fade
step 2 by depth. Keyframe analysis does have a depth map, so the values can be made there, per scene.
This script makes the values on the video-path output (`<k>__uniform.png`) with the keyframe depth
(`<k>__map_depth.png`), the same rule as RestorationEngine.objectColourValues, and compares:
- photo: the app's photo rule (step 2 fades by depth 0.6 to 0.9);
- video pXX: no depth fade at render; step 2 starts above the XX-th percentile of the far water's green excess.
Inputs: a harness sheet folder run with HT_EVAL_PNG=1 HT_EVAL_MATTES=1. redLoss per key from HT_EVAL_LOG lines.
Usage: a2_video.py <sheetDir> <analysis log> <outDir>
"""
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from a2_proto import load, lch, luma, oklab, to_lin, to_srgb  # noqa: E402

NEAR, FAR, NEAR_FULL, NEAR_NONE, RED_K = 0.4, 0.8, 0.6, 0.9, 3.0
DIST_LOW, DIST_HIGH, TINT_FLOOR, CAP = 0.10, 0.14, 0.3, 1.6
LUMA = np.array([0.2126, 0.7152, 0.0722])


def values(px, d, red_loss):
    """RestorationEngine.objectColourValues, on linear sRGB. Returns gains, red k, strength, and the far excess list."""
    far, near = px[d > FAR], px[d < NEAR]
    if len(far) <= 100 or len(near) <= 100: return np.ones(3), 0.0, 0.0, None
    W, N = far.mean(0), near.mean(0)
    w, n = oklab(W), oklab(N); cw = math.hypot(w[1], w[2])
    s = min(1, max(0, (n[1] * w[1] + n[2] * w[2]) / cw / (0.5 * cw))) if cw > 1e-6 else 0
    t = min(1, max(0, (np.linalg.norm(n - w) - DIST_LOW) / (DIST_HIGH - DIST_LOW))); s *= t * t * (3 - 2 * t)
    s = s if s >= TINT_FLOOR else 0.0
    g = np.clip((luma(W) / np.maximum(W, 1e-4)) ** s, 1 / CAP, CAP) if s > 0 else np.ones(3)
    fg = far * g
    return g, RED_K * max(0, red_loss), s, fg[:, 1] - 0.5 * (fg[:, 0] + fg[:, 2])


def apply(img, g, k, base, near):
    s = img * g
    e = np.maximum(0, s[..., 1] - 0.5 * (s[..., 0] + s[..., 2]) - base)
    r = s.copy(); r[..., 0] += k * e * near
    return r * ((s @ LUMA) / np.maximum(r @ LUMA, 1e-6))[..., None]


def stats(img, mask):
    L, C, H = lch(np.median(img[mask], axis=0)); return L, C, H


def main():
    D, logf, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]); out.mkdir(parents=True, exist_ok=True)
    red = {m.group(1): float(m.group(2)) for m in re.finditer(r"^(\S+)\.\w+ analysis: redLoss=([\d.e-]+)", logf.read_text(), re.M)}
    print("| still | redLoss | strength | water L/C/h: video path | photo rule | video p50 | video p90 | video p98 | near hue: video path | photo | p90 | mean dE76 p90 vs photo |")
    print("|" + "---|" * 13)
    for k in sorted(red):
        if not (D / f"{k}__uniform.png").exists(): continue
        u = to_lin(load(D / f"{k}__uniform.png")); dm = load(D / f"{k}__map_depth.png")[..., 0]
        dimg = np.asarray(Image.fromarray((dm * 255).astype(np.uint8)).resize(u.shape[1::-1], Image.BILINEAR), dtype=np.float64) / 255
        small = np.asarray(Image.fromarray((to_srgb(u) * 255 + 0.5).astype(np.uint8)).resize(dm.shape[::-1], Image.BOX), dtype=np.float64) / 255
        g, kk, s, fe = values(to_lin(small).reshape(-1, 3), dm.ravel(), red[k])
        far, near = dimg > FAR, dimg < NEAR
        if fe is None:
            print(f"| {k} | {red[k]:.2f} | skip (too few near or far pixels) |"); continue
        w = np.clip((NEAR_NONE - dimg) / (NEAR_NONE - NEAR_FULL), 0, 1); w = (w * w * (3 - 2 * w))[..., None][..., 0]
        photo = apply(u, g, kk, max(0, fe.mean() if len(fe) else 0), w)
        vids = {p: apply(u, g, kk, max(0, np.percentile(fe, p)), np.ones_like(dimg)) for p in (50, 90, 98)}
        f = lambda x, m: "{:.2f}/{:.3f}/{:.0f}".format(*stats(x, m))
        h = lambda x, m: f"{stats(x, m)[2]:.0f}"
        from a2_proto import lab76
        de = np.linalg.norm(lab76(vids[90]) - lab76(photo), axis=-1).mean()
        print(f"| {k} | {red[k]:.2f} | {s:.2f} | {f(u, far)} | {f(photo, far)} | {f(vids[50], far)} | {f(vids[90], far)} | {f(vids[98], far)} | "
              f"{h(u, near)} | {h(photo, near)} | {h(vids[90], near)} | {de:.1f} |")
        for n, x in (("photo", photo), ("p90", vids[90])):
            Image.fromarray((to_srgb(x) * 255 + 0.5).astype(np.uint8)).save(out / f"{k}__{n}.png")


if __name__ == "__main__":
    main()
