"""Section sitemaps with hreflang, the Kynetix sitemap, the root sitemap index, and llms files."""
import pathlib
import page
from page import URL, TODAY, HREFLANG, LANGS, SITE

ROOT_SITE = pathlib.Path(r"C:/Users/Dhruv/Desktop/dhruvgupta-24.github.io")
CORE = ["", "download/", "about/", "privacy/", "terms/", "delete-account/"]
SECTIONS = ["foods", "exercises", "guides", "tools", "compare", "learn", "i18n"]


def _url_entry(path):
    alts = page.alternates_for(path) if path in page.REGISTRY else page.CLUSTERS.get("home", {}) if path == "" else {}
    links = ""
    if alts:
        for l in LANGS:
            if l in alts:
                links += f'<xhtml:link rel="alternate" hreflang="{HREFLANG[l]}" href="{URL}{alts[l]}"/>'
        links += f'<xhtml:link rel="alternate" hreflang="x-default" href="{URL}{alts.get("en", path)}"/>'
    return f"  <url><loc>{URL}{path}</loc><lastmod>{TODAY}</lastmod>{links}</url>"


def _write(name, paths):
    xml = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">']
    xml += [_url_entry(p) for p in paths]
    xml.append("</urlset>\n")
    (SITE / name).parent.mkdir(parents=True, exist_ok=True)
    (SITE / name).write_text("\n".join(xml), encoding="utf-8", newline="\n")


def section_of(path, info):
    return "i18n" if info["lang"] != "en" else info["section"]


def write():
    by = {s: [] for s in SECTIONS}
    for path, info in sorted(page.REGISTRY.items()):
        if path in CORE:
            continue
        by[section_of(path, info)].append(path)
    _write("sitemap.xml", CORE)
    names = ["sitemap.xml"]
    for s in SECTIONS:
        if by[s]:
            _write(f"sitemaps/{s}.xml", by[s])
            names.append(f"sitemaps/{s}.xml")
    idx = ['<?xml version="1.0" encoding="UTF-8"?>', '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    idx += [f"  <sitemap><loc>{URL}{n}</loc><lastmod>{TODAY}</lastmod></sitemap>" for n in names]
    idx.append("</sitemapindex>\n")
    if ROOT_SITE.exists():
        (ROOT_SITE / "sitemap.xml").write_text("\n".join(idx), encoding="utf-8", newline="\n")
    # robots: list every sitemap too
    rb = (SITE / "robots.txt").read_text(encoding="utf-8").split("\nSitemap:")[0].rstrip() + "\n\n"
    rb += "".join(f"Sitemap: {URL}{n}\n" for n in names)
    (SITE / "robots.txt").write_text(rb, encoding="utf-8", newline="\n")
    print("sitemaps", {s: len(v) for s, v in by.items()})
    return names
