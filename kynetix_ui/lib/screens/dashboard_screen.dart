import 'package:flutter/material.dart';
import 'dart:async' show Timer;
import 'dart:convert';
import '../config/app_theme.dart';
import '../screens/onboarding_screen.dart';
import '../screens/day_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../models/day_log.dart';
import '../models/carry_forward_record.dart';
import '../services/health_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../services/widget_service.dart';
import '../services/workout_service.dart';
import '../screens/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/insights_report_service.dart';
import '../models/insights_models.dart';
import 'insights_screen.dart';
import 'home_screen.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  static final DateTime _baseMonth = DateTime(2024, 1, 1);
  late final PageController _calendarPageController;

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
  WeightContext? get _weightContext =>
      _weightHistory != null && _weightHistory!.isNotEmpty
          ? WeightContext.fromHistory(_weightHistory!, goal: currentUserProfile?.goal)
          : null;

  @override
  void initState() {
    super.initState();
    _calendarPageController = PageController(initialPage: _monthIndex(_focusedMonth));
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
    _calendarPageController.dispose();
    super.dispose();
  }

  Future<void> _checkCalorieCarryForward() async {
    final profile = currentUserProfile;
    if (profile == null || !profile.carryForwardEnabled) return;

    final today = DateTime.now();
    final todayKey = dateKey(today);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayKey = dateKey(yesterday);

    final prefs = await SharedPreferences.getInstance();
    final resolvedListRaw = prefs.getStringList('carry_forward_resolved_dates_v1') ?? [];
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

    final ws = WorkoutService.instance;
    final yesterdaySession = ws.sessionFor(yesterday);
    final yesterdaySplit = ws.splitDayFor(yesterday);
    final yesterdayGymDay = yesterdayLog.gymDay;

    final bool isGymDay;
    if (yesterdayGymDay != null) {
      isGymDay = yesterdayGymDay.didGym || (yesterdaySession?.isEmpty == false);
    } else {
      final splitIsTraining = yesterdaySplit != null && !yesterdaySplit.isRestDay;
      isGymDay = splitIsTraining || (yesterdaySession?.isEmpty == false);
    }

    final String? workoutTypeName;
    if (yesterdaySession != null && !yesterdaySession.isEmpty && yesterdaySession.splitDayName.isNotEmpty) {
      workoutTypeName = yesterdaySession.splitDayName;
    } else if (yesterdayGymDay != null && yesterdayGymDay.workoutType != null) {
      workoutTypeName = yesterdayGymDay.workoutType!.displayName;
    } else if (yesterdayGymDay != null && yesterdayGymDay.splitDayName != null) {
      workoutTypeName = yesterdayGymDay.splitDayName;
    } else if (yesterdaySplit != null && !yesterdaySplit.isRestDay) {
      workoutTypeName = yesterdaySplit.name;
    } else {
      workoutTypeName = null;
    }

    final targetDay = NutritionTargetEngine().dayTarget(
      profile,
      isGymDay: isGymDay,
      health: _syncResult,
      session: yesterdaySession,
      workoutTypeName: workoutTypeName,
      targetCaloriesOverride: yesterdayGymDay?.targetCaloriesOverride,
      carryForwardAdjustment: null, // Zero compounding / banking protection!
      date: yesterday,
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
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          title: Row(
            children: const [
              Icon(Icons.cached_rounded, color: Color(0xFF52B788)),
              SizedBox(width: 8),
              Text(
                'Calorie Carry-Forward',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'Yesterday you ate $absDiffInt kcal $directionWord your target.\n\n'
            'Would you like to $adjWord today\'s target by $absAdjInt kcal to account for this?',
            style: const TextStyle(color: Color(0xFF9CA3AF), height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                resolvedListRaw.add(yesterdayKey);
                await prefs.setStringList('carry_forward_resolved_dates_v1', resolvedListRaw);

                final historyRaw = prefs.getStringList('carry_forward_history_v1') ?? [];
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
                await prefs.setStringList('carry_forward_history_v1', historyRaw);

                // Save inside today's gymDay so it syncs to cloud
                final todayLog = logFor(today);
                todayLog.gymDay = (todayLog.gymDay ?? const GymDay(didGym: false)).withCarryForwardRecord(record);
                await PersistenceService.saveDay(today);
              },
              child: const Text('Ignore', style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                resolvedListRaw.add(yesterdayKey);
                await prefs.setStringList('carry_forward_resolved_dates_v1', resolvedListRaw);

                final historyRaw = prefs.getStringList('carry_forward_history_v1') ?? [];
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
                await prefs.setStringList('carry_forward_history_v1', historyRaw);

                final todayLog = logFor(today);
                todayLog.carryForwardAdjustment = adjustmentAmount;
                todayLog.gymDay = (todayLog.gymDay ?? const GymDay(didGym: false)).withCarryForwardRecord(record);
                await PersistenceService.saveDay(today);

                if (mounted) {
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF52B788),
                foregroundColor: const Color(0xFF0F0F14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Adjust Today', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final results = await Future.wait([
      HealthService().sync(),
      HealthService().syncWeight(),
      HealthService().syncSleepAndHrv(),
    ]);

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

    if (!result.hasError && result.hasData) {
      currentUserProfile = currentUserProfile!.copyWithHealth(
        averageDailySteps: result.effectiveAverageSteps!.toInt(),
        lastHealthSyncAt:  result.syncedAt,
      );
      PersistenceService.saveProfile(currentUserProfile!).ignore();
    }

    setState(() {
      _syncResult    = result;
      _weightHistory = weightHistory.isNotEmpty ? weightHistory : _weightHistory;
      _syncing       = false;
    });
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

  WeeklyTargetPlan get _weeklyPlan =>
      NutritionTargetEngine().weeklyPlan(_profile, health: _syncResult);

  DayTarget? get _effectiveDayTarget {
    final ws      = WorkoutService.instance;
    final log     = _selectedLog;
    final session = ws.sessionFor(_selectedDate);
    final splitDay = ws.splitDayFor(_selectedDate);
    final gymDay  = log.gymDay;

    // isGymDay: mirrors DayDetail logic exactly.
    final bool isGymDay;
    if (gymDay != null) {
      isGymDay = gymDay.didGym || (session?.isEmpty == false);
    } else {
      final splitIsTraining = splitDay != null && !splitDay.isRestDay;
      isGymDay = splitIsTraining || (session?.isEmpty == false);
    }

    // Best available workout type name: session > user-chosen > split.
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
      _profile,
      isGymDay:               isGymDay,
      health:                 _syncResult,
      session:                session,
      workoutTypeName:        workoutTypeName,
      targetCaloriesOverride: gymDay?.targetCaloriesOverride,
      carryForwardAdjustment: log.carryForwardAdjustment,
      date:                   _selectedDate,
    );
  }

  // Live reads from the global store
  DayLog get _selectedLog      => logFor(_selectedDate);
  double get _consumedCalories => _selectedLog.totalCaloriesMid;
  double get _consumedProtein  => _selectedLog.totalProteinMid;
  double get _targetCalories   => _effectiveDayTarget?.calories ?? _weeklyPlan.avgDailyCalories;
  double get _targetProtein    => _effectiveDayTarget?.protein  ?? _weeklyPlan.avgDailyProtein;
  double get _targetFiber      => (14.0 * _targetCalories / 1000).clamp(20.0, 60.0);
  double get _remainingCalories => (_targetCalories - _consumedCalories).clamp(0, double.infinity);
  double get _remainingProtein  => (_targetProtein  - _consumedProtein ).clamp(0, double.infinity);

  void _prevMonth() {
    _calendarPageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _nextMonth() {
    _calendarPageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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
    setState(() {});   // refresh rings after returning
  }

  void _openQuickMacroEstimator() {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const HomeScreen(),
    ).then((updated) {
      if (updated == true && mounted) {
        setState(() {}); // refresh rings on return
      }
    });
  }

  void _showAddMealOptionsSheet() {
    showModalBottomSheet<void>(
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
                const Text(
                  'Add Food or Activity',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: KColor.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.restaurant_menu_rounded, color: KColor.green),
                  ),
                  title: const Text('Log Daily Food & Gym', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('View detailed day log, log meals, track water and workouts.', style: TextStyle(color: KColor.textMuted, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openDay(_selectedDate);
                  },
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
                  subtitle: const Text('Directly input macros or estimate with AI instantly.', style: TextStyle(color: KColor.textMuted, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openQuickMacroEstimator();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      floatingActionButton: _AddMealFab(onTap: _showAddMealOptionsSheet),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildCalendar()),
            SliverToBoxAdapter(child: _buildWorkoutState()),
            SliverToBoxAdapter(child: _buildSectionTitle('Today\'s Progress')),
            SliverToBoxAdapter(child: _buildDailySummary()),
            SliverToBoxAdapter(child: _buildSectionTitle('Your Targets')),
            SliverToBoxAdapter(child: _buildTargets()),
            SliverToBoxAdapter(child: _buildSectionTitle('Activity Sync')),
            SliverToBoxAdapter(
              child: _ActivitySyncCard(
                available:  _hcAvailable,
                syncing:    _syncing,
                syncResult: _syncResult,
                profile:    _profile,
                onConnect:  _doSync,
                onSync:     _doSync,
              ),
            ),
            // Weight summary chip — shown when data is available (above full chart).
            if (_weightHistory != null && _weightHistory!.isNotEmpty)
              SliverToBoxAdapter(
                child: _WeightSummaryChip(
                  weightContext: _weightContext!,
                ),
              ),
            // Weight trend card — shown below Activity Sync once data is available.
            SliverToBoxAdapter(
              child: _WeightTrendCard(
                weightHistory: _weightHistory,
                syncing: _syncing,
                onRequestPermission: _doRequestWeightPermission,
              ),
            ),
            SliverToBoxAdapter(child: _buildInsightsEntryCard()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final hour = TimeOfDay.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final emoji = _profile.gender == 'Male' ? '\u{1F4AA}' : '\u{1F31F}';
    final isToday = dateKey(_selectedDate) == dateKey(DateTime.now());
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateLabel = isToday
        ? 'Today'
        : '${months[_selectedDate.month - 1]} ${_selectedDate.day}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.xl, 28, KSpacing.xl, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, ${_profile.name} $emoji',
                  style: KText.caption,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Overview', style: KText.h1),
                    const SizedBox(width: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.3), end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KChip(
                        dateLabel,
                        key: ValueKey(dateLabel),
                        color: isToday ? KColor.green : KColor.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Pressable(
            onTap: () async {
              kHaptic();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    onProfileChanged: () => setState(() {}),
                  ),
                ),
              );
              setState(() {});
            },
            borderRadius: BorderRadius.circular(50),
            child: _AvatarBadge(profile: _profile),
          ),
        ],
      ),
    );
  }

  // ── Calendar ─────────────────────────────────────────────────────────────────

  Widget _buildCalendar() {
    final avgTarget = _weeklyPlan.avgDailyCalories;
    final completedDayKeys = <String>{};
    final loggedDayKeys    = <String>{};
    for (final entry in dayLogStore.entries) {
      final log = entry.value;
      if (log.isEmpty) continue;
      final cal = log.totalCaloriesMid;
      if (cal >= avgTarget * 0.88) {
        completedDayKeys.add(entry.key);
      } else if (cal > 0) {
        loggedDayKeys.add(entry.key);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: _Card(
        child: Column(
          children: [
            _CalendarHeader(
              month: _focusedMonth,
              onPrev: _prevMonth,
              onNext: _nextMonth,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 265,
              child: PageView.builder(
                controller: _calendarPageController,
                onPageChanged: (index) {
                  kHapticSelect();
                  setState(() {
                    _focusedMonth = _monthFromIndex(index);
                  });
                },
                itemBuilder: (context, index) {
                  final month = _monthFromIndex(index);
                  return _CalendarGrid(
                    focusedMonth:     month,
                    selectedDate:     _selectedDate,
                    completedDayKeys: completedDayKeys,
                    loggedDayKeys:    loggedDayKeys,
                    onSelect: (d) {
                      setState(() => _selectedDate = d);
                      _openDay(d);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Weight permission request ──────────────────────────────────────────────────────

  Future<void> _doRequestWeightPermission() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    final granted = await HealthService().requestWeightPermission();

    if (!mounted) return;
    if (!granted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Weight permission was not granted. '
              'Open Health Connect settings to enable it.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Permission granted — fetch weight immediately.
    final weights = await HealthService().syncWeight();
    if (!mounted) return;

    setState(() {
      _weightHistory = weights.isNotEmpty ? weights : _weightHistory;
      _syncing = false;
    });
    WidgetService.updateWidgetData().ignore();

    if (weights.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No weight readings found in Health Connect yet.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // ── Workout State ─────────────────────────────────────────────────────────────

  Widget _buildWorkoutState() {
    final ws = WorkoutService.instance;
    final isToday = dateKey(_selectedDate) == dateKey(DateTime.now());

    if (!isToday) {
      final sessions = ws.sessionsForDate(_selectedDate);
      if (sessions.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: _WorkoutTargetCard(
            title: 'Completed Workout',
            subtitle: sessions.first.splitDayName,
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF52B788),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    Widget content;
    
    // Priority 1: Draft
    if (ws.draftSession != null) {
      content = _WorkoutTargetCard(
        title: 'Workout in Progress',
        subtitle: ws.draftSession!.splitDayName,
        icon: Icons.play_circle_fill_rounded,
        color: const Color(0xFFFFB347),
        actionLabel: 'Resume',
        onAction: () => _goToTrainTab(),
      );
    }
    // Priority 2: Completed
    else if (ws.sessionsForDate(_selectedDate).isNotEmpty) {
      content = _WorkoutTargetCard(
        title: 'Workout Completed',
        subtitle: ws.sessionsForDate(_selectedDate).first.splitDayName,
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF52B788),
      );
    }
    // Priority 3: Scheduled (explicitly mapped from Split config)
    else if (ws.splitDayFor(_selectedDate) != null) {
      content = _WorkoutTargetCard(
        title: 'Scheduled: ${ws.splitDayFor(_selectedDate)!.name}',
        subtitle: 'Hit your protein targets today.',
        icon: Icons.fitness_center_rounded,
        color: const Color(0xFF60A5FA),
        actionLabel: 'Start',
        onAction: () => _goToTrainTab(),
      );
    }
    // Priority 4: Rest Day
    else {
      content = _WorkoutTargetCard(
        title: 'Rest Day',
        subtitle: 'Focus on recovery.',
        icon: Icons.bedtime_rounded,
        color: const Color(0xFF9CA3AF),
        actionLabel: 'Train anyway',
        onAction: () => _goToTrainTab(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: content,
    );
  }

  void _goToTrainTab() {
    AppShell.of(context)?.switchToTab(1);
  }

  // ── Daily summary ─────────────────────────────────────────────────────────────

  Widget _buildDailySummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _RingStatCard(
                  label:    'Calories',
                  consumed: _consumedCalories,
                  target:   _targetCalories,
                  unit:     'kcal',
                  color:    const Color(0xFFFF6B35),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RingStatCard(
                  label:    'Protein',
                  consumed: _consumedProtein,
                  target:   _targetProtein,
                  unit:     'g',
                  color:    const Color(0xFF52B788),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Remaining Cal',
                  value: '${_remainingCalories.toInt()} kcal',
                  icon:  Icons.local_fire_department_outlined,
                  color: const Color(0xFFFFB347),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Remaining Protein',
                  value: '${_remainingProtein.toInt()} g',
                  icon:  Icons.fitness_center_outlined,
                  color: const Color(0xFF60A5FA),
                ),
              ),
            ],
          ),
          DailyNutritionQualityCard(
            log: _selectedLog,
            targetCal: _targetCalories,
            targetPro: _targetProtein,
          ),
          const SizedBox(height: 12),
          _buildQuickEstimatorCard(),
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

  Widget _buildQuickEstimatorCard() {
    return Pressable(
      onTap: _openQuickMacroEstimator,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A2A3C), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: KColor.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bolt_rounded, color: KColor.blue, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Quick Macro Estimator',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Manually enter macros or estimate using AI',
                    style: TextStyle(color: KColor.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: KColor.textMuted),
          ],
        ),
      ),
    );
  }

  // ── Targets ───────────────────────────────────────────────────────────────────

  Widget _buildTargets() {
    final plan = _weeklyPlan;
    final stepOffset = plan.effectiveStepsPerDay != null
        ? _stepOffsetLabel(plan.effectiveStepsPerDay!, _profile)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: _Card(
        child: Column(
          children: [
            _TargetRow(
              label:    'Maintenance (${plan.healthConnectActive ? 'Health Connect' : 'Profile-based'})',
              value:    '${plan.maintenanceCalories.toInt()} kcal/day',
              subtitle: stepOffset,
              icon:     Icons.balance_rounded,
              color:    const Color(0xFF9CA3AF),
            ),
            const _Divider(),
            _TargetRow(
              label:    'Goal — ${_profile.goal}',
              value:    '${plan.avgDailyCalories.toInt()} kcal/day avg',
              subtitle: '🏋️ ${plan.trainingDayCalories.toInt()} train  •  😴 ${plan.restDayCalories.toInt()} rest',
              icon:     Icons.flag_rounded,
              color:    const Color(0xFF52B788),
            ),
            const _Divider(),
            _TargetRow(
              label:    'Protein — avg / train / rest',
              value:    '${plan.avgDailyProtein.toInt()} g/day',
              subtitle: '🏋️ ${plan.trainingDayProtein.toInt()} g  •  😴 ${plan.restDayProtein.toInt()} g',
              icon:     Icons.fitness_center_rounded,
              color:    const Color(0xFF60A5FA),
            ),
          ],
        ),
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
      return '✓ Step history confirms baseline';
    } else if (offset > 0) {
      return '▲ +$offset kcal from step history';
    } else {
      return '▼ −${offset.abs()} kcal from step history';
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

  Widget _buildInsightsEntryCard() {
    return ListenableBuilder(
      listenable: InsightsReportService.instance,
      builder: (context, _) {
        final streak = _computeStreak();
        final latestWeekly = InsightsReportService.instance.latestWeekly();
        final newCount = InsightsReportService.instance.newAchievementCount;

        final hasStreak = streak > 0;
        final hasReport = latestWeekly != null;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Pressable(
            onTap: () {
              kHaptic();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InsightsScreen(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(18),
            child: _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('📊', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Text(
                        'Weekly Insights',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      if (newCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D6A4F),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF52B788),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$newCount new',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (hasReport) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        const Text(
                          'Consistency Score: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${latestWeekly.consistencyScore.score}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (latestWeekly.deltaVsPrior?.consistencyScoreDelta != null) ...[
                          _buildDeltaChip(latestWeekly.deltaVsPrior!.consistencyScoreDelta!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getWeeklyNarrative(latestWeekly),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                        height: 1.2,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Log meals this week to unlock your insights report.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasStreak
                              ? const Color(0xFFFF6B35).withValues(alpha: 0.12)
                              : const Color(0xFF2E2E3E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(hasStreak ? '🔥' : '💤', style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(
                              hasStreak
                                  ? '$streak ${streak == 1 ? 'day' : 'days'}'
                                  : 'No streak',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: hasStreak ? Colors.white : const Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'View Insights →',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF52B788),
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
  }

  Widget _buildDeltaChip(int delta) {
    final isPositive = delta > 0;
    if (delta == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isPositive
            ? const Color(0xFF52B788).withValues(alpha: 0.12)
            : const Color(0xFFFF4D4D).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${isPositive ? '+' : ''}$delta ${isPositive ? '↑' : '↓'}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isPositive ? const Color(0xFF52B788) : const Color(0xFFFF4D4D),
        ),
      ),
    );
  }

  String _getWeeklyNarrative(WeeklyReport report) {
    final aiSummary = InsightsReportService.instance.aiSummaryFor(report.weekKey);
    if (aiSummary != null && aiSummary.narrative.isNotEmpty && !aiSummary.isStale) {
      return aiSummary.narrative;
    }
    final logged = report.loggedDaysCount;
    final proteinHits = (report.consistencyScore.proteinAdherence * logged).round();
    final gym = report.gymDaysCount;
    return 'Protein hit $proteinHits/$logged days. Gym $gym sessions.';
  }

  // ── Section title ─────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return KSectionTitle(title);
  }
}

// ─── Calendar sub-widgets ─────────────────────────────────────────────────────

class _CalendarHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _CalendarHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF9CA3AF)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: Text(
            '${_months[month.month - 1]} ${month.year}',
            key: ValueKey(month),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;
  final Set<String> completedDayKeys;
  final Set<String> loggedDayKeys;

  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onSelect,
    this.completedDayKeys = const {},
    this.loggedDayKeys    = const {},
  });

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

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
        Row(
          children: _weekdays
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4B5563),
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        for (int row = 0; row < rows; row++)
          Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final dayNum = cellIndex - startOffset + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const Expanded(child: SizedBox(height: 36));
              }
              final date = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
              final isToday    = date.year == today.year && date.month == today.month && date.day == today.day;
              final isSelected = date.year == selectedDate.year &&
                  date.month == selectedDate.month &&
                  date.day == selectedDate.day;

              final dk          = dateKey(date);
              final hasGym      = dayLogStore[dk]?.gymDay?.didGym == true;
              final isCompleted = completedDayKeys.contains(dk);
              final isLogged    = loggedDayKeys.contains(dk);

              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(date),
                  child: Container(
                    height: 36,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF2D6A4F)
                          : isCompleted && !isToday
                              ? const Color(0xFF52B788).withValues(alpha: 0.13)
                              : isToday
                                  ? const Color(0xFF52B788).withValues(alpha: 0.15)
                                  : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: isToday && !isSelected
                          ? Border.all(color: const Color(0xFF52B788), width: 1.5)
                          : isCompleted && !isSelected && !isToday
                              ? Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.35), width: 1)
                              : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : isToday
                                    ? const Color(0xFF52B788)
                                    : isCompleted
                                        ? const Color(0xFF74C69D)
                                        : const Color(0xFF9CA3AF),
                          ),
                        ),
                        Positioned(
                          bottom: 3,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCompleted)
                                Container(
                                  width: 4, height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF52B788),
                                    shape: BoxShape.circle,
                                  ),
                                )
                              else if (isLogged)
                                Container(
                                  width: 4, height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFFB347),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (hasGym)
                                Container(
                                  width: 4, height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? const Color(0xFF52B788).withValues(alpha: 0.6)
                                        : const Color(0xFF60A5FA),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

// ─── Stat widgets ─────────────────────────────────────────────────────────────

class _RingStatCard extends StatelessWidget {
  final String label;
  final double consumed;
  final double target;
  final String unit;
  final Color color;

  const _RingStatCard({
    required this.label,
    required this.consumed,
    required this.target,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio    = (consumed / target).clamp(0.0, 1.0);
    final isOver   = consumed > target;
    final ringColor = isOver ? KColor.warning : color;
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76, height: 76,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => KGradientCircularProgress(
                progress: value,
                strokeWidth: 7,
                colors: [
                  ringColor,
                  ringColor.withValues(alpha: 0.6),
                ],
                child: Text(
                  '${(value * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ringColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label.toUpperCase(),
            style: KText.label,
          ),
          const SizedBox(height: 4),
          KAnimatedCount(
            value: consumed,
            style: KText.h3,
          ),
          Text(
            '/ ${target.toInt()} $unit',
            style: KText.caption,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.md),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: KText.label.copyWith(fontSize: 10)),
                const SizedBox(height: 3),
                Text(value, style: KText.h3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Target row ───────────────────────────────────────────────────────────────

class _TargetRow extends StatelessWidget {
  final String  label;
  final String  value;
  final String? subtitle;   // optional step-correction line
  final IconData icon;
  final Color    color;

  const _TargetRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    )),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF52B788),
                        fontWeight: FontWeight.w500,
                      )),
              ],
            ),
          ),
          Text(value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              )),
        ],
      ),
    );
  }
}

// ─── FAB ──────────────────────────────────────────────────────────────────────

class _AddMealFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMealFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () { kHapticMedium(); onTap(); },
      borderRadius: BorderRadius.circular(27),
      scale: 0.95,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [KColor.greenDark, KColor.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(27),
          boxShadow: [
            BoxShadow(
              color: KColor.greenDark.withValues(alpha: 0.5),
              blurRadius: 16, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Add Meal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Avatar badge ─────────────────────────────────────────────────────────────

class _AvatarBadge extends StatelessWidget {
  final UserProfile profile;
  const _AvatarBadge({required this.profile});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final avatarUrl = user?.userMetadata?['avatar_url'] ?? user?.userMetadata?['picture'] as String?;

    String getInitials(String name) {
      if (name.isEmpty) return 'K';
      final parts = name.trim().split(RegExp(r'\s+'));
      if (parts.length == 1) {
        return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
      }
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }

    final initials = getInitials(profile.name);

    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 44,
        height: 44,
        color: const Color(0xFF2D6A4F),
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── Reusable primitives ──────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: Color(0xFF2E2E3E), height: 1, thickness: 1);
  }
}

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
    if (syncing) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: KCardShimmer(height: 110),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _borderColor.withValues(alpha: 0.30),
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: _buildBody(),
      ),
    );
  }

  Color get _borderColor {
    if (!available)         return const Color(0xFF4B5563);
    if (profile.healthSyncEnabled) return const Color(0xFF52B788);
    return const Color(0xFF2E2E3E);
  }

  Widget _buildBody() {
    // ── HC not installed ──────────────────────────────────────────────────────
    if (!available) {
      return Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Health Connect unavailable',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 3),
                Text('Install Health Connect from the Play Store to enable step sync.',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
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
          _SyncHeader(connected: false),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.warning_amber_rounded,
                size: 14, color: Color(0xFFFFB347)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(syncResult!.error!,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFFFB347))),
            ),
          ]),
          const SizedBox(height: 12),
          _ActionButton(label: 'Try again', onTap: onSync),
        ],
      );
    }

    // ── Not yet connected ─────────────────────────────────────────────────────
    if (syncResult == null || !profile.healthSyncEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF52B788).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('⚡', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Activity Sync',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Improve maintenance accuracy using your real step history',
                      style: TextStyle(
                          color: Color(0xFF6B7280), fontSize: 11.5)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _ActionButton(
              label: 'Connect Health Connect',
              filled: true,
              onTap: onConnect),
        ],
      );
    }

    // ── Connected & synced ────────────────────────────────────────────────────
    final r = syncResult!;
    final syncTime = profile.lastHealthSyncAt != null
        ? '${profile.lastHealthSyncAt!.hour.toString().padLeft(2, '0')}:'
          '${profile.lastHealthSyncAt!.minute.toString().padLeft(2, '0')}'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SyncHeader(connected: true),
            Text('Last sync $syncTime',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280))),
          ],
        ),
        const SizedBox(height: 12),

        // Step stats grid
        Row(
          children: [
            _StepStat(
              label:  'Avg 14d',
              value:  r.averageDailySteps14d != null
                  ? '${r.averageDailySteps14d!.toInt()} steps'
                  : 'No data',
            ),
            const SizedBox(width: 12),
            _StepStat(
              label:  'Avg 30d',
              value:  r.averageDailySteps30d != null
                  ? '${r.averageDailySteps30d!.toInt()} steps'
                  : 'No data',
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Effective + tier
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF13131F),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                r.activityTier.emoji,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.effectiveAverageSteps != null
                        ? '${r.effectiveAverageSteps!.toInt()} steps/day effective'
                        : 'No step data available',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${r.activityTier.displayName}  •  '
                    'Calorie offset: ${r.stepCalorieOffsetAt65kg >= 0 ? '+' : ''}${r.stepCalorieOffsetAt65kg} kcal',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 13, color: Color(0xFF52B788)),
            const SizedBox(width: 5),
            const Text('Maintenance is Health Connect–adjusted',
                style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF52B788),
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            _ActionButton(label: 'Sync Now', onTap: onSync),
          ],
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
    return Expanded(
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: 16,
            color: connected
                ? const Color(0xFF52B788)
                : const Color(0xFF4B5563),
          ),
          const SizedBox(width: 6),
          Text(
            'Health Connect',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: connected ? Colors.white : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
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
  const _ActionButton(
      {required this.label, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: filled
              ? const Color(0xFF52B788)
              : const Color(0xFF52B788).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: filled
              ? null
              : Border.all(
                  color: const Color(0xFF52B788).withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.black : const Color(0xFF52B788),
          ),
        ),
      ),
    );
  }
}

