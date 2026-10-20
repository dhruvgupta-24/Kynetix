"""Guides: answer-first articles with Article + FAQPage JSON-LD."""
import re
import foods as F
import exercises as X
from guides_content import GUIDES
from guides_more import MORE
from guides_more2 import MORE2
for _g in GUIDES:
    _g["body"] = _g["body"][:-1] + MORE.get(_g["slug"], []) + MORE2.get(_g["slug"], []) + _g["body"][-1:]
from page import render, register, crumbs_html, faq_html, faq_ld, breadcrumb_ld, url, e, BASE

EX_SLUGS = {x["slug"] for x in X.EX}
TOOL_SLUGS = {"calorie-calculator", "protein-calculator", "macro-calculator", "one-rep-max-calculator", "bmi-calculator"}
GUIDE_SLUGS = {g["slug"] for g in GUIDES}


def food(key):
    pg = F.FOODS[key]
    return pg, F.main_row(pg)


def tok(m, as_text=False):
    kind, arg = m.group(1), m.group(2)
    if kind in ("k", "p", "s", "c", "fb", "ps", "k2", "k3"):
        pg, (lab, n, _) = food(arg)
        if kind == "k": return F.kc(n["kcal"])
        if kind == "k2": return F.kc(2 * n["kcal"])
        if kind == "k3": return F.kc(3 * n["kcal"])
        if kind == "p": return F.fmt(n["protein"])
        if kind == "c": return F.fmt(n["carbs"])
        if kind == "fb": return F.fmt(n["fiber"])
        if kind == "s": return lab
        if kind == "ps": return str(F.protein_share(n))
    target, _, text = arg.partition("|")
    if kind == "f":
        assert target in F.FOODS, target
        href = BASE + F.page_path(F.FOODS[target])
    elif kind == "x":
        assert target in EX_SLUGS, target
        href = f"{BASE}exercises/{target}/"
    elif kind == "t":
        assert target in TOOL_SLUGS, target
        href = f"{BASE}tools/{target}/"
    elif kind == "g":
        href = f"{BASE}foods/" if target == ".." else f"{BASE}guides/{target}/"
        assert target == ".." or target in GUIDE_SLUGS, target
    elif kind == "pp":
        href, text = f"{BASE}privacy/", target
    else:
        raise ValueError(kind)
    return text if as_text else f'<a href="{href}">{e(text)}</a>'


PAT = re.compile(r"\[\[(k|p|s|c|fb|ps|k2|k3|f|x|t|g|pp):([^\]]+)\]\]")
PAT_PP = re.compile(r"\[\[pp\|([^\]]+)\]\]")


def fill(s, as_text=False):
    s = PAT_PP.sub(lambda m: m.group(1) if as_text else f'<a href="{BASE}privacy/">{e(m.group(1))}</a>', s)
    out, last = [], 0
    for m in PAT.finditer(s):
        out.append(s[last:m.start()] if as_text else e(s[last:m.start()]))
        out.append(tok(m, as_text))
        last = m.end()
    out.append(s[last:] if as_text else e(s[last:]))
    return "".join(out)


def block(b):
    if isinstance(b, str):
        return f"<p>{fill(b)}</p>"
    if b[0] == "ul":
        return "<ul>" + "".join(f"<li>{fill(i)}</li>" for i in b[1]) + "</ul>"
    if b[0] == "table":
        head = "".join(f'<th scope="col">{fill(h)}</th>' for h in b[1])
        rows = "".join("<tr>" + "".join((f'<th scope="row">{fill(c)}</th>' if i == 0 else f"<td>{fill(c)}</td>") for i, c in enumerate(r)) + "</tr>" for r in b[2])
        return f'<div class="table-scroll"><table class="nut"><thead><tr>{head}</tr></thead><tbody>{rows}</tbody></table></div>'
    raise ValueError(b)


def words(g):
    txt = fill(g["answer"], True) + " " + " ".join(
        (fill(b, True) if isinstance(b, str) else " ".join(fill(i, True) for i in (b[1] if b[0] == "ul" else [c for r in b[2] for c in r])))
        for _, bl in g["body"] for b in bl) + " " + " ".join(fill(q, True) + " " + fill(a, True) for q, a in g["faq"])
    return len(txt.split())


