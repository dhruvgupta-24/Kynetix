"""Inject shared chrome (icons, header island, mobile dock, menu, footer) into every site page."""
import re, pathlib

SITE = pathlib.Path(r"C:/Users/Dhruv/Desktop/Kynetix/site")
PAGES = {
    "index.html": dict(p="", home="#top", sec="", cur=None),
    "privacy/index.html": dict(p="../", home="../", sec="../", cur="privacy"),
    "terms/index.html": dict(p="../", home="../", sec="../", cur="terms"),
    "delete-account/index.html": dict(p="../", home="../", sec="../", cur="delete"),
    "about/index.html": dict(p="../", home="../", sec="../", cur="about"),
    "download/index.html": dict(p="../", home="../", sec="../", cur="download"),
    "404.html": dict(p="/Kynetix/", home="/Kynetix/", sec="/Kynetix/", cur=None),
}

ICONS = """<symbol id="i-food" viewBox="0 0 24 24"><path d="M7 3v18M4.5 3v5.2A2.5 2.5 0 0 0 7 10.7a2.5 2.5 0 0 0 2.5-2.5V3M17.5 21V3c-2.2 1.2-3.5 3.6-3.5 6.6V14h3.5"/></symbol>
<symbol id="i-train" viewBox="0 0 24 24"><path d="M6.5 7v10M3.5 9.5v5M17.5 7v10M20.5 9.5v5M6.5 12h11"/></symbol>
<symbol id="i-widget" viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="17" height="7" rx="2"/></symbol>
<symbol id="i-kyno" viewBox="0 0 24 24"><rect x="4" y="7.5" width="16" height="12" rx="4.5"/><path d="M12 7.5V4.5"/><circle cx="12" cy="3.6" r=".9"/><path d="M9.2 13.2v1.4M14.8 13.2v1.4"/></symbol>
<symbol id="i-share" viewBox="0 0 24 24"><path d="M12 14.5V3.5M8 7.2l4-3.7 4 3.7M5.5 12v6.5a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V12"/></symbol>
<symbol id="i-privacy" viewBox="0 0 24 24"><path d="M12 3.2 19 6v5.2c0 4.4-2.9 8.2-7 9.6-4.1-1.4-7-5.2-7-9.6V6Z"/><path d="M9.2 12.1l2 2 3.8-3.9"/></symbol>
<symbol id="i-learn" viewBox="0 0 24 24"><path d="M4 5.5c2.6-.9 5.4-.6 8 1.2 2.6-1.8 5.4-2.1 8-1.2v13c-2.6-.9-5.4-.6-8 1.2-2.6-1.8-5.4-2.1-8-1.2Z"/><path d="M12 6.7v13"/></symbol>
<symbol id="i-down" viewBox="0 0 24 24"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/></symbol>
<symbol id="i-menu" viewBox="0 0 24 24"><path d="M3.5 9h17M7.5 15h13"/></symbol>
<symbol id="i-close" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></symbol>
<symbol id="i-phone" viewBox="0 0 26 26"><rect x="7" y="2.5" width="12" height="21" rx="3.2"/><path d="M11 5.4h4"/></symbol>
<symbol id="i-play" viewBox="0 0 26 26"><path d="M6 3.8v18.4c0 .8.9 1.3 1.6.9l15.2-9.2c.7-.4.7-1.4 0-1.8L7.6 2.9C6.9 2.5 6 3 6 3.8Z"/></symbol>
"""

WM = ('<svg class="bm" viewBox="-188.8 250 3797.8 700" role="img" aria-label="Kynetix">'
      '<path class="bm-cut" d="M-170,592.2 H634 A8.8,8.8 0 0 1 634,609.8 H-170 A8.8,8.8 0 0 1 -170,592.2 Z" fill="#FF6A3D"/>'
      '<use href="#kx" clip-path="url(#cb)"/><g clip-path="url(#ct)"><g class="bm-t"><use href="#kx" transform="translate(70 0)"/></g></g></svg>')


def ico(name):
    return f'<svg class="ico" aria-hidden="true" focusable="false"><use href="#i-{name}"/></svg>'


def links(c, cls):
    s = c["sec"]
    items = [("food", "Food", "food"), ("training", "Train", "train")]
    if cls == "island":
        items.append(("widgets", "Widgets", "widget"))
    items += [("kyno", "Kyno", "kyno"), ("share", "Share", "share")]
    out = []
    for sid, label, icon in items:
        out.append(f'<a href="{s}#{sid}" data-sec="{sid}">{ico(icon)}<span class="lb">{label}</span></a>')
    return out


