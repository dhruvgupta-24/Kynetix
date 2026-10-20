"""Exercise hub: /exercises/ and pages for the most searched lifts in the app's library.

Text is written here from the library's structured fields (muscles, equipment, the
app's default sets and reps) plus the app's own form cues. The library's long-form
instructions and images come from third parties, so neither is republished.
"""
import re
import data
from exercise_pick import EXTRA
from page import render, register, crumbs_html, faq_html, faq_ld, breadcrumb_ld, url, e, BASE

CUES = data.form_cues()


def norm(n):
    return re.sub(r"[^a-z0-9]+", " ", n.lower()).strip()


def pick():
    lib = data.exercises()
    out, seen = [], set()
    for x in lib:
        if not x["id"][:1].isdigit() and norm(x["name"]) not in seen:
            out.append(x); seen.add(norm(x["name"]))
    by_name = {}
    for x in lib:
        by_name.setdefault(x["name"], x)
    for n in EXTRA:
        x = by_name.get(n)
        if x and norm(n) not in seen:
            out.append(x); seen.add(norm(n))
    return out


EX = pick()
for x in EX:
    nm = re.sub(r"\s*\((?:ohp|rdl)\)", "", x["name"], flags=re.I)
    x["display"] = nm.replace("Ez ", "EZ ").replace("Rdl", "RDL")
    x["slug"] = data.slugify(x["display"])
slugs = [x["slug"] for x in EX]
assert len(slugs) == len(set(slugs))

GROUP_ORDER = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core", "Other"]


def group(x):
    c = x["category"]
    if c in GROUP_ORDER:
        return c
    if x["bodyPart"] in ("Waist",) or x["targetMuscle"] in ("Abs", "Obliques"):
        return "Core"
    return {"Upper Arms": "Arms", "Lower Arms": "Arms", "Upper Legs": "Legs", "Lower Legs": "Legs", "Waist": "Core"}.get(x["bodyPart"], "Other")


def lc(s):
    return s[:1].lower() + s[1:] if s and not s[:2].isupper() else s


def equipment_phrase(x):
    eq = x["equipment"]
    grp = x["equipmentGroup"]
    if grp == "Bodyweight":
        return "a bodyweight exercise"
    return f"{'an' if eq[:1].lower() in 'aeiou' else 'a'} {lc(eq)} exercise"


def step_for(x):
    grp = x["equipmentGroup"]
    return {"Barbell": "2.5 kg (1.25 kg a side)", "Dumbbell": "the next dumbbell, usually 1 to 2.5 kg heavier",
            "Cable": "the next pin on the stack", "Machine": "the next plate or pin on the machine",
            "Bodyweight": None}.get(grp, "the smallest jump your gym has")


def secondary(x):
    s = [m for m in x.get("secondaryMuscles", []) if m and m != x["targetMuscle"]]
    return s


def summary(x):
    sec = secondary(x)
    s = f"{x['display']} is {equipment_phrase(x)} that mainly works the {lc(x['targetMuscle'])}"
    if sec:
        s += ", with the " + " and ".join(lc(m) for m in sec[:3]) + " helping"
    s += f". Kynetix starts it at {x['defaultTargetSets']} sets of {x['defaultRepMin']} to {x['defaultRepMax']} reps."
    return s


def progression(x):
    lo, hi = x["defaultRepMin"], x["defaultRepMax"]
    st = step_for(x)
    if st:
        return (f"Use double progression. Pick a weight you can lift for {lo} clean reps on every set. Each session, try to add a rep or two. "
                f"When every set reaches {hi} reps with good form, add {st} and start again near {lo}. "
                f"Kynetix suggests the next weight from your own last sessions, so you don't have to remember what you lifted.")
    return (f"Add reps first: when you can do {hi} clean reps on every set, make it harder. Slow the lowering to three seconds, pause at the hardest point, "
            f"or add load with a backpack, dip belt or vest. Kynetix logs bodyweight sets with any extra load, so the progress still shows.")


def path_of(x):
    return f"exercises/{x['slug']}/"


def related(x, n=6):
    same = [y for y in EX if y is not x and y["targetMuscle"] == x["targetMuscle"]]
    if len(same) < n:
        same += [y for y in EX if y is not x and y not in same and group(y) == group(x)]
    return same[:n]


def plan():
    register("exercises/", "en", None, "exercises")
    for x in EX:
        register(path_of(x), "en", None, "exercises")


