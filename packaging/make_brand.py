"""Render RIFT's brand assets from the real logo font.

The supplied SVGs are LIVE TEXT referencing "Yessie's brother", not outlined
paths, so they only render correctly on a machine with that font installed --
which no end user will have. The supplied PNGs are correct but tiny (77x133),
far too small for a 256px icon. So the glyphs are re-rendered here from the
installed OTF at high resolution, and only pixels ship.

Outputs:
  assets/rift.ico          app icon, monogram on the dark app background
  assets/logo_wordmark.png "RiFT" in white on transparent, for the About dialog
  assets/logo_monogram.png the monogram alone, white on transparent
"""
from PIL import Image, ImageDraw, ImageFont
import os

# The repo copy, not the machine-installed one: regenerating the icon must
# not depend on what happens to be installed locally.
FONT = r"H:\ROGUEX PORTFOLIO\RIFT_engine\assets\fonts\yessiesbrotherregular.otf"
OUT  = r"H:\ROGUEX PORTFOLIO\RIFT_engine\assets"

BG     = (13, 13, 15, 255)      # Theme.bg, so the icon matches the app
ACCENT = (232, 68, 46, 255)     # Theme.accent
WHITE  = (255, 255, 255, 255)

# The logo sets -0.1em tracking. PIL has no tracking, so glyphs are placed one
# at a time and the advance is adjusted by hand.
TRACK = -0.10


def render_text(text, px, colour):
    """Draw `text` at `px` em size, tightly cropped, on transparent."""
    font = ImageFont.truetype(FONT, px)
    # Generous canvas: the real extent is measured after drawing, because
    # getbbox on a decorative face understates overhang.
    W, H = px * len(text) * 2, px * 3
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    x = px * 0.5
    y = px * 0.8
    for ch in text:
        d.text((x, y), ch, font=font, fill=colour)
        x += font.getlength(ch) + TRACK * px

    return im.crop(im.getbbox())


def icon_at(px, mono):
    """The monogram centred on the app's rounded-square background."""
    S = px * 4                                  # supersample, then reduce
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.18), fill=BG)

    # The mark fills ~62% of the tile. At taskbar sizes the strokes of this
    # face are barely a pixel wide, so small tiles trade padding for legibility
    # rather than shrinking the mark to a smudge.
    target_h = int(S * (0.80 if px <= 32 else 0.62))
    scale = target_h / mono.height
    m = mono.resize((max(1, int(mono.width * scale)), target_h), Image.LANCZOS)
    im.paste(m, ((S - m.width) // 2, (S - m.height) // 2), m)
    return im.resize((px, px), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)

# Master renders, big enough that every downscale is a reduction.
mono_accent = render_text("R1",   900, ACCENT)
mono_white  = render_text("R1",   900, WHITE)
word_white  = render_text("RiFT", 900, WHITE)

sizes = [16, 24, 32, 48, 64, 128, 256]

# White is the brand's own dark-background monogram; red is the app accent.
# Both are built so the choice is a one-line switch, not a re-render.
variants = {"white": mono_white, "accent": mono_accent}
built = {}
for name, mark in variants.items():
    built[name] = [icon_at(s, mark) for s in sizes]
    path = os.path.join(OUT, "rift.ico" if name == "white"
                             else "rift_accent.ico")
    built[name][-1].save(path, format="ICO", sizes=[(s, s) for s in sizes])
    print(path, os.path.getsize(path), "bytes")
imgs = built["white"]

mono_white.save(os.path.join(OUT, "logo_monogram.png"))
word_white.save(os.path.join(OUT, "logo_wordmark.png"))
print("wordmark", word_white.size, "monogram", mono_white.size)

# Contact sheet, so the small icon sizes can actually be judged.
sheet = Image.new("RGBA", (sum(sizes) + 20 * len(sizes), 420), (30, 30, 34, 255))
for row, name in enumerate(["white", "accent"]):
    x, cy = 10, 60 + row * 120
    for s, im in zip(sizes, built[name]):
        sheet.paste(im, (x, cy - s // 2), im)
        x += s + 20
w = word_white.resize((int(word_white.width * 90 / word_white.height), 90),
                      Image.LANCZOS)
sheet.paste(w, (10, 370 - 45), w)
sheet.save(os.path.join(OUT, "rift_sheet.png"))
print("sheet written")
