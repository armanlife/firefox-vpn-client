"""Makes every icon of the program from tool/app_icon.png (the fox shield,
1024 px, transparent):

- Android (android/app/src/main/res): an adaptive icon for Android 8+, a
  blue gradient background layer and the art as the foreground layer, 108 dp
  each, which the launcher crops to its own shape; and ic_launcher.png for
  older Android, the same tile, rounded.
- Windows (windows/runner/resources/app_icon.ico): the art alone, without a
  tile, as Windows shows icons, in every size Explorer and the taskbar use;
  the small sizes sharpened, since the taskbar shows 24 or 32 px.
- The core (core/internal/desktop): appicon.ico, the same for its
  executable (tools/winres), and appicon.png for its notifications.
- The web dashboard (core/internal/service/web/icon.png): the art alone, for
  the page icon and the logo.
- The tray icons, drawn rather than made from the art, which 16 px cannot
  show: a disk in the state's color with the logo's shield in white. The
  app's tray (assets/tray: .ico for Windows, .png for Linux) and the core's (core/internal/desktop/tray:
  .ico for Windows, .png elsewhere) use the same drawings.

Run from app/ after changing the art or the colors (needs Pillow):

    python tool/app_icons.py
"""
import os

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, '..')
CORE = os.path.join(APP, '..', 'core')
SOURCE = os.path.join(HERE, 'app_icon.png')
RES = os.path.join(APP, 'android', 'app', 'src', 'main', 'res')

# The art's height as a share of the 108 dp canvas. Launchers show about
# the middle 72 dp (67%), so 0.60 makes the shield about 90% of the tile.
ART = 0.60
TOP, BOTTOM = (52, 120, 230), (24, 62, 160)
DENSITY = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
WINDOWS_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]

ADAPTIVE = '''<?xml version="1.0" encoding="utf-8"?>
<!-- The launcher icon on Android 8+: the fox shield over a blue gradient;
     the launcher crops both layers to its own shape. Made by
     tool/app_icons.py. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'''


def gradient(size):
    image = Image.new('RGBA', (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        f = y / max(1, size - 1)
        draw.line([(0, y), (size, y)], fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * f) for i in range(3)) + (255,))
    return image


def art_layer(art, size, share):
    """The art's visible part, its larger side share of size, centered."""
    art = art.crop(art.getchannel('A').getbbox())
    scale = size * share / max(art.size)
    w, h = max(1, round(art.width * scale)), max(1, round(art.height * scale))
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    layer.alpha_composite(art.resize((w, h), Image.LANCZOS), ((size - w) // 2, (size - h) // 2))
    return layer


def tile(art, size):
    """The visible middle of the adaptive icon, rounded."""
    canvas = round(size * 108 / 72)
    full = gradient(canvas)
    full.alpha_composite(art_layer(art, canvas, ART))
    cut = (canvas - size) // 2
    square = full.crop((cut, cut, cut + size, cut + size))
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=size // 5, fill=255)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(square, (0, 0), mask)
    return out


def android(art):
    for dpi, k in DENSITY.items():
        folder = os.path.join(RES, 'mipmap-' + dpi)
        os.makedirs(folder, exist_ok=True)
        px = round(108 * k)
        art_layer(art, px, ART).save(os.path.join(folder, 'ic_launcher_foreground.png'), optimize=True)
        gradient(px).save(os.path.join(folder, 'ic_launcher_background.png'), optimize=True)
        tile(art, round(48 * k)).save(os.path.join(folder, 'ic_launcher.png'), optimize=True)
    folder = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, 'ic_launcher.xml'), 'w', newline='\n') as f:
        f.write(ADAPTIVE)


def crisp(art, size):
    """A small size: shrunk from the full art, then sharpened and given a
    little more contrast and color, which a few pixels otherwise lose."""
    image = art_layer(art, size, 1.0)
    alpha = image.getchannel('A')
    rgb = image.convert('RGB').filter(ImageFilter.UnsharpMask(radius=0.6 if size <= 24 else 0.8, percent=120, threshold=0))
    rgb = ImageEnhance.Color(ImageEnhance.Contrast(rgb).enhance(1.06)).enhance(1.10)
    out = rgb.convert('RGBA')
    out.putalpha(alpha)
    return out


def write_ico(path, art):
    # Each size drawn from the full art; up to 48 px sharpened.
    images = [crisp(art, n) if n <= 48 else art_layer(art, n, 1.0) for n in WINDOWS_SIZES]
    images[-1].save(path, format='ICO', sizes=[(n, n) for n in WINDOWS_SIZES], append_images=images[:-1])


def windows(art):
    write_ico(os.path.join(APP, 'windows', 'runner', 'resources', 'app_icon.ico'), art)


