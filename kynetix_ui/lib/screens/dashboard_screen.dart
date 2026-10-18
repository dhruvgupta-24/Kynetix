import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'dart:async' show Timer;
import 'dart:convert';
import 'dart:math' as math;
import 'app_shell.dart';
import '../config/app_theme.dart';
import 'barcode_scanner_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/day_detail_screen.dart';
import '../models/day_log.dart';
import '../models/carry_forward_record.dart';
import '../services/health_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../widgets/body_log_widgets.dart';
import '../widgets/fasting_card.dart';
import '../services/fasting_service.dart';
import '../widgets/nutrients_summary_card.dart';
import '../services/body_metrics_service.dart';
import '../models/quick_add_item.dart';
import '../services/quick_add_service.dart';
import '../services/meal_repeat_service.dart';
import '../services/profile_service.dart';
import '../services/widget_service.dart';
import '../services/workout_service.dart';
import '../services/user_session_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/insights_report_service.dart';
import 'insights_screen.dart';
import 'workout_screen.dart';
import 'add_meal_screen.dart';
import '../ui/k_rolling.dart';
import '../widgets/k_equal_height_row.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────
//
// Nutrition tab root. Lives inside AppShell, which paints the aurora (KTone.fuel)
// and floats a glass dock over the bottom of the body, so:
//   • the Scaffold is transparent,
//   • scroll content ends with dock clearance,
//   • the "Add Meal" button is lifted above the dock using the body's bottom
//     padding (AppShell's Scaffold adds the dock height to it via extendBody).
//
// Motion budget: one staggered entrance on first mount; the memorable moment is
// the concentric fuel rings (calories ember→saffron outside, protein jade
// inside) with counting numbers. Everything else is calm.

