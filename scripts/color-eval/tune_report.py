import csv, sys, os, math
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
O = sys.argv[1]
def load(p):
    rows = {}
    for r in csv.DictReader(open(p)): rows.setdefault(r["image"], {})[r["variant"]] = r
    return rows
def f(r, k): return float(r[k])
def table(title, rows, names=None):
    print(f"\n== {title}")
    print("| image | dE orig -> ours (video path) | meanL ours/ref | localContrast ours/ref | Lab farHue ours/ref (orig) | farChroma ours/ref | nearRG ours/ref | OKLab water hue ours/ref (orig) |")
    for k in (names or sorted(rows)):
        if k not in rows or k.startswith("n_"): continue
        v = rows[k]; o, c, u, r = v["original"], v["combined"], v.get("uniform", v["combined"]), v["reference"]
        print(f"| {k} | {f(o,'deltaE'):.1f} -> {f(c,'deltaE'):.1f} ({f(u,'deltaE'):.1f}) | {f(c,'meanL'):.1f}/{f(r,'meanL'):.1f} | {f(c,'localContrast'):.2f}/{f(r,'localContrast'):.2f} | "
              f"{f(c,'farHue'):.0f}/{f(r,'farHue'):.0f} ({f(o,'farHue'):.0f}) | {f(c,'farChroma'):.1f}/{f(r,'farChroma'):.1f} | {f(c,'nearRG'):.2f}/{f(r,'nearRG'):.2f} |"
              + (f" {f(c,'farHueOK'):.0f}/{f(r,'farHueOK'):.0f} ({f(o,'farHueOK'):.0f}) |" if 'farHueOK' in c else ""))
def lab_chroma(p):
    a = np.asarray(Image.open(p).convert("RGB")).astype(np.float64) / 255
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = lin @ M.T / np.array([0.95047, 1.0, 1.08883])
    fx = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    A = 500 * (fx[..., 0] - fx[..., 1]); B = 200 * (fx[..., 1] - fx[..., 2])
    return float(np.sqrt(A * A + B * B).max()), float(np.sqrt(A * A + B * B).mean())
def sheet(folder, names, cols, out, W=240):
    rows = []
    for n in names:
        stem = n.rsplit(".", 1)[0]
        ims = []
        for _, v in cols:
            p = f"{folder}/{stem}__{v}.jpg"
            if os.path.exists(p): ims.append(Image.open(p).convert("RGB"))
        if not ims: continue
        h = int(ims[0].height * W / ims[0].width); rows.append([i.resize((W, h)) for i in ims])
    if not rows: return
    H = sum(r[0].height for r in rows) + 18
    sh = Image.new("RGB", (W * len(cols), H), "white"); d = ImageDraw.Draw(sh)
    for i, (t, _) in enumerate(cols): d.text((i * W + 5, 3), t, fill="black")
    y = 18
    for r in rows:
        for i, im in enumerate(r): sh.paste(im, (i * W, y))
        y += r[0].height
    sh.save(out, quality=88)
