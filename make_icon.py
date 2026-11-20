#!/usr/bin/env python3
"""Generate AppIcon.icns for StudyTimer (macOS style stopwatch icon).
Draws at 1024px with PIL, downscales to the icns sizes, packs PNG-based icns.
Local helper only - the released .icns is committed as base64 for GitHub builds.
"""
import io, struct, sys
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# macOS squircle background with a teal -> blue vertical gradient
bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(bg)
for y in range(S):
    t = y / S
    r = int(20 + (10 - 20) * t)
    g = int(184 + (90 - 184) * t)
    b = int(166 + (220 - 166) * t)
    bd.line([(0, y), (S, y)], fill=(r, g, b, 255))
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
inset = 90
md.rounded_rectangle([inset, inset, S - inset, S - inset], radius=190, fill=255)
img.paste(bg, (0, 0), mask)
d = ImageDraw.Draw(img)

cx, cy = S // 2, 560
R = 265
# top button (crown) and side button
d.rounded_rectangle([cx - 52, cy - R - 92, cx + 52, cy - R - 18], radius=22, fill=(255, 255, 255, 255))
d.rectangle([cx - 16, cy - R - 20, cx + 16, cy - R + 26], fill=(255, 255, 255, 255))
d.rounded_rectangle([cx + R - 28, cy - R + 52, cx + R + 38, cy - R + 118], radius=18, fill=(255, 255, 255, 255))
# watch face
d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(255, 255, 255, 255))
d.ellipse([cx - R + 34, cy - R + 34, cx + R - 34, cy + R - 34], outline=(30, 120, 130, 255), width=10)
# minute ticks
import math
for i in range(12):
    a = math.radians(i * 30)
    r1, r2 = R - 78, R - 52
    x1, y1 = cx + r1 * math.sin(a), cy - r1 * math.cos(a)
    x2, y2 = cx + r2 * math.sin(a), cy - r2 * math.cos(a)
    d.line([(x1, y1), (x2, y2)], fill=(30, 120, 130, 255), width=14)
# hands: about 10:10 style, study time
for angle_deg, length, width in [(300, 150, 30), (55, 195, 24)]:
    a = math.radians(angle_deg)
    x, y = cx + length * math.sin(a), cy - length * math.cos(a)
    d.line([(cx, cy), (x, y)], fill=(20, 40, 50, 255), width=width)
d.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], fill=(230, 90, 60, 255))

def png_bytes(size):
    im = img.resize((size, size), Image.LANCZOS)
    im = im.quantize(colors=128, method=Image.FASTOCTREE, dither=Image.NONE)
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()

# icns entry types by pixel size
entries = [
    (16, b"ic04"), (32, b"ic05"), (64, b"ic06"), (128, b"ic07"),
    (256, b"ic08"), (512, b"ic09"), (1024, b"ic10"),
]
body = b""
for size, typ in entries:
    data = png_bytes(size)
    body += typ + struct.pack(">I", len(data) + 8) + data

icns = b"icns" + struct.pack(">I", len(body) + 8) + body
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.icns"
open(out, "wb").write(icns)
# also save a preview png
img.resize((512, 512), Image.LANCZOS).save("icon_preview.png")
print(f"wrote {out}: {len(icns)} bytes")
