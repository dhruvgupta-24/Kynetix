import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// What Kyno is doing, which sets its face and body.
enum KynoMood {
  /// Breathing, blinking, glancing around now and then.
  idle,

  /// The user is typing: eyes down toward the composer, leaning in.
  listening,

  /// Waiting on the model: eyes up and to the side, antenna pulsing.
  thinking,

  /// Streaming an answer: the mouth moves.
  talking,

  /// Good news (targets hit, a lift went up).
  happy,

  /// Something needs attention (protein missed all week).
  concerned,

  /// A record or a streak: one arm up in a flex.
  celebrate,
}

/// Kyno's character: a small rounded robot with a visor, two light-up eyes,
/// an antenna and a stubby body. It is drawn, not an image, so it follows the
/// theme (ink body, base visor, ember eyes) and costs a single painter.
///
/// Motion layers:
/// • ambient — breathing and antenna drift, only when ambient motion is on;
/// • blink   — every few seconds at random;
/// • mood    — a 460 ms blend from the last pose to the new one.
/// With reduced motion Kyno holds the mood's pose, still and readable.
class KynoAvatar extends StatefulWidget {
  const KynoAvatar({
    super.key,
    this.size = 56,
    this.mood = KynoMood.idle,
    this.showBody = true,
    this.ambient = true,
  });

  /// Height of the whole figure (head only when [showBody] is false).
  final double size;
  final KynoMood mood;
  final bool showBody;

  /// Breathing, blinking and glancing. Off for small repeated faces (chat
  /// bylines), so a long chat never runs a ticker per message.
  final bool ambient;

  @override
  State<KynoAvatar> createState() => _KynoAvatarState();
}

class _KynoAvatarState extends State<KynoAvatar> with TickerProviderStateMixin {
  late final AnimationController _ambient =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  late final AnimationController _blend =
      AnimationController(vsync: this, duration: KMotion.emphasized, value: 1);

  late _Pose _from = _Pose.of(widget.mood);
  late _Pose _to = _from;
  Timer? _blinkTimer;
  Timer? _glanceTimer;
  double _glance = 0;
  final _rng = math.Random();

  bool get _motion => widget.ambient && KMotion.ambientAllowed(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient();
  }