const _kMonthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  /// Calendar starts as a compact week strip; expands to the full month grid.
  bool _calendarExpanded = false;

  /// Week shown by the collapsed strip after arrow navigation (null = derive
  /// from the selected date / today).
  DateTime? _weekAnchor;

  static final DateTime _baseMonth = DateTime(2024, 1, 1);
  late final PageController _calendarPageController;

  /// Collapsed strip: one page per week, swiped like the month grid.
  late final PageController _weekPageController;

  int _monthIndex(DateTime date) {
    return (date.year - _baseMonth.year) * 12 + date.month - _baseMonth.month;
  }

  DateTime _monthFromIndex(int index) {
    return DateTime(_baseMonth.year, _baseMonth.month + index, 1);
  }

  // ── Health Connect state ────────────────────────────────────────────────────
  HealthSyncResult?    _syncResult;
  List<WeightReading>? _weightHistory;  // 90-day weight from Health Connect
  bool _syncing     = false;
  bool _hcAvailable = false;

  /// Compact weight summary derived from latest Health Connect data.
  /// Null when no weight readings are available.
  WeightContext? get _weightContext {
    final all = _allWeights;
    return all.isNotEmpty ? WeightContext.fromHistory(all, goal: currentUserProfile?.goal) : null;
  }

  /// Health Connect weigh-ins plus the ones logged in Kynetix.
  List<WeightReading> get _allWeights => BodyMetricsService.instance.mergedReadings(_weightHistory);

  int _bodyTick = 0;
  void _onBodyChange() {
    if (mounted) setState(() => _bodyTick++);
  }

  /// A food suggested by the Nutrients screen: open the meal box with it.
  void _logFoodText(String text) {
    Navigator.of(context).push(
      kRiseRoute<dynamic>(
        builder: (_) => AddMealScreen(
          section: DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), _selectedDate),
          date: _selectedDate,
          initialText: text,
        ),
      ),
    );
  }

  Future<void> _logWeight() async {
    KHaptics.select();
    final t = BodyMetricsService.instance.trend(external: _weightHistory ?? const []);
    final start = BodyMetricsService.instance.weightFor(_selectedDate) ??
        t.latest?.scaleKg ??
        currentUserProfile?.weight ??
        70.0;
    final saved = await showWeightLogSheet(
      context,
      date: _selectedDate,
      startKg: start,
      trendKg: t.latest?.trendKg,
      weeklyRateKg: t.weeklyRateKg,
    );
    if (saved == null || !mounted) return;
    WidgetService.updateWidgetData().ignore();
    final p = currentUserProfile;
    final trendKg = BodyMetricsService.instance.trend(external: _weightHistory ?? const []).latest?.trendKg ?? saved;
    // Targets run on the profile weight: offer to move it once the trend has
    // drifted a full kilo away, never silently.
    if (p != null && (trendKg - p.weight).abs() >= 1.0) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        persist: false,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Text('Your targets use ${p.weight.toStringAsFixed(1)} kg. Trend is ${trendKg.toStringAsFixed(1)} kg.'),
        action: SnackBarAction(
          label: 'Update',
          onPressed: () async {
            final updated = p.copyWith(weight: (trendKg * 10).round() / 10);
            ProfileService.instance.currentUserProfile = updated;
            await ProfileService.instance.save(updated);
            await NutritionTargetEngine.instance.refreshTargetForDate(DateTime.now(), force: true);
            if (mounted) setState(() => _epoch++);
          },
        ),
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    _calendarPageController = PageController(initialPage: _monthIndex(_focusedMonth));
    _weekPageController = PageController(initialPage: _weekIndex(_weekStartOf(_stripAnchor())));
    // "Add meal" lives in the shell's dock, beside the nav pill.
    // Registered after the first frame: the dock rebuilds from this notifier,
    // and notifying mid-build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppShell.addMealAction.value = _showAddMealOptionsSheet;
    });
    WorkoutService.instance.addListener(_onWorkoutServiceChange);
    // Settings now live on the Profile tab: pick up any change there when
    // Nutrition comes back into view.
    AppShell.currentTab.addListener(_onTabChange);
    PersistenceService.dayLogNotifier.addListener(_onDayLogChange);
    BodyMetricsService.instance.changes.addListener(_onBodyChange);
    // Show a loading indicator if user already connected
    if (currentUserProfile?.healthSyncEnabled == true) {
      _syncing = true;
    }
    _initHealth();

    // Check for calorie carry-forward adjustments on next day's launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCalorieCarryForward();
    });
  }

  @override
  void dispose() {
    if (AppShell.addMealAction.value == _showAddMealOptionsSheet) {
      AppShell.addMealAction.value = null;
    }
    AppShell.currentTab.removeListener(_onTabChange);
    WorkoutService.instance.removeListener(_onWorkoutServiceChange);
    PersistenceService.dayLogNotifier.removeListener(_onDayLogChange);
    BodyMetricsService.instance.changes.removeListener(_onBodyChange);
    _calendarPageController.dispose();
    _weekPageController.dispose();
    super.dispose();
  }

  // Each listener bumps its own tick; only the sections that read that source
  // are rebuilt (see _section below).
  void _onWorkoutServiceChange() {
    if (mounted) {
      setState(() => _workoutTick++);
    }
  }

  void _onDayLogChange() {
    if (mounted) {
      setState(() => _logTick++);
    }
  }

  Future<void> _checkCalorieCarryForward() async {
    final profile = currentUserProfile;
    if (profile == null || !profile.carryForwardEnabled) return;

    final today = DateTime.now();
    final todayKey = dateKey(today);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayKey = dateKey(yesterday);

    // Carry-forward state is per user; keys are fixed to the user who opened
    // this check, so a later account switch cannot redirect them.
    final cfUserId = UserSessionCoordinator.instance.currentUserId;
    final resolvedKey = UserSessionCoordinator.carryForwardWriteKey(
        UserSessionCoordinator.kCarryForwardResolved, cfUserId);
    final historyKey = UserSessionCoordinator.carryForwardWriteKey(
        UserSessionCoordinator.kCarryForwardHistory, cfUserId);
    final prefs = await SharedPreferences.getInstance();
    final resolvedListRaw = UserSessionCoordinator.readCarryForwardList(
            prefs, UserSessionCoordinator.kCarryForwardResolved, cfUserId) ??
        [];
    if (resolvedListRaw.contains(yesterdayKey)) {
      debugPrint('[CarryForward] Yesterday $yesterdayKey already resolved');
      return;
    }

    final yesterdayLog = logFor(yesterday);
    final yesterdayConsumed = yesterdayLog.totalCaloriesMid;
    if (yesterdayConsumed == 0) {
      debugPrint('[CarryForward] Yesterday had 0 logged calories, skipping');
      return;
    }

    // The target the user actually saw yesterday (frozen when it was saved,
    // with that day's own profile and training plan), so the balance is
    // against a real number.
    final targetDay = NutritionTargetEngine().effectiveTargetForDate(
      yesterday,
      profile: profile.profileActiveOn(yesterday) ?? profile,
      health: _syncResult,
      log: yesterdayLog,
    );

    final yesterdayTarget = targetDay.calories;
    final diff = yesterdayConsumed - yesterdayTarget;
    final absDiff = diff.abs();

    final threshold = profile.carryForwardThreshold;
    if (absDiff < threshold) {
      debugPrint('[CarryForward] Deviation $absDiff < threshold $threshold, skipping');
      return;
    }

    // adjustment amount = -diff, capped at ±300
    final rawAdjustment = -diff;
    final adjustmentAmount = rawAdjustment.clamp(-300.0, 300.0);

    if (!mounted) return;

    final directionWord = diff > 0 ? 'above' : 'below';
    final absDiffInt = absDiff.round();
    final adjWord = adjustmentAmount > 0 ? 'increase' : 'decrease';
    final absAdjInt = adjustmentAmount.abs().round();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: KColor.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: KRadius.xl,
            side: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
          ),
          title: Row(
            children: [
              Icon(Icons.cached_rounded, color: KColor.ember),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Text('Balance out yesterday?', style: KText.h2),
              ),
            ],
          ),
          content: Text(
            'Yesterday landed $absDiffInt kcal $directionWord your target. No stress.\n\n'
            'Want to $adjWord today\'s target by $absAdjInt kcal to even it out? '
            'Still logging yesterday? Pick Not now and even it out later from Today\'s fuel.',
            style: KText.body.copyWith(color: KColor.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                resolvedListRaw.add(yesterdayKey);
                await prefs.setStringList(resolvedKey, resolvedListRaw);

                final historyRaw = UserSessionCoordinator.readCarryForwardList(
                        prefs, UserSessionCoordinator.kCarryForwardHistory, cfUserId) ??
                    [];
                final record = CarryForwardRecord(
                  date: todayKey,
                  yesterdayDate: yesterdayKey,
                  yesterdayTarget: yesterdayTarget,
                  yesterdayConsumed: yesterdayConsumed,
                  difference: diff,
                  adjustmentAmount: adjustmentAmount,
                  accepted: false,
                );
                historyRaw.add(jsonEncode(record.toJson()));
                await prefs.setStringList(historyKey, historyRaw);

                // Save inside today's gymDay so it syncs to cloud
                final todayLog = logFor(today);
                const defaultGymDay = GymDay.unpicked();
                todayLog.gymDay = (todayLog.gymDay ?? defaultGymDay).withCarryForwardRecord(record);
                await PersistenceService.saveDay(today);
              },
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              child: Text(
                'Not now',
                style: KText.bodyMedium.copyWith(color: KColor.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                resolvedListRaw.add(yesterdayKey);
                await prefs.setStringList(resolvedKey, resolvedListRaw);

                final historyRaw = UserSessionCoordinator.readCarryForwardList(
                        prefs, UserSessionCoordinator.kCarryForwardHistory, cfUserId) ??
                    [];
                final record = CarryForwardRecord(
                  date: todayKey,
                  yesterdayDate: yesterdayKey,
                  yesterdayTarget: yesterdayTarget,
                  yesterdayConsumed: yesterdayConsumed,
                  difference: diff,
                  adjustmentAmount: adjustmentAmount,
                  accepted: true,
                );
                historyRaw.add(jsonEncode(record.toJson()));
                await prefs.setStringList(historyKey, historyRaw);

                final todayLog = logFor(today);
                todayLog.carryForwardAdjustment = adjustmentAmount;
                const defaultGymDay = GymDay.unpicked();
                todayLog.gymDay = (todayLog.gymDay ?? defaultGymDay).withCarryForwardRecord(record);
                await PersistenceService.saveDay(today);
                // Today's target is usually frozen already; recompute it so the
                // accepted adjustment actually applies (a manual override wins).
                await NutritionTargetEngine.instance.refreshTargetForDate(today);

                _refresh();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: KColor.ink,
                foregroundColor: KColor.onInk,
                elevation: 0,
                minimumSize: const Size(64, 48),
                shape: const StadiumBorder(),
              ),
              child: Text(
                'Adjust today',
                style: KText.bodyMedium.copyWith(
                  color: KColor.onInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initHealth() async {
    final available = await HealthService().isAvailable();
    if (!mounted) return;
    setState(() => _hcAvailable = available);

    if (available && (currentUserProfile?.healthSyncEnabled == true)) {
      _doSyncInternal(); // auto-refresh on every launch
    } else {
      if (mounted) setState(() => _syncing = false);
    }
  }


  // Called from UI "Connect" button — guarded against double-tap.
  Future<void> _doSync() async {
    if (_syncing) return;
    _doSyncInternal();
  }

  // Internal sync — always runs regardless of the busy flag.
  // Sets _syncing=true itself so the UI shows a spinner.
  Future<void> _doSyncInternal() async {
    if (!mounted) return;
    setState(() => _syncing = true);

    // Only ask for permission if user hasn't previously connected.
    // When healthSyncEnabled=true the user already granted access once;
    // calling hasPermission() on Android can unreliably return false and
    // trigger the permission dialog on every launch — avoid that.
    final alreadyConnected = currentUserProfile?.healthSyncEnabled == true;
    if (!alreadyConnected) {
      final hasPerm = await HealthService().hasPermission();
      if (!hasPerm) {
        final granted = await HealthService().requestPermission();
        if (!granted) {
          if (mounted) setState(() => _syncing = false);
          return;
        }
      }
      final hasSleep = await HealthService().hasSleepPermission();
      if (!hasSleep) {
        await HealthService().requestSleepPermission();
      }
      final hasHrv = await HealthService().hasHrvPermission();
      if (!hasHrv) {
        await HealthService().requestHrvPermission();
      }
    }

    // Run step sync, weight sync, and sleep/HRV sync concurrently.
    // Weight, Sleep, and HRV permissions are separate: a denial does not block other results.
    // The profile this sync was started for. If the user signs out (or
    // switches account) while the platform calls are in flight, the results
    // are dropped instead of being written into whoever is signed in now.
    final syncUserId = UserSessionCoordinator.instance.currentUserId;
    final List<Object?> results;
    try {
      results = await Future.wait<Object?>([
        HealthService().sync(),
        HealthService().syncWeight(),
        HealthService().syncSleepAndHrv(),
      ]);
    } catch (e) {
      debugPrint('[Dashboard] Health sync failed: $e');
      if (mounted) setState(() => _syncing = false);
      return;
    }

    if (!mounted) return;

    final result        = results[0] as HealthSyncResult;
    final weightHistory = results[1] as List<WeightReading>;
    final sleepHrvData   = results[2] as Map<String, double?>;

    // Update WorkoutService with synced Sleep and HRV data
    await WorkoutService.instance.updateSleepAndHrv(
      sleepHours: sleepHrvData['sleep_hours'],
      hrvRmssd: sleepHrvData['hrv_rmssd'],
      hrvBaseline: sleepHrvData['hrv_baseline'],
    );

    // Signed out (or switched account) mid-sync: nothing to update.
    final profileNow = currentUserProfile;
    if (!mounted ||
        profileNow == null ||
        UserSessionCoordinator.instance.currentUserId != syncUserId) {
      if (mounted) setState(() => _syncing = false);
      return;
    }

    final avgSteps = result.effectiveAverageSteps;
    if (!result.hasError && result.hasData && avgSteps != null) {
      currentUserProfile = profileNow.copyWithHealth(
        averageDailySteps: avgSteps.toInt(),
        lastHealthSyncAt:  result.syncedAt,
      );
      ProfileService.instance.save(currentUserProfile!).ignore();
    }

    setState(() {
      _syncResult    = result;
      _weightHistory = weightHistory.isNotEmpty ? weightHistory : _weightHistory;
      _syncing       = false;
    });
    // New step average: today's frozen target follows it (past days keep
    // theirs). The refresh saves and refreshes the widget when it changes.
    if (result.hasData && !result.hasError) {
      NutritionTargetEngine.instance.refreshTargetForDate(DateTime.now()).ignore();
    }
    WidgetService.updateWidgetData().ignore();
  }

  UserProfile get _profile => currentUserProfile!;

  // ── Engine-based target ───────────────────────────────────────────────────
  //
  // Single _effectiveDayTarget mirrors DayDetailScreen._dayTarget exactly.
  // Priority order:
  //   1. Actual logged WorkoutSession (highest truth — real volume/sets → load bonus)
  //   2. log.gymDay (user manually toggled / type-selected)
  //   3. WorkoutService split config for this date (auto-prefill)
  //   4. Rest day fallback
  //
  // Calling dayTarget() ONCE ensures dashboard and DayDetail always match,
  // including the ±200 kcal workout load bonus.

  // Both engine calls are fairly heavy and every section asks for them, so
  // they are memoised for the duration of one build (reset at the top of
  // build()). Outside build they are recomputed on demand.
  WeeklyTargetPlan? _planMemo;
  DayTarget? _targetMemo;
  bool _targetMemoValid = false;
  bool _inBuild = false;

  WeeklyTargetPlan get _weeklyPlan {
    if (_inBuild) {
      return _planMemo ??=
          NutritionTargetEngine().weeklyPlan(_profile, health: _syncResult);
    }
    return NutritionTargetEngine().weeklyPlan(_profile, health: _syncResult);
  }

  DayTarget? get _effectiveDayTarget {
    if (_inBuild && _targetMemoValid) return _targetMemo;
    final t = NutritionTargetEngine().effectiveTargetForDate(_selectedDate, profile: _profile, health: _syncResult);
    if (_inBuild) {
      _targetMemo = t;
      _targetMemoValid = true;
    }
    return t;
  }

  // Live reads from the global store
  DayLog get _selectedLog      => logFor(_selectedDate);
  int get _consumedCalories => displayKcal(_selectedLog);
  int get _consumedProtein  => displayProtein(_selectedLog);
  double get _targetCalories   => _effectiveDayTarget?.calories ?? _weeklyPlan.avgDailyCalories;
  double get _targetProtein    => _effectiveDayTarget?.protein  ?? _weeklyPlan.avgDailyProtein;
  double get _targetFiber      => (14.0 * _targetCalories / 1000).clamp(20.0, 60.0);

  void _prevMonth() {
    if (!_calendarExpanded) return _stepWeek(-1);
    _calendarPageController.previousPage(
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
    );
  }

  void _nextMonth() {
    if (!_calendarExpanded) return _stepWeek(1);
    _calendarPageController.nextPage(
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
    );
  }

  /// Arrow taps on the collapsed strip slide the week pager, and its
  /// onPageChanged does the rest, so arrows and swipes behave the same.
  void _stepWeek(int dir) {
    if (!_weekPageController.hasClients) return _shiftWeek(dir * 7);
    final d = KMotion.of(context, KMotion.standard);
    if (dir < 0) {
      _weekPageController.previousPage(duration: d, curve: KMotion.emphasizedCurve);
    } else {
      _weekPageController.nextPage(duration: d, curve: KMotion.emphasizedCurve);
    }
  }

  // Weeks are counted from Monday 3 Jan 2000, in UTC days so DST never
  // shifts an index.
  static DateTime _weekStartOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
  static int _weekIndex(DateTime weekStart) =>
      DateTime.utc(weekStart.year, weekStart.month, weekStart.day).difference(DateTime.utc(2000, 1, 3)).inDays ~/ 7;
  static DateTime _weekFromIndex(int i) => DateTime(2000, 1, 3 + i * 7);

  /// Keeps the week pager on the strip's week when something else moved it
  /// (picking a day, changing month while expanded). Never mid-swipe.
  void _syncWeekPager(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_weekPageController.hasClients) return;
      if (_weekPageController.position.isScrollingNotifier.value) return;
      if (_weekPageController.page?.round() != index) _weekPageController.jumpToPage(index);
    });
  }

  /// Collapsed strip: step one week at a time, keeping the month grid
  /// (offstage) in sync so expanding lands on the same month.
  void _shiftWeek(int days) {
    KHaptics.select();
    final a = _stripAnchor();
    final next = DateTime(a.year, a.month, a.day + days);
    setState(() {
      _weekAnchor = next;
      _focusedMonth = DateTime(next.year, next.month, 1);
    });
    final page = _monthIndex(next);
    if (_calendarPageController.hasClients &&
        _calendarPageController.page?.round() != page) {
      _calendarPageController.jumpToPage(page);
    }
  }

  void _toggleCalendar() {
    KHaptics.select();
    setState(() => _calendarExpanded = !_calendarExpanded);
  }

  void _selectDay(DateTime d) {
    KHaptics.select();
    setState(() {
      _selectedDate = d;
      _weekAnchor = null;
    });
    _openDay(d);
  }

  Future<void> _openDay(DateTime date) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayDetailScreen(
          date:          date,
          health:        _syncResult,
          weightContext: _weightContext,
        ),
      ),
    );
    _refresh();   // refresh rings after returning
  }

  /// Scan a packaged product and log it to the selected day.
  Future<void> _scanBarcode() async {
    final outcome = await openBarcodeFlow(context, date: _selectedDate);
    if (outcome?.entry != null) _refresh();
  }

  /// Describe a meal to Kyno for the section that fits the time of day.
  Future<void> _describeMeal() async {
    final section = DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), _selectedDate);
    final entry = await Navigator.of(context).push<dynamic>(
      kRiseRoute<dynamic>(
        builder: (_) => AddMealScreen(section: section, date: _selectedDate),
      ),
    );
    if (entry != null) _refresh();
  }

  /// One tap from the + sheet: logs it, closes the sheet, offers Undo.
  void _confirmLogged(String what, List<MealEntry> added) {
    _refresh();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        behavior: SnackBarBehavior.floating,
        content: Text(what),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await MealRepeatService.undo(_selectedDate, added);
            _refresh();
          },
        ),
      ),
    );
  }

  Future<void> _relogRecent(RecentFood food) async {
    KHaptics.commit();
    final section = DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), _selectedDate);
    final added = await MealRepeatService.relog(_selectedDate, [food.entry], section: section);
    if (!mounted) return;
    _confirmLogged('Logged ${food.name}, ${thousands(food.kcal.round())} kcal', added);
  }

  Future<void> _logQuickAdd(QuickAddItem item) async {
    KHaptics.commit();
    final section = DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), _selectedDate);
    final entry = await QuickAddService.instance.addMealToDay(
      date: _selectedDate,
      name: item.name,
      calories: item.calories,
      protein: item.protein,
      section: section,
    );
    if (!mounted) return;
    _confirmLogged('Logged ${item.name}, ${thousands(entry.calMid.round())} kcal', [entry]);
  }

  Future<void> _repeatYesterday(List<MealEntry> entries) async {
    KHaptics.commit();
    final added = await MealRepeatService.relog(_selectedDate, entries);
    if (!mounted) return;
    final kcal = added.fold<double>(0, (s, e) => s + e.calMid).round();
    _confirmLogged('Copied ${plural(added.length, 'item')} from yesterday, ${thousands(kcal)} kcal', added);
  }

  void _showAddMealOptionsSheet() {
    // Computed once per open: what you can log again in one tap.
    final quickAdds = QuickAddService.instance.customItems;
    final quickNames = {for (final q in quickAdds) q.name.trim().toLowerCase()};
    final recent = MealRepeatService.recentFoods(date: _selectedDate)
        .where((f) => !quickNames.contains(f.name.toLowerCase()))
        .toList();
    final yesterday = _selectedLog.isEmpty
        ? MealRepeatService.yesterday(_selectedDate)
        : const <MealEntry>[];
    final yesterdayKcal = yesterday.fold<double>(0, (s, e) => s + e.calMid).round();

    showKSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        void go(VoidCallback f) {
          Navigator.pop(ctx);
          f();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: KSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KSheetHeader('Log a meal'),
                if (quickAdds.isNotEmpty || recent.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, KSpacing.sm),
                    child: Text(
                      'Again, in one tap',
                      style: KText.caption.copyWith(color: KColor.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                      children: [
                        for (final q in quickAdds)
                          _AgainPill(
                            title: q.name,
                            meta: '${thousands(q.calories.round())} kcal · ${q.protein.round()} g',
                            onTap: () => go(() => _logQuickAdd(q)),
                          ),
                        for (final f in recent)
                          _AgainPill(
                            title: f.name,
                            meta: '${thousands(f.kcal.round())} kcal · ${f.protein.round()} g',
                            onTap: () => go(() => _relogRecent(f)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: KSpacing.sm),
                ],
                const SizedBox(height: KSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KOptionRow(
                        icon: KIcons.kyno,
                        leading: const KynoMark(size: 24, outlined: true),
                        title: 'Describe it',
                        subtitle: 'Type it like you\'d say it. Kyno does the maths.',
                        onTap: () => go(_describeMeal),
                      ),
                      const KHairline(indent: 40),
                      KOptionRow(
                        icon: KIcons.scan,
                        title: 'Scan a barcode',
                        subtitle: 'Packaged food. Logs the exact pack, like 40 g.',
                        onTap: () => go(_scanBarcode),
                      ),
                      if (yesterday.isNotEmpty) ...[
                        const KHairline(indent: 40),
                        KOptionRow(
                          icon: Icons.replay_rounded,
                          title: 'Repeat yesterday',
                          subtitle: '${plural(yesterday.length, 'item')}, ${thousands(yesterdayKcal)} kcal. Undo if you change your mind.',
                          onTap: () => go(() => _repeatYesterday(yesterday)),
                        ),
                      ],
                      const SizedBox(height: KSpacing.xs),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: KTextAction(
                          'Open the full day',
                          onTap: () => go(() => _openDay(_selectedDate)),
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
    );
  }

  // ── Section memoisation ──────────────────────────────────────────────────
  //
  // The dashboard listens to both day logs and workout state. Instead of
  // rebuilding all nine sections (~650 widgets) on every tick, each section is
  // cached together with the inputs it reads; a section is rebuilt only when
  // one of those inputs changes. Explicit refreshes (returning from a pushed
  // screen, a sheet reporting an update) bump [_epoch], which invalidates
  // every section, so in-place log edits are always picked up.

  // ── Per-day entrance ───────────────────────────────────────────────────
  //
  // The meals block and the bento tiles rise 8 px and fade in, 50 ms apart,
  // the first time the dashboard shows a given day this session. Rebuilds,
  // tab returns and coming back from a pushed screen don't replay it; for a
  // new day the same KReveal elements replay in place (no remount).
  static final Set<String> _enteredDays = {};
  bool _firstEntranceDone = false;
  String _revealDay = '';
  bool _revealPlay = false;
  Duration _revealLead = Duration.zero;

  Widget _dayReveal(int index, Widget child) => KReveal(
        index: index,
        maxIndex: 5,
        rise: 8,
        stagger: const Duration(milliseconds: 50),
        duration: KMotion.standard,
        delay: _revealLead,
        enabled: _revealPlay,
        replayKey: _revealDay,
        child: child,
      );

  int _epoch = 0;
  int _logTick = 0;
  int _workoutTick = 0;
  final Map<int, (List<Object?>, Widget)> _sectionMemo = {};

  void _refresh() {
    if (!mounted) return;
    setState(() => _epoch++);
  }

  void _onTabChange() {
    if (AppShell.currentTab.value == 0) _refresh();
  }

  Widget _section(int slot, List<Object?> deps, Widget Function() build) {
    final prev = _sectionMemo[slot];
    if (prev != null && listEquals(prev.$1, deps)) return prev.$2;
    final widget = build();
    _sectionMemo[slot] = (deps, widget);
    return widget;
  }

  @override
  Widget build(BuildContext context) {
    _inBuild = true;
    _planMemo = null;
    _targetMemo = null;
    _targetMemoValid = false;
    try {
      return _buildBody(context);
    } finally {
      _inBuild = false;
    }
  }

  Widget _buildBody(BuildContext context) {
    // Inside AppShell this includes the floating dock's height (extendBody).
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final scrollBottom =
        math.max(KSpacing.dockClearance, bottomInset + KSpacing.lg) + KSpacing.lg;



    // Inputs every section depends on: palette (colours are resolved into
    // widget fields), reduced motion (durations), explicit refreshes, and the
    // calendar day (for "today").
    final common = [
      KColor.palette,
      KMotion.reduced(context),
      _epoch,
      dateKey(DateTime.now()),
    ];
    final selectedKey = dateKey(_selectedDate);
    final hour = TimeOfDay.now().hour;
    _revealDay = selectedKey;
    _revealPlay = !_enteredDays.contains(selectedKey);
    // On the very first show, wait for the sections above to start.
    _revealLead = _firstEntranceDone ? Duration.zero : KMotion.stagger * 4;

    // (section, reveals its own items) in screen order.
    final sections = <(Widget, bool)>[
      (_section(0, [...common, selectedKey, _profile, hour < 12 ? 0 : hour < 17 ? 1 : 2],
          _buildHeader), false),
      (_section(1, [
        ...common, _logTick, _focusedMonth, selectedKey, _calendarExpanded,
        _weekAnchor, _profile, _syncResult,
      ], _buildCalendar), false),
      (_section(2, [...common, _logTick, _workoutTick, _bodyTick, selectedKey, _profile, _syncResult],
          _buildFuelHero), false),
      (_section(12, [...common, _logTick, selectedKey, _profile, _syncResult, _carryTick],
          _buildCarryForwardCard), false),
      (_section(13, [...common, _logTick, selectedKey], _buildMeals), true),
      (_section(3, [
        ...common, _logTick, _workoutTick, _bodyTick, selectedKey, _profile, _syncResult,
        _hcAvailable, _syncing, _weightHistory,
      ], _buildBento), true),
      (_section(4, [...common, _logTick, _workoutTick, selectedKey, _profile, _syncResult],
          _buildNutritionDetails), false),
      (_section(10, [...common, _logTick, selectedKey], () => Padding(
        padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
        child: NutrientsSummaryCard(onLogFood: _logFoodText),
      )), false),
    ];
    _enteredDays.add(selectedKey);
    _firstEntranceDone = true;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                // One orchestrated entrance on first mount. Keys keep each
                // section's element (and KReveal state) stable across rebuilds.
                // Meals and bento run their own per-day entrance instead.
                for (var i = 0; i < sections.length; i++)
                  SliverToBoxAdapter(
                    key: ValueKey('dash-section-$i'),
                    child: sections[i].$2
                        ? sections[i].$1
                        : KReveal(index: i, child: sections[i].$1),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: scrollBottom)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final hour = TimeOfDay.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final first = _profile.name.trim().split(RegExp(r'\s+')).first;
    final isToday = dateKey(_selectedDate) == dateKey(DateTime.now());
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dateLine = '${weekdays[_selectedDate.weekday - 1]}, ${_selectedDate.day} '
        '${_kMonthShort[_selectedDate.month - 1]}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xl, KSpacing.md, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    isToday ? 'Today, $dateLine' : 'Looking back, $dateLine',
                    key: ValueKey(dateLine),
                    style: KText.caption.copyWith(fontSize: 13.5, color: KColor.textSecondary),
                  ),
                ),
                const SizedBox(height: 2),
                Semantics(
                  header: true,
                  child: Text(
                    first.isEmpty ? greeting : '$greeting, $first',
                    style: KText.display.copyWith(fontSize: 28),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Calendar ─────────────────────────────────────────────────────────────────
  //
  // Collapsed: the week around the selected day (or today / the 1st of the
  // focused month). Expanded: the full swipeable month grid. Month navigation
  // works in both modes — the PageView stays mounted (Offstage) so its
  // controller and onPageChanged keep driving _focusedMonth.

  DateTime _stripAnchor() {
    if (_weekAnchor != null) return _weekAnchor!;
    final now = DateTime.now();
    bool inFocused(DateTime d) =>
        d.year == _focusedMonth.year && d.month == _focusedMonth.month;
    if (inFocused(_selectedDate)) return _selectedDate;
    if (inFocused(now)) return now;
    return DateTime(_focusedMonth.year, _focusedMonth.month, 1);
  }

  Widget _buildCalendar() {
    // Markers are resolved lazily for the days actually on screen (a week, or
    // one month page) instead of totalling every logged day in the store.
    final marks = _DayMarks(_weeklyPlan.avgDailyCalories);

    _syncWeekPager(_weekIndex(_weekStartOf(_stripAnchor())));

    // No card: the week sits on the page, set like a diary strip.
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.sm, KSpacing.md, KSpacing.sm, 0),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CalendarHeader(
              month: _focusedMonth,
              expanded: _calendarExpanded,
              onPrev: _prevMonth,
              onNext: _nextMonth,
              onToggle: _toggleCalendar,
            ),
            const SizedBox(height: KSpacing.xs),
            AnimatedSize(
              duration: KMotion.of(context, KMotion.standard),
              curve: KMotion.emphasizedCurve,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Offstage(
                    offstage: !_calendarExpanded,
                    child: SizedBox(
                      height: 272,
                      child: PageView.builder(
                        controller: _calendarPageController,
                        onPageChanged: (index) {
                          if (!_calendarExpanded) return; // driven by _shiftWeek
                          kHapticSelect();
                          setState(() {
                            _focusedMonth = _monthFromIndex(index);
                            _weekAnchor = null;
                          });
                        },
                        itemBuilder: (context, index) {
                          // Collapsed: the pager only has to keep its
                          // position, so skip building ~40 hidden cells.
                          if (!_calendarExpanded) return const SizedBox.shrink();
                          final month = _monthFromIndex(index);
                          return _CalendarGrid(
                            focusedMonth: month,
                            selectedDate: _selectedDate,
                            marks:        marks,
                            onSelect:     _selectDay,
                          );
                        },
                      ),
                    ),
                  ),
                  // Kept mounted like the month pager, so the controller
                  // never re-attaches on a stale week.
                  Offstage(
                    offstage: _calendarExpanded,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _WeekdayRow(),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 48,
                          child: PageView.builder(
                            controller: _weekPageController,
                            onPageChanged: (index) {
                              if (_calendarExpanded) return;
                              final delta = index - _weekIndex(_weekStartOf(_stripAnchor()));
                              if (delta != 0) _shiftWeek(delta * 7);
                            },
                            itemBuilder: (context, index) => _WeekStrip(
                              weekStart:    _weekFromIndex(index),
                              focusedMonth: _focusedMonth,
                              selectedDate: _selectedDate,
                              marks:        marks,
                              onSelect:     _selectDay,
                            ),
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
      ),
    );
  }

  // ── Weight permission request ──────────────────────────────────────────────────────

  // ── Workout State ─────────────────────────────────────────────────────────────

  /// [start]: open today's session (or resume the paused one) right away,
  /// instead of making you tap Start again on Train.
  void _goToTrainTab({bool start = false}) {
    AppShell.of(context)?.switchToTab(1);
    if (start) WorkoutScreen.startRequests.value++;
  }

  // ── Meals ───────────────────────────────────────────────────────────────────
  //
  // What was eaten, by meal: the line you typed, its kcal and protein. Tapping
  // anywhere opens the full day, where meals are edited.

  Widget _buildMeals() {
    final log = _selectedLog;
    final groups = [
      for (final s in MealSection.values)
        if (log.entriesFor(s).isNotEmpty) (s, log.entriesFor(s)),
    ];
    return _dayReveal(0, Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xl, KSpacing.p, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: KSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Meals', style: KText.h3.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                KTextAction('Open day', onTap: () => _openDay(_selectedDate)),
              ],
            ),
          ),
          Pressable(
            // Nothing logged yet: the card is the way in, so it logs a meal.
            onTap: () {
              final log = AppShell.addMealAction.value;
              if (groups.isEmpty && log != null) {
                log();
              } else {
                _openDay(_selectedDate);
              }
            },
            scale: 0.98,
            borderRadius: KRadius.lg,
            semanticLabel: groups.isEmpty ? 'No meals logged. Log a meal' : 'Open the day to edit meals',
            child: KCard(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.xs),
              child: groups.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: KSpacing.lg),
                      child: Row(
                        children: [
                          Icon(KIcons.plate, size: 18, color: KColor.textMuted),
                          const SizedBox(width: KSpacing.md),
                          Expanded(
                            child: Text(
                              'Nothing logged yet. Tap here and type what you ate.',
                              style: KText.body.copyWith(color: KColor.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < groups.length; i++) ...[
                          if (i > 0) const KHairline(),
                          _MealGroupRow(section: groups[i].$1, entries: groups[i].$2),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    ));
  }

  // ── Bento ───────────────────────────────────────────────────────────────────
  //
  // The rest of the day at a glance: six tiles in two columns, each with one
  // number and one tap. The full cards (fasting timer, step sync, weight
  // chart, targets) open from their tile.

  Widget _buildBento() {
    final weights = _allWeights;
    final wc = weights.isNotEmpty ? _weightContext : null;
    final tiles = <Widget>[
      _trainingTile(),
      const _FastingTile(),
      _stepsTile(),
      _weightTile(wc),
      _streakTile(),
      _targetsTile(),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.lg, KSpacing.p, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < tiles.length; r += 2) ...[
            if (r > 0) const SizedBox(height: KSpacing.md),
            // Both tiles in a row share the taller one's height, without an
            // intrinsic pass over the tiles.
            KEqualHeightRow(
              gap: KSpacing.md,
              minHeight: _BentoTile.minHeight,
              children: [
                _dayReveal(1 + r, tiles[r]),
                _dayReveal(2 + r, tiles[r + 1]),
              ],
            ),
          ],
          if (weights.length >= 2) ...[
            const SizedBox(height: KSpacing.md),
            _dayReveal(
              1 + tiles.length,
              _WeightTrendCard(
                key: const ValueKey('weight-trend'),
                healthReadings: _weightHistory ?? const [],
                onLogWeight: _logWeight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trainingTile() {
    final ws = WorkoutService.instance;
    final isToday = dateKey(_selectedDate) == dateKey(DateTime.now());
    final plan = ws.planFor(_selectedDate);
    final done = ws.sessionsForDate(_selectedDate);
    String label;
    String value;
    String? sub;
    VoidCallback? onTap = () => _goToTrainTab();
    var check = false;
    if (done.isNotEmpty) {
      label = isToday ? 'Trained today' : 'Trained';
      value = done.first.splitDayName;
      sub = 'Done';
      check = true;
    } else if (!isToday) {
      label = 'Training';
      value = plan.isTraining ? (plan.name ?? 'Workout') : 'Rest day';
      sub = plan.isTraining ? 'Not logged' : null;
    } else if (ws.draftSession != null) {
      label = 'In progress';
      value = ws.draftSession!.splitDayName;
      sub = 'Tap to resume';
      onTap = () => _goToTrainTab(start: true);
    } else if (!ws.isSetupDone && plan.source == DayPlanSource.split) {
      label = 'Training';
      value = 'Pick a split';
      sub = 'Takes a minute';
    } else if (plan.isTraining) {
      label = 'Up next';
      value = plan.name ?? 'Workout';
      sub = 'Tap to start';
      onTap = () => _goToTrainTab(start: true);
    } else {
      label = 'Rest day';
      value = 'Recover';
      sub = plan.source == DayPlanSource.manual ? 'You picked rest' : 'Part of the plan';
    }
    return _BentoTile(
      icon: KIcons.train,
      accent: KColor.ink,
      label: label,
      value: value,
      sub: sub,
      check: check,
      onTap: onTap,
    );
  }

  Widget _stepsTile() {
    final r = _syncResult;
    final connected = _hcAvailable && r != null && !r.hasError && _profile.healthSyncEnabled;
    if (_syncing) {
      return _BentoTile(
        icon: Icons.directions_walk_rounded,
        accent: KColor.textSecondary,
        label: 'Steps',
        value: 'Syncing',
        sub: 'Health Connect',
      );
    }
    if (!connected) {
      return _BentoTile(
        icon: Icons.directions_walk_rounded,
        accent: KColor.textSecondary,
        label: 'Steps',
        value: _hcAvailable ? 'Connect' : 'Not set up',
        sub: _hcAvailable ? 'For sharper targets' : 'Install Health Connect',
        onTap: _hcAvailable ? _doSync : _openStepsSheet,
      );
    }
    final avg = r.effectiveAverageSteps ?? r.averageDailySteps14d;
    return _BentoTile(
      icon: Icons.directions_walk_rounded,
      accent: KColor.textSecondary,
      label: 'Steps a day',
      value: avg != null ? thousands(avg) : 'No data',
      sub: r.activityTier.displayName,
      onTap: _openStepsSheet,
    );
  }

  void _openStepsSheet() {
    showKSheet<void>(
      context: context,
      builder: (ctx) => _BentoSheet(
        title: 'Activity sync',
        child: _ActivitySyncCard(
          available: _hcAvailable,
          syncing: _syncing,
          syncResult: _syncResult,
          profile: _profile,
          onConnect: () {
            Navigator.of(ctx).pop();
            _doSync();
          },
          onSync: () {
            Navigator.of(ctx).pop();
            _doSync();
          },
        ),
      ),
    );
  }

  Widget _weightTile(WeightContext? wc) {
    if (wc == null || wc.latestWeightKg == null) {
      return _BentoTile(
        icon: Icons.monitor_weight_outlined,
        accent: KColor.textSecondary,
        label: 'Weight',
        value: 'Log it',
        sub: 'See the trend',
        onTap: _logWeight,
      );
    }
    final d = wc.delta7dKg;
    String? sub;
    if (d != null) {
      sub = d.abs() < 0.1
          ? 'Steady this week'
          : '${d > 0 ? '+' : '-'}${d.abs().toStringAsFixed(1)} kg this week';
    }
    return _BentoTile(
      icon: Icons.monitor_weight_outlined,
      accent: KColor.textSecondary,
      label: 'Weight',
      value: wc.latestWeightKg!.toStringAsFixed(1),
      unit: 'kg',
      sub: sub ?? 'Tap to log',
      onTap: _logWeight,
    );
  }

  Widget _streakTile() {
    return ListenableBuilder(
      listenable: InsightsReportService.instance,
      builder: (context, _) {
        final streak = _computeStreak();
        final newCount = InsightsReportService.instance.newAchievementCount;
        return _BentoTile(
          icon: KIcons.calories,
          accent: KColor.ember,
          label: 'Logging streak',
          value: '$streak',
          unit: streak == 1 ? 'day' : 'days',
          sub: newCount > 0 ? '$newCount new in insights' : 'Weekly insights',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightsScreen()));
          },
        );
      },
    );
  }

  Widget _targetsTile() {
    final plan = _weeklyPlan;
    return _BentoTile(
      icon: Icons.track_changes_rounded,
      accent: KColor.ink,
      label: 'Targets',
      value: thousands(plan.avgDailyCalories),
      unit: 'kcal',
      sub: '${plan.avgDailyProtein.round()} g protein a day',
      onTap: () => showKSheet<void>(
        context: context,
        builder: (_) => _BentoSheet(title: 'Your targets', child: _buildTargets(inset: false)),
      ),
    );
  }

  // ── Carry-forward card ─────────────────────────────────────────────────────
  //
  // The midnight "Balance out yesterday?" prompt fires before late meals for
  // yesterday are logged. This card stays on today's view and recomputes from
  // yesterday's log as it is now, so the balance can be applied, updated or
  // undone at any point today.

  int _carryTick = 0;
  bool _carryDismissed = false;
  String? _carryDismissedFor;

  /// What yesterday says today should shift by right now (0 below the
  /// user's threshold), and what is applied to today already.
  ({double suggested, double applied, double diff, double target, double consumed})? _carryState() {
    final profile = currentUserProfile;
    if (profile == null || !profile.carryForwardEnabled) return null;
    final today = DateTime.now();
    if (dateKey(_selectedDate) != dateKey(today)) return null;
    final yesterday = today.subtract(const Duration(days: 1));
    final yLog = logFor(yesterday);
    final consumed = yLog.totalCaloriesMid;
    final applied = logFor(today).carryForwardAdjustment ?? 0;
    if (consumed == 0 && applied == 0) return null;
    final target = NutritionTargetEngine().effectiveTargetForDate(
      yesterday,
      profile: profile.profileActiveOn(yesterday) ?? profile,
      health: _syncResult,
      log: yLog,
    ).calories;
    final diff = consumed - target;
    final suggested = diff.abs() < profile.carryForwardThreshold ? 0.0 : (-diff).clamp(-300.0, 300.0).toDouble();
    return (suggested: suggested, applied: applied, diff: diff, target: target, consumed: consumed);
  }

  Future<void> _applyCarry(double? amount) async {
    try {
      await _applyCarryInner(amount);
    } catch (e, st) {
      debugPrint('[CarryForward] apply failed: $e $st');
    }
  }

  Future<void> _applyCarryInner(double? amount) async {
    final today = DateTime.now();
    final todayLog = logFor(today);
    final st = _carryState();
    final apply = amount != null && amount != 0;
    todayLog.carryForwardAdjustment = apply ? amount : null;
    // The day's record decides what applies (a "Not now" from the midnight
    // prompt is stored as declined), so it is rewritten to match.
    if (st != null) {
      final record = CarryForwardRecord(
        date: dateKey(today),
        yesterdayDate: dateKey(today.subtract(const Duration(days: 1))),
        yesterdayTarget: st.target,
        yesterdayConsumed: st.consumed,
        difference: st.diff,
        adjustmentAmount: apply ? amount : st.suggested,
        accepted: apply,
      );
      todayLog.gymDay = (todayLog.gymDay ?? const GymDay.unpicked()).withCarryForwardRecord(record);
    }
    await PersistenceService.saveDay(today);
    await NutritionTargetEngine.instance.refreshTargetForDate(today);
    KHaptics.commit();
    if (!mounted) return;
    setState(() => _carryTick++);
    _refresh();
  }

  Widget _buildCarryForwardCard() {
    final todayKey = dateKey(DateTime.now());
    if (_carryDismissed && _carryDismissedFor == todayKey) return const SizedBox.shrink();
    final st = _carryState();
    if (st == null) return const SizedBox.shrink();
    final suggested = st.suggested.round();
    final applied = st.applied.round();
    if (suggested == 0 && applied == 0) return const SizedBox.shrink();

    String signed(int v) => '${v > 0 ? '+' : '-'}${thousands(v.abs())}';
    final over = st.diff > 0;
    final String line;
    final List<Widget> actions;
    if (applied == 0) {
      line = 'Yesterday ended ${thousands(st.diff.abs())} kcal ${over ? 'over' : 'under'}. '
          '${over ? 'Take' : 'Add'} ${thousands(suggested.abs())} kcal ${over ? 'off' : 'to'} today to even it out?';
      actions = [KTextAction('Adjust today', onTap: () => _applyCarry(st.suggested))];
    } else if (applied != suggested) {
      line = suggested == 0
          ? 'Yesterday is back near target, so today\'s ${signed(applied)} kcal is no longer needed.'
          : 'Yesterday changed since you adjusted. Today is ${signed(applied)} kcal, it should now be ${signed(suggested)}.';
      actions = [
        if (suggested != 0) KTextAction('Update to ${signed(suggested)}', onTap: () => _applyCarry(st.suggested)),
        KTextAction('Undo', onTap: () => _applyCarry(null)),
      ];
    } else {
      line = 'Today includes ${signed(applied)} kcal to balance yesterday.';
      actions = [KTextAction('Undo', onTap: () => _applyCarry(null))];
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.sm, KSpacing.md),
        decoration: BoxDecoration(
          color: KColor.tint(KColor.ember, dark: 0.08, light: 0.06),
          borderRadius: KRadius.lg,
          border: Border.all(color: KColor.ember.withValues(alpha: KColor.isDark ? 0.28 : 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.cached_rounded, size: 18, color: KColor.ember),
            ),
            const SizedBox(width: KSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line, style: KText.body.copyWith(fontSize: 14, height: 1.4)),
                  const SizedBox(height: 6),
                  Wrap(spacing: KSpacing.lg, runSpacing: 4, children: actions),
                ],
              ),
            ),
            if (applied == 0)
              IconButton(
                tooltip: 'Hide for today',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: KColor.textMuted),
                onPressed: () => setState(() {
                  _carryDismissed = true;
                  _carryDismissedFor = todayKey;
                  _carryTick++;
                }),
              ),
          ],
        ),
      ),
    );
  }

  // ── Fuel hero (today's progress) ─────────────────────────────────────────────

  Widget _buildFuelHero() {
    final isToday = dateKey(_selectedDate) == dateKey(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.lg, KSpacing.p, 0),
      // The rings fly into the day screen. Only from the visible tab: the
      // shell keeps this tab mounted offstage while others show.
      child: ValueListenableBuilder<int>(
        valueListenable: AppShell.currentTab,
        builder: (context, tab, child) => HeroMode(enabled: tab == 0, child: child!),
        child: FuelLabel(
          heroTag: FuelLabel.heroTagFor(_selectedDate),
          title: isToday
              ? 'Today\'s fuel'
              : 'Fuel on ${_kMonthShort[_selectedDate.month - 1]} ${_selectedDate.day}',
          trailing: Text(
            _targetCalories > 0
                ? '${(_consumedCalories / _targetCalories * 100).round()}% eaten'
                : '',
            style: KText.caption.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          consumedCal: _consumedCalories,
          targetCal:   _targetCalories,
          consumedPro: _consumedProtein,
          targetPro:   _targetProtein,
        ),
      ),
    );
  }

  // ── Nutrition details ─────────────────────────────────────────────────────────

  Widget _buildNutritionDetails() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, 0, KSpacing.p, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DailyNutritionQualityCard(
            log: _selectedLog,
            targetCal: _targetCalories,
            targetPro: _targetProtein,
          ),
          const SizedBox(height: KSpacing.md),
          AdditionalMacrosCard(
            log: _selectedLog,
            targetCal: _targetCalories,
            targetPro: _targetProtein,
            targetFiber: _targetFiber,
          ),
        ],
      ),
    );
  }

  // ── Targets ───────────────────────────────────────────────────────────────────

  Widget _buildTargets({bool inset = true}) {
    final plan = _weeklyPlan;
    final stepOffset = plan.effectiveStepsPerDay != null
        ? _stepOffsetLabel(plan.effectiveStepsPerDay!, _profile)
        : null;

    return Padding(
      padding: inset ? const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0) : EdgeInsets.zero,
      child: Column(
        children: [
          _TargetRow(
            label:    'Maintenance, ${plan.healthConnectActive ? 'from Health Connect' : 'from your profile'}',
            value:    '${thousands(plan.maintenanceCalories)} kcal a day',
            subtitle: stepOffset,
          ),
          const KHairline(),
          _TargetRow(
            label:    'Goal: ${_profile.goal}',
            value:    '${thousands(plan.avgDailyCalories)} kcal a day on average',
            subtitle: 'Train days ${thousands(plan.trainingDayCalories)}, rest days ${thousands(plan.restDayCalories)}',
            dot:      KColor.ember,
          ),
          const KHairline(),
          _TargetRow(
            label:    'Protein',
            value:    '${plan.avgDailyProtein.round()} g a day on average',
            subtitle: 'Train days ${plan.trainingDayProtein.round()} g, rest days ${plan.restDayProtein.round()} g',
            dot:      KColor.protein,
          ),
          const KHairline(),
        ],
      ),
    );
  }

  /// Produces a human-readable step-correction note using the dynamic engine formula.
  static String _stepOffsetLabel(int steps, UserProfile profile) {
    const baseline = 7000.0;
    const strideKm = 0.00075;
    const metFactor = 0.55;
    final kcalPerStep = profile.weight * strideKm * metFactor;
    final offset = ((steps - baseline) * kcalPerStep).clamp(-400.0, 400.0).round();

    if (offset == 0) {
      return 'Your step history matches the baseline.';
    } else if (offset > 0) {
      return 'Your steps add $offset kcal.';
    } else {
      return 'Your steps take off ${offset.abs()} kcal.';
    }
  }

  // ── Streak ────────────────────────────────────────────────────────────────────

  /// Counts consecutive logged days going backwards from today.
  /// Grace-period rule: if today has no entries yet (user hasn't logged)
  /// we start from yesterday — the streak is "continuing" until midnight.
  int _computeStreak() {
    final today = DateTime.now();
    final todayLog = dayLogStore[dateKey(today)];
    final todayEmpty = todayLog == null || todayLog.isEmpty;

    int streak = 0;
    for (int i = (todayEmpty ? 1 : 0); i < 365; i++) {
      final day = today.subtract(Duration(days: i));
      final log = dayLogStore[dateKey(day)];
      if (log == null || log.isEmpty) break;
      streak++;
    }
    return streak;
  }

  // ── Section title ─────────────────────────────────────────────────────────────

}

