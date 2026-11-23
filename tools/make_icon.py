import os, sys
from PIL import Image, ImageDraw

res = sys.argv[1]
K, OX, OY = 3.6, 76, 94
outer = [(50, 84), (8, 72), (6, 46), (50, 60)]
inner = [(50, 72), (16, 62), (14, 50), (50, 62)]
gem = [(50, 8), (62, 24), (50, 40), (38, 24)]

def P(pts, mirror=False):
    return [(OX + ((100 - x) if mirror else x) * K, OY + y * K) for x, y in pts]

img = Image.new('RGB', (512, 512), '#FFF9F4')
d = ImageDraw.Draw(img)
for m in (False, True):
    d.polygon(P(outer, m), fill='#79B5D8')
    d.polygon(P(inner, m), fill='#B7D9EE')
d.polygon(P(gem), fill='#D995A8')

for folder, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    out = os.path.join(res, f'mipmap-{folder}')
    os.makedirs(out, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(os.path.join(out, 'ic_launcher.png'))
print('icons written')
