/// Kynetix icon language. One family, one weight, one size scale.
///
/// Every icon in the app is a Material *outlined* glyph (single stroke, the
/// same optical weight), drawn at one of three sizes. Emoji are never used as
/// UI icons. Colour follows the usual rule: neutral (`KColor.textSecondary`)
/// unless the icon carries meaning (fuel, protein, train, danger).
///
/// ## API (stable; other screens build on it)
///
/// Sizes
/// - `KIcons.sm` 16 (inline with caption text), `KIcons.md` 20 (rows, chips),
///   `KIcons.lg` 24 (app bars, primary controls).
///
/// Lookups (all pure, never null)
/// - `KIcons.meal(MealSection s)`      → icon for a meal section.
/// - `KIcons.mealTime(MealSection s)`  → quiet time-of-day hint ("Morning").
/// - `KIcons.workout(WorkoutType t)`   → icon for a workout type.
/// - `KIcons.split(String name)`       → icon for a free-text split day
///                                       ("Chest + Triceps", "Push", "Legs").
/// - Muscle groups have no icon: use `MuscleThumb` (widgets/muscle_body_map.dart),
///   which lights the real muscle on an anatomical body.
/// - `KIcons.food(String name)`        → icon for a food/quick-add name.
///
/// Semantic constants (use these instead of picking ad-hoc icons)
/// - Nutrition: `calories`, `protein`, `carbs`, `fat`, `fiber`, `water`,
///   `plate`, `scan`, `quickAdd`, `library`, `target`.
/// - Training: `train`, `push`, `pull`, `legs`, `upper`, `core`, `cardio`,
///   `rest`, `record` (a personal record), `baseline` (a first-ever set),
///   `history`, `timer`.
/// - Chrome: `add`, `edit`, `delete`, `close`, `back`, `forward`, `prev`,
///   `next`, `calendar`, `settings`, `info`, `done`, `send`, `kyno`.
///
/// Widgets
/// - `KIcon(data, {size, color, semanticLabel})` — an [Icon] at a scale size,
///   neutral by default, excluded from semantics unless labelled.
/// - `KynoMark({size, outlined, color})` — Kyno's monochrome mark: the Kyno
///   robot's head, solid with the visor knocked out (or a line drawing when
///   [outlined]). Use it wherever Kyno speaks or is summoned. On an ink fill
///   pass `color: KColor.onInk`. Never pair it with a gradient.
/// - `KDot({color, size})` — the 6dp colour dot used in "● 201 kcal" stats.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';

abstract final class KIcons {
  // ── Size scale ────────────────────────────────────────────────────────────
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;

  // ── Nutrition ─────────────────────────────────────────────────────────────
  static const IconData calories = Icons.local_fire_department_outlined;
  static const IconData protein = Icons.egg_outlined;
  static const IconData carbs = Icons.grain_outlined;
  static const IconData fat = Icons.water_drop_outlined;
  static const IconData fiber = Icons.eco_outlined;
  static const IconData water = Icons.local_drink_outlined;
  static const IconData plate = Icons.restaurant_outlined;
  static const IconData scan = Icons.qr_code_scanner_outlined;
  static const IconData quickAdd = Icons.bolt_outlined;
  static const IconData library = Icons.menu_book_outlined;
  static const IconData target = Icons.track_changes_outlined;

  // ── Training ──────────────────────────────────────────────────────────────
  // Push = a pressing figure, pull = rowing. Bare arrows read as "trending".
  static const IconData train = Icons.fitness_center_outlined;
  // Day types share the dumbbell: Material's figure icons (gymnast, rower,
  // walker) read as the wrong body part.
  static const IconData push = Icons.fitness_center_outlined;
  static const IconData pull = Icons.fitness_center_outlined;
  static const IconData legs = Icons.fitness_center_outlined;
  static const IconData upper = Icons.accessibility_new_outlined;
  static const IconData core = Icons.fitness_center_outlined;
  static const IconData cardio = Icons.directions_run_outlined;
  static const IconData rest = Icons.bedtime_outlined;
  static const IconData record = Icons.workspace_premium_outlined;
  static const IconData baseline = Icons.flag_outlined;
  static const IconData history = Icons.history_outlined;
  static const IconData timer = Icons.timer_outlined;

  // ── Chrome ────────────────────────────────────────────────────────────────
  static const IconData add = Icons.add;
  static const IconData edit = Icons.edit_outlined;
  static const IconData delete = Icons.delete_outline;
  static const IconData close = Icons.close;
  static const IconData back = Icons.arrow_back;
  static const IconData forward = Icons.arrow_forward;
  static const IconData prev = Icons.chevron_left;
  static const IconData next = Icons.chevron_right;
  static const IconData calendar = Icons.calendar_today_outlined;
  static const IconData settings = Icons.settings_outlined;
  static const IconData info = Icons.info_outline;
  static const IconData done = Icons.check;
  static const IconData send = Icons.arrow_upward;
  static const IconData kyno = Icons.chat_bubble_outline;