// ─── Display totals ───────────────────────────────────────────────────────────
// What the screen adds up is exactly what the rows show: every meal row prints
// its rounded kcal, and every total is the sum of those printed numbers.

int displayKcal(DayLog log) =>
    log.allEntries.fold<int>(0, (s, e) => s + e.calMid.round());

int displayProtein(DayLog log) =>
    log.allEntries.fold<int>(0, (s, e) => s + e.result.protein.mid.round());

// ─── Fuel label ───────────────────────────────────────────────────────────────
// The day as two concentric rings on a jewel card: calories outside, protein
// inside, and what's left of the day's calories in the middle. Under the rings,
// one line each for calories and protein. The title row and any footer sit on
// the page just outside the card. Shared by the dashboard and the day screen.

class FuelLabel extends StatelessWidget {
  const FuelLabel({
    super.key,
    required this.title,
    required this.consumedCal,
    required this.targetCal,
    required this.consumedPro,
    required this.targetPro,
    this.trailing,
    this.footer,
    this.heroTag,
    this.sweepIn = true,
  });

  /// The Hero tag that carries a day's rings from the dashboard into the
  /// day screen.
  static String heroTagFor(DateTime day) => 'fuel-rings-${dateKey(day)}';

  final String title;
  final int consumedCal;
  final double targetCal;
  final int consumedPro;
  final double targetPro;

