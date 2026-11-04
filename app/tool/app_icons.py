"""Makes every icon of the program from its symbol, which it draws itself
(symbol()): four rings at the left, top, bottom, and right, joined along a
path (left-top, the upright bar top-bottom, bottom-right). From it: the
symbol alone (white, transparent), the tile (the white symbol on a black
rounded square), and the tray icons:

- Android (android/app/src/main/res): an adaptive icon for Android 8+, a
  black background layer and the symbol as the foreground layer, 108 dp
  each, which the launcher crops to its own shape; and ic_launcher.png for
  older Android, the same tile, rounded. The status bar icon
  (res/drawable/ic_stat_logo.xml) is the symbol in white, by hand. The
  Android TV banner (res/drawable-xhdpi/banner.png, 320 x 180 px): the
  symbol and the name in white on the night theme's navy.
- macOS (macos/Runner/Assets.xcassets/AppIcon.appiconset): the black tile
  in Apple's grid, a rounded square of 824 in 1024 with room for its
  shadow, the symbol in its middle, in the sizes the icon set lists.
- Windows (windows/runner/resources/app_icon.ico): the tile, in every size
  Explorer and the taskbar use; the small sizes sharpened, since the
  taskbar shows 24 or 32 px.
- The core (core/internal/desktop): appicon.ico, the same for its
  executable (tools/winres).
- The web dashboard (core/internal/service/web/icon.png): the tile, for
  the page icon and the logo.
- The app's logo (assets/logo.png): the tile, beside its name.
- The tray icons: the symbol on a dark tile, plain while off; while
  connecting, one ring after the other along the path is filled (four
  frames); otherwise a dot of the state's color sits on the last bar,
  between the third ring and the fourth. The app's tray (assets/tray: .ico for Windows, .png for
  Linux): off, busy1 to busy4, on and idle (green), error (red). The core's
  tray (core/internal/desktop/tray: .ico for Windows, .png elsewhere): one
  icon per state, green while the proxy runs, blue while Windows' system
  proxy points at it, faded while asleep, red on an error; the first frame
  while waiting.

The fox shield of the documentation is docs/images/logo.png, kept as is.

Run from app/ after changing the symbol or the colors (needs Pillow):

    python tool/app_icons.py
"""
import os

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, '..')
CORE = os.path.join(APP, '..', 'core')
RES = os.path.join(APP, 'android', 'app', 'src', 'main', 'res')

# The symbol's height as a share of the 108 dp canvas. Launchers show about
# the middle 72 dp (67%), so 0.46 makes it about 70% of the tile.
ART = 0.46
BLACK = (0, 0, 0, 255)
DENSITY = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
WINDOWS_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]

ADAPTIVE = '''<?xml version="1.0" encoding="utf-8"?>
<!-- The launcher icon on Android 8+: the symbol over black;
     the launcher crops both layers to its own shape. Made by
     tool/app_icons.py. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'''


# The symbol in a 24 grid: four rings (radius 2.8, 1.6 thick) at the left,
# top, bottom, and right, joined left-top, top-bottom, bottom-right. The
# tray shows the state as a dot of DOT radius on the last bar (bottom-right),
# with a gap of DOT_GAP around it.
NODES = [(7, 12), (12, 7), (12, 17), (17, 12)]
EDGES = [(0, 1), (1, 2), (2, 3)]
RING, STROKE = 2.8, 1.6
DOT, DOT_GAP = 4.0, 0.3
WHITE = (255, 255, 255, 255)


