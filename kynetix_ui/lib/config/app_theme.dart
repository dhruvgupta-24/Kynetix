import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/k_format.dart';

import '../ui/k_icons.dart';
import '../ui/k_loaders.dart';
import '../ui/k_motion.dart';
import '../ui/k_surfaces.dart';
import '../ui/k_transitions.dart';

// The design system: one import gives screens tokens, motion, surfaces,
// transitions and animated primitives.
export '../ui/k_format.dart';
export '../ui/k_hero.dart';
export '../ui/k_icons.dart';
export '../ui/k_loaders.dart';
export '../ui/k_motion.dart';
export '../ui/k_reveal.dart';
export '../ui/k_surfaces.dart';
export '../ui/k_transitions.dart';
export '../ui/k_widgets.dart';

// ─── KPalette ─────────────────────────────────────────────────────────────────
// "Graphite Ember". Three colours per theme, nothing else:
//
//   Dark   Graphite #0B0B0C   Bone #F2F1EC   Ember #FF6A3D
//   Light  Paper    #F4F3EF   Ink  #151515   Burnt ember #B8401A
//
// Protein has its own colour, used only for protein:
//
//   Dark   Sage #79D49B       Light  Fern #1E7A4C
//
// Base is the ground. Ink is text and primary buttons.
// Ember is the one accent, kept for one meaning on a small part of the
// screen: calories, the open tab, the log action, and what needs attention.
// Every surface, hairline and secondary text is a mix of base and ink, so
// the screen never shows a fourth hue. Older names (green, violet, cyan,
// saffron, danger) resolve into these three so every call site stays in
// the palette.

@immutable
class KPalette {
  const KPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.card,
    required this.cardHigh,
    required this.inset,
    required this.border,
    required this.divider,
    required this.fg,
    required this.ink,
    required this.onInk,
    required this.green,
    required this.greenDark,
    required this.ember,
    required this.protein,
    required this.saffron,
    required this.violet,
    required this.cyan,
    required this.blue,
    required this.danger,
    required this.warning,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.onAccent,
    required this.shadow,
    required this.track,
    required this.auroraStrength,
  });

  final Brightness brightness;
  final Color bg, surface, card, cardHigh, inset, border, divider;
  final Color fg, ink, onInk;

  /// [ember] is the accent; [green] is ink (protein, success); [saffron],
  /// [violet], [cyan], [danger] and [warning] resolve to the accent and
  /// [blue] to a neutral mid tone.
  final Color green, greenDark, ember, saffron, violet, cyan, blue;
  final Color danger, warning;

  /// Protein only: rings, dots, bars and numbers. Nothing else wears it.
  final Color protein;
  final Color textPrimary, textSecondary, textMuted, textDisabled;
  final Color onAccent;
  final Color shadow;

  /// Unfilled part of rings and bars.
  final Color track;
  final double auroraStrength;

  bool get isDark => brightness == Brightness.dark;

  /// Graphite, Bone, Ember.
  static const dark = KPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0B0C),
    surface: Color(0xFF111112),
    card: Color(0xFF161617),
    cardHigh: Color(0xFF1F1F20),
    inset: Color(0xFF0E0E0F),
    border: Color(0xFF2B2B2C),
    divider: Color(0xFF202021),
    fg: Color(0xFFF2F1EC),
    ink: Color(0xFFF2F1EC),
    onInk: Color(0xFF0B0B0C),
    green: Color(0xFFF2F1EC),
    greenDark: Color(0xFF2B2B2C),
    ember: Color(0xFFFF6A3D),
    protein: Color(0xFF79D49B),
    saffron: Color(0xFFFF6A3D),
    violet: Color(0xFFFF6A3D),
    cyan: Color(0xFFFF6A3D),
    blue: Color(0xFF9D9C97),
    danger: Color(0xFFFF6A3D),
    warning: Color(0xFFFF6A3D),
    textPrimary: Color(0xFFF2F1EC),
    textSecondary: Color(0xFFA6A5A0),
    textMuted: Color(0xFF7B7A76),
    textDisabled: Color(0xFF4A4A48),
    onAccent: Color(0xFF0B0B0C),
    shadow: Color(0xFF000000),
    track: Color(0xFF232324),
    auroraStrength: 0,
  );

  /// Paper, Ink, Burnt ember.
  static const light = KPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF4F3EF),
    surface: Color(0xFFF9F8F5),
    card: Color(0xFFFFFFFF),
    cardHigh: Color(0xFFEBEAE5),
    inset: Color(0xFFEFEEEA),
    border: Color(0xFFE0DFD9),
    divider: Color(0xFFE8E7E1),
    fg: Color(0xFF151515),
    ink: Color(0xFF151515),
    onInk: Color(0xFFF9F8F5),
    green: Color(0xFF151515),
    greenDark: Color(0xFF151515),
    ember: Color(0xFFB8401A),
    protein: Color(0xFF1E7A4C),
    saffron: Color(0xFFB8401A),
    violet: Color(0xFFB8401A),
    cyan: Color(0xFFB8401A),
    blue: Color(0xFF6E6D69),
    danger: Color(0xFFB8401A),
    warning: Color(0xFFB8401A),
    textPrimary: Color(0xFF151515),
    textSecondary: Color(0xFF55544F),
    textMuted: Color(0xFF6B6A65),
    textDisabled: Color(0xFFBEBDB7),
    onAccent: Color(0xFFFFFFFF),
    shadow: Color(0xFF000000),
    track: Color(0xFFE6E5DF),
    auroraStrength: 0,
  );
}