  /// Right of the title: a date, or an "Edit target" action.
  final Widget? trailing;

  /// Below the card (a day status line, an empty-day nudge).
  final Widget? footer;

  /// Wraps the rings in a Hero with this tag (see [heroTagFor]).
  final Object? heroTag;

  /// Sweep the rings up from empty on first show. Off where the rings
  /// arrive by Hero, already drawn.
  final bool sweepIn;

  @override
  Widget build(BuildContext context) {
    // Integer maths on the printed numbers, so "eaten + left = target" always
    // holds on screen.
    final tCal = targetCal.round();
    final tPro = targetPro.round();
    final hasCal = tCal > 0;
    final hasPro = tPro > 0;
    final calOver = hasCal && consumedCal > tCal;
    final calLeft = hasCal ? (tCal - consumedCal).abs() : 0;
    final proHit = hasPro && consumedPro >= tPro;
    final proLeft = (tPro - consumedPro).abs();
    final calRatio = hasCal ? consumedCal / tCal : 0.0;
    final proRatio = hasPro ? consumedPro / tPro : 0.0;

    final summary = hasCal
        ? 'Calories ${thousands(consumedCal)} of ${thousands(tCal)} kcal, '
            '${calOver ? '${thousands(calLeft)} kcal over' : '${thousands(calLeft)} kcal left'}. '
            'Protein $consumedPro of $tPro grams, '
            '${proHit ? 'target hit' : '$proLeft grams left'}.'
        : 'Calories ${thousands(consumedCal)} kcal. Protein $consumedPro grams.';

    final centre = KText.numDisplay.copyWith(
      fontSize: 48,
      fontWeight: FontWeight.w600,
      letterSpacing: -2.0,
      height: 1.0,
      color: calOver ? KColor.ember : KColor.textPrimary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: KSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: KText.h3.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        KHeroSurface(
          tone: KTone.fuel,
          padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.xl, KSpacing.xl, KSpacing.lg),
          child: Semantics(
            container: true,
            label: summary,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: _maybeHero(KDabbaRings(
                      size: 220,
                      stroke: 16,
                      sweepIn: sweepIn,
                      rings: [
                        KRingSpec(calRatio, calOver ? KRingColors.over : KRingColors.calories),
                        KRingSpec(proRatio, KRingColors.protein),
                      ],
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Rolls like an odometer when a meal changes it;
                          // a plain rebuild with the same number stays still.
                          ConstrainedBox(
                            // Inside the inner ring.
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: KRollingNumber.int(
                              hasCal ? calLeft : consumedCal,
                              style: centre,
                              alignment: Alignment.center,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            !hasCal ? 'kcal eaten' : (calOver ? 'kcal over' : 'kcal left'),
                            style: KText.caption.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: KHeroInk.secondary,
                            ),
                          ),
                        ],
                      ),
                    )),
                  ),
                  const SizedBox(height: KSpacing.xl),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _RingLegend(
                          color: (calOver ? KRingColors.over : KRingColors.calories).first,
                          label: 'Calories',
                          value: thousands(consumedCal),
                          of: hasCal ? '/ ${thousands(tCal)} kcal' : 'kcal',
                        ),
                      ),
                      const SizedBox(width: KSpacing.lg),
                      Expanded(
                        child: _RingLegend(
                          color: KRingColors.protein.first,
                          label: proHit ? 'Protein, hit' : (hasPro ? 'Protein, $proLeft g left' : 'Protein'),
                          value: '$consumedPro',
                          of: hasPro ? '/ $tPro g' : 'g',
                        ),
                      ),
                    ],
                  ),
                  if (calOver) ...[
                    const SizedBox(height: KSpacing.md),
                    Text(
                      'No stress, tomorrow\'s a fresh page.',
                      style: KText.caption.copyWith(fontSize: 13, color: KHeroInk.secondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: KSpacing.md),
          footer!,
        ],
      ],
    );
  }

  Widget _maybeHero(KDabbaRings rings) {
    final tag = heroTag;
    if (tag == null) return rings;
    return Hero(tag: tag, flightShuttleBuilder: KDabbaRings.heroShuttle, child: rings);
  }
}

