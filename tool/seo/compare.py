"""Honest comparison pages. Only Kynetix's own facts are stated as facts; the other apps are described
by what they are publicly known for, with a pointer to their store listing. No pricing claims."""
from page import render, register, crumbs_html, faq_html, faq_ld, breadcrumb_ld, url, e, BASE

AS_OF = "October 2026"
KYNETIX = [("Platforms", "Android (beta). iPhone is on the roadmap."), ("Focus", "Food and training in one app, built around Indian food."),
           ("Food logging", "Type meals in plain words (\"2 roti, dal\"); katori and roti portions; barcode scanning."),
           ("Workout logging", "Sets, reps, rest timer, splits, personal records and next-weight suggestions."),
           ("Coach", "Kyno, an AI coach that reads your meals, lifts, steps and weight."),
           ("Price", "Free during early access, no ads.")]

APPS = [
    dict(slug="kynetix-vs-healthifyme", name="HealthifyMe", kind="nutrition and fitness app from India",
         known=["A large Indian food database and calorie tracking.", "An AI nutrition assistant (Ria) and plans with human coaches.", "Available on Android and iPhone."],
         pick_them="You want a long-established Indian nutrition app on both Android and iPhone, or a plan with a human coach.",
         pick_us="You lift weights and want food and training tracked together, with a coach that reads both, and you're on Android."),
    dict(slug="kynetix-vs-myfitnesspal", name="MyFitnessPal", kind="global calorie counter",
         known=["One of the best-known calorie counters, with a very large food database.", "Free and Premium tiers.", "Available on Android and iPhone."],
         pick_them="You eat a lot of packaged or international food, or you want the biggest food database and an iPhone app.",
         pick_us="Most of your food is home-cooked Indian food and you want katori and roti portions understood, plus workout logging in the same app."),
    dict(slug="kynetix-vs-hevy", name="Hevy", kind="workout tracker",
         known=["A popular workout logger with routines and progress charts.", "A social feed to follow friends' workouts.", "Available on Android and iPhone."],
         pick_them="You only want to log workouts, like a social feed, or need an iPhone app today.",
         pick_us="You want your food and your training in one place, with targets that follow your training days."),
    dict(slug="kynetix-vs-strong", name="Strong", kind="workout tracker",
         known=["A clean, simple workout logger with routines and history.", "Available on Android and iPhone."],
         pick_them="You only want a minimal set logger, or need an iPhone app today.",
         pick_us="You also want to count Indian food and get coaching that connects what you eat with how you lift."),
]


def plan():
    register("compare/", "en", None, "compare")
    for a in APPS:
        register(f"compare/{a['slug']}/", "en", None, "compare")


def build():
    for a in APPS:
        path = f"compare/{a['slug']}/"
        h1 = f"Kynetix vs {a['name']}"
        trail = [("Kynetix", ""), ("Compare", "compare/"), (h1, path)]
        krows = "".join(f'<tr><th scope="row">{e(k)}</th><td>{e(v)}</td></tr>' for k, v in KYNETIX)
        known = "".join(f"<li>{e(k)}</li>" for k in a["known"])
        qas = [(f"Is Kynetix better than {a['name']}?", f"It depends on what you need. Pick {a['name']} if: {a['pick_them']} Pick Kynetix if: {a['pick_us']}"),
               (f"Can I use Kynetix and {a['name']} together?", "Yes. Many people try a new app alongside the one they use. Kynetix reads steps, weight and sleep from Health Connect, so it can sit next to other apps that write there.")]
        body = (crumbs_html(trail, "en") + '<article class="c-art">' +
                f'<header class="c-head"><p class="kicker">Compare</p><h1 class="c-h1">{e(h1)}</h1>'
                f'<p class="answer">{e(a["name"])} is a {e(a["kind"])}. Kynetix tracks Indian food and gym training together, with an AI coach that reads both. '
                f'Choose {e(a["name"])} if {e(a["pick_them"][0].lower() + a["pick_them"][1:])} Choose Kynetix if {e(a["pick_us"][0].lower() + a["pick_us"][1:])}</p></header>'
                f'<section class="c-sec" aria-labelledby="k-t"><h2 id="k-t">What Kynetix does</h2><div class="table-scroll"><table class="nut nut-s"><tbody>{krows}</tbody></table></div></section>'
                f'<section class="c-sec" aria-labelledby="o-t"><h2 id="o-t">What {e(a["name"])} is known for</h2><ul>{known}</ul>'
                f'<p class="small">From {e(a["name"])}\'s public app store listings as of {AS_OF}. Features and prices change, so check their listing for the latest.</p></section>'
                f'<section class="c-sec" aria-labelledby="w-t"><h2 id="w-t">Which one is for you</h2><ul><li><b>{e(a["name"])}:</b> {e(a["pick_them"])}</li><li><b>Kynetix:</b> {e(a["pick_us"])}</li></ul></section>' +
                faq_html(qas) +
                f'<p><a class="link-arrow" href="{BASE}compare/"><span>All comparisons</span></a><a class="link-arrow" href="{BASE}"><span>See Kynetix</span></a></p>'
                f'<p class="note">{e(a["name"])} is a trademark of its owner. Kynetix is not affiliated with it. We only state facts about Kynetix as facts.</p></article>')
        ld = [breadcrumb_ld(path, trail), faq_ld(path, qas, "en"),
              {"@type": "WebPage", "@id": url(path) + "#webpage", "url": url(path), "name": h1, "inLanguage": "en-IN", "breadcrumb": {"@id": url(path) + "#breadcrumb"}}]
        render(path, "en", f"Kynetix vs {a['name']}: Which App Fits You? | Kynetix",
               f"Kynetix vs {a['name']}, compared honestly: what each app is for, who should pick which, and what Kynetix does for Indian food and gym training.",
               body, ld, og="og-compare.png", og_alt="Kynetix comparisons")
    path = "compare/"
    trail = [("Kynetix", ""), ("Compare", path)]
    lis = "".join(f'<li><a href="{BASE}compare/{a["slug"]}/"><b>Kynetix vs {e(a["name"])}</b><span>{e(a["name"])} is a {e(a["kind"])}.</span></a></li>' for a in APPS)
    body = (crumbs_html(trail, "en") + '<header class="c-head"><p class="kicker">Compare</p><h1 class="c-h1">How Kynetix compares</h1>'
            '<p class="answer">Neutral, short comparisons with popular nutrition and workout apps: what each is for and who should pick which. We state facts about Kynetix and point you to the others\' own listings for theirs.</p></header>'
            f'<ul class="food-list cards-list">{lis}</ul>')
    render(path, "en", "Kynetix Compared: HealthifyMe, MyFitnessPal, Hevy, Strong | Kynetix",
           "Honest comparisons of Kynetix with HealthifyMe, MyFitnessPal, Hevy and Strong: what each app is for and who should choose which.",
           body, [breadcrumb_ld(path, trail)], og="og-compare.png", og_alt="Kynetix comparisons")
