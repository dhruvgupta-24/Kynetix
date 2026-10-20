"""Localized home, food index and food pages for hi, mr, ta, te, bn, gu, kn, ml, pa."""
import foods as F
import data
from i18n import TOP10, TOP30_HI, FOOD_NAMES, SERVINGS, FOOD_T, HOME_T
from page import render, register, crumbs_html, faq_html, faq_ld, breadcrumb_ld, url, e, BASE, LANGS, HREFLANG, shell, prefix

LOCALES = [l for l in LANGS if l != "en"]


def foods_for(lang):
    return TOP30_HI if lang == "hi" else TOP10


def localized_food_slugs():
    return {F.FOODS[k]["slug"] for k in TOP30_HI}


def fpath(lang, pg):
    return f"{lang}/foods/{pg['slug']}/"


def plan():
    register("", "en", "home", "core")
    for lang in LOCALES:
        register(f"{lang}/", lang, "home", "i18n")
        register(f"{lang}/foods/", lang, "foods-index", "i18n")
        for k in foods_for(lang):
            pg = F.FOODS[k]
            register(fpath(lang, pg), lang, "food:" + pg["slug"], "i18n")


def serv(lang, label):
    m = SERVINGS[lang]
    if label in m:
        return m[label]
    raise KeyError((lang, label))


def nums(n):
    return dict(k=F.kc(n["kcal"]), p=F.fmt(n["protein"]) if n.get("protein") is not None else "",
                c=F.fmt(n["carbs"]) if n.get("carbs") is not None else "", f=F.fmt(n["fat"]) if n.get("fat") is not None else "")


def food_page(lang, key):
    T = FOOD_T[lang]
    pg = F.FOODS[key]
    name = FOOD_NAMES[lang][key]
    rows = F.rows_for(pg)
    lab, n, _ = rows[0]
    s = serv(lang, lab)
    v = nums(n)
    path = fpath(lang, pg)
    has_p = n.get("protein") is not None
    summary = (T["sum"] if has_p else T["sum_k"]).format(food=name, serving=s, **v)
    p100 = F.per100(pg)
    extra = (" " + T["per100"].format(**nums(p100))) if (p100 and has_p) else ""
    # table
    th = T["th"] if has_p else T["th"][:2]
    head = "".join(f'<th scope="col">{e(h)}</th>' for h in th)
    body_rows = []
    for rl, rn, kind in rows:
        if kind == "kyno":
            continue
        if kind == "roti":
            g = rl.split("(")[1].split(" ")[0]
            label = T["with_roti"].format(g=g)
        elif kind == "rice":
            g = rl.split("(")[1].split(" ")[0]
            label = T["with_rice"].format(g=g)
        else:
            label = serv(lang, rl)
        cells = f'<th scope="row">{e(label)}</th><td>{F.kc(rn["kcal"])} kcal</td>'
        if has_p:
            fib = rn.get("fiber")
            cells += (f'<td>{F.fmt(rn["protein"])} {T["g"]}</td><td>{F.fmt(rn["carbs"])} {T["g"]}</td><td>{F.fmt(rn["fat"])} {T["g"]}</td>'
                      f'<td>{(F.fmt(fib) + " " + T["g"]) if fib is not None else "n/a"}</td>')
        body_rows.append(f"<tr>{cells}</tr>")
    table = f'<div class="table-scroll"><table class="nut"><thead><tr>{head}</tr></thead><tbody>{"".join(body_rows)}</tbody></table></div>'
    l1, _ = F.log_text(pg)
    qas = [(T["q1"].format(food=name, serving=s), summary)]
    if has_p:
        qas.append((T["q2"].format(food=name), T["a2"].format(serving=s, **v)))
    sh = shell(lang)
    trail = [("Kynetix", f"{lang}/"), (sh["foods"], f"{lang}/foods/"), (name, path)]
    others = [k for k in foods_for(lang) if k != key][:8]
    rel = "".join(f'<li><a href="{BASE}{fpath(lang, F.FOODS[k])}">{e(FOOD_NAMES[lang][k])}</a></li>' for k in others)
    body = (crumbs_html(trail, lang) + '<article class="c-art">' +
            f'<header class="c-head"><p class="kicker">{e(T["kicker"])}</p><h1 class="c-h1">{e(T["h1"].format(food=name))}</h1><p class="answer">{e(summary + extra)}</p></header>'
            f'<section class="c-sec" aria-labelledby="nut-t"><h2 id="nut-t">{e(T["nut"])}</h2>{table}</section>'
            f'<section class="c-sec" aria-labelledby="log-t"><h2 id="log-t">{e(T["log_h"])}</h2><p>{e(T["log"].format(log=l1))}</p></section>' +
            faq_html(qas, T["faq"]) +
            f'<section class="c-sec" aria-labelledby="rel-t"><h2 id="rel-t">{e(T["all"])}</h2><ul class="chips">{rel}</ul>'
            f'<p><a class="link-arrow" href="{BASE}{lang}/foods/"><span>{e(T["all"])}</span></a>'
            f'<a class="link-arrow" href="{BASE}{F.page_path(pg)}" hreflang="en-IN"><span>{e(T["en"])}</span></a></p></section>'
            f'<p class="note">{e(T["note"])}</p></article>')
    ld = [breadcrumb_ld(path, trail), faq_ld(path, qas, lang),
          {"@type": "WebPage", "@id": url(path) + "#webpage", "url": url(path), "name": T["h1"].format(food=name), "inLanguage": HREFLANG[lang],
           "breadcrumb": {"@id": url(path) + "#breadcrumb"}, "about": {"@type": "Thing", "name": name}}]
    desc = (T["desc"] if has_p else T["desc_k"]).format(food=name, serving=s, **v)
    render(path, lang, T["title"].format(food=name, serving=s), desc[:160], body, ld, og="og-foods.png", og_alt=name, active="foods")