  void _syncAmbient() {
    if (_motion) {
      if (!_ambient.isAnimating) _ambient.repeat();
      _scheduleBlink();
      _scheduleGlance();
    } else {
      _ambient.stop();
      _blinkTimer?.cancel();
      _glanceTimer?.cancel();
      _blink.value = 0;
      _glance = 0;
    }
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 2200 + _rng.nextInt(3800)), () async {
      if (!mounted || !_motion) return;
      await _blink.forward(from: 0);
      if (!mounted) return;
      await _blink.reverse();
      // Now and then a double blink, like a person.
      if (mounted && _rng.nextDouble() < 0.18) {
        await _blink.forward(from: 0);
        if (mounted) await _blink.reverse();
      }
      if (mounted) _scheduleBlink();
    });
  }

  void _scheduleGlance() {
    _glanceTimer?.cancel();
    _glanceTimer = Timer(Duration(milliseconds: 4000 + _rng.nextInt(5000)), () {
      if (!mounted || !_motion) return;
      if (widget.mood == KynoMood.idle) {
        setState(() => _glance = _glance == 0 ? (_rng.nextBool() ? 0.7 : -0.7) : 0);
      }
      _scheduleGlance();
    });
  }

  @override
  void didUpdateWidget(covariant KynoAvatar old) {
    super.didUpdateWidget(old);
    if (old.ambient != widget.ambient) _syncAmbient();
    if (old.mood != widget.mood) {
      _from = _currentPose();
      _to = _Pose.of(widget.mood);
      if (widget.mood != KynoMood.idle) _glance = 0;
      final d = KMotion.of(context, KMotion.emphasized);
      if (d == Duration.zero) {
        _blend.value = 1;
      } else {
        _blend
          ..duration = d
          ..forward(from: 0);
      }
    }
  }

  _Pose _currentPose() => _Pose.lerp(_from, _to, KMotion.emphasizedCurve.transform(_blend.value));

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _glanceTimer?.cancel();
    _ambient.dispose();
    _blink.dispose();
    _blend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.showBody ? 0.92 : 1.0;
    return Semantics(
      label: 'Kyno, ${_moodWord(widget.mood)}',
      image: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size * aspect,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_ambient, _blink, _blend]),
            builder: (context, _) => CustomPaint(
              painter: _KynoPainter(
                pose: _currentPose(),
                phase: _ambient.value,
                blink: _blink.value,
                glance: _glance,
                showBody: widget.showBody,
                talking: widget.mood == KynoMood.talking,
                thinking: widget.mood == KynoMood.thinking,
                body: KColor.ink,
                // An ink body with a base-coloured visor and mouth, and ember
                // for the eyes, chest light and antenna: Bone and Graphite on
                // the dark theme, Ink and Paper on the light one.
                visor: KColor.onInk,
                eye: KColor.ember,
                accent: KColor.ember,
                shade: KColor.isDark ? KColor.bg : KColor.onInk,
                mouth: KColor.onInk,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _moodWord(KynoMood m) => switch (m) {
        KynoMood.idle => 'ready',
        KynoMood.listening => 'listening',
        KynoMood.thinking => 'thinking',
        KynoMood.talking => 'answering',
        KynoMood.happy => 'pleased',
        KynoMood.concerned => 'concerned',
        KynoMood.celebrate => 'celebrating',
      };
}

/// A face-and-body pose; moods blend between these.
class _Pose {
  const _Pose({
    this.eyeOpen = 1,
    this.happy = 0,
    this.lookX = 0,
    this.lookY = 0,
    this.tilt = 0,
    this.brow = 0,
    this.armUp = 0,
    this.lean = 0,
    this.bounce = 0,
  });

  final double eyeOpen; // 0 closed … 1 open
  final double happy; // 0 round eyes … 1 "^ ^"
  final double lookX; // -1 left … 1 right
  final double lookY; // -1 up … 1 down
  final double tilt; // head tilt, radians
  final double brow; // 0 none … 1 worried brows
  final double armUp; // 0 down … 1 flexed
  final double lean; // forward lean, 0..1
  final double bounce; // vertical bob amplitude, 0..1

  static _Pose of(KynoMood m) => switch (m) {
        KynoMood.idle => const _Pose(),
        KynoMood.listening => const _Pose(lookY: 0.8, lean: 1, tilt: 0.05),
        KynoMood.thinking => const _Pose(lookX: 0.7, lookY: -0.8, tilt: -0.1, eyeOpen: 0.85),
        KynoMood.talking => const _Pose(bounce: 0.35),
        KynoMood.happy => const _Pose(happy: 1, bounce: 0.6, tilt: 0.06),
        KynoMood.concerned => const _Pose(brow: 1, eyeOpen: 0.8, tilt: -0.06, lookY: 0.2),
        KynoMood.celebrate => const _Pose(happy: 1, armUp: 1, bounce: 1, tilt: 0.08),
      };

  static double _l(double a, double b, double t) => a + (b - a) * t;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
        eyeOpen: _l(a.eyeOpen, b.eyeOpen, t),
        happy: _l(a.happy, b.happy, t),
        lookX: _l(a.lookX, b.lookX, t),
        lookY: _l(a.lookY, b.lookY, t),
        tilt: _l(a.tilt, b.tilt, t),
        brow: _l(a.brow, b.brow, t),
        armUp: _l(a.armUp, b.armUp, t),
        lean: _l(a.lean, b.lean, t),
        bounce: _l(a.bounce, b.bounce, t),
      );
}

class _KynoPainter extends CustomPainter {
  _KynoPainter({
    required this.pose,
    required this.phase,
    required this.blink,
    required this.glance,
    required this.showBody,
    required this.talking,
    required this.thinking,
    required this.body,
    required this.visor,
    required this.eye,
    required this.accent,
    required this.shade,
    required this.mouth,
  });