// ─── KColor ───────────────────────────────────────────────────────────────────
// Reads the active palette. Values change when the theme changes, so never
// cache them in a `static final`, a State field, or a `const`.

abstract class KColor {
  static KPalette _p = KPalette.dark;
  static KPalette get palette => _p;
  static bool get isDark => _p.isDark;

  // ── Backgrounds
  static Color get bg => _p.bg; // page background
  static Color get surface => _p.surface; // bars, sheets
  static Color get card => _p.card; // cards
  static Color get cardHigh => _p.cardHigh; // raised / pressed cards

  /// Recessed tray inside a card (e.g. the logged meals under a meal header).
  static Color get inset => _p.inset;

  // ── Borders
  static Color get border => _p.border;
  static Color get divider => _p.divider;

  /// Hairlines and translucent overlays: white on Carbon, ink on Paper.
  /// Use `KColor.fg.withValues(alpha: …)` instead of `Colors.white.withValues`.
  static Color get fg => _p.fg;

  // ── Monochrome primary (buttons, selected states)
  static Color get ink => _p.ink;
  static Color get onInk => _p.onInk;

  // ── Brand / data
  static Color get green => _p.green; // protein / success
  static Color get greenDark => _p.greenDark; // fills behind white text
  static Color get greenGlow => _p.green;
  static Color get ember => _p.ember;
  static Color get saffron => _p.saffron;
  static Color get violet => _p.violet;
  static Color get cyan => _p.cyan;

  // ── World accents (one per tab)
  static Color get fuel => _p.ember;
  static Color get train => _p.violet;
  static Color get kyno => _p.cyan;

  /// The accent for dock tab [index]: Nutrition, Train, Kyno.
  static Color tabAccent(int index) => switch (index) {
        0 => _p.ember,
        1 => _p.violet,
        _ => _p.cyan,
      };

  /// A whisper of [accent] over a card, for a world's hero surface.
  static Color tint(Color accent, {double dark = 0.08, double light = 0.06}) =>
      Color.alphaBlend(accent.withValues(alpha: isDark ? dark : light), _p.card);

  // ── Semantic
  static Color get calorie => _p.ember;
  static Color get protein => _p.protein;
  static Color get amber => _p.saffron;
  static Color get blue => _p.blue;
  static Color get danger => _p.danger;
  static Color get warning => _p.warning;
  static Color get success => _p.green;

  // ── Text
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;
  static Color get textDisabled => _p.textDisabled;

  /// Text / icons placed ON a saturated accent fill.
  static Color get onAccent => _p.onAccent;

  /// Unfilled part of rings and progress bars.
  static Color get track => _p.track;

  // ── Data series, as tints of the three colours ──
  /// Carbs: the accent, softened.
  static Color get carbs => Color.lerp(_p.ember, _p.bg, isDark ? 0.38 : 0.18)!;

  /// Fat: ink, set back.
  static Color get fat => Color.lerp(_p.ink, _p.bg, 0.42)!;

  /// Fiber: ink, further back.
  static Color get fiber => Color.lerp(_p.ink, _p.bg, isDark ? 0.66 : 0.5)!;

  /// The 1px edge of a card.
  static Color get hairline => isDark ? const Color(0xFF242425) : _p.border;
}