def header(c):
    p = c["p"]
    dl_cur = ' aria-current="page" class="nav-dl on"' if c["cur"] == "download" else ' class="nav-dl"'
    nav = "".join(links(c, "island")) + '<span class="sep" aria-hidden="true"></span>' + \
        f'<a href="{p}learn/" data-page="learn">{ico("learn")}<span class="lb">Learn</span></a>' + \
        f'<a href="{p}download/" data-page="download"{dl_cur}>{ico("down")}<span class="lb">Download</span></a>'
    dock = "".join(links(c, "")) + \
        f'<button type="button" class="menu-btn" aria-haspopup="dialog" aria-controls="menu" aria-expanded="false">{ico("menu")}<span class="lb">Menu</span></button>'
    menu_links = [
        (f'{c["sec"]}#food', "Food"), (f'{c["sec"]}#training', "Training"), (f'{c["sec"]}#widgets', "Widgets"), (f'{c["sec"]}#kyno', "Kyno"),
        (f'{c["sec"]}#share', "Share cards"), (f"{p}download/", "Download the beta"), (f"{p}foods/", "Food calories"),
        (f"{p}exercises/", "Exercises"), (f"{p}guides/", "Guides"), (f"{p}tools/", "Calculators"), (f"{p}about/", "About and press"),
        (f"{p}privacy/", "Privacy"), (f"{p}terms/", "Terms"), (f"{p}delete-account/", "Delete account"),
    ]
    pill = ('<a class="dl-pill" href="download/"><svg class="ico" aria-hidden="true" focusable="false"><use href="#i-down"/></svg><span>Download the beta</span></a>' + chr(10)
            if c["home"] == "#top" else "")
    ml = "".join(f'<li style="--i:{i}"><a href="{h}">{t}</a></li>' for i, (h, t) in enumerate(menu_links))
    return f'''<a class="skip" href="#main">Skip to content</a>
<header class="top"><div class="island">
<a class="brand" href="{c["home"]}" aria-label="Kynetix home">{WM}</a>
<nav class="links" aria-label="Main"><span class="ind" aria-hidden="true"></span>{nav}</nav>
</div></header>
{pill}<nav class="dock" aria-label="Sections"><span class="ind" aria-hidden="true"></span>{dock}</nav>
<dialog class="menu" id="menu" aria-label="Menu"><div class="menu-in">
<div class="menu-top"><a class="brand" href="{c["home"]}" aria-label="Kynetix home">{WM}</a><button type="button" class="menu-x" aria-label="Close menu">{ico("close")}</button></div>
<ol class="menu-list">{ml}</ol>
<div class="menu-foot"><p>Android beta: download now. Google Play coming soon. iPhone is on the roadmap.</p><a href="mailto:kynetix.app@gmail.com">kynetix.app@gmail.com</a></div>
</div><span class="menu-cut" aria-hidden="true"></span></dialog>'''


def footer(c):
    p = c["p"]
    return f'''<footer class="foot"><div class="wrap">
<div class="foot-a">
<a class="brand" href="{c["home"]}" aria-label="Kynetix home">{WM}</a>
<p>Real food. Real lifts. Made in India by Dhruv Gupta. &copy; 2026</p>
</div>
<p class="talk"><b>Got thoughts?</b> Talk to us inside the app (<span class="path">Profile &gt; Talk to us</span>) or email <a href="mailto:kynetix.app@gmail.com">kynetix.app@gmail.com</a></p>
<nav aria-label="Learn"><ul class="foot-learn">
<li><a href="{p}download/">Download</a></li>
<li><a href="{p}foods/">Food calories</a></li>
<li><a href="{p}exercises/">Exercises</a></li>
<li><a href="{p}guides/">Guides</a></li>
<li><a href="{p}tools/">Calculators</a></li>
<li><a href="{p}compare/">Compare</a></li>
</ul></nav>
<nav aria-label="Footer"><ul>
<li><a href="{p}about/">About and press kit</a></li>
<li><a href="{p}privacy/">Privacy policy</a></li>
<li><a href="{p}terms/">Terms of use</a></li>
<li><a href="{p}delete-account/">Delete your account</a></li>
</ul></nav>
</div></footer>'''


def run():
  for rel, c in PAGES.items():
    f = SITE / rel
    s = f.read_text(encoding="utf-8")
    s = re.sub(r'<symbol id="i-.*?</symbol>\n?', "", s, flags=re.S)
    s = s.replace("</defs></svg>", ICONS + "</defs></svg>", 1)
    s = re.sub(r'<a class="skip".*?</dialog>|<a class="skip".*?</div></header>', lambda m: header(c), s, count=1, flags=re.S)
    s = re.sub(r'<footer class="foot">.*?</footer>', lambda m: footer(c), s, count=1, flags=re.S)
    f.write_text(s, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    run()
