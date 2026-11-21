#!/usr/bin/env python3
"""Draws the app icons and writes them into the platform folders.

  tools/icons/make.py                 write every icon file in the repo
  tools/icons/make.py --preview DIR   only write preview PNGs into DIR

Two icons share one emerald: the tracker app has a gold progress ring around it, the server tray
app has broadcast arcs. The drawing is an SVG built here and rendered with headless Google Chrome
(set $CHROME to another Chromium binary if needed); Pillow does the resizing and the .ico files.
Sizes up to 48 px use a bolder drawing without the fine lines.
"""

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
RENDER = 2048  # px, downscaled afterwards
SMALL = 48  # up to this size the bold drawing is used

DEFS = """
<defs>
  <radialGradient id="bg" cx="50%" cy="38%" r="75%">
    <stop offset="0" stop-color="#27624a"/>
    <stop offset="0.55" stop-color="#143628"/>
    <stop offset="1" stop-color="#0a1c15"/>
  </radialGradient>
  <radialGradient id="glow" cx="50%" cy="50%" r="50%">
    <stop offset="0" stop-color="#4dea93" stop-opacity="0.55"/>
    <stop offset="0.6" stop-color="#3ddc84" stop-opacity="0.12"/>
    <stop offset="1" stop-color="#3ddc84" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="gold" x1="0.15" y1="0" x2="0.85" y2="1">
    <stop offset="0" stop-color="#fff0b0"/>
    <stop offset="0.45" stop-color="#f5c043"/>
    <stop offset="1" stop-color="#c8841c"/>
  </linearGradient>
  <linearGradient id="table" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#a5f2bd"/>
    <stop offset="1" stop-color="#3cbd73"/>
  </linearGradient>
  <linearGradient id="f_ul" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#e2ffe9"/><stop offset="1" stop-color="#93eaae"/>
  </linearGradient>
  <linearGradient id="f_ur" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#8fe8ab"/><stop offset="1" stop-color="#4ccb81"/>
  </linearGradient>
  <linearGradient id="f_r" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#36b06c"/><stop offset="1" stop-color="#218a51"/>
  </linearGradient>
  <linearGradient id="f_lr" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#1f8950"/><stop offset="1" stop-color="#12613a"/>
  </linearGradient>
  <linearGradient id="f_ll" x1="1" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2ba463"/><stop offset="1" stop-color="#187345"/>
  </linearGradient>
  <linearGradient id="f_l" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#74dd98"/><stop offset="1" stop-color="#3fbd75"/>
  </linearGradient>
  <filter id="soft" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur stdDeviation="14"/>
  </filter>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
    <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#04100b" flood-opacity="0.55"/>
  </filter>
  <filter id="plate" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.3"/>
  </filter>
</defs>
"""


def pts(points):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in points)


def gem(scale, fine, shadow=True):
    """A tall six-sided cut stone around (512, 512), lit from the upper left."""
    w, h, shoulder = 142 * scale, 232 * scale, 116 * scale
    outer = [(0, -h), (w, -shoulder), (w, shoulder), (0, h), (-w, shoulder), (-w, -shoulder)]
    k = 0.5
    inner = [(x * k, y * k) for x, y in outer]
    outer = [(512 + x, 512 + y) for x, y in outer]
    inner = [(512 + x, 512 + y) for x, y in inner]
    fills = ["f_ur", "f_r", "f_lr", "f_ll", "f_l", "f_ul"]
    out = ['<g filter="url(#shadow)">' if shadow else "<g>"]
    for i, fill in enumerate(fills):
        j = (i + 1) % 6
        quad = [outer[i], outer[j], inner[j], inner[i]]
        # A hairline stroke in the facet's own paint closes the seams between neighbours.
        out.append(f'<polygon points="{pts(quad)}" fill="url(#{fill})" stroke="url(#{fill})" stroke-width="1.5"/>')
    out.append(f'<polygon points="{pts(inner)}" fill="url(#table)"/>')
    out.append("</g>")
    if fine:
        ridges = "".join(
            f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}"/>' for a, b in zip(outer, inner)
        )
        out.append(f'<g stroke="#eafff0" stroke-opacity="0.42" stroke-width="3" stroke-linecap="round">{ridges}</g>')
        out.append(
            f'<polygon points="{pts(inner)}" fill="none" stroke="#eafff0" stroke-opacity="0.5" stroke-width="3" '
            'stroke-linejoin="round"/>'
        )
        # Bright rim on the two lit edges.
        out.append(
            f'<polyline points="{pts([outer[4], outer[5], outer[0]])}" fill="none" stroke="#ffffff" '
            'stroke-opacity="0.75" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/>'
        )
        out.append(sparkle(512 - w * 0.62, 512 - h * 0.6, 46 * scale))
    return "\n".join(out)


