#!/usr/bin/env python3
"""Stage A1 of docs/RestorationExperiments.md: ceiling test for a global cross-channel map.

Diagnostic only. Nothing here ships. For each pair it fits a linear 3x3 map with an offset in linear RGB,
on a random 70% of the pixels, and scores the other 30% in CIE76:
  fit(source -> reference)  how close one global map gets to the reference
  ours                      our render against the same reference, on the same test pixels
  fit(source -> ours)       how close one global map gets to our own render (small = our pipeline is near global)
Usage: a1_ceiling.py <tuneOut> <aquaOut> <outDir>
  tuneOut  a tune_eval.sh output folder (market/m5__combined.jpg ...)
  aquaOut  an aquacolorfix_eval.sh output folder (sheet/p1__combined.jpg ...)
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
from aquacolorfix_benchmark import linear_to_lab, linear_to_oklab, srgb_to_linear, watermark_mask  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DATA = REPO / "DeveloperMedia/eval"
# The reef under the manta: olive-green on our photo path, brown on Sea-thru (docs/ColorAlgorithm.md).
M6_REEF = (0.30, 0.80, 0.70, 0.95)


def load(path, size=None):
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        if size and im.size != size:
            im = im.resize(size, Image.Resampling.LANCZOS)
        return np.asarray(im, dtype=np.float64) / 255


def to_srgb(lin):
    lin = np.clip(lin, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)


def fit(src_lin, dst_lin, train):
    x = np.column_stack((src_lin[train], np.ones(len(train))))
    return np.linalg.lstsq(x, dst_lin[train], rcond=None)[0]  # 4x3: rows R, G, B, offset


def apply(coef, lin):
    flat = lin.reshape(-1, 3)
    return (np.column_stack((flat, np.ones(len(flat)))) @ coef).reshape(lin.shape)


def cie76(a_lin, b_lin, chroma_only=False):
    d = linear_to_lab(np.clip(a_lin, 0, 1)) - linear_to_lab(np.clip(b_lin, 0, 1))
    return np.linalg.norm(d[..., 1:] if chroma_only else d, axis=-1)


def box_oklab(srgb, box):
    h, w = srgb.shape[:2]
    x0, y0, x1, y1 = box
    med = np.median(srgb[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)].reshape(-1, 3), axis=0)
    L, a, b = linear_to_oklab(srgb_to_linear(med))
    return f"{L:.2f}/{math.hypot(a, b):.3f}/{math.degrees(math.atan2(b, a)) % 360:.0f}"


def main():
    tune, aqua, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    pairs = [(k, DATA / f"market/raw/{k}.png", DATA / f"market/ref/{k}.png", tune / f"market/{k}__combined.jpg", False)
             for k in ("m5", "m6")]
    pairs += [(f"p{n}", next(DATA.glob(f"aquacolorfix/O{n}.*")), next(DATA.glob(f"aquacolorfix/A{n}.*")),
               aqua / f"sheet/p{n}__combined.jpg", True) for n in range(1, 6)]
    # The a*b* columns leave out L*: our target look is a little brighter than the references on purpose.
    print("| pair | ours | fit src->ref | gain | fit src->ours | ours a*b* | fit a*b* |")
    coefs = {}
    for i, (name, src_p, ref_p, ours_p, marked) in enumerate(pairs):
        ours = load(ours_p)
        size = (ours.shape[1], ours.shape[0])
        src, ref = load(src_p, size), load(ref_p, size)
        valid = watermark_mask(size[1], size[0]) if marked else np.ones((size[1], size[0]), bool)
        s, r, o = (srgb_to_linear(x).reshape(-1, 3) for x in (src, ref, ours))
        usable = np.flatnonzero(valid.ravel() & (s.max(axis=1) > 0.0016) & (s.min(axis=1) < 0.96))
        idx = np.random.default_rng(100 + i).permutation(usable)[:100_000]
        cut = int(len(idx) * 0.7)
        train, test = idx[:cut], idx[cut:]
        c_ref, c_ours = fit(s, r, train), fit(s, o, train)
        e_ours = cie76(o[test], r[test]).mean()
        e_fit = cie76(apply(c_ref, s[test]), r[test]).mean()
        e_self = cie76(apply(c_ours, s[test]), o[test]).mean()
        ab_ours = cie76(o[test], r[test], True).mean()
        ab_fit = cie76(apply(c_ref, s[test]), r[test], True).mean()
        print(f"| {name} | {e_ours:.1f} | {e_fit:.1f} | {e_ours - e_fit:+.1f} | {e_self:.1f} | {ab_ours:.1f} | {ab_fit:.1f} |")
        coefs[name] = (c_ref, c_ours)
        fitted = to_srgb(apply(c_ref, srgb_to_linear(src)))
        Image.fromarray((np.clip(fitted, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out / f"{name}__fit.jpg", quality=90)
        Image.fromarray((src * 255 + 0.5).astype(np.uint8)).save(out / f"{name}__source.jpg", quality=90)
        Image.fromarray((ref * 255 + 0.5).astype(np.uint8)).save(out / f"{name}__reference.jpg", quality=90)
        Image.fromarray((ours * 255 + 0.5).astype(np.uint8)).save(out / f"{name}__ours.jpg", quality=90)
        if name == "m6":
            reef = {v: box_oklab(x, M6_REEF) for v, x in (("source", src), ("ours", ours), ("fit", fitted), ("reference", ref))}
    print("\nm6 reef box, OKLab L/chroma/hue (brown is about hue 40-70):")
    print(" | ".join(f"{k} {v}" for k, v in reef.items()))
    print("\nFit coefficients, linear RGB. Column = output channel, row = input R, G, B, offset.")
    for name, (c_ref, c_ours) in coefs.items():
        for label, c in (("src->ref", c_ref), ("src->ours", c_ours)):
            print(f"{name} {label}: R<-(R {c[0,0]:.2f}, G {c[1,0]:.2f}, B {c[2,0]:.2f}, +{c[3,0]:.3f})  "
                  f"G<-(R {c[0,1]:.2f}, G {c[1,1]:.2f}, B {c[2,1]:.2f})  B<-(R {c[0,2]:.2f}, G {c[1,2]:.2f}, B {c[2,2]:.2f})")


if __name__ == "__main__":
    main()
