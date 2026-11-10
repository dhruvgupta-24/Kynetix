"""Real last-modified dates for the sitemaps, from git history.

Every page's <lastmod> is the date of the last commit that touched its
index.html, so search engines re-crawl what actually changed instead of
seeing one build date on every URL.

  python tool/seo/lastmod.py            rewrite <lastmod> in site/sitemap.xml,
                                        site/sitemaps/*.xml and, if given,
                                        the root sitemap index
  python tool/seo/lastmod.py --root PATH/TO/dhruvgupta-24.github.io
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve()
REPO = HERE.parents[2]
SITE = REPO / "site"
URL = "https://dhruvgupta-24.github.io/Kynetix/"


def lastmod_map():
    """{site-relative file path: 'YYYY-MM-DD'} for every file under site/,
    newest commit first. Files with uncommitted edits count as today."""
    out = subprocess.run(
        ["git", "log", "--format=%x00%cs", "--name-only", "--", "site"],
        cwd=REPO, capture_output=True, text=True, check=True).stdout
    dates = {}
    for block in out.split("\x00")[1:]:
        lines = [l for l in block.splitlines() if l.strip()]
        if not lines:
            continue
        day, files = lines[0], lines[1:]
        for f in files:
            dates.setdefault(f.replace("\\", "/"), day)
    dirty = subprocess.run(["git", "status", "--porcelain", "--", "site"], cwd=REPO,
                           capture_output=True, text=True, check=True).stdout
    if dirty.strip():
        import datetime
        today = datetime.date.today().isoformat()
        for line in dirty.splitlines():
            dates[line[3:].strip().replace("\\", "/")] = today
    return dates


def date_for_url(loc, dates, fallback):
    """The lastmod for a page URL: the date its index.html last changed."""
    if not loc.startswith(URL):
        return fallback
    path = loc[len(URL):]
    f = f"site/{path}index.html" if (path == "" or path.endswith("/")) else f"site/{path}"
    return dates.get(f, fallback)


def rewrite(xml_text, dates, fallback):
    def one(m):
        loc = m.group(1)
        return f"<loc>{loc}</loc><lastmod>{date_for_url(loc, dates, fallback)}</lastmod>"
    return re.sub(r"<loc>([^<]+)</loc><lastmod>[^<]*</lastmod>", one, xml_text)


def newest(xml_text):
    found = re.findall(r"<lastmod>([^<]+)</lastmod>", xml_text)
    return max(found) if found else None


def main():
    dates = lastmod_map()
    fallback = max(dates.values())
    files = [SITE / "sitemap.xml", *sorted((SITE / "sitemaps").glob("*.xml"))]
    newest_by_name = {}
    for p in files:
        before = p.read_text(encoding="utf-8")
        after = rewrite(before, dates, fallback)
        p.write_text(after, encoding="utf-8", newline="\n")
        name = p.relative_to(SITE).as_posix()
        newest_by_name[name] = newest(after)
        print(f"{name:24} newest {newest_by_name[name]}")

    if "--root" in sys.argv:
        root = pathlib.Path(sys.argv[sys.argv.index("--root") + 1]) / "sitemap.xml"
        idx = root.read_text(encoding="utf-8")
        def idx_one(m):
            loc = m.group(1)
            name = loc[len(URL):] if loc.startswith(URL) else None
            return f"<loc>{loc}</loc><lastmod>{newest_by_name.get(name) or fallback}</lastmod>"
        idx = re.sub(r"<loc>([^<]+)</loc><lastmod>[^<]*</lastmod>", idx_one, idx)
        root.write_text(idx, encoding="utf-8", newline="\n")
        print("root index updated:", root)


if __name__ == "__main__":
    main()
