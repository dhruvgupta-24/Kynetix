"""Free calculators with the app's own formulas. English here; Hindi strings come from i18n.TOOLS['hi']."""
import json
from page import render, register, crumbs_html, faq_html, faq_ld, breadcrumb_ld, url, e, BASE, prefix, HREFLANG

SLUGS = {"calories": "calorie-calculator", "protein": "protein-calculator", "macros": "macro-calculator",
         "onerm": "one-rep-max-calculator", "bmi": "bmi-calculator"}
ORDER = ["calories", "protein", "macros", "onerm", "bmi"]

EN = dict(
    common=dict(sex="Sex", male="Male", female="Female", age="Age (years)", height="Height (cm)", weight="Body weight (kg)",
                days="Training days per week", goal="Goal", steps="Average daily steps (optional)", calc="Calculate", results="Your result",
                goals=dict(maintain="Maintain", cut="Lose fat (cut)", recomp="Recomposition", leanbulk="Lean bulk", bulk="Bulk"),
                hub="Free fitness calculators", hub_title="Free Calorie, Protein, Macro, 1RM and BMI Calculators | Kynetix",
                hub_desc="Free calculators for calories (TDEE), protein, macros, one rep max and BMI, using the same formulas as the Kynetix app. No sign-up, works on your phone.",
                hub_answer="Five free calculators that use the exact formulas inside the Kynetix app: daily calories, protein, macros, one rep max and BMI. Nothing is sent anywhere; the maths runs in your browser.",
                kicker="Tools", how="How it works", app_cta="Kynetix works these out from your profile and adjusts them as you train and log. ", app_link="See the app",
                more="More calculators", unit_kcal="kcal", unit_g="g", note="Estimates for healthy adults, not medical advice.", words={"to": "to"}),
    calories=dict(
        title="Calorie Calculator (TDEE and BMR) for Gym Training | Kynetix",
        desc="Work out your BMR, maintenance calories and daily target for fat loss, recomp or bulking, with training and rest day calories, using the Kynetix app's formula.",
        h1="Calorie calculator", answer="Your daily calories start from your BMR (Mifflin-St Jeor), multiplied by an activity factor for how often you lift, then adjusted for your goal. Training days get a little more, rest days a little less.",
        out=[("bmr", "BMR (calories at rest)", "kcal"), ("tdee", "Maintenance (TDEE)", "kcal"), ("avg", "Daily target, average", "kcal"),
             ("train", "Training day", "kcal"), ("rest", "Rest day", "kcal")],
        how=["BMR uses Mifflin-St Jeor: 10 x weight (kg) + 6.25 x height (cm) - 5 x age, then + 5 for men or - 161 for women.",
             "Maintenance is BMR x an activity factor from 1.20 (no training) to 1.50 (7 days a week). These factors are deliberately lower than the classic tables, which assume cardio; a lifting session burns less than people think.",
             "Steps, if you add them, adjust maintenance by (steps - 7,000) x weight x 0.00041 kcal, capped at 400 either way.",
             "Goal: a cut takes off 22% (between 350 and 550 kcal), recomp 9% (120 to 250), a lean bulk adds 8% (150 to 250) and a bulk 10% (200 to 350). The target never drops below BMR + 200.",
             "Training and rest days differ by 140 to 220 kcal, weighted so the weekly average still equals your target."],
        faq=[("How many calories should I eat to lose fat?", "About 22% below your maintenance calories, which for most people is a 350 to 550 kcal daily deficit. That usually means losing 0.5 to 1% of body weight a week while keeping your lifts."),
             ("What is the difference between BMR and TDEE?", "BMR is what your body burns at complete rest. TDEE, or maintenance, adds everything you do in a day: walking, work and training."),
             ("Calories kitni khani chahiye?", "Pehle maintenance calories nikalo (BMR x activity), phir goal ke hisaab se: fat loss ke liye lagbhag 22% kam, lean bulk ke liye 8% zyada.")]),
    protein=dict(
        title="Protein Calculator: How Much Protein Per Day for Gym | Kynetix",
        desc="How much protein you need a day for fat loss, recomp or muscle gain, in grams, with training and rest day targets. Uses the same g/kg as the Kynetix app.",
        h1="Protein calculator", answer="Most people who lift do well on 1.7 to 2.2 g of protein per kg a day: the top of that range while losing fat, a little less while gaining. Above a BMI of 27 it is worked out on a capped reference weight, so it tracks muscle rather than body fat.",
        out=[("ref", "Reference weight", "kg"), ("perkg", "Grams per kg (average day)", "g/kg"), ("avg", "Average day", "g"), ("train", "Training day", "g"), ("rest", "Rest day", "g")],
        how=["Reference weight is your weight, capped at a BMI of 27 for your height.",
             "Grams per kg by goal (average, training day, rest day): cut 2.1, 2.2, 2.0; recomp 2.0, 2.1, 1.9; maintain and bulk 1.8, 1.9, 1.7.",
             "These follow the ISSN position stand on protein for people who train (1.6 to 2.2 g/kg)."],
        faq=[("How much protein do I need to build muscle?", "Around 1.8 g per kg of body weight a day on an average day, a little more on training days. A 70 kg lifter is looking at about 125 g."),
             ("Can vegetarians hit their protein?", "Yes. Paneer, curd, soya chunks, dal, chana, milk and whey cover it. Spread it over three or four meals."),
             ("Roz kitna protein khana chahiye?", "Gym karte ho to lagbhag 1.7 se 2.2 g protein per kg body weight. 70 kg ke liye lagbhag 125 g.")]),
    macros=dict(
        title="Macro Calculator: Protein, Carbs and Fat for Your Goal | Kynetix",
        desc="Get daily protein, carbs, fat and fiber in grams for fat loss, recomp or bulking. Same macro split as the Kynetix app: protein first, fat 30%, carbs fill the rest.",
        h1="Macro calculator", answer="Set protein first from your weight and goal, give fat 30% of the remaining calories (never under 0.6 g per kg), and let carbs fill the rest. Fiber follows 14 g per 1,000 kcal.",
        out=[("cal", "Calories", "kcal"), ("protein", "Protein", "g"), ("carbs", "Carbs", "g"), ("fat", "Fat", "g"), ("fiber", "Fiber", "g")],
        how=["Calories come from the calorie calculator: BMR x activity, adjusted for your goal.",
             "Protein: reference weight (capped at BMI 27) x grams per kg for your goal.",
             "Fat: 30% of the calories left after protein, but never under 0.6 g per kg of reference weight.",
             "Carbs: whatever calories remain, divided by 4. Fiber: 14 g per 1,000 kcal, between 20 and 60 g."],
        faq=[("What macros should I eat to lose fat?", "Keep protein high (about 2.1 g per kg), fat at roughly 30% of the calories left after protein, and carbs filling the rest of a 22% deficit."),
             ("Do I need to hit my macros exactly?", "No. Get protein and calories close most days; carbs and fat can move around. Weekly averages matter more than any single day.")]),
    onerm=dict(
        title="One Rep Max Calculator (1RM, Epley Formula) | Kynetix",
        desc="Estimate your one rep max from any set with the Epley formula, the same one Kynetix uses to spot PRs, plus training weights from 50 to 95% of your 1RM.",
        h1="One rep max calculator", answer="Your estimated one rep max is the weight times one plus the reps divided by 30 (the Epley formula). It is most accurate for sets of 10 reps or fewer.",
        out=[("orm", "Estimated 1RM", "kg")],
        how=["Epley: 1RM = weight x (1 + reps / 30). Kynetix uses the same formula to spot personal records as you lift.",
             "Training weights are your estimated 1RM times each percentage, rounded to the nearest 0.5 kg."],
        faq=[("How accurate is a one rep max calculator?", "Close for sets of 3 to 10 reps, less so above 12. It estimates; it does not replace a careful test with a spotter."),
             ("What percentage of my 1RM should I train at?", "Roughly 70 to 85% for most strength and muscle work, which lines up with sets of about 5 to 12 reps.")]),
    bmi=dict(
        title="BMI Calculator with Asian (Indian) Cut-offs | Kynetix",
        desc="Calculate your BMI and see where it falls on both the standard WHO ranges and the lower cut-offs suggested for Asian (including Indian) adults.",
        h1="BMI calculator", answer="BMI is your weight in kg divided by your height in metres squared. For Asian adults, including Indians, a WHO expert group suggested lower cut-offs: 23 for overweight and 27.5 for obesity, instead of 25 and 30.",
        out=[("bmi", "Your BMI", ""), ("who", "WHO standard ranges", ""), ("asia", "Asian cut-offs", ""), ("range", "Healthy weight for your height (BMI 18.5 to 22.9)", "kg")],
        how=["BMI = weight (kg) / height (m) x height (m).",
             "WHO standard: under 18.5 underweight, 18.5 to 24.9 normal, 25 to 29.9 overweight, 30 and above obese.",
             "Asian cut-offs (WHO expert consultation, 2004): 23 to 27.4 overweight, 27.5 and above obese.",
             "BMI ignores muscle. Lifters with a lot of muscle can read overweight while being lean."],
        faq=[("What is a healthy BMI for Indians?", "Between 18.5 and 22.9 on the Asian cut-offs. Above 23 counts as overweight there, earlier than the standard 25."),
             ("Is BMI accurate for people who lift?", "Not very. It cannot tell muscle from fat, so a muscular person can score high. Waist size and how your clothes fit tell you more.")]),
    words=dict(bmi=dict(under="Underweight", normal="Normal", over="Overweight", obese="Obese")),
)


