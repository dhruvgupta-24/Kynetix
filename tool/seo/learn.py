"""/learn/: one door to every hub."""
import foods, exercises, guides_content, tools, compare
from page import render, register, crumbs_html, breadcrumb_ld, url, e, BASE

HUBS = [("foods/", "Foods", lambda: f"Calories and protein in {len(foods.FOODS)} Indian foods, per katori, roti or 100 g."),
        ("exercises/", "Exercises", lambda: f"{len(exercises.EX)} gym and bodyweight exercises: muscles, sets, reps, one cue and how to progress."),
        ("guides/", "Guides", lambda: f"{len(guides_content.GUIDES)} practical guides on Indian diet, protein, splits, overload and fasting."),
        ("tools/", "Tools", lambda: "Calorie, protein, macro, one rep max and BMI calculators with the app's own formulas."),
        ("compare/", "Compare", lambda: "Honest comparisons with HealthifyMe, MyFitnessPal, Hevy and Strong.")]


def plan():
    register("learn/", "en", None, "learn")


def build():
    path = "learn/"
    trail = [("Kynetix", ""), ("Learn", path)]
    lis = "".join(f'<li><a href="{BASE}{p}"><b>{e(n)}</b><span>{e(d())}</span></a></li>' for p, n, d in HUBS)
    body = (crumbs_html(trail, "en") + '<header class="c-head"><p class="kicker">Learn</p><h1 class="c-h1">Learn with Kynetix</h1>'
            '<p class="answer">Free reference pages from the Kynetix app: what Indian food is worth, how to do and progress common lifts, practical guides and calculators. Everything uses the same numbers and formulas as the app.</p></header>'
            f'<ul class="food-list cards-list">{lis}</ul>')
    render(path, "en", "Learn: Indian Food, Exercises, Guides and Calculators | Kynetix",
           "Free reference from the Kynetix app: calories and protein in Indian food, exercise guides, practical diet and training guides and fitness calculators.",
           body, [breadcrumb_ld(path, trail)], og="og-home.png", og_alt="Learn with Kynetix")