// ─── KThemeController ─────────────────────────────────────────────────────────
// System / Light / Dark preference, persisted locally. A UI preference only —
// it never touches user data. `KThemeScope` applies it.

class KThemeController extends ValueNotifier<ThemeMode> {
  // Kynetix is designed dark first: everyone starts in dark, and a choice
  // made in Settings sticks.
  KThemeController._() : super(ThemeMode.dark);
  static final instance = KThemeController._();

  static const _key = 'ui_theme_mode_v2';
  static const _legacyKey = 'ui_theme_mode_v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // v1 defaulted to System. Only an explicit Light pick carries over;
      // everything else starts in dark.
      final v = prefs.getString(_key) ??
          (prefs.getString(_legacyKey) == ThemeMode.light.name ? ThemeMode.light.name : null);
      value = ThemeMode.values.firstWhere(
        (m) => m.name == v,
        orElse: () => ThemeMode.dark,
      );
    } catch (_) {
      /* keep dark */
    }
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}

/// Resolves the active palette above the app and repaints every widget when it
/// changes, without remounting anything (state, scroll and forms survive).
class KThemeScope extends StatefulWidget {
  const KThemeScope({super.key, required this.builder});
  final Widget Function(BuildContext context, KPalette palette) builder;

  @override
  State<KThemeScope> createState() => _KThemeScopeState();
}

class _KThemeScopeState extends State<KThemeScope> with WidgetsBindingObserver {
  final _ctrl = KThemeController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl.addListener(_apply);
    _resolve();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_apply);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _apply();

  void _resolve() {
    final mode = _ctrl.value;
    final platformDark =
        SchedulerBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final dark =
        mode == ThemeMode.dark || (mode == ThemeMode.system && platformDark);
    KColor._p = dark ? KPalette.dark : KPalette.light;
    KText._refresh();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  void _apply() {
    final before = KColor._p;
    _resolve();
    if (identical(before, KColor._p) || !mounted) return;
    setState(() {});
    // Widgets read KColor statically, so they don't depend on Theme. Mark the
    // whole tree dirty so everything repaints in the new palette.
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, KColor._p);
}

// ─── KGradient ────────────────────────────────────────────────────────────────

abstract class KGradient {
  // Graphite is flat: every "gradient" is one colour, so fills read as solid
  // pigment. The lists stay two long so existing gradient call sites work.
  static List<Color> _flat(Color c) => [c, c];

  static List<Color> get fuel => _flat(KColor.ember);
  static List<Color> get protein => _flat(KColor.protein);
  static List<Color> get train => _flat(KColor.violet);
  static List<Color> get kyno => _flat(KColor.cyan);

  /// The fill for a world's accent elements.
  static List<Color> world(KTone tone) => switch (tone) {
        KTone.fuel => fuel,
        KTone.train => train,
        KTone.kyno => kyno,
        KTone.neutral => primary,
      };

  /// Primary actions are solid ink: white on Graphite, near-black on paper.
  static List<Color> get primary => _flat(KColor.ink);
  static List<Color> get danger => _flat(KColor.danger);

  static LinearGradient linear(
    List<Color> c, {
    AlignmentGeometry begin = Alignment.topLeft,
    AlignmentGeometry end = Alignment.bottomRight,
  }) => LinearGradient(colors: c, begin: begin, end: end);
}

// ─── KText ────────────────────────────────────────────────────────────────────
// Geist (bundled, OFL) for text and numbers; Bricolage Grotesque (bundled,
// OFL) for display and h1 headlines, where the type itself is the voice.
// Numbers use tabular figures so they don't jitter while counting.

abstract class KText {
  static const family = 'Inter';
  static const displayFace = 'InterTight';

  /// The Kynetix wordmark face. Used for the name only.
  static const brandFace = 'Bricolage';
  static const _tabular = [FontFeature.tabularFigures()];

  /// Display font family, for inline TextStyles that need the display face.
  static String? get displayFamily => displayFace;

  static _KTextSet _set = _KTextSet(KPalette.dark);
  static void _refresh() => _set = _KTextSet(KColor._p);

