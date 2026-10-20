"""Reads the app's real food and exercise data so the website's numbers always match the app.

Sources (all under kynetix_ui/):
  lib/data/indian_curry_table.dart    cooked dishes per 100 g, with roti / rice portion rules
  lib/data/kyno_food_catalog.dart     everyday foods per stated serving
  lib/data/micronutrient_library.dart minerals per serving (scaled by calories, as the app does)
  lib/data/form_cues.dart             one form cue per lift
  assets/data/exercises_library.json  exercise library
"""
import json, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "kynetix_ui"

# ── Portion rules (accompaniment_portion_resolver.dart, indian_curry_table.dart) ──
KATORI_G = 150.0
# CurryFamily.gramsPer(balanced): grams eaten per roti, per rice ladle (~100 g rice)
FAMILY_GRAMS = {
    "liquid": (50.0, 85.0), "rasam": (50.0, 110.0), "legume": (50.0, 70.0), "rich": (45.0, 60.0),
    "vegGravy": (50.0, 60.0), "dry": (45.0, 35.0), "raita": (30.0, 75.0),
}
FAMILY_LABEL = {
    "liquid": "dal or kadhi", "rasam": "rasam", "legume": "legume curry", "rich": "rich gravy",
    "vegGravy": "vegetable curry", "dry": "dry sabzi", "raita": "raita",
}


def slugify(s):
    s = s.lower().replace("&", " and ")
    s = re.sub(r"[()/%,.+']", " ", s)
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s


def nice(s):
    return s[:1].upper() + s[1:]


def _num(x):
    return float(x)


def parse_curry():
    src = (APP / "lib/data/indian_curry_table.dart").read_text(encoding="utf-8")
    out = []
    pat = re.compile(r"CurryDish\('([^']+)', CurryFamily\.(\w+), ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+),\s*aliases: \[(.*?)\]\)", re.S)
    for m in pat.finditer(src):
        name, fam, kcal, p, c, f, fib, al = m.groups()
        aliases = re.findall(r"'([^']+)'", al)
        out.append(dict(src="curry", name=name, family=fam, per100=dict(kcal=_num(kcal), protein=_num(p), carbs=_num(c), fat=_num(f), fiber=_num(fib)), aliases=aliases))
    return out


def parse_catalog():
    src = (APP / "lib/data/kyno_food_catalog.dart").read_text(encoding="utf-8")
    body = src[src.index("const List<CatalogFood> kynoFoodCatalog"):]
    out, section = [], ""
    for line in body.splitlines():
        sm = re.match(r"\s*// ── (.+?) ─", line)
        if sm:
            section = sm.group(1).strip()
            continue
        m = re.match(r"\s*CatalogFood\('([^']+)', '([^']+)', ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)(.*)\),\s*$", line)
        if not m:
            continue
        name, serving, kcal, p, c, f, rest = m.groups()
        fib = re.search(r"fiber: ([\d.]+)", rest)
        diet = re.search(r"diet: FoodDiet\.(\w+)", rest)
        out.append(dict(src="catalog", name=name, serving=serving, section=section,
                        per_serving=dict(kcal=_num(kcal), protein=_num(p), carbs=_num(c), fat=_num(f), fiber=_num(fib.group(1)) if fib else None),
                        diet=diet.group(1) if diet else "veg", vrat="_vrat" in rest, logAs=(re.search(r"logAs: '([^']+)'", rest) or [None, None])[1]))
    return out


def parse_micro():
    src = (APP / "lib/data/micronutrient_library.dart").read_text(encoding="utf-8")
    out = []
    pat = re.compile(r"MicroFood\(\[([^\]]*)\], '([^']+)', ([\d.]+), (.*?)\),\n")
    for m in pat.finditer(src):
        al, serving, kcal, rest = m.groups()
        vals = dict((k, float(v)) for k, v in re.findall(r"(\w+): ([\d.]+)", rest))
        out.append(dict(src="micro", aliases=re.findall(r"'([^']+)'", al), serving=serving, kcal=float(kcal), micros=vals))
    return out


def grams_of(serving):
    """Grams in a serving string, only when grams are stated ("200 g", "1 katori (150 g)")."""
    m = re.search(r"(\d+(?:\.\d+)?)\s*g\b(?! *besan)(?! *flour)(?! *atta)(?! *ragi)", serving)
    if m and "+" not in serving and "dry" not in serving:
        return float(m.group(1))
    return None


def strip_paren(n):
    return re.sub(r"\s*\([^)]*\)", "", n).strip()