def foods_index(lang):
    T = FOOD_T[lang]
    sh = shell(lang)
    path = f"{lang}/foods/"
    trail = [("Kynetix", f"{lang}/"), (sh["foods"], path)]
    lis = []
    for k in foods_for(lang):
        pg = F.FOODS[k]
        lab, n, _ = F.main_row(pg)
        v = nums(n)
        meta = f'{v["k"]} kcal' + (f', {v["p"]} {T["g"]} protein' if v["p"] else "") + f" / {serv(lang, lab)}"
        lis.append(f'<li><a href="{BASE}{fpath(lang, pg)}"><b>{e(FOOD_NAMES[lang][k])}</b><span>{e(meta)}</span></a></li>')
    body = (crumbs_html(trail, lang) + f'<header class="c-head"><p class="kicker">{e(T["kicker"])}</p><h1 class="c-h1">{e(T["idx_h1"])}</h1><p class="answer">{e(T["idx_answer"])}</p></header>'
            f'<ul class="food-list">{"".join(lis)}</ul><p><a class="link-arrow" href="{BASE}foods/" hreflang="en-IN"><span>{e(T["more_en"])}</span></a></p>'
            f'<p class="note">{e(T["note"])}</p>')
    ld = [breadcrumb_ld(path, trail), {"@type": "CollectionPage", "@id": url(path) + "#webpage", "url": url(path), "name": T["idx_h1"], "inLanguage": HREFLANG[lang]}]
    render(path, lang, T["idx_title"], T["idx_desc"][:160], body, ld, og="og-foods.png", og_alt=T["idx_h1"], active="foods")


def home(lang):
    H = HOME_T[lang]
    T = FOOD_T[lang]
    path = f"{lang}/"
    facts = "".join(f"<li><b>{e(k)}</b>{e(v)}</li>" for k, v in H["facts"])
    top = "".join(f'<li><a href="{BASE}{fpath(lang, F.FOODS[k])}"><b>{e(FOOD_NAMES[lang][k])}</b><span>{F.kc(F.main_row(F.FOODS[k])[1]["kcal"])} kcal / {e(serv(lang, F.main_row(F.FOODS[k])[0]))}</span></a></li>' for k in TOP10)
    tools_href = f"{BASE}hi/tools/" if lang == "hi" else f"{BASE}tools/"
    body = (f'<section class="l-hero"><div class="l-hero-in"><p class="kicker">Kynetix</p><h1 class="c-h1 l-h1">{e(H["h1"])}</h1><p class="lede-l">{e(H["lede"])}</p>'
            f'<div class="badges"><a class="badge play dl" href="{BASE}download/"><span><small>Android</small><b>{e(H["cta"])}</b></span></a>'
            f'<p class="badge ios" role="note"><span><small>Google Play</small><b>{e(H["play"])}</b></span></p><p class="badge ios" role="note"><span><small>iPhone</small><b>{e(H["ios"])}</b></span></p></div></div></section>'
            f'<section class="c-sec" aria-labelledby="what-t"><h2 id="what-t">{e(H["what"])}</h2><p class="answer">{e(H["definition"])}</p><ul class="facts">{facts}</ul><p>{e(H["lang_note"])}</p></section>'
            f'<section class="c-sec" aria-labelledby="fd-t"><h2 id="fd-t">{e(H["foods_h"])}</h2><ul class="food-list">{top}</ul>'
            f'<p><a class="link-arrow" href="{BASE}{lang}/foods/"><span>{e(H["foods_more"])}</span></a></p></section>'
            f'<section class="c-sec" aria-labelledby="tl-t"><h2 id="tl-t">{e(H["tools_h"])}</h2><p>{e(H["tools_p"])}</p><p><a class="link-arrow" href="{tools_href}"><span>{e(H["tools_h"])}</span></a></p></section>' +
            faq_html(H["faq"], H["faq_h"]) +
            f'<p><a class="link-arrow" href="{BASE}" hreflang="en-IN"><span>{e(H["en_site"])}</span></a></p>')
    ld = [faq_ld(path, H["faq"], lang),
          {"@type": "WebPage", "@id": url(path) + "#webpage", "url": url(path), "name": H["title"], "description": H["desc"], "inLanguage": HREFLANG[lang],
           "isPartOf": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#website"}, "about": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#app"}}]
    render(path, lang, H["title"], H["desc"][:160], body, ld, og="og-home.png", og_alt="Kynetix")


def build():
    for lang in LOCALES:
        home(lang)
        foods_index(lang)
        for k in foods_for(lang):
            food_page(lang, k)
