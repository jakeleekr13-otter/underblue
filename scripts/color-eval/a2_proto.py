#!/usr/bin/env python3
"""Stage A2 prototype (docs/RestorationExperiments.md): anchors from the photo itself, blended by depth.

main() runs post() (the second try, on our output). proto() is the first try, on the source; it failed (see the doc).

Diagnostic only. Nothing here ships, and nothing reads a reference to build the map.
- Water colour W: mean linear RGB of the far pixels (depth above FAR).
- Light colour E: mean linear RGB of the near pixels (depth below NEAR): grey world on the near scene.
- Object gains turn E grey at its own luminance. Water gains move W to hue WATER_HUE at its own L and chroma.
- The two gain sets are blended per pixel by depth: near = object gains, far = water gains.
Inputs: a harness folder run with HT_EVAL_PNG=1 HT_EVAL_MATTES=1 (<k>__original.png, <k>__combined.png,
<k>__map_depth.png). Usage: a2_proto.py <folder> <outDir>
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
NEAR, FAR, WATER_HUE, WATER_CHROMA = 0.4, 0.8, 245.0, 0.9
M_OKLAB1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M_OKLAB2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])


def to_lin(a): return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
def to_srgb(l): l = np.clip(l, 0, 1); return np.where(l <= 0.0031308, l * 12.92, 1.055 * l ** (1 / 2.4) - 0.055)
def oklab(lin): return np.cbrt(np.maximum(lin, 0) @ M_OKLAB1.T) @ M_OKLAB2.T
def from_oklab(lab): return (lab @ np.linalg.inv(M_OKLAB2).T) ** 3 @ np.linalg.inv(M_OKLAB1).T
def lch(lin):
    L, a, b = oklab(np.asarray(lin, dtype=np.float64)); return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360
def luma(c): return float(np.dot(c, [0.2126, 0.7152, 0.0722]))
def load(p): return np.asarray(Image.open(p).convert("RGB"), dtype=np.float64) / 255


def proto(src_lin, depth, light="near", strength=1.0, cap=4.0):
    flat, d = src_lin.reshape(-1, 3), depth.ravel()
    W = flat[d > FAR].mean(axis=0) if np.count_nonzero(d > FAR) > 100 else flat.mean(axis=0)
    E = flat[d < NEAR].mean(axis=0) if np.count_nonzero(d < NEAR) > 100 else flat.mean(axis=0)
    if light == "water": E = W
    g_obj = np.clip((luma(E) / np.maximum(E, 1e-4)) ** strength, 1 / cap, cap)
    L, C, hw = lch(W)
    # Water already in the blue band keeps its hue; green and cyan water move to WATER_HUE.
    h = math.radians(hw if 235 <= hw <= 265 else WATER_HUE)
    T = from_oklab(np.array([L, C * WATER_CHROMA * math.cos(h), C * WATER_CHROMA * math.sin(h)]))
    g_wat = np.clip(T / np.maximum(W, 1e-4), 1 / cap, cap)
    o = np.clip((0.75 - depth) / 0.4, 0, 1)[..., None]; o = o * o * (3 - 2 * o)
    return src_lin * (o * g_obj + (1 - o) * g_wat), W, E, g_obj, g_wat


def post(src_lin, ours_lin, depth, keep=0.85, cap=1.6, z0=0.3):
    """Current candidate (25 Oct 2026): a correction on top of our own output, not on the source.
    - W: our output's water colour (mean of the far pixels). Its chroma floor is keep x the source's far-water chroma;
      water out of the blue band (hue below 215) moves to hue 235. That is the target water T.
    - Near objects carry W's tint in our output (O6's grey chart reads hue 225). Object gains g take it away with
      strength s = how far the near mean leans toward W (projection on W's a,b over half W's chroma), for all pixels.
    - The veil is added back, not multiplied: out = ours x g + v x (T - W x g), with v the veil share from depth
      (0 below z0, 1 at the far end). Far water becomes T; near objects keep g; seabed in between gets part of the veil.
    Tried and dropped (docs/RestorationExperiments.md): gains blended by a depth mask (seam on O6's sand), by the
    colour water share (O6 reads all water), by a texture mask (blotches), and a colour-space water shift (reef blue)."""
    fo, fs, d = ours_lin.reshape(-1, 3), src_lin.reshape(-1, 3), depth.ravel()
    far = d > FAR
    W = fo[far].mean(axis=0) if np.count_nonzero(far) > 100 else fo.mean(axis=0)
    Ws = fs[far].mean(axis=0) if np.count_nonzero(far) > 100 else fs.mean(axis=0)
    N = fo[d < NEAR].mean(axis=0) if np.count_nonzero(d < NEAR) > 100 else fo.mean(axis=0)
    _, wa, wb = oklab(W); _, na, nb = oklab(N); cw = math.hypot(wa, wb)
    s = float(np.clip(((na * wa + nb * wb) / max(cw, 1e-6)) / (0.5 * max(cw, 1e-6)), 0, 1))
    g = np.clip((luma(W) / np.maximum(W, 1e-4)) ** s, 1 / cap, cap)
    L, C, hw = lch(W)
    h = math.radians(hw if hw >= 215 else 235)
    Ct = max(C, keep * lch(Ws)[1])
    T = from_oklab(np.array([L, Ct * math.cos(h), Ct * math.sin(h)]))
    v = np.clip((depth - z0) / (1 - z0), 0, 1)[..., None]
    return np.clip(ours_lin * g + v * (T - W * g), 0, None), s


def box(img, b):
    h, w = img.shape[:2]; return img[int(b[1] * h):int(b[3] * h), int(b[0] * w):int(b[2] * w)].reshape(-1, 3)


def lab76(lin):
    x = lin @ np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]]).T / np.array([0.95047, 1, 1.08883])
    f = np.where(x > 0.008856, np.cbrt(np.maximum(x, 0)), 7.787 * x + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def main():
    D, out = Path(sys.argv[1]), Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
    res = {}
    for k in ("m5", "m6", "o6", "pl1", "pl2"):
        src = to_lin(load(D / f"{k}__original.png")); ours = to_lin(load(D / f"{k}__combined.png"))
        depth = load(D / f"{k}__map_depth.png")[..., 0]
        p, s = post(src, ours, depth)
        print(f"{k}: object strength s {s:.2f}")
        Image.fromarray((to_srgb(p) * 255 + 0.5).astype(np.uint8)).save(out / f"{k}__proto.png")
        res[k] = (src, ours, p)
    print("\nSea-thru pairs, CIE76 mean (a*b* only):")
    for k in ("m5", "m6"):
        src, ours, p = res[k]; h, w = src.shape[:2]
        ref = to_lin(np.asarray(Image.open(REPO / f"DeveloperMedia/eval/market/ref/{k}.png").convert("RGB").resize((w, h), Image.LANCZOS), dtype=np.float64) / 255)
        R = lab76(ref)
        def e(x, ab=False): d = lab76(x) - R; return np.linalg.norm(d[..., 1:] if ab else d, axis=-1).mean()
        print(f"  {k}: original {e(src):.1f} ({e(src, True):.1f}) | ours {e(ours):.1f} ({e(ours, True):.1f}) | proto {e(p):.1f} ({e(p, True):.1f})")
    src, ours, p = res["m6"]; b = (0.30, 0.80, 0.70, 0.95)
    print("  m6 reef box hue: " + " | ".join(f"{n} {lch(np.median(box(x, b), axis=0))[2]:.0f}" for n, x in (("original", src), ("ours", ours), ("proto", p))) + " | Sea-thru 64")
    patches = [(0.465, 0.825, 0.476, 0.858), (0.483, 0.825, 0.493, 0.858), (0.500, 0.825, 0.510, 0.858), (0.518, 0.825, 0.528, 0.858), (0.536, 0.825, 0.546, 0.858)]
    src, ours, p = res["o6"]
    print("\nO6 chart grey step, mean chroma: " + " | ".join(f"{n} {np.mean([lch(np.median(box(x, b), axis=0))[1] for b in patches]):.3f}" for n, x in (("original", src), ("ours", ours), ("proto", p))) + " | AquaColorFix 0.024")
    print("\nPlants and water (OKLab L / chroma / hue):")
    for k, name, b, plant in (("pl1", "sargassum", (0.32, 0.82, 0.52, 0.95), True), ("pl1", "green water", (0.05, 0.30, 0.30, 0.45), False),
                              ("pl2", "kelp blades", (0.53, 0.14, 0.63, 0.28), True), ("pl2", "teal water", (0.05, 0.10, 0.35, 0.35), False)):
        src, ours, p = res[k]; s = box(src, b)
        mask = np.array([lch(c)[2] < 180 for c in s]) if plant else np.ones(len(s), bool)
        print(f"  {name}: " + " | ".join(f"{n} " + "{:.2f}/{:.3f}/{:.0f}".format(*lch(np.median(box(x, b)[mask], axis=0))) for n, x in (("original", src), ("ours", ours), ("proto", p))))


if __name__ == "__main__":
    main()
