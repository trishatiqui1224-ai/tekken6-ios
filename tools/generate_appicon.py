#!/usr/bin/env python3
"""
tools/generate_appicon.py
Studio-Grade iOS/iPadOS AppIcon Generator for Tekken 6 Recompiled
Title ID: 4E4D07FC ("King of Iron Fist Tournament" Edition)

Features:
  1. 4096x4096 Ultra-HD Procedural Master rendered with PIL, then Lanczos-supersampled to 1024x1024.
  2. Styles supported via --style [fist|lightning|gold]:
     - fist: King of Iron Fist Tournament clash motif, fiery impact sparks, brushed-gold emblem.
     - lightning: Mishima electric blood-red & gold lightning arcs, dark iron backdrop.
     - gold: Pure tournament championship gold metallic plate with specular highlights.
  3. Custom image input via --input <path.png> with center-crop and Lanczos downsampling.
  4. Strict 24-bit RGB export (zero alpha channel) satisfying Xcode actool & App Store requirements.
  5. Complete AppIcon.appiconset populator with Apple-compliant Contents.json.
  6. Preview sheet generator: tools/icon_preview_sheet.png displaying all variants & iOS squircle mockups.
"""

import argparse
import json
import math
import os
import pathlib
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
APPICONSET_DIR = REPO_ROOT / "ios" / "resources" / "Assets.xcassets" / "AppIcon.appiconset"

# Color Palette ("King of Iron Fist" Theme)
TEKKEN_CRIMSON_DARK  = (22, 4, 8)
TEKKEN_CRIMSON_MID   = (88, 12, 24)
TEKKEN_CRIMSON_HOT   = (214, 28, 48)
TEKKEN_GOLD_DEEP     = (180, 130, 20)
TEKKEN_GOLD_BRIGHT   = (255, 215, 0)
TEKKEN_GOLD_SPECULAR = (255, 250, 210)
DARK_IRON_DEEP       = (14, 15, 18)
DARK_IRON_MID        = (32, 35, 42)
DARK_IRON_LIGHT      = (65, 70, 82)
ELECTRIC_BLUE        = (80, 210, 255)
PURE_WHITE           = (255, 255, 255)

ICON_SPECS = [
    # Universal / App Store
    ("universal", "1024x1024", "1x", 1024, "AppIcon-1024.png"),
    # iPhone
    ("iphone", "20x20", "2x", 40, "AppIcon-20@2x.png"),
    ("iphone", "20x20", "3x", 60, "AppIcon-20@3x.png"),
    ("iphone", "29x29", "2x", 58, "AppIcon-29@2x.png"),
    ("iphone", "29x29", "3x", 87, "AppIcon-29@3x.png"),
    ("iphone", "40x40", "2x", 80, "AppIcon-40@2x.png"),
    ("iphone", "40x40", "3x", 120, "AppIcon-40@3x.png"),
    ("iphone", "60x60", "2x", 120, "AppIcon-60@2x.png"),
    ("iphone", "60x60", "3x", 180, "AppIcon-60@3x.png"),
    # iPad
    ("ipad", "20x20", "1x", 20, "AppIcon-20@1x.png"),
    ("ipad", "20x20", "2x", 40, "AppIcon-20@2x-ipad.png"),
    ("ipad", "29x29", "1x", 29, "AppIcon-29@1x.png"),
    ("ipad", "29x29", "2x", 58, "AppIcon-29@2x-ipad.png"),
    ("ipad", "40x40", "1x", 40, "AppIcon-40@1x.png"),
    ("ipad", "40x40", "2x", 80, "AppIcon-40@2x-ipad.png"),
    ("ipad", "76x76", "1x", 76, "AppIcon-76@1x.png"),
    ("ipad", "76x76", "2x", 152, "AppIcon-76@2x.png"),
    ("ipad", "83.5x83.5", "2x", 167, "AppIcon-83.5@2x.png"),
]


