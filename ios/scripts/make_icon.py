"""Draws the app icon: orb design D (a glass core inside a tilted sphere of
points) on the night sky, 1024 px, no transparency (App Store Connect
refuses an icon with alpha). Run: python3 scripts/make_icon.py"""
import math
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = 'App/Assets.xcassets/AppIcon.appiconset/icon-1024.png'


def sky():
    """The page's night gradient, top to bottom."""
    img = Image.new('RGB', (SIZE, SIZE))
    top, bottom = (0x0f, 0x17, 0x26), (0x1d, 0x2a, 0x40)
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        f = y / SIZE
        draw.line([(0, y), (SIZE, y)], fill=tuple(int(a + (b - a) * f) for a, b in zip(top, bottom)))
    return img


def sphere(count, turn, tilt=0.45):
    """Points on a unit sphere (golden-angle spiral), turned and tilted; same maths as OrbView.sphere."""
    out = []
    for i in range(count):
        y0 = 1 - (i / (count - 1)) * 2
        ring = math.sqrt(max(0.0, 1 - y0 * y0))
        a = i * 2.39996 + turn
        x, z0 = math.cos(a) * ring, math.sin(a) * ring
        out.append((x, y0 * math.cos(tilt) - z0 * math.sin(tilt), y0 * math.sin(tilt) + z0 * math.cos(tilt)))
    return out


def lines(img, points, front):
    """Faint lines between neighbouring points (same rule as orbLinks in src/lib/orb.ts)."""
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c, r = SIZE / 2, SIZE * 0.36
    count = [0] * len(points)
    for i, a in enumerate(points):
        near = sorted((math.dist(a, b), j) for j, b in enumerate(points) if j > i and math.dist(a, b) < 0.56)
        for _, j in near:
            if count[i] >= 3:
                break
            if count[j] >= 3:
                continue
            count[i] += 1
            count[j] += 1
            b = points[j]
            z = (a[2] + b[2]) / 2
            if (z >= 0) != front:
                continue
            alpha = int(255 * (0.08 + (z + 1) / 2 * 0.22))
            d.line([(c + a[0] * r, c + a[1] * r), (c + b[0] * r, c + b[1] * r)], fill=(185, 220, 243, alpha), width=3)
    img.alpha_composite(layer)


def dots(img, points, front):
    """Glowing points, either the half behind the core or the half in front."""
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    sharp = Image.new('RGBA', img.size, (0, 0, 0, 0))
    g, s = ImageDraw.Draw(glow), ImageDraw.Draw(sharp)
    c, r = SIZE / 2, SIZE * 0.36
    for x, y, z in points:
        if (z >= 0) != front:
            continue
        near = (z + 1) / 2
        d = 8 + near * 20
        alpha = int(255 * (0.25 + near * 0.75))
        px, py = c + x * r, c + y * r
        g.ellipse([px - d * 1.6, py - d * 1.6, px + d * 1.6, py + d * 1.6], fill=(142, 197, 234, alpha // 2))
        s.ellipse([px - d / 2, py - d / 2, px + d / 2, py + d / 2], fill=(242, 239, 233, alpha))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10)))
    img.alpha_composite(sharp)


def core(img):
    """The glass core, nearly solid (Dylan, 2026-11-17, twice: "too transparent"):
    a lit blue body brighter toward the upper left, a soft rim, a highlight.
    Only a hint of the constellation's back points shows through it."""
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    c, r = SIZE / 2, SIZE * 0.2
    light = (c - r * 0.35, c - r * 0.4)
    px = layer.load()
    for y in range(int(c - r) - 1, int(c + r) + 2):
        for x in range(int(c - r) - 1, int(c + r) + 2):
            d = math.hypot(x - c, y - c)
            if d > r:
                continue
            # 0 at the lit spot, 1 at the far edge.
            f = min(1.0, math.hypot(x - light[0], y - light[1]) / (r * 1.6))
            col = tuple(int(a + (b - a) * f) for a, b in zip((214, 236, 250), (63, 120, 163)))
            edge = d / r
            alpha = int(248 - 18 * (1 - edge))
            px[x, y] = col + (alpha,)
    # Rim and highlight on their own layer: drawing straight onto the body
    # would replace its pixels (and their opacity) instead of lighting them.
    shine = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(shine)
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 150), width=5)
    d.ellipse([c - r * 0.55, c - r * 0.78, c + r * 0.2, c - r * 0.36], fill=(255, 255, 255, 120))
    layer.alpha_composite(shine.filter(ImageFilter.GaussianBlur(3)))
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([c - r * 1.35, c - r * 1.35, c + r * 1.35, c + r * 1.35], fill=(142, 197, 234, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2)))


def main():
    img = sky().convert('RGBA')
    points = sphere(70, 0.6)
    lines(img, points, front=False)
    dots(img, points, front=False)
    core(img)
    lines(img, points, front=True)
    dots(img, points, front=True)
    img.convert('RGB').save(OUT)


if __name__ == '__main__':
    main()