def symbol(size, filled=None):
    """The symbol, white on transparent, on a size px square for the 24
    grid; filled maps ring indexes to a fill color. Drawn at 4x."""
    filled = filled or {}
    k = 4
    s = size * k / 24
    img = Image.new('RGBA', (size * k, size * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, j in EDGES:
        d.line([(NODES[i][0] * s, NODES[i][1] * s), (NODES[j][0] * s, NODES[j][1] * s)],
               fill=WHITE, width=round(STROKE * s))
    hole = Image.new('L', img.size, 0)
    holes = ImageDraw.Draw(hole)
    r, w = RING * s, STROKE * s
    for x, y in NODES:
        x, y = x * s, y * s
        d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)
        holes.ellipse([x - r + w, y - r + w, x + r - w, y + r - w], fill=255)
    img.paste((0, 0, 0, 0), (0, 0), hole)
    for n, color in filled.items():
        x, y = NODES[n][0] * s, NODES[n][1] * s
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    return img.resize((size, size), Image.LANCZOS)


def tile_art():
    """The tile (512 px): a black rounded square of 412 px, the symbol 300
    px wide in its middle."""
    size, body = 512, 412
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    off = (size - body) // 2
    ImageDraw.Draw(out).rounded_rectangle([off, off, off + body - 1, off + body - 1], radius=round(body * 0.2), fill=BLACK)
    span = (NODES[3][0] + RING) - (NODES[0][0] - RING)
    art = symbol(round(300 * 24 / span))
    out.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return out


def art_layer(art, size, share):
    """The art's visible part, its larger side share of size, centered."""
    art = art.crop(art.getchannel('A').getbbox())
    scale = size * share / max(art.size)
    w, h = max(1, round(art.width * scale)), max(1, round(art.height * scale))
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    layer.alpha_composite(art.resize((w, h), Image.LANCZOS), ((size - w) // 2, (size - h) // 2))
    return layer


def tile(glyph, size):
    """The visible middle of the adaptive icon, rounded."""
    canvas = round(size * 108 / 72)
    full = Image.new('RGBA', (canvas, canvas), BLACK)
    full.alpha_composite(art_layer(glyph, canvas, ART))
    cut = (canvas - size) // 2
    square = full.crop((cut, cut, cut + size, cut + size))
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=size // 5, fill=255)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(square, (0, 0), mask)
    return out


def android(glyph):
    for dpi, k in DENSITY.items():
        folder = os.path.join(RES, 'mipmap-' + dpi)
        os.makedirs(folder, exist_ok=True)
        px = round(108 * k)
        art_layer(glyph, px, ART).save(os.path.join(folder, 'ic_launcher_foreground.png'), optimize=True)
        Image.new('RGBA', (px, px), BLACK).save(os.path.join(folder, 'ic_launcher_background.png'), optimize=True)
        tile(glyph, round(48 * k)).save(os.path.join(folder, 'ic_launcher.png'), optimize=True)
    folder = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, 'ic_launcher.xml'), 'w', newline='\n') as f:
        f.write(ADAPTIVE)


def tv_banner(glyph):
    """Android TV's banner, which its home screen shows in the apps row:
    the symbol and the name, 320 x 180 px (160 x 90 dp at xhdpi), on the
    app's dark navy (its night theme), which stands out from the TV's black
    home screen as the other apps' tiles do."""
    from PIL import ImageFont
    w, h = 320, 180
    top, bottom = (0x26, 0x30, 0x6B), (0x14, 0x1B, 0x3D)
    out = Image.new('RGBA', (w, h))
    for y in range(h):
        t = y / (h - 1)
        out.paste(tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,), (0, y, w, y + 1))
    symbol = art_layer(glyph, 96, 1.0)
    font = ImageFont.truetype(os.path.join(APP, 'assets', 'fonts', 'Vazirmatn-Bold.ttf'), 34)
    name = 'Arman VPN'
    draw = ImageDraw.Draw(out)
    left, top, right, bottom = draw.textbbox((0, 0), name, font=font)
    gap = 14
    x = (w - (symbol.width + gap + right - left)) // 2
    out.alpha_composite(symbol, (x, (h - symbol.height) // 2))
    draw.text((x + symbol.width + gap - left, (h - (bottom - top)) // 2 - top), name, font=font, fill=(255, 255, 255, 255))
    folder = os.path.join(RES, 'drawable-xhdpi')
    os.makedirs(folder, exist_ok=True)
    out.save(os.path.join(folder, 'banner.png'), optimize=True)


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


MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def macos_icon(glyph):
    """The 1024 px macOS icon: the black tile, 824 px with rounded corners,
    over a soft shadow, the symbol in its middle."""
    size, body = 1024, 824
    off = (size - body) // 2
    mask = Image.new('L', (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, body - 1, body - 1], radius=round(body * 0.225), fill=255)
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (off, off + 12), mask)
    out = shadow.filter(ImageFilter.GaussianBlur(14))
    face = Image.new('RGBA', (body, body), BLACK)
    face.alpha_composite(art_layer(glyph, body, ART * 108 / 72 * 0.9))
    out.paste(face, (off, off), mask)
    return out


def macos(glyph):
    folder = os.path.join(APP, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    big = macos_icon(glyph)
    for n in MACOS_SIZES:
        big.resize((n, n), Image.LANCZOS).save(os.path.join(folder, 'app_icon_%d.png' % n), optimize=True)


def app_logo(tile_art):
    art_layer(tile_art, 256, 1.0).save(os.path.join(APP, 'assets', 'logo.png'), optimize=True)


def windows(tile_art):
    write_ico(os.path.join(APP, 'windows', 'runner', 'resources', 'app_icon.ico'), tile_art)


def core(tile_art):
    desktop = os.path.join(CORE, 'internal', 'desktop')
    write_ico(os.path.join(desktop, 'appicon.ico'), tile_art)
    art_layer(tile_art, 192, 1.0).save(os.path.join(CORE, 'internal', 'service', 'web', 'icon.png'), optimize=True)


# The tray's state colors: green while connected, red on an error, and the
# core's own: blue while Windows' system proxy points at the proxy, faded
# while asleep.
DOT_GOOD, DOT_BAD = (63, 225, 176), (226, 40, 80)
DOT_SET = (96, 165, 250)
TRAY_SIZES = [16, 20, 24, 32, 48, 64]


def asleep(color):
    return tuple(round(c * 0.45 + g * 0.55) for c, g in zip(color, (150, 160, 158)))


TRAY_TILE = (39, 39, 41, 255)


def tray_icon(filled=None, dot=None):
    """A tray icon (80 px): the symbol on a dark rounded tile, its rings
    filled as filled maps them (index: RGB), and a dot of color dot (RGB) on
    the last bar."""
    n = 320
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=round(n * 0.22), fill=TRAY_TILE)
    art = symbol(round(n * 1.12), {k: v + (255,) for k, v in (filled or {}).items()})
    off = (n - art.width) // 2
    img.alpha_composite(art, (off, off))
    if dot:
        s = art.width / 24
        (x1, y1), (x2, y2) = NODES[EDGES[-1][0]], NODES[EDGES[-1][1]]
        x, y = off + (x1 + x2) / 2 * s, off + (y1 + y2) / 2 * s
        r = (DOT + DOT_GAP) * s
        d.ellipse([x - r, y - r, x + r, y + r], fill=TRAY_TILE)
        r = DOT * s
        d.ellipse([x - r, y - r, x + r, y + r], fill=dot + (255,))
    return img.resize((80, 80), Image.LANCZOS)


def save_ico(path, big):
    images = [big.resize((n, n), Image.LANCZOS) for n in TRAY_SIZES]
    images[-1].save(path, format='ICO', sizes=[(n, n) for n in TRAY_SIZES], append_images=images[:-1])


def tray():
    # The app's tray.
    app = os.path.join(APP, 'assets', 'tray')
    for old in os.listdir(app):
        os.remove(os.path.join(app, old))
    icons = {
        'off': tray_icon(),
        'on': tray_icon(dot=DOT_GOOD),
        'idle': tray_icon(dot=DOT_GOOD),
        'error': tray_icon(dot=DOT_BAD),
    }
    # Connecting: each ring in turn, along the path.
    for frame in range(1, 5):
        icons['busy%d' % frame] = tray_icon({frame - 1: (255, 255, 255)})
    for name, big in icons.items():
        save_ico(os.path.join(app, name + '.ico'), big)
        # Linux (AppIndicator) takes a .png; 64 px stays sharp when scaled.
        big.resize((64, 64), Image.LANCZOS).save(os.path.join(app, name + '.png'), optimize=True)
    # The core's tray: an .ico for Windows, a 32 px .png elsewhere.
    folder = os.path.join(CORE, 'internal', 'desktop', 'tray')
    os.makedirs(folder, exist_ok=True)
    states = {
        'running': tray_icon(dot=DOT_GOOD),
        'set': tray_icon(dot=DOT_SET),
        'running-asleep': tray_icon(dot=asleep(DOT_GOOD)),
        'set-asleep': tray_icon(dot=asleep(DOT_SET)),
        'waiting': tray_icon({0: (255, 255, 255)}),
        'error': tray_icon(dot=DOT_BAD),
        'off': tray_icon(),
    }
    for name, big in states.items():
        save_ico(os.path.join(folder, name + '.ico'), big)
        big.resize((32, 32), Image.LANCZOS).save(os.path.join(folder, name + '.png'), optimize=True)


def main():
    square = tile_art()
    glyph = symbol(1024)
    android(glyph)
    tv_banner(glyph)
    macos(glyph)
    windows(square)
    core(square)
    app_logo(square)
    tray()


if __name__ == '__main__':
    main()