def plan():
    register("guides/", "en", None, "guides")
    for g in GUIDES:
        register(f"guides/{g['slug']}/", "en", None, "guides")


def build():
    for g in GUIDES:
        path = f"guides/{g['slug']}/"
        trail = [("Kynetix", ""), ("Guides", "guides/"), (g["h1"], path)]
        toc = "".join(f'<li><a href="#s{i}">{e(h)}</a></li>' for i, (h, _) in enumerate(g["body"]))
        secs = "".join(f'<section class="c-sec" aria-labelledby="s{i}"><h2 id="s{i}">{e(h)}</h2>{"".join(block(b) for b in bl)}</section>'
                       for i, (h, bl) in enumerate(g["body"]))
        qas = [(fill(q, True), fill(a, True)) for q, a in g["faq"]]
        others = [o for o in GUIDES if o is not g][:4]
        more = "".join(f'<li><a href="{BASE}guides/{o["slug"]}/">{e(o["h1"])}</a></li>' for o in others)
        n = words(g)
        body = (crumbs_html(trail, "en") + '<article class="c-art guide">' +
                f'<header class="c-head"><p class="kicker">Guide</p><h1 class="c-h1">{e(g["h1"])}</h1>'
                f'<p class="byline">By Dhruv Gupta, maker of Kynetix. <time datetime="{g["date"]}">20 October 2026</time>. {max(1, round(n / 200))} min read.</p>'
                f'<p class="answer">{fill(g["answer"])}</p></header>'
                f'<nav class="g-toc" aria-label="In this guide"><ol>{toc}</ol></nav>' + secs + faq_html(qas) +
                f'<section class="c-sec" aria-labelledby="more-t"><h2 id="more-t">More guides</h2><ul class="chips">{more}</ul></section>'
                '<p class="note">General information for healthy adults, not medical advice. Food values are estimates from Kynetix\'s food table.</p></article>')
        ld = [breadcrumb_ld(path, trail), faq_ld(path, qas, "en"),
              {"@type": "Article", "@id": url(path) + "#article", "headline": g["h1"], "description": g["desc"], "url": url(path),
               "mainEntityOfPage": url(path), "inLanguage": "en-IN", "datePublished": g["date"], "dateModified": g["date"], "wordCount": n,
               "author": {"@type": "Person", "@id": "https://dhruvgupta-24.github.io/Kynetix/#founder", "name": "Dhruv Gupta"},
               "publisher": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#org"},
               "image": "https://dhruvgupta-24.github.io/Kynetix/assets/img/og-guides.png"}]
        render(path, "en", g["title"], g["desc"], body, ld, og="og-guides.png", og_alt="Kynetix guide", active="guides")
        print("guide", g["slug"], n, "words")
    path = "guides/"
    trail = [("Kynetix", ""), ("Guides", path)]
    lis = "".join(f'<li><a href="{BASE}guides/{g["slug"]}/"><b>{e(g["h1"])}</b><span>{e(fill(g["answer"], True)[:120].rsplit(" ", 1)[0])}...</span></a></li>' for g in GUIDES)
    body = (crumbs_html(trail, "en") + '<header class="c-head"><p class="kicker">Guides</p><h1 class="c-h1">Food and training guides</h1>'
            '<p class="answer">Short, practical guides on counting calories in Indian food, getting enough protein, choosing a gym split and training through fasts, written by the maker of Kynetix.</p></header>'
            f'<ul class="food-list cards-list">{lis}</ul>')
    ld = [breadcrumb_ld(path, trail), {"@type": "CollectionPage", "@id": url(path) + "#webpage", "url": url(path), "name": "Food and training guides", "inLanguage": "en-IN"}]
    render(path, "en", "Indian Diet and Gym Guides: Calories, Protein, Splits | Kynetix",
           "Practical guides on counting calories in Indian food, high-protein vegetarian eating, beginner gym splits, progressive overload, cutting, bulking and fasting.",
           body, ld, og="og-guides.png", og_alt="Kynetix guides", active="guides")
