"""Draws the Apple TV's home-screen art from the iPhone icon's orb (design D):
the layered app icon (a sky back layer and an orb front layer, so tvOS can
give it parallax) at 400x240 @1x/@2x and the 1280x768 App Store size, and
the Top Shelf banners (1920x720 and 2320x720, @1x/@2x) with the orb and the
word "Jarvis". Run: python3 scripts/make_tv_icon.py (needs Pillow)."""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import make_icon  # noqa: E402  (the orb drawing, shared with the iPhone icon)

CATALOG = 'TV/Assets.xcassets'
BRAND = f'{CATALOG}/App Icon & Top Shelf Image.brandassets'
TOP, BOTTOM = (0x0f, 0x17, 0x26), (0x1d, 0x2a, 0x40)
FONT = '/System/Library/Fonts/SFNSRounded.ttf'


def sky(w, h):
    """The night gradient, top to bottom, opaque."""
    img = Image.new('RGBA', (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        f = y / max(h - 1, 1)
        draw.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * f) for a, b in zip(TOP, BOTTOM)) + (255,))
    return img


def orb(side):
    """The orb alone on a transparent square `side` px wide: back points,
    the nearly solid core, then front points, exactly as on the iPhone icon."""
    make_icon.SIZE = side
    img = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    points = make_icon.sphere(70, 0.6)
    make_icon.lines(img, points, front=False)
    make_icon.dots(img, points, front=False)
    make_icon.core(img)
    make_icon.lines(img, points, front=True)
    make_icon.dots(img, points, front=True)
    return img


def front_layer(w, h, word=False):
    """The orb centred (or left of "Jarvis" for the Top Shelf) on
    transparency, kept inside tvOS's parallax safe area."""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    side = int(h * (0.92 if word else 0.88))
    o = orb(side)
    if not word:
        img.alpha_composite(o, ((w - side) // 2, (h - side) // 2))
        return img
    font = ImageFont.truetype(FONT, int(h * 0.30))
    text = 'Jarvis'
    tw = ImageDraw.Draw(img).textlength(text, font=font)
    # The constellation reaches 0.14..0.86 of the square; the word starts
    # a clear gap after its right edge, and the pair is centred.
    left, right = 0.12, 0.88
    gap = int(h * 0.06)
    total = side * (right - left) + gap + tw
    x0 = int((w - total) / 2 - side * left)
    img.alpha_composite(o, (x0, (h - side) // 2))
    ImageDraw.Draw(img).text((x0 + int(side * right) + gap, h // 2), text, font=font, fill=(242, 239, 233, 255), anchor='lm')
    return img


def write_json(path, data):
    """Writes an asset catalog Contents.json."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')


INFO = {'author': 'xcode', 'version': 1}


def imagestack(name, w, h, scales):
    """A two-layer image stack (Front over Back) at the given scales."""
    stack = f'{BRAND}/{name}.imagestack'
    write_json(f'{stack}/Contents.json', {'info': INFO, 'layers': [{'filename': 'Front.imagestacklayer'}, {'filename': 'Back.imagestacklayer'}]})
    for layer, draw in (('Front', lambda W, H: front_layer(W, H)), ('Back', sky)):
        folder = f'{stack}/{layer}.imagestacklayer'
        write_json(f'{folder}/Contents.json', {'info': INFO})
        images = []
        for s in scales:
            file = f'{layer.lower()}@{s}x.png'
            img = draw(w * s, h * s)
            if layer == 'Back':
                img = img.convert('RGB')
            os.makedirs(f'{folder}/Content.imageset', exist_ok=True)
            img.save(f'{folder}/Content.imageset/{file}')
            images.append({'filename': file, 'idiom': 'tv', 'scale': f'{s}x'})
        write_json(f'{folder}/Content.imageset/Contents.json', {'images': images, 'info': INFO})


def top_shelf(name, w, h):
    """A flat Top Shelf banner: the orb and "Jarvis" on the sky, @1x and @2x."""
    folder = f'{BRAND}/{name}.imageset'
    os.makedirs(folder, exist_ok=True)
    images = []
    for s in (1, 2):
        img = sky(w * s, h * s)
        img.alpha_composite(front_layer(w * s, h * s, word=True))
        file = f'shelf@{s}x.png'
        img.convert('RGB').save(f'{folder}/{file}')
        images.append({'filename': file, 'idiom': 'tv', 'scale': f'{s}x'})
    write_json(f'{folder}/Contents.json', {'images': images, 'info': INFO})


def main():
    write_json(f'{CATALOG}/Contents.json', {'info': INFO})
    imagestack('App Icon', 400, 240, (1, 2))
    imagestack('App Icon - App Store', 1280, 768, (1,))
    top_shelf('Top Shelf Image', 1920, 720)
    top_shelf('Top Shelf Image Wide', 2320, 720)
    write_json(f'{BRAND}/Contents.json', {'assets': [
        {'filename': 'App Icon - App Store.imagestack', 'idiom': 'tv', 'role': 'primary-app-icon', 'size': '1280x768'},
        {'filename': 'App Icon.imagestack', 'idiom': 'tv', 'role': 'primary-app-icon', 'size': '400x240'},
        {'filename': 'Top Shelf Image Wide.imageset', 'idiom': 'tv', 'role': 'top-shelf-image-wide', 'size': '2320x720'},
        {'filename': 'Top Shelf Image.imageset', 'idiom': 'tv', 'role': 'top-shelf-image', 'size': '1920x720'},
    ], 'info': INFO})


if __name__ == '__main__':
    main()