  final _Pose pose;
  final double phase; // 0..1 ambient loop
  final double blink; // 0 open … 1 shut
  final double glance;
  final bool showBody;
  final bool talking;
  final bool thinking;
  final Color body, visor, eye, accent, shade, mouth;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tau = math.pi * 2;
    final breath = math.sin(phase * tau);
    final bob = math.sin(phase * tau * 2) * pose.bounce * h * 0.025;

    // Proportions: head is ~62% of the height with a body.
    final headH = showBody ? h * 0.6 : h * 0.82;
    final headW = showBody ? w * 0.86 : w * 0.86;
    final headTop = (showBody ? h * 0.1 : h * 0.14) + bob - pose.lean * h * 0.01;
    final cx = w / 2 + pose.lean * w * 0.015;

    // ── Body ────────────────────────────────────────────────────────────────
    if (showBody) {
      final bodyTop = headTop + headH * 0.94;
      final bodyW = w * 0.56 * (1 + breath * 0.012);
      final bodyH = h - bodyTop - h * 0.02;
      final bodyRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - bodyW / 2, bodyTop, bodyW, bodyH),
        topLeft: Radius.circular(bodyW * 0.32),
        topRight: Radius.circular(bodyW * 0.32),
        bottomLeft: Radius.circular(bodyW * 0.22),
        bottomRight: Radius.circular(bodyW * 0.22),
      );
      final bodyPaint = Paint()..color = body;
      canvas.drawRRect(bodyRect, bodyPaint);
      // Chest light: a small cyan pill.
      final chest = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, bodyTop + bodyH * 0.42), width: bodyW * 0.26, height: bodyH * 0.14),
        Radius.circular(bodyH),
      );
      canvas.drawRRect(chest, Paint()..color = accent.withValues(alpha: 0.85));

      // Arms: stubs at the sides; the right one flexes up.
      final armPaint = Paint()
        ..color = body
        ..strokeWidth = w * 0.11
        ..strokeCap = StrokeCap.round;
      final shoulderY = bodyTop + bodyH * 0.22;
      final lx = cx - bodyW / 2 - w * 0.02;
      final rx = cx + bodyW / 2 + w * 0.02;
      canvas.drawLine(Offset(lx, shoulderY), Offset(lx - w * 0.05, shoulderY + bodyH * 0.42), armPaint);
      final up = pose.armUp;
      final wave = up > 0 ? math.sin(phase * tau * 3) * 0.08 * up : 0.0;
      final elbow = Offset(rx + w * 0.06 * (1 - up) + w * 0.09 * up, shoulderY + bodyH * 0.42 * (1 - up) - bodyH * 0.05 * up);
      final hand = Offset(
        elbow.dx + w * 0.0 * (1 - up) - w * 0.02 * up,
        elbow.dy + bodyH * 0.0 * (1 - up) - bodyH * (0.42 + wave) * up,
      );
      canvas.drawLine(Offset(rx, shoulderY), elbow, armPaint);
      if (up > 0.02) {
        canvas.drawLine(elbow, Offset.lerp(elbow, hand, up)!, armPaint);
      }
    }

    // ── Head ────────────────────────────────────────────────────────────────
    canvas.save();
    final pivot = Offset(cx, headTop + headH);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(pose.tilt + (thinking ? math.sin(phase * tau) * 0.03 : 0));
    canvas.translate(-pivot.dx, -pivot.dy);

    // Antenna
    final antennaBase = Offset(cx, headTop + headH * 0.02);
    final sway = math.sin(phase * tau) * w * 0.02;
    final antennaTip = Offset(cx + sway + glance * w * 0.02, headTop - headH * 0.16);
    canvas.drawLine(
      antennaBase,
      antennaTip,
      Paint()
        ..color = body
        ..strokeWidth = math.max(1.2, w * 0.035)
        ..strokeCap = StrokeCap.round,
    );
    final pulse = thinking ? (0.5 + 0.5 * math.sin(phase * tau * 4)) : 0.0;
    if (pulse > 0) {
      canvas.drawCircle(antennaTip, w * (0.06 + 0.05 * pulse), Paint()..color = accent.withValues(alpha: 0.18 * pulse));
    }
    canvas.drawCircle(antennaTip, w * 0.05, Paint()..color = accent);

    // Head shell: a soft squircle.
    final headRect = Rect.fromCenter(
      center: Offset(cx, headTop + headH / 2),
      width: headW,
      height: headH * (1 + breath * 0.008),
    );
    final head = RRect.fromRectAndRadius(headRect, Radius.circular(headW * 0.34));
    canvas.drawRRect(head, Paint()..color = body);

    // Visor
    final visorRect = Rect.fromCenter(
      center: Offset(cx, headRect.top + headH * 0.5),
      width: headW * 0.8,
      height: headH * 0.52,
    );
    final visorR = RRect.fromRectAndRadius(visorRect, Radius.circular(visorRect.height * 0.46));
    canvas.drawRRect(visorR, Paint()..color = visor);
    // A thin rim so the visor reads as glass on either body colour.
    canvas.drawRRect(
      visorR,
      Paint()
        ..color = shade.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, w * 0.012),
    );

    // Eyes
    final lookX = (pose.lookX + glance).clamp(-1.0, 1.0);
    final eyeDx = visorRect.width * 0.1 * lookX;
    final eyeDy = visorRect.height * 0.14 * pose.lookY;
    final eyeGap = visorRect.width * 0.21;
    final eyeW = visorRect.width * 0.16;
    final eyeHFull = visorRect.height * 0.46;
    final open = (pose.eyeOpen * (1 - blink)).clamp(0.06, 1.0);
    final eyePaint = Paint()..color = eye;
    for (final side in const [-1.0, 1.0]) {
      final c = Offset(visorRect.center.dx + side * eyeGap + eyeDx, visorRect.center.dy + eyeDy);
      if (pose.happy > 0.5) {
        // "^ ^": an upward arc.
        final arc = Path()
          ..moveTo(c.dx - eyeW * 0.6, c.dy + eyeHFull * 0.12)
          ..quadraticBezierTo(c.dx, c.dy - eyeHFull * 0.5 * pose.happy, c.dx + eyeW * 0.6, c.dy + eyeHFull * 0.12);
        canvas.drawPath(
          arc,
          Paint()
            ..color = eye
            ..style = PaintingStyle.stroke
            ..strokeWidth = eyeW * 0.42
            ..strokeCap = StrokeCap.round,
        );
      } else {
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: eyeW, height: eyeHFull * open),
          Radius.circular(eyeW),
        );
        canvas.drawRRect(r, eyePaint);
      }
      // Worried brows: short lines tilted toward the middle.
      if (pose.brow > 0.05) {
        final by = c.dy - eyeHFull * 0.62;
        final inner = Offset(c.dx - side * eyeW * 0.7, by + eyeHFull * 0.12 * pose.brow);
        final outer = Offset(c.dx + side * eyeW * 0.7, by - eyeHFull * 0.04 * pose.brow);
        canvas.drawLine(
          inner,
          outer,
          Paint()
            ..color = eye.withValues(alpha: 0.9 * pose.brow)
            ..strokeWidth = eyeW * 0.28
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Mouth: a short line under the visor, opening while talking.
    final mouthY = visorRect.bottom + (headRect.bottom - visorRect.bottom) * 0.48;
    final talk = talking ? (0.5 + 0.5 * math.sin(phase * tau * 9)).abs() : 0.0;
    final smile = pose.happy * headH * 0.04;
    final mouthW = headW * (0.16 + 0.04 * pose.happy);
    final mouthPaint = Paint()
      ..color = mouth
      ..strokeWidth = math.max(1.2, headH * 0.045)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (talk > 0.15) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, mouthY), width: mouthW, height: headH * 0.1 * talk),
          Radius.circular(headH),
        ),
        Paint()..color = mouth,
      );
    } else {
      final m = Path()
        ..moveTo(cx - mouthW / 2, mouthY)
        ..quadraticBezierTo(cx, mouthY + smile - pose.brow * headH * 0.03, cx + mouthW / 2, mouthY);
      canvas.drawPath(m, mouthPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KynoPainter old) => true;
}
