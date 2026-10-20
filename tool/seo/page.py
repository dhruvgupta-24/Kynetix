"""Lean static page shell for the content hubs (foods, exercises, guides, tools, compare, languages)."""
import html, json, pathlib

HERE = pathlib.Path(__file__).resolve().parent
SITE = HERE.parents[1] / "site"
BASE = "/Kynetix/"
URL = "https://dhruvgupta-24.github.io/Kynetix/"
TODAY = "2026-10-20"
EMAIL = "kynetix.app@gmail.com"
REPO = "https://github.com/dhruvgupta-24/Kynetix"
KX = (HERE / "kx.svgfrag").read_text(encoding="utf-8")
e = html.escape

LANGS = ["en", "hi", "mr", "ta", "te", "bn", "gu", "kn", "ml", "pa"]
HREFLANG = {"en": "en-IN", "hi": "hi-IN", "mr": "mr-IN", "ta": "ta-IN", "te": "te-IN", "bn": "bn-IN", "gu": "gu-IN", "kn": "kn-IN", "ml": "ml-IN", "pa": "pa-IN"}
OG_LOCALE = {k: v.replace("-", "_") for k, v in HREFLANG.items()}
NATIVE = {"en": "English", "hi": "हिन्दी", "mr": "मराठी", "ta": "தமிழ்", "te": "తెలుగు", "bn": "বাংলা", "gu": "ગુજરાતી", "kn": "ಕನ್ನಡ", "ml": "മലയാളം", "pa": "ਪੰਜਾਬੀ"}

# Every page written this run: path -> dict(lang, alternates key, lastmod, section)
REGISTRY = {}
# Cluster key -> {lang: path}
CLUSTERS = {}


def url(path):
    return URL + path


def register(path, lang, cluster, section):
    REGISTRY[path] = dict(lang=lang, cluster=cluster, section=section)
    if cluster:
        CLUSTERS.setdefault(cluster, {})[lang] = path


WM = ('<svg class="bm" viewBox="-188.8 250 3797.8 700" role="img" aria-label="Kynetix">'
      '<path class="bm-cut" d="M-170,592.2 H634 A8.8,8.8 0 0 1 634,609.8 H-170 A8.8,8.8 0 0 1 -170,592.2 Z" fill="#FF6A3D"/>'
      '<use href="#kx" clip-path="url(#cb)"/><g clip-path="url(#ct)"><g class="bm-t"><use href="#kx" transform="translate(70 0)"/></g></g></svg>')
SPRITE = ('<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false"><defs>' + KX +
          '<clipPath id="ct"><path d="M-2000,-2000 H9000 V590 H-2000 Z"/></clipPath><clipPath id="cb"><path d="M-2000,612 H9000 V3000 H-2000 Z"/></clipPath></defs></svg>')

ORG_REF = {"@id": URL + "#org"}
ORG = {"@type": "Organization", "@id": URL + "#org", "name": "Kynetix", "url": URL,
       "logo": {"@type": "ImageObject", "url": URL + "assets/img/icon-512.png", "width": 512, "height": 512},
       "email": EMAIL, "founder": {"@id": URL + "#founder"}, "sameAs": [REPO]}
PERSON = {"@type": "Person", "@id": URL + "#founder", "name": "Dhruv Gupta", "jobTitle": "Founder and developer", "worksFor": ORG_REF}
WEBSITE = {"@type": "WebSite", "@id": URL + "#website", "url": URL, "name": "Kynetix", "inLanguage": "en-IN", "publisher": ORG_REF}

# UI strings for the shell, per language.
SHELL = {
    "en": dict(skip="Skip to content", foods="Foods", exercises="Exercises", guides="Guides", tools="Tools", compare="Compare", app="The app",
               home="Kynetix", about="About and press kit", privacy="Privacy policy", terms="Terms of use", langs="Read in",
               talk="Got thoughts? Talk to us inside the app (Profile &gt; Talk to us) or email", made="Real food. Real lifts. Made in India by Dhruv Gupta.",
               crumbs="Breadcrumb", learn="Learn", note_en=""),
}


def shell(lang):
    from i18n import SHELL_I18N
    s = dict(SHELL["en"])
    s.update(SHELL_I18N.get(lang, {}))
    return s


