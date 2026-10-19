"""Every native Kynetix brand asset from one geometry: the Shear K.

Font units (Bricolage 800, y down from the ascender): cap top 270, baseline
930, K box x 50..576, K advance in the word 564. The cut is at 590 with a
22 unit gap, the top half shifts 70, the ember runs from -170 to 634 at
y 601, 17.6 thick. These match KShear in lib/ui/k_brand_intro.dart.
"""
import io, json, os, shutil, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
APP = r'C:\Users\Dhruv\Desktop\Kynetix\kynetix_ui'
RES = os.path.join(APP, r'android\app\src\main\res')
OUT = r'C:\Users\Dhruv\Desktop\Kynetix-logo-concepts\shear-final'
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
G = json.load(open(os.path.join(HERE, 'glyphs.json')))
K = G['K']['glyphs'][0]['d']
WORD = G['upper']

GRAPHITE, BONE, EMBER, INK, BURNT, PAPER = '#0B0B0C', '#F2F1EC', '#FF6A3D', '#151515', '#B8401A', '#F4F3EF'
CUT, GAP, SHIFT, TRAIL, EMBER_Y, EMBER_H, K_RIGHT = 590, 22, 70, 170, 601, 17.6, 564
EMBER_L, EMBER_R = -TRAIL, K_RIGHT + SHIFT
# The mark's box (ember caps included) and the K's own cap centre.
BOX = (EMBER_L - EMBER_H / 2, 270, 576 + SHIFT, 930)
BOX_C = ((BOX[0] + BOX[2]) / 2, (BOX[1] + BOX[3]) / 2)
K_C = (313, 600)

TOP_CLIP = f'M-2000,-2000 H6000 V{CUT} H-2000 Z'
BOT_CLIP = f'M-2000,{CUT + GAP} H6000 V3000 H-2000 Z'
BOT_CLIP_CLOSED = f'M-2000,{CUT} H6000 V3000 H-2000 Z'


def ember_rect():
    r = EMBER_H / 2
    y0, y1 = EMBER_Y - r, EMBER_Y + r
    return (f'M{EMBER_L},{y0} H{EMBER_R} A{r},{r} 0 0 1 {EMBER_R},{y1} H{EMBER_L} A{r},{r} 0 0 1 {EMBER_L},{y0} Z')


# ── SVG (for PNG renders and emails) ─────────────────────────────────────────
def svg_mark(ink, ember, word=False, uid='m'):
    paths = ''.join(f'<path d="{g["d"]}"/>' for g in WORD['glyphs']) if word else f'<path d="{K}"/>'
    right = (WORD['glyphs'][-1]['box'][2] if word else 576) + SHIFT
    vb = (BOX[0] - 10, 250, right - BOX[0] + 20, 700)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb[0]} {vb[1]} {vb[2]} {vb[3]}">'
            f'<defs><clipPath id="t{uid}"><path d="{TOP_CLIP}"/></clipPath><clipPath id="b{uid}"><path d="{BOT_CLIP}"/></clipPath></defs>'
            f'<path d="{ember_rect()}" fill="{ember}"/>'
            f'<g fill="{ink}" clip-path="url(#b{uid})">{paths}</g>'
            f'<g fill="{ink}" clip-path="url(#t{uid})"><g transform="translate({SHIFT} 0)">{paths}</g></g></svg>')


def render(svg, path, w, h, bg='transparent', radius=0, pad=0.0):
    html = os.path.join(HERE, '_g.html')
    io.open(html, 'w', encoding='utf-8').write(
        f'<!doctype html><meta charset="utf-8"><style>html,body{{margin:0;background:transparent}}'
        f'.t{{width:{w}px;height:{h}px;background:{bg};border-radius:{radius}px;display:grid;place-items:center;overflow:hidden}}'
        f'.t svg{{width:{(1 - 2 * pad) * 100}%;height:{(1 - 2 * pad) * 100}%}}</style><div class="t">{svg}</div>')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000',
                    f'--window-size={w},{h}', f'--screenshot={path}', 'file:///' + html.replace('\\', '/')],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90)


# ── Android vector drawables ─────────────────────────────────────────────────
def vd_groups(ink, ember, s, tx, ty, names=False):
    # names=True is the animated splash: everything starts at its first frame
    # (K clear, no blade, no cut, no shift); the animators take it from there.
    n = (lambda x: f' android:name="{x}"') if names else (lambda x: '')
    trim = ' android:trimPathEnd="0"' if names else ''
    alpha = ' android:fillAlpha="0"' if names else ''
    shift = 0 if names else SHIFT
    bot = BOT_CLIP_CLOSED if names else BOT_CLIP
    return f'''    <group{n("mark")} android:translateX="{tx:.3f}" android:translateY="{ty:.3f}" android:scaleX="{s:.5f}" android:scaleY="{s:.5f}">
        <group{n("bottom")}>
            <clip-path{n("bottomClip")} android:pathData="{bot}"/>
            <path{n("kBottom")} android:fillColor="{ink}" android:pathData="{K}"{alpha}/>
        </group>
        <group{n("top")} android:translateX="{shift}">
            <clip-path android:pathData="{TOP_CLIP}"/>
            <path{n("kTop")} android:fillColor="{ink}" android:pathData="{K}"{alpha}/>
        </group>
        <!-- The ember last, so it reads as the cut across the K. -->
        <path{n("ember")} android:pathData="M{EMBER_L},{EMBER_Y} L{EMBER_R},{EMBER_Y}" android:strokeColor="{ember}" android:strokeWidth="{EMBER_H}" android:strokeLineCap="round"{trim}/>
    </group>'''