class _RingLegend extends StatelessWidget {
  const _RingLegend({required this.color, required this.label, required this.value, required this.of});
  final Color color;
  final String label;
  final String value;
  final String of;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KText.caption.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: KHeroInk.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                KRollingNumber(
                  value,
                  style: KText.numMedium.copyWith(fontSize: 22, fontWeight: FontWeight.w800, color: KHeroInk.primary),
                  alignment: AlignmentDirectional.centerStart,
                ),
                Text(' $of', maxLines: 1, style: KText.caption.copyWith(fontSize: 13, color: KHeroInk.muted)),
              ],
            ),
          ),
        ],
      );
}

// ─── Calendar sub-widgets ─────────────────────────────────────────────────────

const _kWeekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

enum _DayMark { none, logged, completed }

/// Calendar marker lookup, computed on first use per day and memoised for
/// one build. Totalling a day re-derives every meal's nutrition, so only the
/// visible days are ever resolved.
class _DayMarks {
  _DayMarks(this.avgTarget);
  final double avgTarget;
  final Map<String, _DayMark> _cache = {};

  _DayMark of(String dk) => _cache[dk] ??= () {
        final log = dayLogStore[dk];
        if (log == null || log.isEmpty) return _DayMark.none;
        final cal = log.totalCaloriesMid;
        if (cal >= avgTarget * 0.88) return _DayMark.completed;
        if (cal > 0) return _DayMark.logged;
        return _DayMark.none;
      }();
}

