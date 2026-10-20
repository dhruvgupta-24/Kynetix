"""Build every generated part of the Kynetix site.

    python tool/seo/build.py

1. Reads the app's food and exercise data (kynetix_ui/), so numbers always match the app.
2. Writes /download/ from site/version.json, then the shared header, dock, menu and footer
   on the hand-written pages (chrome.py) and their heads and JSON-LD (seo_core.py).
3. Writes the content hubs (foods, exercises, guides, tools, compare, learn) and the
   localized pages, then section sitemaps, robots.txt, llms files and the root sitemap index.
"""
import pathlib, runpy, shutil, sys
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import page
import foods, exercises, guides, tools, compare, learn, i18n_pages, sitemaps, download, chrome

GENERATED = ["foods", "exercises", "guides", "tools", "compare", "learn"] + [l for l in page.LANGS if l != "en"]


def clean():
    for d in GENERATED:
        p = page.SITE / d
        if p.exists():
            shutil.rmtree(p)


def css():
    """Keep the content-hub styles in site.css between markers."""
    f = page.SITE / "assets/css/site.css"
    s = f.read_text(encoding="utf-8")
    nl = chr(10)
    end = "/* @content-end */" + nl
    block = "/* @content-start */" + nl + (HERE / "content.css").read_text(encoding="utf-8").strip() + nl + end
    if "/* @content-start */" in s:
        a = s.index("/* @content-start */"); b = s.index(end) + len(end)
        s = s[:a] + block + s[b:]
    else:
        s = s.rstrip() + nl + nl + block
    f.write_text(s, encoding="utf-8", newline=nl)


def llms(core):
    URL = page.URL
    hubs = [("Foods", "foods/", f"Calories, protein, carbs, fat and fiber for {len(foods.FOODS)} Indian foods per katori, roti, plate or 100 g, from the app's food table."),
            ("Exercises", "exercises/", f"{len(exercises.EX)} gym and bodyweight exercises: muscles worked, equipment, sets and reps, one form cue, how to progress."),
            ("Guides", "guides/", "Practical guides: counting calories in Indian food, vegetarian protein, beginner splits, progressive overload, cutting and bulking, fasting, Health Connect."),
            ("Tools", "tools/", "Calorie (TDEE), protein, macro, one rep max and BMI calculators using the app's own formulas."),
            ("Compare", "compare/", "Neutral comparisons with HealthifyMe, MyFitnessPal, Hevy and Strong."),
            ("Download", "download/", "The free Android beta APK, install steps and SHA-256 checksums.")]
    langs = " ".join(f"[{page.NATIVE[l]}]({URL}{l}/)" for l in page.LANGS if l != "en")
    base = (page.SITE / "llms.txt").read_text(encoding="utf-8").split("\n## Optional")[0].rstrip()
    base = base.split("\n## Learn")[0].rstrip()
    add = ["", "## Learn", ""] + [f"- [{t}]({URL}{p}): {d}" for t, p, d in hubs] + ["", f"Localized pages: {langs}. The app itself is in English.", "",
           "## Optional", "", f"- [Full text for AI systems]({URL}llms-full.txt): every fact, FAQ answer and hub in one file.",
           f"- [Source code]({page.REPO}): the Flutter app, Supabase backend and this website.", ""]
    (page.SITE / "llms.txt").write_text(base + "\n" + "\n".join(add), encoding="utf-8", newline="\n")
    full = (page.SITE / "llms-full.txt").read_text(encoding="utf-8").split("\n## Learn")[0].rstrip()
    gl = "\n".join(f"- [{g['h1']}]({URL}guides/{g['slug']}/): {g['desc']}" for g in guides.GUIDES)
    fl = "\n".join(f"- [{p['display']}]({URL}{foods.page_path(p)}): {foods.summary(p)}" for p in sorted(foods.FOODS.values(), key=lambda p: p["name"]))
    full += "\n\n## Learn\n\n" + "\n".join(f"- [{t}]({URL}{p}): {d}" for t, p, d in hubs) + "\n\n### Guides\n\n" + gl + "\n\n### Food values (Kynetix food table)\n\n" + fl + "\n"
    (page.SITE / "llms-full.txt").write_text(full, encoding="utf-8", newline="\n")


def main():
    clean()
    css()
    # Plan every page first so each one knows its language alternates.
    localized = i18n_pages.localized_food_slugs()
    i18n_pages.plan()
    foods.plan(localized)
    exercises.plan()
    guides.plan()
    tools.plan(["en", "hi"])
    compare.plan()
    learn.plan()
    page.register("download/", "en", None, "core")
    # Hand-written pages: download main, shared chrome, heads and JSON-LD.
    download.write()
    chrome.run()
    home_alts = {l: p for l, p in page.CLUSTERS["home"].items()}
    core = runpy.run_path(str(HERE / "seo_core.py"), init_globals={"HOME_ALTS": home_alts, "LANG_HREF": page.HREFLANG})
    # Generated pages.
    foods.build_pages(); foods.build_index()
    exercises.build()
    guides.build()
    tools.build("en"); tools.build("hi")
    compare.build()
    learn.build()
    i18n_pages.build()
    sitemaps.write()
    llms(core)
    print(len(page.REGISTRY), "registered pages")


if __name__ == "__main__":
    main()
