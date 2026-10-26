"""Photo orb prototype, round 2 (docs/RestorationExperiments.md, D3). Diagnostic only.

detect(): soft round bright spots on luma (0-255), several sizes:
  band_s = Gaussian(s) - Gaussian(3.3 s), s in SIZES. A spot is a local maximum of band_s (window 4 s + 1) with
  - band above max(FLOOR, K x the local mean |band| over a 64 px box) and below MAXPEAK levels;
  - in water (colour share >= SHARE), off the subject mask (< SUBJ);
  - isolated: on a ring at 3.3 s the band's spread is below RING x the peak;
  - round: its half-max region fills ROUND of its box, and is at most 40 s^2 px;
  - not in a bubble cluster: at most CLUSTER other bright peaks (any size, band > thr) within 8 s.
  Overlapping finds of different sizes keep the strongest.
fill(): each spot gets the mean of a 3 px ring at 1.3 x its radius, blended over a soft disc.
"""
import numpy as np
from scipy import ndimage

SIZES = (3.0, 4.5, 6.5)
FLOOR, K, MAXPEAK = 0.8, 2.5, 30.0
SHARE, SUBJ, RING, ROUND, CLUSTER = 0.5, 0.3, 0.6, 0.5, 2
# Flat background: the spread of Y on a ring at 1.4-2.4 r is at most FLAT x the local noise spread (plus 0.5 level).
FLAT = 2.0
# Soft, not sharp: the fine band (Gaussian 1 minus 3 px) at the centre is at most SOFT x the spot's band peak.
# A bubble has a bright sharp core; an orb is a soft disc.
SOFT = 0.6
# Depth (when the depth map can be trusted, B2 rule): fill only where the background reads far (water).
FAR = 0.75


def detect(Y, share=None, subj=None, depth=None, trust=0.0):
    H, W = Y.shape
    found = []
    noise = np.sqrt(ndimage.uniform_filter((Y - ndimage.gaussian_filter(Y, 1)) ** 2, 32)) * 1.25
    fine = ndimage.gaussian_filter(Y, 1) - ndimage.gaussian_filter(Y, 3)
    for s in SIZES:
        band = ndimage.gaussian_filter(Y, s) - ndimage.gaussian_filter(Y, 3.3 * s)
        spread = ndimage.uniform_filter(np.abs(band), 64)
        thr = np.maximum(FLOOR, K * spread)
        win = int(4 * s) | 1
        bright = band > thr
        peaks = (band == ndimage.maximum_filter(band, size=win)) & bright & (band < MAXPEAK)
        # bubble clusters: count bright local maxima at the smallest scale near each point
        allpk = (band == ndimage.maximum_filter(band, size=win)) & bright
        dens = ndimage.uniform_filter(allpk.astype(np.float64), int(16 * s) | 1) * (int(16 * s) | 1) ** 2
        rr = 3.3 * s
        ang = np.linspace(0, 2 * np.pi, 16, endpoint=False)
        m = int(np.ceil(rr)) + 2
        for y, x in zip(*np.nonzero(peaks)):
            if y < m or x < m or y >= H - m or x >= W - m: continue
            if share is not None and share[y, x] < SHARE: continue
            if subj is not None and subj[y, x] > SUBJ: continue
            if depth is not None and trust >= 0.5 and depth[y, x] < FAR: continue
            if dens[y, x] - 1 > CLUSTER: continue
            p = band[y, x]
            if fine[y, x] > SOFT * p: continue
            ring = band[(y + rr * np.sin(ang)).astype(int), (x + rr * np.cos(ang)).astype(int)]
            if ring.max() - ring.min() > RING * p: continue
            r0 = int(np.ceil(rr))
            win2 = band[y - r0:y + r0 + 1, x - r0:x + r0 + 1] >= 0.5 * p
            lab, _ = ndimage.label(win2)
            c = lab[r0, r0]
            if c == 0: continue
            reg = lab == c
            area = reg.sum()
            if area > 40 * s * s: continue
            yy, xx = np.nonzero(reg)
            if area / ((np.ptp(yy) + 1) * (np.ptp(xx) + 1)) < ROUND: continue
            r = max(2.5, 1.6 * np.sqrt(area / np.pi))
            R = int(np.ceil(2.4 * r))
            if y < R or x < R or y >= H - R or x >= W - R: continue
            gy, gx = np.mgrid[-R:R + 1, -R:R + 1]
            dd = np.hypot(gx, gy)
            ring2 = Y[y - R:y + R + 1, x - R:x + R + 1][(dd >= 1.4 * r) & (dd <= 2.4 * r)]
            if ring2.std() > FLAT * noise[y, x] + 0.5: continue
            found.append((x, y, p, area, s))
    found.sort(key=lambda f: -f[2])
    kept = []
    for f in found:
        if all(np.hypot(f[0] - g[0], f[1] - g[1]) > 2 * max(f[4], g[4]) for g in kept): kept.append(f)
    return kept


def fill(src, spots):
    out = src.copy()
    H, W = src.shape[:2]
    for x, y, p, area, s in spots:
        r = max(2.5, 1.6 * np.sqrt(area / np.pi))
        y0, y1, x0, x1 = max(0, int(y - 2 * r - 4)), min(H, int(y + 2 * r + 5)), max(0, int(x - 2 * r - 4)), min(W, int(x + 2 * r + 5))
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d = np.hypot(xx - x, yy - y)
        ring = (d >= 1.3 * r) & (d < 1.3 * r + 3)
        if ring.sum() < 8: continue
        c = src[y0:y1, x0:x1][ring].mean(0)
        w = np.clip((1.3 * r - d) / (0.5 * r), 0, 1)[..., None]
        out[y0:y1, x0:x1] = out[y0:y1, x0:x1] * (1 - w) + c * w
    return out


def subtract(src, spots):
    """Takes off only each orb's smooth bump: per channel, the Gaussian(s) image minus the mean of a ring at 1.3 r,
    above zero, over a soft disc. Backscatter adds light on top of the background, so the texture under it stays."""
    out = src.copy()
    H, W = src.shape[:2]
    smooth = {s: np.stack([ndimage.gaussian_filter(src[..., c], s) for c in range(3)], -1) for s in {f[4] for f in spots}}
    for x, y, p, area, s in spots:
        r = max(2.5, 1.6 * np.sqrt(area / np.pi))
        y0, y1, x0, x1 = max(0, int(y - 2 * r - 4)), min(H, int(y + 2 * r + 5)), max(0, int(x - 2 * r - 4)), min(W, int(x + 2 * r + 5))
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d = np.hypot(xx - x, yy - y)
        ring = (d >= 1.3 * r) & (d < 1.3 * r + 3)
        if ring.sum() < 8: continue
        base = src[y0:y1, x0:x1][ring].mean(0)
        bump = np.maximum(0, smooth[s][y0:y1, x0:x1] - base)
        w = np.clip((1.3 * r - d) / (0.5 * r), 0, 1)[..., None]
        out[y0:y1, x0:x1] = out[y0:y1, x0:x1] - w * bump
    return out
