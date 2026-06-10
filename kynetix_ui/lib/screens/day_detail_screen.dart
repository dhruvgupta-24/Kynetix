import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/coach_insight.dart';
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../models/nutrition_result.dart';
import '../models/quick_add_item.dart';
import '../screens/onboarding_screen.dart';
import '../services/coach_service.dart';
import '../services/health_service.dart';
import '../services/nutrition_pipeline.dart';
import '../services/nutrition_target_engine.dart';
import '../services/meal_memory.dart';
import '../services/persistence_service.dart';
import '../services/quick_add_service.dart';
import '../services/workout_service.dart';
import 'add_meal_screen.dart';
import 'ai_coach_screen.dart';
import 'dashboard_screen.dart';
import 'home_screen.dart';

class DayDetailScreen extends StatefulWidget {
  final DateTime date;
  final HealthSyncResult? health; // passed from dashboard for engine
  final WeightContext?    weightContext; // compact weight summary for Kyno

  const DayDetailScreen({
    super.key,
    required this.date,
    this.health,
    this.weightContext,
  });

  static MealSection getSectionForTimeAndDate(DateTime now, DateTime targetDate) {
    final today = DateTime(now.year, now.month, now.day);
    final targetDateMidnight = DateTime(targetDate.year, targetDate.month, targetDate.day);
    
    if (now.hour < 5 && targetDateMidnight.isBefore(today)) {
      return MealSection.lateNight;
    }
    
    final h = now.hour;
    if (h < 11) return MealSection.breakfast;
    if (h < 16) return MealSection.lunch;
    if (h < 19) return MealSection.eveningSnack;
    if (h < 23) return MealSection.dinner;
    return MealSection.lateNight;
  }

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  late DateTime _currentDate;
  late final PageController _dayPageController;

  static final DateTime _todayMidnight = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }();
  static const int _todayPageIndex = 10000;

  int _dateToPageIndex(DateTime date) {
    final dateMidnight = DateTime(date.year, date.month, date.day);
    final diffDays = _todayMidnight.difference(dateMidnight).inDays;
    return _todayPageIndex - diffDays;
  }

  DateTime _pageIndexToDate(int index) {
    final diffDays = _todayPageIndex - index;
    return _todayMidnight.subtract(Duration(days: diffDays));
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _currentDate = widget.date;
    _dayPageController = PageController(initialPage: _dateToPageIndex(widget.date));
  }

  @override
  void dispose() {
    _dayPageController.dispose();
    super.dispose();
  }

  String get _dateLabel {
    final d = _currentDate;
    final wd = _weekdays[d.weekday - 1];
    return '$wd, ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  bool get _isToday {
    final now = DateTime.now();
    return _currentDate.year == now.year &&
        _currentDate.month == now.month &&
        _currentDate.day == now.day;
  }

  String get _dateKey {
    final d = _currentDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _navigateToPrevDay() {
    _dayPageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _navigateToNextDay() {
    if (_isToday) return;
    _dayPageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final log = logFor(_currentDate);
    final profile = currentUserProfile;

    final session = WorkoutService.instance.sessionFor(_currentDate);
    final splitDay = WorkoutService.instance.splitDayFor(_currentDate);
    final gymDay = log.gymDay;
    final bool isGymDay = gymDay != null
        ? (gymDay.didGym || (session?.isEmpty == false))
        : ((splitDay != null && !splitDay.isRestDay) || (session?.isEmpty == false));

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

    final target = profile != null
        ? NutritionTargetEngine().dayTarget(
            profile,
            isGymDay: isGymDay,
            health: widget.health,
            session: session,
            workoutTypeName: workoutTypeName,
            targetCaloriesOverride: log.gymDay?.targetCaloriesOverride,
            carryForwardAdjustment: log.carryForwardAdjustment,
            date: _currentDate,
          )
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      floatingActionButton: _AiCoachFab(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AiCoachScreen(
              dateKey:                _dateKey,
              isGymDay:               target?.isTrainingDay,
              workoutType:            target?.isTrainingDay == true ? target?.label : null,
              targetCaloriesOverride: log.gymDay?.targetCaloriesOverride,
              weightContext:          widget.weightContext,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
            tooltip: 'Previous day',
            onPressed: _navigateToPrevDay,
          ),
          if (!_isToday)
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
              tooltip: 'Next day',
              onPressed: _navigateToNextDay,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _dayPageController,
        itemCount: _todayPageIndex + 1,
        onPageChanged: (index) {
          kHapticSelect();
          setState(() {
            _currentDate = _pageIndexToDate(index);
          });
        },
        itemBuilder: (context, index) {
          final date = _pageIndexToDate(index);
          return _DayDetailContent(
            date: date,
            health: widget.health,
            weightContext: widget.weightContext,
          );
        },
      ),
    );
  }
}