  static TextStyle get display => _set.display;
  static TextStyle get h1 => _set.h1;
  static TextStyle get h2 => _set.h2;
  static TextStyle get h3 => _set.h3;
  static TextStyle get body => _set.body;
  static TextStyle get bodyMedium => _set.bodyMedium;
  static TextStyle get caption => _set.caption;
  static TextStyle get label => _set.label;
  static TextStyle get numDisplay => _set.numDisplay;
  static TextStyle get numMedium => _set.numMedium;
  static TextStyle get numSmall => _set.numSmall;
}

// Inter Tight sets headlines and numbers tight (-4% at display sizes, -2%
// below), Inter sets everything you read. Weights stop at 700.
class _KTextSet {
  _KTextSet(KPalette p)
    : display = _s(p.textPrimary, 32, FontWeight.w700, -1.3, 1.05, face: KText.displayFace),
      h1 = _s(p.textPrimary, 25, FontWeight.w700, -0.9, 1.12, face: KText.displayFace),
      h2 = _s(p.textPrimary, 19, FontWeight.w600, -0.5, 1.22, face: KText.displayFace),
      h3 = _s(p.textPrimary, 15, FontWeight.w600, -0.25, 1.35),
      body = _s(p.textPrimary, 14, FontWeight.w400, -0.15, 1.55),
      bodyMedium = _s(p.textPrimary, 14, FontWeight.w500, -0.15, 1.5),
      caption = _s(p.textSecondary, 12, FontWeight.w500, -0.05, 1.4),
      label = _s(p.textMuted, 11.5, FontWeight.w500, 0.1, 1.3),
      numDisplay = _s(p.textPrimary, 36, FontWeight.w700, -1.5, 1.0, tab: true, face: KText.displayFace),
      numMedium = _s(p.textPrimary, 22, FontWeight.w600, -0.7, 1.05, tab: true, face: KText.displayFace),
      numSmall = _s(p.textPrimary, 13, FontWeight.w600, -0.1, 1.1, tab: true);

  final TextStyle display, h1, h2, h3, body, bodyMedium, caption, label;
  final TextStyle numDisplay, numMedium, numSmall;

  static TextStyle _s(
    Color c,
    double size,
    FontWeight w,
    double ls,
    double h, {
    bool tab = false,
    String face = KText.family,
  }) => TextStyle(
    fontFamily: face,
    color: c,
    fontSize: size,
    fontWeight: w,
    letterSpacing: ls,
    height: h,
    fontFeatures: tab ? KText._tabular : null,
  );
}

// ─── KSpacing ─────────────────────────────────────────────────────────────────

abstract class KSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double p = 20; // standard horizontal page padding

  /// Bottom padding scrollable tab content needs to clear the floating dock.
  static const double dockClearance = 112;
}

// ─── KRadius ──────────────────────────────────────────────────────────────────

// Radius follows hierarchy: tags and inputs are nearly square (xs/sm),
// objects such as a meal or a product are softly rounded (md/lg), and only
// sheets and the floating dock get the big curve (xl). Buttons are pills.
abstract class KRadius {
  static const xs = BorderRadius.all(Radius.circular(8));
  static const sm = BorderRadius.all(Radius.circular(12));
  static const md = BorderRadius.all(Radius.circular(16));
  static const lg = BorderRadius.all(Radius.circular(22));
  static const xl = BorderRadius.all(Radius.circular(28));
  static const pill = BorderRadius.all(Radius.circular(100));
}

// ─── KShadow ──────────────────────────────────────────────────────────────────

abstract class KShadow {
  /// Depth comes from surface steps and hairlines in both themes, never from
  /// shadows.
  static List<BoxShadow> get card => const [];
  /// Retired: the owner's rule is no glow anywhere. Kept so callers compile;
  /// it draws nothing.
  static List<BoxShadow> glow(Color c, {double strength = 1}) => const [];
}

// ─── Pressable ────────────────────────────────────────────────────────────────
// A card that physically responds to press with scale + haptic.

// Press = squash on finger-down (easeOut, ~120 ms, starts the same frame),
// release on a real spring (KMotion.pressSpring: slight lift, no wobble).
// Both are interruptible: a new touch mid-release picks up from wherever the
// card is. Optional `haptic` fires a selection tick on commit;
// `semanticLabel` makes the target speak as a button.

