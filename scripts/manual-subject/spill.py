# spill.py <outDir>...: OKLab L change (lift - combined) x100 in rings outside the press mask, and inside it.
import sys, glob, os, numpy as np
from PIL import Image
from scipy import ndimage
def okl(path):
    a = np.asarray(Image.open(path).convert('RGB'), dtype=np.float64) / 255
    a = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    l = 0.4122214708*a[...,0] + 0.5363325363*a[...,1] + 0.0514459929*a[...,2]
    m = 0.2119034982*a[...,0] + 0.6806995451*a[...,1] + 0.1073969566*a[...,2]
    s = 0.0883024619*a[...,0] + 0.2817188376*a[...,1] + 0.6299787005*a[...,2]
    return 0.2104542553*np.cbrt(l) + 0.7936177850*np.cbrt(m) - 0.0040720453*np.cbrt(s)
for d in sys.argv[1:]:
    raw = glob.glob(os.path.join(d, '*_mask_*.raw'))[0]
    w, h = map(int, raw.rsplit('_', 1)[1][:-4].split('x'))
    mask = np.fromfile(raw, dtype=np.float32).reshape(h, w) > 0.5
    comb = glob.glob(os.path.join(d, '*__combined.png'))[0]; lift = comb.replace('__combined', '__lift')
    dl = (okl(lift) - okl(comb)) * 100
    dist = ndimage.distance_transform_edt(~mask)
    def ring(a, b): r = (dist >= a) & (dist <= b); return dl[r].mean(), np.percentile(dl[r], 99), r.sum()
    r1 = ring(2, 10); r2 = ring(2, 40); r3 = ring(11, 40)
    print(f"{os.path.basename(d)}: {w}x{h} share={mask.mean():.4f} inside median={np.median(dl[mask]):.2f} "
          f"ring2-40 mean={r2[0]:.2f} p99={r2[1]:.2f} | ring2-10 mean={r1[0]:.2f} p99={r1[1]:.2f} | ring11-40 mean={r3[0]:.2f}")
