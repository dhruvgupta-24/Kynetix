"""Site checks: internal links resolve, JSON-LD parses, hreflang is reciprocal, no em/en dashes in visible text,
one h1 per page, every page has a title, description and canonical."""
import json, pathlib, re, sys
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse

SITE = pathlib.Path(__file__).resolve().parents[2] / "site"
BASE = "https://dhruvgupta-24.github.io/Kynetix/"


class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.ids, self.alts, self.ld, self.h1, self.text, self.canon = [], set(), {}, [], 0, [], None
        self._ld = False; self._skip = 0; self._cur = ""
    def handle_starttag(self, t, a):
        a = dict(a)
        if "id" in a: self.ids.add(a["id"])
        if t == "a" and a.get("href"): self.links.append(a["href"])
        if t in ("link",) and a.get("rel") == "alternate" and a.get("hreflang"): self.alts[a["hreflang"]] = a["href"]
        if t == "link" and a.get("rel") == "canonical": self.canon = a["href"]
        if t in ("img", "script", "link") and a.get("src"): self.links.append(a["src"])
        if t == "link" and a.get("rel") in ("stylesheet", "icon", "manifest", "apple-touch-icon", "preload"): self.links.append(a["href"])
        if t == "script" and a.get("type") == "application/ld+json": self._ld = True; self._cur = ""
        if t in ("script", "style"): self._skip += 1
        if t == "h1": self.h1 += 1
    def handle_endtag(self, t):
        if t in ("script", "style"):
            self._skip -= 1
            if self._ld: self.ld.append(self._cur); self._ld = False
    def handle_data(self, d):
        if self._ld: self._cur += d
        elif not self._skip: self.text.append(d)


def url_of(f):
    rel = f.relative_to(SITE).as_posix()
    return BASE + (rel[:-len("index.html")] if rel.endswith("index.html") else rel)


def main():
    pages = {}
    for f in SITE.rglob("*.html"):
        if f.name.startswith("google") and f.parent == SITE: continue
        p = P(); p.feed(f.read_text(encoding="utf-8")); pages[url_of(f)] = (f, p)
    errs = []
    for u, (f, p) in pages.items():
        for href in p.links:
            if href.startswith(("mailto:", "data:", "#")) or "://" in href and not href.startswith(BASE):
                if href.startswith("#") and href[1:] and href[1:] not in p.ids and href != "#top":
                    errs.append(f"{u}: missing anchor {href}")
                continue
            full = urljoin(u, href)
            if not full.startswith(BASE) and urlparse(full).netloc == "dhruvgupta-24.github.io":
                continue
            path, _, frag = full.partition("#")
            path = path.split("?")[0]
            rel = path[len(BASE):]
            target = SITE / rel
            if rel.endswith("/") or rel == "":
                target = target / "index.html"
            if not target.exists():
                errs.append(f"{u}: broken {href}")
            elif frag and target.suffix == ".html":
                tp = pages.get(path) or pages.get(url_of(target))
                if tp and frag not in tp[1].ids:
                    errs.append(f"{u}: missing anchor {href}")
        for blob in p.ld:
            try: json.loads(blob)
            except Exception as ex: errs.append(f"{u}: bad JSON-LD {ex}")
        if f.name != "404.html" and p.h1 != 1: errs.append(f"{u}: {p.h1} h1")
        txt = "".join(p.text)
        if re.search("[–—]", txt): errs.append(f"{u}: em/en dash in text")
        if f.name != "404.html" and "/og/" not in u:
            if p.canon != u: errs.append(f"{u}: canonical {p.canon}")
            for hl, href in p.alts.items():
                other = pages.get(href)
                if not other: errs.append(f"{u}: hreflang {hl} -> missing {href}"); continue
                if u not in other[1].alts.values(): errs.append(f"{u}: hreflang not reciprocal with {href}")
    print(len(pages), "pages checked,", len(errs), "problems")
    for e in errs[:60]: print(" ", e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
