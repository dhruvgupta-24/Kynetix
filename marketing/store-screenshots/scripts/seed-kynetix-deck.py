"""Seed app-store-screenshots.json with the Kynetix Google Play deck.

Run from marketing/store-screenshots:  python scripts/seed-kynetix-deck.py
Canvas: Android phone 1080x1920 per screen, connected canvas (8 screens).
Headline markup: [word] = ember, {word} = shear (see rich-text.tsx).
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "app-store-screenshots.json"
SHOT = "/screenshots/android/phone/en/"
CARD = "/cards/"
BONE_LINE = "rgba(242,241,236,0.16)"


def t(x, y, w, h, rot=0, z=None):
    out = {"x": x, "y": y, "width": w, "height": h, "rotation": rot}
    if z is not None:
        out["zIndex"] = z
    return out


def phone(x, y, w, rot=0, z=3):
    return t(x, y, w, round(w * 19.5 / 9), rot, z)


def card(id_, src, x, y, w, rot, z, border=True, radius=22, shadow=70):
    el = {"id": id_, "src": CARD + src, "fit": "contain", "transform": t(x, y, w, round(w * 16 / 9), rot, z),
          "shadow": shadow}
    if border:
        el["border"] = BONE_LINE
        el["radius"] = radius
    return el


def txt(id_, text, x, y, w, h, size, weight=800, color=None, align="left", z=6):
    el = {"id": id_, "text": {"en": text}, "transform": t(x, y, w, h, 0, z), "fontSize": size,
          "fontWeight": weight, "align": align}
    if color:
        el["color"] = color
    return el


def slide(id_, layout, label, headline, shot="", **kw):
    s = {"id": id_, "layout": layout, "label": {"en": label}, "headline": {"en": headline}, "screenshot": shot}
    s.update(kw)
    return s


def widget(id_, name, x, y, w, h):
    return {"id": id_, "src": f"/widgets/{name}.png", "fit": "cover", "transform": t(x, y, w, h, 0, 5),
            "radius": 44, "border": BONE_LINE, "shadow": 55}


WM = {"id": "wordmark", "src": "/brand/kynetix-wordmark.svg", "fit": "contain"}

android = [
    # 01 HERO: the promise, dashboard rings.
    slide("k01-hero", "hero", "", "REAL FOOD.\nREAL {LIFTS.}", SHOT + "home.png",
          typography={"headlineScale": 1.3},
          transforms={"caption": t(40, 250, 1000, 300, 0, 4), "device": phone(175, 600, 730)},
          imageElements=[{**WM, "transform": t(400, 120, 280, 52, 0, 6)}]),
    # 02 MEAL: type it in your own words, loupe on the input.
    slide("k02-meal", "device-bottom", "DAL, ROTI, KATORI. SORTED.", "TYPE IT LIKE\nYOU [SAY] IT.", SHOT + "meal.png",
          typography={"headlineScale": 1.12},
          callout={"focusX": 0.475, "focusY": 0.206, "zoom": 1.5, "shape": "rounded"},
          transforms={"caption": t(40, 150, 1000, 360, 0, 4), "device": phone(215, 560, 650),
                      "callout": t(50, 740, 780, 220, -3, 5)}),
    # 03 KYNO: the differentiator, on bone for contrast.
    slide("k03-kyno", "two-devices", "MEET KYNO", "A COACH THAT\nREADS [BOTH].", SHOT + "kyno_answer.png",
          screenshotSecondary=SHOT + "kyno_empty.png", inverted=True,
          typography={"headlineScale": 1.12},
          transforms={"caption": t(40, 150, 1000, 360, 0, 4),
                      "deviceSecondary": phone(80, 700, 560, -7, 2),
                      "device": phone(380, 590, 640, 4, 3)},
          textElements=[txt("sub", "Meals and lifts, read together.", 140, 430, 800, 70, 40, 500, "#55544F", "center")]),
    # 04 WORKOUT: device on top, tilted, caption below.
    slide("k04-sets", "device-top", "TRAINING", "EVERY SET.\n[ONE] TAP.", SHOT + "workout.png",
          typography={"headlineScale": 1.3},
          transforms={"device": phone(185, -150, 710, -5, 3), "caption": t(40, 1440, 1000, 400, 0, 4)}),
    # 05 + 06: share cards fanned across the seam (the connected moment).
    slide("k05-cards", "no-device", "SHARE CARDS", "MADE TO BE\n[POSTED].",
          typography={"headlineScale": 1.3},
          transforms={"caption": t(40, 150, 1000, 360, 0, 4)},
          imageElements=[
              card("eq", "card-equivalent-graphite.png", 72, 690, 370, -11, 4),
              card("sticker", "card-sticker-on-tile.png", 225, 630, 370, -5, 5),
              card("poster", "card-poster-paper.png", 430, 600, 370, 2, 6),
              card("receipt", "card-receipt-graphite.png", 650, 650, 370, 9, 7),
              # Connected moment: the Skyline card's own bars, stretched into one
              # skyline that runs across screens 5 and 6. The seam splits an ember
              # bar, like the shear cut in the wordmark. No text crosses.
              {"id": "skyline", "src": "/brand/skyline-panorama.png", "fit": "cover",
               "transform": t(128, 1190, 2020, 660, 0, 1)},
              {"id": "baseline", "src": "/brand/ember-line.svg", "fit": "cover",
               "transform": t(-20, 1846, 2120, 8, 0, 2)},
          ]),
    slide("k06-story", "device-bottom", "STORIES READY", "STRAIGHT TO\nYOUR {STORY}.", SHOT + "share_skyline.png",
          typography={"headlineScale": 1.2},
          transforms={"caption": t(40, 150, 1000, 360, 0, 4), "device": phone(425, 610, 590, 5, 3)}),
    # 07 PRS: bone contrast slide, workout done.
    slide("k07-prs", "hero", "SPLITS, PRS, STREAKS", "EVERY PR,\n[COUNTED].", SHOT + "done.png", inverted=True,
          typography={"headlineScale": 1.3},
          transforms={"caption": t(40, 150, 1000, 380, 0, 4), "device": phone(175, 600, 730)}),
    # 08 WIDGETS: real home-screen widget crops as a bento, plus the rest in one line.
    slide("k08-widgets", "no-device", "HOME SCREEN WIDGETS", "YOUR RINGS.\nNO APP [NEEDED].",
          typography={"headlineScale": 1.15},
          transforms={"caption": t(40, 150, 1000, 300, 0, 4)},
          imageElements=[
              widget("w-day", "widget-4x4-day", 60, 495, 614, 676),
              widget("w-wide", "widget-4x2-wide", 60, 1195, 614, 331),
              widget("w-rings", "widget-2x2-rings", 698, 495, 322, 329),
              widget("w-tall", "widget-2x4-tall", 698, 848, 322, 681),
          ],
          textElements=[
              txt("rest", "HEALTH CONNECT / BARCODE SCAN\nNO ADS / DELETE ANYTIME", 40, 1590, 1000, 170, 50, 800,
                  None, "center"),
              txt("rest-sub", "Steps, weight, sleep and HRV. Packaged food in one look.", 60, 1770, 960, 60, 32, 500,
                  "#8A8984", "center"),
          ]),
]

feature = [
    slide("k-fg", "feature-graphic", "{KYNETIX}", "Real food.\nReal [lifts].", inverted=False,
          typography={"appNameScale": 1.25, "headlineScale": 1.45},
          imageElements=[
              card("fg-eq", "card-equivalent-graphite.png", 600, 70, 210, -10, 5, radius=12, shadow=60),
              card("fg-poster", "card-poster-paper.png", 720, 40, 210, 0, 6, radius=12, shadow=60),
              card("fg-receipt", "card-receipt-graphite.png", 840, 80, 210, 9, 7, border=False, shadow=50),
          ]),
]

data = json.loads(PROJECT.read_text(encoding="utf8"))
data.pop("crossScreenMockupsByDevice", None)
data.update({
    "schemaVersion": 3,
    "appName": "Kynetix",
    "themeId": "kynetix-graphite",
    "fontId": "kynetix",
    "connectedCanvas": True,
    "locales": ["en"],
    "locale": "en",
    "device": "android",
    "orientation": "portrait",
    "appIcon": "/app-icon.png",
    "scene": {
        "backdrop": "solid", "span": False, "decoration": "none", "shadow": 55, "glow": 0, "tilt": 0,
        "headlineWeight": 800, "headlineScale": 1, "headlineCase": "upper", "captionAlign": "auto",
    },
})
data["slidesByDevice"] = {"android": android, "feature-graphic": feature}
PROJECT.write_text(json.dumps(data, indent=2) + "\n", encoding="utf8")
print("seeded", len(android), "android screens + feature graphic")