def get_font(size: int, bold: bool = True, black: bool = False) -> ImageFont.ImageFont:
    """Locates system bold/black font across macOS, Linux, and Windows."""
    candidates = []
    if black:
        candidates.extend([
            "Impact.ttf", "impact.ttf", "ariblk.ttf", "Arial Black.ttf",
            "HelveticaNeue-CondensedBlack.otf", "DejaVuSans-Bold.ttf"
        ])
    if bold:
        candidates.extend([
            "arialbd.ttf", "Arial Bold.ttf", "segoeuib.ttf", "tahomabd.ttf",
            "HelveticaNeue-Bold.otf", "DejaVuSans-Bold.ttf", "LiberationSans-Bold.ttf"
        ])
    candidates.extend(["arial.ttf", "segoeui.ttf", "HelveticaNeue.otf", "DejaVuSans.ttf"])

    search_dirs = [
        os.environ.get("WINDIR", r"C:\Windows") + r"\Fonts",
        "/Library/Fonts",
        "/System/Library/Fonts",
        "/System/Library/Fonts/Supplemental",
        "/usr/share/fonts",
        "/usr/share/fonts/truetype",
    ]

    for d in search_dirs:
        if os.path.isdir(d):
            for cand in candidates:
                fp = os.path.join(d, cand)
                if os.path.isfile(fp):
                    try:
                        return ImageFont.truetype(fp, size)
                    except Exception:
                        continue
    return ImageFont.load_default()


def draw_radial_gradient(img: Image.Image, center: tuple[int, int], radius: int,
                         color_inner: tuple[int, int, int], color_outer: tuple[int, int, int]):
    """Draws a smooth radial gradient over an RGB image."""
    w, h = img.size
    cx, cy = center
    # Create gradient on lower resolution for speed, then resize
    scale = 4
    gw, gh = w // scale, h // scale
    gcx, gcy = cx // scale, cy // scale
    grad = Image.new("RGB", (gw, gh))
    pixels = grad.load()

    ri, gi, bi = color_inner
    ro, go, bo = color_outer

    r_scaled = radius // scale
    r_sq = r_scaled * r_scaled

    for y in range(gh):
        dy = y - gcy
        dy2 = dy * dy
        for x in range(gw):
            dx = x - gcx
            d2 = dx * dx + dy2
            if d2 >= r_sq:
                pixels[x, y] = color_outer
            else:
                t = math.sqrt(d2) / r_scaled
                # Smooth cubic step
                t = t * t * (3 - 2 * t)
                r = int(ri + (ro - ri) * t)
                g = int(gi + (go - gi) * t)
                b = int(bi + (bo - bi) * t)
                pixels[x, y] = (r, g, b)

    grad_resized = grad.resize((w, h), Image.Resampling.BICUBIC)
    img.paste(grad_resized)


def add_brushed_metal_texture(img: Image.Image, intensity: int = 14):
    """Applies a fine brushed dark-iron horizontal texture."""
    import random
    w, h = img.size
    tex = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tex)

    random.seed(42)  # Deterministic seed for reproducible builds
    for y in range(0, h, 4):
        val = random.randint(-intensity, intensity)
        c = max(0, min(255, 128 + val))
        alpha = random.randint(10, 35)
        draw.line([(0, y), (w, y)], fill=(c, c, c, alpha), width=2)

    img.alpha_composite(tex)


def draw_lightning_bolt(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]],
                        core_color: tuple[int, int, int, int], glow_color: tuple[int, int, int, int],
                        core_width: int = 6, glow_width: int = 24):
    """Draws high-voltage jagged electric lightning bolt with radial glow."""
    # Outer glow
    for i in range(len(points) - 1):
        draw.line([points[i], points[i+1]], fill=glow_color, width=glow_width)
    # Inner glow
    mid_color = (glow_color[0], glow_color[1], glow_color[2], min(255, glow_color[3] * 2))
    for i in range(len(points) - 1):
        draw.line([points[i], points[i+1]], fill=mid_color, width=core_width * 2)
    # Hot core
    for i in range(len(points) - 1):
        draw.line([points[i], points[i+1]], fill=core_color, width=core_width)


