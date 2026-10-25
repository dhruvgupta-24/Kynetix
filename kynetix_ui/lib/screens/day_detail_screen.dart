import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../ui/k_segmented.dart';
import 'barcode_scanner_screen.dart';
import '../models/coach_insight.dart';
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../models/nutrition_result.dart';
import '../models/quick_add_item.dart';
import '../screens/onboarding_screen.dart';
import '../services/coach_service.dart';
import '../services/health_service.dart';
import '../services/meal_tombstones.dart';
import '../services/meal_memory.dart';
import '../services/nutrition_pipeline.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../services/meal_repeat_service.dart';
import '../services/quick_add_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/food_link_service.dart';
import '../services/workout_service.dart';
import 'add_meal_screen.dart';
import 'ai_coach_screen.dart';
import 'dashboard_screen.dart';
import '../ui/k_text_morph.dart';

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
  late final int _initialPageIndex;

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
    _initialPageIndex = _dateToPageIndex(widget.date);
    _dayPageController = PageController(initialPage: _initialPageIndex);
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

  /// Secondary header line: how far this day is from today.
  String get _relativeLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(_currentDate.year, _currentDate.month, _currentDate.day);
    final diff = d.difference(today).inDays;
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return diff < 0 ? '${-diff} days ago' : 'In $diff days';
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

  /// Animated page step that collapses to a jump under reduced motion
  /// (a zero-duration animateTo is not allowed by the scroll machinery).
  void _stepPage(int delta) {
    if (!_dayPageController.hasClients) return;
    final current = _dayPageController.page?.round() ?? _initialPageIndex;
    final target = current + delta;
    final d = KMotion.of(context, KMotion.standard);
    if (d == Duration.zero) {
      _dayPageController.jumpToPage(target);
    } else {
      _dayPageController.animateToPage(
        target,
        duration: d,
        curve: KMotion.emphasizedCurve,
      );
    }
  }

  void _navigateToPrevDay() {
    _stepPage(-1);
  }

  void _navigateToNextDay() {
    if (_isToday) return;
    _stepPage(1);
  }

  @override
  Widget build(BuildContext context) {
    final profile = currentUserProfile;

    final target = profile != null
        ? NutritionTargetEngine().effectiveTargetForDate(
            _currentDate,
            profile: profile,
            health: widget.health,
          )
        : null;

    return KPage(
      tone: KTone.fuel,
      intensity: 0.85,
      floatingActionButton: KAskKyno(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AiCoachScreen(
              dateKey:                _dateKey,
              isGymDay:               target?.isTrainingDay,
              workoutType:            target?.isTrainingDay == true ? target?.label : null,
              targetCaloriesOverride: target?.calories,
              weightContext:          widget.weightContext,
            ),
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(KIcons.back, color: KColor.textPrimary),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: AnimatedSwitcher(
          duration: KMotion.of(context, KMotion.quick),
          switchInCurve: KMotion.decelerate,
          switchOutCurve: KMotion.accelerate,
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [...previous, ?current],
          ),
          // Cross-fades only between today and a past day (one line or two);
          // from one past day to the next the letters morph in place.
          child: Semantics(
            key: ValueKey(_isToday),
            header: true,
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                KTextMorph(
                  _isToday ? 'Today' : _dateLabel,
                  order: _dateToPageIndex(_currentDate),
                  style: KText.h2.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                if (!_isToday)
                  KTextMorph(
                    _relativeLabel,
                    order: _dateToPageIndex(_currentDate),
                    style: KText.caption.copyWith(
                      color: KColor.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          // A balanced pair: "next" stays in place on today, just disabled,
          // so the control never looks half-drawn.
          IconButton(
            icon: const Icon(KIcons.prev),
            color: KColor.textPrimary,
            tooltip: 'Previous day',
            onPressed: _navigateToPrevDay,
          ),
          IconButton(
            icon: const Icon(KIcons.next),
            color: KColor.textPrimary,
            disabledColor: KColor.textDisabled,
            tooltip: _isToday ? 'Next day (you\'re on today)' : 'Next day',
            onPressed: _isToday ? null : _navigateToNextDay,
          ),
          const SizedBox(width: KSpacing.xs),
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
            // One orchestrated entrance — only for the day the screen opened on.
            entrance: index == _initialPageIndex,
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
  final bool entrance;

  const _DayDetailContent({
    required this.date,
    this.health,
    this.weightContext,
    this.entrance = false,
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

  /// Saves a meal add/remove explicitly. The target refresh below only saves
  /// as a side effect, and skips it on days with a manual calorie target —
  /// which used to let deleted meals come back after a restart. It also
  /// schedules the cloud upload, so the removal (or Undo) reaches the cloud
  /// and hydration cannot bring a deleted meal back.
  void _persistLogChange() {
    PersistenceService.saveDayLogsAndSync(widget.date).ignore();
    PersistenceService.notifyLogsChanged();
  }

  void _refresh() {
    NutritionTargetEngine.instance.refreshTargetForDate(widget.date, force: true).ignore();
    // Undo snackbars and sheets can call back after this page was swiped
    // away (PageView disposes off-screen days): the data work above still
    // runs, only the rebuild is skipped.
    if (!mounted) return;
    setState(() {
      _log = logFor(widget.date);
    });
  }

  /// The same meal on an earlier day: yesterday first, else the same weekday
  /// last week (mess menus and office lunches repeat by weekday).
  ({String when, List<MealEntry> entries})? _repeatSource(MealSection section) {
    for (final (back, label) in [(1, 'yesterday'), (7, 'last ${_weekdayName(widget.date)}')]) {
      final d = widget.date.subtract(Duration(days: back));
      final entries = dayLogStore[dateKey(d)]?.entriesFor(section) ?? const <MealEntry>[];
      if (entries.isNotEmpty) return (when: label, entries: entries);
    }
    return null;
  }

  static String _weekdayName(DateTime d) =>
      const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];

  Future<void> _copyEarlier(MealSection section, String when, List<MealEntry> entries) async {
    final added = await MealRepeatService.relog(widget.date, entries, section: section);
    if (!mounted) return;
    _refresh();
    KHaptics.success();
    final kcal = added.fold<double>(0, (s, e) => s + e.calMid).round();
    showKToast(
      context,
      'Copied ${section.displayName.toLowerCase()} from $when, ${thousands(kcal)} kcal.',
      kind: KToastKind.success,
      actionLabel: 'Undo',
      onAction: () async {
        await MealRepeatService.undo(widget.date, added);
        _refresh();
      },
    );
  }

  Future<void> _openAddMeal(MealSection section) async {
    final repeat = _repeatSource(section);
    final option = await showKSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: KSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KSheetHeader('Add to ${section.displayName}'),
                const SizedBox(height: KSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KOptionRow(
                        icon: KIcons.kyno,
                        leading: const KynoMark(size: 24, outlined: true),
                        title: 'Describe it to Kyno',
                        subtitle: 'Type it like you\'d say it, e.g. 2 roti and dal.',
                        onTap: () => Navigator.pop(ctx, 'ai'),
                      ),
                      const KHairline(indent: 40),
                      KOptionRow(
                        icon: KIcons.scan,
                        title: 'Scan a barcode',
                        subtitle: 'Packaged food. Logs the exact pack, like 40 g.',
                        onTap: () => Navigator.pop(ctx, 'scan'),
                      ),
                      if (repeat != null) ...[
                        const KHairline(indent: 40),
                        KOptionRow(
                          icon: Icons.replay_rounded,
                          title: 'Same as ${repeat.when}',
                          subtitle: '${repeat.entries.map((e) => e.finalSavedInput.isNotEmpty ? e.finalSavedInput : e.rawInput).take(3).join(', ')}'
                              '${repeat.entries.length > 3 ? ' and more' : ''}, '
                              '${thousands(repeat.entries.fold<double>(0, (s, e) => s + e.calMid).round())} kcal',
                          onTap: () => Navigator.pop(ctx, 'repeat'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (option == 'repeat' && repeat != null) {
      await _copyEarlier(section, repeat.when, repeat.entries);
      return;
    }
    if (option == 'ai') {
      if (!mounted) return;
      final entry = await Navigator.of(context).push<dynamic>(
        kRiseRoute<dynamic>(
          builder: (_) => AddMealScreen(section: section, date: widget.date),
        ),
      );
      if (entry != null) {
        _refresh();
        if (entry is MealEntry) _showLoggedFeedback(section);
      }
    } else if (option == 'scan') {
      if (!mounted) return;
      final outcome = await openBarcodeFlow(
        context,
        date: widget.date,
        section: section,
      );
      if (outcome?.entry != null) _refresh();
    }
  }

  /// Success acknowledgement after a meal comes back from the composer: the
  /// summary ring and kcal count tick up to the new total (KRing / _CountUp
  /// animate from their current value), one success haptic lands on the same
  /// frame, and a short banner repeats the button's verb.
  void _showLoggedFeedback(MealSection section) {
    if (!mounted) return;
    KHaptics.success();
    final accessible = MediaQuery.accessibleNavigationOf(context);
    showKToast(
      context,
      'Meal logged to ${section.displayName}.',
      kind: KToastKind.success,
      duration: Duration(seconds: accessible ? 8 : 2),
    );
  }

  MealSection get _currentSection {
    return DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), widget.date);
  }

  Future<void> _quickAddMeal({
    required String name,
    required double calories,
    required double protein,
    MealSection? section,
  }) async {
    final sw = Stopwatch()..start();
    final sec = section ?? _currentSection;

    // Optimistic: continue as soon as the entry is in the in-memory log; the
    // coalesced persistence inside addMealToDay finishes in the background.
    final inserted = Completer<void>();
    QuickAddService.instance
        .addMealToDay(
          date: widget.date,
          name: name,
          calories: calories,
          protein: protein,
          section: sec,
          onInserted: (_) {
            if (!inserted.isCompleted) inserted.complete();
          },
        )
        .then<void>((_) {
      if (!inserted.isCompleted) inserted.complete();
    }, onError: (Object e, StackTrace st) {
      if (!inserted.isCompleted) inserted.completeError(e, st);
    });
    await inserted.future;

    final tRebuild = sw.elapsedMicroseconds / 1000.0;
    if (kDebugMode) debugPrint('[QuickAddTap] ⏱️ UI rebuild started: T+${tRebuild.toStringAsFixed(2)} ms');

    _refresh();

    final tVisible = sw.elapsedMicroseconds / 1000.0;
    if (kDebugMode) debugPrint('[QuickAddTap] ⏱️ Meal visible in list: T+${tVisible.toStringAsFixed(2)} ms');

    if (!mounted) return;
    kHapticMedium();
    showKToast(
      context,
      '$name logged.',
      kind: KToastKind.success,
      duration: const Duration(seconds: 2),
    );

    final tSnackbar = sw.elapsedMicroseconds / 1000.0;
    if (kDebugMode) debugPrint('[QuickAddTap] ⏱️ Snackbar shown: T+${tSnackbar.toStringAsFixed(2)} ms');
  }

  Future<void> _openEditMeal(MealEntry entry) async {
    final updated = await Navigator.of(context).push<dynamic>(
      kRiseRoute<dynamic>(
        builder: (_) => AddMealScreen(
          section: entry.section,
          date: widget.date,
          initialEntry: entry,
        ),
      ),
    );
    if (!mounted) return;
    if (updated is DeleteSentinel) {
      _log.remove(entry.section, entry);
      MealTombstones.instance.recordRemoval(dateKey(widget.date), entry);
      _persistLogChange();
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

    final result = await showKSheet<double?>(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(bottom: KSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const KSheetHeader(
                      'Change this day\'s target',
                      subtitle: 'Just for this day. Your usual target stays put.',
                    ),
                    const SizedBox(height: KSpacing.lg),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: ctrl,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            cursorColor: KColor.ink,
                            style: KText.numMedium.copyWith(fontSize: 24, color: KColor.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Calories (kcal)',
                              labelStyle: KText.caption.copyWith(color: KColor.textSecondary),
                              prefixIcon: Icon(Icons.local_fire_department_rounded, color: KColor.ember),
                              filled: true,
                              fillColor: KColor.card,
                              border: const OutlineInputBorder(
                                borderRadius: KRadius.md,
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: KRadius.md,
                                borderSide: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: KRadius.md,
                                borderSide: BorderSide(color: KColor.ink, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: KSpacing.xxl),
                          Row(
                            children: [
                              if (currentOverride != null) ...[
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(ctx, -1.0),
                                    style: TextButton.styleFrom(
                                      foregroundColor: KColor.danger,
                                      minimumSize: const Size(44, 48),
                                      textStyle: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    child: const Text('Use usual target'),
                                  ),
                                ),
                                const SizedBox(width: KSpacing.md),
                              ],
                              Expanded(
                                child: KButton(
                                  label: 'Save target',
                                  onTap: () {
                                    final val = double.tryParse(ctrl.text);
                                    Navigator.pop(ctx, val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
        _log.gymDay = GymDay.unpicked(targetCaloriesOverride: result);
      } else {
        _log.gymDay = _log.gymDay!.withTargetCaloriesOverride(result);
      }
    }
    // refreshTargetForDate deliberately skips days with a manual target, so
    // it never saved this change: persist it explicitly or it is lost on
    // restart.
    PersistenceService.saveDay(widget.date).ignore();
    PersistenceService.notifyLogsChanged();
    _refresh();
  }

  void _handleDeleteWithUndo(MealSection section, MealEntry entry) {
    _log.remove(section, entry);
    MealTombstones.instance.recordRemoval(dateKey(widget.date), entry);
    _persistLogChange();
    _refresh();

    showKToast(
      context,
      'Deleted ${entry.finalSavedInput}.',
      actionLabel: 'Undo',
      onAction: () {
        // Touched: the restored copy must beat the deletion even if
        // it already reached the cloud.
        _log.add(section, entry.touched());
        MealTombstones.instance.forgive(dateKey(widget.date), entry);
        _persistLogChange();
        _refresh();
        kHapticMedium();
      },
    );
  }

  DayTarget? get _dayTarget =>
      NutritionTargetEngine().effectiveTargetForDate(
        widget.date,
        health: widget.health,
      );

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

    // Keyed blocks so conditional sections never steal another block's state.
    var revealIndex = 0;
    Widget block(String key, Widget child, {bool reveal = true}) {
      // Only the first few blocks take part in the entrance; the rest are
      // below the fold and should simply be there.
      final i = revealIndex++;
      if (!widget.entrance || i > 6 || !reveal) {
        return KeyedSubtree(key: ValueKey(key), child: child);
      }
      return KReveal(key: ValueKey(key), index: i, child: child);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, 112),
      children: [
        // The rings arrive by Hero from the dashboard on the day the screen
        // opened on: already drawn, and not faded (a fading target would
        // flicker when the flight lands).
        block(
          'summary',
          _DaySummaryBanner(
            log: _log,
            target: target,
            dayStatus: dayStatus,
            onEditTarget: _editDailyTarget,
            heroTag: FuelLabel.heroTagFor(widget.date),
            sweepIn: !widget.entrance,
          ),
          reveal: false,
        ),
        // ── Coach insights ───────────────────────────────────────
        if (insights.isNotEmpty)
          block('insights', _CoachInsightCard(insights: insights)),

        block(
          'quality',
          DailyNutritionQualityCard(
            log: _log,
            targetCal: target?.calories ?? 2000.0,
            targetPro: target?.protein ?? 130.0,
          ),
        ),
        block(
          'macros',
          AdditionalMacrosCard(
            log: _log,
            targetCal: target?.calories ?? 2000.0,
            targetPro: target?.protein ?? 130.0,
            targetFiber: _targetFiber,
          ),
        ),
        // ── Meals ───────────────────────────────────────────────
        const _SectionHead('Meals', top: KSpacing.xxl),
        ...MealSection.values.map(
          (section) => block(
            'meal_${section.name}',
            _MealSectionCard(
              section: section,
              log: _log,
              onAdd: () => _openAddMeal(section),
              onEdit: _openEditMeal,
              onDelete: (entry) => _handleDeleteWithUndo(section, entry),
            ),
          ),
        ),
        // ── Quick Add ───────────────────────────────────────────
        block('quickadd', _QuickAddCard(onAdd: _quickAddMeal)),

        // ── Gym tracking ──────────────────────────────────────────
        block('gym', _GymCard(log: _log, date: widget.date, onChanged: _refresh)),
      ],
    );
  }

}

// ─── Shared private bits ─────────────────────────────────────────────────────

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
    final plan = WorkoutService.instance.planFor(date, log: log);
    if (plan.source == DayPlanSource.manual && log.gymDay != null) return log.gymDay!;
    if (!plan.isTraining) return const GymDay.unpicked();
    final name = plan.name;
    return GymDay(
      didGym:          true,
      workoutType:     name == null ? null : WorkoutType.fromSplitName(name),
      splitDayName:    name,
      splitOverridden: false,
      manual:          false,
    );
  }

  void _toggleGym(bool didGym) {
    final base = log.gymDay ?? const GymDay.unpicked();
    if (!didGym) {
      // An explicit No: a rest day on both the Nutrition and Train tabs.
      log.gymDay = base.withGym(false);
      onChanged();
      return;
    }
    // Yes: keep what the day already shows (the split's day), now as a pick.
    final shown = _effectiveGymDay();
    final name = shown.didGym
        ? shown.splitDayName
        : WorkoutService.instance.splitDayFor(date)?.name;
    log.gymDay = name != null
        ? base.withUserOverride(splitName: name, type: WorkoutType.fromSplitName(name))
        : base.withGym(true);
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
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _SelectChip(label: label, icon: icon, selected: selected, onTap: onTap);
  }

  @override
  Widget build(BuildContext context) {
    final gym    = _effectiveGymDay();
    final didGym = gym.didGym;
    final source = WorkoutService.instance.planFor(date, log: log).source;
    final isPrefilled = source == DayPlanSource.split && didGym;
    final fromSession = source == DayPlanSource.session;

    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.xxl, bottom: KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Did you train?', style: KText.h2.copyWith(fontSize: 18)),
                    ),
                    if (fromSession && gym.splitDayName != null)
                      Text(
                        '${gym.splitDayName}, from your logged workout',
                        style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                      )
                    else if (isPrefilled && gym.splitDayName != null)
                      Text(
                        WorkoutService.instance.isSetupDone
                            ? '${gym.splitDayName}, from your split'
                            : '${gym.splitDayName}, from ${WorkoutService.instance.split.name}',
                        style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              // Yes / No toggle
              KSegmented<bool>(
                segments: const [
                  KSegment(true, 'Yes', semanticLabel: 'Trained today: Yes'),
                  KSegment(false, 'No', semanticLabel: 'Trained today: No'),
                ],
                value: didGym,
                dense: true,
                segmentWidth: 56,
                onChanged: (yes) {
                  if (!yes && fromSession) {
                    showKToast(context, 'A workout is logged for this day. Delete it in Train to make it a rest day.');
                    return;
                  }
                  _toggleGym(yes);
                },
              ),
            ],
          ),

          // Workout type chips (only shown when gym = yes)
          AnimatedSize(
            duration: KMotion.of(context, KMotion.standard),
            curve: KMotion.emphasizedCurve,
            alignment: Alignment.topCenter,
            child: !didGym
                ? const SizedBox(width: double.infinity)
                : Builder(
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
                          const SizedBox(height: KSpacing.md),
                          if (hasSplitOptions) ...[
                            Text('Your split', style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: KSpacing.xs),
                            // MAIN SPLIT CHIPS
                            Wrap(
                              spacing: KSpacing.sm,
                              children: exactSplitDays.map((name) {
                                // Match by name rather than generic enum to ensure fidelity
                                final selected = gym.splitDayName == name;
                                return _buildChip(
                                  label: name,
                                  icon: KIcons.split(name),
                                  selected: selected,
                                  onTap: () => _selectSplitDay(name),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: KSpacing.md),
                          ],

                          // FALLBACK CHIPS
                          Text('Other workouts', style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: KSpacing.xs),
                          Wrap(
                            spacing: KSpacing.sm,
                            children: [WorkoutType.cardio, WorkoutType.other].map((t) {
                              // Mark fallback as selected if type matches but name is NOT in the main split
                              // (e.g. they literally chose 'Cardio' or 'Other')
                              final selected = gym.workoutType == t && !exactSplitDays.contains(gym.splitDayName);
                              return _buildChip(
                                label: t.displayName,
                                icon: KIcons.workout(t),
                                selected: selected,
                                onTap: () => _selectCoarseType(t),
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Selectable chip with a 48dp tap target. Text first, with a tiny
/// muscle-group mark; selection is an ink fill AND a check (never colour
/// alone).
class _SelectChip extends StatelessWidget {
  const _SelectChip({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? KColor.onInk : KColor.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          KHaptics.select();
          onTap();
        },
        borderRadius: KRadius.sm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: KMotion.of(context, KMotion.quick),
              curve: KMotion.emphasizedCurve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? KColor.ink : null,
                borderRadius: KRadius.sm,
                border: Border.all(
                  color: selected
                      ? KColor.ink
                      : KColor.fg.withValues(alpha: KColor.isDark ? 0.16 : 0.16),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KIcon(selected ? KIcons.done : icon, size: 15, color: selected ? fg : KColor.textSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: KText.bodyMedium.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Day summary ──────────────────────────────────────────────────────────────
// The same fuel label as the dashboard, so a day reads the same everywhere.

class _DaySummaryBanner extends StatelessWidget {
  final DayLog log;
  final DayTarget? target;
  final DayOutcomeResult? dayStatus;
  final VoidCallback? onEditTarget;
  final Object? heroTag;
  final bool sweepIn;
  const _DaySummaryBanner({
    required this.log,
    this.target,
    this.dayStatus,
    this.onEditTarget,
    this.heroTag,
    this.sweepIn = true,
  });

  static String _targetTitle(DayTarget t) => switch (t.label) {
        'Manual Override' => 'Custom target for this day',
        'Saved Target' => 'Your saved target',
        'Default' => 'Daily target',
        _ => '${t.label[0].toUpperCase()}${t.label.substring(1).toLowerCase()} target',
      };

  @override
  Widget build(BuildContext context) {
    final t = target;
    final status = dayStatus;
    final showStatus = !log.isEmpty &&
        status != null &&
        status.outcome != DayOutcome.incomplete &&
        status.outcome != DayOutcome.unlogged;

    return FuelLabel(
      heroTag: heroTag,
      sweepIn: sweepIn,
      title: t == null ? 'Fuel' : _targetTitle(t),
      trailing: (t != null && onEditTarget != null)
          ? KTextAction('Edit target', onTap: onEditTarget, semanticLabel: 'Edit daily target')
          : null,
      consumedCal: displayKcal(log),
      targetCal: t?.calories ?? 0,
      consumedPro: displayProtein(log),
      targetPro: t?.protein ?? 0,
      footer: log.isEmpty
          ? Text(
              'Nothing logged yet. Your first meal sets the tone.',
              style: KText.caption.copyWith(fontSize: 13.5, color: KColor.textSecondary),
            )
          : showStatus
              ? _DayStatusChip(status: status)
              : null,
    );
  }
}

// ─── Day status line ──────────────────────────────────────────────────────────

class _DayStatusChip extends StatelessWidget {
  final DayOutcomeResult status;
  const _DayStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    // A dot, the verdict, the note. No tinted pill, no emoji.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: KDot(color: status.color, size: 7),
        ),
        const SizedBox(width: KSpacing.sm),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: status.label,
                style: KText.bodyMedium.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (status.note.isNotEmpty)
                TextSpan(
                  text: '. ${status.note}',
                  style: KText.body.copyWith(fontSize: 14, color: KColor.textSecondary),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─── Meal section ─────────────────────────────────────────────────────────────
// Quietly typographic: a small time-of-day glyph, the section name, its kcal
// total set right, and an Add action. Logged meals hang beneath as hairline
// rows. No tile, no card.

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
    final hasEntries = entries.isNotEmpty;
    // The total is the sum of the numbers printed on the rows below.
    final kcal = entries.fold<int>(0, (s, e) => s + e.calMid.round());
    final pro = entries.fold<int>(0, (s, e) => s + e.result.protein.mid.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KHairline(),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(
            children: [
              KIcon(KIcons.meal(section), size: 18, color: hasEntries ? KColor.ember : KColor.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: section.displayName, style: KText.h3.copyWith(fontSize: 16)),
                      if (hasEntries)
                        TextSpan(
                          text: '   ${plural(entries.length, 'item')}',
                          style: KText.caption.copyWith(fontSize: 13, color: KColor.textMuted),
                        ),
                    ]),
                  ),
                ),
              ),
              if (hasEntries) ...[
                Semantics(
                  label: '$kcal kilocalories, $pro grams protein',
                  child: ExcludeSemantics(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: thousands(kcal),
                          style: KText.numSmall.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' kcal',
                          style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],
              _AddIconButton(
                onTap: onAdd,
                semanticLabel: 'Log a meal to ${section.displayName}',
              ),
            ],
          ),
        ),
        if (hasEntries)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: KSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const KHairline(),
                  _EntryTile(
                    entry: entries[i],
                    onTap: onEdit != null ? () => onEdit!(entries[i]) : null,
                    onDelete: () => onDelete(entries[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A 48dp "+" with an outlined circle: the one action per meal section.
class _AddIconButton extends StatelessWidget {
  const _AddIconButton({required this.onTap, required this.semanticLabel});
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        KHaptics.select();
        onTap();
      },
      semanticLabel: semanticLabel,
      borderRadius: KRadius.pill,
      scale: 0.9,
      child: SizedBox.square(
        dimension: 48,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.22 : 0.2)),
            ),
            child: KIcon(KIcons.add, size: 18, color: KColor.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Section heading on the day page: weight and space, no box.
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.top = KSpacing.xl, this.trailing});
  final String title;
  final double top;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: KSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: KText.h2.copyWith(fontSize: 18)),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

// ─── Entry tile ───────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  final MealEntry entry;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, this.onTap, required this.onDelete});

  static Color _qualityColor(int score) => score >= 80
      ? KColor.success
      : (score >= 60 ? KColor.textSecondary : KColor.ember);

  @override
  Widget build(BuildContext context) {
    final calMid = entry.result.calories.mid;
    final time = '${entry.addedAt.hour.toString().padLeft(2, '0')}:'
        '${entry.addedAt.minute.toString().padLeft(2, '0')}';
    // One printed number per macro; the section and day totals add these.
    final kcalN = entry.calMid.round();
    final protN = entry.result.protein.mid.round();
    final kcal = '$kcalN kcal';
    final prot = '$protN g';
    return Dismissible(
      key: ObjectKey(entry),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        color: KColor.danger.withValues(alpha: KColor.isDark ? 0.16 : 0.1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete',
              style: KText.caption.copyWith(fontSize: 13, color: KColor.danger, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            KIcon(KIcons.delete, color: KColor.danger, size: 20),
          ],
        ),
      ),
      child: Pressable(
        onTap: () => _showMealDetailSheet(context, entry, onTap),
        scale: 0.985,
        borderRadius: BorderRadius.zero,
        semanticLabel: '${entry.finalSavedInput}, $kcal, $prot protein, logged at $time. Open details',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.finalSavedInput,
                      style: KText.bodyMedium.copyWith(
                        fontSize: 15,
                        color: KColor.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    KDotStats([
                      KDotStat('$kcalN', 'kcal', color: KColor.ember),
                      KDotStat('$protN', 'g protein', color: KColor.protein),
                      if (calMid >= 50 && entry.result.mealQualityScore != null)
                        Text(
                          'Quality ${entry.result.mealQualityScore}',
                          style: KText.caption.copyWith(
                            fontSize: 13,
                            color: _qualityColor(entry.result.mealQualityScore!),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    time,
                    style: KText.numSmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: KColor.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  KIcon(KIcons.next, size: 18, color: KColor.textDisabled),
                ],
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

  showKSheet<void>(
    context: context,
    builder: (ctx) {
      final scoreColor = score == null
          ? KColor.textMuted
          : (score >= 80
              ? KColor.success
              : (score >= 60 ? KColor.textSecondary : KColor.ember));
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(KSpacing.p, 0, KSpacing.p, KSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KDragHandle(),
                const SizedBox(height: KSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.finalSavedInput, style: KText.h2),
                          const SizedBox(height: 4),
                          Text(
                            'Logged at ${entry.addedAt.hour.toString().padLeft(2, '0')}:${entry.addedAt.minute.toString().padLeft(2, '0')} · ${entry.section.displayName}',
                            style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: KColor.textSecondary, size: 20),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      style: IconButton.styleFrom(backgroundColor: KColor.cardHigh),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.xl),
                if (score != null) ...[
                  KReveal(
                    child: KCard(
                      boxShadow: const [],
                      child: Row(
                        children: [
                          RepaintBoundary(
                            child: KRing(
                              progress: (score / 100).clamp(0.0, 1.0),
                              colors: [scoreColor.withValues(alpha: 0.7), scoreColor],
                              size: 52,
                              stroke: 5,
                              semanticsLabel: 'Meal quality',
                              child: Text(
                                '$score',
                                style: KText.numSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: scoreColor),
                              ),
                            ),
                          ),
                          const SizedBox(width: KSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Meal quality', style: KText.h3),
                                if (entry.result.mealQualityExplanation != null &&
                                    entry.result.mealQualityExplanation!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    entry.result.mealQualityExplanation!,
                                    style: KText.caption.copyWith(fontSize: 13, height: 1.45),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: KSpacing.xl),
                ],
                Text('Macros', style: KText.h3.copyWith(color: KColor.textSecondary, fontSize: 14)),
                const SizedBox(height: 10),
                Builder(builder: (c) {
                  final locked = entry.result.macrosLockedByUser;
                  final cards = <Widget>[
                    _buildGridMacroCell('Calories', _macroLabel(entry.result.calories.min, entry.result.calories.max, 'kcal'), KColor.ember, locked: locked),
                    _buildGridMacroCell('Protein',  _macroLabel(entry.result.protein.min,  entry.result.protein.max,  'g'),    KColor.protein, locked: locked),
                    // When macros are locked always show carbs/fat/fiber, even if 0.
                    if (locked || (carbs != null && (carbs.max > 0 || carbs.min > 0)))
                      _buildGridMacroCell('Carbs', _macroLabel(carbs?.min ?? 0, carbs?.max ?? 0, 'g'), KColor.carbs, locked: locked),
                    if (locked || (fat != null && (fat.max > 0 || fat.min > 0)))
                      _buildGridMacroCell('Fat', _macroLabel(fat?.min ?? 0, fat?.max ?? 0, 'g'), KColor.fat, locked: locked),
                    if (locked || (fiber != null && (fiber.max > 0 || fiber.min > 0)))
                      _buildGridMacroCell('Fiber', _macroLabel(fiber?.min ?? 0, fiber?.max ?? 0, 'g'), KColor.fiber, locked: locked),
                    if (sugar != null && (sugar.max > 0 || sugar.min > 0))
                      _buildGridMacroCell('Sugar', _macroLabel(sugar.min, sugar.max, 'g'), KColor.carbs),
                    if (satFat != null && (satFat.max > 0 || satFat.min > 0))
                      _buildGridMacroCell('Sat. fat', _macroLabel(satFat.min, satFat.max, 'g'), KColor.fat),
                    if (sodium != null && (sodium.max > 0 || sodium.min > 0))
                      _buildGridMacroCell('Sodium', _macroLabel(sodium.min, sodium.max, 'mg'), KColor.textSecondary),
                  ];

                  // Two-column flow with intrinsic heights, so large text
                  // grows the cells instead of overflowing a fixed ratio.
                  return LayoutBuilder(
                    builder: (context, box) {
                      final cellW = (box.maxWidth - 10) / 2;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < cards.length; i++)
                            SizedBox(
                              width: cellW,
                              child: i < 8 ? KReveal(index: i, rise: 10, child: cards[i]) : cards[i],
                            ),
                        ],
                      );
                    },
                  );
                }),
                if (userWarnings.isNotEmpty) ...[
                  const SizedBox(height: KSpacing.xl),
                  Text('Worth checking', style: KText.h3.copyWith(color: KColor.textSecondary, fontSize: 14)),
                  const SizedBox(height: KSpacing.sm),
                  ...userWarnings.map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 2.0),
                          child: Icon(Icons.info_outline_rounded,
                              color: KColor.warning, size: 13),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            w,
                            style: KText.caption.copyWith(
                              fontSize: 13,
                              color: KColor.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
                if (onEditClick != null) ...[
                  const SizedBox(height: KSpacing.xxl),
                  KButton(
                    label: 'Edit this meal',
                    icon: Icons.edit_rounded,
                    width: double.infinity,
                    onTap: () {
                      Navigator.pop(ctx);
                      onEditClick();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildGridMacroCell(String name, String value, Color color, {bool locked = false}) {
  final dark = KColor.isDark;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: KColor.fg.withValues(alpha: dark ? 0.04 : 0.035),
      borderRadius: KRadius.sm,
      border: Border.all(
        color: locked
            ? color.withValues(alpha: dark ? 0.4 : 0.45)
            : Colors.transparent,
        width: 1.0,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                style: KText.caption.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KColor.textSecondary,
                ),
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock_rounded, size: 12, color: KColor.textMuted, semanticLabel: 'Locked'),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: KText.numSmall.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: KColor.textPrimary,
          ),
        ),
      ],
    ),
  );
}

String _macroLabel(double min, double max, String unit) {
  final minI = min.round();
  final maxI = max.round();
  return minI == maxI ? '$minI $unit' : '$minI-$maxI $unit';
}

// ─── Coach insight card ───────────────────────────────────────────────────────

class _CoachInsightCard extends StatelessWidget {
  final List<CoachInsight> insights;
  const _CoachInsightCard({required this.insights});

  static Color _tone(CoachInsightType type) => switch (type) {
    CoachInsightType.protein => KColor.protein,
    CoachInsightType.overGoal => KColor.ember,
    CoachInsightType.underEaten => KColor.ember,
    CoachInsightType.balance => KColor.textSecondary,
    CoachInsightType.info => KColor.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    // Show only the top 2 most relevant insights, as Kyno talking: its mark,
    // then plain sentences keyed by a thin coloured rule.
    final top = insights.take(2).toList();
    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const KynoMark(size: 22),
              const SizedBox(width: KSpacing.sm),
              Semantics(
                header: true,
                child: Text('Kyno noticed', style: KText.h3.copyWith(fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          for (int i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(height: KSpacing.md),
            _CoachInsightRow(insight: top[i], tone: _tone(top[i].type)),
          ],
          const SizedBox(height: KSpacing.lg),
          const KHairline(),
        ],
      ),
    );
  }
}

class _CoachInsightRow extends StatelessWidget {
  final CoachInsight insight;
  final Color tone;
  const _CoachInsightRow({required this.insight, required this.tone});

  @override
  Widget build(BuildContext context) {
    // The tone rule runs the text's full height. Painted behind the text
    // rather than stretched in a row, so no intrinsic-height pass is needed.
    return CustomPaint(
      painter: _ToneRulePainter(tone),
      child: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              insight.message,
              style: KText.bodyMedium.copyWith(
                color: KColor.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (insight.actionHint != null) ...[
              const SizedBox(height: 3),
              Text(
                insight.actionHint!,
                style: KText.body.copyWith(fontSize: 14, color: KColor.textSecondary, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 2 px rounded rule at x = 10, inset 3 px top and bottom.
class _ToneRulePainter extends CustomPainter {
  const _ToneRulePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 6) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(10, 3, 2, size.height - 6), const Radius.circular(1)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ToneRulePainter old) => old.color != color;
}

// ─── Quick Add item model ─────────────────────────────────────────────────────

// ─── Quick Add card ───────────────────────────────────────────────────────────

class _QuickAddCard extends StatefulWidget {
  final Future<void> Function({
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
  Map<String, NutritionResult> _resolvedResults = {};
  String? _loadingItemId;

  @override
  void initState() {
    super.initState();
    _resolveItems();
  }

  Future<void> _resolveItems() async {
    final List<QuickAddItem> allItems = QuickAddService.instance.customItems;
    final map = <String, NutritionResult>{};
    for (final item in allItems) {
      // Same precedence QuickAddService.addMealToDay logs with, so the card
      // always shows exactly what a tap will log: your correction, then your
      // remembered meal, then the item's own numbers.
      final remembered = FoodLinkService.instance.resolveMeal(item.name) ??
          UserNutritionMemory.instance.lookup(item.name) ??
          MealMemory.instance.lookupExactKnownFood(item.name) ??
          MealMemory.instance.lookupRecurring(item.name);
      final double cals = remembered != null ? remembered.calories.mid : item.calories;
      final double prot = remembered != null ? remembered.protein.mid : item.protein;
      map[item.id] = NutritionResult.createCustom(
        canonicalMeal: item.name,
        calories: cals,
        protein: prot,
        source: 'quick_add',
        userCorrected: true,
      );
    }
    if (mounted) {
      setState(() {
        _resolvedResults = map;
      });
    }
  }

  Future<void> _handleAdd(QuickAddItem item, double calories, double protein) async {
    if (_loadingItemId != null) return;
    final sw = Stopwatch()..start();
    final t0 = sw.elapsedMicroseconds / 1000.0;
    if (kDebugMode) debugPrint('[QuickAddTap] ⏱️ Tap received: T+${t0.toStringAsFixed(2)} ms (Item: "${item.name}")');

    setState(() => _loadingItemId = item.id);
    KHaptics.commit();

    await WidgetsBinding.instance.endOfFrame;
    final t1 = sw.elapsedMicroseconds / 1000.0;
    if (kDebugMode) debugPrint('[QuickAddTap] ⏱️ Loading state displayed: T+${t1.toStringAsFixed(2)} ms');

    try {
      await widget.onAdd(name: item.name, calories: calories, protein: protein);
    } finally {
      if (mounted) {
        setState(() => _loadingItemId = null);
      }
    }
  }

  Future<void> _deleteCustomItem(QuickAddItem item) async {
    // Optimistic: deleteItem drops the item from memory synchronously, so the
    // chip disappears this frame; the disk write follows.
    final done = QuickAddService.instance.deleteItem(item);
    await _resolveItems();
    await done;
  }

  Future<void> _openAddCustom() async {
    final result = await showKSheet<QuickAddItem>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCustomQuickSheet(),
    );
    if (result == null || !mounted) return;
    final exists = QuickAddService.instance.customItems.any(
      (i) => i.name.toLowerCase() == result.name.toLowerCase(),
    );
    if (exists) {
      KHaptics.reject();
      showKToast(context, 'That one\'s already in Quick Add.', kind: KToastKind.error);
      return;
    }
    // Optimistic: both calls update memory synchronously, so the new chip
    // shows this frame; the disk writes finish after.
    final saved = Future.wait([
      UserNutritionMemory.instance.saveOverride(
        result.name,
        result.calories,
        result.protein,
        referenceQuantity: 1.0,
        referenceUnit: 'serving',
      ),
      QuickAddService.instance.saveItem(result),
    ]);
    await _resolveItems();
    await saved;
  }

  @override
  Widget build(BuildContext context) {
    final allItems = QuickAddService.instance.customItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(
          'Quick add',
          top: KSpacing.xxl,
          trailing: KTextAction(
            'New',
            icon: KIcons.add,
            onTap: _openAddCustom,
            semanticLabel: 'Add a Quick Add item',
          ),
        ),
        Text(
          allItems.isEmpty
              ? 'Nothing here yet. Add your go-to meals and log them in one tap.'
              : 'Tap to log. Long-press to remove.',
          style: KText.caption.copyWith(fontSize: 13, color: KColor.textMuted),
        ),
        const SizedBox(height: KSpacing.xs),
        ...allItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final resolved = _resolvedResults[item.id];
          final cals = resolved?.calories.mid ?? item.calories;
          final prot = resolved?.protein.mid ?? item.protein;
          final isLoading = _loadingItemId == item.id;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (i > 0) const KHairline(),
              _QuickAddRow(
                title: item.name,
                calories: cals.round(),
                protein: prot.round(),
                isCustom: true,
                isLoading: isLoading,
                onTap: () => _handleAdd(item, cals, prot),
                onDelete: () => _deleteCustomItem(item),
              ),
            ],
          );
        }),
        const KHairline(),
      ],
    );
  }
}

// ─── Quick Add row ────────────────────────────────────────────────────────────

class _QuickAddRow extends StatelessWidget {
  final String       title;
  final int          calories;
  final int          protein;
  final bool         isCustom;
  final bool         isLoading;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _QuickAddRow({
    required this.title,
    required this.calories,
    required this.protein,
    required this.isCustom,
    this.isLoading = false,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: isLoading ? null : onTap,
      onLongPress: (isCustom && onDelete != null && !isLoading)
          ? () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: KColor.surface,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: KRadius.xl,
                    side: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
                  ),
                  title: Text('Remove from Quick Add?', style: KText.h2),
                  content: Text('"$title" comes off your Quick Add list. You can add it back any time.',
                      style: KText.body.copyWith(color: KColor.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: KColor.textSecondary,
                        minimumSize: const Size(64, 48),
                      ),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () { Navigator.of(context).pop(); onDelete!(); },
                      style: TextButton.styleFrom(
                        foregroundColor: KColor.danger,
                        minimumSize: const Size(64, 48),
                        textStyle: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              )
          : null,
      scale: 0.985,
      borderRadius: BorderRadius.zero,
      semanticLabel: 'Quick add $title, $calories kcal, $protein grams protein',
      child: AnimatedOpacity(
        duration: KMotion.of(context, KMotion.quick),
        opacity: isLoading ? 0.6 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: KText.bodyMedium.copyWith(
                            fontSize: 15,
                            color: KColor.textPrimary,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    KDotStats([
                      KDotStat('$calories', 'kcal', color: KColor.ember),
                      KDotStat('$protein', 'g protein', color: KColor.protein),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              SizedBox(
                width: 24,
                height: 24,
                child: AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  child: isLoading
                      ? Padding(
                          key: const ValueKey('busy'),
                          padding: const EdgeInsets.all(3),
                          child: KSpinner(size: 18, color: KColor.textSecondary),
                        )
                      : Icon(
                          Icons.add_circle_outline,
                          key: const ValueKey('add'),
                          size: 22,
                          color: KColor.textPrimary,
                        ),
                ),
              ),
            ],
          ),
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
      setState(() { _loading = false; _error = "Couldn't estimate that. Check your connection and try again."; });
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
    final kbHeight = MediaQuery.viewInsetsOf(context).bottom;
    final fieldBorder = OutlineInputBorder(
      borderRadius: KRadius.md,
      borderSide: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
    );
    return Container(
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border)),
      ),
      padding: EdgeInsets.only(bottom: KSpacing.xl + kbHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KSheetHeader(
              'Add to Quick Add',
              subtitle: 'Name a food and Kyno estimates it. One tap to log next time.',
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Input row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          style: KText.body.copyWith(color: KColor.textPrimary),
                          cursorColor: KColor.ink,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _estimate(),
                          decoration: InputDecoration(
                            hintText: 'e.g. 2 roti with dal',
                            hintStyle: KText.body.copyWith(color: KColor.textDisabled),
                            filled: true,
                            fillColor: KColor.card,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: fieldBorder,
                            enabledBorder: fieldBorder,
                            focusedBorder: OutlineInputBorder(
                                borderRadius: KRadius.md,
                                borderSide: BorderSide(color: KColor.ink, width: 1.5)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Pressable(
                        onTap: _loading ? null : _estimate,
                        semanticLabel: 'Estimate',
                        borderRadius: KRadius.md,
                        child: AnimatedContainer(
                          duration: KMotion.of(context, KMotion.quick),
                          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _loading
                                  ? KGradient.primary.map((c) => c.withValues(alpha: 0.45)).toList()
                                  : KGradient.primary,
                            ),
                            borderRadius: KRadius.pill,
                          ),
                          child: AnimatedSwitcher(
                            duration: KMotion.of(context, KMotion.quick),
                            child: _loading
                                ? KSpinner(
                                    key: const ValueKey('busy'),
                                    size: 16,
                                    color: KColor.onInk,
                                  )
                                : Text(
                                    'Estimate',
                                    key: const ValueKey('label'),
                                    style: KText.bodyMedium.copyWith(
                                      color: KColor.onInk,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 14, color: KColor.warning),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(_error!, style: KText.caption.copyWith(fontSize: 13, color: KColor.warning)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Result
                  AnimatedSize(
                    duration: KMotion.of(context, KMotion.standard),
                    curve: KMotion.emphasizedCurve,
                    alignment: Alignment.topCenter,
                    child: _calories == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: KSpacing.lg),
                            child: KCard(
                              boxShadow: const [],
                              border: Border.all(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const KynoMark(size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Kyno\'s estimate',
                                          style: KText.caption.copyWith(
                                            color: KColor.textSecondary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => setState(() => _showEdit = !_showEdit),
                                        style: TextButton.styleFrom(
                                          foregroundColor: KColor.textSecondary,
                                          minimumSize: const Size(48, 48),
                                          textStyle: KText.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        child: Text(_showEdit ? 'Done' : 'Adjust'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  AnimatedSwitcher(
                                    duration: KMotion.of(context, KMotion.quick),
                                    child: !_showEdit
                                        ? KDotStats(
                                            key: const ValueKey('chips'),
                                            [
                                              KDotStat('${_calories!.round()}', 'kcal', color: KColor.ember, size: 16),
                                              KDotStat('${_protein!.round()}', 'g protein', color: KColor.protein, size: 16),
                                            ],
                                          )
                                        : Row(
                                            key: const ValueKey('edit'),
                                            children: [
                                              Expanded(child: _NumField(controller: _calCtrl, label: 'kcal', color: KColor.ember)),
                                              const SizedBox(width: 10),
                                              Expanded(child: _NumField(controller: _proCtrl, label: 'g protein', color: KColor.protein)),
                                            ],
                                          ),
                                  ),
                                  const SizedBox(height: 14),
                                  KButton(
                                    label: 'Save to Quick Add',
                                    onTap: _accept,
                                  ),
                                ],
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

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Color  color;
  const _NumField({required this.controller, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final hair = KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      cursorColor: KColor.ink,
      style: KText.numSmall.copyWith(color: KColor.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        label: Text.rich(
          TextSpan(children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            TextSpan(text: label),
          ]),
        ),
        labelStyle: KText.caption.copyWith(color: KColor.textSecondary, fontSize: 13),
        filled: true,
        fillColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.035),
        border: OutlineInputBorder(
            borderRadius: KRadius.sm,
            borderSide: BorderSide(color: hair)),
        enabledBorder: OutlineInputBorder(
            borderRadius: KRadius.sm,
            borderSide: BorderSide(color: hair)),
        focusedBorder: OutlineInputBorder(
            borderRadius: KRadius.sm,
            borderSide: BorderSide(color: KColor.ink, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
