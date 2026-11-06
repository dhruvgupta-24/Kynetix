import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/user_session_coordinator.dart';
import '../services/workout_service.dart';
import '../ui/k_brand_intro.dart' show KShearWordmark, kBrandBone, kBrandEmber, kBrandGraphite;
import '../ui/k_rolling.dart';
import '../ui/k_shear_text.dart';

// ─── Birthday ─────────────────────────────────────────────────────────────────
//
// Open the app on your birthday and Kynetix throws you a small party, once a
// year: confetti in the brand's own colours, your new age rolling up like a
// level counter, your year in numbers, and a pass for today.

class BirthdayService {
  const BirthdayService._();

  static String _key(String userId, int year) => 'birthday_party_${userId}_$year';

  /// Shows the party if today is the user's birthday and it hasn't been shown
  /// this year. Also brings a stale age up to date.
  static Future<void> maybeCelebrate(BuildContext context, {DateTime? now}) async {
    final profile = ProfileService.instance.currentUserProfile;
    final uid = UserSessionCoordinator.instance.currentUserId;
    if (profile == null || uid == null || profile.dateOfBirth == null) return;
    final today = now ?? DateTime.now();

    final fresh = profile.withCurrentAge(today);
    if (!identical(fresh, profile)) await ProfileService.instance.save(fresh);

    if (!fresh.isBirthday(today)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _key(uid, today.year);
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    if (!context.mounted) return;
    KHaptics.milestone();
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => BirthdayScreen(profile: fresh, now: today),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }
}

/// What the user did since their last birthday.
class BirthdayYear {
  const BirthdayYear({required this.workouts, required this.loggedDays, required this.kgMoved});
  final int workouts;
  final int loggedDays;
  final double kgMoved;

  static BirthdayYear since(DateTime from, DateTime to) {
    final sessions = WorkoutService.instance.sessions
        .where((s) => !s.date.isBefore(from) && s.date.isBefore(to) && !s.isEmpty)
        .toList();
    var days = 0;
    for (final e in dayLogStore.entries) {
      final d = DateTime.tryParse(e.key);
      if (d == null || d.isBefore(from) || !d.isBefore(to)) continue;
      if (e.value.allEntries.isNotEmpty) days++;
    }
    return BirthdayYear(
      workouts: sessions.length,
      loggedDays: days,
      kgMoved: sessions.fold(0.0, (a, s) => a + s.totalVolume),
    );
  }

  bool get isEmpty => workouts == 0 && loggedDays == 0;
}

class BirthdayScreen extends StatefulWidget {
  const BirthdayScreen({super.key, required this.profile, required this.now});
  final UserProfile profile;
  final DateTime now;

  @override
  State<BirthdayScreen> createState() => _BirthdayScreenState();
}

class _BirthdayScreenState extends State<BirthdayScreen> with SingleTickerProviderStateMixin {
  // The confetti falls for a while, then the controller stops: no endless
  // ticker behind the screen.
  late final AnimationController _fall = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  late final List<_Bit> _bits = _Bit.scatter(140, widget.now.year * 31 + widget.now.day);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KMotion.reduced(context)) {
      _fall.value = 0.55; // a still scatter, nothing moving
    } else if (!_fall.isAnimating && _fall.value == 0) {
      _fall.forward();
    }
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  String get _first {
    final n = widget.profile.name.trim();
    return n.isEmpty ? 'legend' : n.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final age = widget.profile.age;
    final lastBirthday = DateTime(widget.now.year - 1, widget.now.month, widget.now.day);
    final year = BirthdayYear.since(lastBirthday, DateTime(widget.now.year, widget.now.month, widget.now.day));
    final title = 'HAPPY BIRTHDAY, ${_first.toUpperCase()}';

    return Scaffold(
      backgroundColor: kBrandGraphite,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Deep room light: graphite with one soft ember wash low down.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 1.25),
                radius: 1.2,
                colors: [Color(0x40FF6A3D), Color(0x00FF6A3D)],
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _ConfettiPainter(_bits, _fall)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 22),
              child: LayoutBuilder(builder: (context, c) {
                final titleSize = KShearText.fit(
                  title,
                  _brand(10),
                  c.maxWidth,
                  maxLines: 3,
                  min: 30,
                  max: 64,
                  ember: true,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const KShearWordmark(fontSize: 18, ink: kBrandBone, ember: kBrandEmber),
                        const Spacer(),
                        Text(
                          '${widget.now.day.toString().padLeft(2, '0')}.${widget.now.month.toString().padLeft(2, '0')}',
                          style: _label(color: const Color(0x99F2F1EC)),
                        ),
                      ],
                    ),
                    const Spacer(flex: 2),
                    Text('LEVEL', style: _label(color: kBrandEmber)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        KRollingNumber(
                          '$age',
                          fromZero: true,
                          duration: const Duration(milliseconds: 1600),
                          style: _brand(132, height: 0.86),
                          semanticsLabel: 'You are $age',
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text('UNLOCKED', style: _label(color: kBrandBone, size: 13)),
                        ),
                      ],
                    ),
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      header: true,
                      child: KShearText(title, style: _brand(titleSize), ember: kBrandEmber, maxLines: 3),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Another lap around the sun, and you showed up for it.',
                      style: _text(17, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 22),
                    _Rules(age: age),
                    if (!year.isEmpty) ...[
                      const SizedBox(height: 22),
                      _YearStrip(year: year),
                    ],
                    const Spacer(flex: 3),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kBrandBone,
                          foregroundColor: kBrandGraphite,
                          shape: const StadiumBorder(),
                          textStyle: _text(16, weight: FontWeight.w700, color: kBrandGraphite),
                        ),
                        onPressed: () {
                          KHaptics.commit();
                          Navigator.of(context).pop();
                        },
                        child: const Text("Let's get it"),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _brand(double size, {double height = 0.92}) => TextStyle(
      fontFamily: KText.brandFace,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: height,
      letterSpacing: size * -0.02,
      color: kBrandBone,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle _label({Color color = kBrandBone, double size = 11}) => TextStyle(
      fontFamily: KText.family,
      fontWeight: FontWeight.w700,
      fontSize: size,
      letterSpacing: 2.2,
      color: color,
    );

TextStyle _text(double size, {FontWeight weight = FontWeight.w500, Color color = kBrandBone}) => TextStyle(
      fontFamily: KText.family,
      fontWeight: weight,
      fontSize: size,
      height: 1.4,
      color: color,
    );

/// Today's house rules, set like a printed ticket.
class _Rules extends StatelessWidget {
  const _Rules({required this.age});
  final int age;

  List<String> get _lines => [
        'Rest day is allowed. So is a heavy single, your call.',
        'Cake counts as carbs. We checked.',
        if (age == 18)
          'Teen mode is done. Kyno, our AI, is yours from today.'
        else if (age < 18)
          'Growing is a full-time job. Eat like it.'
        else
          'Kyno is not judging the macros today.',
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0x14F2F1EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x26F2F1EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("TODAY'S RULES", style: _label(color: kBrandEmber, size: 10)),
          const SizedBox(height: 8),
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 22, child: Text('0${i + 1}', style: _label(color: const Color(0x99F2F1EC), size: 11))),
                  Expanded(child: Text(_lines[i], style: _text(14.5))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The year since the last birthday, in three numbers.
class _YearStrip extends StatelessWidget {
  const _YearStrip({required this.year});
  final BirthdayYear year;

  @override
  Widget build(BuildContext context) {
    Widget stat(String v, String l) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(v, style: _brand(28, height: 1)),
              ),
              const SizedBox(height: 4),
              Text(l, style: _text(12, color: const Color(0xB3F2F1EC))),
            ],
          ),
        );
    final kg = year.kgMoved >= 1000 ? '${(year.kgMoved / 1000).toStringAsFixed(1)}t' : '${year.kgMoved.round()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SINCE YOUR LAST BIRTHDAY', style: _label(color: const Color(0x99F2F1EC), size: 10)),
        const SizedBox(height: 10),
        Row(
          children: [
            stat('${year.workouts}', year.workouts == 1 ? 'workout' : 'workouts'),
            stat(kg, year.kgMoved >= 1000 ? 'moved' : 'kg moved'),
            stat('${year.loggedDays}', year.loggedDays == 1 ? 'day logged' : 'days logged'),
          ],
        ),
      ],
    );
  }
}

