"""The launch intro as one Android animated vector (avd_intro.xml).

It runs on Android's RenderThread, so app startup work on the Flutter
threads can't make it stutter. It starts exactly where the system splash
(avd_splash) ends: the sheared K, 158 dp type, cap centre on the window
centre. Then the K glides and shrinks into its place in the word, the tail
slides out from behind it, an ember blade runs across the word shearing
each letter as it passes, and the blade draws back into the K's own cut.

Coordinates: the vector is 360 x 360 dp, centred in the window. The word is
set at 88 dp type (311 dp wide), its cap centre on the window centre.
"""
import io, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
RES = r'C:\Users\Dhruv\Desktop\Kynetix\kynetix_ui\android\app\src\main\res'
G = json.load(open(os.path.join(HERE, 'glyphs.json')))
WORD = G['upper']['glyphs']

BONE, EMBER = '#F2F1EC', '#FF6A3D'
CUT, GAP, SHIFT, TRAIL, EMBER_Y, EMBER_H = 590, 22, 70, 170, 601, 17.6
K_RIGHT = 564
EMBER_L, EMBER_R = -TRAIL, K_RIGHT + SHIFT

SIZE = 360.0                 # dp, the vector's box
F = 88.0                     # dp, the word's type size
S = F / 1000                 # dp per font unit
SPLASH = 0.158               # dp per font unit of the splash K
TEXT_L, TEXT_R = 0, 3538     # the word's advance box
CAP_C = 600                  # cap centre (font units)
K_C = (313, 600)
WORD_R = WORD[-1]['box'][2]  # 3529
BLADE_END = WORD_R + 40

# Word group: font units -> dp, text centred, cap centre on the box centre.
TX = SIZE / 2 - (TEXT_L + TEXT_R) / 2 * S
TY = SIZE / 2 - CAP_C * S
CENTRE_U = ((TEXT_L + TEXT_R) / 2, CAP_C)   # the window centre, in font units

# The halves overlap by 2 units so no antialiased seam shows on uncut letters.
TOP_CLIP = f'M-4000,-4000 H8000 V{CUT + GAP + 1} H-4000 Z'
BOT_CLIP = f'M-4000,{CUT + GAP - 1} H8000 V8000 H-4000 Z'

# Timeline (ms after the splash hands over).
GLIDE = (0, 520)
LETTERS = (470, 1030)  # once the K has all but landed
BLADE = (960, 1480)
TRIM = (1500, 1780)
SNAP = 170

IN_OUT_CUBIC = (0.65, 0, 0.35, 1)
OUT_EXPO = (0.16, 1, 0.3, 1)
OUT_BACK = (0.34, 1.56, 0.64, 1)


def bez(c):
    return (f'<aapt:attr name="android:interpolator"><pathInterpolator android:controlX1="{c[0]}" android:controlY1="{c[1]}"'
            f' android:controlX2="{c[2]}" android:controlY2="{c[3]}"/></aapt:attr>')


def anim(prop, a, b, span, c, value_type=None):
    vt = f' android:valueType="{value_type}"' if value_type else ''
    return (f'<objectAnimator android:propertyName="{prop}" android:valueFrom="{a}" android:valueTo="{b}"'
            f' android:startOffset="{span[0]}" android:duration="{span[1] - span[0]}"{vt}>{bez(c)}</objectAnimator>')


def cubic_in_out(x):
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def time_blade_at(xu):
    """When (ms) the eased blade head reaches font-unit x."""
    target = (xu - EMBER_R) / (BLADE_END - EMBER_R)
    lo, hi = 0.0, 1.0
    for _ in range(40):
        m = (lo + hi) / 2
        if cubic_in_out(m) < target:
            lo = m
        else:
            hi = m
    return BLADE[0] + lo * (BLADE[1] - BLADE[0])


def halves(name, d, shifted):
    sx = SHIFT if shifted else 0
    return (f'<group android:name="{name}B"><clip-path android:pathData="{BOT_CLIP}"/>'
            f'<path android:fillColor="{BONE}" android:pathData="{d}"/></group>'
            f'<group android:name="{name}T" android:translateX="{sx}"><clip-path android:pathData="{TOP_CLIP}"/>'
            f'<path android:fillColor="{BONE}" android:pathData="{d}"/></group>')