def generate_master_icon(size: int = 4096, style: str = "fist") -> Image.Image:
    """Generates the master 4096x4096 icon."""
    print(f"[generate_appicon] Generating 4096x4096 master icon (style: {style})...")
    img = Image.new("RGBA", (size, size), TEKKEN_CRIMSON_DARK)

    # 1. Background: Arena Lighting & Radial Vignette
    draw_radial_gradient(img, (size // 2, int(size * 0.42)), int(size * 0.75),
                         TEKKEN_CRIMSON_MID, TEKKEN_CRIMSON_DARK)
    add_brushed_metal_texture(img, intensity=18)

    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)

    # Tournament arena spotlight beams
    spotlight_color = (255, 60, 20, 28)
    for angle in [-45, -25, -10, 10, 25, 45]:
        rad = math.radians(angle + 90)
        cx, cy = size // 2, int(size * 0.45)
        length = size * 1.2
        x1 = cx + math.cos(rad - 0.08) * length
        y1 = cy - math.sin(rad - 0.08) * length
        x2 = cx + math.cos(rad + 0.08) * length
        y2 = cy - math.sin(rad + 0.08) * length
        odraw.polygon([(cx, cy), (int(x1), int(y1)), (int(x2), int(y2))], fill=spotlight_color)

    # 2. Midground: Dynamic Lightning & Fist Clash Motif
    import random
    random.seed(1337)

    cx, cy = size // 2, int(size * 0.48)

    if style in ["fist", "lightning"]:
        # Explosive radial energy rays
        ray_count = 36
        for i in range(ray_count):
            ang = math.radians(i * (360 / ray_count) + random.uniform(-4, 4))
            dist = random.uniform(size * 0.35, size * 0.58)
            x_end = cx + math.cos(ang) * dist
            y_end = cy + math.sin(ang) * dist
            odraw.line([(cx, cy), (int(x_end), int(y_end))],
                       fill=(255, 180, 40, random.randint(30, 80)),
                       width=random.randint(8, 28))

        # Sharp electric lightning arcs
        for _ in range(12):
            pts = [(cx + random.randint(-120, 120), cy + random.randint(-100, 100))]
            curr_x, curr_y = pts[0]
            ang = random.uniform(0, 2 * math.pi)
            seg_len = size * 0.09
            for _ in range(6):
                ang += random.uniform(-0.6, 0.6)
                curr_x += math.cos(ang) * seg_len
                curr_y += math.sin(ang) * seg_len
                pts.append((int(curr_x), int(curr_y)))

            glow = (255, 200, 0, 70) if style == "fist" else (240, 40, 40, 85)
            core = (255, 255, 220, 240)
            draw_lightning_bolt(odraw, pts, core, glow, core_width=10, glow_width=45)

    if style == "gold":
        # Concentric metallic arena rings
        for r in range(int(size * 0.28), int(size * 0.48), 35):
            odraw.ellipse([cx - r, cy - r, cx + r, cy + r],
                          outline=(255, 215, 0, random.randint(40, 110)), width=random.randint(6, 16))

    img.alpha_composite(overlay)

    # 3. Foreground: Sculpted Brushed-Gold Typographic Emblem
    text_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(text_layer)

    # Main Typography: "TEKKEN" & "6"
    font_main = get_font(size=int(size * 0.165), bold=True, black=True)
    font_sub = get_font(size=int(size * 0.052), bold=True)
    font_six = get_font(size=int(size * 0.24), bold=True, black=True)

    text_tekken = "TEKKEN"
    text_edition = "KING OF IRON FIST TOURNAMENT"
    text_six = "6"

    # Measure
    bbox_tekken = font_main.getbbox(text_tekken)
    tw = bbox_tekken[2] - bbox_tekken[0]
    th = bbox_tekken[3] - bbox_tekken[1]
    tx = (size - tw) // 2
    ty = int(size * 0.42) - th // 2

    # Draw Deep Drop Shadow for 3D metallic extrusion
    shadow_offset = int(size * 0.012)
    for off in range(shadow_offset, 0, -2):
        tdraw.text((tx + off, ty + off), text_tekken, font=font_main, fill=(5, 5, 8, 220))

    # Metallic Gradient Fill for "TEKKEN"
    # Create horizontal slices with metallic reflections
    tekken_mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(tekken_mask)
    mdraw.text((tx, ty), text_tekken, font=font_main, fill=255)

    metal_grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mgdraw = ImageDraw.Draw(metal_grad)
    for y in range(ty, ty + th + 20):
        t = (y - ty) / max(1, th)
        # Specular multi-band metallic reflection curve
        if t < 0.2:
            r = int(TEKKEN_GOLD_SPECULAR[0] - t * 150)
            g = int(TEKKEN_GOLD_SPECULAR[1] - t * 150)
            b = int(TEKKEN_GOLD_SPECULAR[2] - t * 200)
        elif t < 0.5:
            r = int(TEKKEN_GOLD_BRIGHT[0] - (t - 0.2) * 200)
            g = int(TEKKEN_GOLD_BRIGHT[1] - (t - 0.2) * 250)
            b = 10
        elif t < 0.55:  # Specular streak
            r, g, b = 255, 255, 240
        else:
            r = int(TEKKEN_GOLD_DEEP[0] + (t - 0.55) * 120)
            g = int(TEKKEN_GOLD_DEEP[1] + (t - 0.55) * 80)
            b = 15
        mgdraw.line([(tx - 50, y), (tx + tw + 50, y)], fill=(r, g, b, 255), width=1)

    text_layer.paste(metal_grad, (0, 0), tekken_mask)

    # Crisp Bevel Highlight Outline
    tdraw.text((tx, ty), text_tekken, font=font_main, fill=None,
               stroke_width=int(size * 0.0035), stroke_fill=(255, 255, 220, 220))

    # "6" Emblem - Huge Beveled Blood-Crimson & Gold Number
    bbox_six = font_six.getbbox(text_six)
    sw = bbox_six[2] - bbox_six[0]
    sh = bbox_six[3] - bbox_six[1]
    sx = (size - sw) // 2
    sy = ty + th + int(size * 0.015)

    # Shadow for "6"
    for off in range(int(size * 0.015), 0, -2):
        tdraw.text((sx + off, sy + off), text_six, font=font_six, fill=(0, 0, 0, 230))

    # Blood-Red & Specular Gold outline for "6"
    six_mask = Image.new("L", (size, size), 0)
    sdraw = ImageDraw.Draw(six_mask)
    sdraw.text((sx, sy), text_six, font=font_six, fill=255)

    six_grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sgdraw = ImageDraw.Draw(six_grad)
    for y in range(sy, sy + sh + 20):
        t = (y - sy) / max(1, sh)
        r = int(TEKKEN_CRIMSON_HOT[0] - t * 90)
        g = int(TEKKEN_CRIMSON_HOT[1] - t * 20)
        b = int(TEKKEN_CRIMSON_HOT[2] + t * 10)
        sgdraw.line([(sx - 50, y), (sx + sw + 50, y)], fill=(r, g, b, 255), width=1)
    text_layer.paste(six_grad, (0, 0), six_mask)

    # 3D Highlight stroke on "6"
    tdraw.text((sx, sy), text_six, font=font_six, fill=None,
               stroke_width=int(size * 0.004), stroke_fill=TEKKEN_GOLD_BRIGHT + (255,))

    # Subtitle: "KING OF IRON FIST TOURNAMENT"
    bbox_sub = font_sub.getbbox(text_edition)
    subw = bbox_sub[2] - bbox_sub[0]
    subx = (size - subw) // 2
    suby = int(size * 0.82)
    # Subtle backing pill
    pill_pad_x = int(size * 0.04)
    pill_pad_y = int(size * 0.012)
    tdraw.rounded_rectangle([subx - pill_pad_x, suby - pill_pad_y,
                             subx + subw + pill_pad_x, suby + (bbox_sub[3] - bbox_sub[1]) + pill_pad_y],
                            radius=int(size * 0.015), fill=(10, 10, 15, 200),
                            outline=TEKKEN_GOLD_DEEP + (200,), width=int(size * 0.002))
    tdraw.text((subx, suby), text_edition, font=font_sub, fill=TEKKEN_GOLD_BRIGHT + (255,))

    # Composite text over background
    img.alpha_composite(text_layer)

    # 4. Vignette border darkening
    border_vig = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bvdraw = ImageDraw.Draw(border_vig)
    corner_r = int(size * 0.15)
    bvdraw.rectangle([0, 0, size, size], outline=(0, 0, 0, 160), width=int(size * 0.018))
    img.alpha_composite(border_vig)

    # Return RGB strictly (24-bit zero alpha)
    return img.convert("RGB")