def sparkle(cx, cy, r):
    k = 0.16
    points = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * k
        points.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return f'<polygon points="{pts(points)}" fill="#ffffff" fill-opacity="0.95"/>'


def ring(radius, width, share, fine):
    """A progress ring starting at twelve o'clock, `share` of it filled."""
    around = 2 * math.pi * radius
    out = [
        f'<circle cx="512" cy="512" r="{radius}" fill="none" stroke="#ffffff" stroke-opacity="0.09" '
        f'stroke-width="{width}"/>'
    ]
    arc = (
        f'<circle cx="512" cy="512" r="{radius}" fill="none" stroke="url(#gold)" stroke-width="{width}" '
        f'stroke-linecap="round" stroke-dasharray="{around * share:.1f} {around:.1f}" '
        'transform="rotate(-90 512 512)"{extra}/>'
    )
    if fine:
        out.append(arc.format(extra=' filter="url(#soft)" opacity="0.45"'))
    out.append(arc.format(extra=""))
    return "\n".join(out)


def waves(radii, width, half_angle, fine):
    """Broadcast arcs to the left and right of the stone."""
    out = []
    for n, radius in enumerate(radii):
        for side in (0, 180):
            a0, a1 = math.radians(side - half_angle), math.radians(side + half_angle)
            x0, y0 = 512 + radius * math.cos(a0), 512 + radius * math.sin(a0)
            x1, y1 = 512 + radius * math.cos(a1), 512 + radius * math.sin(a1)
            d = f"M {x0:.1f} {y0:.1f} A {radius} {radius} 0 0 1 {x1:.1f} {y1:.1f}"
            opacity = 1 if n == 0 else 0.6
            if fine:
                out.append(
                    f'<path d="{d}" fill="none" stroke="#f5c043" stroke-width="{width}" stroke-linecap="round" '
                    f'filter="url(#soft)" opacity="{0.4 * opacity}"/>'
                )
            # userSpaceOnUse keeps the gradient across all arcs instead of per bounding box.
            out.append(
                f'<path d="{d}" fill="none" stroke="url(#gold_all)" stroke-width="{width}" stroke-linecap="round" '
                f'opacity="{opacity}"/>'
            )
    gradient = (
        '<linearGradient id="gold_all" gradientUnits="userSpaceOnUse" x1="150" y1="250" x2="874" y2="774">'
        '<stop offset="0" stop-color="#fff0b0"/><stop offset="0.45" stop-color="#f5c043"/>'
        '<stop offset="1" stop-color="#c8841c"/></linearGradient>'
    )
    return gradient + "\n".join(out)


def arc_shape(radius, width, start, end):
    """A thick arc with round ends as a filled outline; angles in degrees, clockwise from three o'clock."""
    a0, a1 = math.radians(start), math.radians(end)
    ro, ri, cap = radius + width / 2, radius - width / 2, width / 2
    large = 1 if end - start > 180 else 0

    def at(r, a):
        return f"{512 + r * math.cos(a):.2f} {512 + r * math.sin(a):.2f}"

    return (
        f"M {at(ro, a0)} A {ro} {ro} 0 {large} 1 {at(ro, a1)} A {cap} {cap} 0 0 1 {at(ri, a1)} "
        f"A {ri} {ri} 0 {large} 0 {at(ri, a0)} A {cap} {cap} 0 0 1 {at(ro, a0)} Z"
    )


