# sheet.py <prefix> <stem> <x0,y0,x1,y1> <scale> <out>: rows = way A, way B; columns = k 0, 0.5, 1, 1.5, 2.
import sys, glob
from PIL import Image, ImageDraw
pre, stem, box, scale, out = sys.argv[1], sys.argv[2], [float(v) for v in sys.argv[3].split(',')], float(sys.argv[4]), sys.argv[5]
S = sys.path[0]
def crop(path):
    im = Image.open(path).convert('RGB'); W, H = im.size
    c = im.crop((int(box[0]*W), int(box[1]*H), int(box[2]*W), int(box[3]*H)))
    return c.resize((int(c.width*scale), int(c.height*scale)), Image.LANCZOS)
ks = ['0', '0.5', '1', '1.5', '2']
tiles = {}
for way in 'ABC':
    for k in ks:
        d = f"{S}/out/{pre}_{way}_{'0.5' if k == '0' else k}"
        tiles[(way, k)] = crop(glob.glob(f"{d}/{stem}__{'combined' if k == '0' else 'lift'}.png")[0])
tw, th = tiles[('A', '0')].size; pad = 28
sheet = Image.new('RGB', (tw*5, (th+pad)*3), 'white'); dr = ImageDraw.Draw(sheet)
for r, way in enumerate('ABC'):
    for c, k in enumerate(ks):
        sheet.paste(tiles[(way, k)], (c*tw, r*(th+pad)+pad))
        dr.text((c*tw+6, r*(th+pad)+6), f"{dict(A='A strength only', B='B whole recipe', C='C bright + low pivot')[way]}  x{k}", fill='black')
sheet.save(out, quality=92)
print(out, sheet.size)