def build():
    for x in EX:
        path = path_of(x)
        trail = [("Kynetix", ""), ("Exercises", "exercises/"), (x["display"], path)]
        cue = data.cue_for(x["name"], CUES)
        sec = secondary(x)
        facts = [("Main muscle", x["targetMuscle"]), ("Also works", ", ".join(sec) if sec else "Mostly the main muscle"),
                 ("Body part", x["bodyPart"]), ("Equipment", x["equipment"]),
                 ("Kynetix default", f"{x['defaultTargetSets']} sets of {x['defaultRepMin']} to {x['defaultRepMax']} reps")]
        frows = "".join(f'<tr><th scope="row">{e(k)}</th><td>{e(v)}</td></tr>' for k, v in facts)
        parts = [crumbs_html(trail, "en"), '<article class="c-art">',
                 f'<header class="c-head"><p class="kicker">{e(group(x))}</p><h1 class="c-h1">{e(x["display"])}</h1><p class="answer">{e(summary(x))}</p></header>',
                 f'<section class="c-sec" aria-labelledby="f-t"><h2 id="f-t">At a glance</h2><div class="table-scroll"><table class="nut nut-s"><tbody>{frows}</tbody></table></div></section>']
        if cue:
            parts.append(f'<section class="c-sec" aria-labelledby="c-t"><h2 id="c-t">The one cue</h2><p class="cue">{e(cue)}</p>'
                         f'<p class="small">The same cue Kynetix shows on this lift during a workout.</p></section>')
        parts.append(f'<section class="c-sec" aria-labelledby="p-t"><h2 id="p-t">How to progress</h2><p>{e(progression(x))}</p></section>')
        parts.append('<section class="c-sec" aria-labelledby="t-t"><h2 id="t-t">How Kynetix tracks it</h2><ul>'
                     '<li>Log each set in a tap with weight and rep steppers. Your last set sits right there.</li>'
                     '<li>The rest timer starts on its own after every set.</li>'
                     '<li>Personal records are spotted as you lift, using an estimated one-rep max (weight x (1 + reps / 30)).</li>'
                     '<li>Kyno suggests the next weight from your own history.</li></ul></section>')
        qas = [(f"What muscles does {lc(x['display'])} work?",
                f"Mainly the {lc(x['targetMuscle'])}" + (", with the " + " and ".join(lc(m) for m in sec[:3]) + " helping." if sec else ".")),
               (f"How many sets and reps of {lc(x['display'])} should I do?",
                f"Kynetix starts it at {x['defaultTargetSets']} sets of {x['defaultRepMin']} to {x['defaultRepMax']} reps. Stay in that range and add weight once every set reaches {x['defaultRepMax']} reps with good form.")]
        parts.append(faq_html(qas))
        rel = "".join(f'<li><a href="{BASE}{path_of(r)}">{e(r["display"])}</a></li>' for r in related(x))
        parts.append(f'<section class="c-sec" aria-labelledby="r-t"><h2 id="r-t">Similar exercises</h2><ul class="chips">{rel}</ul>'
                     f'<p><a class="link-arrow" href="{BASE}exercises/"><span>All exercises</span></a>'
                     f'<a class="link-arrow" href="{BASE}tools/one-rep-max-calculator/"><span>One rep max calculator</span></a></p></section>')
        parts.append('<p class="note">General training information, not medical advice. Stop if something hurts and get it checked.</p></article>')
        ld = [breadcrumb_ld(path, trail), faq_ld(path, qas, "en"),
              {"@type": "WebPage", "@id": url(path) + "#webpage", "url": url(path), "name": f"{x['display']}: muscles worked, sets, reps and progression",
               "inLanguage": "en-IN", "isPartOf": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#website"},
               "breadcrumb": {"@id": url(path) + "#breadcrumb"}, "about": {"@type": "Thing", "name": x["display"]}}]
        title = f"{x['display']}: Muscles Worked, Sets, Reps and Form | Kynetix"
        desc = f"{x['display']} works the {lc(x['targetMuscle'])}. Equipment, sets and reps, the one form cue and how to progress it, from the Kynetix workout tracker."
        render(path, "en", title, desc[:160], "\n".join(parts), ld, og="og-exercises.png", og_alt="Kynetix exercise guide", active="exercises")

    # index
    path = "exercises/"
    trail = [("Kynetix", ""), ("Exercises", path)]
    secs = []
    for g in GROUP_ORDER:
        items = sorted([x for x in EX if group(x) == g], key=lambda x: x["display"])
        if not items:
            continue
        lis = "".join(f'<li><a href="{BASE}{path_of(x)}"><b>{e(x["display"])}</b><span>{e(x["targetMuscle"])}, {e(lc(x["equipment"]))}</span></a></li>' for x in items)
        secs.append(f'<section class="c-sec" aria-labelledby="g-{g.lower()}"><h2 id="g-{g.lower()}">{e(g)}</h2><ul class="food-list">{lis}</ul></section>')
    qas = [("Which exercises should a beginner start with?", "A squat or leg press, a bench or dumbbell press, a row or lat pulldown, an overhead press and a Romanian deadlift cover most of the body. Add arms and calves once those feel steady."),
           ("How does Kynetix suggest the next weight?", "From your own history on that lift: when you hit the top of the rep range on every set, it suggests the next jump; when you miss, it holds the weight.")]
    body = (crumbs_html(trail, "en") + f'<header class="c-head"><p class="kicker">Exercises</p><h1 class="c-h1">Gym exercise guide</h1>'
            f'<p class="answer">{len(EX)} common gym and bodyweight exercises: which muscles they work, the equipment, how many sets and reps to start with, one form cue and how to progress, '
            f'as the Kynetix workout tracker sets them up.</p></header>' + "".join(secs) + faq_html(qas))
    ld = [breadcrumb_ld(path, trail), faq_ld(path, qas, "en"),
          {"@type": "CollectionPage", "@id": url(path) + "#webpage", "url": url(path), "name": "Gym exercise guide", "inLanguage": "en-IN",
           "isPartOf": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#website"}, "breadcrumb": {"@id": url(path) + "#breadcrumb"}}]
    render(path, "en", "Gym Exercise Guide: Muscles Worked, Sets and Reps | Kynetix",
           f"{len(EX)} gym and bodyweight exercises with muscles worked, equipment, sets and reps, one form cue and how to progress, from the Kynetix workout tracker.",
           body, ld, og="og-exercises.png", og_alt="Kynetix exercise guide", active="exercises")