cols = [("before", "original"), ("ours", "combined"), ("ours (video path)", "uniform"), ("target", "reference")]
m = load(f"{O}/market.csv")
table("MARKET target pairs (ref = market 'after'; m3 is a creative mood grade; m5 and m6 are Sea-thru results)", m, ["m1.png", "m2.png", "m3.png", "m4.png", "m5.png", "m6.png"])
if os.path.exists(f"{O}/real.csv"):
    rr = load(f"{O}/real.csv")
    print("\n== REAL user dive photos (no reference). r01-r13 are blue or deep-blue scenes. r14 and r15 are the user's GREEN/TEAL examples: r14 has teal sand under deep blue water, r15 is a diver in teal water; both must move toward clear cyan-blue water with natural skin/subject colour (the committed code leaves r15 almost unchanged and pushes r14's upper water to indigo, hue 292). Aim: water OKLab hue about 215-265 (cyan to blue; indigo 270-282 and violet >=282 are failures), water chroma natural (roughly 15-35, not neon), subject nearRG up toward 0.9-1.1. r04 has a real magenta anemone: keep it magenta. r10 is a bright backlit sun scene.")
    print("| image | water OKLab hue orig -> ours (video) [cyan <235, blue 235-270, indigo 270-282, violet >=282] | farChroma orig -> ours | nearRG orig -> ours | meanL orig -> ours | localContrast orig -> ours |")
    for k in sorted(rr):
        v = rr[k]; o, c, u = v["original"], v["combined"], v.get("uniform", v["combined"])
        ok = "farHueOK" in o
        hk = 'farHueOK' if ok else 'farHue'
        print(f"| {k} | {f(o,hk):.0f} -> {f(c,hk):.0f} ({f(u,hk):.0f}) | {f(o,'farChroma'):.1f} -> {f(c,'farChroma'):.1f} | {f(o,'nearRG'):.2f} -> {f(c,'nearRG'):.2f} | {f(o,'meanL'):.1f} -> {f(c,'meanL'):.1f} | {f(o,'localContrast'):.2f} -> {f(c,'localContrast'):.2f} |")
    sheet(f"{O}/real", sorted(rr), [("before", "original"), ("ours", "combined"), ("ours (video path)", "uniform")], f"{O}/real_sheet.jpg", W=300)
# Neutral surfaces: regions that should be colourless after correction (per-channel median in a fixed box).
def ok_lab(rgb):
    a = np.asarray(rgb, dtype=np.float64) / 255
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    l = np.cbrt(lin @ np.array([0.4122214708, 0.5363325363, 0.0514459929]))
    mm = np.cbrt(lin @ np.array([0.2119034982, 0.6806995451, 0.1073969566]))
    ss = np.cbrt(lin @ np.array([0.0883024619, 0.2817188376, 0.6299787005]))
    L = 0.2104542553 * l + 0.7936177850 * mm - 0.0040720468 * ss
    A = 1.9779984951 * l - 2.4285922050 * mm + 0.4505937099 * ss
    B = 0.0259040371 * l + 0.7827717662 * mm - 0.8086757660 * ss
    return float(L), float(A), float(B)
def ok_chroma(rgb):
    _, A, B = ok_lab(rgb)
    return float(np.hypot(A, B))
def box_median(p, box):
    im = Image.open(p).convert("RGB"); w, h = im.size; x0, y0, x1, y1 = box
    return np.median(np.asarray(im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))).reshape(-1, 3), axis=0)
NEUTRAL = [("m5", "sand", (0.70, 0.88, 0.85, 0.98)), ("m5", "chart grey row (approx.)", (0.618, 0.839, 0.663, 0.849)),
           ("m6", "manta belly", (0.44, 0.38, 0.56, 0.50))]
if all(os.path.exists(f"{O}/market/{k}__original.jpg") for k, _, _ in NEUTRAL):
    print("\n== NEUTRAL SURFACES (OKLab chroma of the box median; 0 = colourless; Sea-thru = the market 'after')")
    print("| surface | original | ours | ours (video path) | Sea-thru |")
    for k, name, (x0, y0, x1, y1) in NEUTRAL:
        vals = []
        for v in ["original", "combined", "uniform", "reference"]:
            im = Image.open(f"{O}/market/{k}__{v}.jpg").convert("RGB"); w, h = im.size
            box = np.asarray(im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))).reshape(-1, 3)
            vals.append(ok_chroma(np.median(box, axis=0)))
        print(f"| {k} {name} | " + " | ".join(f"{x:.3f}" for x in vals) + " |")