class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale while held. Defaults to 0.97, the app-wide press depth.
  final double scale;

  /// Press-down duration (release always runs on the spring).
  final Duration duration;
  final BorderRadius borderRadius;
  final bool haptic;
  final String? semanticLabel;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.duration = KMotion.press,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.haptic = false,
    this.semanticLabel,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  // How pressed the target is: 0 at rest, 1 fully held. Unbounded so the
  // release spring can carry it a hair past rest (a tiny lift) and back.
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );
  late final Animation<double> _scale = _PressScale(_press, () => widget.scale);
  bool _isDown = false;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down() {
    if (_isDown) return;
    _isDown = true;
    if (KMotion.reduced(context)) return;
    _press.animateTo(1, duration: widget.duration, curve: KMotion.easeOut);
  }

  void _up() {
    if (!_isDown) return;
    _isDown = false;
    if (KMotion.reduced(context)) {
      _press.value = 0;
      return;
    }
    _press.animateWith(
      SpringSimulation(KMotion.pressSpring, _press.value, 0, _press.velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget out = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _down() : null,
      onTapUp: enabled
          ? (_) {
              _up();
              if (widget.haptic) KHaptics.select();
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => _up() : null,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
    if (widget.semanticLabel != null) {
      out = Semantics(
        container: true,
        button: true,
        enabled: enabled,
        label: widget.semanticLabel,
        // excludeSemantics drops the GestureDetector's own tap action, so
        // re-expose it: screen readers must be able to activate the target.
        onTap: enabled ? widget.onTap : null,
        onLongPress: widget.onLongPress,
        excludeSemantics: true,
        child: out,
      );
    }
    return out;
  }
}

/// Maps press amount (0 rest, 1 held) to scale, reading the target scale
/// live so a rebuilt Pressable with a new `scale` stays correct.
class _PressScale extends Animation<double>
    with AnimationWithParentMixin<double> {
  _PressScale(this.parent, this._target);

  @override
  final Animation<double> parent;
  final double Function() _target;

  @override
  double get value => 1.0 - (1.0 - _target()) * parent.value;
}

// ─── KCard ────────────────────────────────────────────────────────────────────
// Standard app card. Carbon: a lifted surface step plus a hairline (no shadow).
// Paper: an off-white sheet with a warm hairline and a soft, low shadow.

class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final Border? border;

  const KCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderRadius,
    this.boxShadow,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    // Flat: one surface step above the page and a 1px hairline.
    return Container(
      padding: padding ?? const EdgeInsets.all(KSpacing.lg),
      decoration: BoxDecoration(
        color: color ?? KColor.card,
        borderRadius: borderRadius ?? KRadius.lg,
        border: border ?? Border.all(color: KColor.hairline, width: 1),
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }
}

// ─── KSectionTitle ────────────────────────────────────────────────────────────
// Quiet sentence-case heading for a group of cards.

class KSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  const KSectionTitle(this.text, {super.key, this.trailing, this.padding});

  static String _sentence(String s) {
    if (s.isEmpty || s != s.toUpperCase()) return s;
    final lower = s.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.xxl, KSpacing.xl, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                _sentence(text),
                style: KText.h3.copyWith(
                  color: KColor.textSecondary,
                  fontSize: 14,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ─── KButton ──────────────────────────────────────────────────────────────────
// Primary action: a monochrome ink pill (warm white on Carbon, near-black on
// Paper), unmistakably "the" action without borrowing a data colour. 56dp
// tall, haptic on commit, built-in loading and success states.
//
// States (see [KButtonState]):
//   idle     label (and optional icon), tappable.
//   loading  the spinner leads the label; taps are ignored.
//   success  the label cross-fades to a check mark that draws itself
//            (~300 ms) beside [successLabel] ("Logged"). One success haptic
//            fires on the frame it switches. Taps are ignored until the
//            caller sets the state back to idle.

/// What a [KButton] is showing.
enum KButtonState { idle, loading, success }

class KButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool outlined;
  final IconData? icon;
  final Color? color;
  final double? width;

  /// Shortcut for `state: KButtonState.success`.
  final bool success;

  /// Short past-tense label shown with the check mark ("Logged", "Saved").
  /// Falls back to [label].
  final String? successLabel;

  /// Explicit state. When null it is derived from [success] and [loading].
  final KButtonState? state;

  const KButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.outlined = false,
    this.icon,
    this.color,
    this.width,
    this.success = false,
    this.successLabel,
    this.state,
  });

  /// The state this button shows.
  KButtonState get effectiveState =>
      state ??
      (success
          ? KButtonState.success
          : loading
              ? KButtonState.loading
              : KButtonState.idle);

  @override
  State<KButton> createState() => _KButtonState();
}

class _KButtonState extends State<KButton> with SingleTickerProviderStateMixin {
  // 0 shows the label, 1 shows the check. Created lazily: most buttons never
  // succeed, and they should not carry a ticker for it.
  AnimationController? _done;

  static const _successDuration = Duration(milliseconds: 300);

  AnimationController _ensureDone(double value) =>
      _done ??= AnimationController(
        vsync: this,
        duration: _successDuration,
        value: value,
      );

  @override
  void initState() {
    super.initState();
    if (widget.effectiveState == KButtonState.success) _ensureDone(1);
  }

  @override
  void didUpdateWidget(covariant KButton old) {
    super.didUpdateWidget(old);
    final was = old.effectiveState == KButtonState.success;
    final now = widget.effectiveState == KButtonState.success;
    if (was == now) return;
    final ctrl = _ensureDone(was ? 1 : 0);
    final reduced = KMotion.reduced(context);
    if (now) {
      KHaptics.success();
      if (reduced) {
        ctrl.value = 1;
      } else {
        ctrl.forward();
      }
    } else {
      // Back to idle: the label returns quickly, without redrawing the check.
      if (reduced) {
        ctrl.value = 0;
      } else {
        ctrl.animateBack(0, duration: KMotion.quick, curve: KMotion.easeOut);
      }
    }
  }

  @override
  void dispose() {
    _done?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    // One primary look everywhere: a solid ink pill (white on Graphite,
    // near-black on paper). A custom colour fills it instead.
    final custom = w.color != null;
    final bg = w.color ?? KColor.ink;
    final Color fg;
    if (w.outlined) {
      fg = custom ? bg : KColor.textPrimary;
    } else if (custom) {
      // Ink and accent fills have their own on-colours; anything else picks
      // the darker or lighter end of the palette by luminance.
      fg = bg == KColor.ember
          ? KColor.onAccent
          : bg == KColor.ink
              ? KColor.onInk
              : bg.computeLuminance() > 0.45
                  ? KPalette.dark.bg
                  : KPalette.light.card;
    } else {
      fg = KColor.onInk;
    }
    final state = w.effectiveState;
    final loading = state == KButtonState.loading;
    final succeeded = state == KButtonState.success;
    final disabled = w.onTap == null && state == KButtonState.idle;
    final dim = loading || disabled;
    final textStyle = TextStyle(
      fontFamily: KText.family,
      color: fg,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );

    final Widget idle = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: KMotion.of(context, KMotion.quick),
          switchInCurve: KMotion.easeOut,
          child: loading
              ? Padding(
                  key: const ValueKey('l'),
                  padding: const EdgeInsets.only(right: 10),
                  child: KSpinner(size: 16, color: fg),
                )
              : w.icon != null
                  ? Padding(
                      key: const ValueKey('i'),
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(w.icon, size: 19, color: fg),
                    )
                  : const SizedBox.shrink(key: ValueKey('n')),
        ),
        Flexible(
          child: Text(
            w.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );

    final done = _done;
    final Widget content;
    if (done == null) {
      content = idle;
    } else {
      // Both faces stay laid out, so the pill keeps one width through the
      // swap; only opacity and a small transform animate.
      // `drive` (not CurvedAnimation) so nothing registers on the controller
      // per build.
      const outCurve = Interval(0, 0.45, curve: Curves.easeIn);
      const inCurve = Interval(0.15, 0.75, curve: KMotion.easeOut);
      final outOpacity = done.drive(
        Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: outCurve)),
      );
      final outSlide = done.drive(
        Tween(begin: Offset.zero, end: const Offset(0, -0.25))
            .chain(CurveTween(curve: outCurve)),
      );
      final inOpacity = done.drive(CurveTween(curve: inCurve));
      final inSlide = done.drive(
        Tween(begin: const Offset(0, 0.25), end: Offset.zero)
            .chain(CurveTween(curve: inCurve)),
      );
      final stroke = done.drive(
        CurveTween(curve: const Interval(0.2, 1, curve: Curves.easeInOutCubic)),
      );
      content = Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(
            excluding: succeeded,
            child: FadeTransition(
              opacity: outOpacity,
              child: SlideTransition(
                position: outSlide,
                child: idle,
              ),
            ),
          ),
          ExcludeSemantics(
            excluding: !succeeded,
            child: FadeTransition(
              opacity: inOpacity,
              child: SlideTransition(
                position: inSlide,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox.square(
                        dimension: 19,
                        child: CustomPaint(
                          painter: _CheckPainter(progress: stroke, color: fg),
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        w.successLabel ?? w.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: w.width,
      child: Pressable(
        onTap: (state != KButtonState.idle || w.onTap == null)
            ? null
            : () {
                KHaptics.commit();
                w.onTap!();
              },
        borderRadius: KRadius.pill,
        child: AnimatedContainer(
          duration: KMotion.of(context, KMotion.quick),
          curve: KMotion.easeOut,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: w.outlined
                ? Colors.transparent
                : (dim ? bg.withValues(alpha: 0.4) : bg),
            borderRadius: KRadius.pill,
            border: w.outlined
                ? Border.all(
                    color: custom ? bg.withValues(alpha: 0.6) : KColor.border,
                    width: 1,
                  )
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// A check mark that draws itself along its path as [progress] runs 0 to 1.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color})
      : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0) return;
    final s = size.shortestSide;
    // Two legs: the short one is ~38% of the total length.
    final a = Offset(s * 0.18, s * 0.53);
    final b = Offset(s * 0.41, s * 0.75);
    final c = Offset(s * 0.84, s * 0.29);
    final l1 = (b - a).distance;
    final l2 = (c - b).distance;
    final drawn = (l1 + l2) * t;
    final path = Path()..moveTo(a.dx, a.dy);
    if (drawn <= l1) {
      final p = Offset.lerp(a, b, drawn / l1)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = Offset.lerp(b, c, (drawn - l1) / l2)!;
      path.lineTo(p.dx, p.dy);
    }
    _paint
      ..color = color
      ..strokeWidth = (s * 0.12).clamp(1.8, 2.6).toDouble();
    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── KChip ────────────────────────────────────────────────────────────────────

class KChip extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  const KChip(this.label, {super.key, this.color, this.textColor, this.icon});

  @override
  Widget build(BuildContext context) {
    // A quiet filled pill on the step above the card. A colour (when the
    // tag carries meaning) shows only in the leading icon or dot, so the
    // label stays readable in both themes.
    final tone = color;
    final fg = textColor ?? KColor.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: KRadius.pill,
        color: KColor.cardHigh,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone ?? fg),
            const SizedBox(width: 4),
          ] else if (tone != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KText.caption.copyWith(
                color: fg,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── KDragHandle ──────────────────────────────────────────────────────────────

class KDragHandle extends StatelessWidget {
  const KDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 40,
        height: 4.5,
        decoration: BoxDecoration(
          color: KColor.fg.withValues(alpha: 0.18),
          borderRadius: KRadius.pill,
        ),
      ),
    );
  }
}

// ─── KSheetHeader ─────────────────────────────────────────────────────────────

class KSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const KSheetHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KDragHandle(),
          const SizedBox(height: 8),
          Text(title, style: KText.h2),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: KText.caption),
          ],
        ],
      ),
    );
  }
}