// ─── DayDetailContent ────────────────────────────────────────────────────────

class _DayDetailContent extends StatefulWidget {
  final DateTime date;
  final HealthSyncResult? health;
  final WeightContext? weightContext;

  const _DayDetailContent({
    required this.date,
    this.health,
    this.weightContext,
  });

  @override
  State<_DayDetailContent> createState() => _DayDetailContentState();
}

class _DayDetailContentState extends State<_DayDetailContent> {
  late DayLog _log;

  @override
  void initState() {
    super.initState();
    _log = logFor(widget.date);
  }

  @override
  void didUpdateWidget(covariant _DayDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _log = logFor(widget.date);
    }
  }

  void _refresh() {
    setState(() {
      _log = logFor(widget.date);
    });
    PersistenceService.saveDay(widget.date).ignore();
  }

  Future<void> _openAddMeal(MealSection section) async {
    final option = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const KDragHandle(),
                const SizedBox(height: 8),
                Text(
                  'Add to ${section.displayName}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: KColor.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: KColor.green),
                  ),
                  title: const Text('AI Meal Logger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Describe your food in plain text (e.g. 2 eggs and toast).', style: TextStyle(color: KColor.textMuted, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'ai'),
                ),
                const Divider(color: KColor.divider, height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: KColor.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: KColor.blue),
                  ),
                  title: const Text('Quick Macro Estimator', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Directly input macros or estimate with manual override.', style: TextStyle(color: KColor.textMuted, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, 'quick'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (option == 'ai') {
      if (!mounted) return;
      final entry = await Navigator.of(context).push<dynamic>(
        PageRouteBuilder(
          pageBuilder: (_, animation, secondaryAnimation) =>
              AddMealScreen(section: section, date: widget.date),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              SlideTransition(
                position: Tween<Offset>(
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
    } else if (option == 'quick') {
      if (!mounted) return;
      final updated = await showModalBottomSheet<dynamic>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => HomeScreen(initialSection: section),
      );
      if (updated == true) _refresh();
    }
  }

  MealSection get _currentSection {
    return DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), widget.date);
  }

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
      userCorrected:   true,
      result: NutritionResult.createCustom(
        canonicalMeal: name,
        calories: calories,
        protein: protein,
        source: 'quick_add',
        userCorrected: true,
      ),
    );
    _log.add(sec, entry);
    MealMemory.instance.store(
      name,
      entry.result,
      finalSavedInput: name,
      canonicalMeal: name,
    ).ignore();
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
                            onPressed: () => Navigator.pop(ctx, -1.0),
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

  void _handleDeleteWithUndo(MealSection section, MealEntry entry) {
    _log.remove(section, entry);
    _refresh();

    final media = MediaQuery.of(context);
    final bottomPadding = media.padding.bottom;
    final screenWidth = media.size.width;
    final horizontalMargin = screenWidth > 600 ? (screenWidth - 400) / 2 : 16.0;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          persist: false,
          backgroundColor: const Color(0xFF222232),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: bottomPadding + 80.0,
            left: horizontalMargin,
            right: horizontalMargin,
          ),
          elevation: 6.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF52B788), width: 1.2),
          ),
          content: Row(
            children: [
              const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFF9CA3AF), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Deleted ${entry.finalSavedInput}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Undo',
            textColor: const Color(0xFF52B788),
            onPressed: () {
              _log.add(section, entry);
              _refresh();
              kHapticMedium();
            },
          ),
        ),
      );
  }

  DayTarget? get _dayTarget {
    final profile = currentUserProfile;
    if (profile == null) return null;

    final session = WorkoutService.instance.sessionFor(widget.date);
    final splitDay = WorkoutService.instance.splitDayFor(widget.date);
    final gymDay = _log.gymDay;

    final bool isGymDay = gymDay != null
        ? (gymDay.didGym || (session?.isEmpty == false))
        : ((splitDay != null && !splitDay.isRestDay) || (session?.isEmpty == false));

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
      carryForwardAdjustment: _log.carryForwardAdjustment,
      date:            widget.date,
    );
  }

  double get _targetFiber {
    final target = _dayTarget;
    if (target == null) return 30.0;
    return (14.0 * target.calories / 1000).clamp(20.0, 60.0);
  }

  @override
  Widget build(BuildContext context) {
    final target = _dayTarget;
    final dayStatus = target != null
        ? DayStatusEngine.classify(_log, target)
        : null;

    final profile = currentUserProfile;
    final todayWorkout = WorkoutService.instance.sessionFor(widget.date);
    final insights = target != null
        ? CoachService.instance.insightsForDay(
            _log,
            target,
            profile: profile,
            todayWorkout: todayWorkout,
          )
        : const <CoachInsight>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _DaySummaryBanner(
          log: _log,
          target: target,
          dayStatus: dayStatus,
          onEditTarget: _editDailyTarget,
        ),
        const SizedBox(height: 12),

        // ── Coach insights ───────────────────────────────────────
        if (insights.isNotEmpty) ...[
          _CoachInsightCard(insights: insights),
          const SizedBox(height: 12),
        ],

        DailyNutritionQualityCard(
          log: _log,
          targetCal: target?.calories ?? 2000.0,
          targetPro: target?.protein ?? 130.0,
        ),
        AdditionalMacrosCard(
          log: _log,
          targetCal: target?.calories ?? 2000.0,
          targetPro: target?.protein ?? 130.0,
          targetFiber: _targetFiber,
        ),
        const SizedBox(height: 12),

        // ── Quick Add ───────────────────────────────────────────
        _QuickAddCard(onAdd: _quickAddMeal),
        const SizedBox(height: 12),

        // ── Gym tracking ──────────────────────────────────────────
        _GymCard(log: _log, date: widget.date, onChanged: _refresh),
        const SizedBox(height: 4),
        ...MealSection.values.map(
          (section) => _MealSectionCard(
            section: section,
            log: _log,
            onAdd: () => _openAddMeal(section),
            onEdit: _openEditMeal,
            onDelete: (entry) => _handleDeleteWithUndo(section, entry),
          ),
        ),
      ],
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
              'Ask Kyno',
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
                      'Other Workouts',
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
    final calMid = entry.result.calories.mid;
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
        onTap: () => _showMealDetailSheet(context, entry, onTap),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                        fontSize: 13.5,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
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
                        if (calMid >= 50 && entry.result.mealQualityScore != null) ...[
                          const SizedBox(width: 6),
                          _MacroBadge(
                            'Quality: ${entry.result.mealQualityScore}',
                            entry.result.mealQualityScore! >= 80
                                ? const Color(0xFF52B788)
                                : (entry.result.mealQualityScore! >= 60
                                    ? const Color(0xFFFFB347)
                                    : const Color(0xFFEF4444)),
                          ),
                        ],
                        if (entry.edited || entry.result.macrosLockedByUser || entry.userCorrected || entry.result.userCorrected) ...[
                          const SizedBox(width: 6),
                          const _MacroBadge('Manually Edited', Color(0xFF60A5FA)),
                        ] else ...[
                          const SizedBox(width: 6),
                          _SourceBadge(entry.result.source),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '${entry.addedAt.hour.toString().padLeft(2, '0')}:'
                '${entry.addedAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF4B5563),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showMealDetailSheet(BuildContext context, MealEntry entry, VoidCallback? onEditClick) {
  final carbs = entry.result.carbohydrates;
  final fat = entry.result.fat;
  final fiber = entry.result.fiber;
  final sugar = entry.result.sugar;
  final satFat = entry.result.saturatedFat;
  final sodium = entry.result.sodium;
  final score = entry.result.mealQualityScore;
  final userWarnings = entry.result.userFacingWarnings;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF13131F),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E2E3E),
                  borderRadius: BorderRadius.circular(2.25),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.finalSavedInput,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Logged at ${entry.addedAt.hour.toString().padLeft(2, '0')}:${entry.addedAt.minute.toString().padLeft(2, '0')} · ${entry.section.displayName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      // ── Edited macros indicator ─────────────────────────────
                      if (entry.result.macrosLockedByUser || entry.result.userCorrected || entry.userCorrected) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF60A5FA).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF60A5FA).withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded, size: 9.5, color: Color(0xFF60A5FA)),
                              SizedBox(width: 4),
                              Text(
                                'Manually Edited',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF60A5FA),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 6),
                        _SourceBadge(entry.result.source),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF6B7280), size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1E1E2C),
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (score != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E2E3E), width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: (score >= 80
                            ? const Color(0xFF52B788)
                            : (score >= 60
                                ? const Color(0xFFFFB347)
                                : const Color(0xFFEF4444))).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: score >= 80
                              ? const Color(0xFF52B788)
                              : (score >= 60
                                  ? const Color(0xFFFFB347)
                                  : const Color(0xFFEF4444)),
                          width: 2.2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$score',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: score >= 80
                              ? const Color(0xFF52B788)
                              : (score >= 60
                                  ? const Color(0xFFFFB347)
                                  : const Color(0xFFEF4444)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Meal Quality Rating',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (entry.result.mealQualityExplanation != null &&
                              entry.result.mealQualityExplanation!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              entry.result.mealQualityExplanation!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF9CA3AF),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            const Text(
              'MACRONUTRIENTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7280),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Builder(builder: (c) {
              final locked = entry.result.macrosLockedByUser;
              final cards = <Widget>[
                _buildGridMacroCell('Calories', _macroLabel(entry.result.calories.min, entry.result.calories.max, 'kcal'), const Color(0xFFFF6B35), locked: locked),
                _buildGridMacroCell('Protein',  _macroLabel(entry.result.protein.min,  entry.result.protein.max,  'g'),    const Color(0xFF52B788), locked: locked),
                // When macros are locked always show carbs/fat/fiber, even if 0.
                if (locked || (carbs != null && (carbs.max > 0 || carbs.min > 0)))
                  _buildGridMacroCell('Carbs', _macroLabel(carbs?.min ?? 0, carbs?.max ?? 0, 'g'), const Color(0xFF60A5FA), locked: locked),
                if (locked || (fat != null && (fat.max > 0 || fat.min > 0)))
                  _buildGridMacroCell('Fat', _macroLabel(fat?.min ?? 0, fat?.max ?? 0, 'g'), const Color(0xFFFBBF24), locked: locked),
                if (locked || (fiber != null && (fiber.max > 0 || fiber.min > 0)))
                  _buildGridMacroCell('Fiber', _macroLabel(fiber?.min ?? 0, fiber?.max ?? 0, 'g'), const Color(0xFFA78BFA), locked: locked),
                if (sugar != null && (sugar.max > 0 || sugar.min > 0))
                  _buildGridMacroCell('Sugar', _macroLabel(sugar.min, sugar.max, 'g'), const Color(0xFFF472B6)),
                if (satFat != null && (satFat.max > 0 || satFat.min > 0))
                  _buildGridMacroCell('Sat. Fat', _macroLabel(satFat.min, satFat.max, 'g'), const Color(0xFFFB7185)),
                if (sodium != null && (sodium.max > 0 || sodium.min > 0))
                  _buildGridMacroCell('Sodium', _macroLabel(sodium.min, sodium.max, 'mg'), const Color(0xFF9CA3AF)),
              ];

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.8,
                ),
                itemCount: cards.length,
                itemBuilder: (context, index) => cards[index],
              );
            }),
            if (userWarnings.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'MEAL CALIBRATION REMINDERS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6B7280),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              ...userWarnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2.0),
                      child: Icon(Icons.info_outline_rounded,
                          color: Color(0xFFFFB347), size: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFFFB347),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
            if (onEditClick != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onEditClick();
                  },
                  icon: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                  label: const Text(
                    'Edit or Adjust Entry',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _buildGridMacroCell(String name, String value, Color color, {bool locked = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E2C),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: locked
            ? color.withValues(alpha: 0.35)
            : const Color(0xFF2E2E3E),
        width: locked ? 1.0 : 0.5,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 3),
              Icon(Icons.lock_rounded, size: 7, color: color.withValues(alpha: 0.6)),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
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



// ─── Quick Add item model ─────────────────────────────────────────────────────

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
  static final _builtIn = [
    const QuickAddItem(id: 'builtin_whey', name: '1 scoop whey',              calories: 115, protein: 22, emoji: '🥛', builtIn: true),
    const QuickAddItem(id: 'builtin_eggs', name: '4 egg whites + 400ml milk', calories: 328, protein: 27, emoji: '🥚', builtIn: true),
  ];

  @override
  void initState() {
    super.initState();
  }

  Future<void> _deleteCustomItem(QuickAddItem item) async {
    setState(() {}); // trigger rebuild
    await QuickAddService.instance.deleteItem(item);
  }

  Future<void> _openAddCustom() async {
    final result = await showModalBottomSheet<QuickAddItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCustomQuickSheet(),
    );
    if (result == null || !mounted) return;
    final exists = [..._builtIn, ...QuickAddService.instance.customItems].any(
      (i) => i.name.toLowerCase() == result.name.toLowerCase(),
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already in Quick Add'), backgroundColor: Color(0xFF1E1E2C), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await QuickAddService.instance.saveItem(result);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final allItems = [..._builtIn, ...QuickAddService.instance.customItems];
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
    Navigator.of(context).pop(QuickAddItem(
      id: QuickAddService.instance.generateUuid(),
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

class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge(this.source);

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _getAttribution(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 9.5)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (String, String, Color) _getAttribution(String src) {
    switch (src) {
      case 'memory_exact':
      case 'personal_exact':
      case 'personal_template':
        return ('From your saved foods', '📋', const Color(0xFF60A5FA));
      case 'cache':
      case 'memory_recurring_promoted':
        return ('Matched from your history', '🔄', const Color(0xFF2DD4BF));
      case 'user_override':
        return ('Your confirmed macros', '✏️', const Color(0xFF3B82F6));
      case 'local_hybrid':
      case 'local_fallback':
        return ('Local estimate', '📊', const Color(0xFF9CA3AF));
      default:
        return ('AI estimate', '🤖', const Color(0xFF9CA3AF));
    }
  }
}