def vector(size_dp, viewport, ink, ember, fit_w, comment):
    s = fit_w / (BOX[2] - BOX[0])
    tx, ty = viewport / 2 - BOX_C[0] * s, viewport / 2 - BOX_C[1] * s
    return (f'<?xml version="1.0" encoding="utf-8"?>\n<!-- {comment} Generated from the Shear geometry; see KShear. -->\n'
            f'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="{size_dp}dp" android:height="{size_dp}dp"'
            f' android:viewportWidth="{viewport}" android:viewportHeight="{viewport}">\n{vd_groups(ink, ember, s, tx, ty)}\n</vector>\n')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, 'w', encoding='utf-8', newline='\n').write(text)


# Adaptive icon: 108 dp canvas, 66 dp safe zone. Mark 60 dp wide.
for f in os.listdir(RES):
    p = os.path.join(RES, f, 'ic_launcher_foreground.png')
    if os.path.exists(p):
        os.remove(p)
write(os.path.join(RES, 'drawable', 'ic_launcher_foreground.xml'),
      vector(108, 108, BONE, EMBER, 52, 'Launcher icon foreground: the Shear K.'))
write(os.path.join(RES, 'drawable', 'ic_launcher_monochrome.xml'),
      vector(108, 108, '#FFFFFF', '#FFFFFF', 52, 'Themed (Android 13+) launcher icon: one tone.'))
write(os.path.join(RES, 'values', 'colors.xml'),
      '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#0B0B0C</color>\n</resources>\n')
write(os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml'),
      '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '  <background android:drawable="@color/ic_launcher_background"/>\n'
      '  <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
      '  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n</adaptive-icon>\n')
# Notification icon: white on transparent, 24 dp.
write(os.path.join(RES, 'drawable', 'ic_stat_kynetix.xml'),
      vector(24, 24, '#FFFFFF', '#FFFFFF', 21, 'Notification small icon: the Shear K, one tone.'))

# Splash: the same K the Flutter intro starts from (158 dp type, cap centre in
# the middle of a 288 dp icon).
S = 0.158
TX, TY = 144 - K_C[0] * S, 144 - K_C[1] * S
write(os.path.join(RES, 'drawable', 'splash_mark.xml'),
      f'<?xml version="1.0" encoding="utf-8"?>\n<!-- The finished splash K (pre-Android 12 launch screen). Matches KShear.splashFontSize. -->\n'
      f'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="288dp" android:height="288dp"'
      f' android:viewportWidth="288" android:viewportHeight="288">\n{vd_groups(BONE, EMBER, S, TX, TY)}\n</vector>\n')

# Animated splash icon (Android 12+): the K appears, the blade slices it, the
# top half shears. 900 ms, ending exactly on splash_mark.
anim_vec = vd_groups(BONE, EMBER, S, TX, TY, names=True)
avd = f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Android 12+ splash icon: the K settles in, an ember blade slices it left
     to right, then the top half shears forward. Ends on the same K the
     Flutter intro (KBrandIntro) starts from. Generated; see KShear. -->
<animated-vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt">
    <aapt:attr name="android:drawable">
        <vector android:width="288dp" android:height="288dp" android:viewportWidth="288" android:viewportHeight="288">
            <group android:name="settle" android:pivotX="144" android:pivotY="144">
{anim_vec}
            </group>
        </vector>
    </aapt:attr>
    <target android:name="settle">
        <aapt:attr name="android:animation">
            <set>
                <objectAnimator android:propertyName="scaleX" android:valueFrom="0.84" android:valueTo="1" android:duration="340"
                    android:interpolator="@android:interpolator/decelerate_cubic"/>
                <objectAnimator android:propertyName="scaleY" android:valueFrom="0.84" android:valueTo="1" android:duration="340"
                    android:interpolator="@android:interpolator/decelerate_cubic"/>
            </set>
        </aapt:attr>
    </target>
    <target android:name="kBottom">
        <aapt:attr name="android:animation">
            <objectAnimator android:propertyName="fillAlpha" android:valueFrom="0" android:valueTo="1" android:duration="300"/>
        </aapt:attr>
    </target>
    <target android:name="kTop">
        <aapt:attr name="android:animation">
            <objectAnimator android:propertyName="fillAlpha" android:valueFrom="0" android:valueTo="1" android:duration="300"/>
        </aapt:attr>
    </target>
    <target android:name="ember">
        <aapt:attr name="android:animation">
            <objectAnimator android:propertyName="trimPathEnd" android:valueFrom="0" android:valueTo="1" android:startOffset="300"
                android:duration="300" android:interpolator="@android:interpolator/fast_out_slow_in"/>
        </aapt:attr>
    </target>
    <target android:name="top">
        <aapt:attr name="android:animation">
            <objectAnimator android:propertyName="translateX" android:valueFrom="0" android:valueTo="{SHIFT}" android:startOffset="600"
                android:duration="280" android:interpolator="@android:interpolator/overshoot"/>
        </aapt:attr>
    </target>