  // ── Lookups ───────────────────────────────────────────────────────────────

  static IconData meal(MealSection s) => switch (s) {
        MealSection.breakfast => Icons.wb_twilight_outlined,
        MealSection.lunch => Icons.light_mode_outlined,
        MealSection.eveningSnack => Icons.coffee_outlined,
        MealSection.dinner => Icons.dark_mode_outlined,
        MealSection.lateNight => Icons.bedtime_outlined,
      };

  /// A quiet time-of-day hint shown beside a meal section's name.
  static String mealTime(MealSection s) => switch (s) {
        MealSection.breakfast => 'Morning',
        MealSection.lunch => 'Midday',
        MealSection.eveningSnack => 'Evening',
        MealSection.dinner => 'Night',
        MealSection.lateNight => 'Late',
      };

  static IconData workout(WorkoutType t) => switch (t) {
        WorkoutType.push => push,
        WorkoutType.pull => pull,
        WorkoutType.legs => legs,
        WorkoutType.upper => upper,
        WorkoutType.cardio => cardio,
        WorkoutType.rest => rest,
        WorkoutType.other => train,
      };

  /// Icon for a free-text split day such as "Chest + Triceps" or "Pull".
  static IconData split(String name) =>
      workout(WorkoutType.fromSplitName(name));

  static IconData food(String name) {
    final n = name.toLowerCase();
    if (n.contains('egg')) return Icons.egg_outlined;
    if (n.contains('whey') || n.contains('shake') || n.contains('milk') ||
        n.contains('lassi') || n.contains('smoothie') || n.contains('juice')) {
      return Icons.local_drink_outlined;
    }
    if (n.contains('chai') || n.contains('tea') || n.contains('coffee')) {
      return Icons.coffee_outlined;
    }
    if (n.contains('rice') || n.contains('dal') || n.contains('curry') ||
        n.contains('khichdi') || n.contains('poha') || n.contains('oats')) {
      return Icons.rice_bowl_outlined;
    }
    if (n.contains('roti') || n.contains('bread') || n.contains('paratha') ||
        n.contains('biscuit') || n.contains('toast')) {
      return Icons.bakery_dining_outlined;
    }
    if (n.contains('banana') || n.contains('apple') || n.contains('fruit')) {
      return Icons.spa_outlined;
    }
    return plate;
  }
}

/// An [Icon] on the Kynetix scale. Neutral unless given a colour; decorative
/// (excluded from semantics) unless given a [semanticLabel].
class KIcon extends StatelessWidget {
  const KIcon(this.icon, {super.key, this.size = KIcons.md, Color? color, this.semanticLabel})
      : _color = color;

  final IconData icon;
  final double size;
  final Color? _color;
  Color get color => _color ?? KColor.textSecondary;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final i = Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
    return semanticLabel == null ? ExcludeSemantics(child: i) : i;
  }
}

/// The small colour dot that keys a number to its meaning: "● 201 kcal".
class KDot extends StatelessWidget {
  const KDot({super.key, Color? color, this.size = 6}) : _color = color;
  final Color? _color;
  Color get color => _color ?? KColor.textMuted;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
}

/// Kyno's mark: the head of the Kyno robot (squircle head, antenna, visor,
/// two eyes), drawn on a 24 grid so it sits with the line icons around it.
/// Solid fills the head and knocks the visor out; [outlined] draws the head
/// as a line with solid eyes, for the dock and list rows.
///
/// [alive] gives the mark a quiet idle life: it blinks, glances around, tilts
/// its head and now and then looks up as if thinking, with the antenna
/// lagging behind each move. [selected] going true earns a happy squint and
/// a small hop. Moves are short tweens with still holds between them, so no
/// frame is drawn while Kyno just looks at you. Reduced motion keeps it still.
class KynoMark extends StatelessWidget {
  const KynoMark({
    super.key,
    this.size = 28,
    this.outlined = false,
    this.alive = false,
    this.selected = false,
    Color? color,
  }) : _color = color;

  final double size;
  final bool outlined;
  final bool alive;
  final bool selected;
  final Color? _color;
  Color get color => _color ?? KColor.ink;

  @override
  Widget build(BuildContext context) {
    final knock = color == KColor.ink ? KColor.onInk : KColor.ink;
    if (alive) {
      return _AliveKynoMark(size: size, color: color, knock: knock, outlined: outlined, selected: selected);
    }
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _KynoMarkPainter(color: color, knock: knock, outlined: outlined),
        ),
      ),
    );
  }
}

