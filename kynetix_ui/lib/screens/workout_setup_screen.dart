import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../data/exercise_classification.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import '../widgets/exercise_picker_sheet.dart';

// ─── Training Onboarding Questionnaire Enums ────────────────────────────────

enum TrainingExperience {
  beginner(
    'Beginner',
    'New to lifting, or coming back after a break.',
    Icons.signal_cellular_alt_1_bar_rounded,
  ),
  intermediate(
    'Intermediate',
    'Lifting steadily for 1-3 years.',
    Icons.signal_cellular_alt_2_bar_rounded,
  ),
  advanced(
    'Advanced',
    '3+ years in. Chasing the small gains now.',
    Icons.signal_cellular_alt_rounded,
  );

  final String label;
  final String description;
  final IconData icon;
  const TrainingExperience(this.label, this.description, this.icon);
}

enum TrainingGoal {
  buildMuscle(
    'Build muscle',
    'More volume, moderate to high reps. Size first.',
    KIcons.upper,
  ),
  buildStrength(
    'Build strength',
    'Heavy compound lifts, lower reps.',
    KIcons.train,
  ),
  loseFat(
    'Lose fat',
    'Keep the muscle, burn more, train denser.',
    KIcons.calories,
  ),
  generalFitness(
    'General fitness',
    'Move well, stay strong, keep your joints happy.',
    KIcons.cardio,
  );

  final String label;
  final String description;
  final IconData icon;
  const TrainingGoal(this.label, this.description, this.icon);
}

// ─── WorkoutSetupScreen ───────────────────────────────────────────────────────

class WorkoutSetupScreen extends StatefulWidget {
  final bool editMode;

  const WorkoutSetupScreen({super.key, this.editMode = false});

  @override
  State<WorkoutSetupScreen> createState() => _WorkoutSetupScreenState();
}

class _WorkoutSetupScreenState extends State<WorkoutSetupScreen> {
  // Steps:
  //   0: Experience Level Selection
  //   1: Training Days Selection
  //   2: Training Goal Selection
  //   3: Split Recommendation Page
  //   4: Customize Day Names & Exercises (was step 1 in legacy code)
  int _step = 0;
  int _activeCustomizingWeekday = 1;

  TrainingExperience _experience = TrainingExperience.intermediate;
  int _daysPerWeek = 4;
  TrainingGoal _goal = TrainingGoal.buildMuscle;

  final Map<int, bool> _selectedDays = {
    1: true,
    2: true,
    3: true,
    4: true,
    5: true,
    6: true,
    7: false,
  };

  final Map<int, TextEditingController> _nameControllers = {};
  final Map<int, List<Exercise>> _dayExercises = {};

  static const _defaultNames = {
    1: 'Chest + Triceps',
    2: 'Back + Biceps',
    3: 'Shoulders',
    4: 'Legs',
    5: 'Push',
    6: 'Pull',
    7: 'Rest Day',
  };

  static const _shortDays = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  @override
  void initState() {
    super.initState();
    if (widget.editMode) {
      _step =
          4; // Skip directly to customization step when editing existing split
    }
    _initDefaultFields();
  }

