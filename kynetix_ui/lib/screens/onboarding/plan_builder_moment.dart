import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/user_profile.dart';
import '../../services/nutrition_target_engine.dart';
import '../../ui/k_rolling.dart';

// ─── Building your plan ───────────────────────────────────────────────────────
// Moment: the payoff of the questions. Trigger: arriving on "Your targets"
// with answers the person hasn't seen worked out yet.
//
// Nothing here is a fake loader. The sheet is the real arithmetic, written
// out line by line from the person's own answers: what they burn, what the
// goal does to it, how training and rest days split it, protein, and how
// their plates will be read. As each line lands, its number rolls in and the
// figure at the top follows it like an odometer (maintenance first, then the
// goal moves only the digits that change). The calorie ring closes when the
// daily target is known, the protein ring when protein is. Then the sheet
// simply stays: the moment IS the summary, so there is no hand-off jump.
//
// Timing: about 3.4 s. A tap anywhere settles it at once. Reduced motion, or
// a return visit with the same answers, shows the settled sheet straight
// away. Haptics: a selection tick when the calorie target forms and when
// protein lands, one success when the sheet settles. Settled, each line can
// be tapped open to show how it was worked out.

/// The answers the plan is built from, plus the plan itself (computed by
/// [NutritionTargetEngine], never re-derived here).
class PlanBuildInputs {
  const PlanBuildInputs({
    required this.plan,
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.trainingDaysLabel,
    required this.goal,
    required this.teen,
    this.portionAnchor,
  });

  final WeeklyTargetPlan plan;
  final double heightCm;
  final double weightKg;
  final int age;

  /// As picked, e.g. "4 to 5 days".
  final String trainingDaysLabel;
  final Goal goal;
  final bool teen;
  final PortionAnchor? portionAnchor;

  /// Changes whenever anything shown on the sheet would change, so a return
  /// visit with the same answers doesn't replay the moment.
  String get signature => [
        plan.maintenanceCalories.round(),
        plan.avgDailyCalories.round(),
        plan.avgDailyProtein.round(),
        plan.trainingDayCalories.round(),
        plan.restDayCalories.round(),
        heightCm.round(),
        weightKg,
        age,
        trainingDaysLabel,
        goal,
        teen,
        portionAnchor?.name,
      ].join('|');
}

/// One line of the worked-out sheet.
class PlanLine {
  const PlanLine({
    required this.label,
    required this.detail,
    required this.why,
    this.number,
    this.signed = false,
    this.unit = '',
    this.word,
  });

  final String label;
  final String detail;

  /// How it was worked out, shown when the settled line is tapped.
  final String why;

  /// The line's value, or null for a word value ([word]).
  final int? number;

  /// Show a + on positive numbers (the goal's change).
  final bool signed;
  final String unit;
  final String? word;

  String get valueText {
    if (word != null) return word!;
    final n = number ?? 0;
    final digits = KRollingNumber.thousandsOf(n);
    return signed && n > 0 ? '+$digits' : digits;
  }
}