// ─── Navigation helpers ───────────────────────────────────────────────────────

/// Rise + fade route — used for composer / editor screens (AddMeal, etc.)
PageRoute<T> slideUpRoute<T>({required WidgetBuilder builder}) =>
    kRiseRoute<T>(builder: builder);

/// Haptic conveniences — routed through the central [KHaptics] map.
void kHaptic() => KHaptics.commit();
void kHapticMedium() => KHaptics.success();
void kHapticSelect() => KHaptics.select();

// ─── KGradientCircularProgress ───────────────────────────────────────────────

class KGradientCircularProgress extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final double strokeWidth;
  final List<Color> colors;
  final Color? trackColor;
  final Widget? child;

  const KGradientCircularProgress({
    super.key,
    required this.progress,
    this.strokeWidth = 10,
    required this.colors,
    this.trackColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GradientCircularProgressPainter(
        progress: progress,
        strokeWidth: strokeWidth,
        colors: colors,
        trackColor: trackColor ?? KColor.border,
      ),
      child: child != null ? Center(child: child) : null,
    );
  }
}

class _GradientCircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final List<Color> colors;
  final Color trackColor;

  _GradientCircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.colors,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    // Flat arc in the first colour: no gradient, no glow.
    final rect = Rect.fromCircle(center: center, radius: radius);
    final progressPaint = Paint()
      ..color = colors.isEmpty ? KColor.ink : colors.first
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      rect,
      -3.14159 / 2,
      2 * 3.14159 * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientCircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.colors != colors ||
        oldDelegate.trackColor != trackColor;
  }
}