def prefix(lang):
    return BASE if lang == "en" else BASE + lang + "/"


def ld_script(nodes):
    data = {"@context": "https://schema.org", "@graph": nodes}
    return '<script type="application/ld+json">' + json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/") + "</script>"


def breadcrumb_ld(path, trail):
    """trail: list of (name, path) ending with the current page."""
    return {"@type": "BreadcrumbList", "@id": url(path) + "#breadcrumb", "itemListElement": [
        {"@type": "ListItem", "position": i + 1, "name": n, "item": url(p)} for i, (n, p) in enumerate(trail)]}


def faq_ld(path, qas, lang):
    return {"@type": "FAQPage", "@id": url(path) + "#faq", "inLanguage": HREFLANG[lang], "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in qas]}


def faq_html(qas, title="Questions", hid="faq"):
    items = "".join(f'<details class="qa"{" open" if i == 0 else ""}><summary><h3>{e(q)}</h3><i aria-hidden="true"></i></summary>'
                    f'<div class="qa-a"><p>{e(a)}</p></div></details>' for i, (q, a) in enumerate(qas))
    return f'<section class="c-sec" id="{hid}" aria-labelledby="{hid}-t"><h2 id="{hid}-t">{e(title)}</h2><div class="faq-list">{items}</div></section>'


def crumbs_html(trail, lang):
    s = shell(lang)
    lis = []
    for i, (n, p) in enumerate(trail):
        if i == len(trail) - 1:
            lis.append(f'<li aria-current="page">{e(n)}</li>')
        else:
            lis.append(f'<li><a href="{BASE}{p}">{e(n)}</a></li>')
    return f'<nav class="crumbs" aria-label="{e(s["crumbs"])}"><ol>{"".join(lis)}</ol></nav>'


def alternates_for(path):
    info = REGISTRY.get(path)
    if not info or not info["cluster"]:
        return {}
    return CLUSTERS.get(info["cluster"], {})


def header(lang, active=None):
    s = shell(lang)
    p = prefix(lang)
    # Hubs exist in English for everything; other languages link their own home and foods where present.
    if lang == "en":
        items = [("foods", BASE + "foods/"), ("exercises", BASE + "exercises/"), ("guides", BASE + "guides/"), ("tools", BASE + "tools/")]
    else:
        items = [("foods", p + "foods/"), ("tools", (p + "tools/") if lang == "hi" else BASE + "tools/"), ("exercises", BASE + "exercises/"), ("guides", BASE + "guides/")]
    links = "".join(f'<a href="{h}"{" aria-current=\"page\"" if k == active else ""}>{e(s[k])}</a>' for k, h in items)
    return (f'<a class="skip" href="#main">{e(s["skip"])}</a>\n<header class="chead"><div class="wrap chead-in">'
            f'<a class="brand" href="{p}" aria-label="Kynetix">{WM}</a>'
            f'<nav class="cnav" aria-label="{e(s["learn"])}">{links}<a class="cnav-app" href="{BASE}">{e(s["app"])}</a></nav></div></header>')


def lang_switch(path, lang):
    alts = alternates_for(path)
    if len(alts) < 2:
        return ""
    s = shell(lang)
    items = []
    for l in LANGS:
        if l in alts:
            cur = ' aria-current="true"' if l == lang else ""
            items.append(f'<li><a href="{BASE}{alts[l]}" hreflang="{HREFLANG[l]}" lang="{HREFLANG[l]}"{cur}>{NATIVE[l]}</a></li>')
    return f'<nav class="langs" aria-label="{e(s["langs"])}"><span>{e(s["langs"])}</span><ul>{"".join(items)}</ul></nav>'


def footer(lang, path):
    s = shell(lang)
    p = prefix(lang)
    hubs = [("foods", BASE + "foods/"), ("exercises", BASE + "exercises/"), ("guides", BASE + "guides/"), ("tools", BASE + "tools/"),
            ("compare", BASE + "compare/"), ("about", BASE + "about/"), ("privacy", BASE + "privacy/"), ("terms", BASE + "terms/")]
    if lang != "en":
        hubs[0] = ("foods", p + "foods/")
        if lang == "hi":
            hubs[3] = ("tools", p + "tools/")
    nav = "".join(f'<li><a href="{h}">{e(s[k])}</a></li>' for k, h in hubs)
    langs = "".join(f'<li><a href="{prefix(l)}" hreflang="{HREFLANG[l]}" lang="{HREFLANG[l]}">{NATIVE[l]}</a></li>' for l in LANGS)
    return (f'<footer class="foot"><div class="wrap">'
            f'<div class="foot-a"><a class="brand" href="{p}" aria-label="Kynetix">{WM}</a><p>{e(s["made"])} &copy; 2026</p></div>'
            f'<p class="talk">{s["talk"]} <a href="mailto:{EMAIL}">{EMAIL}</a></p>'
            f'<nav aria-label="{e(s["learn"])}"><ul>{nav}</ul></nav>'
            f'<nav class="foot-langs" aria-label="{e(s["langs"])}"><ul>{langs}</ul></nav>'
            f'</div></footer>')


def render(path, lang, title, desc, body, ld_nodes=(), og="og-home.png", og_alt="Kynetix", scripts="", section=None, active=None, robots=None):
    """Write site/<path>index.html (path ends with '/' or is '')."""
    alts = alternates_for(path)
    hl = []
    for l in LANGS:
        if l in alts:
            hl.append(f'<link rel="alternate" hreflang="{HREFLANG[l]}" href="{url(alts[l])}">')
    if alts:
        hl.append(f'<link rel="alternate" hreflang="x-default" href="{url(alts.get("en", path))}">')
    else:
        hl += [f'<link rel="alternate" hreflang="{HREFLANG[lang]}" href="{url(path)}">', f'<link rel="alternate" hreflang="x-default" href="{url(path)}">']
    img = URL + "assets/img/" + og
    head = "\n".join([
        '<meta charset="utf-8">', '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
        f'<title>{e(title)}</title>', f'<meta name="description" content="{e(desc)}">',
        f'<meta name="robots" content="{robots or "index, follow, max-image-preview:large, max-snippet:-1"}">',
        f'<link rel="canonical" href="{url(path)}">', *hl,
        '<meta name="author" content="Dhruv Gupta">', '<meta name="theme-color" content="#0B0B0C">', '<meta name="color-scheme" content="dark">',
        '<meta property="og:type" content="website">', '<meta property="og:site_name" content="Kynetix">',
        f'<meta property="og:locale" content="{OG_LOCALE[lang]}">', f'<meta property="og:title" content="{e(title)}">',
        f'<meta property="og:description" content="{e(desc)}">', f'<meta property="og:url" content="{url(path)}">',
        f'<meta property="og:image" content="{img}">', '<meta property="og:image:width" content="1200">', '<meta property="og:image:height" content="630">',
        f'<meta property="og:image:alt" content="{e(og_alt)}">', '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{e(title)}">', f'<meta name="twitter:description" content="{e(desc)}">', f'<meta name="twitter:image" content="{img}">',
        f'<link rel="icon" href="{BASE}favicon.ico" sizes="48x48">', f'<link rel="icon" href="{BASE}assets/img/favicon.svg" type="image/svg+xml">',
        f'<link rel="apple-touch-icon" href="{BASE}assets/img/apple-touch-icon.png">', f'<link rel="manifest" href="{BASE}site.webmanifest">',
        f'<link rel="preload" href="{BASE}assets/fonts/bricolage-800.woff2" as="font" type="font/woff2" crossorigin>',
        f'<link rel="stylesheet" href="{BASE}assets/css/site.css">',
        ld_script([ORG, PERSON, WEBSITE, *ld_nodes]),
    ])
    doc = (f'<!doctype html>\n<html lang="{HREFLANG[lang]}" class="content lang-{lang}">\n<head>\n{head}\n</head>\n<body>\n{SPRITE}\n'
           f'{header(lang, active)}\n<main id="main" class="c-main">\n{body}\n{lang_switch(path, lang)}\n</main>\n{footer(lang, path)}\n{scripts}\n</body>\n</html>\n')
    out = SITE / path / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(doc, encoding="utf-8", newline="\n")
    return out