def core(art):
    desktop = os.path.join(CORE, 'internal', 'desktop')
    write_ico(os.path.join(desktop, 'appicon.ico'), art)
    art_layer(art, 256, 1.0).save(os.path.join(desktop, 'appicon.png'), optimize=True)
    art_layer(art, 192, 1.0).save(os.path.join(CORE, 'internal', 'service', 'web', 'icon.png'), optimize=True)


# Tray states and their colors. Sleeping (the proxy runs without a
# connection to Mozilla) is the running color faded toward gray.
TRAY_COLORS = {
    'running': (34, 160, 107),
    'set': (37, 99, 235),         # the core's tray: Windows uses the proxy
    'waiting': (226, 150, 20),
    'error': (220, 64, 56),
    'off': (138, 143, 152),
}
TRAY_SIZES = [16, 20, 24, 32, 48, 64]
BIG = 512


def asleep(color):
    return tuple(round(c * 0.45 + g * 0.55) for c, g in zip(color, (150, 160, 158)))


def shield_points(cx, top, w, h, peak=0.10):
    """The logo's shield: a crest rising to a point in the middle, shoulders
    sloping to the sides, straight sides, and sides curving into a sharp
    point at the bottom."""
    left, right = cx - w / 2, cx + w / 2
    side = top + h * 0.44
    bottom = top + h

    def quad(p0, p1, p2, n=28):
        return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                 (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
                for t in (i / n for i in range(1, n + 1))]

    pts = [(cx, top), (right, top + h * peak), (right, side)]
    pts += quad((right, side), (right, top + h * 0.80), (cx, bottom))
    pts += quad((cx, bottom), (left, top + h * 0.80), (left, side))
    pts += [(left, top + h * peak)]
    return pts


def tray_icon(color):
    """A disk with a soft vertical gradient in color, and the shield in
    white, its left half lightly tinted; drawn at 512 px, shrunk by the
    caller."""
    def mask(fn):
        m = Image.new('L', (BIG, BIG), 0)
        fn(ImageDraw.Draw(m))
        return m

    def mix(c, toward, f):
        return tuple(round(v + (toward - v) * f) for v in c)

    shade = Image.new('RGBA', (BIG, BIG))
    d = ImageDraw.Draw(shade)
    top, bottom = mix(color, 255, 0.18), mix(color, 0, 0.18)
    for y in range(BIG):
        f = y / (BIG - 1)
        d.line([(0, y), (BIG, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * f) for i in range(3)) + (255,))
    img = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))
    img.paste(shade, (0, 0), mask(lambda m: m.ellipse([8, 8, BIG - 8, BIG - 8], fill=255)))
    points = shield_points(BIG / 2, BIG * 0.19, BIG * 0.50, BIG * 0.64)
    img.paste((255, 255, 255, 255), (0, 0), mask(lambda m: m.polygon(points, fill=255)))
    left = mask(lambda m: (m.polygon(points, fill=255), m.rectangle([BIG // 2, 0, BIG, BIG], fill=0)))
    img.paste(mix(color, 255, 0.80) + (255,), (0, 0), left)
    return img


def tray_ico(path, color):
    big = tray_icon(color)
    images = [big.resize((n, n), Image.LANCZOS) for n in TRAY_SIZES]
    images[-1].save(path, format='ICO', sizes=[(n, n) for n in TRAY_SIZES], append_images=images[:-1])


def tray():
    states = {name: color for name, color in TRAY_COLORS.items()}
    states['running-asleep'] = asleep(TRAY_COLORS['running'])
    states['set-asleep'] = asleep(TRAY_COLORS['set'])
    # The app's tray: on, idle (asleep), busy, error, off.
    app = os.path.join(APP, 'assets', 'tray')
    for name, state in [('on', 'running'), ('idle', 'running-asleep'), ('busy', 'waiting'), ('error', 'error'), ('off', 'off')]:
        tray_ico(os.path.join(app, name + '.ico'), states[state])
        # Linux (AppIndicator) takes a .png; 64 px stays sharp when scaled.
        tray_icon(states[state]).resize((64, 64), Image.LANCZOS).save(os.path.join(app, name + '.png'), optimize=True)
    # The core's tray: an .ico for Windows, a 32 px .png elsewhere.
    folder = os.path.join(CORE, 'internal', 'desktop', 'tray')
    os.makedirs(folder, exist_ok=True)
    for name, color in states.items():
        tray_ico(os.path.join(folder, name + '.ico'), color)
        tray_icon(color).resize((32, 32), Image.LANCZOS).save(os.path.join(folder, name + '.png'), optimize=True)


def main():
    art = Image.open(SOURCE).convert('RGBA')
    android(art)
    windows(art)
    core(art)
    tray()


if __name__ == '__main__':
    main()