# Black gear (Stage C, docs/RestorationExperiments.md): wetsuits and BCDs must stay dark and colourless, not turn brown.
# Pass rule: OKLab L < 0.35 and hue outside 40-90 (orange-brown) when chroma >= 0.02. Chroma may rise by 0.01 at most
# over the baseline table in the doc, so compare it there.
BLACK = [("real", "r15", "wetsuit chest, teal water", (0.52, 0.88, 0.64, 0.98)),
         ("real", "r12", "BCD chest, deep blue cast", (0.42, 0.43, 0.48, 0.50)),
         ("guard", "g1", "wetsuit torso (DSC03696)", (0.61, 0.385, 0.645, 0.41)),
         ("guard", "g1", "BCD bladder (DSC03696)", (0.685, 0.345, 0.705, 0.40))]
def black_cell(rgb):
    L, A, B = ok_lab(rgb); C = math.hypot(A, B); hue = math.degrees(math.atan2(B, A)) % 360
    flags = (" BROWN" if C >= 0.02 and 40 <= hue <= 90 else "") + (" LIGHT" if L >= 0.35 else "")
    return f"{L:.2f} / {C:.3f} / {hue:.0f}{flags}"
if all(os.path.exists(f"{O}/{d}/{k}__original.jpg") for d, k, _, _ in BLACK):
    print("\n== BLACK GEAR (box median, OKLab L / chroma / hue; flags: BROWN = hue 40-90 at chroma >= 0.02, LIGHT = L >= 0.35;"
          " chroma: compare with the baseline in docs/RestorationExperiments.md)")
    print("| surface | original | ours | ours (video path) |")
    for d, k, name, box in BLACK:
        print(f"| {k} {name} | " + " | ".join(black_cell(box_median(f"{O}/{d}/{k}__{v}.jpg", box)) for v in ["original", "combined", "uniform"]) + " |")
# Plants and their water (Stage C). Plants must keep their colour while the water around them turns cyan or blue.
# Plant pixels = pixels of the box whose ORIGINAL OKLab hue is below 180 (the water in these photos sits at 150-215,
# the kelp blades at 150-170), so water between the leaves stays out. The same pixels are read in every output.
PLANTS = [("guard", "pl1", "sargassum foreground", (0.32, 0.82, 0.52, 0.95)),
          ("guard", "pl1", "sargassum right cluster", (0.63, 0.72, 0.74, 0.84)),
          ("guard", "pl2", "kelp blades", (0.53, 0.14, 0.63, 0.28)),
          ("guard", "pl2", "kelp stipe", (0.49, 0.33, 0.56, 0.41))]
PLANT_WATER = [("guard", "pl1", "green water", (0.05, 0.30, 0.30, 0.45)),
               ("guard", "pl2", "teal water", (0.05, 0.10, 0.35, 0.35))]
def ok_lab_px(a):
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    l = np.cbrt(lin @ np.array([0.4122214708, 0.5363325363, 0.0514459929]))
    mm = np.cbrt(lin @ np.array([0.2119034982, 0.6806995451, 0.1073969566]))
    ss = np.cbrt(lin @ np.array([0.0883024619, 0.2817188376, 0.6299787005]))
    A = 1.9779984951 * l - 2.4285922050 * mm + 0.4505937099 * ss
    B = 0.0259040371 * l + 0.7827717662 * mm - 0.8086757660 * ss
    return np.degrees(np.arctan2(B, A)) % 360
def box_pixels(p, box):
    im = Image.open(p).convert("RGB"); w, h = im.size; x0, y0, x1, y1 = box
    return np.asarray(im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))).reshape(-1, 3)
def lch(rgb):
    L, A, B = ok_lab(rgb); return L, math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360
