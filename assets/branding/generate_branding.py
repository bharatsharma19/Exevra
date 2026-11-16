#!/usr/bin/env python3
"""Regenerates the Exevra brand images used by the native packaging tools.

Usage (from the repository root, needs Pillow):

    python3 assets/branding/generate_branding.py

Input:   assets/icons/app_icon.png (1024 x 1024 source artwork: the "E" mark
         on a dark rounded tile, shown as a mock-up on a grid backdrop; it
         is only a source and is never used as an icon directly).
Outputs: assets/branding/
  icon_foreground.png          colour "E" mark on transparency, for the
                               Android adaptive icon foreground layer
  icon_monochrome.png          white "E" mark on transparency, for the
                               Android 13+ themed (monochrome) icon layer
  icon_full_bleed.png          colour "E" mark on a flat, opaque square in the
                               app's dark background colour, for the legacy
                               Android icon and the iOS app icon
  splash_logo.png              colour "E" mark for the native splash
  splash_logo_android12.png    colour "E" mark sized for the Android 12+
                               splash icon (1152 px canvas, mark inside the
                               768 px safe circle)

The "E" mark is cut out of the dark rounded tile of the source artwork by
brightness, so these files must be regenerated whenever app_icon.png changes.
Afterwards run:

    dart run flutter_launcher_icons
    dart run flutter_native_splash:create
"""

from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "icons" / "app_icon.png"
OUT = ROOT / "assets" / "branding"

# Brightness ramp (HSV value) that separates the glowing mark from the tile.
ALPHA_LOW, ALPHA_HIGH = 110, 190
# Interior of the rounded tile in app_icon.png; excludes the glass border.
TILE_INTERIOR = (230, 230, 794, 794)
# Approximate colour of the tile behind the mark, used to undo the blend.
TILE_COLOUR = (9, 13, 24)
# Icon background: AppColors.darkBackground, also the adaptive icon
# background (adaptive_icon_background in pubspec.yaml).
ICON_BACKGROUND = (0x07, 0x0B, 0x14)
# Height of the mark on the 1024 px adaptive layers. flutter_launcher_icons
# insets these layers by 16%, so the mark is about 40 dp tall and stays well
# inside the 66 dp adaptive-icon safe zone.
ADAPTIVE_MARK_HEIGHT = 560
# Height of the mark on the 1024 px full-bleed icon.
FULL_BLEED_MARK_HEIGHT = 600


def _ramp(value: int) -> int:
    if value <= ALPHA_LOW:
        return 0
    if value >= ALPHA_HIGH:
        return 255
    return round((value - ALPHA_LOW) * 255 / (ALPHA_HIGH - ALPHA_LOW))


def extract_mark() -> tuple[Image.Image, Image.Image]:
    """Returns (colour mark RGBA, alpha mask), both cropped to the mark."""
    rgb = Image.open(SOURCE).convert("RGB")
    alpha = rgb.convert("HSV").getchannel("V").point(_ramp)
    interior = Image.new("L", rgb.size, 0)
    interior.paste(255, TILE_INTERIOR)
    alpha = ImageChops.multiply(alpha, interior)

    # Remove the dark tile colour from semi-transparent pixels so the mark
    # keeps its colour on a light background.
    colour = Image.new("RGBA", rgb.size)
    src, mask, dst = rgb.load(), alpha.load(), colour.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            a = mask[x, y]
            if a == 0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            f = a / 255
            r, g, b = (
                max(0, min(255, round((c - (1 - f) * t) / f)))
                for c, t in zip(src[x, y], TILE_COLOUR)
            )
            dst[x, y] = (r, g, b, a)

    box = alpha.getbbox()
    return colour.crop(box), alpha.crop(box)


def place(mark: Image.Image, canvas: int, height: int) -> Image.Image:
    width = round(mark.width * height / mark.height)
    scaled = mark.resize((width, height), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(scaled, ((canvas - width) // 2, (canvas - height) // 2))
    return out


def main() -> None:
    colour, alpha = extract_mark()
    white = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    white.putalpha(alpha)

    # Adaptive layers: identical geometry, so the themed icon matches.
    place(colour, 1024, ADAPTIVE_MARK_HEIGHT).save(
        OUT / "icon_foreground.png", optimize=True
    )
    place(white, 1024, ADAPTIVE_MARK_HEIGHT).save(
        OUT / "icon_monochrome.png", optimize=True
    )
    # Legacy Android and iOS: flat and opaque (iOS rejects transparency and
    # applies its own corner mask), no frame, bevel or backdrop.
    full = Image.new("RGBA", (1024, 1024), ICON_BACKGROUND + (255,))
    full.alpha_composite(place(colour, 1024, FULL_BLEED_MARK_HEIGHT))
    full.convert("RGB").save(OUT / "icon_full_bleed.png", optimize=True)
    # Pre-Android 12 and iOS splash (treated as a 4x image: about 192 dp).
    place(colour, 768, 400).save(OUT / "splash_logo.png", optimize=True)
    # Android 12+: 1152 px canvas, mark inside the 768 px circle.
    place(colour, 1152, 520).save(OUT / "splash_logo_android12.png", optimize=True)


if __name__ == "__main__":
    main()
