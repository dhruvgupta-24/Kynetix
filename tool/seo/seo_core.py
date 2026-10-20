"""SEO / AEO / GEO build for the Kynetix site: heads, JSON-LD, FAQ, sitemap, robots, llms.txt."""
import json, re, pathlib, html
HOME_ALTS = globals().get("HOME_ALTS", {})
LANG_HREF = globals().get("LANG_HREF", {})

SITE = pathlib.Path(r"C:/Users/Dhruv/Desktop/Kynetix/site")
URL = "https://dhruvgupta-24.github.io/Kynetix/"
VERSION = json.loads((SITE / "version.json").read_text(encoding="utf-8"))
TODAY = "2026-10-20"
EMAIL = "kynetix.app@gmail.com"
REPO = "https://github.com/dhruvgupta-24/Kynetix"

DEFINITION = ("Kynetix is an Android app for calorie, protein and workout tracking, built around Indian food. "
              "You log meals in plain words like \"2 roti and dal\", log your sets and personal records, and ask Kyno, "
              "an AI coach that reads both. It is free during early access, has no ads, and is made in India by Dhruv Gupta.")

FAQ = [
    ("How do I count calories in Indian food like dal and roti?",
     "Type the meal the way you would say it, for example \"2 roti, 1 katori dal, aloo sabzi\", and Kynetix estimates the calories and protein for each item. Indian portions like katori, roti, bowl and plate are understood, and once you correct a portion it remembers how you eat it."),
    ("Is Kynetix free?",
     "Yes. Kynetix is free during early access, with no ads, and your data is never sold."),
    ("What is Kyno?",
     "Kyno is the AI coach inside Kynetix. It reads your recent meals, workouts, steps and weight, then answers questions like what to eat to hit your protein today or how your week is going. Its numbers are estimates and it is not a doctor."),
    ("Does Kynetix work with Health Connect?",
     "Yes. With your permission, Kynetix reads steps, weight, sleep and heart rate variability (HRV) from Health Connect on Android to keep your targets honest. It is read only and never writes to Health Connect."),
    ("Can Kynetix log meals from a photo?",
     "You can send Kyno a photo of your plate or a menu and ask what fits your day. For logging, typing the meal in plain words or scanning a barcode is the quickest and most accurate route, and photos you send are not stored."),
    ("Can I scan barcodes on packaged food?",
     "Yes. Scan the barcode and Kynetix looks the product up on Open Food Facts, so you log the exact pack. You can also save your own products and quick-add meals you eat often."),
    ("Does Kynetix track workouts and personal records?",
     "Yes. Log sets, reps and weight with rest timers, follow a split like push pull legs, and Kynetix spots personal records as you lift. Kyno suggests the next weight from your own history."),
    ("Does Kynetix have home screen widgets?",
     "Yes. There are four Android home screen widgets, 2x2, 4x2, 2x4 and 4x4, showing the calories and protein you have left, with macros and a Log meal button on the larger sizes."),
    ("Is my data private, and can I delete my account?",
     "Yes. There are no ads, no data selling and no third-party trackers or analytics; simple usage stats stay in Kynetix's own database. You can delete your account and all of its data from inside the app at any time, or by email using the delete account page."),
    ("Is Kynetix available on iPhone?",
     "Not yet. Kynetix is Android first, and an iPhone version is on the roadmap with no date yet."),
    ("Can I download Kynetix now?",
     "Yes. The Android beta is free to download from the Kynetix download page as an APK, with step-by-step install instructions. Google Play is coming soon; when it arrives, you sign in with the same account and everything is there."),
    ("When will Kynetix be on Google Play?",
     "Soon, with no public date yet. Until then, the Android beta installs from the Kynetix download page, and the app tells you when the Play version is live."),
    ("Who makes Kynetix?",
     "Kynetix is made by Dhruv Gupta, an independent developer in India. You can reach him at kynetix.app@gmail.com, or from inside the app under Profile > Talk to us."),
]