// ─── Confetti ─────────────────────────────────────────────────────────────────

/// One piece: where it starts, how it falls, spins and sways, and its shape.
class _Bit {
  _Bit(this.x, this.delay, this.speed, this.spin, this.sway, this.size, this.color, this.shape, this.phase);
  final double x, delay, speed, spin, sway, size, phase;
  final Color color;
  final int shape; // 0 strip, 1 square, 2 dot, 3 shear chip (the logo's cut)

  static const _colors = [kBrandEmber, kBrandBone, Color(0xFF79D49B), Color(0xFFE0B65C), Color(0xFFFF8A65)];

  static List<_Bit> scatter(int n, int seed) {
    final r = math.Random(seed);
    return [
      for (var i = 0; i < n; i++)
        _Bit(
          r.nextDouble(),
          r.nextDouble() * 0.45,
          0.55 + r.nextDouble() * 0.8,
          (r.nextDouble() - 0.5) * 14,
          6 + r.nextDouble() * 26,
          4 + r.nextDouble() * 8,
          _colors[r.nextInt(_colors.length)],
          r.nextInt(4),
          r.nextDouble() * math.pi * 2,
        ),
    ];
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t) : super(repaint: t);
  final List<_Bit> bits;
  final Animation<double> t;
  final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    for (final b in bits) {
      // Each piece starts above the screen after its delay and falls past
      // the bottom; the last ones are still drifting as the clock runs out.
      final local = ((v - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -40 + local * b.speed * (size.height + 120);
      if (y > size.height + 30) continue;
      final x = b.x * size.width + math.sin(local * 9 + b.phase) * b.sway;
      final angle = b.phase + local * b.spin;
      final fade = local > 0.85 ? (1 - local) / 0.15 : 1.0;
      _p.color = b.color.withValues(alpha: 0.95 * fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      // A tilting piece shows its edge: squash one axis with a cosine.
      canvas.scale(1, math.cos(local * 12 + b.phase).abs() * 0.8 + 0.2);
      switch (b.shape) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: b.size * 0.45, height: b.size * 1.6), const Radius.circular(1.5)),
            _p,
          );
        case 1:
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size), _p);
        case 2:
          canvas.drawCircle(Offset.zero, b.size * 0.45, _p);
        default:
          // The cut from the logo: a slanted parallelogram.
          final s = b.size;
          canvas.drawPath(
            Path()
              ..moveTo(-s * 0.6, s * 0.3)
              ..lineTo(-s * 0.1, -s * 0.3)
              ..lineTo(s * 0.6, -s * 0.3)
              ..lineTo(s * 0.1, s * 0.3)
              ..close(),
            _p,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.bits != bits;
}