</animated-vector>
'''
write(os.path.join(RES, 'drawable', 'avd_splash.xml'), avd)

# Pre-12 launch screen: graphite with the finished splash K.
lb = ('<?xml version="1.0" encoding="utf-8"?>\n<!-- Graphite with the Shear K, the same K the Flutter intro starts from. -->\n'
      '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <item><color android:color="#0B0B0C"/></item>\n'
      '    <item android:gravity="center" android:width="288dp" android:height="288dp" android:drawable="@drawable/splash_mark"/>\n'
      '</layer-list>\n')
for d in ('drawable', 'drawable-night', 'drawable-v21', 'drawable-night-v21'):
    if os.path.exists(os.path.join(RES, d, 'launch_background.xml')):
        write(os.path.join(RES, d, 'launch_background.xml'), lb)

# ── PNGs ─────────────────────────────────────────────────────────────────────
icon_svg = svg_mark(BONE, EMBER, uid='i')
# Legacy launcher PNGs (rounded square, full bleed graphite).
for d, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    render(icon_svg, os.path.join(RES, f'mipmap-{d}', 'ic_launcher.png'), px, px, GRAPHITE, int(px * 0.22), 0.2)
# Store, web and app branding.
render(icon_svg, os.path.join(OUT, 'play-store-icon-512.png'), 512, 512, GRAPHITE, 0, 0.2)
render(icon_svg, os.path.join(OUT, 'app-icon-1024.png'), 1024, 1024, GRAPHITE, 230, 0.2)
render(icon_svg, os.path.join(APP, r'assets\branding\kynetix_icon.png'), 1024, 1024, GRAPHITE, 0, 0.2)
render(icon_svg, os.path.join(APP, r'assets\branding\kynetix_icon_fg.png'), 1024, 1024, GRAPHITE, 0, 0.2)
render(icon_svg, os.path.join(APP, r'assets\branding\kynetix_icon_padded.png'), 1024, 1024, 'transparent', 0, 0.3)
word_dark = svg_mark(BONE, EMBER, word=True, uid='w')
word_light = svg_mark(INK, BURNT, word=True, uid='l')
render(word_dark, os.path.join(APP, r'assets\branding\kynetix_logo.png'), 1600, 400, 'transparent', 0, 0.04)
render(word_dark, os.path.join(APP, r'assets\branding\kynetix_logo_padded.png'), 1600, 1600, 'transparent', 0, 0.22)
render(word_dark, os.path.join(OUT, 'kynetix-wordmark-on-dark.png'), 1600, 400, GRAPHITE, 0, 0.06)
render(word_light, os.path.join(OUT, 'kynetix-wordmark-on-light.png'), 1600, 400, PAPER, 0, 0.06)
render(word_dark, os.path.join(OUT, 'email-wordmark.png'), 960, 240, 'transparent', 0, 0.04)
io.open(os.path.join(OUT, 'kynetix-wordmark.svg'), 'w', encoding='utf-8').write(word_dark)
io.open(os.path.join(OUT, 'kynetix-k.svg'), 'w', encoding='utf-8').write(icon_svg)
# Web.
WEB = os.path.join(APP, 'web')
for name, px, pad, rad in (('Icon-192.png', 192, 0.2, 0), ('Icon-512.png', 512, 0.2, 0),
                           ('Icon-maskable-192.png', 192, 0.28, 0), ('Icon-maskable-512.png', 512, 0.28, 0)):
    render(icon_svg, os.path.join(WEB, 'icons', name), px, px, GRAPHITE, rad, pad)
render(icon_svg, os.path.join(WEB, 'favicon.png'), 64, 64, GRAPHITE, 14, 0.16)
# iOS app icons (full bleed; iOS masks them).
IOS = os.path.join(APP, r'ios\Runner\Assets.xcassets\AppIcon.appiconset')
spec = json.load(open(os.path.join(IOS, 'Contents.json')))
for im in spec['images']:
    if 'filename' not in im:
        continue
    px = round(float(im['size'].split('x')[0]) * float(im['scale'].rstrip('x')))
    render(icon_svg, os.path.join(IOS, im['filename']), px, px, GRAPHITE, 0, 0.2)
print('done')