GOLD_ALL = (
    '<linearGradient id="gold_all" gradientUnits="userSpaceOnUse" x1="150" y1="250" x2="874" y2="774">'
    '<stop offset="0" stop-color="#fff0b0"/><stop offset="0.45" stop-color="#f5c043"/>'
    '<stop offset="1" stop-color="#c8841c"/></linearGradient>'
)


def layer(body, defs=""):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
        f"<defs>{defs}</defs>{body}</svg>\n"
    )


def gem_defs():
    """Only the stone's gradients: Icon Composer layers cannot use filters."""
    start = DEFS.index('<linearGradient id="table"')
    return DEFS[start : DEFS.index("<filter")]


# The stone for the tinted and clear styles, which only keep brightness: nearly white where it is lit.
PALE = {
    "table": ("#ffffff", "#e3f8ea"),
    "f_ul": ("#ffffff", "#f2fff5"),
    "f_ur": ("#f4fff7", "#dcf7e4"),
    "f_l": ("#e9fbee", "#cfeeda"),
    "f_r": ("#bfe3cb", "#a9d4b8"),
    "f_ll": ("#a5cfb3", "#8fbd9f"),
    "f_lr": ("#8fbd9f", "#789f86"),
}


def pale_defs():
    return "".join(
        f'<linearGradient id="{name}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{a}"/>'
        f'<stop offset="1" stop-color="{b}"/></linearGradient>'
        for name, (a, b) in PALE.items()
    )


def write_layered(kind, folder, platform="macOS"):
    """An Icon Composer document: macOS and iOS 26 and later redraw its layers for the dark, clear and tinted styles."""
    assets = folder / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "gem.svg").write_text(layer(gem(1.12, True, shadow=False), gem_defs()))
    (assets / "gem_pale.svg").write_text(layer(gem(1.12, True, shadow=False), pale_defs()))
    if kind == "app":
        gold = f'<path d="{arc_shape(346, 46, -90, -90 + 360 * 0.78)}" fill="url(#gold_all)"/>'
        faint = '<path fill-rule="evenodd" fill="#ffffff" d="M 143 512 a 369 369 0 1 0 738 0 a 369 369 0 1 0 -738 0 Z M 189 512 a 323 323 0 1 0 646 0 a 323 323 0 1 0 -646 0 Z"/>'
    else:
        gold = "".join(
            f'<path d="{arc_shape(262, 46, side - 34, side + 34)}" fill="url(#gold_all)"/>' for side in (0, 180)
        )
        faint = "".join(
            f'<path d="{arc_shape(356, 46, side - 34, side + 34)}" fill="url(#gold_all)"/>' for side in (0, 180)
        )
    (assets / "gold.svg").write_text(layer(gold, GOLD_ALL))
    (assets / "faint.svg").write_text(layer(faint, GOLD_ALL))
    document = {
        "fill": {"linear-gradient": ["srgb:0.15294,0.38431,0.29020,1.00000", "srgb:0.03922,0.10980,0.08235,1.00000"]},
        "groups": [
            {
                "layers": [
                    {
                        "image-name": "gem.svg",
                        "name": "gem",
                        "glass": True,
                        "hidden-specializations": [{"value": False}, {"appearance": "tinted", "value": True}],
                    },
                    {
                        "image-name": "gem_pale.svg",
                        "name": "gem pale",
                        "glass": True,
                        "hidden-specializations": [{"value": True}, {"appearance": "tinted", "value": False}],
                    },
                ],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.5},
            },
            {
                "layers": [
                    {"image-name": "gold.svg", "name": "gold", "glass": True},
                    {
                        "image-name": "faint.svg",
                        "name": "faint",
                        "glass": False,
                        "opacity": 0.09 if kind == "app" else 0.6,
                    },
                ],
                "shadow": {"kind": "neutral", "opacity": 0.35},
                "translucency": {"enabled": False, "value": 0.5},
            },
        ],
        "supported-platforms": {"squares": [platform]},
    }
    (folder / "icon.json").write_text(json.dumps(document, indent=2) + "\n")