class _WorkoutTargetCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _WorkoutTargetCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                        height: 1.2)),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(actionLabel!,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Weight Summary Chip ─────────────────────────────────────────────────────
//
// Compact single-line pill above the full trend chart.
// Shows: current weight   ·   7d delta
// Only rendered when weightContext is non-null (controlled by caller).

class _WeightSummaryChip extends StatelessWidget {
  final WeightContext weightContext;
  const _WeightSummaryChip({required this.weightContext});

  @override
  Widget build(BuildContext context) {
    final ctx     = weightContext;
    final kgLabel = ctx.latestWeightKg != null
        ? '${ctx.latestWeightKg!.toStringAsFixed(1)} kg'
        : '—';

    // 7-day delta label + colour
    Widget deltaWidget;
    if (ctx.delta7dKg != null) {
      final d       = ctx.delta7dKg!;
      final abs     = d.abs();
      final sign    = d >= 0 ? '+' : '−';
      final neutral = abs < 0.1;
      final color   = neutral
          ? const Color(0xFF9CA3AF)
          : (d < 0 ? const Color(0xFF52B788) : const Color(0xFFEF4444));
      final icon    = neutral
          ? Icons.remove_rounded
          : (d < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded);
      deltaWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text('$sign${abs.toStringAsFixed(1)} kg  7d',
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      );
    } else {
      deltaWidget = const Text('7d: —',
          style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          const Icon(Icons.monitor_weight_outlined,
              size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Text(kgLabel,
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          deltaWidget,
          const Spacer(),
          // Confidence badge — only shown for low quality data
          if (ctx.quality.confidenceLabel == 'low')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('sparse data',
                  style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

// ─── Weight Trend Card ────────────────────────────────────────────────────────

class _WeightTrendCard extends StatefulWidget {
  final List<WeightReading>? weightHistory;
  final bool syncing;
  final VoidCallback onRequestPermission;

  const _WeightTrendCard({
    required this.weightHistory,
    required this.syncing,
    required this.onRequestPermission,
  });

  @override
  State<_WeightTrendCard> createState() => _WeightTrendCardState();
}

class _WeightTrendCardState extends State<_WeightTrendCard>
    with SingleTickerProviderStateMixin {
  String _range = '30D';
  int? _hoveredIndex;
  Timer? _tooltipTimer;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _entranceAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _tooltipTimer?.cancel();
    super.dispose();
  }

  void _setRange(String r) {
    kHaptic();
    setState(() {
      _range = r;
      _hoveredIndex = null;
    });
    _entranceController.reset();
    _entranceController.forward();
  }

  void _handleTouch(Offset localPos, double width, int pointCount) {
    if (pointCount < 1) return;
    _tooltipTimer?.cancel();
    final idx = (localPos.dx / width * (pointCount - 1)).round().clamp(0, pointCount - 1);
    if (idx != _hoveredIndex) {
      setState(() {
        _hoveredIndex = idx;
      });
      kHaptic();
    }
  }

  void _clearTouch() {
    _tooltipTimer?.cancel();
    _tooltipTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _hoveredIndex = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.weightHistory;
    if (widget.syncing && (history == null || history.isEmpty)) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: KChartShimmer(height: 160),
      );
    }

    if (history == null || history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: _Card(
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.monitor_weight_outlined,
                    color: Color(0xFF3B82F6), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Weight Tracking',
                        style: TextStyle(
                            fontSize: 15, color: Colors.white,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('Connect to see your weight trend',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.45),
                            height: 1.2)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: widget.onRequestPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Connect',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    final DateTime cutoff;
    switch (_range) {
      case '7D':
        cutoff = now.subtract(const Duration(days: 7));
        break;
      case '30D':
        cutoff = now.subtract(const Duration(days: 30));
        break;
      case '90D':
        cutoff = now.subtract(const Duration(days: 90));
        break;
      case 'ALL':
      default:
        cutoff = DateTime(1970);
        break;
    }

    final filtered = history.where((r) => r.recordedAt.isAfter(cutoff)).toList();
    final chartData = filtered.reversed.toList(); // oldest -> newest for X axis

    final latest = history.first;
    final fullContext = WeightContext.fromHistory(history);
    final delta7d = fullContext?.delta7dKg;
    final delta30d = fullContext?.delta30dKg;
    final qualityLabel = fullContext?.quality.confidenceLabel ?? 'low';

    double? minW, maxW, avgW;
    if (filtered.isNotEmpty) {
      final weights = filtered.map((r) => r.kg).toList();
      minW = weights.reduce((a, b) => a < b ? a : b);
      maxW = weights.reduce((a, b) => a > b ? a : b);
      avgW = weights.reduce((a, b) => a + b) / weights.length;
    }

    final String trendText;
    final IconData trendIcon;
    final Color trendColor;
    switch (fullContext?.trendDirection ?? 'unknown') {
      case 'gaining':
        trendText = 'Gaining';
        trendIcon = Icons.trending_up_rounded;
        trendColor = const Color(0xFFEF4444);
        break;
      case 'losing':
        trendText = 'Losing';
        trendIcon = Icons.trending_down_rounded;
        trendColor = const Color(0xFF52B788);
        break;
      case 'stable':
      default:
        trendText = 'Stable';
        trendIcon = Icons.remove_rounded;
        trendColor = const Color(0xFF9CA3AF);
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Weight Trend',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${latest.kg.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                                fontSize: 24,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        const SizedBox(width: 8),
                        Icon(trendIcon, size: 14, color: trendColor),
                        const SizedBox(width: 3),
                        Text(trendText,
                            style: TextStyle(
                                fontSize: 11,
                                color: trendColor,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: ['7D', '30D', '90D', 'ALL'].map((r) {
                    final isSelected = _range == r;
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: GestureDetector(
                        onTap: () => _setRange(r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF52B788).withValues(alpha: 0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF52B788) : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            r,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF52B788) : const Color(0xFF9CA3AF),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (delta7d != null) _DeltaChip('7d', delta7d),
                if (delta30d != null) ...[
                  const SizedBox(width: 8),
                  _DeltaChip('30d', delta30d),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (qualityLabel == 'high'
                            ? const Color(0xFF52B788)
                            : (qualityLabel == 'medium' ? const Color(0xFF60A5FA) : const Color(0xFFFFB347)))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (qualityLabel == 'high'
                              ? const Color(0xFF52B788)
                              : (qualityLabel == 'medium' ? const Color(0xFF60A5FA) : const Color(0xFFFFB347)))
                          .withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '$qualityLabel data',
                    style: TextStyle(
                      fontSize: 9,
                      color: qualityLabel == 'high'
                          ? const Color(0xFF52B788)
                          : (qualityLabel == 'medium' ? const Color(0xFF60A5FA) : const Color(0xFFFFB347)),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 110,
              child: chartData.isEmpty
                  ? const Center(
                      child: Text(
                        'No weigh-ins in this period',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: _entranceAnimation,
                      builder: (context, child) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final height = constraints.maxHeight;

                            final weights = chartData.map((r) => r.kg).toList();
                            final minWVal = weights.reduce((a, b) => a < b ? a : b);
                            final maxWVal = weights.reduce((a, b) => a > b ? a : b);
                            final avgWVal = weights.isNotEmpty
                                ? weights.reduce((a, b) => a + b) / weights.length
                                : 0.0;
                            final rangeVal = (maxWVal - minWVal).clamp(0.5, double.infinity);
                            final paddingVal = rangeVal * 0.2;
                            
                            double getY(double kg) {
                              final double animValue = _entranceAnimation.value;
                              // Interpolate coordinates from average weight (flat line) to target coordinates
                              final double currentKg = avgWVal + (kg - avgWVal) * animValue;
                              final norm = (currentKg - (minWVal - paddingVal)) / (rangeVal + paddingVal * 2);
                              return height - norm * height;
                            }

                            Widget? tooltipWidget;
                            if (_hoveredIndex != null && _hoveredIndex! < chartData.length) {
                              final reading = chartData[_hoveredIndex!];
                              final x = _hoveredIndex! / (chartData.length - 1) * width;
                              final y = getY(reading.kg);

                              final dateStr = '${reading.recordedAt.month}/${reading.recordedAt.day}';
                              tooltipWidget = Positioned(
                                left: (x - 50).clamp(0.0, width - 100.0),
                                top: (y - 45).clamp(0.0, height - 20.0),
                                child: Container(
                                  width: 100,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF222232),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF52B788), width: 1),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${reading.kg.toStringAsFixed(1)} kg',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        dateStr,
                                        style: const TextStyle(
                                          color: Color(0xFF9CA3AF),
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) => _handleTouch(details.localPosition, width, chartData.length),
                              onPanUpdate: (details) => _handleTouch(details.localPosition, width, chartData.length),
                              onPanEnd: (_) => _clearTouch(),
                              onPanCancel: () => _clearTouch(),
                              onTapDown: (details) => _handleTouch(details.localPosition, width, chartData.length),
                              onTapUp: (_) => _clearTouch(),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CustomPaint(
                                    size: Size.infinite,
                                    painter: _WeightChartPainter(
                                      readings: chartData,
                                      hoveredIndex: _hoveredIndex,
                                      getY: getY,
                                    ),
                                  ),
                                  if (tooltipWidget != null) tooltipWidget,
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            if (chartData.length >= 2)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${chartData.first.recordedAt.month}/${chartData.first.recordedAt.day}',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280)),
                    ),
                    Text(
                      '${chartData[chartData.length ~/ 2].recordedAt.month}/${chartData[chartData.length ~/ 2].recordedAt.day}',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280)),
                    ),
                    Text(
                      '${chartData.last.recordedAt.month}/${chartData.last.recordedAt.day}',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (minW != null && maxW != null && avgW != null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A2A3C), width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatCol('MIN', '${minW.toStringAsFixed(1)} kg'),
                    Container(width: 1, height: 16, color: const Color(0xFF2A2A3C)),
                    _StatCol('MAX', '${maxW.toStringAsFixed(1)} kg'),
                    Container(width: 1, height: 16, color: const Color(0xFF2A2A3C)),
                    _StatCol('AVG', '${avgW.toStringAsFixed(1)} kg'),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${history.length} readings · Last from ${latest.source}',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.30)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCol extends StatelessWidget {
  final String label;
  final String value;
  const _StatCol(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF6B7280), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<WeightReading> readings;
  final int? hoveredIndex;
  final double Function(double) getY;

  _WeightChartPainter({
    required this.readings,
    required this.hoveredIndex,
    required this.getY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.isEmpty) return;

    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A3C)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    void drawDashedLine(double y) {
      const dashWidth = 4.0;
      const dashSpace = 4.0;
      double startX = 0.0;
      while (startX < size.width) {
        canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), gridPaint);
        startX += dashWidth + dashSpace;
      }
    }

    drawDashedLine(size.height * 0.25);
    drawDashedLine(size.height * 0.50);
    drawDashedLine(size.height * 0.75);

    final n = readings.length;

    if (n == 1) {
      final y = getY(readings.first.kg);
      final centerPoint = Offset(size.width / 2, y);

      canvas.drawCircle(centerPoint, 6.0, Paint()..color = const Color(0xFF13131F)..style = PaintingStyle.fill);
      canvas.drawCircle(centerPoint, 4.0, Paint()..color = const Color(0xFF52B788)..style = PaintingStyle.fill);

      const dashWidth = 4.0;
      const dashSpace = 4.0;
      double startX = 0.0;
      final dashedGuidePaint = Paint()
        ..color = const Color(0xFF52B788).withValues(alpha: 0.3)
        ..strokeWidth = 1.0;
      while (startX < size.width) {
        canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), dashedGuidePaint);
        startX += dashWidth + dashSpace;
      }
      return;
    }

    final points = List.generate(n, (i) {
      final x = i / (n - 1) * size.width;
      final y = getY(readings[i].kg);
      return Offset(x, y);
    });

    final linePaint = Paint()
      ..color = const Color(0xFF52B788)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cpX  = (prev.dx + curr.dx) / 2;
      path.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(path, linePaint);

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF52B788).withValues(alpha: 0.20),
            const Color(0xFF52B788).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    if (hoveredIndex != null && hoveredIndex! < points.length) {
      final hoveredPt = points[hoveredIndex!];

      final indicatorPaint = Paint()
        ..color = const Color(0xFF52B788).withValues(alpha: 0.4)
        ..strokeWidth = 1.0;
      double startY = hoveredPt.dy;
      while (startY < size.height) {
        canvas.drawLine(Offset(hoveredPt.dx, startY), Offset(hoveredPt.dx, startY + 4.0), indicatorPaint);
        startY += 8.0;
      }

      // Glowing pulsing rings around touch target
      canvas.drawCircle(hoveredPt, 14.0, Paint()..color = const Color(0xFF52B788).withValues(alpha: 0.15)..style = PaintingStyle.fill);
      canvas.drawCircle(hoveredPt, 8.5, Paint()..color = const Color(0xFF52B788).withValues(alpha: 0.3)..style = PaintingStyle.fill);
      canvas.drawCircle(hoveredPt, 5.0, Paint()..color = const Color(0xFF13131F)..style = PaintingStyle.fill);
      canvas.drawCircle(hoveredPt, 3.5, Paint()..color = const Color(0xFF52B788)..style = PaintingStyle.fill);
    } else {
      final dotPaint = Paint()
        ..color = const Color(0xFF52B788)
        ..style = PaintingStyle.fill;
      final rimPaint  = Paint()
        ..color = const Color(0xFF1C1C2E)
        ..style = PaintingStyle.fill;

      for (int i = 0; i < points.length; i++) {
        final pt = points[i];
        if (i == points.length - 1) {
          // Pulse the latest point
          canvas.drawCircle(pt, 12.0, Paint()..color = const Color(0xFF52B788).withValues(alpha: 0.12)..style = PaintingStyle.fill);
          canvas.drawCircle(pt, 7.0, Paint()..color = const Color(0xFF52B788).withValues(alpha: 0.25)..style = PaintingStyle.fill);
        }
        canvas.drawCircle(pt, 5.5, rimPaint);
        canvas.drawCircle(pt, 3.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_WeightChartPainter oldDelegate) =>
      oldDelegate.readings != readings || oldDelegate.hoveredIndex != hoveredIndex;
}

class _DeltaChip extends StatelessWidget {
  final String label;
  final double delta;

  const _DeltaChip(this.label, this.delta);

  @override
  Widget build(BuildContext context) {
    final isLoss = delta < 0;
    final isNeutral = delta.abs() < 0.1;
    final color = isNeutral
        ? const Color(0xFF9CA3AF)
        : (isLoss ? const Color(0xFF52B788) : const Color(0xFFEF4444));
    final sign  = isLoss ? '' : '+'; // negative sign comes from value
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$sign${delta.toStringAsFixed(1)} kg  $label',
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
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
    final insights = log.getDailyNutritionInsights(targetCal, targetPro, 30.0);

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: KCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.analytics_rounded, color: Color(0xFF52B788), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Daily Nutrition Quality',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (score >= 80
                              ? const Color(0xFF52B788)
                              : (score >= 60
                                  ? const Color(0xFFFFB347)
                                  : const Color(0xFFEF4444)))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$score / 100',
                      style: TextStyle(
                        color: score >= 80
                            ? const Color(0xFF52B788)
                            : (score >= 60
                                ? const Color(0xFFFFB347)
                                : const Color(0xFFEF4444)),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  const Text(
                    '--',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...insights.map((insight) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5.0, right: 8.0),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: Color(0xFF52B788),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          insight,
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    if (widget.log.isEmpty) return const SizedBox.shrink();

    // Standardized Targets
    final targetFiber = widget.targetFiber;
    final remainingCal = (widget.targetCal - widget.targetPro * 4).clamp(0.0, double.infinity);
    final targetFat = remainingCal * 0.35 / 9;
    final targetCarbs = remainingCal * 0.65 / 4;

    // Consumed Midpoints
    final consumedFiber = widget.log.totalFiberMid;
    final consumedCarbs = widget.log.totalCarbsMid;
    final consumedFat = widget.log.totalFatMid;

    final consumedSugar = widget.log.totalSugarMid;
    final consumedSatFat = widget.log.totalSaturatedFatMid;
    final consumedSodium = widget.log.totalSodiumMid;

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: KCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.tune_rounded, color: Color(0xFF60A5FA), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Additional Macros',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(color: Color(0xFF2E2E3E), height: 1),
                    const SizedBox(height: 12),
                    // 1. Fiber (Highest priority secondary metric)
                    _buildMacroRow(
                      label: 'Dietary Fiber',
                      consumed: consumedFiber,
                      target: targetFiber,
                      unit: 'g',
                      color: const Color(0xFF52B788),
                    ),
                    const SizedBox(height: 12),
                    // 2. Carbohydrates
                    _buildMacroRow(
                      label: 'Carbohydrates',
                      consumed: consumedCarbs,
                      target: targetCarbs,
                      unit: 'g',
                      color: const Color(0xFF60A5FA),
                    ),
                    const SizedBox(height: 12),
                    // 3. Fat
                    _buildMacroRow(
                      label: 'Fat',
                      consumed: consumedFat,
                      target: targetFat,
                      unit: 'g',
                      color: const Color(0xFFFFB347),
                    ),
                    
                    // Optional macros: Sugar, Sat Fat, Sodium
                    if (consumedSugar > 0) ...[
                      const SizedBox(height: 12),
                      _buildOptionalMacroRow('Sugar', consumedSugar, 'g'),
                    ],
                    if (consumedSatFat > 0) ...[
                      const SizedBox(height: 12),
                      _buildOptionalMacroRow('Saturated Fat', consumedSatFat, 'g'),
                    ],
                    if (consumedSodium > 0) ...[
                      const SizedBox(height: 12),
                      _buildOptionalMacroRow('Sodium', consumedSodium, 'mg'),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroRow({
    required String label,
    required double consumed,
    required double target,
    required String unit,
    required Color color,
  }) {
    final pct = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              '${consumed.toStringAsFixed(1)} / ${target.toStringAsFixed(0)} $unit (${(pct * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: pct),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: const Color(0xFF2E2E3E),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildOptionalMacroRow(String label, double consumed, String unit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
        ),
        Text(
          '${consumed.toStringAsFixed(1)} $unit',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