String _num(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// The sheet's lines for [i]. Public for tests: the copy is part of the
/// contract (teen mode never talks about deficits or fat loss).
@visibleForTesting
List<PlanLine> planLines(PlanBuildInputs i) {
  final p = i.plan;
  final burn = p.maintenanceCalories.round();
  final avg = p.avgDailyCalories.round();
  final delta = avg - burn;
  final train = p.trainingDayCalories.round();
  final rest = p.restDayCalories.round();
  final protein = p.avgDailyProtein.round();
  final perKg = i.weightKg > 0 ? p.avgDailyProtein / i.weightKg : 0.0;
  final days = i.trainingDaysLabel.toLowerCase();

  final burnLine = PlanLine(
    label: 'What you burn',
    detail: '${_num(i.heightCm)} cm, ${_num(i.weightKg)} kg, age ${i.age}, '
        'training $days',
    why: i.teen
        ? 'The energy equation made for 13 to 17 year olds, with your '
            'training days. It already counts what growing takes.'
        : 'Your resting burn from height, weight, age and sex, times how much '
            'you move with $days of training a week.',
    number: burn,
    unit: ' kcal',
  );

  final PlanLine goalLine;
  if (i.teen) {
    final building = i.goal == kLeanBulk || i.goal == kBulk;
    goalLine = building
        ? PlanLine(
            label: 'Building up',
            detail: 'A small surplus',
            why: 'A little over what you burn, to fuel growing and training.',
            number: delta,
            signed: true,
            unit: ' kcal',
          )
        : PlanLine(
            label: 'Your goal',
            detail: 'Held at what you burn',
            why: 'In teen mode your food target never goes below what a '
                'growing body needs. Training does the rest.',
            number: delta,
            signed: true,
            unit: ' kcal',
          );
  } else {
    final (label, detail, why) = switch (i.goal) {
      kFatLoss => (
          'Fat loss',
          'A steady deficit',
          'Far enough under your burn for steady progress, close enough that '
              'training still feels strong.',
        ),
      kRecomposition => (
          'Recomp',
          'A small deficit, protein high',
          'Just under your burn, with protein high so training keeps '
              'building muscle while fat comes off slowly.',
        ),
      kLeanBulk => (
          'Lean bulk',
          'A small surplus',
          'A little over your burn, so most of what you gain is muscle.',
        ),
      kBulk => (
          'Bulk',
          'A bigger surplus',
          'Further over your burn to grow faster. Some fat comes along; '
              'that is the trade.',
        ),
      _ => (
          'Maintenance',
          'Hold your weight',
          'Eat what you burn. Same weight, better body, while training does '
              'its work.',
        ),
    };
    goalLine = PlanLine(
      label: label,
      detail: detail,
      why: why,
      number: delta,
      signed: true,
      unit: ' kcal',
    );
  }

  final spread = train - rest;
  final splitWhy = spread > 0
      ? 'Training days get $spread kcal more than rest days. Across your '
          'week it still averages ${KRollingNumber.thousandsOf(avg)} kcal a day.'
      : 'Every day gets the same target.';

  final (plateDetail, plateWord, plateWhy) = switch (i.portionAnchor) {
    PortionAnchor.carbAnchored => (
        'Roti or rice first',
        'Set',
        'Log "2 roti with dal" and the dal is sized to the 2 roti, the way '
            'you actually eat.',
      ),
    PortionAnchor.curryAnchored => (
        'Dal or curry first',
        'Set',
        'Log "rice with rajma" and the rajma counts as the main dish, the way '
            'you actually eat.',
      ),
    PortionAnchor.balanced => (
        'Balanced',
        'Set',
        'Dal and sabzi count as an equal partner to your roti or rice.',
      ),
    null => (
        'Not set yet',
        'Later',
        'Kyno starts with a balanced plate and learns yours from what you '
            'log. You can set it in your profile anytime.',
      ),
  };

  return [
    burnLine,
    goalLine,
    PlanLine(
      label: 'Training days',
      detail: 'A little more fuel when you lift',
      why: splitWhy,
      number: train,
      unit: ' kcal',
    ),
    PlanLine(
      label: 'Rest days',
      detail: 'A little less when you rest',
      why: splitWhy,
      number: rest,
      unit: ' kcal',
    ),
    PlanLine(
      label: 'Protein',
      detail: 'About ${perKg.toStringAsFixed(1)} g per kg of body weight',
      why: 'Enough to build and keep muscle. It is set on your weight up to '
          'a BMI of 27, so it follows muscle, not extra body fat.',
      number: protein,
      unit: ' g',
    ),
    PlanLine(
      label: 'Your plates',
      detail: plateDetail,
      why: plateWhy,
      word: plateWord,
    ),
  ];
}

/// The "Your targets" step: the plan written out from the person's answers.
class PlanBuilderMoment extends StatefulWidget {
  const PlanBuilderMoment({
    super.key,
    required this.inputs,
    required this.play,
    this.onSettled,
  });

  final PlanBuildInputs inputs;

  /// Play the build. False shows the settled sheet (already seen, same
  /// answers).
  final bool play;

  /// Called once when the sheet is settled (built, skipped or shown settled).
  final VoidCallback? onSettled;

  /// The whole build, first line to settled.
  static const total = Duration(milliseconds: 3400);

  /// Where each line starts landing, as a fraction of [total]. The last one
  /// lands with room to read it before the sheet settles.
  static const lineStarts = [0.03, 0.17, 0.33, 0.44, 0.60, 0.74];
  static const _landing = 0.12;

  @override
  State<PlanBuilderMoment> createState() => _PlanBuilderMomentState();
}

class _PlanBuilderMomentState extends State<PlanBuilderMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PlanBuilderMoment.total,
    // The timeline is the arithmetic being written; reduced motion is
    // handled by settling, not by a sped-up clock.
    animationBehavior: AnimationBehavior.preserve,
  );

  late final List<PlanLine> _lines = planLines(widget.inputs);

  /// Lines landed so far (0 to all).
  int _landed = 0;
  bool _settled = false;

  /// Settled without the build playing: numbers appear without rolling.
  bool _instant = false;
  bool _started = false;
  final Set<int> _open = {};

  int get _goalIndex => 1;
  int get _proteinIndex => 4;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduced = KMotion.reduced(context);
    if (!widget.play || reduced) {
      _instant = true;
      _landed = _lines.length;
      _c.value = 1;
      _settle(haptic: widget.play);
      return;
    }
    _c
      ..addListener(_onTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _settle(haptic: true);
      })
      ..forward();
  }

  void _onTick() {
    var n = 0;
    for (final start in PlanBuilderMoment.lineStarts) {
      if (_c.value >= start) n++;
    }
    if (n == _landed) return;
    final before = _landed;
    setState(() => _landed = n);
    // The two numbers that make the target: a quiet tick as each forms.
    final formed = before <= _goalIndex && n > _goalIndex ||
        before <= _proteinIndex && n > _proteinIndex;
    if (formed && !_settled) KHaptics.select();
  }

  void _settle({required bool haptic}) {
    if (_settled) return;
    _settled = true;
    if (haptic) KHaptics.success();
    if (mounted) setState(() => _landed = _lines.length);
    // Never call back into the parent mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSettled?.call();
    });
  }

  /// Tap during the build: everything lands at once.
  void _skip() {
    if (_settled) return;
    _instant = true;
    _c
      ..removeListener(_onTick)
      ..stop()
      ..value = 1;
    _settle(haptic: true);
  }

  /// Entrance progress of each line (0 to 1), made once: a CurvedAnimation
  /// listens to its parent until disposed.
  late final List<CurvedAnimation> _lineAnims = [
    for (final a in PlanBuilderMoment.lineStarts)
      CurvedAnimation(
        parent: _c,
        curve: Interval(a, (a + PlanBuilderMoment._landing).clamp(0.0, 1.0), curve: KMotion.easeOut),
      ),
  ];

  @override
  void dispose() {
    for (final a in _lineAnims) {
      a.dispose();
    }
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.inputs.plan;
    final kcal = _landed > _goalIndex
        ? p.avgDailyCalories.round()
        : (_landed > 0 ? p.maintenanceCalories.round() : null);
    final protein = _landed > _proteinIndex ? p.avgDailyProtein.round() : null;

    final sheet = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Crest(
          kcal: kcal,
          protein: protein,
          calRing: _landed > _goalIndex ? 1.0 : 0.0,
          proteinRing: protein != null ? 1.0 : 0.0,
          settled: _settled,
          instant: _instant,
          onSkip: _settled ? null : _skip,
        ),
        const SizedBox(height: KSpacing.lg),
        for (var i = 0; i < _lines.length; i++)
          _LedgerRow(
            line: _lines[i],
            entrance: _instant ? kAlwaysCompleteAnimation : _lineAnims[i],
            landed: i < _landed,
            writing: !_settled && i == _landed - 1,
            instant: _instant,
            open: _open.contains(i),
            onTap: _settled
                ? () {
                    KHaptics.select();
                    setState(() => _open.contains(i) ? _open.remove(i) : _open.add(i));
                  }
                : null,
          ),
        AnimatedOpacity(
          opacity: _settled ? 1 : 0,
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.easeOut,
          child: Padding(
            padding: const EdgeInsets.only(top: KSpacing.md),
            child: Text(
              'Tap a line to see how it was worked out. These are estimates, '
              'not medical advice; tweak them anytime in your profile.',
              style: KText.caption.copyWith(color: KColor.textMuted, height: 1.45),
            ),
          ),
        ),
      ],
    );

    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(KSpacing.xxl, 0, KSpacing.xxl, KSpacing.xxl),
      child: sheet,
    );

    if (_settled) return body;
    // While building: the whole sheet is one "tap to skip" target, and a
    // screen reader hears what is happening instead of half-written lines.
    return Semantics(
      container: true,
      button: true,
      liveRegion: true,
      label: 'Working out your targets from your answers. Double tap to skip.',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: body,
      ),
    );
  }
}

