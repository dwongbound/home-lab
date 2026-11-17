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
    """The see-through glass core: faint blue fill, soft rim, a highlight."""
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c, r = SIZE / 2, SIZE * 0.2
    for i in range(40):
        f = i / 40
        rr = r * (1 - f)
        d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=(142, 197, 234, int(30 + 70 * f)))
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 110), width=4)
    d.ellipse([c - r * 0.55, c - r * 0.78, c + r * 0.25, c - r * 0.33], fill=(255, 255, 255, 80))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2)))


def main():
    img = sky().convert('RGBA')
    points = sphere(70, 0.6)
    dots(img, points, front=False)
    core(img)
    dots(img, points, front=True)
    img.convert('RGB').save(OUT)


if __name__ == '__main__':
    main()
