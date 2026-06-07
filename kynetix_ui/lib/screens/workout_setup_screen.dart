import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';

// ─── Training Onboarding Questionnaire Enums ────────────────────────────────

enum TrainingExperience {
  beginner('Beginner', 'New to structured lifting or resuming after a break.', '👶'),
  intermediate('Intermediate', 'Consistent lifting for 1–3 years with structured progression.', '💪'),
  advanced('Advanced', '3+ years of serious training, optimizing for minor gains.', '🏋️');

  final String label;
  final String description;
  final String emoji;
  const TrainingExperience(this.label, this.description, this.emoji);
}

enum TrainingGoal {
  buildMuscle('Build Muscle', 'Focus on hypertrophy, moderate/high volume, and metabolic stress.', '🍗'),
  buildStrength('Build Strength', 'Focus on heavy compound lifts, lower reps, and neural drive.', '⚡'),
  loseFat('Lose Fat', 'Focus on calorie burn, muscle retention, and training density.', '🔥'),
  generalFitness('General Fitness', 'Focus on athletic capacity, core strength, and joint health.', '🏃');

  final String label;
  final String description;
  final String emoji;
  const TrainingGoal(this.label, this.description, this.emoji);
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
      _step = 4; // Skip directly to customization step when editing existing split
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
      days[0] = SplitDay(weekday: 1, name: 'Full Body A', exercises: fullBodyEx);
      days[2] = SplitDay(weekday: 3, name: 'Full Body B', exercises: fullBodyEx);
      days[4] = SplitDay(weekday: 5, name: 'Full Body C', exercises: fullBodyEx);
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
      days[0] = SplitDay(weekday: 1, name: 'Push', exercises: exerciseLibraryByDay['Push']!);
      days[1] = SplitDay(weekday: 2, name: 'Pull', exercises: exerciseLibraryByDay['Pull']!);
      days[2] = SplitDay(weekday: 3, name: 'Legs', exercises: exerciseLibraryByDay['Legs']!);
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
      days[0] = SplitDay(weekday: 1, name: 'Chest + Triceps', exercises: exerciseLibraryByDay['Chest + Triceps']!);
      days[1] = SplitDay(weekday: 2, name: 'Back + Biceps', exercises: exerciseLibraryByDay['Back + Biceps']!);
      days[2] = SplitDay(weekday: 3, name: 'Shoulders', exercises: exerciseLibraryByDay['Shoulders']!);
      days[3] = SplitDay(weekday: 4, name: 'Legs', exercises: exerciseLibraryByDay['Legs']!);
      days[4] = SplitDay(weekday: 5, name: 'Push', exercises: exerciseLibraryByDay['Push']!);
      days[5] = SplitDay(weekday: 6, name: 'Pull', exercises: exerciseLibraryByDay['Pull']!);
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

  Future<void> _finish() async {
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

    final newSplit = WorkoutSplit(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'My Split',
      days: days,
    );
    await WorkoutService.instance.saveSplit(newSplit);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
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
    final available = WorkoutService.instance.allExercises
        .where((e) => !current.any((c) => c.id == e.id))
        .toList();

    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExercisePickerSheet(exercises: available),
    );

    if (picked != null) {
      setState(() => _dayExercises[weekday] = [...current, picked]);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColor.bg,
      appBar: AppBar(
        backgroundColor: KColor.bg,
        surfaceTintColor: Colors.transparent,
        leading: _step > 0 && !widget.editMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: _goBack,
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          widget.editMode ? 'Edit Training Split' : 'Set Up Training',
          style: KText.h2.copyWith(color: Colors.white, fontSize: 16),
        ),
      ),
      body: _buildCurrentStep(),
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

  // ── Step 0: Experience ────────────────────────────────────────────────────