s0 = SPLASH / S
k_dx = CENTRE_U[0] - K_C[0]
k_dy = CENTRE_U[1] - K_C[1]
tail_dx = -(WORD_R - K_RIGHT)
# The mask starts past the K's sheared top and retreats as the tail lands,
# so letters come out from fully behind the K, never through its notch.
mask_r = K_RIGHT + SHIFT + 16
mask_back = mask_r - (K_RIGHT - 30)

tail = ''.join(halves(f'l{i}', g['d'], False) for i, g in enumerate(WORD) if i > 0)
vector = f'''<vector android:width="{SIZE:g}dp" android:height="{SIZE:g}dp" android:viewportWidth="{SIZE:g}" android:viewportHeight="{SIZE:g}">
            <group android:name="word" android:translateX="{TX:.3f}" android:translateY="{TY:.3f}" android:scaleX="{S}" android:scaleY="{S}">
                <!-- The tail, parked behind the K until it slides out. -->
                <group android:name="tail" android:translateX="{tail_dx}">{tail}</group>
                <!-- Graphite over everything left of the K's right edge: the tail emerges from under it. -->
                <group android:name="mask"><path android:fillColor="#0B0B0C" android:pathData="M-6000,-4000 H{mask_r} V8000 H-6000 Z"/></group>
                <!-- The blade: runs out from the K's cut across the word, then draws back. -->
                <path android:name="blade" android:pathData="M{EMBER_R - EMBER_H},{EMBER_Y} L{BLADE_END},{EMBER_Y}" android:strokeColor="{EMBER}"
                    android:strokeWidth="{EMBER_H}" android:strokeLineCap="round" android:trimPathEnd="0"/>
                <!-- The K as the splash left it: sheared, its ember trailing left. Starts at splash size in the centre. -->
                <group android:name="k" android:pivotX="{K_C[0]}" android:pivotY="{K_C[1]}" android:scaleX="{s0:.5f}" android:scaleY="{s0:.5f}"
                    android:translateX="{k_dx}" android:translateY="{k_dy}">
                    {halves('k', WORD[0]['d'], True)}
                    <path android:pathData="M{EMBER_L},{EMBER_Y} L{EMBER_R},{EMBER_Y}" android:strokeColor="{EMBER}" android:strokeWidth="{EMBER_H}" android:strokeLineCap="round"/>
                </group>
            </group>
        </vector>'''

targets = []
targets.append(('k', '<set>' + anim('scaleX', f'{s0:.5f}', 1, GLIDE, IN_OUT_CUBIC) + anim('scaleY', f'{s0:.5f}', 1, GLIDE, IN_OUT_CUBIC)
                + anim('translateX', k_dx, 0, GLIDE, IN_OUT_CUBIC) + anim('translateY', k_dy, 0, GLIDE, IN_OUT_CUBIC) + '</set>'))
targets.append(('tail', anim('translateX', tail_dx, 0, LETTERS, OUT_EXPO)))
targets.append(('mask', anim('translateX', 0, -mask_back, LETTERS, (0.7, 0, 0.84, 0))))
targets.append(('blade', '<set>' + anim('trimPathEnd', 0, 1, BLADE, IN_OUT_CUBIC) + anim('trimPathStart', 0, 1, TRIM, IN_OUT_CUBIC) + '</set>'))
for i, g in enumerate(WORD):
    if i == 0:
        continue
    mid = (g['box'][0] + g['box'][2]) / 2
    t0 = round(time_blade_at(mid - 0.08 * 1000))
    targets.append((f'l{i}T', anim('translateX', 0, SHIFT, (t0, t0 + SNAP), OUT_BACK)))
total = TRIM[1]

body = '\n'.join(f'    <target android:name="{n}">\n        <aapt:attr name="android:animation">{a}</aapt:attr>\n    </target>'
                 for n, a in targets)
xml = f'''<?xml version="1.0" encoding="utf-8"?>
<!-- The launch intro, {total} ms, played by MainActivity over the app as it
     starts. Continues from avd_splash: the sheared K glides into the word,
     the tail slides out from behind it, the ember blade shears each letter,
     then draws back into the K's cut. Generated by gen_intro.py; see KShear. -->
<animated-vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt">
    <aapt:attr name="android:drawable">
        {vector}
    </aapt:attr>
{body}
</animated-vector>
'''
p = os.path.join(RES, 'drawable', 'avd_intro.xml')
io.open(p, 'w', encoding='utf-8', newline='\n').write(xml)
print('wrote', p, 'total', total, 'ms; K start scale', round(s0, 4), 'snaps',
      [round(time_blade_at((g['box'][0] + g['box'][2]) / 2 - 80)) for g in WORD[1:]])