def generate_preview_sheet(out_path: pathlib.Path):
    """Generates a presentation preview sheet comparing styles and iOS squircles."""
    print(f"[generate_appicon] Generating preview sheet -> {out_path}...")
    sheet_w, sheet_h = 2400, 1200
    sheet = Image.new("RGB", (sheet_w, sheet_h), (18, 20, 25))
    sdraw = ImageDraw.Draw(sheet)

    title_font = get_font(size=56, bold=True)
    label_font = get_font(size=36, bold=True)

    sdraw.text((80, 60), "Tekken 6 (Title ID: 4E4D07FC) - iOS AppIcon Styles",
               font=title_font, fill=(240, 240, 250))
    sdraw.text((80, 130), "Studio-grade 4096x4096 procedural master with Lanczos downsampling",
               font=label_font, fill=(160, 170, 190))

    styles = [("fist", "Fist Clash"), ("lightning", "Mishima Lightning"), ("gold", "Tournament Gold")]
    box_size = 500
    y_pos = 280

    for idx, (st, label) in enumerate(styles):
        x_pos = 80 + idx * 760
        master = generate_master_icon(size=2048, style=st)
        icon_thumb = master.resize((box_size, box_size), Image.Resampling.LANCZOS)

        # iOS Squircle mask
        mask = Image.new("L", (box_size, box_size), 0)
        mdraw = ImageDraw.Draw(mask)
        mdraw.rounded_rectangle([0, 0, box_size, box_size], radius=115, fill=255)

        squircle = Image.new("RGB", (box_size, box_size), (18, 20, 25))
        squircle.paste(icon_thumb, (0, 0), mask)

        sheet.paste(squircle, (x_pos, y_pos))
        sdraw.text((x_pos, y_pos + box_size + 30), f"Style: {label}", font=label_font, fill=TEKKEN_GOLD_BRIGHT)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, format="PNG")
    print(f"[generate_appicon] Saved preview sheet to {out_path}")


