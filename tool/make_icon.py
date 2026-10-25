"""Generates the ToneX Tweaker launcher icon (adaptive vector + legacy PNGs).

Usage: python tool/make_icon.py android/app/src/main/res <preview_dir>   (needs Pillow)

Geometry is in the 108x108 adaptive-icon space, centre (54, 54).
"""
import math, os, sys
from PIL import Image, ImageDraw

RES = sys.argv[1]
PREVIEW = sys.argv[2]

C = 54.0
ARC_R, ARC_W = 26.0, 5.5
START, END, VALUE = 135.0, 405.0, 335.0
KNOB_R, CAP_R = 16.0, 13.0
PTR_IN, PTR_OUT, PTR_W = 4.5, 11.5, 3.4

BG_A, BG_B = '#2F2F35', '#0C0C0E'
ARC_A, ARC_B = '#FFC23A', '#FF5A00'
TRACK = '#26FFFFFF'          # ARGB
KNOB_A, KNOB_B = '#4A4A51', '#1C1C20'
CAP_A, CAP_B = '#24242A', '#3A3A41'
PTR = '#FF8A1A'


def pt(r, deg):
    a = math.radians(deg)
    return C + r * math.cos(a), C + r * math.sin(a)


def f(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def arc_path(r, a0, a1):
    x0, y0 = pt(r, a0)
    x1, y1 = pt(r, a1)
    large = 1 if (a1 - a0) > 180 else 0
    return f'M{f(x0)},{f(y0)} A{f(r)},{f(r)} 0 {large},1 {f(x1)},{f(y1)}'


def circle_path(r):
    return f'M{f(C - r)},{f(C)} a{f(r)},{f(r)} 0 1,0 {f(2 * r)},0 a{f(r)},{f(r)} 0 1,0 {f(-2 * r)},0'


def lin(x0, y0, x1, y1, a, b):
    return f'''
        <aapt:attr name="android:{{attr}}">
            <gradient android:type="linear" android:startX="{f(x0)}" android:startY="{f(y0)}"
                android:endX="{f(x1)}" android:endY="{f(y1)}"
                android:startColor="{a}" android:endColor="{b}" />
        </aapt:attr>'''


px0, py0 = pt(PTR_IN, VALUE)
px1, py1 = pt(PTR_OUT, VALUE)
ptr_path = f'M{f(px0)},{f(py0)} L{f(px1)},{f(py1)}'

HEAD = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
'''

background = HEAD + f'''    <path android:pathData="M0,0h108v108h-108z">{lin(0, 0, 108, 108, BG_A, BG_B).replace('{attr}', 'fillColor')}
    </path>
</vector>
'''

foreground = HEAD + f'''    <!-- value track -->
    <path android:pathData="{arc_path(ARC_R, START, END)}"
        android:strokeColor="{TRACK}" android:strokeWidth="{ARC_W}" android:strokeLineCap="round" />
    <path android:pathData="{arc_path(ARC_R, START, VALUE)}"
        android:strokeWidth="{ARC_W}" android:strokeLineCap="round">{lin(28, 80, 82, 36, ARC_A, ARC_B).replace('{attr}', 'strokeColor')}
    </path>
    <!-- knob -->
    <path android:pathData="{circle_path(KNOB_R)}">{lin(C, C - KNOB_R, C, C + KNOB_R, KNOB_A, KNOB_B).replace('{attr}', 'fillColor')}
    </path>
    <path android:pathData="{circle_path(CAP_R)}">{lin(C, C - CAP_R, C, C + CAP_R, CAP_A, CAP_B).replace('{attr}', 'fillColor')}
    </path>
    <path android:pathData="{ptr_path}"
        android:strokeColor="{PTR}" android:strokeWidth="{PTR_W}" android:strokeLineCap="round" />
</vector>
'''

monochrome = HEAD + f'''    <path android:pathData="{arc_path(ARC_R, START, END)}"
        android:strokeColor="#66FFFFFF" android:strokeWidth="{ARC_W}" android:strokeLineCap="round" />
    <path android:pathData="{arc_path(ARC_R, START, VALUE)}"
        android:strokeColor="#FFFFFFFF" android:strokeWidth="{ARC_W}" android:strokeLineCap="round" />
    <path android:pathData="{circle_path(KNOB_R)} {circle_path(CAP_R)}" android:fillType="evenOdd"
        android:fillColor="#FFFFFFFF" />
    <path android:pathData="{ptr_path}"
        android:strokeColor="#FFFFFFFF" android:strokeWidth="{PTR_W}" android:strokeLineCap="round" />
</vector>
'''

adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''

os.makedirs(f'{RES}/drawable', exist_ok=True)
os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
for name, body in [('ic_launcher_background', background), ('ic_launcher_foreground', foreground),
                   ('ic_launcher_monochrome', monochrome)]:
    open(f'{RES}/drawable/{name}.xml', 'w').write(body)
open(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', 'w').write(adaptive)


# ------------------------------------------------------------ raster (legacy)

def rgba(h):
    h = h.lstrip('#')
    if len(h) == 8:
        return (int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16), int(h[0:2], 16))
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def gradient(size, p0, p1, a, b, s):
    """Linear gradient image; p0/p1 in design units, s = px per unit."""
    ca, cb = rgba(a), rgba(b)
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = dx * dx + dy * dy
    small = 128
    img = Image.new('RGBA', (small, small))
    k = size / small / s
    px = img.load()
    for y in range(small):
        for x in range(small):
            ux, uy = x * k, y * k
            t = max(0.0, min(1.0, ((ux - p0[0]) * dx + (uy - p0[1]) * dy) / L))
            px[x, y] = tuple(round(ca[i] + (cb[i] - ca[i]) * t) for i in range(4))
    return img.resize((size, size), Image.BICUBIC)


def stroke_arc(d, s, r, a0, a1, w, fill):
    # PIL strokes inward from the bbox: grow it so the centreline sits on r.
    o = r + w / 2
    bb = [(C - o) * s, (C - o) * s, (C + o) * s, (C + o) * s]
    d.arc(bb, a0, a1, fill=fill, width=round(w * s))
    for a in (a0, a1):
        x, y = pt(r, a)
        d.ellipse([(x - w / 2) * s, (y - w / 2) * s, (x + w / 2) * s, (y + w / 2) * s], fill=fill)


def render(px, full_bleed):
    """Renders the icon at `px` pixels. Legacy icons crop the central 76 units."""
    crop = 108.0 if full_bleed else 76.0
    ss = 4
    size = px * ss
    s = size / crop
    off = (108 - crop) / 2

    def layer():
        return Image.new('RGBA', (size, size), (0, 0, 0, 0))

    def shifted(fn):
        # draw in design units shifted by the crop offset
        img = layer()
        fn(ImageDraw.Draw(img), s)
        return img

    global C
    C0 = C
    C = C0 - off

    out = layer()
    bg = gradient(size, (0 - off, 0 - off), (108 - off, 108 - off), BG_A, BG_B, s)
    mask = layer()
    md = ImageDraw.Draw(mask)
    if full_bleed:
        md.rectangle([0, 0, size, size], fill=(255, 255, 255, 255))
    else:
        md.rounded_rectangle([0, 0, size - 1, size - 1], radius=size * 0.22, fill=(255, 255, 255, 255))
    out.paste(bg, (0, 0), mask.split()[3])

    out.alpha_composite(shifted(lambda d, s: stroke_arc(d, s, ARC_R, START, END, ARC_W, rgba(TRACK))))
    arc_mask = shifted(lambda d, s: stroke_arc(d, s, ARC_R, START, VALUE, ARC_W, (255, 255, 255, 255)))
    arc = gradient(size, (28 - off, 80 - off), (82 - off, 36 - off), ARC_A, ARC_B, s)
    out.paste(arc, (0, 0), arc_mask.split()[3])

    for r, a, b in [(KNOB_R, KNOB_A, KNOB_B), (CAP_R, CAP_A, CAP_B)]:
        m = shifted(lambda d, s, r=r: d.ellipse([(C - r) * s, (C - r) * s, (C + r) * s, (C + r) * s],
                                                fill=(255, 255, 255, 255)))
        g = gradient(size, (C, C - r), (C, C + r), a, b, s)
        out.paste(g, (0, 0), m.split()[3])

    def pointer(d, s):
        x0, y0 = pt(PTR_IN, VALUE)
        x1, y1 = pt(PTR_OUT, VALUE)
        d.line([x0 * s, y0 * s, x1 * s, y1 * s], fill=rgba(PTR), width=round(PTR_W * s))
        for x, y in ((x0, y0), (x1, y1)):
            h = PTR_W / 2
            d.ellipse([(x - h) * s, (y - h) * s, (x + h) * s, (y + h) * s], fill=rgba(PTR))

    out.alpha_composite(shifted(pointer))
    C = C0
    return out.resize((px, px), Image.LANCZOS)


for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    render(px, False).save(f'{RES}/mipmap-{folder}/ic_launcher.png')

render(512, False).save(f'{PREVIEW}/icon_legacy_512.png')
full = render(512, True)
circle = Image.new('L', (512, 512), 0)
ImageDraw.Draw(circle).ellipse([512 * 18 / 108, 512 * 18 / 108, 512 * 90 / 108, 512 * 90 / 108], fill=255)
preview = Image.new('RGBA', (512, 512), (240, 240, 240, 255))
preview.paste(full, (0, 0), circle)
preview.save(f'{PREVIEW}/icon_adaptive_circle_512.png')
print('ok')