PAGES = {
    "index.html": dict(
        path="", p="",
        title="Kynetix: Indian Calorie Counter and Workout Tracker App",
        desc="Kynetix is an Android calorie and workout tracker built for Indian food. Log meals in plain words, track sets and PRs, and ask Kyno, an AI coach. Free.",
        og="og-home.png", og_alt="The Kynetix wordmark above the words Real food. Real lifts. Calorie, protein and workout tracker for Indian food."),
    "privacy/index.html": dict(
        path="privacy/", p="../", crumb="Privacy policy",
        title="Privacy Policy | Kynetix Calorie and Workout Tracker",
        desc="How Kynetix handles your data: what it collects, the AI providers involved, Health Connect, retention, deletion and your rights under India's DPDP Act.",
        og="og-privacy.png", og_alt="Kynetix privacy policy: what Kynetix collects, why, who it goes to, and how to delete it."),
    "terms/index.html": dict(
        path="terms/", p="../", crumb="Terms of use",
        title="Terms of Use | Kynetix Calorie and Workout Tracker App",
        desc="The terms for using Kynetix, the Android calorie and workout tracker: 18 and over, not medical advice, AI can be wrong, fair use and Indian law.",
        og="og-terms.png", og_alt="Kynetix terms of use: short, plain-language rules for using the app."),
    "delete-account/index.html": dict(
        path="delete-account/", p="../", crumb="Delete your account",
        title="Delete Your Kynetix Account and Data | Kynetix Help",
        desc="How to delete your Kynetix account and all of its data, in the app in four taps or by email, plus exactly what is deleted and what is kept, and for how long.",
        og="og-delete.png", og_alt="Delete your Kynetix account and all its data, in the app or by email."),
    "about/index.html": dict(
        path="about/", p="../", crumb="About and press kit", about=True,
        title="About Kynetix: Press Kit, Key Facts, Founder and Contact",
        desc="About Kynetix, the Android calorie and workout tracker for Indian food: key facts, what it does, founder Dhruv Gupta, brand files, screenshots and contact.",
        og="og-about.png", og_alt="About Kynetix press kit: facts, founder, contact, brand files and screenshots."),
    "download/index.html": dict(
        path="download/", p="../", crumb="Download",
        title="Download Kynetix for Android (Free Beta APK) | Kynetix",
        desc="Download the free Kynetix Android beta: the APK, how to install it step by step, SHA-256 checksums, and what happens when it arrives on Google Play.",
        og="og-download.png", og_alt="Download the Kynetix Android beta."),
    "404.html": dict(
        path=None, p="/Kynetix/",
        title="Page not found | Kynetix",
        desc="This page does not exist. Head back to Kynetix, the Android calorie and workout tracker built for Indian food.",
        og="og.png", og_alt="The Kynetix wordmark, cut through the middle with an ember line."),
}

for k, c in PAGES.items():
    if c["path"] is not None:
        assert 50 <= len(c["title"]) <= 60, (k, len(c["title"]))
        assert 140 <= len(c["desc"]) <= 160, (k, len(c["desc"]))

ORG = {"@type": "Organization", "@id": URL + "#org", "name": "Kynetix", "url": URL,
       "logo": {"@type": "ImageObject", "url": URL + "assets/img/icon-512.png", "width": 512, "height": 512},
       "email": EMAIL, "founder": {"@id": URL + "#founder"}, "sameAs": [REPO],
       "contactPoint": {"@type": "ContactPoint", "email": EMAIL, "contactType": "customer support", "availableLanguage": ["English"]}}
PERSON = {"@type": "Person", "@id": URL + "#founder", "name": "Dhruv Gupta", "jobTitle": "Founder and developer",
          "worksFor": {"@id": URL + "#org"}, "homeLocation": {"@type": "Country", "name": "India"}}
WEBSITE = {"@type": "WebSite", "@id": URL + "#website", "url": URL, "name": "Kynetix", "inLanguage": "en-IN",
           "description": "Official website of Kynetix, an Android calorie and workout tracker built for Indian food.",
           "publisher": {"@id": URL + "#org"}}
APP = {"@type": "MobileApplication", "@id": URL + "#app", "name": "Kynetix", "url": URL,
       "description": DEFINITION, "operatingSystem": "Android", "applicationCategory": "HealthApplication",
       "applicationSubCategory": "Calorie counter and workout tracker", "inLanguage": "en-IN",
       "image": URL + "assets/img/og-home.png",
       "screenshot": [URL + "assets/press/kynetix-" + n + ".jpg" for n in ["home", "meal", "workout", "kyno-answer", "train", "done"]],
       "featureList": ["Log Indian meals in plain words", "Barcode scanning with Open Food Facts", "Calorie and protein targets that follow training days",
                       "Workout logging with sets, reps, rest timers and personal records", "Kyno, an AI coach that reads meals and workouts",
                       "Health Connect: steps, weight, sleep and HRV, read only", "Home screen widgets in four sizes", "Share cards for finished sessions"],
       "offers": {"@type": "Offer", "price": "0", "priceCurrency": "INR", "availability": "https://schema.org/InStock",
                  "description": "Free during early access. Android beta available to download now; Google Play coming soon."},
       "downloadUrl": VERSION["apk"], "installUrl": URL + "download/", "softwareVersion": VERSION["versionName"],
       "fileSize": VERSION["size"]["arm64"], "datePublished": VERSION["released"], "releaseNotes": " ".join(VERSION["notes"]),
       "author": {"@id": URL + "#founder"}, "publisher": {"@id": URL + "#org"}, "countriesSupported": "IN"}


