"""Build public/brand/skyline-panorama.png from the real Skyline share card.

Crops the bar chart out of card-skyline-graphite.png, keys out the graphite
background, dims the bone bars to a quiet graphite grey (ember bars stay ember)
and stretches it wide so one skyline can run across two store screenshots.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
src = Image.open(ROOT / "public/cards/card-skyline-graphite.png").convert("RGB")
crop = src.crop((75, 840, 1005, 1381))  # bars only, above the baseline and labels
BG = (11, 11, 12)
GREY = (52, 51, 48)
EMBER = (255, 106, 61)
out = Image.new("RGBA", crop.size, (0, 0, 0, 0))
px, po = crop.load(), out.load()
for y in range(crop.height):
    for x in range(crop.width):
        r, g, b = px[x, y]
        d = max(abs(r - BG[0]), abs(g - BG[1]), abs(b - BG[2]))
        if d < 14:
            continue
        a = min(255, int(d * 255 / 120))
        if r > 150 and g < 150 and r - b > 90:
            po[x, y] = (*EMBER, a)
        else:
            po[x, y] = (*GREY, a)
out = out.resize((2020, 660), Image.LANCZOS)
out.save(ROOT / "public/brand/skyline-panorama.png")
print("wrote", out.size)