  void _initDefaultFields() {
    final existing = WorkoutService.instance.split;
    for (int wd = 1; wd <= 7; wd++) {
      final existingDay = existing.dayFor(wd);
      final name = existingDay?.name ?? _defaultNames[wd] ?? 'Day $wd';
      _nameControllers[wd] = TextEditingController(text: name);
      _dayExercises[wd] = List.of(
        existingDay?.exercises ??
            exerciseLibraryByDay[_defaultNames[wd] ?? ''] ??
            const [],
      );
      if (widget.editMode) {
        _selectedDays[wd] = existingDay != null && !existingDay.isRestDay;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _trainingDayCount => _selectedDays.values.where((v) => v).length;

  // ── Recommendation Engine ──────────────────────────────────────────────────

  WorkoutSplit _generateRecommendedSplit() {
    final days = List.generate(7, (i) {
      final wd = i + 1;
      return SplitDay(weekday: wd, name: 'Rest Day', exercises: const []);
    });

    final allEx = deduplicatedLibrary;
    Exercise? findEx(String id) => allEx.where((e) => e.id == id).firstOrNull;

    if (_daysPerWeek == 3) {
      final fullBodyEx = [
        findEx('bench_press'),
        findEx('seated_cable_row'),
        findEx('db_shoulder_press'),
        findEx('leg_press'),
        findEx('bb_curl'),
      ].whereType<Exercise>().toList();
      days[0] = SplitDay(
        weekday: 1,
        name: 'Full Body A',
        exercises: fullBodyEx,
      );
      days[2] = SplitDay(
        weekday: 3,
        name: 'Full Body B',
        exercises: fullBodyEx,
      );
      days[4] = SplitDay(
        weekday: 5,
        name: 'Full Body C',
        exercises: fullBodyEx,
      );
    } else if (_daysPerWeek == 4) {
      final upperEx = [
        findEx('bench_press'),
        findEx('lat_pulldown'),
        findEx('db_shoulder_press'),
        findEx('seated_cable_row'),
        findEx('tri_pushdown'),
        findEx('bb_curl'),
      ].whereType<Exercise>().toList();
      final lowerEx = [
        findEx('leg_press'),
        findEx('rdl'),
        findEx('leg_curl'),
        findEx('calf_raise'),
      ].whereType<Exercise>().toList();
      days[0] = SplitDay(weekday: 1, name: 'Upper Day A', exercises: upperEx);
      days[1] = SplitDay(weekday: 2, name: 'Lower Day A', exercises: lowerEx);
      days[3] = SplitDay(weekday: 4, name: 'Upper Day B', exercises: upperEx);
      days[4] = SplitDay(weekday: 5, name: 'Lower Day B', exercises: lowerEx);
    } else if (_daysPerWeek == 5) {
      days[0] = SplitDay(
        weekday: 1,
        name: 'Push',
        exercises: exerciseLibraryByDay['Push']!,
      );
      days[1] = SplitDay(
        weekday: 2,
        name: 'Pull',
        exercises: exerciseLibraryByDay['Pull']!,
      );
      days[2] = SplitDay(
        weekday: 3,
        name: 'Legs',
        exercises: exerciseLibraryByDay['Legs']!,
      );
      final upperEx = [
        findEx('bench_press'),
        findEx('lat_pulldown'),
        findEx('db_shoulder_press'),
        findEx('seated_cable_row'),
      ].whereType<Exercise>().toList();
      final lowerEx = [
        findEx('leg_press'),
        findEx('rdl'),
        findEx('leg_curl'),
      ].whereType<Exercise>().toList();
      days[4] = SplitDay(weekday: 5, name: 'Upper', exercises: upperEx);
      days[5] = SplitDay(weekday: 6, name: 'Lower', exercises: lowerEx);
    } else {
      days[0] = SplitDay(
        weekday: 1,
        name: 'Chest + Triceps',
        exercises: exerciseLibraryByDay['Chest + Triceps']!,
      );
      days[1] = SplitDay(
        weekday: 2,
        name: 'Back + Biceps',
        exercises: exerciseLibraryByDay['Back + Biceps']!,
      );
      days[2] = SplitDay(
        weekday: 3,
        name: 'Shoulders',
        exercises: exerciseLibraryByDay['Shoulders']!,
      );
      days[3] = SplitDay(
        weekday: 4,
        name: 'Legs',
        exercises: exerciseLibraryByDay['Legs']!,
      );
      days[4] = SplitDay(
        weekday: 5,
        name: 'Push',
        exercises: exerciseLibraryByDay['Push']!,
      );
      days[5] = SplitDay(
        weekday: 6,
        name: 'Pull',
        exercises: exerciseLibraryByDay['Pull']!,
      );
    }

    return WorkoutSplit(
      id: 'recommended_${DateTime.now().millisecondsSinceEpoch}',
      name: '$_daysPerWeek-Day Recommended Split',
      days: days,
    );
  }

  void _applyRecommendation(WorkoutSplit split) {
    setState(() {
      for (int wd = 1; wd <= 7; wd++) {
        final d = split.dayFor(wd);
        if (d != null && !d.isRestDay) {
          _selectedDays[wd] = true;
          _nameControllers[wd]!.text = d.name;
          _dayExercises[wd] = List.from(d.exercises);
        } else {
          _selectedDays[wd] = false;
          _nameControllers[wd]!.text = 'Rest Day';
          _dayExercises[wd] = [];
        }
      }
      _step = 4;
    });
  }

  // ── Navigation Logic ───────────────────────────────────────────────────────

  void _goBack() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  void _goForward() {
    if (_step < 4) {
      setState(() => _step++);
    }
  }

  bool _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return;
    final days = <SplitDay>[];
    for (int wd = 1; wd <= 7; wd++) {
      final isTraining = _selectedDays[wd] == true;
      final name = _nameControllers[wd]!.text.trim().isEmpty
          ? (_defaultNames[wd] ?? 'Day $wd')
          : _nameControllers[wd]!.text.trim();
      days.add(
        SplitDay(
          weekday: wd,
          name: isTraining ? name : 'Rest Day',
          exercises: isTraining ? (_dayExercises[wd] ?? []) : [],
        ),
      );
    }

    var newSplit = WorkoutSplit(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'My Split',
      days: days,
    );
    // Saved untouched: still the Developer's Choice, keep its name.
    if (isUnchangedDevelopersChoice(newSplit)) newSplit = developersChoiceSplit;
    // Captured before the await: the result toast lands on the screen below.
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _finishing = true);
    try {
      await WorkoutService.instance.saveSplit(newSplit);
    } catch (_) {
      if (!mounted) return;
      setState(() => _finishing = false);
      KHaptics.reject();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't save your split. Try again in a moment."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    KHaptics.success();
    Navigator.of(context).pop(true);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            widget.editMode ? 'Split saved.' : "Split saved. Chalo, let's train.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _removeExercise(int weekday, Exercise ex) {
    setState(() => _dayExercises[weekday]!.remove(ex));
  }

  void _reorderExercise(int weekday, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex--;
      }
      final item = _dayExercises[weekday]!.removeAt(oldIndex);
      _dayExercises[weekday]!.insert(newIndex, item);
    });
  }

  Future<void> _addExercise(int weekday) async {
    final current = _dayExercises[weekday] ?? [];
    final excludeIds = current.map((c) => c.id).toSet();

    final picked = await showExercisePickerSheet(
      context,
      excludeIds: excludeIds,
    );

    if (picked != null && mounted) {
      setState(() => _dayExercises[weekday] = [...current, picked]);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KPage(
      tone: KTone.train,
      intensity: 0.8,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: _step > 0 && !widget.editMode
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: KColor.textPrimary,
                ),
                tooltip: 'Back',
                onPressed: _goBack,
              )
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: KColor.textPrimary,
                ),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          widget.editMode ? 'Edit training split' : 'Set up training',
          style: KText.h2.copyWith(fontSize: 17),
        ),
        bottom: widget.editMode
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KSpacing.xxl,
                    0,
                    KSpacing.xxl,
                    10,
                  ),
                  child: Semantics(
                    label: 'Step ${_step + 1} of 5',
                    child: KBar(
                      progress: (_step + 1) / 5,
                      colors: KGradient.train,
                      height: 4,
                      duration: KMotion.emphasized,
                    ),
                  ),
                ),
              ),
      ),
      body: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.emphasized),
        switchInCurve: KMotion.emphasizedCurve,
        switchOutCurve: KMotion.accelerate,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey('step_$_step'),
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    return switch (_step) {
      0 => _buildExperienceStep(),
      1 => _buildDaysStep(),
      2 => _buildGoalStep(),
      3 => _buildRecommendationStep(),
      4 => _buildCustomizeStep(),
      _ => const SizedBox(),
    };
  }

  /// Shared layout for the questionnaire steps: title, subtitle, a body that
  /// takes the remaining height, and a bottom CTA that respects the safe area.
  Widget _stepScaffold({
    required String title,
    required String subtitle,
    required Widget body,
    required Widget footer,
  }) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KSpacing.xxl,
          KSpacing.lg,
          KSpacing.xxl,
          KSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: KText.h1.copyWith(fontSize: 26)),
            const SizedBox(height: KSpacing.sm),
            Text(
              subtitle,
              style: KText.body.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: KSpacing.xxl),
            Expanded(child: body),
            const SizedBox(height: KSpacing.md),
            footer,
          ],
        ),
      ),
    );
  }

  Widget _continueButton({String label = 'Continue'}) => SizedBox(
    width: double.infinity,
    child: KButton(
      label: label,
      icon: Icons.arrow_forward_rounded,
      onTap: _goForward,
    ),
  );

  // ── Step 0: Experience ────────────────────────────────────────────────────

  Widget _buildExperienceStep() {
    return _stepScaffold(
      title: 'Experience level',
      subtitle:
          'Helps us size your weight jumps and weekly volume.',
      body: ListView(
        children: [
          for (final (i, exp) in TrainingExperience.values.indexed)
            KReveal(
              index: i,
              child: _ChoiceCard(
                icon: exp.icon,
                label: exp.label,
                description: exp.description,
                selected: _experience == exp,
                onTap: () => setState(() => _experience = exp),
              ),
            ),
        ],
      ),
      footer: _continueButton(),
    );
  }

  // ── Step 1: Days ──────────────────────────────────────────────────────────

  Widget _buildDaysStep() {
    return _stepScaffold(
      title: 'How many days?',
      subtitle:
          'Pick what you can actually stick to. Consistency beats ambition.',
      body: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: KSpacing.md,
        crossAxisSpacing: KSpacing.md,
        childAspectRatio: 1.05,
        children: [
          for (final (i, days) in [3, 4, 5, 6].indexed)
            KReveal(
              index: i,
              fromScale: 0.94,
              child: _DaysTile(
                days: days,
                selected: _daysPerWeek == days,
                onTap: () => setState(() => _daysPerWeek = days),
              ),
            ),
        ],
      ),
      footer: _continueButton(),
    );
  }

  // ── Step 2: Goal ──────────────────────────────────────────────────────────

  Widget _buildGoalStep() {
    return _stepScaffold(
      title: 'Primary focus',
      subtitle:
          'Shapes your exercise picks and rep ranges.',
      body: ListView(
        children: [
          for (final (i, goal) in TrainingGoal.values.indexed)
            KReveal(
              index: i,
              child: _ChoiceCard(
                icon: goal.icon,
                label: goal.label,
                description: goal.description,
                selected: _goal == goal,
                onTap: () => setState(() => _goal = goal),
              ),
            ),
        ],
      ),
      footer: _continueButton(label: 'See my recommended split'),
    );
  }

  // ── Step 3: Recommendation ────────────────────────────────────────────────

  Widget _buildRecommendationStep() {
    final split = _generateRecommendedSplit();
    final splitDays = split.days.where((d) => !d.isRestDay).toList();

    return _stepScaffold(
      title: 'Recommended split',
      subtitle:
          'Built from your answers, with enough volume and enough rest. You can tweak any day.',
      body: ListView.builder(
        itemCount: splitDays.length,
        itemBuilder: (context, i) {
          final d = splitDays[i];
          return KReveal(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KColor.card,
                borderRadius: KRadius.md,
                border: Border.all(color: _hairline),
                boxShadow: KShadow.card,
              ),
              child: Row(
                children: [
                  _WeekdayBadge(label: _shortDays[d.weekday]!),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: KText.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${d.exercises.length} exercises planned',
                          style: KText.caption.copyWith(
                            fontSize: 13,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KButton(
            label: 'Use this split',
            onTap: () => _applyRecommendation(split),
          ),
          const SizedBox(height: 10),
          KButton(
            label: "Use Developer's Choice",
            outlined: true,
            onTap: () => _applyRecommendation(developersChoiceSplit),
          ),
          const SizedBox(height: 10),
          KButton(
            label: 'Set up days myself',
            outlined: true,
            onTap: () {
              setState(() {
                _step = 4;
              });
            },
          ),
        ],
      ),
    );
  }

  // ── Step 4: Customize Days & Exercises ────────────────────────────────────

  Widget _buildCustomizeStep() {
    final activeWd = _activeCustomizingWeekday;

    return Column(
      children: [
        // Pinned weekday tabs
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.p,
            KSpacing.lg,
            KSpacing.p,
            KSpacing.md,
          ),
          child: _buildWeekdayTabs(),
        ),

        // Active tab configuration area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.p,
              0,
              KSpacing.p,
              KSpacing.xl,
            ),
            child: Column(children: [_buildActiveDayCard(activeWd)]),
          ),
        ),

        // Sticky anchored button area
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: KColor.divider),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpacing.p,
                KSpacing.md,
                KSpacing.p,
                KSpacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: KButton(
                  label: 'Save split',
                  loading: _finishing,
                  onTap: _trainingDayCount == 0 ? null : _finish,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayTabs() {
    return Container(
      padding: const EdgeInsets.all(KSpacing.xs),
      decoration: BoxDecoration(
        color: KColor.isDark
            ? KColor.fg.withValues(alpha: 0.04)
            : KColor.cardHigh.withValues(alpha: 0.7),
        borderRadius: KRadius.md,
        border: Border.all(color: _hairline),
      ),
      child: Row(
        children: List.generate(7, (i) {
          final wd = i + 1;
          final isActive = _activeCustomizingWeekday == wd;
          final isTraining = _selectedDays[wd] == true;

          return Expanded(
            child: Semantics(
              button: true,
              selected: isActive,
              label:
                  '${_shortDays[wd]!}, ${isTraining ? 'training day' : 'rest day'}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_activeCustomizingWeekday == wd) return;
                  KHaptics.select();
                  setState(() {
                    _activeCustomizingWeekday = wd;
                  });
                },
                child: AnimatedContainer(
                  duration: KMotion.of(context, KMotion.standard),
                  curve: KMotion.emphasizedCurve,
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
                  // Selected = ink, like every other selected state.
                  decoration: BoxDecoration(
                    color: isActive ? KColor.ink : Colors.transparent,
                    borderRadius: KRadius.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _shortDays[wd]!,
                        style: KText.label.copyWith(
                          fontSize: 12,
                          letterSpacing: 0,
                          fontWeight: isActive
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: isActive
                              ? KColor.onInk
                              : (isTraining
                                    ? KColor.textPrimary
                                    : KColor.textMuted),
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Training indicator: filled dot = training, dash = rest
                      Container(
                        width: isTraining ? 5 : 8,
                        height: isTraining ? 5 : 2,
                        decoration: BoxDecoration(
                          color: isTraining
                              ? (isActive ? KColor.onInk : KColor.violet)
                              : (isActive
                                    ? KColor.onInk.withValues(alpha: 0.5)
                                    : KColor.textDisabled),
                          borderRadius: KRadius.pill,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActiveDayCard(int weekday) {
    final isTraining = _selectedDays[weekday] == true;
    final exercises = _dayExercises[weekday] ?? [];

    return AnimatedSwitcher(
      duration: KMotion.of(context, KMotion.standard),
      switchInCurve: KMotion.emphasizedCurve,
      switchOutCurve: KMotion.accelerate,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(
          sizeFactor: anim,
          axisAlignment: -1.0,
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey('${weekday}_$isTraining'),
        padding: const EdgeInsets.all(KSpacing.xl),
        decoration: BoxDecoration(
          borderRadius: KRadius.xl,
          color: KColor.card,
          // Train colour as a corner accent only, fading out by mid-card.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.4, 0.4),
            colors: [
              Color.alphaBlend(
                (isTraining ? KColor.violet : KColor.cyan).withValues(
                  alpha: KColor.isDark ? 0.06 : 0.04,
                ),
                KColor.card,
              ),
              KColor.card,
            ],
          ),
          border: Border.all(color: _hairline),
          boxShadow: KShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isTraining
                            ? 'Training day'
                            : 'Rest day',
                        style: KText.h2.copyWith(fontSize: 17),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _defaultNames[weekday]!,
                        style: KText.caption.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Ink switch from the app theme.
                Switch(
                  value: isTraining,
                  onChanged: (val) {
                    KHaptics.select();
                    setState(() {
                      _selectedDays[weekday] = val;
                      if (val && _dayExercises[weekday]!.isEmpty) {
                        _dayExercises[weekday] = List.of(
                          exerciseLibraryByDay[_defaultNames[weekday] ?? ''] ??
                              const [],
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: KSpacing.md),
            Divider(color: KColor.divider, height: 1),
            const SizedBox(height: KSpacing.lg),
            if (isTraining) ...[
              Text('Split day name', style: _fieldLabel),
              const SizedBox(height: KSpacing.sm),
              TextField(
                controller: _nameControllers[weekday],
                style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                cursorColor: KColor.ink,
                decoration: _fieldDecoration(hint: 'e.g. Chest + Triceps'),
              ),
              const SizedBox(height: KSpacing.xl),
              Row(
                children: [
                  Expanded(child: Text('Exercises', style: _fieldLabel)),
                  const SizedBox(width: KSpacing.sm),
                  AnimatedSwitcher(
                    duration: KMotion.of(context, KMotion.quick),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: exercises.isEmpty
                        ? const SizedBox.shrink(key: ValueKey('count_none'))
                        : Text(
                            plural(exercises.length, 'exercise'),
                            key: ValueKey('count_${exercises.length}'),
                            style: KText.numSmall.copyWith(
                              color: KColor.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedSize(
                duration: KMotion.of(context, KMotion.standard),
                curve: KMotion.emphasizedCurve,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.standard),
                  child: exercises.isEmpty
                      ? _buildEmptyExercises()
                      : _buildExerciseList(weekday, exercises),
                ),
              ),
              const SizedBox(height: KSpacing.sm),
              _AddExerciseButton(
                onTap: () {
                  KHaptics.select();
                  _addExercise(weekday);
                },
              ),
            ] else ...[
              // Rest-day recovery placeholder
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: KColor.cyan.withValues(
                          alpha: KColor.isDark ? 0.1 : 0.07,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: KColor.cyan.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.spa_rounded,
                          color: KColor.cyan,
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: KSpacing.xl),
                    Text('Rest and recovery', style: KText.h2),
                    const SizedBox(height: KSpacing.sm),
                    Text(
                      'Rest is where the growth happens. Sleep well, eat well, drink water, maybe some light mobility.',
                      style: KText.body.copyWith(
                        color: KColor.textSecondary,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyExercises() {
    // The "Add exercise" action sits directly below, so the empty state
    // points to it instead of repeating it.
    return Container(
      key: const ValueKey('empty'),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: KRadius.md,
        color: KColor.fg.withValues(alpha: KColor.isDark ? 0.025 : 0.02),
        border: Border.all(color: _hairline),
      ),
      child: const KEmptyState(
        type: KEmptyStateType.workout,
        title: 'Nothing planned yet',
        message: 'Tap "Add exercise" below to build this day.',
      ),
    );
  }

  Widget _buildExerciseList(int weekday, List<Exercise> exercises) {
    return Column(
      key: const ValueKey('list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: KSpacing.sm),
          child: Row(
            children: [
              Icon(
                Icons.drag_indicator_rounded,
                color: KColor.textMuted,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Drag the handle to reorder exercises',
                  style: KText.caption.copyWith(
                    color: KColor.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderStart: (_) => KHaptics.select(),
          onReorder: (oldIdx, newIdx) {
            KHaptics.commit();
            _reorderExercise(weekday, oldIdx, newIdx);
          },
          proxyDecorator: _liftProxy,
          itemCount: exercises.length,
          itemBuilder: (_, index) {
            final ex = exercises[index];
            final subtitle = ex.notes?.trim().isNotEmpty == true
                ? '${ex.muscleGroup} • ${ex.repRangeLabel} • ${ex.notes!.trim()}'
                : '${ex.muscleGroup} • ${ex.repRangeLabel}';
            return Container(
              key: ValueKey('${weekday}_${ex.id}'),
              margin: const EdgeInsets.only(bottom: KSpacing.sm),
              padding: const EdgeInsets.fromLTRB(
                KSpacing.md,
                6,
                KSpacing.xs,
                6,
              ),
              decoration: BoxDecoration(
                color: KColor.isDark ? KColor.surface : KColor.bg,
                borderRadius: KRadius.md,
                border: Border.all(color: _hairline),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KColor.fg.withValues(
                        alpha: KColor.isDark ? 0.07 : 0.06,
                      ),
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: KText.numSmall.copyWith(
                        color: KColor.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: KSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex.name,
                          style: KText.bodyMedium.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: KText.caption.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove ${ex.name}',
                    onPressed: () {
                      KHaptics.commit();
                      _removeExercise(weekday, ex);
                    },
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: KColor.danger,
                      size: 18,
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Semantics(
                      label: 'Reorder ${ex.name}',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: KColor.textMuted,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Lifted look while dragging: slight scale and a soft drop shadow
  /// (deep on Carbon, warm and light on Paper) with a faint train halo.
  Widget _liftProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = KMotion.emphasizedCurve.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.03 * t,
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: KRadius.md,
                boxShadow: [
                  BoxShadow(
                    color: KColor.palette.shadow.withValues(
                      alpha: (KColor.isDark ? 0.6 : 0.16) * t,
                    ),
                    blurRadius: 24 * t,
                    offset: Offset(0, 12 * t),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Hairline for cards and rows: a light seam on Carbon, the warm border on
/// Paper. A getter so it follows the active theme.
Color get _hairline =>
    KColor.isDark ? KColor.fg.withValues(alpha: 0.07) : KColor.border;

/// Sentence-case field / section label.
TextStyle get _fieldLabel => KText.caption.copyWith(
      color: KColor.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

InputDecoration _fieldDecoration({String? label, String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: KText.body.copyWith(color: KColor.textSecondary),
    hintStyle: KText.body.copyWith(color: KColor.textMuted),
    filled: true,
    fillColor: KColor.isDark
        ? KColor.fg.withValues(alpha: 0.05)
        : KColor.cardHigh.withValues(alpha: 0.6),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: KSpacing.md,
    ),
    border: const OutlineInputBorder(
      borderRadius: KRadius.sm,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: KRadius.sm,
      borderSide: BorderSide(color: _hairline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: KRadius.sm,
      borderSide: BorderSide(color: KColor.ink, width: 1.5),
    ),
  );
}

// ─── Private setup widgets ───────────────────────────────────────────────────

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.md),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label. $description',
        excludeSemantics: true,
        child: Pressable(
          scale: 0.98,
          borderRadius: KRadius.lg,
          onTap: () {
            if (!selected) KHaptics.select();
            onTap();
          },
          child: AnimatedContainer(
            duration: KMotion.of(context, KMotion.standard),
            curve: KMotion.emphasizedCurve,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: KRadius.lg,
              // Selected = ink outline + a whisper of ink tint; no glow.
              color: selected
                  ? Color.alphaBlend(
                      KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.035),
                      KColor.card,
                    )
                  : KColor.card,
              border: Border.all(
                color: selected ? KColor.ink : _hairline,
                width: selected ? 1.5 : 1.0,
              ),
              boxShadow: KShadow.card,
            ),
            child: Row(
              children: [
                KIcon(
                  icon,
                  size: KIcons.lg,
                  color: selected ? KColor.textPrimary : KColor.textSecondary,
                ),
                const SizedBox(width: KSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: KText.h3.copyWith(fontSize: 16)),
                      const SizedBox(height: KSpacing.xs),
                      Text(description, style: KText.caption.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(width: KSpacing.sm),
                AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: anim,
                      curve: KMotion.overshoot,
                    ),
                    child: child,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('on'),
                          color: KColor.ink,
                          size: 22,
                        )
                      : Icon(
                          Icons.radio_button_unchecked_rounded,
                          key: ValueKey('off'),
                          color: KColor.textDisabled,
                          size: 22,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DaysTile extends StatelessWidget {
  final int days;
  final bool selected;
  final VoidCallback onTap;

  const _DaysTile({
    required this.days,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$days days per week',
      excludeSemantics: true,
      child: Pressable(
        borderRadius: KRadius.xl,
        onTap: () {
          if (!selected) KHaptics.select();
          onTap();
        },
        child: AnimatedContainer(
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.emphasizedCurve,
          decoration: BoxDecoration(
            borderRadius: KRadius.xl,
            color: selected
                ? Color.alphaBlend(
                    KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.035),
                    KColor.card,
                  )
                : KColor.card,
            border: Border.all(
              color: selected ? KColor.ink : _hairline,
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: KShadow.card,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: KMotion.of(context, KMotion.standard),
                  style: KText.numDisplay.copyWith(
                    fontSize: 42,
                    color: selected ? KColor.textPrimary : KColor.textSecondary,
                  ),
                  child: Text('$days'),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[
                      Icon(
                        Icons.check_rounded,
                        color: KColor.ink,
                        size: 14,
                      ),
                      const SizedBox(width: KSpacing.xs),
                    ],
                    Flexible(
                      child: Text(
                        'days a week',
                        style: KText.caption.copyWith(fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayBadge extends StatelessWidget {
  final String label;
  const _WeekdayBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KColor.violet.withValues(alpha: KColor.isDark ? 0.12 : 0.08),
        borderRadius: KRadius.pill,
        border: Border.all(
          color: KColor.violet.withValues(alpha: KColor.isDark ? 0.3 : 0.24),
        ),
      ),
      child: Text(
        label,
        style: KText.label.copyWith(
          color: KColor.textPrimary,
          fontSize: 12,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _AddExerciseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddExerciseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      borderRadius: KRadius.md,
      semanticLabel: 'Add exercise',
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          vertical: KSpacing.md,
          horizontal: KSpacing.md,
        ),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: KRadius.md,
          border: Border.all(
            color: KColor.fg.withValues(alpha: KColor.isDark ? 0.18 : 0.2),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              color: KColor.textPrimary,
              size: 18,
            ),
            const SizedBox(width: KSpacing.sm),
            Flexible(
              child: Text(
                'Add exercise',
                textAlign: TextAlign.center,
                style: KText.bodyMedium.copyWith(
                  color: KColor.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _ExercisePickerSheet ────────────────────────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  final List<Exercise> exercises;

  const _ExercisePickerSheet({required this.exercises});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.exercises
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query.toLowerCase()) ||
              e.muscleGroup.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const KDragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.lg,
              KSpacing.xs,
              KSpacing.lg,
              KSpacing.sm,
            ),
            child: TextField(
              autofocus: true,
              style: KText.body,
              onChanged: (v) => setState(() => _query = v),
              decoration: _fieldDecoration(hint: 'Search exercises…')
                  .copyWith(
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: KColor.textMuted,
                    ),
                  ),
            ),
          ),
          _CreateCustomTile(onCreated: (ex) => Navigator.of(context).pop(ex)),
          Divider(height: 1, color: KColor.divider),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final ex = filtered[i];
                final isCustom = ex.id.startsWith('custom_');
                return ListTile(
                  title: Text(
                    ex.name,
                    style: KText.bodyMedium.copyWith(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${ex.muscleGroup}${isCustom ? ' (custom)' : ''}',
                    style: KText.caption.copyWith(fontSize: 13),
                  ),
                  trailing: Icon(Icons.add_rounded, color: KColor.textSecondary),
                  onTap: () => Navigator.of(context).pop(ex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<Exercise?> showCreateCustomExerciseSheet(BuildContext context) {
  return showKSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateCustomExerciseSheet(),
  );
}

class _CreateCustomTile extends StatelessWidget {
  final ValueChanged<Exercise> onCreated;

  const _CreateCustomTile({required this.onCreated});

  @override
  Widget build(BuildContext context) => Pressable(
    scale: 0.98,
    borderRadius: KRadius.md,
    semanticLabel: 'Add custom exercise',
    onTap: () async {
      final ex = await showCreateCustomExerciseSheet(context);
      if (ex != null) {
        onCreated(ex);
      }
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.lg,
        vertical: KSpacing.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.05),
              borderRadius: KRadius.sm,
            ),
            child: Icon(
              Icons.add_rounded,
              color: KColor.textPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add custom exercise',
                  style: KText.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Save your own exercise and use it everywhere',
                  style: KText.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CreateCustomExerciseSheet extends StatefulWidget {
  const _CreateCustomExerciseSheet();

  @override
  State<_CreateCustomExerciseSheet> createState() =>
      _CreateCustomExerciseSheetState();
}

class _CreateCustomExerciseSheetState
    extends State<_CreateCustomExerciseSheet> {
  final _nameCtrl = TextEditingController();
  final _repMinCtrl = TextEditingController();
  final _repMaxCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _muscleGroup = 'Other';
  // Follows the name ("Pull-ups" reads as bodyweight) until the user picks.
  ExerciseType _type = ExerciseType.isolation;
  bool _typePicked = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_suggestType);
  }

  void _suggestType() {
    if (_typePicked) return;
    final suggested = ExerciseClassifier.classify(
      name: _nameCtrl.text,
      muscle: _muscleGroup,
    ).type;
    if (suggested != _type) setState(() => _type = suggested);
  }

  static const _muscleGroups = [
    'Chest',
    'Back',
    'Lats',
    'Shoulders',
    'Rear Delts',
    'Traps',
    'Biceps',
    'Forearms',
    'Triceps',
    'Quads',
    'Hamstrings',
    'Glutes',
    'Calves',
    'Core',
    'Other',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _repMinCtrl.dispose();
    _repMaxCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final repMin = int.tryParse(_repMinCtrl.text.trim());
    final repMax = int.tryParse(_repMaxCtrl.text.trim());
    if (name.isEmpty) {
      KHaptics.reject();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Give the exercise a name first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if ((repMin != null || repMax != null) &&
        (repMin == null || repMax == null || repMin <= 0 || repMax < repMin)) {
      KHaptics.reject();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check the rep range. Use both numbers, low to high.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final ex = Exercise(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      muscleGroup: _muscleGroup,
      type: _type,
      defaultRepMin: repMin,
      defaultRepMax: repMax,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      executionMode: _type == ExerciseType.bodyweight &&
              ExerciseClassifier.classify(name: name, muscle: _muscleGroup).isWeighted
          ? ExerciseExecutionMode.weightedBodyweight
          : ExerciseExecutionMode.weightReps,
    );
    await WorkoutService.instance.addCustomExercise(ex);
    if (mounted) {
      Navigator.of(context).pop(ex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const KSheetHeader(
              'Custom exercise',
              subtitle:
                  'Saved to your library. Shows up in setup, logging and history.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpacing.p,
                KSpacing.lg,
                KSpacing.p,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    style: KText.body,
                    cursorColor: KColor.ink,
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration(
                      label: 'Exercise name (e.g. Preacher curl)',
                    ),
                  ),
                  const SizedBox(height: KSpacing.xl),
                  Text('Default rep range (optional)', style: _fieldLabel),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _repMinCtrl,
                          keyboardType: TextInputType.number,
                          style: KText.numSmall.copyWith(fontSize: 14),
                          cursorColor: KColor.ink,
                          decoration: _fieldDecoration(label: 'Min reps'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _repMaxCtrl,
                          keyboardType: TextInputType.number,
                          style: KText.numSmall.copyWith(fontSize: 14),
                          cursorColor: KColor.ink,
                          decoration: _fieldDecoration(label: 'Max reps'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KSpacing.xl),
                  TextField(
                    controller: _notesCtrl,
                    style: KText.body,
                    cursorColor: KColor.ink,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    decoration: _fieldDecoration(
                      label: 'Notes or cue (optional)',
                      hint: 'Example: chest-supported, use 10 to 15 reps',
                    ),
                  ),
                  const SizedBox(height: KSpacing.xl),
                  Text('Muscle group', style: _fieldLabel),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: KSpacing.sm,
                    runSpacing: 0,
                    children: _muscleGroups.map((g) {
                      final selected = _muscleGroup == g;
                      return Semantics(
                        button: true,
                        selected: selected,
                        label: g,
                        excludeSemantics: true,
                        // 48dp hit area around a 40dp ink-selectable chip.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (!selected) KHaptics.select();
                            setState(() => _muscleGroup = g);
                            _suggestType();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: AnimatedContainer(
                              duration: KMotion.of(context, KMotion.quick),
                              constraints: const BoxConstraints(minHeight: 40),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? KColor.ink
                                    : KColor.fg.withValues(
                                        alpha: KColor.isDark ? 0.05 : 0.04,
                                      ),
                                borderRadius: KRadius.pill,
                                border: Border.all(
                                  color: selected ? KColor.ink : _hairline,
                                ),
                              ),
                              child: Text(
                                g,
                                style: KText.caption.copyWith(
                                  fontSize: 13,
                                  color: selected
                                      ? KColor.onInk
                                      : KColor.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: KSpacing.xl),
                  Text('Exercise type', style: _fieldLabel),
                  const SizedBox(height: 10),
                  for (final opt in _typeOptions)
                    Semantics(
                      button: true,
                      selected: _type == opt.type,
                      label: '${opt.label}. ${opt.hint}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_type != opt.type) KHaptics.select();
                          setState(() {
                            _type = opt.type;
                            _typePicked = true;
                          });
                        },
                        child: AnimatedContainer(
                          duration: KMotion.of(context, KMotion.quick),
                          margin: const EdgeInsets.only(bottom: KSpacing.sm),
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _type == opt.type
                                ? Color.alphaBlend(
                                    KColor.fg.withValues(
                                      alpha: KColor.isDark ? 0.06 : 0.035,
                                    ),
                                    KColor.card,
                                  )
                                : KColor.fg.withValues(
                                    alpha: KColor.isDark ? 0.03 : 0.02,
                                  ),
                            borderRadius: KRadius.sm,
                            border: Border.all(
                              color: _type == opt.type
                                  ? KColor.ink
                                  : _hairline,
                              width: _type == opt.type ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.label,
                                      style: KText.bodyMedium.copyWith(
                                        color: _type == opt.type
                                            ? KColor.textPrimary
                                            : KColor.textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      opt.hint,
                                      style: KText.caption.copyWith(
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_type == opt.type)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: KColor.ink,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: KSpacing.xxl),
                  SizedBox(
                    width: double.infinity,
                    child: KButton(
                      label: 'Save exercise',
                      loading: _saving,
                      onTap: _saving ? null : _save,
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

class _TypeOption {
  final ExerciseType type;
  final String hint;

  const _TypeOption({
    required this.type,
    required this.hint,
  });

  String get label => ExerciseClassifier.typeLabel(type);
}

const _typeOptions = [
  _TypeOption(
    type: ExerciseType.barbellCompound,
    hint: '+2.5 kg jumps when rep range is earned',
  ),
  _TypeOption(
    type: ExerciseType.dumbbell,
    hint: '+2 kg jumps (nearest DB increment)',
  ),
  _TypeOption(
    type: ExerciseType.cableMachine,
    hint: '+5 kg stack increments',
  ),
  _TypeOption(
    type: ExerciseType.isolation,
    hint: 'Beat reps twice before adding weight',
  ),
  _TypeOption(
    type: ExerciseType.bodyweight,
    hint: 'Rep-first progression, then add load',
  ),
];
