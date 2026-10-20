"""Food hub: /foods/ and one page per food, numbers straight from the app's food tables."""
import re
import data
from page import render, register, crumbs_html, faq_html, faq_ld, breadcrumb_ld, url, e, BASE, HREFLANG

FOODS = data.foods()
CATALOG = {c["name"]: c for c in data.parse_catalog()}
ROTI = CATALOG["roti (plain)"]["per_serving"]

GROUPS = [
    ("dals", "Dals, kadhi and sambar"), ("legumes", "Rajma, chole and other legumes"), ("paneer", "Paneer dishes"),
    ("meat", "Egg, chicken, fish and soya curries"), ("veg", "Vegetable curries and sabzi"), ("grains", "Roti, rice and breakfasts"),
    ("protein", "High-protein foods"), ("dairy", "Milk, curd and dairy"), ("fruit", "Fruit, nuts and snacks"), ("vrat", "Vrat (fasting) foods"),
    ("other", "Other everyday foods"),
]
SECTION_GROUP = {"Dairy & paneer": "dairy", "Eggs": "protein", "Meat & fish": "protein", "Soy, tofu, legumes": "protein",
                 "Supplements & packaged protein": "protein", "Grains & breakfasts": "grains", "Vegetables & salads": "veg",
                 "Fruit & light snacks": "fruit", "Millets (calcium and iron for vegetarians)": "grains", "Vrat (fasting) foods": "vrat"}
FAMILY_GROUP = {"liquid": "dals", "rasam": "dals", "legume": "legumes", "vegGravy": "veg", "dry": "veg", "raita": "dairy"}
MICRO_GROUP = {"paratha": "grains", "idli": "grains", "dosa": "grains", "oats": "grains", "bread": "grains", "veg biryani": "grains",
               "maggi": "other", "lassi": "dairy", "cheese": "dairy", "chai": "other", "ghee": "other", "salmon": "protein",
               "orange": "fruit", "mango": "fruit", "samosa": "other", "pizza": "other"}


def group_of(pg):
    if pg["curry"]:
        fam = pg["curry"]["family"]
        if fam == "rich":
            return "paneer" if "paneer" in pg["name"] or pg["name"] == "malai kofta" else "meat"
        return FAMILY_GROUP[fam]
    if pg["catalog"]:
        return SECTION_GROUP.get(pg["catalog"]["section"], "other")
    return MICRO_GROUP.get(pg["key"], "other")


def fmt(x, dec=1):
    if x is None:
        return None
    v = round(x, dec)
    return str(int(v)) if v == int(v) else f"{v:.{dec}f}"


def kc(x):
    return str(int(round(x)))


def scale(per, f):
    return {k: (None if v is None else v * f) for k, v in per.items()}


def serving_short(s):
    return re.sub(r"\s*\([^)]*\)", "", s).strip()


def rows_for(pg):
    """[(label, nutrients dict, note)] with the main serving first."""
    rows = []
    if pg["curry"]:
        c = pg["curry"]
        per100 = c["per100"]
        rg, lg = data.FAMILY_GRAMS[c["family"]]
        rows.append(("1 katori (150 g)", scale(per100, 1.5), "main"))
        rows.append(("100 g", per100, "per100"))
        rows.append((f"With 1 roti ({int(rg)} g)", scale(per100, rg / 100), "roti"))
        rows.append((f"With 1 ladle of rice ({int(lg)} g)", scale(per100, lg / 100), "rice"))
        if pg["catalog"]:
            cat = pg["catalog"]
            rows.append((f"As Kyno suggests it: {cat['serving']}", cat["per_serving"], "kyno"))
    elif pg["catalog"]:
        cat = pg["catalog"]
        rows.append((cat["serving"], cat["per_serving"], "main"))
        g = data.grams_of(cat["serving"])
        if g:
            rows.append(("100 g", scale(cat["per_serving"], 100 / g), "per100"))
    else:
        m = pg["micro"]
        rows.append((m["serving"], dict(kcal=m["kcal"], protein=None, carbs=None, fat=None, fiber=None), "main"))
    return rows


def main_row(pg):
    return rows_for(pg)[0]


def per100(pg):
    for lab, n, kind in rows_for(pg):
        if kind == "per100":
            return n
    return None


def micros_for(pg, kcal_basis):
    m = pg["micro"]
    if not m or not m["kcal"]:
        return None
    f = kcal_basis / m["kcal"]
    mm = m["micros"]
    out = [("Iron", mm.get("fe", 0) * f, "mg"), ("Calcium", mm.get("ca", 0) * f, "mg"), ("Magnesium", mm.get("mg", 0) * f, "mg"),
           ("Zinc", mm.get("zn", 0) * f, "mg"), ("Potassium", mm.get("k", 0) * f, "mg"), ("Sodium", mm.get("na", 0) * f, "mg")]
    if mm.get("b12"):
        out.append(("Vitamin B12", mm["b12"] * f, "µg"))
    if mm.get("d"):
        out.append(("Vitamin D", mm["d"] * f, "µg"))
    return out