class _CalendarHeader extends StatelessWidget {
  final DateTime month;
  final bool expanded;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggle;

  const _CalendarHeader({
    required this.month,
    required this.expanded,
    required this.onPrev,
    required this.onNext,
    required this.onToggle,
  });

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: KSpacing.sm),
        Expanded(
          child: AnimatedSwitcher(
            duration: KMotion.of(context, KMotion.quick),
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: Text(
              '${_months[month.month - 1]} ${month.year}',
              key: ValueKey(month),
              style: KText.h3.copyWith(fontSize: 14, color: KColor.textSecondary),
            ),
          ),
        ),
        _CalendarIconButton(
          icon: KIcons.prev,
          label: expanded ? 'Previous month' : 'Previous week',
          onTap: onPrev,
        ),
        _CalendarIconButton(
          icon: KIcons.next,
          label: expanded ? 'Next month' : 'Next week',
          onTap: onNext,
        ),
        _CalendarIconButton(
          icon: expanded ? Icons.unfold_less : KIcons.calendar,
          label: expanded ? 'Collapse calendar' : 'Expand calendar',
          onTap: onToggle,
          highlighted: expanded,
        ),
      ],
    );
  }
}

class _CalendarIconButton extends StatelessWidget {
  const _CalendarIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      scale: 0.9,
      borderRadius: KRadius.pill,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: AnimatedContainer(
            duration: KMotion.of(context, KMotion.quick),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted ? KColor.ink : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: highlighted ? KColor.onInk : KColor.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          for (final d in _kWeekdayLetters)
            Expanded(
              child: Center(
                child: Text(
                  d,
                  style: KText.label.copyWith(fontSize: 12, letterSpacing: 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final DateTime weekStart;
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;
  final _DayMarks marks;

  const _WeekStrip({
    required this.weekStart,
    required this.focusedMonth,
    required this.selectedDate,
    required this.onSelect,
    required this.marks,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Row(
          children: List.generate(7, (i) {
            final date = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
            final dk = dateKey(date);
            return Expanded(
              child: _DayCell(
                date:        date,
                isToday:     DateUtils.isSameDay(date, today),
                isSelected:  DateUtils.isSameDay(date, selectedDate),
                isCompleted: marks.of(dk) == _DayMark.completed,
                isLogged:    marks.of(dk) == _DayMark.logged,
                hasGym:      dayLogStore[dk]?.gymDay?.didGym == true,
                dimmed:      date.month != focusedMonth.month,
                height:      44,
                onTap:       () => onSelect(date),
              ),
            );
          }),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;
  final _DayMarks marks;

  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onSelect,
    required this.marks,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final startOffset = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        const _WeekdayRow(),
        const SizedBox(height: 6),
        for (int row = 0; row < rows; row++)
          Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final dayNum = cellIndex - startOffset + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const Expanded(child: SizedBox(height: 40));
              }
              final date = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
              final dk   = dateKey(date);

              return Expanded(
                child: _DayCell(
                  date:        date,
                  isToday:     DateUtils.isSameDay(date, today),
                  isSelected:  DateUtils.isSameDay(date, selectedDate),
                  isCompleted: marks.of(dk) == _DayMark.completed,
                  isLogged:    marks.of(dk) == _DayMark.logged,
                  hasGym:      dayLogStore[dk]?.gymDay?.didGym == true,
                  onTap:       () => onSelect(date),
                ),
              );
            }),
          ),
      ],
    );
  }
}

/// One calendar day. State is carried by fill/border AND by dots AND by the
/// spoken label, never by colour alone.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.isCompleted,
    required this.isLogged,
    required this.hasGym,
    required this.onTap,
    this.dimmed = false,
    this.height = 36,
  });

  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final bool isCompleted;
  final bool isLogged;
  final bool hasGym;
  final bool dimmed;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    final Color textColor;
    if (isSelected) {
      textColor = KColor.onInk;
    } else if (isToday || isCompleted) {
      textColor = KColor.textPrimary;
    } else if (dimmed) {
      textColor = KColor.textDisabled;
    } else {
      textColor = KColor.textSecondary;
    }

    final status = [
      if (isToday) 'today',
      if (isCompleted) 'target met' else if (isLogged) 'logged',
      if (hasGym) 'gym day',
    ];
    final label = '${_kMonthShort[date.month - 1]} ${date.day}'
        '${status.isEmpty ? '' : ', ${status.join(', ')}'}';

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: KMotion.of(context, KMotion.quick),
          curve: KMotion.emphasizedCurve,
          height: height,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            // Selected = a solid ink chip. Target met keeps a faint ink wash
            // (shape, not just the dot); today gets an ink outline.
            color: isSelected
                ? KColor.ink
                : isCompleted
                    ? KColor.green.withValues(alpha: dark ? 0.12 : 0.1)
                    : Colors.transparent,
            borderRadius: KRadius.sm,
            border: isToday && !isSelected
                ? Border.all(color: KColor.ink.withValues(alpha: dark ? 0.7 : 0.8), width: 1.4)
                : Border.all(color: Colors.transparent, width: 1.4),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${date.day}',
                style: KText.numSmall.copyWith(
                  fontSize: 14,
                  fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
              Positioned(
                bottom: 3,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCompleted)
                      _Dot(color: KColor.ink, ring: isSelected)
                    else if (isLogged)
                      _Dot(color: KColor.textMuted, ring: isSelected),
                    if (hasGym) _Dot(color: KColor.ember, ring: isSelected),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.ring = false});
  final Color color;

  /// On the ink-filled selected day the dot keeps its colour and gets a thin
  /// onInk rim so it still reads against the ink.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ring ? 6 : 4,
      height: ring ? 6 : 4,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: ring ? Border.all(color: KColor.onInk, width: 1) : null,
      ),
    );
  }
}

// ─── Shared small pieces ──────────────────────────────────────────────────────

/// Rounded icon tile tinted with a world's gradient.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.colors});

  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        child: KIcon(icon, size: KIcons.lg, color: colors.first),
      );
}

// ─── Target row ───────────────────────────────────────────────────────────────

class _TargetRow extends StatelessWidget {
  final String  label;
  final String  value;
  final String? subtitle;   // optional step-correction line
  final Color?  dot;

