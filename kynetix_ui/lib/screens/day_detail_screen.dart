import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/coach_insight.dart';
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../models/nutrition_result.dart';
import '../screens/onboarding_screen.dart';
import '../services/coach_service.dart';
import '../services/health_service.dart';
import '../services/meal_suggestion_service.dart';
import '../services/nutrition_pipeline.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../services/workout_service.dart';
import 'add_meal_screen.dart';
import 'ai_coach_screen.dart';

class DayDetailScreen extends StatefulWidget {
  final DateTime date;
  final HealthSyncResult? health; // passed from dashboard for engine

  const DayDetailScreen({super.key, required this.date, this.health});

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  late DayLog _log;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _log = logFor(widget.date);
  }

  void _refresh() {
    setState(() {
      _log = logFor(widget.date);
    });
    PersistenceService.saveDayLogs().ignore();
  }

  Future<void> _openAddMeal(MealSection section) async {
    final entry = await Navigator.of(context).push<dynamic>(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) =>
            AddMealScreen(section: section, date: widget.date),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
    if (entry != null) _refresh();
  }

  /// Opens AddMealScreen with [prefilledText] for the time-appropriate section.
  Future<void> _openAddMealWithText(String prefilledText) async {
    final entry = await Navigator.of(context).push<dynamic>(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) => AddMealScreen(
          section: _currentSection,
          date: widget.date,
          initialText: prefilledText,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
    if (entry != null) _refresh();
  }

  /// The most time-appropriate meal section right now.
  MealSection get _currentSection {
    final h = DateTime.now().hour;
    if (h < 11) return MealSection.breakfast;
    if (h < 16) return MealSection.lunch;
    if (h < 19) return MealSection.eveningSnack;
    if (h < 23) return MealSection.dinner;
    return MealSection.lateNight;
  }

  /// Directly adds a quick-add meal entry without navigating to AddMealScreen.
  void _quickAddMeal({
    required String name,
    required double calories,
    required double protein,
    MealSection? section,
  }) {
    final sec = section ?? _currentSection;
    final entry = MealEntry(
      rawInput:        name,
      finalSavedInput: name,
      section:         sec,
      addedAt:         DateTime.now(),
      dayOfWeek:       widget.date.weekday,
      parsedFoods:     [name],
      result: NutritionResult(
        canonicalMeal: name,
        items: [
          NutritionItem(
            name:      name,
            quantity:  1,
            unit:      'serving',
            estimated: false,
            mode:      EstimationMode.packagedKnown,
            calories:  NutrientRange(min: calories, max: calories),
            protein:   NutrientRange(min: protein,  max: protein),
          ),
        ],
        calories:   NutrientRange(min: calories, max: calories),
        protein:    NutrientRange(min: protein,  max: protein),
        confidence: 1.0,
        warnings:   const [],
        source:     'quick_add',
        createdAt:  DateTime.now(),
      ),
    );
    _log.add(sec, entry);
    _refresh();
    kHapticMedium();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: KColor.green, size: 16),
            const SizedBox(width: 8),
            Text('Added $name', style: const TextStyle(fontSize: 13, color: Colors.white)),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: KColor.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: KRadius.md,
          side: const BorderSide(color: KColor.border, width: 0.5),
        ),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Future<void> _openEditMeal(MealEntry entry) async {
    final updated = await Navigator.of(context).push<dynamic>(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) => AddMealScreen(
          section: entry.section,
          date: widget.date,
          initialEntry: entry,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
    if (!mounted) return;
    if (updated is DeleteSentinel) {
      // User confirmed deletion inside the edit flow — remove from log and sync.
      _log.remove(entry.section, entry);
      _refresh();
    } else if (updated != null) {
      _refresh();
    }
  }

  Future<void> _editDailyTarget() async {
    final t = _dayTarget;
    if (t == null) return;
    final currentOverride = _log.gymDay?.targetCaloriesOverride;
    
    final ctrl = TextEditingController(
      text: currentOverride != null ? currentOverride.toInt().toString() : t.calories.toInt().toString(),
    );
    
    final result = await showModalBottomSheet<double?>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Override Daily Target', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Manually adjust your calorie target for this day.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Calories (kcal)',
                      labelStyle: const TextStyle(color: Color(0xFF4B5563)),
                      filled: true,
                      fillColor: const Color(0xFF0F0F14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (currentOverride != null) ...[
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx, -1.0), // -1 means clear
                            child: const Text('Clear Override', style: TextStyle(color: Color(0xFFF87171))),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final val = double.tryParse(ctrl.text);
                            Navigator.pop(ctx, val);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF52B788),
                            foregroundColor: const Color(0xFF0F0F14),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (result == null) return;

    if (result == -1.0) {
      if (_log.gymDay != null) {
        _log.gymDay = _log.gymDay!.withTargetCaloriesOverride(null);
      }
    } else {
      if (_log.gymDay == null) {
        _log.gymDay = GymDay(didGym: false, targetCaloriesOverride: result);
      } else {
        _log.gymDay = _log.gymDay!.withTargetCaloriesOverride(result);
      }
    }
    _refresh();
  }

  String get _dateLabel {
    final d = widget.date;
    final wd = _weekdays[d.weekday - 1];
    return '$wd, ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  bool get _isToday {
    final now = DateTime.now();
    return widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
  }

  /// Date key in YYYY-MM-DD format matching cloud_sync_service / day_logs table
  String get _dateKey {
    final d = widget.date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Engine-computed target for this day.
  /// Recomputes on every rebuild so gym toggle takes effect instantly.
  ///
  /// Priority order:
  ///   1. Actual logged WorkoutSession (highest truth — real volume/sets)
  ///   2. log.gymDay (user manually toggled / type-selected today)
  ///   3. WorkoutService split config for this date (auto-prefill)
  ///   4. Rest day fallback
  DayTarget? get _dayTarget {
    final profile = currentUserProfile;
    if (profile == null) return null;

    // Actual logged session — always highest priority.
    final session = WorkoutService.instance.sessionFor(widget.date);

    // Configured split for this weekday.
    final splitDay = WorkoutService.instance.splitDayFor(widget.date);
    final splitIsTraining = splitDay != null && !splitDay.isRestDay;

    // log.gymDay captures the user's current manual choice.
    final gymDay = _log.gymDay;

    // isGymDay: true if session logged, user toggled yes, OR split says training.
    // If the user explicitly toggled No (gymDay.didGym == false && gymDay != null),
    // that is a deliberate override — honour it.
    final bool isGymDay;
    if (gymDay != null) {
      // User has explicitly set a state — respect it.
      isGymDay = gymDay.didGym || (session?.isEmpty == false);
    } else {
      // No user choice yet — use split default.
      isGymDay = splitIsTraining || (session?.isEmpty == false);
    }

    // Best available workout type name:
    //   session name > user-chosen type > split day name
    final String? workoutTypeName;
    if (session != null && !session.isEmpty && session.splitDayName.isNotEmpty) {
      workoutTypeName = session.splitDayName;
    } else if (gymDay?.workoutType != null) {
      workoutTypeName = gymDay!.workoutType!.displayName;
    } else if (gymDay?.splitDayName != null) {
      workoutTypeName = gymDay!.splitDayName;
    } else if (splitDay != null && !splitDay.isRestDay) {
      workoutTypeName = splitDay.name;
    } else {
      workoutTypeName = null;
    }

    return NutritionTargetEngine().dayTarget(
      profile,
      isGymDay:        isGymDay,
      health:          widget.health,
      session:         session,
      workoutTypeName: workoutTypeName,
      targetCaloriesOverride: _log.gymDay?.targetCaloriesOverride,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = currentUserProfile;
    final target = _dayTarget;
    final todayWorkout = WorkoutService.instance.sessionFor(widget.date);
    final insights = target != null
        ? CoachService.instance.insightsForDay(
            _log,
            target,
            profile: profile,
            todayWorkout: todayWorkout,
          )
        : const <CoachInsight>[];
    final suggestions = (target != null && profile != null)
        ? MealSuggestionService.instance.suggestionsForDay(
            date: widget.date,
            log: _log,
            target: target,
            profile: profile,
          )
        : const <MealSuggestion>[];
    final dayStatus = target != null
        ? DayStatusEngine.classify(_log, target)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      floatingActionButton: _AiCoachFab(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AiCoachScreen(
              dateKey: _dateKey,
              isGymDay: target?.isTrainingDay,
              workoutType: target?.isTrainingDay == true ? target?.label : null,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isToday ? 'Today' : _dateLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (!_isToday)
              Text(
                _dateLabel,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _DaySummaryBanner(
            log: _log, 
            target: target, 
            dayStatus: dayStatus,
            onEditTarget: _editDailyTarget,
          ),
          const SizedBox(height: 12),

          // ── Coach insights ────────────────────────────────────
          if (insights.isNotEmpty) ...[
            _CoachInsightCard(insights: insights),
            const SizedBox(height: 12),
          ],

          // ── Quick Add ─────────────────────────────────────────
          _QuickAddCard(onAdd: _quickAddMeal),
          const SizedBox(height: 12),

          // ── Gym tracking ──────────────────────────────────────
          _GymCard(log: _log, date: widget.date, onChanged: _refresh),
          const SizedBox(height: 4),
          ...MealSection.values.map(
            (section) => _MealSectionCard(
              section: section,
              log: _log,
              onAdd: () => _openAddMeal(section),
              onEdit: _openEditMeal,
              onDelete: (entry) {
                _log.remove(section, entry);
                _refresh();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AI Coach FAB ─────────────────────────────────────────────────────────────

class _AiCoachFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AiCoachFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF52B788), Color(0xFF2D6A4F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF52B788).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Ask AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Gym tracking card ────────────────────────────────────────────────────────

class _GymCard extends StatelessWidget {
  final DayLog      log;
  final DateTime    date;
  final VoidCallback onChanged;
  const _GymCard({
    required this.log,
    required this.date,
    required this.onChanged,
  });

  // ── Effective gym state ──────────────────────────────────────────────────────

  /// Returns the current GymDay, prefilling from the configured split when the
  /// user has not yet explicitly set a gym state for this date.
  ///
  /// Auto-prefill logic:
  ///   If log.gymDay == null AND the configured split for this weekday is a
  ///   training day, synthesise a GymDay from the split:
  ///     - didGym = true
  ///     - workoutType = WorkoutType.fromSplitName(splitDay.name)
  ///     - splitDayName = splitDay.name
  ///     - splitOverridden = false  ← marks it as a prefill, not a manual choice
  ///
  /// This synthesised value is NOT persisted to log.gymDay — persistence only
  /// happens when the user interacts (toggleGym / selectType).
  GymDay _effectiveGymDay() {
    if (log.gymDay != null) return log.gymDay!;

    final splitDay = WorkoutService.instance.splitDayFor(date);
    if (splitDay == null || splitDay.isRestDay) {
      return const GymDay(didGym: false);
    }

    return GymDay(
      didGym:          true,
      workoutType:     WorkoutType.fromSplitName(splitDay.name),
      splitDayName:    splitDay.name,
      splitOverridden: false,
    );
  }

  void _toggleGym(bool didGym) {
    if (!didGym) {
      // User explicitly said No → clear, persist rest-day state.
      log.gymDay = const GymDay(didGym: false);
      onChanged();
      return;
    }

    // User said Yes.
    if (log.gymDay != null) {
      // Already had a stored state — just flip didGym on.
      log.gymDay = log.gymDay!.withGym(true);
    } else {
      // No stored state yet.  Synthesise from split and immediately persist
      // so the auto-selected workout type survives an app restart.
      final splitDay = WorkoutService.instance.splitDayFor(date);
      if (splitDay != null && !splitDay.isRestDay) {
        log.gymDay = GymDay(
          didGym:          true,
          workoutType:     WorkoutType.fromSplitName(splitDay.name),
          splitDayName:    splitDay.name,
          splitOverridden: false,
        );
      } else {
        log.gymDay = const GymDay(didGym: true);
      }
    }
    onChanged();
  }

  void _selectSplitDay(String name) {
    final existing = _effectiveGymDay();
    log.gymDay = existing.withUserOverride(
      splitName: name,
      type: WorkoutType.fromSplitName(name),
    );
    onChanged();
  }

  void _selectCoarseType(WorkoutType t) {
    final existing = _effectiveGymDay();
    log.gymDay = existing.withUserOverride(
      splitName: t.displayName, // e.g. "Cardio", "Other"
      type: t,
    );
    onChanged();
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF52B788).withValues(alpha: 0.18)
              : const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF52B788).withValues(alpha: 0.6)
                : const Color(0xFF2E2E3E),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? const Color(0xFF52B788)
                : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gym    = _effectiveGymDay();
    final didGym = gym.didGym;
    final isPrefilled = log.gymDay == null && didGym;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: didGym
              ? const Color(0xFF52B788).withValues(alpha: 0.40)
              : const Color(0xFF2E2E3E),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with toggle
          Row(
            children: [
              Text(didGym ? '🏋️' : '💤',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gym / Workout',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isPrefilled && gym.splitDayName != null)
                      Text(
                        '• ${gym.splitDayName} (from split)',
                        style: const TextStyle(
                          color: Color(0xFF52B788),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              // Yes / No toggle
              _GymToggleButton(
                label: 'Yes',
                active: didGym,
                activeColor: const Color(0xFF52B788),
                onTap: () => _toggleGym(true),
              ),
              const SizedBox(width: 8),
              _GymToggleButton(
                label: 'No',
                active: !didGym,
                activeColor: const Color(0xFF4B5563),
                onTap: () => _toggleGym(false),
              ),
            ],
          ),

          // Workout type chips (only shown when gym = yes)
          if (didGym) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2E2E3E), height: 1),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                // Get exact unique split names from user's current configuration.
                final exactSplitDays = WorkoutService.instance.trainingDays
                    .map((d) => d.name)
                    .toSet()
                    .toList();
                
                final hasSplitOptions = exactSplitDays.isNotEmpty;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasSplitOptions) ...[
                      const Text(
                        'Your Split',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // MAIN SPLIT CHIPS
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: exactSplitDays.map((name) {
                          // Match by name rather than generic enum to ensure fidelity
                          final selected = gym.splitDayName == name;
                          final inferredType = WorkoutType.fromSplitName(name);
                          return _buildChip(
                            label: '${inferredType.emoji} $name',
                            selected: selected,
                            onTap: () => _selectSplitDay(name),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // FALLBACK CHIPS
                    const Text(
                      'Manual Fallback',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [WorkoutType.cardio, WorkoutType.other].map((t) {
                        // Mark fallback as selected if type matches but name is NOT in the main split
                        // (e.g. they literally chose 'Cardio' or 'Other')
                        final selected = gym.workoutType == t && !exactSplitDays.contains(gym.splitDayName);
                        return _buildChip(
                          label: '${t.emoji} ${t.displayName}',
                          selected: selected,
                          onTap: () => _selectCoarseType(t),
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _GymToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _GymToggleButton({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? activeColor : const Color(0xFF2E2E3E),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? activeColor : const Color(0xFF4B5563),
          ),
        ),
      ),
    );
  }
}

// ─── Day summary banner ───────────────────────────────────────────────────────

class _DaySummaryBanner extends StatelessWidget {
  final DayLog log;
  final DayTarget? target;
  final DayOutcomeResult? dayStatus;
  final VoidCallback? onEditTarget;
  const _DaySummaryBanner({required this.log, this.target, this.dayStatus, this.onEditTarget});

  @override
  Widget build(BuildContext context) {
    final t = target;

    // ── Empty log — show target only ──────────────────────────────────────
    if (log.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E2E3E)),
        ),
        child: t == null
            ? const Row(
                children: [
                  Icon(
                    Icons.restaurant_menu_rounded,
                    color: Color(0xFF4B5563),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No meals logged yet — add a meal below.',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _DayTypeChip(isGymDay: t.isTrainingDay, label: t.label),
                      if (onEditTarget != null) ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: onEditTarget,
                          child: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _TargetPill(
                        icon: Icons.local_fire_department_rounded,
                        color: const Color(0xFFFF6B35),
                        label: 'Target',
                        value: '${t.calories.toInt()} kcal',
                      ),
                      const SizedBox(width: 10),
                      _TargetPill(
                        icon: Icons.fitness_center_rounded,
                        color: const Color(0xFF52B788),
                        label: 'Protein',
                        value: '${t.protein.toInt()} g',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No meals logged yet — start tracking',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 11),
                  ),
                ],
              ),
      );
    }

    // ── Has food — show progress vs target ────────────────────────────────
    final consumedCal = log.totalCaloriesMid;
    final consumedProt = log.totalProteinMid;
    final targetCal = t?.calories;
    final targetProt = t?.protein;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A2A), Color(0xFF1E1E2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF52B788).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t != null) ...[
            Row(
              children: [
                _DayTypeChip(isGymDay: t.isTrainingDay, label: t.label),
                if (onEditTarget != null) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: onEditTarget,
                    child: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF6B7280)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _MacroProgress(
                  label: 'Calories',
                  consumed: consumedCal,
                  target: targetCal,
                  unit: 'kcal',
                  color: const Color(0xFFFF6B35),
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: const Color(0xFF2E2E3E),
                margin: const EdgeInsets.symmetric(horizontal: 14),
              ),
              Expanded(
                child: _MacroProgress(
                  label: 'Protein',
                  consumed: consumedProt,
                  target: targetProt,
                  unit: 'g',
                  color: const Color(0xFF52B788),
                ),
              ),
            ],
          ),
          // Day status chip — only for meaningful outcomes
          if (dayStatus != null &&
              dayStatus!.outcome != DayOutcome.incomplete &&
              dayStatus!.outcome != DayOutcome.unlogged) ...[
            const SizedBox(height: 10),
            // Constrain width so Flexible inside the chip's Row can ellipsize
            // long notes on small screens instead of overflowing.
            SizedBox(
              width: double.infinity,
              child: _DayStatusChip(status: dayStatus!),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Day status chip ──────────────────────────────────────────────────────────

class _DayStatusChip extends StatelessWidget {
  final DayOutcomeResult status;
  const _DayStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status.color.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      // Use an intrinsic-width row but let the note shrink to available space.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: status.isPositive ? 1.0 : 0.97),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Text(status.emoji, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 5),
          // Label is fixed — always visible.
          Flexible(
            flex: 0,
            child: Text(
              status.label,
              style: TextStyle(
                color: status.color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          // Note is secondary — shrinks / ellipses on small screens.
          if (status.note.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '· ${status.note}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Day type chip ────────────────────────────────────────────────────────────

class _DayTypeChip extends StatelessWidget {
  final bool isGymDay;
  final String label;
  const _DayTypeChip({required this.isGymDay, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = isGymDay ? const Color(0xFF52B788) : const Color(0xFF6B7280);
    final emoji = isGymDay ? '⚡' : '😴';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─── Macro progress col ───────────────────────────────────────────────────────

class _MacroProgress extends StatelessWidget {
  final String label;
  final double consumed;
  final double? target;
  final String unit;
  final Color color;
  const _MacroProgress({
    required this.label,
    required this.consumed,
    required this.target,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasTarget = target != null && target! > 0;
    final ratio = hasTarget ? (consumed / target!).clamp(0.0, 1.0) : 0.0;
    final pct = (ratio * 100).toInt();
    final overGoal = hasTarget && consumed > target!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF6B7280),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        // Consumed / Target
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${consumed.toInt()}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: overGoal ? const Color(0xFFFFB347) : color,
                ),
              ),
              if (hasTarget)
                TextSpan(
                  text: ' / ${target!.toInt()} $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                )
              else
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
            ],
          ),
        ),
        if (hasTarget) ...[
          const SizedBox(height: 5),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 4,
                backgroundColor: const Color(0xFF2E2E3E),
                valueColor: AlwaysStoppedAnimation(
                  overGoal ? const Color(0xFFFFB347) : color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$pct%${overGoal ? ' — over goal' : ''}',
            style: TextStyle(
              fontSize: 9,
              color: overGoal
                  ? const Color(0xFFFFB347)
                  : const Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Target pill (empty state only) ──────────────────────────────────────────

class _TargetPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _TargetPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Meal section card ────────────────────────────────────────────────────────

class _MealSectionCard extends StatelessWidget {
  final MealSection section;
  final DayLog log;
  final VoidCallback onAdd;
  final ValueChanged<MealEntry>? onEdit;
  final ValueChanged<MealEntry> onDelete;

  const _MealSectionCard({
    required this.section,
    required this.log,
    required this.onAdd,
    this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final entries = log.entriesFor(section);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Text(section.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (entries.isNotEmpty) ...[
                  Text(
                    _macroLabel(
                      entries.fold<double>(
                        0,
                        (s, e) => s + e.result.calories.min,
                      ),
                      entries.fold<double>(
                        0,
                        (s, e) => s + e.result.calories.max,
                      ),
                      'kcal',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFF6B35),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF52B788).withValues(alpha: 0.40),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 14,
                          color: Color(0xFF52B788),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF52B788),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Empty slot ────────────────────────────────────
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Nothing logged — tap Add',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
              ),
            )
          else ...[
            const Divider(color: Color(0xFF2E2E3E), height: 1),
            ...entries.map(
              (entry) => _EntryTile(
                entry: entry,
                onTap: onEdit != null ? () => onEdit!(entry) : null,
                onDelete: () => onDelete(entry),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Entry tile ───────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  final MealEntry entry;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ObjectKey(entry),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(0),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFEF4444),
          size: 20,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.fastfood_rounded,
                  size: 14,
                  color: Color(0xFF4B5563),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.finalSavedInput,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _MacroBadge(
                          _macroLabel(
                            entry.result.calories.min,
                            entry.result.calories.max,
                            'kcal',
                          ),
                          const Color(0xFFFF6B35),
                        ),
                        const SizedBox(width: 6),
                        _MacroBadge(
                          _macroLabel(
                            entry.result.protein.min,
                            entry.result.protein.max,
                            'g',
                          ),
                          const Color(0xFF52B788),
                        ),
                        if (entry.edited) ...[
                          const SizedBox(width: 6),
                          const _MacroBadge('Edited', Color(0xFF60A5FA)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.addedAt.hour.toString().padLeft(2, '0')}:'
                    '${entry.addedAt.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  if (onTap != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _MacroBadge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _macroLabel(double min, double max, String unit) {
  final minI = min.toInt();
  final maxI = max.toInt();
  return minI == maxI ? '$minI $unit' : '$minI–$maxI $unit';
}

// ─── Coach insight card ───────────────────────────────────────────────────────

class _CoachInsightCard extends StatelessWidget {
  final List<CoachInsight> insights;
  const _CoachInsightCard({required this.insights});

  static (IconData, Color) _iconColor(CoachInsightType type) => switch (type) {
    CoachInsightType.protein => (
      Icons.fitness_center_rounded,
      const Color(0xFF52B788),
    ),
    CoachInsightType.overGoal => (
      Icons.warning_amber_rounded,
      const Color(0xFFFFB347),
    ),
    CoachInsightType.underEaten => (
      Icons.restaurant_menu_rounded,
      const Color(0xFF60A5FA),
    ),
    CoachInsightType.balance => (
      Icons.balance_rounded,
      const Color(0xFFA78BFA),
    ),
    CoachInsightType.info => (
      Icons.info_outline_rounded,
      const Color(0xFF9CA3AF),
    ),
  };

  @override
  Widget build(BuildContext context) {
    // Show only the top 2 most relevant insights.
    final top = insights.take(2).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E3550)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(color: Color(0xFF1E2438), height: 1),
            _CoachInsightRow(
              insight: top[i],
              iconColor: _iconColor(top[i].type),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachInsightRow extends StatelessWidget {
  final CoachInsight insight;
  final (IconData, Color) iconColor;
  const _CoachInsightRow({required this.insight, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = iconColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (insight.actionHint != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    insight.actionHint!,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Suggestion card ──────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  final List<MealSuggestion> suggestions;
  final void Function(String text) onSuggestionTap;
  const _SuggestionCard({
    required this.suggestions,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 14,
                  color: Color(0xFFFFB347),
                ),
                SizedBox(width: 6),
                Text(
                  'What to eat next',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF2A2A3A), height: 1),
          // Suggestions
          for (int i = 0; i < suggestions.length; i++) ...[
            if (i > 0)
              const Divider(
                color: Color(0xFF252535),
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
            _SuggestionRow(
              suggestion: suggestions[i],
              onTap: suggestions[i].prefilledText != null
                  ? () => onSuggestionTap(suggestions[i].prefilledText!)
                  : null,
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final MealSuggestion suggestion;
  final VoidCallback? onTap;
  const _SuggestionRow({required this.suggestion, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${suggestion.title}  •  ${suggestion.quantity}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    suggestion.reason,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 10),
              const Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: Color(0xFF52B788),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Quick Add item model ─────────────────────────────────────────────────────

class _QuickItem {
  final String name;
  final double calories;
  final double protein;
  final String emoji;
  final bool builtIn;

  const _QuickItem({
    required this.name,
    required this.calories,
    required this.protein,
    this.emoji = '⚡',
    this.builtIn = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'calories': calories,
        'protein': protein,
        'emoji': emoji,
      };

  factory _QuickItem.fromJson(Map<String, dynamic> j) => _QuickItem(
        name:     j['name'] as String,
        calories: (j['calories'] as num).toDouble(),
        protein:  (j['protein'] as num).toDouble(),
        emoji:    j['emoji'] as String? ?? '⚡',
      );
}

// ─── Quick Add card ───────────────────────────────────────────────────────────

class _QuickAddCard extends StatefulWidget {
  final void Function({
    required String name,
    required double calories,
    required double protein,
    MealSection? section,
  }) onAdd;

  const _QuickAddCard({required this.onAdd});

  @override
  State<_QuickAddCard> createState() => _QuickAddCardState();
}

class _QuickAddCardState extends State<_QuickAddCard> {
  static const _prefsKey = 'quick_add_custom_items';

  static const _builtIn = [
    _QuickItem(name: '1 scoop whey',              calories: 115, protein: 22, emoji: '🥛', builtIn: true),
    _QuickItem(name: '4 egg whites + 400ml milk', calories: 328, protein: 27, emoji: '🥚', builtIn: true),
  ];

  List<_QuickItem> _custom = [];

  @override
  void initState() {
    super.initState();
    _loadCustomItems();
  }

  Future<void> _loadCustomItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    if (mounted) {
      setState(() {
        _custom = raw.map((s) {
          try { return _QuickItem.fromJson(jsonDecode(s) as Map<String, dynamic>); }
          catch (_) { return null; }
        }).whereType<_QuickItem>().toList();
      });
    }
  }

  Future<void> _saveCustomItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _custom.map((i) => jsonEncode(i.toJson())).toList());
  }

  Future<void> _deleteCustomItem(_QuickItem item) async {
    setState(() => _custom.removeWhere((i) => i.name == item.name));
    await _saveCustomItems();
  }

  Future<void> _openAddCustom() async {
    final result = await showModalBottomSheet<_QuickItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCustomQuickSheet(),
    );
    if (result == null || !mounted) return;
    final exists = [..._builtIn, ..._custom].any(
      (i) => i.name.toLowerCase() == result.name.toLowerCase(),
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already in Quick Add'), backgroundColor: Color(0xFF1E1E2C), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _custom.add(result));
    await _saveCustomItems();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = [..._builtIn, ..._custom];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF52B788)),
                const SizedBox(width: 6),
                const Text('Quick Add', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: _openAddCustom,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 13, color: Color(0xFF52B788)),
                        SizedBox(width: 4),
                        Text('Add', style: TextStyle(color: Color(0xFF52B788), fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF2A2A3A), height: 1),

          // Items
          ...allItems.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QuickAddRow(
                  emoji: item.emoji,
                  title: item.name,
                  meta: '${item.calories.toInt()} kcal  ·  ${item.protein.toInt()}g protein',
                  isCustom: !item.builtIn,
                  onTap: () => widget.onAdd(name: item.name, calories: item.calories, protein: item.protein),
                  onDelete: !item.builtIn ? () => _deleteCustomItem(item) : null,
                ),
                if (i < allItems.length - 1)
                  const Divider(color: Color(0xFF252535), height: 1, indent: 16, endIndent: 16),
              ],
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Quick Add row ────────────────────────────────────────────────────────────

class _QuickAddRow extends StatelessWidget {
  final String       emoji;
  final String       title;
  final String       meta;
  final bool         isCustom;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _QuickAddRow({
    required this.emoji,
    required this.title,
    required this.meta,
    required this.isCustom,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: isCustom && onDelete != null
          ? () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E2C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Remove from Quick Add?',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  content: Text('Remove "$title" from your quick add list?',
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF9CA3AF))),
                    ),
                    TextButton(
                      onPressed: () { Navigator.of(context).pop(); onDelete!(); },
                      child: const Text('Remove',
                          style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              )
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            style: const TextStyle(color: Colors.white, fontSize: 13,
                                fontWeight: FontWeight.w600, height: 1.3)),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('custom',
                              style: TextStyle(color: Color(0xFF52B788), fontSize: 9,
                                  fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meta, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF52B788)),
          ],
        ),
      ),
    );
  }
}

// ─── Add custom quick-add sheet ───────────────────────────────────────────────

class _AddCustomQuickSheet extends StatefulWidget {
  const _AddCustomQuickSheet();

  @override
  State<_AddCustomQuickSheet> createState() => _AddCustomQuickSheetState();
}

class _AddCustomQuickSheetState extends State<_AddCustomQuickSheet> {
  final _ctrl    = TextEditingController();
  final _calCtrl = TextEditingController();
  final _proCtrl = TextEditingController();

  bool    _loading  = false;
  String? _error;
  double? _calories;
  double? _protein;
  bool    _showEdit = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _calCtrl.dispose();
    _proCtrl.dispose();
    super.dispose();
  }

  Future<void> _estimate() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _loading = true; _error = null; _calories = null; _protein = null; _showEdit = false; });
    try {
      final result = await NutritionPipeline.instance.estimateMeal(text);
      if (!mounted) return;
      final cal = result.primaryCaloriesEstimate;
      final pro = result.primaryProteinEstimate;
      _calCtrl.text = cal.toInt().toString();
      _proCtrl.text = pro.toInt().toString();
      setState(() { _calories = cal; _protein = pro; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not estimate. Try again.'; });
    }
  }

  void _accept() {
    final cal  = double.tryParse(_calCtrl.text.trim()) ?? _calories ?? 0;
    final pro  = double.tryParse(_proCtrl.text.trim()) ?? _protein  ?? 0;
    final name = _ctrl.text.trim();
    if (name.isEmpty || cal <= 0) return;
    Navigator.of(context).pop(_QuickItem(
      name: name, calories: cal, protein: pro, emoji: _pickEmoji(name),
    ));
  }

  String _pickEmoji(String name) {
    final n = name.toLowerCase();
    if (n.contains('oat'))                            return '🥣';
    if (n.contains('rice') || n.contains('roti'))     return '🍚';
    if (n.contains('egg'))                            return '🥚';
    if (n.contains('whey') || n.contains('protein'))  return '🥛';
    if (n.contains('chicken'))                        return '🍗';
    if (n.contains('banana'))                         return '🍌';
    if (n.contains('bread') || n.contains('sandwich'))return '🥪';
    if (n.contains('milk'))                           return '🥛';
    if (n.contains('paneer') || n.contains('cheese')) return '🧀';
    if (n.contains('dal') || n.contains('lentil'))    return '🍲';
    if (n.contains('salad'))                          return '🥗';
    if (n.contains('peanut') || n.contains('almond')) return '🥜';
    if (n.contains('fish') || n.contains('tuna'))     return '🐟';
    return '⚡';
  }

  @override
  Widget build(BuildContext context) {
    final kbHeight = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A28),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + kbHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF4B5563), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Add to Quick Add',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text("Type a food — we'll estimate nutrition for you.",
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          const SizedBox(height: 14),

          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _estimate(),
                  decoration: InputDecoration(
                    hintText: 'e.g. 2 rotis with dal',
                    hintStyle: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF1E1E2C),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2E2E3E))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2E2E3E))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF52B788), width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _loading ? null : _estimate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D6A4F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Estimate',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFFFB347), fontSize: 12)),
          ],

          // Result
          if (_calories != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFFA78BFA)),
                      const SizedBox(width: 5),
                      const Text('AI Estimate',
                          style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _showEdit = !_showEdit),
                        child: Text(_showEdit ? 'Hide edit' : 'Fix values',
                            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!_showEdit)
                    Row(
                      children: [
                        _EstimateChip(
                          icon: Icons.local_fire_department_rounded,
                          color: const Color(0xFFFF6B35),
                          value: '${_calories!.toInt()} kcal',
                        ),
                        const SizedBox(width: 10),
                        _EstimateChip(
                          icon: Icons.fitness_center_rounded,
                          color: const Color(0xFF52B788),
                          value: '${_protein!.toInt()}g protein',
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(child: _NumField(controller: _calCtrl, label: 'kcal', color: const Color(0xFFFF6B35))),
                        const SizedBox(width: 10),
                        Expanded(child: _NumField(controller: _proCtrl, label: 'g protein', color: const Color(0xFF52B788))),
                      ],
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _accept,
                      child: const Text('Accept & Save to Quick Add'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EstimateChip extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   value;
  const _EstimateChip({required this.icon, required this.color, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Color  color;
  const _NumField({required this.controller, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700),
    textAlign: TextAlign.center,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11),
      filled: true,
      fillColor: color.withValues(alpha: 0.08),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
    ),
  );
}