def art(kind, fine):
    """The drawing without its background, on a 1024 canvas."""
    parts = []
    if kind == "app":
        parts.append('<circle cx="512" cy="512" r="330" fill="url(#glow)"/>')
        parts.append(ring(346, 46, 0.78, True) if fine else ring(356, 92, 0.78, False))
        parts.append(gem(1.12 if fine else 1.16, fine))
    else:
        parts.append('<circle cx="512" cy="512" r="330" fill="url(#glow)"/>')
        parts.append(waves((262, 356), 46, 34, True) if fine else waves((300,), 92, 40, False))
        parts.append(gem(1.12 if fine else 1.16, fine))
    return "\n".join(parts)


BACKGROUND = '<rect width="1024" height="1024" fill="url(#bg)"/>'
# A soft light from above and a hairline along the plate's edge.
SHEEN = (
    '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.10"/>'
    '<stop offset="0.5" stop-color="#fff" stop-opacity="0"/></linearGradient>'
    '<rect width="1024" height="1024" fill="url(#sheen)"/>'
)


def svg(kind, shape, fine=True):
    """shape: full (square), mac (824 plate with shadow), round (rounded plate), fg (art only), bg."""
    body = BACKGROUND + SHEEN + art(kind, fine)
    if shape == "full":
        inner = body
    elif shape == "bg":
        inner = BACKGROUND
    elif shape == "fg":
        # Android crops adaptive icons to the middle two thirds.
        inner = f'<g transform="translate(512 512) scale(0.62) translate(-512 -512)">{art(kind, fine)}</g>'
    else:
        size, radius = (824, 185) if shape == "mac" else (980, 220)
        k, off = size / 1024, (1024 - size) / 2
        edge = (
            f'<rect x="{off + 1.5}" y="{off + 1.5}" width="{size - 3}" height="{size - 3}" rx="{radius - 1.5}" '
            'fill="none" stroke="#ffffff" stroke-opacity="0.14" stroke-width="3"/>'
        )
        inner = (
            f'<clipPath id="clip"><rect x="{off}" y="{off}" width="{size}" height="{size}" rx="{radius}"/></clipPath>'
            f'<g{" filter=" + chr(34) + "url(#plate)" + chr(34) if shape == "mac" else ""}>'
            f'<g clip-path="url(#clip)"><g transform="translate({off} {off}) scale({k})">{body}</g></g></g>'
            + (edge if fine else "")
        )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{RENDER}" height="{RENDER}" viewBox="0 0 1024 1024">'
        f"{DEFS}{inner}</svg>"
    )


_cache = {}


def render(kind, shape, fine=True):
    """Renders one drawing at RENDER px (RGBA)."""
    key = (kind, shape, fine)
    if key not in _cache:
        with tempfile.TemporaryDirectory() as tmp:
            page, shot = Path(tmp, "icon.html"), Path(tmp, "icon.png")
            page.write_text(
                "<!doctype html><html><body style='margin:0;background:transparent;overflow:hidden'>"
                + svg(kind, shape, fine)
                + "</body></html>"
            )
            subprocess.run(
                [
                    CHROME,
                    "--headless=new",
                    "--disable-gpu",
                    "--hide-scrollbars",
                    "--force-device-scale-factor=1",
                    "--default-background-color=00000000",
                    f"--window-size={RENDER},{RENDER}",
                    f"--user-data-dir={tmp}/profile",
                    f"--screenshot={shot}",
                    page.as_uri(),
                ],
                check=True,
                capture_output=True,
                timeout=120,
            )
            image = Image.open(shot).convert("RGBA")
            if image.size != (RENDER, RENDER):
                sys.exit(f"Chrome rendered {image.size}, expected {RENDER} px")
            _cache[key] = image
    return _cache[key]


def icon(kind, shape, size, opaque=False):
    image = render(kind, shape, fine=size > SMALL).resize((size, size), Image.LANCZOS)
    return image.convert("RGB") if opaque else image