  const _TargetRow({
    required this.label,
    required this.value,
    this.subtitle,
    this.dot,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (dot != null) ...[
                KDot(color: dot, size: 7),
                const SizedBox(width: 7),
              ],
              Flexible(child: Text(label, style: KText.caption.copyWith(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 3),
          Text(value, style: KText.numSmall.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: KText.caption.copyWith(
                fontSize: 13,
                color: KColor.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Avatar badge ─────────────────────────────────────────────────────────────

// ─── Reusable primitives ──────────────────────────────────────────────────────

// ─── Activity Sync Card ───────────────────────────────────────────────────────

class _ActivitySyncCard extends StatelessWidget {
  final bool              available;
  final bool              syncing;
  final HealthSyncResult? syncResult;
  final UserProfile       profile;
  final VoidCallback      onConnect;
  final VoidCallback      onSync;

  const _ActivitySyncCard({
    required this.available,
    required this.syncing,
    required this.syncResult,
    required this.profile,
    required this.onConnect,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.standard),
        switchInCurve: KMotion.decelerate,
        switchOutCurve: KMotion.accelerate,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: syncing
            ? const KCardShimmer(key: ValueKey('sync-loading'), height: 110)
            : _stateKey() == 'error'
            ? KErrorCard(
                key: const ValueKey('sync-error'),
                title: "Couldn't sync your steps",
                message: "Health Connect didn't answer this time. Give it another go.",
                onRetry: onSync,
              )
            : KCard(
                key: ValueKey('sync-${_stateKey()}'),
                padding: const EdgeInsets.all(18),
                border: available
                    ? null
                    : Border.all(color: KColor.warning.withValues(alpha: 0.3)),
                child: _buildBody(),
              ),
      ),
    );
  }

  String _stateKey() {
    if (!available) return 'unavailable';
    if (syncResult?.hasError == true) return 'error';
    if (syncResult == null || !profile.healthSyncEnabled) return 'disconnected';
    return 'connected';
  }

  Widget _buildBody() {
    // ── HC not installed ──────────────────────────────────────────────────────
    if (!available) {
      return Row(
        children: [
          _IconTile(icon: Icons.warning_amber_rounded, colors: [KColor.warning, KColor.warning]),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Health Connect unavailable', style: KText.h3),
                const SizedBox(height: 3),
                Text(
                  'Install Health Connect from the Play Store to sync your steps.',
                  style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── Error state ───────────────────────────────────────────────────────────
    if (syncResult?.hasError == true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SyncHeader(connected: false),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.warning_amber_rounded, size: 14, color: KColor.warning),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  syncResult!.error!,
                  style: KText.caption.copyWith(fontSize: 13, color: KColor.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          _ActionButton(label: 'Try again', icon: Icons.refresh_rounded, onTap: onSync),
        ],
      );
    }

    // ── Not yet connected ─────────────────────────────────────────────────────
    if (syncResult == null || !profile.healthSyncEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(icon: Icons.directions_walk_rounded, colors: [KColor.textSecondary]),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activity sync', style: KText.h3),
                    const SizedBox(height: 2),
                    Text(
                      'Your real steps make your maintenance calories sharper.',
                      style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ActionButton(
              label: 'Connect Health Connect',
              filled: true,
              icon: Icons.favorite_rounded,
              onTap: onConnect),
        ],
      );
    }

    // ── Connected & synced ────────────────────────────────────────────────────
    final r = syncResult!;
    final syncTime = profile.lastHealthSyncAt != null
        ? '${profile.lastHealthSyncAt!.hour.toString().padLeft(2, '0')}:'
          '${profile.lastHealthSyncAt!.minute.toString().padLeft(2, '0')}'
        : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SyncHeader(connected: true)),
            const SizedBox(width: KSpacing.sm),
            Text(
              'Last sync $syncTime',
              style: KText.caption.copyWith(
                fontSize: 12.5,
                color: KColor.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: KSpacing.md),

        // Step stats grid
        Row(
          children: [
            _StepStat(
              label:  'Last 14 full days',
              value:  r.averageDailySteps14d != null
                  ? '${thousands(r.averageDailySteps14d!)} steps'
                  : 'No data',
            ),
            const SizedBox(width: KSpacing.md),
            _StepStat(
              label:  'Last 30 full days',
              value:  r.averageDailySteps30d != null
                  ? '${thousands(r.averageDailySteps30d!)} steps'
                  : 'No data',
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Effective + tier
        Container(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.035),
            borderRadius: KRadius.sm,
          ),
          child: Row(
            children: [
              KIcon(Icons.directions_walk_outlined, size: KIcons.lg, color: KColor.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.effectiveAverageSteps != null
                          ? '${thousands(r.effectiveAverageSteps!)} steps a day go into your targets'
                          : 'No step data available',
                      style: KText.numSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.activityTier.displayName}. '
                      'Calorie offset ${_signedStepOffset(r)} kcal',
                      style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KSpacing.md),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.check_circle_rounded, size: 13, color: KColor.green),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Maintenance is adjusted from Health Connect',
                style: KText.caption.copyWith(
                  fontSize: 13,
                  color: KColor.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _ActionButton(label: 'Sync now', icon: Icons.sync_rounded, onTap: onSync),
        ),
      ],
    );
  }
}

class _SyncHeader extends StatelessWidget {
  final bool connected;
  const _SyncHeader({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          connected
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          size: 16,
          color: connected ? KColor.green : KColor.textDisabled,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Health Connect',
            style: KText.h3.copyWith(
              fontSize: 14,
              color: connected ? KColor.textPrimary : KColor.textSecondary,
            ),
          ),
        ),
        if (connected) ...[
          const SizedBox(width: KSpacing.sm),
          const KGlowDot(size: 6),
        ],
      ],
    );
  }
}

class _StepStat extends StatelessWidget {
  final String label;
  final String value;
  const _StepStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.035),
          borderRadius: KRadius.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
            const SizedBox(height: 3),
            Text(value, style: KText.numSmall),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final bool         filled;
  final IconData?    icon;
  const _ActionButton(
      {required this.label, required this.onTap, this.filled = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final fg = filled ? KColor.onInk : KColor.textPrimary;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: () {
          KHaptics.commit();
          onTap();
        },
        borderRadius: KRadius.pill,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.sm),
          decoration: BoxDecoration(
            gradient: filled
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: KGradient.primary,
                  )
                : null,
            borderRadius: KRadius.pill,
            border: filled
                ? null
                : Border.all(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.18 : 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
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
    );
  }
}

// ─── Workout card ─────────────────────────────────────────────────────────────

// ─── Weight Summary Chip ─────────────────────────────────────────────────────
//
// Compact single-line pill above the full trend chart.
// Shows: current weight   ·   7d delta
// Only rendered when weightContext is non-null (controlled by caller).

// ─── Weight trend card ────────────────────────────────────────────────────────
// The smoothed trend as one calm line, the scale readings as small dots under
// it, and the number that matters: where the trend is and how fast it moves.

class _WeightTrendCard extends StatefulWidget {
  const _WeightTrendCard({
    super.key,
    required this.healthReadings,
    required this.onLogWeight,
  });

  /// Health Connect weigh-ins; manual ones come from [BodyMetricsService].
  final List<WeightReading> healthReadings;
  final VoidCallback onLogWeight;

  @override
  State<_WeightTrendCard> createState() => _WeightTrendCardState();
}

class _WeightTrendCardState extends State<_WeightTrendCard> {
  int _days = 30;

  /// The weigh-in being inspected (tap or drag on the chart), or null.
  int? _selected;

  static String _day(DateTime d) => '${d.day} ${_kMonthShort[d.month - 1]}';

  void _pick(List<WeightPoint> pts, double dx, double width) {
    if (pts.isEmpty || width <= 0) return;
    final t0 = pts.first.day.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, pts.last.day.millisecondsSinceEpoch - t0);
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final x = (pts[i].day.millisecondsSinceEpoch - t0) / span * width;
      final d = (x - dx).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    if (best != _selected) {
      KHaptics.select();
      setState(() => _selected = best);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trend = BodyMetricsService.instance.trend(days: _days, external: widget.healthReadings);
    final pts = trend.points;
    final sel = (_selected != null && _selected! < pts.length) ? pts[_selected!] : null;
    final latest = trend.latest;
    final rate = trend.weeklyRateKg;
    String sub;
    if (sel != null) {
      sub = '${_day(sel.day)}${sel.manual ? ', logged in Kynetix' : ', Health Connect'}. Trend ${sel.trendKg.toStringAsFixed(1)} kg';
    } else if (rate == null) {
      sub = 'A few more weigh-ins to show a rate';
    } else if (rate.abs() < 0.05) {
      sub = 'Holding steady';
    } else {
      sub = '${rate > 0 ? 'Up' : 'Down'} ${rate.abs().toStringAsFixed(2)} kg a week';
    }
    final headline = sel?.scaleKg ?? latest?.trendKg;
    return KCard(
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.lg, KSpacing.lg, KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sel != null ? 'Weigh-in' : 'Weight trend',
                  style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textSecondary),
                ),
              ),
              _RangeToggle(
                value: _days,
                onChanged: (d) => setState(() {
                  _days = d;
                  _selected = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: headline == null ? '-' : headline.toStringAsFixed(1),
                          style: KText.numDisplay.copyWith(fontSize: 34),
                        ),
                        TextSpan(text: ' kg', style: KText.caption.copyWith(fontSize: 14, color: KColor.textMuted)),
                      ]),
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textMuted)),
                  ],
                ),
              ),
              KTextAction('Log', onTap: widget.onLogWeight),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          SizedBox(
            height: 140,
            child: pts.length < 2
                ? Center(
                    child: Text(
                      'Two weigh-ins draw the line.',
                      style: KText.caption.copyWith(color: KColor.textMuted),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) => Semantics(
                      label: 'Weight chart, ${pts.length} weigh-ins. '
                          'Tap a point to read it.',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) {
                          // Tapping the point that is already open closes it.
                          final before = _selected;
                          _pick(pts, d.localPosition.dx, box.maxWidth);
                          if (before != null && before == _selected) setState(() => _selected = null);
                        },
                        onHorizontalDragStart: (d) => _pick(pts, d.localPosition.dx, box.maxWidth),
                        onHorizontalDragUpdate: (d) => _pick(pts, d.localPosition.dx, box.maxWidth),
                        child: CustomPaint(
                          size: Size(box.maxWidth, box.maxHeight),
                          painter: _WeightLinePainter(
                            points: pts,
                            selected: _selected,
                            line: KColor.textPrimary,
                            dot: KColor.textMuted,
                            grid: KColor.divider,
                            accent: KColor.ember,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          if (pts.length >= 2) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(_day(pts.first.day), style: KText.caption.copyWith(fontSize: 11.5, color: KColor.textMuted)),
                const Spacer(),
                Text(
                  sel == null ? 'Tap the chart to read a day' : 'Tap again to close',
                  style: KText.caption.copyWith(fontSize: 11.5, color: KColor.textMuted),
                ),
                const Spacer(),
                Text(_day(pts.last.day), style: KText.caption.copyWith(fontSize: 11.5, color: KColor.textMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget opt(int d, String label) {
      final on = d == value;
      return Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            KHaptics.select();
            onChanged(d);
          },
          child: AnimatedContainer(
            duration: KMotion.of(context, KMotion.quick),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? KColor.ink : Colors.transparent,
              borderRadius: KRadius.pill,
            ),
            child: Text(
              label,
              style: KText.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? KColor.onInk : KColor.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: KColor.cardHigh, borderRadius: KRadius.pill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [opt(30, '30 days'), opt(90, '90 days')]),
    );
  }
}

class _WeightLinePainter extends CustomPainter {
  _WeightLinePainter({
    required this.points,
    required this.line,
    required this.dot,
    required this.grid,
    required this.accent,
    this.selected,
  });
  final List<WeightPoint> points;
  final int? selected;
  final Color line;
  final Color dot;
  final Color grid;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final p in points) {
      lo = math.min(lo, math.min(p.scaleKg, p.trendKg));
      hi = math.max(hi, math.max(p.scaleKg, p.trendKg));
    }
    if (hi - lo < 1) {
      final mid = (hi + lo) / 2;
      lo = mid - 0.5;
      hi = mid + 0.5;
    }
    final t0 = points.first.day.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.day.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, t1 - t0);
    const padTop = 30.0; // room for the reading above a selected point
    const padBottom = 8.0;
    Offset at(DateTime d, double kg) => Offset(
          (d.millisecondsSinceEpoch - t0) / span * size.width,
          padTop + (1 - (kg - lo) / (hi - lo)) * (size.height - padTop - padBottom),
        );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = padTop + i * (size.height - padTop - padBottom) / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final sel = selected != null && selected! < points.length ? points[selected!] : null;
    if (sel != null) {
      final x = at(sel.day, sel.scaleKg).dx;
      canvas.drawLine(
        Offset(x, padTop - 4),
        Offset(x, size.height),
        Paint()
          ..color = line.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
    }

    final dotPaint = Paint()..color = dot.withValues(alpha: 0.75);
    for (final p in points) {
      canvas.drawCircle(at(p.day, p.scaleKg), 2.6, dotPaint);
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = at(points[i].day, points[i].trendKg);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = line,
    );

    if (sel == null) {
      canvas.drawCircle(at(points.last.day, points.last.trendKg), 4.5, Paint()..color = line);
      return;
    }

    // The selected weigh-in: a ringed dot and its reading in a small label.
    final o = at(sel.day, sel.scaleKg);
    canvas.drawCircle(o, 7, Paint()..color = accent.withValues(alpha: 0.22));
    canvas.drawCircle(o, 4.5, Paint()..color = accent);
    final tp = TextPainter(
      text: TextSpan(
        text: '${sel.scaleKg.toStringAsFixed(1)} kg',
        style: TextStyle(
          fontFamily: KText.displayFace,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: KColor.onInk,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 8.0;
    const padY = 4.0;
    final w = tp.width + padX * 2;
    final h = tp.height + padY * 2;
    final left = (o.dx - w / 2).clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, w, h), const Radius.circular(8));
    canvas.drawRRect(rect, Paint()..color = KColor.ink);
    tp.paint(canvas, Offset(left + padX, padY));
  }

  @override
  bool shouldRepaint(_WeightLinePainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.line != line ||
      old.dot != dot ||
      old.grid != grid ||
      old.accent != accent;
}

// ─── Shared nutrition sections (also used by DayDetailScreen) ─────────────────
// Editorial sections, not cards: a heading, the number, a few plain lines,
// then a hairline.

/// Notes on the day so far, in Kynetix's voice. Never praises a day that has
/// barely started, and never contradicts the fuel label above it.
List<String> nutritionQualityNotes(DayLog log, {
  required double targetCal,
  required double targetPro,
  double targetFib = 30,
}) {
  if (log.isEmpty) return const [];
  final cal = displayKcal(log);
  final pro = displayProtein(log);
  final fib = log.totalFiberMid;
  final calPct = targetCal > 0 ? cal / targetCal * 100 : 0.0;
  final proPct = targetPro > 0 ? pro / targetPro * 100 : 0.0;
  final fibPct = targetFib > 0 ? fib / targetFib * 100 : 0.0;
  final early = calPct < 50;
  final score = log.dailyNutritionScore;
  final notes = <String>[];

  if (calPct > 105) {
    notes.add('You\'re ${thousands(cal - targetCal)} kcal over. No stress, tomorrow\'s a fresh page.');
  } else if (calPct >= 90) {
    notes.add('Calories are right where they should be.');
  }

  if (proPct >= 90) {
    notes.add('Protein\'s covered.');
  } else if (!early && proPct < 70) {
    notes.add('Protein is behind. Dal, paneer, curd or a scoop of whey will close it.');
  }

  if (!early && fibPct < 60) {
    notes.add('Fiber is light. Fruit, sabzi or oats help.');
  } else if (fibPct >= 90) {
    notes.add('Fiber\'s on point.');
  }

  if (score != null) {
    if (score < 60) {
      notes.add('Make the next meal more whole food: dal, sabzi, curd.');
    } else if (score >= 80 && !early) {
      notes.add('What you\'ve eaten is mostly whole food. Keep it that way.');
    }
  }

  if (notes.isEmpty && early) {
    notes.add('Early in the day. Scores settle as you log more.');
  }
  return notes;
}

class DailyNutritionQualityCard extends StatelessWidget {
  final DayLog log;
  final double targetCal;
  final double targetPro;

  const DailyNutritionQualityCard({
    super.key,
    required this.log,
    required this.targetCal,
    required this.targetPro,
  });

  @override
  Widget build(BuildContext context) {
    if (log.isEmpty) return const SizedBox.shrink();

    final score = log.dailyNutritionScore;
    final notes = nutritionQualityNotes(log, targetCal: targetCal, targetPro: targetPro);
    final (Color scoreColor, String verdict) = score == null
        ? (KColor.textSecondary, 'Not scored yet')
        : score >= 80
            ? (KColor.ink, 'Good')
            : score >= 60
                ? (KColor.textSecondary, 'Fair')
                : (KColor.ember, 'Could be cleaner');

    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Food quality', style: KText.h3.copyWith(fontSize: 16)),
                ),
              ),
              if (score != null) ...[
                Text(
                  verdict,
                  style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                ),
                const SizedBox(width: KSpacing.sm),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '$score',
                      style: KText.numMedium.copyWith(fontSize: 22, color: scoreColor),
                    ),
                    TextSpan(
                      text: '/100',
                      style: KText.numSmall.copyWith(fontSize: 13, color: KColor.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ]),
                  semanticsLabel: '$score out of 100',
                ),
              ],
            ],
          ),
          if (score != null) ...[
            const SizedBox(height: KSpacing.sm),
            KBar(
              progress: score / 100,
              height: 3,
              colors: [scoreColor, scoreColor],
            ),
          ],
          const SizedBox(height: KSpacing.md),
          ...notes.map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: KSpacing.sm),
                      child: KDot(size: 4),
                    ),
                    Expanded(
                      child: Text(note, style: KText.body.copyWith(fontSize: 14.5, color: KColor.textSecondary, height: 1.45)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: KSpacing.md),
          const KHairline(),
        ],
      ),
    );
  }
}

