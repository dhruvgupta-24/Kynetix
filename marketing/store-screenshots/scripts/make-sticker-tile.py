"""Build public/cards/card-sticker-on-tile.png: the transparent Sticker share card
laid on a dark, grainy photo-like tile so it reads inside the share-card fan."""
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
W, H = 1080, 1920
tile = Image.new("RGB", (W, H))
d = ImageDraw.Draw(tile)
for y in range(H):  # flat-ish falloff, darker toward the bottom like a dim gym shot
    v = int(30 - 14 * y / H)
    d.line([(0, y), (W, y)], fill=(v, v - 1, v - 2))
# soft out-of-focus shapes suggest a photo without showing anything specific
shapes = Image.new("L", (W, H), 0)
sd = ImageDraw.Draw(shapes)
random.seed(7)
for _ in range(9):
    x, y, r = random.randint(0, W), random.randint(0, H), random.randint(120, 320)
    sd.ellipse([x - r, y - r, x + r, y + r], fill=random.randint(10, 22))
shapes = shapes.filter(ImageFilter.GaussianBlur(90))
tile = Image.composite(Image.new("RGB", (W, H), (70, 68, 64)), tile, shapes)
noise = Image.effect_noise((W, H), 28).convert("L")
tile = Image.blend(tile, Image.merge("RGB", (noise, noise, noise)), 0.06)
sticker = Image.open(ROOT / "public/cards/card-sticker-graphite.png").convert("RGBA")
tile = tile.convert("RGBA")
tile.alpha_composite(sticker)
tile.convert("RGB").save(ROOT / "public/cards/card-sticker-on-tile.png")
print("ok")