/// Where Kyno is looking and how its head sits. Eyes in -1..1 of their
/// travel, tilt in radians, hop in grid units, happy 0..1.
@immutable
class _MarkPose {
  const _MarkPose({this.lookX = 0, this.lookY = 0, this.tilt = 0, this.hop = 0, this.happy = 0});

  final double lookX, lookY, tilt, hop, happy;

  static const rest = _MarkPose();

  bool get isRest => lookX == 0 && lookY == 0 && tilt == 0 && happy == 0;

  static _MarkPose lerp(_MarkPose a, _MarkPose b, double t) => _MarkPose(
        lookX: a.lookX + (b.lookX - a.lookX) * t,
        lookY: a.lookY + (b.lookY - a.lookY) * t,
        tilt: a.tilt + (b.tilt - a.tilt) * t,
        hop: a.hop + (b.hop - a.hop) * t,
        happy: a.happy + (b.happy - a.happy) * t,
      );
}

class _AliveKynoMark extends StatefulWidget {
  const _AliveKynoMark({
    required this.size,
    required this.color,
    required this.knock,
    required this.outlined,
    required this.selected,
  });

  final double size;
  final Color color, knock;
  final bool outlined, selected;

  @override
  State<_AliveKynoMark> createState() => _AliveKynoMarkState();
}