if all(os.path.exists(f"{O}/{d}/{k}__original.jpg") for d, k, _, _ in PLANTS):
    print("\n== PLANTS (median of the box's plant pixels, OKLab L / chroma / hue; flags: GREY = chroma below 0.6 x original,"
          " HUE = hue outside 60-160, golden-brown algae to green seagrass; compare with the baseline in docs/RestorationExperiments.md)")
    print("| plant | plant share | original | ours | ours (video path) |")
    for d, k, name, box in PLANTS:
        src = box_pixels(f"{O}/{d}/{k}__original.jpg", box)
        mask = ok_lab_px(src / 255) < 180
        cells, c0 = [], None
        for v in ["original", "combined", "uniform"]:
            L, C, hue = lch(np.median(box_pixels(f"{O}/{d}/{k}__{v}.jpg", box)[mask], axis=0))
            c0 = C if c0 is None else c0
            flags = "" if v == "original" else (" GREY" if C < 0.6 * c0 else "") + (" HUE" if not 60 <= hue <= 160 else "")
            cells.append(f"{L:.2f} / {C:.3f} / {hue:.0f}{flags}")
        print(f"| {k} {name} | {mask.mean() * 100:.0f}% | " + " | ".join(cells) + " |")
    print("| water box | | original | ours | ours (video path) |")
    for d, k, name, box in PLANT_WATER:
        print(f"| {k} {name} | | " + " | ".join("{:.2f} / {:.3f} / {:.0f}".format(*lch(box_median(f"{O}/{d}/{k}__{v}.jpg", box)))
                                            for v in ["original", "combined", "uniform"]) + " |")
# Grain on flat bright sand (Stage C): std of luma minus its 4 px Gaussian blur, in a box, at 1920 px (lossless PNG).
# Ratio = output over original. Sea-thru's m5 output is the reference point for a good result.
GRAIN = [("r14", "teal sand", (0.55, 0.70, 0.80, 0.95)), ("r03", "white sand", (0.72, 0.80, 0.86, 0.90)),
         ("m5", "sand", (0.70, 0.88, 0.85, 0.98)), ("pl1", "sand beside sargassum", (0.00, 0.55, 0.15, 0.70))]
def grain(im, box):
    w, h = im.size; x0, y0, x1, y1 = box
    c = im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))
    hp = np.asarray(c, dtype=np.float64) - np.asarray(c.filter(ImageFilter.GaussianBlur(4)), dtype=np.float64)
    return float((0.2126 * hp[..., 0] + 0.7152 * hp[..., 1] + 0.0722 * hp[..., 2]).std())
if all(os.path.exists(f"{O}/grain/{k}__original.png") for k, _, _ in GRAIN):
    print("\n== GRAIN on flat bright sand (1920 px; std of luma minus a 4 px blur; ratio over original; compare with the baseline in docs/RestorationExperiments.md)")
    print("| sand | original | ours | ours (video path) | Sea-thru |")
    seathru = os.path.join(os.path.dirname(O.rstrip("/")), "cache/market/ref/m5.png")
    for k, name, box in GRAIN:
        src = Image.open(f"{O}/grain/{k}__original.png").convert("RGB"); g0 = grain(src, box)
        cells = [f"{g0:.2f}"] + [f"{g:.2f} ({g / g0:.2f}x)" for g in (grain(Image.open(f"{O}/grain/{k}__{v}.png").convert("RGB"), box) for v in ("combined", "uniform"))]
        if k == "m5" and os.path.exists(seathru):
            g = grain(Image.open(seathru).convert("RGB").resize(src.size, Image.LANCZOS), box); cells.append(f"{g:.2f} ({g / g0:.2f}x)")
        else:
            cells.append("")
        print(f"| {k} {name} | " + " | ".join(cells) + " |")
mx, mean = lab_chroma(f"{O}/market/n_grey__combined.jpg"); ux, umean = lab_chroma(f"{O}/market/n_grey__uniform.jpg")
print(f"\n== NEUTRAL grey ramp: max Lab chroma ours {mx:.2f} (mean {mean:.2f}), video path {ux:.2f} (mean {umean:.2f}). Must stay below about 3.")
sheet(f"{O}/market", ["m1.png", "m2.png", "m3.png", "m4.png", "m5.png", "m6.png", "n_grey.png"], cols, f"{O}/market_sheet.jpg")
print(f"\nSheets: {O}/market_sheet.jpg, {O}/real_sheet.jpg")