def text(lang):
    if lang == "en":
        return EN
    from i18n import TOOLS
    return TOOLS[lang]


def field(name, label, kind="number", **kw):
    if kind == "select":
        opts = "".join(f'<option value="{v}"{" selected" if v == kw.get("sel") else ""}>{e(t)}</option>' for v, t in kw["options"])
        return f'<div class="fld"><label for="f-{name}">{e(label)}</label><select id="f-{name}" name="{name}">{opts}</select></div>'
    req = "" if kw.get("optional") else " required"
    attrs = " ".join(f'{k}="{v}"' for k, v in kw.items() if k in ("min", "max", "step", "value", "placeholder"))
    return f'<div class="fld"><label for="f-{name}">{e(label)}</label><input id="f-{name}" name="{name}" type="number" inputmode="decimal" {attrs}{req}></div>'


def form_html(tool, T):
    c = T["common"]
    sex = field("sex", c["sex"], "select", options=[("male", c["male"]), ("female", c["female"])], sel="male")
    age = field("age", c["age"], min=15, max=90, step=1, value=25)
    h = field("height", c["height"], min=120, max=230, step="0.5", value=172)
    w = field("weight", c["weight"], min=30, max=250, step="0.1", value=70)
    days = field("days", c["days"], min=0, max=7, step=1, value=4)
    goal = field("goal", c["goal"], "select", options=list(c["goals"].items()), sel="maintain")
    steps = field("steps", c["steps"], min=0, max=40000, step=100, optional=True, placeholder="8000")
    fields = {"calories": [sex, age, h, w, days, goal, steps], "protein": [w, h, goal], "macros": [sex, age, h, w, days, goal],
              "onerm": [field("weight", T["onerm"].get("wlabel", "Weight lifted (kg)"), min=1, max=500, step="0.5", value=60),
                        field("reps", T["onerm"].get("rlabel", "Reps done"), min=1, max=20, step=1, value=8)],
              "bmi": [h, w]}[tool]
    return f'<form class="tool" data-tool="{tool}"><div class="fld-grid">{"".join(fields)}</div><button class="btn" type="submit">{e(c["calc"])}</button></form>'