def write(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def write_ico(kind, path):
    sizes = [256, 128, 64, 48, 32, 24, 16]
    images = [icon(kind, "round", s) for s in sizes]
    images[0].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=images[1:])


ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""


def write_all():
    for kind, project in (("app", "app"), ("host", "host")):
        mac = ROOT / project / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
        for size in (16, 32, 64, 128, 256, 512, 1024):
            write(icon(kind, "mac", size), mac / f"app_icon_{size}.png")
        write_layered(kind, ROOT / project / "macos/Runner/AppIcon.icon")
        write_ico(kind, ROOT / project / "windows/runner/resources/app_icon.ico")
        write(icon(kind, "round", 256), ROOT / "tools/appimage" / f"{kind}.png")

    write_layered("app", ROOT / "app/ios/Runner/AppIcon.icon", platform="iOS")
    ios = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for points, scales in ((20, (1, 2, 3)), (29, (1, 2, 3)), (40, (1, 2, 3)), (60, (2, 3)), (76, (1, 2)), (83.5, (2,))):
        for scale in scales:
            name = f"Icon-App-{points:g}x{points:g}@{scale}x.png"
            write(icon("app", "full", round(points * scale), opaque=True), ios / name)
    write(icon("app", "full", 1024, opaque=True), ios / "Icon-App-1024x1024@1x.png")

    res = ROOT / "app/android/app/src/main/res"
    for density, factor in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
        folder = res / f"mipmap-{density}"
        write(icon("app", "round", round(48 * factor)), folder / "ic_launcher.png")
        layer = round(108 * factor)
        write(render("app", "fg").resize((layer, layer), Image.LANCZOS), folder / "ic_launcher_foreground.png")
        write(render("app", "bg").resize((layer, layer), Image.LANCZOS).convert("RGB"), folder / "ic_launcher_background.png")
    adaptive = res / "mipmap-anydpi-v26/ic_launcher.xml"
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    adaptive.write_text(ADAPTIVE)

    for kind in ("app", "host"):
        (ROOT / "tools/icons" / f"{kind}.svg").write_text(svg(kind, "full").replace(f'"{RENDER}"', '"1024"') + "\n")


def write_preview(folder):
    folder.mkdir(parents=True, exist_ok=True)
    for kind in ("app", "host"):
        write(icon(kind, "mac", 1024), folder / f"{kind}_mac.png")
        write(icon(kind, "full", 512), folder / f"{kind}_full.png")
    # One sheet with every shape and the small sizes at their real size.
    sheet = Image.new("RGBA", (1500, 1130), "#8a8f98")
    for row, kind in enumerate(("app", "host")):
        y = 20 + row * 560
        x = 20
        for shape, size in (("mac", 512), ("round", 256), ("full", 256)):
            sheet.alpha_composite(icon(kind, shape, size), (x, y))
            x += size + 20
        x = 20 + 512 + 20
        for size in (128, 64, 48, 32, 24, 16):
            sheet.alpha_composite(icon(kind, "mac", size), (x, y + 290))
            sheet.alpha_composite(icon(kind, "round", size), (x, y + 290 + 140))
            x += size + 16
        # Android: the adaptive layers under a circle mask.
        layers = render(kind, "bg").copy()
        layers.alpha_composite(render(kind, "fg"))
        crop = layers.resize((324, 324), Image.LANCZOS).crop((54, 54, 270, 270))
        mask = Image.new("L", (864, 864), 0)
        from PIL import ImageDraw

        ImageDraw.Draw(mask).ellipse((0, 0, 863, 863), fill=255)
        crop.putalpha(mask.resize((216, 216), Image.LANCZOS))
        sheet.alpha_composite(crop, (1100, y + 290))
    write(sheet, folder / "sheet.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--preview", type=Path, metavar="DIR", help="only write preview PNGs into DIR")
    args = parser.parse_args()
    if not Path(CHROME).exists():
        sys.exit(f"No Chrome at {CHROME}; set $CHROME to a Chromium binary.")
    if args.preview:
        write_preview(args.preview)
    else:
        write_all()


if __name__ == "__main__":
    main()