// ─── KAnimatedCount ──────────────────────────────────────────────────────────

class KAnimatedCount extends StatefulWidget {
  final num value;
  final TextStyle style;
  final String suffix;
  final String prefix;
  final int decimalPlaces;

  /// "2,181" instead of "2181" (whole numbers only).
  final bool thousandsSeparator;

  const KAnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.suffix = '',
    this.prefix = '',
    this.decimalPlaces = 0,
    this.thousandsSeparator = false,
  });

  @override
  State<KAnimatedCount> createState() => _KAnimatedCountState();
}

class _KAnimatedCountState extends State<KAnimatedCount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _oldValue = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = _controller.drive(
      Tween<double>(begin: 0.0, end: widget.value.toDouble())
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    _oldValue = widget.value.toDouble();
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = KMotion.of(
      context,
      const Duration(milliseconds: 800),
    );
    if (!_started) {
      _started = true;
      if (_controller.duration == Duration.zero) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void didUpdateWidget(covariant KAnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _oldValue = oldWidget.value.toDouble();
      // `drive` keeps no listener on the controller, so replacing the
      // animation on every value change leaks nothing.
      _animation = _controller.drive(
        Tween<double>(begin: _oldValue, end: widget.value.toDouble())
            .chain(CurveTween(curve: Curves.easeOutCubic)),
      );
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final current = _animation.value;
        final text = widget.decimalPlaces == 0
            ? (widget.thousandsSeparator
                  ? thousands(current)
                  : current.round().toString())
            : current.toStringAsFixed(widget.decimalPlaces);
        return Text(
          '${widget.prefix}$text${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}

// ─── KEmptyState ─────────────────────────────────────────────────────────────

enum KEmptyStateType { nutrition, workout, general }

class KEmptyState extends StatelessWidget {
  final KEmptyStateType type;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const KEmptyState({
    super.key,
    required this.type,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A single outlined glyph in a hairline ring. No illustration.
            ExcludeSemantics(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.16 : 0.14)),
                ),
                child: Icon(
                  switch (type) {
                    KEmptyStateType.nutrition => KIcons.plate,
                    KEmptyStateType.workout => KIcons.train,
                    KEmptyStateType.general => Icons.inbox_outlined,
                  },
                  size: 24,
                  color: KColor.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: KText.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: KText.caption.copyWith(
                color: KColor.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
                child: KButton(label: actionLabel!, onTap: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── KErrorCard ──────────────────────────────────────────────────────────────

class KErrorCard extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const KErrorCard({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  State<KErrorCard> createState() => _KErrorCardState();
}

class _KErrorCardState extends State<KErrorCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 8.0), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -8.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 6.0, end: -4.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeIn));
  }

  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_played) return;
    _played = true;
    // Rejection is acknowledged once; under reduced motion it's message-only.
    if (KMotion.reduced(context)) {
      _shakeController.value = 1.0;
    } else {
      _shakeController.forward();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: KCard(
        color: KColor.danger.withValues(alpha: 0.08),
        border: Border.all(
          color: KColor.danger.withValues(alpha: 0.3),
          width: 1.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: KColor.danger, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title, style: KText.h3),
                  const SizedBox(height: 4),
                  Text(
                    widget.message,
                    style: KText.caption.copyWith(
                      color: KColor.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  if (widget.onRetry != null) ...[
                    const SizedBox(height: 12),
                    Pressable(
                      onTap: widget.onRetry,
                      semanticLabel: 'Retry',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              color: KColor.textPrimary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Try again',
                              style: KText.caption.copyWith(
                                color: KColor.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── KSuccessBanner ───────────────────────────────────────────────────────────

class KSuccessBanner extends StatelessWidget {
  final String message;

  const KSuccessBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: KColor.success.withValues(alpha: 0.15),
        borderRadius: KRadius.md,
        border: Border.all(
          color: KColor.success.withValues(alpha: 0.4),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: KColor.success, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              style: KText.bodyMedium.copyWith(
                color: KColor.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// KShimmer, KShimmerBox, KCardShimmer, KChartShimmer, KMessageShimmer,
// KPulseLoader and KLoadingDots live in lib/ui/k_loaders.dart (exported above).