// ─── Crest: the rings and the figure the sheet adds up to ────────────────────

class _Crest extends StatelessWidget {
  const _Crest({
    required this.kcal,
    required this.protein,
    required this.calRing,
    required this.proteinRing,
    required this.settled,
    required this.instant,
    required this.onSkip,
  });

  final int? kcal;
  final int? protein;
  final double calRing;
  final double proteinRing;
  final bool settled;
  final bool instant;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final big = KText.numDisplay.copyWith(fontSize: 44, height: 1.0);
    final label = settled
        ? 'Your daily target: ${KRollingNumber.thousandsOf(kcal ?? 0)} kcal '
            'and ${protein ?? 0} g protein.'
        : null;
    return Semantics(
      container: true,
      liveRegion: settled,
      label: label,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KDabbaRings(
            size: 104,
            stroke: 10,
            sweepIn: false,
            duration: instant ? Duration.zero : KMotion.slow,
            rings: [
              KRingSpec(calRing, KRingColors.calories),
              KRingSpec(proteinRing, KRingColors.protein),
            ],
          ),
          const SizedBox(width: KSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: KMotion.of(context, KMotion.quick),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: AlignmentDirectional.centerStart,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          settled ? 'Your daily target' : 'Working it out from your answers',
                          key: ValueKey(settled),
                          style: KText.caption.copyWith(
                            color: KColor.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (onSkip != null)
                      Semantics(
                        button: true,
                        label: 'Skip',
                        excludeSemantics: true,
                        child: InkResponse(
                          onTap: onSkip,
                          radius: 24,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: KSpacing.sm,
                              vertical: KSpacing.xs,
                            ),
                            child: Text(
                              'Skip',
                              style: KText.caption.copyWith(
                                color: KColor.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: KSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: AnimatedOpacity(
                        opacity: kcal == null ? 0.0 : 1.0,
                        duration: KMotion.of(context, KMotion.quick),
                        child: KRollingNumber.int(
                          kcal ?? 0,
                          fromZero: !instant,
                          duration: instant ? Duration.zero : KMotion.slow,
                          alignment: AlignmentDirectional.centerStart,
                          style: big,
                        ),
                      ),
                    ),
                    Text(
                      ' kcal',
                      style: KText.numMedium.copyWith(color: KColor.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.sm),
                AnimatedOpacity(
                  opacity: protein == null ? 0.0 : 1.0,
                  duration: KMotion.of(context, KMotion.standard),
                  curve: KMotion.easeOut,
                  child: Row(
                    children: [
                      KDot(color: KColor.protein, size: 7),
                      const SizedBox(width: KSpacing.sm),
                      KRollingNumber.int(
                        protein ?? 0,
                        fromZero: !instant,
                        duration: instant ? Duration.zero : null,
                        alignment: AlignmentDirectional.centerStart,
                        style: KText.numSmall.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          ' g protein',
                          style: KText.bodyMedium.copyWith(color: KColor.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── One line of the sheet ────────────────────────────────────────────────────
// Lands by rising 8 px and fading in, its value rolls up from 0 and its rule
// draws left to right, like a line written and underlined. While it is the
// line being written, a short ember tick sits at its left edge.

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.line,
    required this.entrance,
    required this.landed,
    required this.writing,
    required this.instant,
    required this.open,
    required this.onTap,
  });

  final PlanLine line;
  final Animation<double> entrance;
  final bool landed;
  final bool writing;
  final bool instant;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = line.word != null
        ? Text(
            line.valueText,
            style: KText.numSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          )
        : KRollingNumber(
            // Mounted only once landed, so it rolls up as the line lands.
            line.valueText,
            fromZero: !instant,
            duration: instant ? Duration.zero : null,
            style: KText.numSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.label,
                      style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line.detail,
                      style: KText.caption.copyWith(color: KColor.textMuted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.md),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (landed) value,
                  if (landed && line.unit.isNotEmpty)
                    Text(
                      line.unit,
                      style: KText.caption.copyWith(color: KColor.textSecondary),
                    ),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(width: KSpacing.xs),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: KMotion.of(context, KMotion.quick),
                  curve: KMotion.easeOut,
                  child: Icon(Icons.expand_more_rounded, size: 18, color: KColor.textMuted),
                ),
              ],
            ],
          ),
          AnimatedSize(
            duration: KMotion.of(context, KMotion.standard),
            curve: KMotion.easeOut,
            alignment: Alignment.topLeft,
            child: open
                ? Padding(
                    padding: const EdgeInsets.only(top: KSpacing.sm),
                    child: Text(
                      line.why,
                      style: KText.caption.copyWith(color: KColor.textSecondary, height: 1.45),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );

    final rule = Container(height: 1, color: KColor.hairline);

    final content = Stack(
      // The pen tick sits just outside the row's left edge.
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row,
            // The underline draws as the line lands.
            AnimatedBuilder(
              animation: entrance,
              builder: (context, child) => Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: FractionallySizedBox(
                  widthFactor: entrance.value.clamp(0.0, 1.0),
                  child: child,
                ),
              ),
              child: rule,
            ),
          ],
        ),
        // The pen: where the sheet is being written right now.
        PositionedDirectional(
          start: -KSpacing.md,
          top: KSpacing.md + 2,
          child: AnimatedOpacity(
            opacity: writing ? 1 : 0,
            duration: KMotion.of(context, KMotion.quick),
            child: Container(
              width: 2,
              height: 16,
              decoration: BoxDecoration(color: KColor.ember, borderRadius: KRadius.pill),
            ),
          ),
        ),
      ],
    );

    final animated = AnimatedBuilder(
      animation: entrance,
      builder: (context, child) {
        final t = entrance.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
        );
      },
      child: content,
    );

    if (onTap == null) return animated;
    return Semantics(
      button: true,
      expanded: open,
      label: '${line.label}, ${line.detail}, ${line.valueText}${line.unit}'
          '${open ? '. ${line.why}' : ''}',
      hint: open ? null : 'Shows how it was worked out',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: KRadius.md,
        child: animated,
      ),
    );
  }
}
