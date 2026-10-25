# foreign.py <prefix> <stem> <ways> : brighter / sharper / not foreign metrics, each variant against no lift.
import sys, glob, numpy as np
from PIL import Image
from scipy import ndimage

def oklab(path):
    a = np.asarray(Image.open(path).convert('RGB'), dtype=np.float64) / 255
    a = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    l = np.cbrt(0.4122214708*a[...,0] + 0.5363325363*a[...,1] + 0.0514459929*a[...,2])
    m = np.cbrt(0.2119034982*a[...,0] + 0.6806995451*a[...,1] + 0.1073969566*a[...,2])
    s = np.cbrt(0.0883024619*a[...,0] + 0.2817188376*a[...,1] + 0.6299787005*a[...,2])
    return (0.2104542553*l + 0.7936177850*m - 0.0040720453*s,
            1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
            0.0259040371*l + 0.7827717662*m - 0.8086757660*s)

pre, stem, ways = sys.argv[1], sys.argv[2], sys.argv[3]
S = sys.path[0]
first = sorted(glob.glob(f"{S}/out/{pre}_*_1"))[0]
raw = glob.glob(f"{first}/*_mask_*.raw")[0]
w, h = map(int, raw.rsplit('_', 1)[1][:-4].split('x'))
mask = np.fromfile(raw, dtype=np.float32).reshape(h, w) > 0.5
din = ndimage.distance_transform_edt(mask); dout = ndimage.distance_transform_edt(~mask)
core = din > 4                       # inside, away from the edge
inner = (din >= 3) & (din <= 12); outer = (dout >= 3) & (dout <= 12)
B = 16                               # local contrast windows fully inside the mask
hb, wb = h // B, w // B
full = core[:hb*B, :wb*B].reshape(hb, B, wb, B).all(axis=(1, 3))

flat = None
def metrics(path):
    L, a, b = oklab(path)
    lc = L[:hb*B, :wb*B].reshape(hb, B, wb, B).std(axis=(1, 3))[full].mean()
    grain = (L - ndimage.gaussian_filter(L, 1.5))[flat].std() if flat is not None else 0
    C = np.hypot(a, b); hue = np.degrees(np.arctan2(b, a))
    return dict(L=L, C=C, hue=hue, mean=L[mask].mean(), lc=lc, grain=grain, chroma=C[mask].mean(),
                step=L[inner].mean() - L[outer].mean(), clip=(L[mask] > 0.97).mean())

_b = oklab(glob.glob(f"{first}/{stem}__combined.png")[0])[0]
_win = _b[:hb*B, :wb*B].reshape(hb, B, wb, B).std(axis=(1, 3))
_cut = np.percentile(_win[full], 30)
flat = np.zeros((h, w), bool)
flat[:hb*B, :wb*B] = np.repeat(np.repeat(full & (_win <= _cut), B, 0), B, 1)
base = metrics(glob.glob(f"{first}/{stem}__combined.png")[0])
print(f"{pre}: share {mask.mean():.4f} flat {flat.sum()/mask.sum():.2f} hue-px {(mask & (base['C'] > 0.04)).sum()/mask.sum():.2f}  no lift: L {base['mean']:.3f}, step in-out {base['step']:+.3f}, "
      f"local contrast {base['lc']:.4f}, grain {base['grain']:.4f}, chroma {base['chroma']:.4f}, clip {base['clip']:.4f}")
print("way k     dL x100  localC x  grain x  dChroma x100  hue shift deg  step in-out  clip")
for way in ways:
    for k in ['0.5', '1', '1.5', '2']:
        p = glob.glob(f"{S}/out/{pre}_{way}_{k}/{stem}__lift.png")
        if not p: continue
        m = metrics(p[0])
        sel = mask & (base['C'] > 0.04)
        dh = (m['hue'][sel] - base['hue'][sel] + 180) % 360 - 180
        print(f"{way}   {k:<4}  {100*(m['mean']-base['mean']):+7.2f}  {m['lc']/base['lc']:7.2f}  {m['grain']/base['grain']:7.2f}  "
              f"{100*(m['chroma']-base['chroma']):+11.2f}  {np.abs(dh).mean():13.1f}  {m['step']:+11.3f}  {m['clip']:.4f}")