def log_text(pg):
    if pg["curry"]:
        return f"2 roti and {pg['name']}", f"1 katori {pg['name']}"
    if pg["catalog"]:
        c = pg["catalog"]
        lt = c["logAs"] or re.sub(r"[()]", "", f"{c['serving']} {c['name']}")
        return lt, None
    return f"{serving_short(pg['micro']['serving'])} {pg['name']}", None


def protein_share(n):
    if not n.get("kcal") or n.get("protein") is None:
        return None
    return round(n["protein"] * 4 / n["kcal"] * 100)


def summary(pg):
    lab, n, _ = main_row(pg)
    name = pg["name"]
    p100 = per100(pg)
    if pg["curry"]:
        s = (f"One katori (150 g) of {name} has about {kc(n['kcal'])} kcal and {fmt(n['protein'])} g of protein, by Kynetix's food table. "
             f"Per 100 g that is {kc(p100['kcal'])} kcal, {fmt(p100['protein'])} g protein, {fmt(p100['carbs'])} g carbs, {fmt(p100['fat'])} g fat and {fmt(p100['fiber'])} g fiber.")
    elif pg["catalog"]:
        s = (f"{lab[:1].upper() + lab[1:]} of {name} has about {kc(n['kcal'])} kcal and {fmt(n['protein'])} g of protein, "
             f"with {fmt(n['carbs'])} g carbs and {fmt(n['fat'])} g fat, by Kynetix's food table.")
        if p100:
            s += f" That works out to {kc(p100['kcal'])} kcal and {fmt(p100['protein'])} g protein per 100 g."
    else:
        s = (f"{lab[:1].upper() + lab[1:]} of {name} has about {kc(n['kcal'])} kcal in Kynetix's food table. "
             f"When you log it, Kyno works out the protein, carbs and fat for your exact portion.")
    return s


def nut_table(pg):
    rows = rows_for(pg)
    has_macros = rows[0][1].get("protein") is not None
    head = "<tr><th scope=\"col\">Serving</th><th scope=\"col\">Calories</th>" + (
        "<th scope=\"col\">Protein</th><th scope=\"col\">Carbs</th><th scope=\"col\">Fat</th><th scope=\"col\">Fiber</th>" if has_macros else "") + "</tr>"
    body = []
    fiber_given = bool(pg["curry"]) or (pg["catalog"] and pg["catalog"]["per_serving"]["fiber"] is not None)
    for lab, n, kind in rows:
        cells = f"<th scope=\"row\">{e(lab)}</th><td>{kc(n['kcal'])} kcal</td>"
        if has_macros:
            fib = n.get("fiber")
            fib_s = f"{fmt(fib)} g" if (fib is not None and (fiber_given or kind == 'kyno')) else "not listed"
            cells += f"<td>{fmt(n['protein'])} g</td><td>{fmt(n['carbs'])} g</td><td>{fmt(n['fat'])} g</td><td>{fib_s}</td>"
        body.append(f"<tr>{cells}</tr>")
    return f'<div class="table-scroll"><table class="nut"><caption class="sr-only">Nutrition for {e(pg["name"])}</caption><thead>{head}</thead><tbody>{"".join(body)}</tbody></table></div>'


def faqs(pg):
    lab, n, _ = main_row(pg)
    name = pg["name"]
    p100 = per100(pg)
    qas = []
    if pg["curry"]:
        qas.append((f"How many calories are in 1 katori of {name}?", summary(pg).split(" Per 100 g")[0] + f" A katori in Kynetix is 150 g."))
    else:
        qas.append((f"How many calories are in {lab} of {name}?", f"About {kc(n['kcal'])} kcal, by Kynetix's food table."))
    if n.get("protein") is not None:
        share = protein_share(n)
        a = f"About {fmt(n['protein'])} g of protein in {lab}"
        if p100:
            a += f", or {fmt(p100['protein'])} g per 100 g"
        a += f". Roughly {share}% of its calories come from protein."
        qas.append((f"How much protein is in {name}?", a))
    if pg["curry"]:
        rg, _ = data.FAMILY_GRAMS[pg["curry"]["family"]]
        cur = scale(pg["curry"]["per100"], 2 * rg / 100)
        tot_k = 2 * ROTI["kcal"] + cur["kcal"]
        tot_p = 2 * ROTI["protein"] + cur["protein"]
        qas.append((f"How many calories in 2 roti with {name}?",
                    f"About {kc(tot_k)} kcal and {fmt(tot_p)} g protein: two plain roti ({kc(ROTI['kcal'])} kcal each) plus about {int(2 * rg)} g of {name}, "
                    f"which is how much a typical eater has with two roti in Kynetix."))
        qas.append((f"1 katori {name} mein kitni calories hoti hain?",
                    f"Lagbhag {kc(n['kcal'])} kcal aur {fmt(n['protein'])} g protein, Kynetix ki food table ke hisaab se."))
    else:
        qas.append((f"{name[:1].upper() + name[1:]} mein kitni calories hoti hain?",
                    f"{lab} mein lagbhag {kc(n['kcal'])} kcal" + (f" aur {fmt(n['protein'])} g protein" if n.get('protein') is not None else "") + ", Kynetix ki food table ke hisaab se."))
    return qas


