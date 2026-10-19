"""Pad the real home-screen widget crops (docs/widgets, black wallpaper) into
tiles for the store deck. The editor rounds and frames them (radius, hairline,
soft shadow), so the padding keeps rings clear of the rounded corners."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT.parent.parent / "docs" / "widgets"
PAD = 40
for name in ["widget-2x2-rings", "widget-4x2-wide", "widget-2x4-tall", "widget-4x4-day"]:
    im = Image.open(SRC / f"{name}.png").convert("RGB")
    tile = Image.new("RGB", (im.width + 2 * PAD, im.height + 2 * PAD), (0, 0, 0))
    tile.paste(im, (PAD, PAD))
    tile.save(ROOT / "public" / "widgets" / f"{name}.png")
    print(name, tile.size)
