#!/usr/bin/env python3
"""Render the Recorder Probe icon. Requires Pillow; not used during builds."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


SIZE = 1024
SCALE = 2


def render() -> Image.Image:
    side = SIZE * SCALE
    image = Image.new("RGB", (side, side))
    pixels = image.load()
    for y in range(side):
        for x in range(side):
            shade = (x + y) / (2 * side)
            glow = max(0, 1 - ((x / side - 0.22) ** 2 + (y / side - 0.12) ** 2) ** 0.5 / 0.75)
            pixels[x, y] = (
                int(24 + 42 * shade + 21 * glow),
                int(53 + 67 * shade + 24 * glow),
                int(113 + 75 * shade + 22 * glow),
            )

    decoration = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(decoration)
    center = side // 2
    outer = 344 * SCALE
    draw.ellipse((center - outer, center - outer, center + outer, center + outer),
                 outline=(214, 234, 255, 45), width=17 * SCALE)
    inner = 286 * SCALE
    draw.ellipse((center - inner, center - inner, center + inner, center + inner),
                 outline=(210, 233, 255, 30), width=6 * SCALE)
    image = Image.alpha_composite(image.convert("RGBA"), decoration)

    shadow = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    bars = [(306, 128), (372, 220), (438, 348), (504, 468),
            (570, 300), (636, 408), (702, 210)]
    shadow_draw = ImageDraw.Draw(shadow)
    for x, height in bars:
        left = (x - 21) * SCALE + 8 * SCALE
        top = (512 - height // 2) * SCALE + 13 * SCALE
        right = (x + 21) * SCALE + 8 * SCALE
        bottom = (512 + height // 2) * SCALE + 13 * SCALE
        shadow_draw.rounded_rectangle((left, top, right, bottom), radius=21 * SCALE,
                                      fill=(8, 29, 71, 125))
    image = Image.alpha_composite(image, shadow.filter(ImageFilter.GaussianBlur(20 * SCALE)))

    draw = ImageDraw.Draw(image)
    for x, height in bars:
        left = (x - 21) * SCALE
        top = (512 - height // 2) * SCALE
        right = (x + 21) * SCALE
        bottom = (512 + height // 2) * SCALE
        draw.rounded_rectangle((left, top, right, bottom), radius=21 * SCALE,
                               fill=(250, 253, 255, 255))
    draw.ellipse((741 * SCALE, 232 * SCALE, 801 * SCALE, 292 * SCALE),
                 fill=(255, 194, 132, 255))
    return image.convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    full = root / "RecorderProbe/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    small = root / "scripts/icon.png"
    full.parent.mkdir(parents=True, exist_ok=True)
    icon = render()
    icon.save(full, optimize=True)
    icon.resize((256, 256), Image.Resampling.LANCZOS).save(small, optimize=True)
