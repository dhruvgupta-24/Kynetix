import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../ui/k_rolling.dart';
import '../../widgets/kyno_avatar.dart';
import 'scene_backdrop.dart';

/// The story before the questions, in three beats.
///
/// 1. A plate: a line someone typed ("2 roti, 1 katori dal") turns into
///    numbers. That's the food half of the app.
/// 2. A lift: the same exercise, week after week, the weight rolling up.
///    That's the training half.
/// 3. Kyno: the coach who reads both, introducing itself.
///
/// Each beat holds for a few seconds or until a tap; "Skip" leaves at once.
/// Under reduced motion nothing animates: each beat appears complete and
/// waits for a tap.
class OnboardingPrologue extends StatefulWidget {
  const OnboardingPrologue({super.key, required this.onDone});

  final VoidCallback onDone;

  static const beatDuration = Duration(milliseconds: 3600);

  @override
  State<OnboardingPrologue> createState() => _OnboardingPrologueState();
}

class _Beat {
  const _Beat(this.tone, this.scene, this.align, this.eyebrow, this.title, this.body);
  final KTone tone;
  final String scene;
  final Alignment align;
  final String eyebrow;
  final String title;
  final String body;
}

const _beats = [
  _Beat(KTone.fuel, KScene.thali, Alignment(0, 0.1), 'Your food',
      'Every plate is a story.', 'Type it the way you would say it. Kynetix does the maths.'),
  _Beat(KTone.train, KScene.lifter, Alignment(-0.4, 0), 'Your training',
      'Every rep adds a line.', 'Log the sets. Watch the numbers climb, week after week.'),
  _Beat(KTone.kyno, KScene.rack, Alignment(0.4, 0.2), 'Your coach',
      "I read both. That's my job.", "I'm Kyno. I connect what you eat to how you lift, and tell you what to do next."),
];