  Widget _buildExperienceStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Experience level', style: KText.h1.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            'We will use this to recommend progression jumps and volume guidelines.',
            style: KText.body.copyWith(color: KColor.textSecondary),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: TrainingExperience.values.map((exp) {
                final selected = _experience == exp;
                return GestureDetector(
                  onTap: () => setState(() => _experience = exp),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF132F23) : KColor.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? KColor.green : KColor.border,
                        width: selected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(exp.emoji, style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exp.label,
                                style: KText.bodyMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                exp.description,
                                style: KText.caption.copyWith(color: KColor.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check_circle_rounded, color: KColor.green, size: 20),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onTap: _goForward,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Days ──────────────────────────────────────────────────────────

  Widget _buildDaysStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How many days?', style: KText.h1.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            'How many days per week can you consistently commit to training?',
            style: KText.body.copyWith(color: KColor.textSecondary),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: Center(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [3, 4, 5, 6].map((days) {
                  final selected = _daysPerWeek == days;
                  return GestureDetector(
                    onTap: () => setState(() => _daysPerWeek = days),
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF132F23) : KColor.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? KColor.green : KColor.border,
                          width: selected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$days',
                            style: KText.display.copyWith(
                              color: selected ? KColor.green : Colors.white,
                              fontSize: 40,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Days / week',
                            style: KText.caption.copyWith(color: KColor.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onTap: _goForward,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Goal ──────────────────────────────────────────────────────────

  Widget _buildGoalStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Primary focus', style: KText.h1.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            'This drives default exercise selections and compound rep-range strategies.',
            style: KText.body.copyWith(color: KColor.textSecondary),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: TrainingGoal.values.map((goal) {
                final selected = _goal == goal;
                return GestureDetector(
                  onTap: () => setState(() => _goal = goal),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF132F23) : KColor.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? KColor.green : KColor.border,
                        width: selected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(goal.emoji, style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.label,
                                style: KText.bodyMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                goal.description,
                                style: KText.caption.copyWith(color: KColor.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check_circle_rounded, color: KColor.green, size: 20),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'See Recommendation',
              icon: Icons.arrow_forward_rounded,
              onTap: _goForward,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Recommendation ────────────────────────────────────────────────

  Widget _buildRecommendationStep() {
    final split = _generateRecommendedSplit();
    final splitDays = split.days.where((d) => !d.isRestDay).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recommended Split', style: KText.h1.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Based on your inputs, this program offers optimal volume and recovery overlap.',
            style: KText.body.copyWith(color: KColor.textSecondary),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: splitDays.length,
              itemBuilder: (context, i) {
                final d = splitDays[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: KColor.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KColor.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: KColor.bg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _shortDays[d.weekday]!,
                          style: KText.caption.copyWith(color: KColor.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${d.exercises.length} exercises planned',
                              style: KText.caption.copyWith(color: KColor.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: KButton(
                  label: 'Use Recommended',
                  onTap: () => _applyRecommendation(split),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KButton(
                  label: 'Manual Select',
                  outlined: true,
                  onTap: () {
                    setState(() {
                      _step = 4;
                    });
                  },
                ),
              ),
            ],
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
        // Pinned Segmented Weekday Tabs
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: _buildWeekdayTabs(),
        ),
        
        // Active tab configuration area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                _buildActiveDayCard(activeWd),
              ],
            ),
          ),
        ),

        // Sticky anchored button area
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: KButton(
                label: widget.editMode ? 'Save Split' : 'Start Training',
                onTap: _trainingDayCount == 0 ? null : () {
                  HapticFeedback.mediumImpact();
                  _finish();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Row(
        children: List.generate(7, (i) {
          final wd = i + 1;
          final isActive = _activeCustomizingWeekday == wd;
          final isTraining = _selectedDays[wd] == true;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _activeCustomizingWeekday = wd;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [KColor.green, Color(0xFF1B6A47)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: KColor.green.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _shortDays[wd]!,
                      style: TextStyle(
                        color: isActive 
                            ? Colors.white 
                            : (isTraining ? Colors.white70 : KColor.textMuted),
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Small training indicator dot
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isTraining 
                            ? (isActive ? Colors.white : KColor.green)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
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
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(
          sizeFactor: anim,
          axisAlignment: 0.0,
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey('${weekday}_$isTraining'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isTraining ? KColor.surface : const Color(0xFF141624),
          gradient: isTraining 
              ? null 
              : const LinearGradient(
                  colors: [Color(0xFF1A1F36), Color(0xFF0F101A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTraining 
                ? KColor.border 
                : KColor.blue.withValues(alpha: 0.2), 
            width: 0.5,
          ),
          boxShadow: isTraining 
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isTraining ? 'Training Day Split' : 'Scheduled Rest Day',
                        style: KText.h2.copyWith(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _defaultNames[weekday]!,
                        style: KText.caption.copyWith(color: KColor.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isTraining,
                  activeThumbColor: KColor.green,
                  activeTrackColor: KColor.green.withValues(alpha: 0.2),
                  inactiveThumbColor: KColor.textMuted,
                  inactiveTrackColor: KColor.border,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedDays[weekday] = val;
                      if (val && _dayExercises[weekday]!.isEmpty) {
                        _dayExercises[weekday] = List.of(
                          exerciseLibraryByDay[_defaultNames[weekday] ?? ''] ?? const [],
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: KColor.border, height: 1),
            const SizedBox(height: 16),
            if (isTraining) ...[
              Text(
                'SPLIT DAY NAME',
                style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameControllers[weekday],
                style: KText.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Chest + Triceps',
                  hintStyle: const TextStyle(color: KColor.textMuted),
                  fillColor: KColor.bg,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'EXERCISES PLAN',
                      style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (exercises.isNotEmpty)
                    Flexible(
                      child: Text(
                        '${exercises.length} Exercises',
                        style: KText.caption.copyWith(color: KColor.green, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (exercises.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.fitness_center_rounded, color: KColor.textMuted, size: 32),
                      const SizedBox(height: 12),
                      Text(
                        'No Exercises Planned',
                        style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap "Add exercise" below to build this day split.',
                        style: KText.caption.copyWith(color: KColor.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator_rounded, color: KColor.textMuted, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Drag handle to change exercise ordering',
                          style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (oldIdx, newIdx) => _reorderExercise(weekday, oldIdx, newIdx),
                  itemCount: exercises.length,
                  itemBuilder: (_, index) {
                    final ex = exercises[index];
                    final subtitle = ex.notes?.trim().isNotEmpty == true
                        ? '${ex.muscleGroup} • ${ex.repRangeLabel} • ${ex.notes!.trim()}'
                        : '${ex.muscleGroup} • ${ex.repRangeLabel}';
                    return Container(
                      key: ValueKey('${weekday}_${ex.id}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: KColor.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: KColor.border, width: 0.5),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                        leading: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: KColor.surface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: KText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        title: Text(
                          ex.name,
                          style: KText.bodyMedium.copyWith(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          subtitle,
                          style: KText.caption.copyWith(color: KColor.textSecondary, fontSize: 10.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _removeExercise(weekday, ex);
                              },
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: KColor.danger,
                                size: 18,
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: KColor.textMuted,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _addExercise(weekday);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: KColor.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: KColor.green.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        color: KColor.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Add Exercise',
                          overflow: TextOverflow.ellipsis,
                          style: KText.bodyMedium.copyWith(
                            color: KColor.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Rest Day Recovery Placeholder Card (No Nesting, beautifully customized)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: KColor.blue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: KColor.blue.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.spa_rounded,
                          color: KColor.blue,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Rest & Recovery',
                      style: KText.h2.copyWith(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scheduled Rest Day — muscles grow when you rest, not when you lift. Use this day to focus on sleep, quality nutrition, hydration, and light mobility work to return stronger.',
                      style: KText.body.copyWith(
                        color: KColor.textSecondary,
                        height: 1.5,
                        fontSize: 13,
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
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: KColor.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: KColor.textMuted,
                ),
                fillColor: KColor.surface,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          _CreateCustomTile(onCreated: (ex) => Navigator.of(context).pop(ex)),
          const Divider(height: 1, color: KColor.border),
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
                    style: KText.bodyMedium.copyWith(color: Colors.white, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '${ex.muscleGroup}${isCustom ? ' (custom)' : ''}',
                    style: KText.caption.copyWith(color: KColor.textMuted),
                  ),
                  trailing: const Icon(
                    Icons.add_rounded,
                    color: KColor.green,
                  ),
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
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A28),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CreateCustomExerciseSheet(),
  );
}

class _CreateCustomTile extends StatelessWidget {
  final ValueChanged<Exercise> onCreated;

  const _CreateCustomTile({required this.onCreated});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final ex = await showCreateCustomExerciseSheet(context);
      if (ex != null) {
        onCreated(ex);
      }
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: KColor.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: KColor.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '+ Add Custom Exercise',
                  style: KText.bodyMedium.copyWith(
                    color: KColor.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Save your own exercise and use it everywhere',
                  style: KText.caption.copyWith(color: KColor.textMuted),
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
  ExerciseType _type = ExerciseType.barbellCompound;
  bool _saving = false;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a name for the exercise.'),
          backgroundColor: Color(0xFF1E1E2C),
        ),
      );
      return;
    }
    if ((repMin != null || repMax != null) &&
        (repMin == null || repMax == null || repMin <= 0 || repMax < repMin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid rep range.'),
          backgroundColor: Color(0xFF1E1E2C),
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: KColor.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Custom Exercise',
              style: KText.h2.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'Saved permanently and available in split setup, logging, and history.',
              style: KText.caption.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Exercise name (e.g. Preacher Curl)',
                labelStyle: const TextStyle(color: KColor.textSecondary),
                filled: true,
                fillColor: KColor.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: KColor.green,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'DEFAULT REP RANGE (OPTIONAL)',
              style: KText.label.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _repMinCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Min reps',
                      labelStyle: const TextStyle(color: KColor.textSecondary),
                      filled: true,
                      fillColor: KColor.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _repMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Max reps',
                      labelStyle: const TextStyle(color: KColor.textSecondary),
                      filled: true,
                      fillColor: KColor.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes or cue (optional)',
                hintText: 'Example: chest-supported, use 10 to 15 reps',
                labelStyle: const TextStyle(color: KColor.textSecondary),
                hintStyle: const TextStyle(color: KColor.textMuted),
                filled: true,
                fillColor: KColor.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'MUSCLE GROUP',
              style: KText.label.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _muscleGroups.map((g) {
                final selected = _muscleGroup == g;
                return GestureDetector(
                  onTap: () => setState(() => _muscleGroup = g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? KColor.green.withValues(alpha: 0.15)
                          : KColor.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? KColor.green : KColor.border,
                      ),
                    ),
                    child: Text(
                      g,
                      style: TextStyle(
                        color: selected ? KColor.green : KColor.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              'EXERCISE TYPE',
              style: KText.label.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 10),
            for (final opt in _typeOptions)
              GestureDetector(
                onTap: () => setState(() => _type = opt.type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _type == opt.type
                        ? KColor.green.withValues(alpha: 0.15)
                        : KColor.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _type == opt.type ? KColor.green : KColor.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(opt.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.label,
                              style: KText.bodyMedium.copyWith(
                                color: _type == opt.type ? Colors.white : KColor.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              opt.hint,
                              style: KText.caption.copyWith(color: KColor.textMuted),
                            ),
                          ],
                        ),
                      ),
                      if (_type == opt.type)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: KColor.green,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: KButton(
                label: 'Save Exercise',
                onTap: _saving ? null : _save,
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
  final String label;
  final String emoji;
  final String hint;

  const _TypeOption({
    required this.type,
    required this.label,
    required this.emoji,
    required this.hint,
  });
}

const _typeOptions = [
  _TypeOption(
    type: ExerciseType.barbellCompound,
    label: 'Barbell Compound',
    emoji: '🏋️',
    hint: '+2.5 kg jumps when rep range is earned',
  ),
  _TypeOption(
    type: ExerciseType.dumbbell,
    label: 'Dumbbell',
    emoji: '💪',
    hint: '+2 kg jumps (nearest DB increment)',
  ),
  _TypeOption(
    type: ExerciseType.cableMachine,
    label: 'Cable / Machine',
    emoji: '⚙️',
    hint: '+5 kg stack increments',
  ),
  _TypeOption(
    type: ExerciseType.isolation,
    label: 'Isolation',
    emoji: '🎯',
    hint: 'Beat reps twice before adding weight',
  ),
  _TypeOption(
    type: ExerciseType.bodyweight,
    label: 'Bodyweight',
    emoji: '🧘',
    hint: 'Rep-first progression, then add load',
  ),
];