class _AliveKynoMarkState extends State<_AliveKynoMark> with TickerProviderStateMixin {
  // One controller per layer: moves (head and eyes), blinks, and the hop.
  late final AnimationController _move = AnimationController(vsync: this, value: 1);
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 110));
  late final AnimationController _hop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Listenable _repaint = Listenable.merge([_move, _blink, _hop]);

  final _rng = math.Random();
  _MarkPose _from = _MarkPose.rest;
  _MarkPose _to = _MarkPose.rest;
  Curve _curve = KMotion.easeOut;
  Timer? _next;
  Timer? _nextBlink;
  bool _live = false;

  _MarkPose get _pose {
    final base = _MarkPose.lerp(_from, _to, _curve.transform(_move.value));
    // The hop: up and back down, with a happy squint that lets go near the
    // end of it.
    final h = _hop.value;
    if (h == 0) return base;
    return _MarkPose(
      lookX: base.lookX,
      lookY: base.lookY,
      tilt: base.tilt,
      hop: base.hop + math.sin(h * math.pi) * 1.6,
      happy: math.max(base.happy, h < 0.75 ? 1.0 : (1 - h) * 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final live = KMotion.ambientAllowed(context);
    if (live == _live) return;
    _live = live;
    if (live) {
      _schedule(const Duration(milliseconds: 1200));
      _scheduleBlink();
    } else {
      _stop();
    }
  }

  @override
  void didUpdateWidget(_AliveKynoMark old) {
    super.didUpdateWidget(old);
    // Opening Kyno's tab makes it happy to see you.
    if (_live && widget.selected && !old.selected) {
      _hop.forward(from: 0);
      _goTo(const _MarkPose(lookY: -0.2), const Duration(milliseconds: 320));
      _schedule(const Duration(milliseconds: 1400));
    }
  }

  void _stop() {
    _next?.cancel();
    _nextBlink?.cancel();
    _move.stop();
    _hop.stop();
    _blink.value = 0;
    _hop.value = 0;
    _from = _to = _MarkPose.rest;
    _move.value = 1;
  }

  void _goTo(_MarkPose target, Duration d, {Curve curve = KMotion.easeOut}) {
    _from = _pose;
    _to = target;
    _curve = curve;
    _move.duration = d;
    _move.forward(from: 0);
  }

  void _schedule(Duration after) {
    _next?.cancel();
    _next = Timer(after, _act);
  }

  /// Picks Kyno's next small move. Mostly it rests and glances; the bigger
  /// beats are rare, so it reads as calm and attentive, never twitchy.
  void _act() {
    if (!mounted || !_live) return;
    final roll = _rng.nextDouble();
    final side = _rng.nextBool() ? 1.0 : -1.0;
    Duration hold;
    if (!_to.isRest && roll < 0.55) {
      // Back to looking at you.
      _goTo(_MarkPose.rest, const Duration(milliseconds: 380));
      hold = Duration(milliseconds: 2400 + _rng.nextInt(3600));
    } else if (roll < 0.62) {
      // Thinking: eyes up and aside, head tipped back a touch.
      _goTo(_MarkPose(lookX: 0.55 * side, lookY: -0.9, tilt: -0.07 * side), const Duration(milliseconds: 460));
      hold = Duration(milliseconds: 1300 + _rng.nextInt(900));
    } else if (roll < 0.74) {
      // Curious: a slow head tilt with a little settle, eyes follow.
      _goTo(_MarkPose(lookX: 0.3 * side, tilt: 0.2 * side), const Duration(milliseconds: 520), curve: Curves.easeOutBack);
      hold = Duration(milliseconds: 1100 + _rng.nextInt(900));
    } else if (roll < 0.78) {
      // A pleased little squint, now and then.
      _goTo(const _MarkPose(happy: 1, lookY: -0.2), const Duration(milliseconds: 260));
      hold = const Duration(milliseconds: 900);
    } else {
      // A glance: eyes lead, the head turns slightly with them.
      final x = (0.55 + _rng.nextDouble() * 0.45) * side;
      final y = (_rng.nextDouble() - 0.5) * 0.6;
      _goTo(_MarkPose(lookX: x, lookY: y, tilt: x * 0.1), Duration(milliseconds: 240 + _rng.nextInt(140)));
      hold = Duration(milliseconds: 900 + _rng.nextInt(1500));
    }
    _schedule(hold);
  }

  void _scheduleBlink() {
    _nextBlink?.cancel();
    _nextBlink = Timer(Duration(milliseconds: 2600 + _rng.nextInt(4200)), () async {
      if (!mounted || !_live) return;
      try {
        await _blink.forward(from: 0).orCancel;
        await _blink.reverse().orCancel;
        // Now and then a double blink, like a person.
        if (_rng.nextDouble() < 0.2) {
          await _blink.forward(from: 0).orCancel;
          await _blink.reverse().orCancel;
        }
      } on TickerCanceled {
        return;
      }
      if (mounted && _live) _scheduleBlink();
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _nextBlink?.cancel();
    _move.dispose();
    _blink.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _KynoMarkPainter(
              color: widget.color,
              knock: widget.knock,
              outlined: widget.outlined,
              pose: () => _pose,
              blink: () => _blink.value,
              repaint: _repaint,
            ),
          ),
        ),
      );
}

class _KynoMarkPainter extends CustomPainter {
  _KynoMarkPainter({
    required this.color,
    required this.knock,
    required this.outlined,
    this.pose,
    this.blink,
    super.repaint,
  });

  final Color color;
  final Color knock;
  final bool outlined;

  /// Read at paint time, so a move repaints without rebuilding the widget.
  final _MarkPose Function()? pose;
  final double Function()? blink;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose?.call() ?? _MarkPose.rest;
    final shut = blink?.call() ?? 0.0;
    final u = size.width / 24;
    canvas.scale(u);
    final ink = Paint()
      ..color = color
      ..isAntiAlias = true;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlined ? 1.8 : 2
      ..strokeCap = StrokeCap.round;

    // The head turns about the chin and hops straight up.
    canvas.translate(0, -p.hop);
    if (p.tilt != 0) {
      canvas.translate(12, 20);
      canvas.rotate(p.tilt);
      canvas.translate(-12, -20);
    }

    // Antenna, with the light on top. Its tip trails the head's turn, like a
    // light spring.
    canvas.drawLine(const Offset(12, 6.6), Offset(12 - p.tilt * 2.4, 4.4), line);
    canvas.drawCircle(Offset(12 - p.tilt * 5, 3.2 + p.hop * 0.25), 1.5, ink);

    // Head.
    final head = RRect.fromLTRBR(3.4, 6.6, 20.6, 20, const Radius.circular(5.4));
    if (outlined) {
      canvas.drawRRect(head.deflate(0.9), line);
    } else {
      canvas.drawRRect(head, ink);
      canvas.drawRRect(
        RRect.fromLTRBR(6.2, 9.8, 17.8, 16.8, const Radius.circular(3.5)),
        Paint()..color = knock,
      );
    }

    // Eyes: they travel inside the face, close for blinks and curve into
    // "^ ^" when happy.
    final dx = p.lookX * 1.5;
    final dy = p.lookY * 1.2;
    final h = (outlined ? 3.4 : 3.2) * (1 - shut).clamp(0.12, 1.0);
    for (final x in const [9.5, 14.5]) {
      final c = Offset(x + dx, 13.3 + dy);
      if (p.happy > 0.5) {
        final arc = Path()
          ..moveTo(c.dx - 1.4, c.dy + 0.7)
          ..quadraticBezierTo(c.dx, c.dy - 1.3, c.dx + 1.4, c.dy + 0.7);
        canvas.drawPath(
          arc,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: 2.2, height: h),
            const Radius.circular(1.1),
          ),
          ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_KynoMarkPainter old) =>
      old.color != color || old.knock != knock || old.outlined != outlined || old.pose != pose;
}