# Catalog foods that are the same dish as a curry-table dish (page merges them).
CATALOG_TO_CURRY = {
    "chicken curry (home)": "chicken curry", "fish curry (home)": "fish curry", "moong dal (home)": "moong dal",
    "chana dal (home)": "chana dal", "rajma (home)": "rajma", "chole (home)": "chole", "palak paneer": "palak paneer",
    "egg curry": "egg curry", "paneer bhurji": "paneer bhurji", "soya chunk curry": "soya curry", "mixed veg sabzi": "mix veg",
}
# Micronutrient entries attached to a page: micro first alias -> page key.
MICRO_TO_PAGE = {
    "roti": "roti", "ragi roti": "ragi roti", "rice": "rice", "brown rice": "brown rice", "poha": "poha", "upma": "upma",
    "sambar": "sambar", "khichdi": "khichdi", "pulao": "veg pulao", "biryani": "chicken biryani", "multigrain bread": "multigrain bread",
    "dal": "dal", "moong dal": "moong dal", "masoor dal": "masoor dal", "chana dal": "chana dal", "dal makhani": "dal makhani",
    "rajma": "rajma", "chole": "chole", "sprouts": "sprouts chaat", "soya chunks": "soya chunks", "soya chunk curry": "soya curry",
    "tofu": "tofu", "besan cheela": "besan cheela", "moong dal cheela": "moong dal cheela", "roasted chana": "roasted chana",
    "peanuts": "peanuts", "peanut butter": "peanut butter", "edamame": "edamame", "milk": "toned milk", "curd": "curd",
    "greek yogurt": "greek yogurt", "hung curd": "hung curd", "chaas": "chaas", "paneer": "paneer", "paneer bhurji": "paneer bhurji",
    "palak paneer": "palak paneer", "paneer butter masala": "paneer butter masala", "paneer tikka": "paneer tikka",
    "whey": "whey protein in water", "egg white": "egg whites", "omelette": "masala omelette", "egg curry": "egg curry",
    "chicken": "grilled chicken breast", "chicken curry": "chicken curry", "chicken tikka": "chicken tikka", "chicken keema": "chicken keema",
    "mutton": "mutton curry", "fish": "grilled fish", "fish curry": "fish curry", "tuna": "canned tuna in water", "prawns": "prawns masala",
    "palak": "saag", "sabzi": "mix veg", "aloo": "aloo matar", "bhindi": "bhindi", "salad": "kachumber salad", "sweet potato": "sweet potato",
    "banana": "banana", "apple": "apple", "papaya": "papaya", "guava": "guava", "dates": "dates", "fruit": "fruit bowl", "almonds": "almonds",
    "walnuts": "walnuts", "pumpkin seeds": "pumpkin seeds", "makhana": "makhana", "dark chocolate": "dark chocolate",
    "sabudana khichdi": "sabudana khichdi", "kuttu roti": "kuttu roti", "singhare atta roti": "singhare atta roti", "samak rice": "samak rice",
    "egg": "boiled eggs",
}
# Micro-only foods that get their own page (calories and minerals only).
MICRO_ONLY = {"paratha", "idli", "dosa", "oats", "bread", "veg biryani", "maggi", "lassi", "cheese", "chai", "ghee", "salmon", "orange", "mango", "samosa", "pizza"}
MICRO_LABEL = {"bread": "white bread", "chai": "chai (tea with milk)", "ghee": "ghee", "maggi": "Maggi (instant noodles)", "oats": "oats", "cheese": "cheese slice", "dosa": "plain dosa"}


def page_key_for_catalog(c):
    if c["name"] in CATALOG_TO_CURRY:
        return CATALOG_TO_CURRY[c["name"]]
    return strip_paren(c["name"]).lower()


def foods():
    curry, cat, micro = parse_curry(), parse_catalog(), parse_micro()
    pages = {}
    for d in curry:
        pages[d["name"]] = dict(key=d["name"], name=d["name"], curry=d, catalog=None, micro=None, aliases=list(d["aliases"]))
    for c in cat:
        k = page_key_for_catalog(c)
        if k in pages:
            pages[k]["catalog"] = c
        else:
            pages[k] = dict(key=k, name=strip_paren(c["name"]) if c["name"] not in ("curd (dahi)", "chaas (buttermilk)", "samak rice (vrat ke chawal)") else c["name"],
                            curry=None, catalog=c, micro=None, aliases=[])
    for m in micro:
        first = m["aliases"][0]
        if first in MICRO_TO_PAGE and MICRO_TO_PAGE[first] in pages:
            pg = pages[MICRO_TO_PAGE[first]]
            pg["micro"] = m
            pg["micro_aliases"] = m["aliases"]
        elif first in MICRO_ONLY:
            nm = MICRO_LABEL.get(first, first)
            pages[first] = dict(key=first, name=nm, curry=None, catalog=None, micro=m, aliases=[a for a in m["aliases"] if a != first])
    pages.pop("cottage cheese", None)
    taken = set()
    for pg in pages.values():
        taken.add(pg["name"]); taken.update(pg["aliases"])
    for pg in pages.values():
        for a in pg.pop("micro_aliases", []):
            if a not in taken and a not in pg["aliases"]:
                pg["aliases"].append(a); taken.add(a)
    for pg in pages.values():
        pg["slug"] = slugify(pg["name"])
        pg["display"] = nice(pg["name"])
    slugs = [p["slug"] for p in pages.values()]
    assert len(slugs) == len(set(slugs)), [s for s in slugs if slugs.count(s) > 1]
    return pages


# ── Exercises ────────────────────────────────────────────────────────────────

def form_cues():
    src = (APP / "lib/data/form_cues.dart").read_text(encoding="utf-8")
    out = []
    for m in re.finditer(r"\(\[(.*?)\], (\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')\),", src):
        keys = re.findall(r"'([^']+)'", m.group(1))
        cue = m.group(2)[1:-1].replace("\\'", "'")
        out.append((keys, cue))
    return out


def cue_for(name, cues):
    n = name.lower()
    for keys, cue in cues:
        if re.search("|".join(r"\b" + re.escape(k) for k in keys), n):
            return cue or None
    return None


def exercises():
    return json.loads((APP / "assets/data/exercises_library.json").read_text(encoding="utf-8"))


if __name__ == "__main__":
    fp = foods()
    print(len(fp), "food pages")
    for k, p in sorted(fp.items()):
        print(f"{p['slug']:32} curry={'Y' if p['curry'] else '-'} cat={'Y' if p['catalog'] else '-'} micro={'Y' if p['micro'] else '-'}")
    cues = form_cues()
    print(len(cues), "cues")