def results_html(tool, T):
    rows = "".join(f'<div class="res"><dt>{e(lab)}</dt><dd><b data-out="{k}">0</b> <span>{e(u)}</span></dd></div>' for k, lab, u in T[tool]["out"])
    extra = ""
    if tool == "onerm":
        pcts = [95, 90, 85, 80, 75, 70, 65, 60, 50]
        extra = ('<div class="table-scroll"><table class="nut nut-s"><thead><tr><th scope="col">%</th><th scope="col">kg</th></tr></thead><tbody>' +
                 "".join(f'<tr><th scope="row">{p}%</th><td data-pct="{p}">0</td></tr>' for p in pcts) + "</tbody></table></div>")
    return f'<section class="results" data-results hidden aria-live="polite"><h2>{e(T["common"]["results"])}</h2><dl class="res-grid">{rows}</dl>{extra}</section>'


def path_for(tool, lang):
    return ("" if lang == "en" else lang + "/") + f"tools/{SLUGS[tool]}/"


def hub_path(lang):
    return ("" if lang == "en" else lang + "/") + "tools/"


def plan(langs):
    for lang in langs:
        register(hub_path(lang), lang, "tools-hub", "tools")
        for t in ORDER:
            register(path_for(t, lang), lang, "tool:" + t, "tools")


