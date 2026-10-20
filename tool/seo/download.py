"""/download/: the Android beta, read from site/version.json at build time (and refreshed at runtime by site.js)."""
import json, re, html
import qrcode
from page import SITE, URL

e = html.escape
V = json.loads((SITE / "version.json").read_text(encoding="utf-8"))
LATEST = "https://github.com/dhruvgupta-24/Kynetix/releases/latest"
MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]


def nice_date(d):
    y, m, dd = d.split("-")
    return f"{int(dd)} {MONTHS[int(m) - 1]} {y}"


def qr_svg(text):
    q = qrcode.QRCode(border=2, error_correction=qrcode.constants.ERROR_CORRECT_M)
    q.add_data(text)
    q.make(fit=True)
    m = q.get_matrix()
    n = len(m)
    d = "".join(f"M{x},{y}h1v1h-1z" for y, row in enumerate(m) for x, v in enumerate(row) if v)
    return (f'<svg class="qr" viewBox="0 0 {n} {n}" role="img" aria-label="QR code that opens {e(text)}" shape-rendering="crispEdges">'
            f'<rect width="{n}" height="{n}" fill="#F2F1EC"/><path d="{d}" fill="#0B0B0C"/></svg>')


def main_html():
    v = V
    sha = v["sha256"]
    size = v["size"]
    notes = "".join(f"<li>{e(n)}</li>" for n in v["notes"])
    return f'''<main id="main">
<div class="wrap">
<header class="legal-head dl-head">
<div class="dl-top">
<div class="dl-copy">
<h1 class="shear">Download Kynetix</h1>
<p>The Android beta is here. Free, no ads, and signed by Kynetix. Google Play is coming soon; until then, install it straight from here.</p>
<div class="dl-cta" data-version-root>
<a class="dl-btn" href="{e(v["apk"])}" data-v-href="apk" data-magnetic rel="noopener"><svg class="b-ico" viewBox="0 0 26 26" aria-hidden="true" focusable="false"><path d="M13 3.5v13M7.5 11.5 13 17l5.5-5.5M5 21.5h16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg><span><b>Download for Android</b><small>Most phones (arm64), <span data-v="size.arm64">{e(size["arm64"])}</span></small></span></a>
<p class="dl-alt"><a href="{e(v["apkV7"])}" data-v-href="apkV7">Older phone? Get the armv7 build (<span data-v="size.armv7">{e(size["armv7"])}</span>)</a></p>
<dl class="dl-meta"><div><dt>Version</dt><dd data-v="versionName">{e(v["versionName"])}</dd></div><div><dt>Released</dt><dd data-v-date="released">{e(nice_date(v["released"]))}</dd></div><div><dt>Needs</dt><dd>Android 8 or newer</dd></div></dl>
<p class="dl-badges"><span class="badge ios"><span><small>Google Play</small><b>Coming soon</b></span></span><span class="badge ios"><span><small>iPhone</small><b>On the roadmap</b></span></span></p>
<p class="small">No JavaScript or link not working? Every build is on <a href="{LATEST}">GitHub Releases</a>.</p>
</div>
</div>
<figure class="dl-qr" aria-labelledby="qr-cap">{qr_svg(URL + "download/")}<figcaption id="qr-cap">On a computer? Scan this with your phone to open this page there.</figcaption></figure>
</div>
</header>
<div class="legal-grid">
<aside class="toc"><div class="inner"><details><summary><span class="t-label">On this page</span><span class="t-now" aria-hidden="true"></span></summary><ol><li><a href="#install">How to install</a></li><li><a href="#which">Which build</a></li><li><a href="#check">Check the file</a></li><li><a href="#safe">Is this safe?</a></li><li><a href="#updates">Updates</a></li><li><a href="#play">When it's on Google Play</a></li><li><a href="#iphone">iPhone</a></li><li><a href="#new">What's in this build</a></li></ol></details></div></aside>
<article class="prose">
<h2 id="install">How to install</h2>
<ol class="steps">
<li><span>Tap <strong>Download for Android</strong> above on your phone. Your browser saves the file (it ends in <code>.apk</code>).</span></li>
<li><span>Open the downloaded file from the notification or your Downloads.</span></li>
<li><span>Android asks to allow installing apps from your browser. Tap <strong>Settings</strong>, switch on <strong>Allow from this source</strong>, then go back.</span></li>
<li><span>Tap <strong>Install</strong>. When it finishes, tap <strong>Open</strong> and sign in.</span></li>
<li><span>If Play Protect warns that the app isn't from Play yet, tap <strong>More details</strong> and then <strong>Install anyway</strong>, but only for a file you downloaded from this page.</span></li>
</ol>
<p>Done? You can switch <strong>Allow from this source</strong> back off for your browser in Settings.</p>

<h2 id="which">Which build do I need?</h2>
<p>Almost every phone from the last several years needs the <strong>arm64</strong> build, the big button. Pick the <strong>armv7</strong> build only for an older or very low-cost phone where the arm64 file says "App not installed". Not sure? Try arm64 first; it won't harm anything if it doesn't fit.</p>

<h2 id="check">Check the file (optional)</h2>
<p>Each build has a SHA-256 checksum. If the checksum of the file you downloaded matches, it is exactly the file we published.</p>
<div class="sha"><p><b>arm64</b> <code data-v="sha256.arm64">{e(sha["arm64"])}</code> <button type="button" class="copy" data-copy="sha256.arm64">Copy</button></p>
<p><b>armv7</b> <code data-v="sha256.armv7">{e(sha["armv7"])}</code> <button type="button" class="copy" data-copy="sha256.armv7">Copy</button></p></div>
<p>On a computer: <code>certutil -hashfile file.apk SHA256</code> (Windows) or <code>shasum -a 256 file.apk</code> (Mac and Linux). The full list is in <code>SHA256SUMS.txt</code> on the <a href="{LATEST}">release page</a>.</p>

<h2 id="safe">Is this safe?</h2>
<details class="qa" open><summary><h3>Who made this file?</h3><i aria-hidden="true"></i></summary><div class="qa-a"><p>Kynetix, built and signed by Dhruv Gupta. It's the same app that's going to Google Play, signed with the same key, so it can update in place later.</p></div></details>
<details class="qa"><summary><h3>Why does Android warn me?</h3><i aria-hidden="true"></i></summary><div class="qa-a"><p>Android warns about any app installed from outside an app store. That's a sensible default, not a sign something is wrong. Only install files from this page, and check the SHA-256 if you want to be sure.</p></div></details>
<details class="qa"><summary><h3>What does the app do with my data?</h3><i aria-hidden="true"></i></summary><div class="qa-a"><p>No ads, no selling data and no third-party trackers. Everything is explained in plain words in the <a href="../privacy/">privacy policy</a>, and you can delete your account and data from inside the app.</p></div></details>
<details class="qa"><summary><h3>Does it cost anything?</h3><i aria-hidden="true"></i></summary><div class="qa-a"><p>No. Kynetix is free during early access.</p></div></details>

<h2 id="updates">Updates</h2>
<p>The app checks for a new build and tells you when one is out, with a button that brings you back here. Your data lives in your account, so updating never loses it.</p>

<h2 id="play">When it's on Google Play</h2>
<p>We'll tell you inside the app. Install Kynetix from Google Play, sign in with the same account, and everything is there: your meals, workouts and settings live in your account, not on the phone.</p>

<h2 id="iphone">iPhone</h2>
<p>Not yet. Kynetix is Android first, and an iPhone version is on the roadmap with no date yet.</p>

<h2 id="new">What's in this build</h2>
<ul>{notes}</ul>
<p>Questions or a problem installing? Email <a href="mailto:kynetix.app@gmail.com">kynetix.app@gmail.com</a>, or once you're in, Profile &gt; Talk to us.</p>
</article>
</div>
</div>
</main>
'''


def write():
    f = SITE / "download/index.html"
    f.parent.mkdir(parents=True, exist_ok=True)
    if f.exists():
        s = f.read_text(encoding="utf-8")
    else:
        s = (SITE / "terms/index.html").read_text(encoding="utf-8")
    s = re.sub(r'<main id="main">.*?</main>\n', lambda _: main_html(), s, count=1, flags=re.S)
    f.write_text(s, encoding="utf-8", newline="\n")