def page_url(c):
    return URL + c["path"]


def ld_for(key, c):
    u = page_url(c)
    graph = [ORG, PERSON, WEBSITE]
    if key == "index.html":
        graph += [APP,
                  {"@type": "WebPage", "@id": u + "#webpage", "url": u, "name": c["title"], "description": c["desc"],
                   "inLanguage": "en-IN", "isPartOf": {"@id": URL + "#website"}, "about": {"@id": URL + "#app"},
                   "primaryImageOfPage": {"@type": "ImageObject", "url": URL + "assets/img/" + c["og"], "width": 1200, "height": 630},
                   "dateModified": TODAY},
                  {"@type": "FAQPage", "@id": u + "#faq", "url": u + "#faq", "inLanguage": "en-IN", "isPartOf": {"@id": u + "#webpage"},
                   "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in FAQ]}]
    else:
        graph += [{"@type": "AboutPage" if c.get("about") else "WebPage", "@id": u + "#webpage", "url": u, "name": c["title"],
                   "description": c["desc"], "inLanguage": "en-IN", "isPartOf": {"@id": URL + "#website"},
                   "about": {"@id": URL + ("#org" if c.get("about") else "#app")}, "breadcrumb": {"@id": u + "#breadcrumb"},
                   "primaryImageOfPage": {"@type": "ImageObject", "url": URL + "assets/img/" + c["og"], "width": 1200, "height": 630},
                   "dateModified": TODAY},
                  {"@type": "BreadcrumbList", "@id": u + "#breadcrumb", "itemListElement": [
                      {"@type": "ListItem", "position": 1, "name": "Kynetix", "item": URL},
                      {"@type": "ListItem", "position": 2, "name": c["crumb"], "item": u}]}]
        if key == "download/index.html":
            graph.append(APP)
    return {"@context": "https://schema.org", "@graph": graph}


def head(key, c, inline_script):
    p = c["p"]
    e = html.escape
    out = ['<meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
           f'<title>{e(c["title"])}</title>',
           f'<meta name="description" content="{e(c["desc"])}">']
    if c["path"] is None:
        out.append('<meta name="robots" content="noindex, follow">')
    else:
        u = page_url(c)
        out += ['<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">',
                f'<link rel="canonical" href="{u}">',
                *([f'<link rel="alternate" hreflang="{LANG_HREF[l]}" href="{URL}{pth}">' for l, pth in HOME_ALTS.items()] + [f'<link rel="alternate" hreflang="x-default" href="{u}">']
                  if key == "index.html" and HOME_ALTS else
                  [f'<link rel="alternate" hreflang="en-IN" href="{u}">', f'<link rel="alternate" hreflang="x-default" href="{u}">'])]
    og_url = page_url(c) if c["path"] is not None else URL
    img = URL + "assets/img/" + c["og"]
    out += ['<meta name="author" content="Dhruv Gupta">',
            '<meta name="theme-color" content="#0B0B0C">',
            '<meta name="color-scheme" content="dark">',
            '<meta property="og:type" content="website">',
            '<meta property="og:site_name" content="Kynetix">',
            '<meta property="og:locale" content="en_IN">',
            f'<meta property="og:title" content="{e(c["title"])}">',
            f'<meta property="og:description" content="{e(c["desc"])}">',
            f'<meta property="og:url" content="{og_url}">',
            f'<meta property="og:image" content="{img}">',
            '<meta property="og:image:type" content="image/png">',
            '<meta property="og:image:width" content="1200">',
            '<meta property="og:image:height" content="630">',
            f'<meta property="og:image:alt" content="{e(c["og_alt"])}">',
            '<meta name="twitter:card" content="summary_large_image">',
            f'<meta name="twitter:title" content="{e(c["title"])}">',
            f'<meta name="twitter:description" content="{e(c["desc"])}">',
            f'<meta name="twitter:image" content="{img}">',
            f'<meta name="twitter:image:alt" content="{e(c["og_alt"])}">',
            f'<link rel="icon" href="{p}favicon.ico" sizes="48x48">',
            f'<link rel="icon" href="{p}assets/img/favicon.svg" type="image/svg+xml">',
            f'<link rel="apple-touch-icon" href="{p}assets/img/apple-touch-icon.png">',
            f'<link rel="manifest" href="{p}site.webmanifest">',
            f'<link rel="preload" href="{p}assets/fonts/bricolage-800.woff2" as="font" type="font/woff2" crossorigin>',
            f'<link rel="preload" href="{p}assets/fonts/inter-400.woff2" as="font" type="font/woff2" crossorigin>',
            f'<link rel="stylesheet" href="{p}assets/css/site.css">',
            inline_script]
    if c["path"] is not None:
        out.append('<script type="application/ld+json">' + json.dumps(ld_for(key, c), ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/") + '</script>')
    return "<head>\n" + "\n".join(out) + "\n</head>"


def faq_html():
    items = []
    for i, (q, a) in enumerate(FAQ):
        items.append(f'<details class="qa"{" open" if i == 0 else ""}><summary><h3>{html.escape(q)}</h3><i aria-hidden="true"></i></summary>'
                     f'<div class="qa-a"><p>{html.escape(a)}</p></div></details>')
    return ('<!-- faq -->\n<section class="sec faq" id="faq" aria-labelledby="faq-title">\n<div class="wrap faq-grid">\n'
            '<div class="sec-head">\n<p class="kicker">Questions</p>\n<h2 class="shear" id="faq-title">Straight answers</h2>\n'
            '<p data-reveal>The things people ask before they install. Short answers first, details after.</p>\n'
            '<p class="faq-more" data-reveal>Something else? Email <a href="mailto:kynetix.app@gmail.com">kynetix.app@gmail.com</a> or read the <a href="about/">press kit</a>.</p>\n'
            '</div>\n<div class="faq-list">\n' + "\n".join(items) + '\n</div>\n</div>\n</section>\n<!-- /faq -->\n')


def what_html():
    return ('<!-- what -->\n<section class="what" id="what" aria-labelledby="what-title">\n<div class="wrap what-in">\n'
            '<h2 id="what-title">What is Kynetix?</h2>\n<p>' + html.escape(DEFINITION, quote=False) + '</p>\n'
            '<ul class="facts" aria-label="Kynetix at a glance"><li><b>Platform</b>Android, iPhone later</li><li><b>Price</b>Free in early access</li>'
            '<li><b>Status</b>Android beta, download now</li><li><b>Made by</b>Dhruv Gupta, India</li></ul>\n'
            '</div>\n</section>\n<!-- /what -->\n')


for key, c in PAGES.items():
    f = SITE / key
    s = f.read_text(encoding="utf-8")
    m = re.search(r"<script>\(function\(d\).*?</script>", s, re.S)
    assert m, key
    s = re.sub(r"<head>.*?</head>", lambda _: head(key, c, m.group(0)), s, count=1, flags=re.S)
    if key == "index.html":
        s = re.sub(r"<!-- faq -->.*?<!-- /faq -->\n", "", s, flags=re.S)
        s = re.sub(r"<!-- what -->.*?<!-- /what -->\n", "", s, flags=re.S)
        anchor = '<section class="sec close"'
        assert anchor in s
        s = s.replace(anchor, faq_html() + "\n" + anchor, 1)
        anchor2 = '<section class="story"'
        assert anchor2 in s
        s = s.replace(anchor2, what_html() + "\n" + anchor2, 1)
    f.write_text(s, encoding="utf-8", newline="\n")
    print("head", key, len(c["title"]), len(c["desc"]))

# sitemap
urls = ["", "about/", "privacy/", "terms/", "delete-account/"]
sm = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">']
for u in urls:
    sm.append(f'  <url><loc>{URL}{u}</loc><lastmod>{TODAY}</lastmod><xhtml:link rel="alternate" hreflang="en-IN" href="{URL}{u}"/><xhtml:link rel="alternate" hreflang="x-default" href="{URL}{u}"/></url>')
sm.append("</urlset>\n")
(SITE / "sitemap.xml").write_text("\n".join(sm), encoding="utf-8", newline="\n")

bots = ["Googlebot", "Bingbot", "DuckDuckBot", "Applebot", "YandexBot", "GPTBot", "OAI-SearchBot", "ChatGPT-User", "PerplexityBot",
        "Perplexity-User", "ClaudeBot", "Claude-User", "Claude-SearchBot", "anthropic-ai", "Google-Extended", "Applebot-Extended", "CCBot",
        "Meta-ExternalAgent", "Amazonbot", "cohere-ai", "MistralAI-User"]
rb = ["# Kynetix welcomes search engines and AI assistants.", "# Facts for AI systems: " + URL + "llms.txt", ""]
for b in bots:
    rb += [f"User-agent: {b}", "Allow: /", ""]
rb += ["User-agent: *", "Allow: /", "", f"Sitemap: {URL}sitemap.xml", ""]
(SITE / "robots.txt").write_text("\n".join(rb), encoding="utf-8", newline="\n")

facts = [
    "Name: Kynetix. The AI coach inside it is called Kyno.",
    "What it is: an Android app for calorie, protein and workout tracking, built around Indian food.",
    "Platform: Android. iPhone is on the roadmap, no date yet.",
    "Status: Android beta available now as a free APK from " + URL + "download/ . Google Play coming soon, no public date yet.",
    "Price: free during early access. No ads.",
    "Made by: Dhruv Gupta, an independent developer in India.",
    "Contact: " + EMAIL + ", or in the app under Profile > Talk to us.",
    "Age: 18 and over.",
    "Privacy: no ads, no data selling, no third-party analytics or ad SDKs. Simple in-house usage analytics (screen opens, meals logged, workouts finished) stay in Kynetix's own database and are deleted with the account. Account and data deletion inside the app.",
    "Health Connect: reads steps, weight, sleep and HRV with permission. Read only, never writes.",
    "AI: meal estimates and Kyno use AI providers (Gemini, Groq, OpenRouter, or the user's own ChatGPT if linked). Estimates, not medical advice.",
    "Source code: " + REPO,
]
links = [
    ("Home", "", "What Kynetix does: food logging in plain words, training, Kyno, widgets, share cards, FAQ."),
    ("About and press kit", "about/", "Key facts, founder, brand files, screenshots and contact."),
    ("Privacy policy", "privacy/", "What is collected, why, AI providers, retention, deletion and rights under India's DPDP Act."),
    ("Terms of use", "terms/", "Rules for using Kynetix: 18 and over, not medical advice, AI can be wrong."),
    ("Delete your account", "delete-account/", "How to delete a Kynetix account and its data, in the app or by email."),
]
llms = ["# Kynetix", "", "> " + DEFINITION, "", "## Key facts", ""] + ["- " + x for x in facts] + ["", "## Pages", ""] + \
       [f"- [{t}]({URL}{u}): {d}" for t, u, d in links] + ["", "## Optional", "",
       f"- [Full text for AI systems]({URL}llms-full.txt): every fact and FAQ answer in one file.",
       f"- [Source code]({REPO}): the Flutter app, Supabase backend and this website.", ""]
(SITE / "llms.txt").write_text("\n".join(llms), encoding="utf-8", newline="\n")

full = ["# Kynetix: full reference for AI systems", "", "> " + DEFINITION, "", f"Website: {URL}", f"Last updated: {TODAY}", "",
        "## Key facts", ""] + ["- " + x for x in facts] + ["", "## What it does", "",
        "- Food: log meals in your own words (\"2 roti, 1 katori dal, aloo sabzi\"). Indian portions like katori, roti, bowl and plate are understood. Corrections are remembered.",
        "- Barcode scanning for packaged food via Open Food Facts, plus saved products and quick-adds.",
        "- Targets: calorie and protein targets from body, goal and training; slightly higher on training days.",
        "- Training: splits, sets, reps, rest timers, supersets, warm-ups, automatic personal record detection, progression charts and a muscle map.",
        "- Kyno: an AI coach that reads the last two weeks of meals, lifts, steps and weight. Accepts photos of a plate or menu. Photos are not stored. Not a doctor.",
        "- Health Connect: steps, weight, sleep and HRV, read only.",
        "- Home screen widgets: 2x2 (rings), 4x2 (rings plus carbs, fat, fiber), 2x4 (every macro plus Log meal), 4x4 (the whole day).",
        "- Share cards: Poster, Receipt, Skyline, In real terms, Sticker; story or post size; graphite, paper or your own photo.",
        "- Feedback: from anywhere in the app (Profile > Talk to us).",
        "", "## Frequently asked questions", ""]
for q, a in FAQ:
    full += ["### " + q, "", a, ""]
full += ["## Pages", ""] + [f"- [{t}]({URL}{u}): {d}" for t, u, d in links] + [""]
(SITE / "llms-full.txt").write_text("\n".join(full), encoding="utf-8", newline="\n")
print("done")