def build(lang):
    T = text(lang)
    c = T["common"]
    home = "Kynetix"
    hubp = hub_path(lang)
    for t in ORDER:
        tt = T[t]
        path = path_for(t, lang)
        trail = [(home, "" if lang == "en" else lang + "/"), (c["kicker"], hubp), (tt["h1"], path)]
        how = "".join(f"<li>{e(x)}</li>" for x in tt["how"])
        more = "".join(f'<li><a href="{BASE}{path_for(o, lang)}">{e(T[o]["h1"])}</a></li>' for o in ORDER if o != t)
        words = json.dumps(dict(T["words"], **c.get("words", {})), ensure_ascii=False)
        body = (crumbs_html(trail, lang) + '<article class="c-art">' +
                f'<header class="c-head"><p class="kicker">{e(c["kicker"])}</p><h1 class="c-h1">{e(tt["h1"])}</h1><p class="answer">{e(tt["answer"])}</p></header>' +
                form_html(t, T) + results_html(t, T) +
                f'<section class="c-sec" aria-labelledby="how-t"><h2 id="how-t">{e(c["how"])}</h2><ul>{how}</ul>'
                f'<p>{e(c["app_cta"])}<a href="{prefix(lang)}">{e(c["app_link"])}</a>.</p></section>' +
                faq_html(tt["faq"], T.get("faq_title", "Questions")) +
                f'<section class="c-sec" aria-labelledby="more-t"><h2 id="more-t">{e(c["more"])}</h2><ul class="chips">{more}</ul></section>' +
                f'<p class="note">{e(c["note"])}</p></article>' +
                f'<script type="application/json" id="tool-words">{words}</script>')
        ld = [breadcrumb_ld(path, trail), faq_ld(path, tt["faq"], lang),
              {"@type": "WebApplication", "@id": url(path) + "#app", "name": tt["h1"], "url": url(path), "description": tt["desc"],
               "applicationCategory": "HealthApplication", "operatingSystem": "Any (web browser)", "inLanguage": HREFLANG[lang],
               "isAccessibleForFree": True, "offers": {"@type": "Offer", "price": "0", "priceCurrency": "INR"},
               "publisher": {"@id": "https://dhruvgupta-24.github.io/Kynetix/#org"}}]
        render(path, lang, tt["title"], tt["desc"], body, ld, og="og-tools.png", og_alt="Kynetix free fitness calculators",
               scripts=f'<script src="{BASE}assets/js/tools.js" defer></script>', active="tools")
    # hub
    trail = [(home, "" if lang == "en" else lang + "/"), (c["kicker"], hubp)]
    cards = "".join(f'<li><a href="{BASE}{path_for(t, lang)}"><b>{e(T[t]["h1"])}</b><span>{e(T[t]["answer"][:110].rsplit(" ", 1)[0])}...</span></a></li>' for t in ORDER)
    body = (crumbs_html(trail, lang) + f'<header class="c-head"><p class="kicker">{e(c["kicker"])}</p><h1 class="c-h1">{e(c["hub"])}</h1><p class="answer">{e(c["hub_answer"])}</p></header>'
            f'<ul class="food-list cards-list">{cards}</ul>')
    ld = [breadcrumb_ld(hubp, trail), {"@type": "CollectionPage", "@id": url(hubp) + "#webpage", "url": url(hubp), "name": c["hub"], "inLanguage": HREFLANG[lang]}]
    render(hubp, lang, c["hub_title"], c["hub_desc"], body, ld, og="og-tools.png", og_alt="Kynetix free fitness calculators", active="tools")