class AdditionalMacrosCard extends StatefulWidget {
  final DayLog log;
  final double targetCal;
  final double targetPro;
  final double targetFiber;

  const AdditionalMacrosCard({
    super.key,
    required this.log,
    required this.targetCal,
    required this.targetPro,
    required this.targetFiber,
  });

  @override
  State<AdditionalMacrosCard> createState() => _AdditionalMacrosCardState();
}

class _AdditionalMacrosCardState extends State<AdditionalMacrosCard> {
  bool _expanded = false;

  void _toggle() {
    KHaptics.select();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.log.isEmpty) return const SizedBox.shrink();

    // Standardized Targets
    final targetFiber = widget.targetFiber;
    final split = NutritionTargetEngine.instance.macroSplit(widget.targetCal, widget.targetPro);
    final targetFat = split.fat;
    final targetCarbs = split.carbs;

    // Consumed Midpoints
    final consumedFiber = widget.log.totalFiberMid;
    final consumedCarbs = widget.log.totalCarbsMid;
    final consumedFat = widget.log.totalFatMid;

    final consumedSugar = widget.log.totalSugarMid;
    final consumedSatFat = widget.log.totalSaturatedFatMid;
    final consumedSodium = widget.log.totalSodiumMid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Carbs, fat and fiber', style: KText.h3.copyWith(fontSize: 16)),
                  ),
                  if (!_expanded)
                    Padding(
                      padding: const EdgeInsets.only(right: KSpacing.sm),
                      child: Text(
                        '${amount(consumedCarbs.roundToDouble())} g carbs',
                        style: KText.caption.copyWith(fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: KMotion.of(context, KMotion.standard),
                    curve: KMotion.emphasizedCurve,
                    child: KIcon(Icons.expand_more, size: KIcons.md),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.emphasizedCurve,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: KSpacing.lg),
                  child: Column(
                    children: [
                      _buildMacroRow(
                        label: 'Fiber',
                        consumed: consumedFiber,
                        target: targetFiber,
                        unit: 'g',
                        colors: [KColor.fiber],
                      ),
                      const SizedBox(height: KSpacing.md),
                      _buildMacroRow(
                        label: 'Carbs',
                        consumed: consumedCarbs,
                        target: targetCarbs,
                        unit: 'g',
                        colors: [KColor.carbs],
                      ),
                      const SizedBox(height: KSpacing.md),
                      _buildMacroRow(
                        label: 'Fat',
                        consumed: consumedFat,
                        target: targetFat,
                        unit: 'g',
                        colors: [KColor.fat],
                      ),
                      if (consumedSugar > 0) ...[
                        const SizedBox(height: KSpacing.md),
                        _buildOptionalMacroRow('Sugar', consumedSugar, 'g'),
                      ],
                      if (consumedSatFat > 0) ...[
                        const SizedBox(height: KSpacing.md),
                        _buildOptionalMacroRow('Saturated fat', consumedSatFat, 'g'),
                      ],
                      if (consumedSodium > 0) ...[
                        const SizedBox(height: KSpacing.md),
                        _buildOptionalMacroRow('Sodium', consumedSodium, 'mg'),
                      ],
                    ],
                  ),
                ),
        ),
        const KHairline(),
      ],
    );
  }

  Widget _buildMacroRow({
    required String label,
    required double consumed,
    required double target,
    required String unit,
    required List<Color> colors,
  }) {
    final progressRatio = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    final isOver        = target > 0 && consumed > target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: KText.bodyMedium.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: KSpacing.sm),
            Flexible(
              flex: 2,
              child: Text(
                '${amount(consumed)} / ${target.round()} $unit${isOver ? ', a little over' : ''}',
                textAlign: TextAlign.end,
                style: KText.caption.copyWith(
                  fontSize: 13,
                  color: isOver ? KColor.ember : KColor.textSecondary,
                  fontWeight: isOver ? FontWeight.w600 : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        KBar(
          progress: progressRatio,
          height: 4,
          duration: KMotion.standard,
          colors: isOver ? [KColor.ember, KColor.ember] : colors,
        ),
      ],
    );
  }

  Widget _buildOptionalMacroRow(String label, double consumed, String unit) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: KText.caption.copyWith(fontSize: 13)),
        ),
        Text(
          '${amount(consumed)} $unit',
          style: KText.numSmall.copyWith(fontSize: 14),
        ),
      ],
    );
  }
}

/// The engine's own step adjustment for the signed-in user (same number the
/// targets use), e.g. "+84".
String _signedStepOffset(HealthSyncResult r) {
  final profile = ProfileService.instance.currentUserProfile;
  final kcal = profile == null
      ? r.stepCalorieOffsetAt65kg
      : NutritionTargetEngine.instance.stepCorrectionKcal(profile, r);
  return '${kcal >= 0 ? '+' : ''}$kcal';
}

/// A food you can log again in one tap, from the + sheet.
class _AgainPill extends StatelessWidget {
  const _AgainPill({required this.title, required this.meta, required this.onTap});
  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: KSpacing.sm),
      child: Pressable(
        onTap: onTap,
        borderRadius: KRadius.md,
        scale: 0.96,
        semanticLabel: 'Log $title again',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200, minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: KColor.tint(KColor.ember, dark: 0.07, light: 0.05),
            borderRadius: KRadius.md,
            border: Border.all(color: KColor.ember.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.bodyMedium.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(meta, maxLines: 1, style: KText.caption.copyWith(color: KColor.textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}


// ─── Bento tiles ──────────────────────────────────────────────────────────────
// One fact per tile: what it is (top), the number (bottom), one line of
// context. Colour sits only in the small icon.

class _BentoTile extends StatelessWidget {
  const _BentoTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.unit,
    this.sub,
    this.check = false,
    this.progress,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? unit;
  final String? sub;
  final bool check;
  final double? progress;
  final VoidCallback? onTap;

  static const double minHeight = 132;

  @override
  Widget build(BuildContext context) {
    final spoken = '$label. $value${unit == null ? '' : ' $unit'}.${sub == null ? '' : ' $sub.'}';
    final valueStyle = KText.numMedium.copyWith(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.9);
    final body = Container(
      constraints: const BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, 14, KSpacing.md, KSpacing.lg),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.lg,
        border: Border.all(color: KColor.hairline),
      ),
      // spaceBetween rather than a Spacer: the row measures each tile at its
      // natural height first, then stretches the shorter one.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textSecondary),
                ),
              ),
              if (check)
                Icon(Icons.check_circle_rounded, size: 16, color: KColor.green)
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 18, color: KColor.textMuted),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: KSpacing.md),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // Numbers roll when they change; words just change.
                    if (KRollingNumber.isRollable(value))
                      KRollingNumber(value, style: valueStyle, alignment: AlignmentDirectional.centerStart)
                    else
                      Text(value, maxLines: 1, style: valueStyle),
                    if (unit != null)
                      Text(
                        ' $unit',
                        maxLines: 1,
                        style: KText.caption.copyWith(fontSize: 13, color: KColor.textMuted),
                      ),
                  ],
                ),
              ),
              if (sub != null) ...[
                const SizedBox(height: 3),
                Text(
                  sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: KRadius.pill,
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: KColor.track,
                    color: accent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: spoken, child: ExcludeSemantics(child: body));
    }
    return Pressable(
      onTap: () {
        KHaptics.select();
        onTap!();
      },
      scale: 0.97,
      borderRadius: KRadius.lg,
      semanticLabel: spoken,
      child: body,
    );
  }
}

/// The fasting tile follows the fast live and opens the full timer card.
class _FastingTile extends StatefulWidget {
  const _FastingTile();

  @override
  State<_FastingTile> createState() => _FastingTileState();
}

class _FastingTileState extends State<_FastingTile> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    FastingService.instance.state.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    FastingService.instance.state.removeListener(_sync);
    _ticker?.cancel();
    super.dispose();
  }

  void _sync() {
    final running = FastingService.instance.state.value.active != null;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (mounted) setState(() {});
  }

  static String _hm(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  void _open() => showKSheet<void>(
        context: context,
        builder: (_) => const _BentoSheet(title: 'Fasting', child: FastingCard()),
      );

  @override
  Widget build(BuildContext context) {
    final st = FastingService.instance.state.value;
    final a = st.active;
    if (a == null) {
      final planned = st.scheduled;
      return _BentoTile(
        icon: Icons.timer_outlined,
        accent: KColor.ink,
        label: 'Fasting',
        value: planned != null ? 'Planned' : 'Start',
        sub: planned != null ? planned.preset.label : '16:8, a vrat or a roza',
        onTap: _open,
      );
    }
    final status = FastStatus(a, DateTime.now());
    return _BentoTile(
      icon: Icons.timer_outlined,
      accent: KColor.ink,
      label: a.preset.label,
      value: status.goalReached ? 'Done' : _hm(status.remaining),
      unit: status.goalReached ? null : 'left',
      sub: '${_hm(status.elapsed)} in',
      progress: status.progress,
      onTap: _open,
    );
  }
}

/// A sheet that hosts a full card opened from a tile.
class _BentoSheet extends StatelessWidget {
  const _BentoSheet({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, KSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(child: KDragHandle()),
            const SizedBox(height: KSpacing.md),
            Text(title, style: KText.h2),
            const SizedBox(height: KSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}


/// One meal on the dashboard: its name and totals, then what was in it.
class _MealGroupRow extends StatelessWidget {
  const _MealGroupRow({required this.section, required this.entries});
  final MealSection section;
  final List<MealEntry> entries;

  @override
  Widget build(BuildContext context) {
    final kcal = entries.fold<int>(0, (s, e) => s + e.calMid.round());
    final pro = entries.fold<int>(0, (s, e) => s + e.result.protein.mid.round());
    final what = entries
        .map((e) => (e.finalSavedInput.trim().isNotEmpty ? e.finalSavedInput : e.rawInput).trim())
        .where((t) => t.isNotEmpty)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_sentenceCaseSection(section), style: KText.h3),
                const SizedBox(height: 2),
                Text(
                  what,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: KText.caption.copyWith(fontSize: 13, color: KColor.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: KSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: thousands(kcal), style: KText.numSmall.copyWith(fontSize: 15)),
                  TextSpan(text: ' kcal', style: KText.caption.copyWith(color: KColor.textMuted)),
                ]),
              ),
              const SizedBox(height: 3),
              Text(
                '$pro g protein',
                style: KText.caption.copyWith(fontSize: 12, color: KColor.protein),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Evening Snack" reads as "Evening snack" in a list.
String _sentenceCaseSection(MealSection s) {
  final n = s.displayName;
  if (n.isEmpty) return n;
  return n[0] + n.substring(1).toLowerCase();
}