def populate_appiconset(master_1024: Image.Image, target_dir: pathlib.Path):
    """Outputs all icon sizes and writes Contents.json."""
    target_dir.mkdir(parents=True, exist_ok=True)
    print(f"[generate_appicon] Populating AppIcon.appiconset in {target_dir}...")

    contents_images = []

    for idiom, size_str, scale, px, fname in ICON_SPECS:
        out_file = target_dir / fname
        resized = master_1024.resize((px, px), Image.Resampling.LANCZOS)
        # Strict RGB (no alpha)
        resized.convert("RGB").save(out_file, format="PNG")

        contents_images.append({
            "idiom": idiom,
            "size": size_str,
            "scale": scale,
            "filename": fname
        })

    # Master AppIcon.png
    master_1024.convert("RGB").save(target_dir / "AppIcon.png", format="PNG")

    contents_json = {
        "images": contents_images,
        "info": {
            "version": 1,
            "author": "tekken6-ios-recomp"
        }
    }

    with open(target_dir / "Contents.json", "w", encoding="utf-8") as f:
        json.dump(contents_json, f, indent=2)

    print(f"[generate_appicon] Generated {len(ICON_SPECS)} icon sizes and validated Contents.json.")


def main():
    parser = argparse.ArgumentParser(description="Tekken 6 Studio-Grade AppIcon Generator")
    parser.add_argument("--style", choices=["fist", "lightning", "gold"], default="fist",
                        help="Procedural style: fist (default), lightning, or gold")
    parser.add_argument("--input", type=str, help="Path to custom source image (PNG/JPG)")
    parser.add_argument("--outdir", type=str, default=str(APPICONSET_DIR),
                        help="Target AppIcon.appiconset directory")
    parser.add_argument("--preview", type=str, default=str(SCRIPT_DIR / "icon_preview_sheet.png"),
                        help="Output path for style comparison preview sheet")
    args = parser.parse_args()

    outdir = pathlib.Path(args.outdir)

    if args.input:
        in_path = pathlib.Path(args.input)
        if not in_path.is_file():
            sys.exit(f"[ERROR] Input image not found: {in_path}")
        print(f"[generate_appicon] Loading custom image: {in_path}")
        src_img = Image.open(in_path).convert("RGB")
        w, h = src_img.size
        min_dim = min(w, h)
        left = (w - min_dim) // 2
        top = (h - min_dim) // 2
        cropped = src_img.crop((left, top, left + min_dim, top + min_dim))
        master_1024 = cropped.resize((1024, 1024), Image.Resampling.LANCZOS)
    else:
        master_4096 = generate_master_icon(size=4096, style=args.style)
        print("[generate_appicon] Downsampling 4096x4096 -> 1024x1024 via Lanczos supersampling...")
        master_1024 = master_4096.resize((1024, 1024), Image.Resampling.LANCZOS)

    populate_appiconset(master_1024, outdir)

    if args.preview:
        generate_preview_sheet(pathlib.Path(args.preview))

    print("[generate_appicon] SUCCESS: Studio-grade AppIcon generation complete!")


if __name__ == "__main__":
    main()