def related(pg, n=6):
    g = group_of(pg)
    same = [p for p in FOODS.values() if p is not pg and group_of(p) == g]
    same.sort(key=lambda p: p["name"])
    if len(same) < n:
        same += [p for p in FOODS.values() if p is not pg and p not in same][: n - len(same)]
    # rotate so neighbours differ per page
    if same:
        i = sorted(FOODS).index(pg["key"]) % len(same)
        same = same[i:] + same[:i]
    return same[:n]


def title_for(pg):
    d = pg["display"]
    if pg["curry"]:
        return f"{d} Calories and Protein per Katori | Kynetix"
    lab, n, _ = main_row(pg)
    if pg["catalog"]:
        return f"{d} Calories and Protein per {serving_short(lab)} | Kynetix"
    return f"{d} Calories per {serving_short(lab)} | Kynetix"


def desc_for(pg):
    lab, n, _ = main_row(pg)
    if n.get("protein") is not None:
        d = f"{pg['display']}: about {kc(n['kcal'])} kcal and {fmt(n['protein'])} g protein per {lab}. Carbs, fat, fiber, Indian portions and how to log it in Kynetix."
    else:
        d = f"{pg['display']}: about {kc(n['kcal'])} kcal per {lab}, with iron, calcium and other minerals, from Kynetix's food table, and how to log it."
    if len(d) > 160:
        d = d[:157].rsplit(" ", 1)[0] + "..."
    return d


def page_path(pg):
    return f"foods/{pg['slug']}/"


def plan(localized_slugs):
    register("foods/", "en", "foods-index", "foods")
    for pg in FOODS.values():
        p = page_path(pg)
        register(p, "en", "food:" + pg["slug"] if pg["slug"] in localized_slugs else None, "foods")


def build_pages():
    for pg in FOODS.values():
        path = page_path(pg)
        lab, n, _ = main_row(pg)
        trail = [("Kynetix", ""), ("Foods", "foods/"), (pg["display"], path)]
        parts = [crumbs_html(trail, "en"), '<article class="c-art">',
                 f'<header class="c-head"><p class="kicker">Food</p><h1 class="c-h1">{e(pg["display"])} calories and protein</h1>'
                 f'<p class="answer">{e(summary(pg))}</p></header>',
                 '<section class="c-sec" aria-labelledby="nut-t"><h2 id="nut-t">Nutrition by portion</h2>', nut_table(pg)]
        if pg["curry"]:
            c = pg["curry"]
            rg, lg = data.FAMILY_GRAMS[c["family"]]
            parts.append(f'<p>Kynetix sizes a {data.FAMILY_LABEL[c["family"]]} by what you eat it with: about {int(rg)} g with each roti and {int(lg)} g with each ladle of rice for a typical eater, '
                         f'or a full katori (150 g) when you eat it on its own. Tell Kynetix you eat curry first or carb first and these portions adjust.</p>')
        share = protein_share(n)
        if share is not None:
            parts.append(f'<p>About {share}% of the calories in {e(pg["name"])} come from protein.</p>')
        parts.append('</section>')
        mi = micros_for(pg, n["kcal"])
        if mi:
            rows = "".join(f'<tr><th scope="row">{e(k)}</th><td>{fmt(v) if v >= 1 else fmt(v, 2)} {u}</td></tr>' for k, v, u in mi)
            parts.append(f'<section class="c-sec" aria-labelledby="min-t"><h2 id="min-t">Minerals in {e(lab)}</h2>'
                         f'<div class="table-scroll"><table class="nut nut-s"><tbody>{rows}</tbody></table></div>'
                         f'<p class="small">From Kynetix\'s micronutrient table (IFCT 2017 and USDA FoodData Central), scaled to this serving\'s calories the way the app does.</p></section>')
        l1, l2 = log_text(pg)
        how = f'Type <q>{e(l1)}</q>' + (f' or <q>{e(l2)}</q>' if l2 else "") + ' in Kynetix, in plain words. It matches the food, sizes the portion and adds it to your day. Fix a number once and it remembers how you eat it.'
        parts.append(f'<section class="c-sec" aria-labelledby="log-t"><h2 id="log-t">How to log it in Kynetix</h2><p>{how}</p></section>')
        if pg["aliases"]:
            al = ", ".join(e(a) for a in pg["aliases"][:10])
            parts.append(f'<p class="small">Also searched as: {al}.</p>')
        qas = faqs(pg)
        parts.append(faq_html(qas))
        rel = "".join(f'<li><a href="{BASE}{page_path(r)}">{e(r["display"])}</a></li>' for r in related(pg))
        parts.append(f'<section class="c-sec" aria-labelledby="rel-t"><h2 id="rel-t">Related foods</h2><ul class="chips">{rel}</ul>'
                     f'<p><a class="link-arrow" href="{BASE}foods/"><span>All foods</span></a><a class="link-arrow" href="{BASE}guides/how-to-count-calories-in-indian-food/"><span>How to count calories in Indian food</span></a></p></section>')
        parts.append('<p class="note">Values are estimates from Kynetix\'s food table, worked from IFCT 2017 and USDA FoodData Central for typical home recipes. Oil, ghee and portion size change the real number.</p>')
        parts.append('</article>')
        ld = [breadcrumb_ld(path, trail), faq_ld(path, qas, "en"),
              {"@type": "WebPage", "@id": url(path) + "#webpage", "url": url(path), "name": title_for(pg), "inLanguage": "en-IN",
               "isPartOf": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#website"}, "breadcrumb": {"@id": url(path) + "#breadcrumb"},
               "about": {"@type": "Thing", "name": pg["display"]}, "dateModified": "2026-10-20"}]
        render(path, "en", title_for(pg), desc_for(pg), "\n".join(parts), ld, og="og-foods.png", og_alt="Kynetix food calories and protein", active="foods")


