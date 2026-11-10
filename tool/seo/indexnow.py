"""Tell IndexNow search engines (Bing, Yandex, Seznam, Naver...) which pages changed.

Runs in the Deploy website workflow after GitHub Pages publishes. It lists the
site/**/index.html files that changed between two commits, drops pages marked
noindex, and posts their URLs in one request. The key is public by design: it
lives at site/<key>.txt so engines can check we own the site.

  python tool/seo/indexnow.py BEFORE_SHA AFTER_SHA
  python tool/seo/indexnow.py --all          every indexable page (one-off)
"""
import json
import pathlib
import subprocess
import sys
import urllib.request

REPO = pathlib.Path(__file__).resolve().parents[2]
SITE = REPO / "site"
HOST = "dhruvgupta-24.github.io"
URL = f"https://{HOST}/Kynetix/"
KEY = "b5d642f19a30042ebb0ac47bba868ad7"
ENDPOINT = "https://api.indexnow.org/indexnow"


def page_url(rel):
    """site/foods/dal/index.html -> https://.../Kynetix/foods/dal/"""
    rel = rel.replace("\\", "/")
    if not (rel.startswith("site/") and rel.endswith("index.html")):
        return None
    return URL + rel[len("site/"):-len("index.html")]


def indexable(rel):
    p = REPO / rel
    if not p.exists():
        return False  # deleted pages are not submitted
    head = p.read_text(encoding="utf-8", errors="ignore")[:6000].lower()
    return 'name="robots" content="noindex' not in head


def changed(before, after):
    if not before or set(before) == {"0"}:
        return []
    out = subprocess.run(["git", "diff", "--name-only", before, after, "--", "site"],
                         cwd=REPO, capture_output=True, text=True)
    return out.stdout.split() if out.returncode == 0 else []


def everything():
    return [p.relative_to(REPO).as_posix() for p in SITE.rglob("index.html")]


def main():
    files = everything() if "--all" in sys.argv else changed(*(sys.argv[1:3] + ["", ""])[:2])
    urls = sorted({u for f in files if (u := page_url(f)) and indexable(f)})
    if not urls:
        print("IndexNow: no indexable page changed")
        return
    body = json.dumps({
        "host": HOST,
        "key": KEY,
        "keyLocation": f"{URL}{KEY}.txt",
        "urlList": urls[:10000],
    }).encode()
    req = urllib.request.Request(ENDPOINT, data=body, method="POST",
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print(f"IndexNow: submitted {len(urls)} URL(s), HTTP {r.status}")
    except urllib.error.HTTPError as e:
        # 202 = accepted and pending key check; anything else is logged, never fails the deploy
        print(f"IndexNow: HTTP {e.code} {e.reason} for {len(urls)} URL(s)")
    except Exception as e:  # network trouble must not break deploys
        print(f"IndexNow: skipped ({e})")
    for u in urls[:20]:
        print("  ", u)


if __name__ == "__main__":
    main()
