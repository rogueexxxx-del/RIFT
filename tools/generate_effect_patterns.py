import os
import math
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "effect_previews")
os.makedirs(OUT_DIR, exist_ok=True)

W, H = 450, 100

def create_base():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))

def gen_ascii():
    im = create_base()
    draw = ImageDraw.Draw(im)
    chars = "@%#*+=-:. "
    step_x = 10
    step_y = 12
    for y in range(0, H, step_y):
        for x in range(0, W, step_x):
            # calculate noise-like wave
            v = int((math.sin(x * 0.05) + math.cos(y * 0.08) + 2) * 2.5) % len(chars)
            ch = chars[v]
            draw.text((x, y), ch, fill=(0, 0, 0, 180))
    return im

def gen_dither():
    im = create_base()
    draw = ImageDraw.Draw(im)
    # Bayer matrix / dither dot grid
    for y in range(0, H, 4):
        for x in range(0, W, 4):
            factor = (x / W) * (y / H)
            if ((x // 4 + y // 4) % 2 == 0) or ((x * 7 + y * 13) % 5 < 3):
                draw.rectangle([x, y, x + 1, y + 1], fill=(0, 0, 0, 200))
    return im

def gen_tunnel():
    im = create_base()
    draw = ImageDraw.Draw(im)
    cx, cy = W // 2, H // 2
    # Concentric perspective rectangles & lines to center
    for i in range(1, 14):
        rw = int(W * (i / 14.0) ** 1.5)
        rh = int(H * (i / 14.0) ** 1.5)
        draw.rectangle([cx - rw // 2, cy - rh // 2, cx + rw // 2, cy + rh // 2], outline=(0, 0, 0, 160), width=2)
    # 4 corner lines
    draw.line([0, 0, cx, cy], fill=(0, 0, 0, 180), width=2)
    draw.line([W, 0, cx, cy], fill=(0, 0, 0, 180), width=2)
    draw.line([0, H, cx, cy], fill=(0, 0, 0, 180), width=2)
    draw.line([W, H, cx, cy], fill=(0, 0, 0, 180), width=2)
    return im

def gen_risograph():
    im = create_base()
    draw = ImageDraw.Draw(im)
    # Halftone stipple dot rosette
    for y in range(0, H, 6):
        for x in range(0, W, 6):
            r = int((math.sin(x * 0.04) * math.cos(y * 0.05) + 1.0) * 2.2)
            if r > 0:
                draw.ellipse([x - r, y - r, x + r, y + r], fill=(0, 0, 0, 170))
    return im

def gen_glitch():
    im = create_base()
    draw = ImageDraw.Draw(im)
    for y in range(4, H, 8):
        offset = int(math.sin(y * 0.3) * 30)
        draw.rectangle([50 + offset, y, 200 + offset, y + 3], fill=(0, 0, 0, 180))
        draw.rectangle([250 - offset, y + 2, 400 - offset, y + 5], fill=(0, 0, 0, 160))
    return im

def gen_halftone():
    im = create_base()
    draw = ImageDraw.Draw(im)
    for y in range(0, H, 8):
        for x in range(0, W, 8):
            r = int((x / W) * 3.5 + 0.5)
            draw.ellipse([x - r, y - r, x + r, y + r], fill=(0, 0, 0, 180))
    return im

def gen_oscilloscope():
    im = create_base()
    draw = ImageDraw.Draw(im)
    pts = []
    cy = H // 2
    for x in range(0, W, 2):
        y = cy + int(math.sin(x * 0.05) * 28 * math.sin(x * 0.012) + math.sin(x * 0.15) * 8)
        pts.append((x, y))
    for i in range(len(pts) - 1):
        draw.line([pts[i], pts[i+1]], fill=(0, 0, 0, 200), width=3)
    return im

def gen_voronoi():
    im = create_base()
    draw = ImageDraw.Draw(im)
    # Triangular / polygonal grid lines
    points = []
    for r in range(0, H + 30, 25):
        for c in range(0, W + 30, 45):
            ox = int(math.sin(r + c) * 12)
            oy = int(math.cos(r * 2 + c) * 10)
            points.append((c + ox, r + oy))
    for i in range(len(points) - 1):
        p1 = points[i]
        p2 = points[i + 1]
        if (p1[0] - p2[0])**2 + (p1[1] - p2[1])**2 < 3600:
            draw.line([p1, p2], fill=(0, 0, 0, 160), width=2)
    return im

def gen_terminal():
    im = create_base()
    draw = ImageDraw.Draw(im)
    for y in range(0, H, 4):
        draw.line([(0, y), (W, y)], fill=(0, 0, 0, 120), width=1)
    draw.rectangle([20, 25, 34, 45], fill=(0, 0, 0, 190))
    draw.text((45, 28), "> _", fill=(0, 0, 0, 190))
    return im

def gen_lens():
    im = create_base()
    draw = ImageDraw.Draw(im)
    cx, cy = W // 2, H // 2
    for r in range(15, 160, 15):
        draw.ellipse([cx - r*2, cy - r, cx + r*2, cy + r], outline=(0, 0, 0, 150), width=2)
    return im

def gen_dot_field():
    im = create_base()
    draw = ImageDraw.Draw(im)
    for y in range(6, H, 12):
        for x in range(6, W, 12):
            draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(0, 0, 0, 180))
    return im

def gen_flow_warp():
    im = create_base()
    draw = ImageDraw.Draw(im)
    for y_base in range(10, H, 14):
        pts = [(x, y_base + int(math.sin(x * 0.03 + y_base * 0.1) * 12)) for x in range(0, W, 4)]
        for i in range(len(pts) - 1):
            draw.line([pts[i], pts[i+1]], fill=(0, 0, 0, 160), width=2)
    return im

def gen_default_lines():
    im = create_base()
    draw = ImageDraw.Draw(im)
    for x in range(0, W, 10):
        draw.line([(x, 0), (x + 30, H)], fill=(0, 0, 0, 140), width=2)
    return im

generators = {
    "ascii": gen_ascii,
    "dither": gen_dither,
    "tunnel": gen_tunnel,
    "risograph": gen_risograph,
    "glitch": gen_glitch,
    "halftone": gen_halftone,
    "oscilloscope": gen_oscilloscope,
    "voronoi_shatter": gen_voronoi,
    "terminal": gen_terminal,
    "lens": gen_lens,
    "dot_field": gen_dot_field,
    "flow_warp": gen_flow_warp,
}

all_effects = [
    "ascii", "halftone", "dither", "glitch", "pixel_sort", "blur", "oscilloscope",
    "datamosh", "cyanotype", "risograph", "thermal", "terminal", "electron_scan",
    "kaleido", "mirror_tile", "flow_warp", "voronoi_shatter", "dot_field",
    "tunnel", "lens", "bloom", "feedback", "slit_scan", "post_fx"
]

for eff in all_effects:
    gen_func = generators.get(eff, gen_default_lines)
    img = gen_func()
    out_path = os.path.join(OUT_DIR, f"{eff}.png")
    img.save(out_path, "PNG")
    print(f"Generated {eff}.png")

print("All patterns generated successfully.")