def build_index():
    path = "foods/"
    trail = [("Kynetix", ""), ("Foods", path)]
    groups = {}
    for pg in FOODS.values():
        groups.setdefault(group_of(pg), []).append(pg)
    secs = []
    for gk, gl in GROUPS:
        items = sorted(groups.get(gk, []), key=lambda p: p["name"])
        if not items:
            continue
        lis = []
        for pg in items:
            lab, n, _ = main_row(pg)
            meta = f"{kc(n['kcal'])} kcal" + (f", {fmt(n['protein'])} g protein" if n.get("protein") is not None else "") + f" per {lab}"
            lis.append(f'<li><a href="{BASE}{page_path(pg)}"><b>{e(pg["display"])}</b><span>{e(meta)}</span></a></li>')
        secs.append(f'<section class="c-sec" aria-labelledby="g-{gk}"><h2 id="g-{gk}">{e(gl)}</h2><ul class="food-list">{"".join(lis)}</ul></section>')
    qas = [("Where do these numbers come from?", "From the same food tables the Kynetix app uses: cooked Indian dishes per 100 g worked from IFCT 2017 and USDA FoodData Central for typical home recipes, plus everyday foods per serving. They are estimates, and your oil, ghee and portions change the real number."),
           ("How big is a katori in Kynetix?", "150 g. With roti or rice, Kynetix sizes the curry by how much you eat with each roti or ladle of rice instead."),
           ("Roti calories kitni hoti hain?", f"Ek plain roti mein lagbhag {kc(ROTI['kcal'])} kcal aur {fmt(ROTI['protein'])} g protein hota hai, Kynetix ki food table ke hisaab se.")]
    body = (crumbs_html(trail, "en") + f'<header class="c-head"><p class="kicker">Foods</p><h1 class="c-h1">Calories and protein in Indian food</h1>'
            f'<p class="answer">Calories, protein, carbs, fat and fiber for {len(FOODS)} Indian foods, per katori, roti, plate or 100 g, straight from the food table inside the Kynetix app. '
            f'Pick a food, or type your whole meal into Kynetix in plain words.</p></header>' + "".join(secs) + faq_html(qas) +
            '<p class="note">All values are estimates for typical home recipes. Kynetix lets you correct any number, and remembers your version.</p>')
    ld = [breadcrumb_ld(path, trail), faq_ld(path, qas, "en"),
          {"@type": "CollectionPage", "@id": url(path) + "#webpage", "url": url(path), "name": "Calories and protein in Indian food", "inLanguage": "en-IN",
           "isPartOf": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#website"}, "breadcrumb": {"@id": url(path) + "#breadcrumb"}}]
    render(path, "en", "Indian Food Calories and Protein Chart (per Katori) | Kynetix",
           f"Calories, protein, carbs, fat and fiber in {len(FOODS)} Indian foods, per katori, roti, plate or 100 g: dal, roti, rice, paneer, chole, rajma, eggs and more.",
           body, ld, og="og-foods.png", og_alt="Kynetix food calories and protein", active="foods")
