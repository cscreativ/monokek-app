#!/usr/bin/env python3
"""Builds the Android launcher icons and the in-app logo from the artwork in design/source/.

    python3 tool/generate_assets.py

Inputs  : design/source/icon.jpg  (rounded-square app icon, white glyph on orange, white margin)
          design/source/logo.jpg  (full logo with wordmark on white)
Outputs : android/app/src/main/res/{mipmap-*,drawable-*,mipmap-anydpi-v26}/ic_launcher*
          assets/images/logo.png (transparent), design/play-store-icon-512.png
Requires: Pillow only.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC_ICON = ROOT / "design/source/icon.jpg"
SRC_LOGO = ROOT / "design/source/logo.jpg"
RES = ROOT / "android/app/src/main/res"

MASTER = 1024
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def glyph_and_background():
    """Returns (white glyph as RGBA, orange gradient background RGB), both MASTER x MASTER."""
    src = Image.open(SRC_ICON).convert("RGB")
    r, g, b = src.split()

    # The saturated orange squircle: bounding box → drop the white margin + soft shadow.
    orange = ImageChops.subtract(r, b).point(lambda p: 255 if p > 90 else 0)
    x0, y0, x1, y1 = orange.getbbox()
    side = int(min(x1 - x0, y1 - y0) * 0.80)  # corners of the crop must stay inside the rounded corners
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    box = (cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)
    crop = src.crop(box)

    # White glyph = pixels whose weakest channel is high (orange/red have a very low blue).
    cr, cg, cb = crop.split()
    weakest = ImageChops.darker(ImageChops.darker(cr, cg), cb)
    alpha = weakest.point(lambda p: max(0, min(255, round((p - 120) * 255 / 110))))
    glyph = Image.merge("RGBA", (Image.new("L", crop.size, 255),) * 3 + (alpha,))
    glyph = glyph.resize((MASTER, MASTER), Image.LANCZOS)

    # Background: bilinear blend of the four corner colours (the glyph never touches the corners).
    k = max(6, side // 40)
    def corner(x, y):
        return crop.crop((x, y, x + k, y + k)).resize((1, 1), Image.BOX).getpixel((0, 0))
    grid = Image.new("RGB", (2, 2))
    grid.putpixel((0, 0), corner(0, 0))
    grid.putpixel((1, 0), corner(side - k, 0))
    grid.putpixel((0, 1), corner(0, side - k))
    grid.putpixel((1, 1), corner(side - k, side - k))
    return glyph, grid.resize((MASTER, MASTER), Image.BILINEAR)


def fit_glyph(glyph: Image.Image, fraction: float, canvas: int = MASTER) -> Image.Image:
    """Centres the glyph's visible bounding box on a transparent canvas at `fraction` of its size."""
    bbox = glyph.getchannel("A").point(lambda p: 255 if p > 100 else 0).getbbox()
    g = glyph.crop(bbox)
    scale = fraction * canvas / max(g.size)
    g = g.resize((round(g.width * scale), round(g.height * scale)), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(g, ((canvas - g.width) // 2, (canvas - g.height) // 2), g)
    return out


def rounded(img: Image.Image, radius_frac: float) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=int(img.width * radius_frac), fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def save(img: Image.Image, path: Path, size: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


def make_launcher_icons():
    glyph, bg = glyph_and_background()

    foreground = fit_glyph(glyph, 0.50)          # adaptive: well inside the 66dp-of-108dp safe zone
    black = Image.new("L", foreground.size, 0)    # themed icon (Android 13+): only the alpha matters
    mono = Image.merge("RGBA", (black, black, black, foreground.getchannel("A")))

    legacy = bg.convert("RGBA")                   # API 24-25: no adaptive masking, so shape is baked in
    legacy.alpha_composite(fit_glyph(glyph, 0.66))
    legacy = rounded(legacy, 0.22)

    for name, scale in DENSITIES.items():
        save(legacy, RES / f"mipmap-{name}/ic_launcher.png", round(48 * scale))
        save(foreground, RES / f"drawable-{name}/ic_launcher_foreground.png", round(108 * scale))
        save(mono, RES / f"drawable-{name}/ic_launcher_monochrome.png", round(108 * scale))
        save(bg, RES / f"drawable-{name}/ic_launcher_background.png", round(108 * scale))

    (RES / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (RES / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )

    store = bg.convert("RGBA")
    store.alpha_composite(fit_glyph(glyph, 0.66))
    save(store.convert("RGB"), ROOT / "design/play-store-icon-512.png", 512)


def make_logo():
    """White → transparent ("colour to alpha"), so the logo sits cleanly on any surface."""
    src = Image.open(SRC_LOGO).convert("RGB")
    out_px = []
    for r, g, b in src.getdata():
        m = min(r, g, b)
        a = max(0.0, min(1.0, (255 - m - 8) / (255 - 8)))
        if a < 0.004:
            out_px.append((0, 0, 0, 0))
            continue
        k = (1 - a) * 255
        out_px.append((
            max(0, min(255, round((r - k) / a))),
            max(0, min(255, round((g - k) / a))),
            max(0, min(255, round((b - k) / a))),
            round(a * 255),
        ))
    img = Image.new("RGBA", src.size)
    img.putdata(out_px)
    img = img.crop(img.getchannel("A").point(lambda p: 255 if p > 20 else 0).getbbox())
    pad = round(img.width * 0.03)
    padded = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    padded.paste(img, (pad, pad), img)
    w = 720
    padded = padded.resize((w, round(padded.height * w / padded.width)), Image.LANCZOS)
    out = ROOT / "assets/images/logo.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    padded.save(out, optimize=True)


if __name__ == "__main__":
    make_launcher_icons()
    make_logo()
    print("ok")