class _OnboardingPrologueState extends State<OnboardingPrologue> {
  int _beat = 0;
  Timer? _timer;
  bool _left = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    // Reduced motion: no auto-advance; the reader sets the pace.
    if (KMotion.reduced(context)) return;
    if (_beat < _beats.length - 1) {
      _timer = Timer(OnboardingPrologue.beatDuration, _next);
    }
  }

  void _next() {
    if (!mounted || _left) return;
    if (_beat >= _beats.length - 1) {
      _leave();
      return;
    }
    KHaptics.select();
    setState(() => _beat++);
    _schedule();
  }

  void _leave() {
    if (_left) return;
    _left = true;
    _timer?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final beat = _beats[_beat];
    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final heroH = (size.height * 0.5).clamp(280.0, 480.0);
    final last = _beat == _beats.length - 1;
    return KPage(
      tone: beat.tone,
      intensity: 0.5,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: last ? null : _next,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroH + topInset,
              child: KSceneBackdrop(asset: beat.scene, alignment: beat.align, veil: 1.1),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(KSpacing.xxl, KSpacing.sm, KSpacing.sm, 0),
                    child: Row(
                      children: [
                        _BeatDots(count: _beats.length, current: _beat),
                        const Spacer(),
                        if (!last)
                          TextButton(
                            onPressed: _leave,
                            child: Text('Skip', style: KText.bodyMedium.copyWith(color: KColor.textSecondary)),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
                    child: AnimatedSwitcher(
                      duration: KMotion.of(context, KMotion.emphasized),
                      switchInCurve: KMotion.decelerate,
                      switchOutCurve: KMotion.accelerate,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_beat),
                        child: _BeatContent(beat: beat, index: _beat),
                      ),
                    ),
                  ),
                  const SizedBox(height: KSpacing.xxl),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(KSpacing.xxl, 0, KSpacing.xxl, KSpacing.lg),
                    child: AnimatedSwitcher(
                      duration: KMotion.of(context, KMotion.standard),
                      child: last
                          ? KButton(
                              key: const ValueKey('begin'),
                              label: "Let's begin",
                              width: double.infinity,
                              icon: Icons.arrow_forward_rounded,
                              onTap: _leave,
                            )
                          : Semantics(
                              key: const ValueKey('tap'),
                              button: true,
                              label: 'Next',
                              onTap: _next,
                              child: SizedBox(
                                height: 52,
                                child: Center(
                                  child: Text(
                                    'Tap to continue',
                                    style: KText.caption.copyWith(color: KColor.textMuted),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatContent extends StatelessWidget {
  const _BeatContent({required this.beat, required this.index});
  final _Beat beat;
  final int index;

  @override
  Widget build(BuildContext context) {
    final accent = switch (beat.tone) {
      KTone.fuel => KColor.fuel,
      KTone.train => KColor.train,
      _ => KColor.kyno,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        switch (index) {
          0 => const _PlateDemo(),
          1 => const _LiftDemo(),
          _ => const Padding(
              padding: EdgeInsets.only(bottom: KSpacing.lg),
              child: KynoAvatar(size: 120, mood: KynoMood.celebrate),
            ),
        },
        const SizedBox(height: KSpacing.xl),
        Text(
          beat.eyebrow,
          style: KText.caption.copyWith(color: accent, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        const SizedBox(height: KSpacing.sm),
        Semantics(
          header: true,
          child: Text(beat.title, style: KText.display.copyWith(fontSize: 34, height: 1.06)),
        ),
        const SizedBox(height: KSpacing.sm),
        Text(beat.body, style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 16, height: 1.45)),
      ],
    );
  }
}

/// Beat 1: a typed meal becomes numbers.
class _PlateDemo extends StatefulWidget {
  const _PlateDemo();

  @override
  State<_PlateDemo> createState() => _PlateDemoState();
}

class _PlateDemoState extends State<_PlateDemo> {
  static const _typed = '2 roti, 1 katori dal, salad';
  int _shown = 0;
  bool _counted = false;
  Timer? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_t != null) return;
    if (KMotion.reduced(context)) {
      _shown = _typed.length;
      _counted = true;
      return;
    }
    _t = Timer.periodic(const Duration(milliseconds: 42), (t) {
      if (!mounted) return t.cancel();
      if (_shown < _typed.length) {
        setState(() => _shown++);
      } else {
        t.cancel();
        setState(() => _counted = true);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _typed.substring(0, _shown);
    return _DemoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: KColor.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _shown < _typed.length ? '$text|' : text,
                  style: KText.bodyMedium.copyWith(fontSize: 16),
                  semanticsLabel: _typed,
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          Row(
            children: [
              Expanded(child: _Stat(label: 'kcal', value: _counted ? 395 : 0, color: KColor.fuel)),
              Expanded(child: _Stat(label: 'protein g', value: _counted ? 15 : 0, color: KColor.protein)),
              Expanded(child: _Stat(label: 'carbs g', value: _counted ? 58 : 0, color: KColor.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Beat 2: the same lift, four weeks, rolling up.
class _LiftDemo extends StatefulWidget {
  const _LiftDemo();

  @override
  State<_LiftDemo> createState() => _LiftDemoState();
}

class _LiftDemoState extends State<_LiftDemo> {
  static const _weeks = [60, 62, 65, 67];
  int _week = 0;
  Timer? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_t != null) return;
    if (KMotion.reduced(context)) {
      _week = _weeks.length - 1;
      return;
    }
    _t = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (!mounted) return t.cancel();
      if (_week < _weeks.length - 1) {
        KHaptics.select();
        setState(() => _week++);
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final train = KColor.train;
    final d = KMotion.of(context, KMotion.emphasized);
    return _DemoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Bench press',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              KRollingNumber(
                '${_weeks[_week]}',
                style: KText.numDisplay.copyWith(fontSize: 30, color: KColor.textPrimary),
                semanticsLabel: '${_weeks.last} kilograms',
              ),
              Text(' kg × 8', style: KText.caption.copyWith(color: KColor.textMuted)),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          SizedBox(
            height: 46,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _weeks.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedContainer(
                      duration: d,
                      curve: KMotion.emphasizedCurve,
                      height: i <= _week ? 14.0 + (_weeks[i] - 58) * 4.0 : 4,
                      decoration: BoxDecoration(
                        color: i <= _week ? train.withValues(alpha: 0.35 + 0.65 * (i + 1) / _weeks.length) : KColor.divider,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 1; i <= _weeks.length; i++) ...[
                if (i > 1) const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Week $i', style: KText.caption.copyWith(fontSize: 11, color: KColor.textMuted)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: KRollingNumber.int(value, style: KText.numDisplay.copyWith(fontSize: 28, color: color)),
        ),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.caption.copyWith(color: KColor.textMuted)),
      ],
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(KSpacing.lg),
        decoration: BoxDecoration(
          color: KColor.card.withValues(alpha: KColor.isDark ? 0.86 : 0.92),
          borderRadius: KRadius.lg,
          border: Border.all(color: KColor.border),
          boxShadow: KShadow.card,
        ),
        child: child,
      ),
    );
  }
}

class _BeatDots extends StatelessWidget {
  const _BeatDots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final d = KMotion.of(context, KMotion.standard);
    return Semantics(
      label: 'Part ${current + 1} of $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: d,
              curve: KMotion.emphasizedCurve,
              margin: const EdgeInsets.only(right: 6),
              width: i == current ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i <= current ? KColor.ink : KColor.fg.withValues(alpha: 0.18),
                borderRadius: KRadius.pill,
              ),
            ),
        ],
      ),
    );
  }
}
