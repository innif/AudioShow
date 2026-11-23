"""Generates the AudioShow launcher icon (adaptive vector + legacy PNGs).

Run from the repo root:  python tool/make_icon.py
Design (108 x 108 dp adaptive canvas, safe zone = circle r=33 around 54,54):
  dark radial background, green GO button with white play triangle,
  two sound-wave arcs to the right.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

RES = os.path.join('android', 'app', 'src', 'main', 'res')

BG_INNER = '#22302A'
BG_OUTER = '#0C0F0E'
GREEN_TOP = '#45C463'
GREEN_BOTTOM = '#1F7F38'
WAVE = '#9BE3AC'
WHITE = '#FFFFFF'

# geometry (dp on the 108 canvas)
CX, CY, R = 44.0, 54.0, 19.0                      # GO button
TRI = [(38.5, 44.5), (38.5, 63.5), (55.0, 54.0)]  # play triangle
WAVES = [(26.5, 3.8), (34.0, 3.8)]                # (radius, stroke width) around (CX, CY)
WAVE_ANGLE = 33.0                                 # degrees above/below horizontal


def arc_points(r):
    a = math.radians(WAVE_ANGLE)
    return (CX + r * math.cos(a), CY - r * math.sin(a)), (CX + r * math.cos(a), CY + r * math.sin(a))


def f(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)


# ---------- adaptive icon (vector) ----------

def foreground_xml(monochrome=False):
    circle = (f'M{f(CX - R)},{f(CY)} a{f(R)},{f(R)} 0 1,0 {f(2 * R)},0 '
              f'a{f(R)},{f(R)} 0 1,0 {f(-2 * R)},0 Z')
    tri = 'M' + ' L'.join(f'{f(x)},{f(y)}' for x, y in TRI) + ' Z'
    waves = []
    for r, w in WAVES:
        (x1, y1), (x2, y2) = arc_points(r)
        waves.append((f'M{f(x1)},{f(y1)} A{f(r)},{f(r)} 0 0,1 {f(x2)},{f(y2)}', w))

    if monochrome:
        # single colour; the play triangle is cut out of the circle
        body = (f'    <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd"\n'
                f'        android:pathData="{circle} {tri}"/>\n')
        wave_color = '#FFFFFFFF'
    else:
        body = (f'    <path android:pathData="{circle}">\n'
                f'        <aapt:attr name="android:fillColor">\n'
                f'            <gradient android:type="linear" android:startX="{f(CX)}" android:startY="{f(CY - R)}"\n'
                f'                android:endX="{f(CX)}" android:endY="{f(CY + R)}"\n'
                f'                android:startColor="#FF{GREEN_TOP[1:]}" android:endColor="#FF{GREEN_BOTTOM[1:]}"/>\n'
                f'        </aapt:attr>\n'
                f'    </path>\n'
                f'    <path android:fillColor="#FFFFFFFF" android:strokeColor="#FFFFFFFF" android:strokeWidth="2.4"\n'
                f'        android:strokeLineJoin="round" android:pathData="{tri}"/>\n')
        wave_color = f'#FF{WAVE[1:]}'
    for d, w in waves:
        body += (f'    <path android:strokeColor="{wave_color}" android:strokeWidth="{f(w)}"\n'
                 f'        android:strokeLineCap="round" android:pathData="{d}"/>\n')
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    xmlns:aapt="http://schemas.android.com/aapt"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n'
            + body + '</vector>\n')


BACKGROUND_XML = f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:pathData="M0,0 H108 V108 H0 Z">
        <aapt:attr name="android:fillColor">
            <gradient android:type="radial" android:centerX="46" android:centerY="48" android:gradientRadius="78"
                android:startColor="#FF{BG_INNER[1:]}" android:endColor="#FF{BG_OUTER[1:]}"/>
        </aapt:attr>
    </path>
</vector>
'''

ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
'''


# ---------- legacy PNGs (API < 26) and preview ----------

def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size, mask='squircle'):
    """Renders the full icon at `size` px (4x supersampled)."""
    ss = 4
    n = size * ss
    s = n / 108.0  # dp -> px on the 108 canvas
    img = Image.new('RGBA', (n, n))

    # background radial gradient
    inner, outer = hex_rgb(BG_INNER), hex_rgb(BG_OUTER)
    bg = Image.new('RGB', (n, n))
    px = bg.load()
    cx, cy, rad = 46 * s, 48 * s, 78 * s
    for y in range(n):
        for x in range(n):
            t = min(1.0, math.hypot(x - cx, y - cy) / rad)
            px[x, y] = lerp(inner, outer, t)
    img.paste(bg)

    d = ImageDraw.Draw(img)
    # soft shadow under the button
    shadow = Image.new('L', (n, n), 0)
    ImageDraw.Draw(shadow).ellipse([(CX - R) * s, (CY - R + 2.2) * s, (CX + R) * s, (CY + R + 2.2) * s], fill=120)
    shadow = shadow.filter(ImageFilter.GaussianBlur(2.2 * s))
    img.paste((0, 0, 0), mask=shadow)

    # green button with vertical gradient
    top, bot = hex_rgb(GREEN_TOP), hex_rgb(GREEN_BOTTOM)
    grad = Image.new('RGB', (n, n))
    gd = ImageDraw.Draw(grad)
    for y in range(n):
        t = min(1.0, max(0.0, (y / s - (CY - R)) / (2 * R)))
        gd.line([(0, y), (n, y)], fill=lerp(top, bot, t))
    m = Image.new('L', (n, n), 0)
    ImageDraw.Draw(m).ellipse([(CX - R) * s, (CY - R) * s, (CX + R) * s, (CY + R) * s], fill=255)
    img.paste(grad, mask=m)

    # play triangle (rounded via thick outline)
    pts = [(x * s, y * s) for x, y in TRI]
    d.polygon(pts, fill=WHITE)
    d.line(pts + [pts[0]], fill=WHITE, width=round(2.4 * s), joint='curve')
    for x, y in pts:
        r = 1.2 * s
        d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)

    # sound waves
    for r, w in WAVES:
        o = r + w / 2  # PIL strokes inward from the box; centre the stroke on r
        box = [(CX - o) * s, (CY - o) * s, (CX + o) * s, (CY + o) * s]
        d.arc(box, -WAVE_ANGLE, WAVE_ANGLE, fill=WAVE, width=round(w * s))
        for (x, y) in arc_points(r):
            rr = w / 2 * s
            d.ellipse([x * s - rr, y * s - rr, x * s + rr, y * s + rr], fill=WAVE)

    # legacy icons show the central 72dp-ish area: crop to the safe zone + margin
    crop = 18 * s
    img = img.crop((crop, crop, n - crop, n - crop)).resize((n, n), Image.LANCZOS)

    if mask:
        mk = Image.new('L', (n, n), 0)
        if mask == 'circle':
            ImageDraw.Draw(mk).ellipse([0, 0, n - 1, n - 1], fill=255)
        else:
            ImageDraw.Draw(mk).rounded_rectangle([0, 0, n - 1, n - 1], radius=n * 0.22, fill=255)
        out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
        out.paste(img, mask=mk)
        img = out
    return img.resize((size, size), Image.LANCZOS)


def main():
    write(os.path.join(RES, 'drawable', 'ic_launcher_foreground.xml'), foreground_xml())
    write(os.path.join(RES, 'drawable', 'ic_launcher_monochrome.xml'), foreground_xml(monochrome=True))
    write(os.path.join(RES, 'drawable', 'ic_launcher_background.xml'), BACKGROUND_XML)
    write(os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml'), ADAPTIVE_XML)
    for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        render(px).save(os.path.join(RES, f'mipmap-{folder}', 'ic_launcher.png'))
    os.makedirs('tool', exist_ok=True)
    render(512).save(os.path.join('tool', 'icon_preview.png'))
    print('icon written')


if __name__ == '__main__':
    main()
