import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../screens/onboarding_screen.dart';
import '../screens/day_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../models/day_log.dart';
import '../services/health_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../services/workout_service.dart';
import '../screens/app_shell.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  // ── Health Connect state ────────────────────────────────────────────────────
  HealthSyncResult? _syncResult;
  bool _syncing     = false;
  bool _hcAvailable = false;

  @override
  void initState() {
    super.initState();
    // Show a loading indicator if user already connected
    if (currentUserProfile?.healthSyncEnabled == true) {
      _syncing = true;
    }
    _initHealth();
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
    }

    final result = await HealthService().sync();
    if (!mounted) return;

    if (!result.hasError && result.hasData) {
      currentUserProfile = currentUserProfile!.copyWithHealth(
        averageDailySteps: result.effectiveAverageSteps!.toInt(),
        lastHealthSyncAt:  result.syncedAt,
      );
      PersistenceService.saveProfile(currentUserProfile!).ignore();
    }
    setState(() {
      _syncResult = result;
      _syncing    = false;
    });
  }

  UserProfile get _profile => currentUserProfile!;

  // ── Engine-based target getters ───────────────────────────────────────────
  //
  // The engine is the single source of truth for all nutrition targets.
  // We compute the weekly plan once per rebuild (pure math, microseconds).

  WeeklyTargetPlan get _weeklyPlan =>
      NutritionTargetEngine().weeklyPlan(_profile, health: _syncResult);

  bool get _isActualTrainingDay {
    final ws = WorkoutService.instance;
    final isToday = dateKey(_selectedDate) == dateKey(DateTime.now());

    // 1. Active draft
    if (isToday && ws.draftSession != null) return true;

    // 2. Completed workout
    if (ws.sessionsForDate(_selectedDate).isNotEmpty) return true;

    // 3. Explicitly toggled in daily log
    if (logFor(_selectedDate).gymDay != null) {
      return logFor(_selectedDate).gymDay!.didGym;
    }

    // 4. Scheduled Split
    if (ws.splitDayFor(_selectedDate) != null) return true;

    return false;
  }

  double get _targetCalories {
    return NutritionTargetEngine().dayTarget(
      _profile,
      isGymDay: _isActualTrainingDay,
      health: _syncResult,
    ).calories;
  }

  double get _targetProtein {
    return NutritionTargetEngine().dayTarget(
      _profile,
      isGymDay: _isActualTrainingDay,
      health: _syncResult,
    ).protein;
  }

  // Live reads from the global store
  DayLog get _selectedLog      => logFor(_selectedDate);
  double get _consumedCalories => _selectedLog.totalCaloriesMid;
  double get _consumedProtein  => _selectedLog.totalProteinMid;
  double get _remainingCalories => (_targetCalories - _consumedCalories).clamp(0, double.infinity);
  double get _remainingProtein  => (_targetProtein  - _consumedProtein ).clamp(0, double.infinity);

  void _prevMonth() => setState(() =>
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));

  void _nextMonth() => setState(() =>
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));

  Future<void> _openDay(DateTime date) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayDetailScreen(date: date, health: _syncResult),
      ),
    );
    setState(() {});   // refresh rings after returning
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      floatingActionButton: _AddMealFab(onTap: () => _openDay(_selectedDate)),
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
            SliverToBoxAdapter(child: _buildStreak()),
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
    // Compute which days have nutrition data for the focused month.
    // "completed" = ≥88% of the profile's avg daily calorie target hit.
    // "logged"    = any meals recorded but target not fully met.
    // (We use avg daily target here since we don't know per-day gym state for
    //  historic dates without expensive lookups. 88% is a generous threshold.)
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
            _CalendarGrid(
              focusedMonth:     _focusedMonth,
              selectedDate:     _selectedDate,
              completedDayKeys: completedDayKeys,
              loggedDayKeys:    loggedDayKeys,
              onSelect: (d) {
                setState(() => _selectedDate = d);
                _openDay(d);
              },
            ),
          ],
        ),
      ),
    );
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
        ],
      ),
    );
  }

  // ── Targets ───────────────────────────────────────────────────────────────────

  Widget _buildTargets() {
    final plan = _weeklyPlan;
    final stepOffset = plan.healthConnectActive && plan.effectiveStepsPerDay != null
        ? _stepOffsetLabel(plan.effectiveStepsPerDay!)
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

  /// Produces a human-readable step-correction note (matches engine bands).
  static String _stepOffsetLabel(int steps) {
    if (steps < 3000)  return '▼ −150 kcal from step history';
    if (steps < 5000)  return '▼ −75 kcal  from step history';
    if (steps < 7500)  return '✓ Step history confirms baseline';
    if (steps < 10000) return '▲ +100 kcal from step history';
    if (steps < 12000) return '▲ +180 kcal from step history';
    return '▲ +250 kcal from step history';
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

  Widget _buildStreak() {
    final streak = _computeStreak();
    final hasStreak = streak > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: _Card(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hasStreak
                    ? const Color(0xFFFF6B35).withValues(alpha: 0.15)
                    : const Color(0xFF2E2E3E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  hasStreak ? '🔥' : '💤',
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasStreak ? 'Current Streak' : 'No streak yet',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasStreak
                        ? '$streak ${streak == 1 ? 'day' : 'days'} in a row'
                        : 'Log a meal today to start!',
                    style: TextStyle(
                      fontSize: hasStreak ? 20 : 14,
                      fontWeight: FontWeight.w800,
                      color: hasStreak ? Colors.white : const Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
            if (hasStreak)
              Text(
                streak >= 7 ? '🏆' : streak >= 3 ? '⭐' : '✨',
                style: const TextStyle(fontSize: 28),
              ),
          ],
        ),
      ),
    );
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
        Text(
          '${_months[month.month - 1]} ${month.year}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
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
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 76, height: 76,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, __) => CircularProgressIndicator(
                    value: value,
                    strokeWidth: 7,
                    backgroundColor: KColor.border,
                    valueColor: AlwaysStoppedAnimation(ringColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, value, __) => Text(
                  '${(value * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: ringColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label.toUpperCase(),
            style: KText.label,
          ),
          const SizedBox(height: 4),
          Text(
            '${consumed.toInt()}',
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
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF2D6A4F),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Center(
        child: Text(
          profile.gender == 'Male' ? '👨' : '👩',
          style: const TextStyle(fontSize: 22),
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

    // ── Syncing spinner ───────────────────────────────────────────────────────
    if (syncing) {
      return const Row(
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Color(0xFF52B788)),
          ),
          SizedBox(width: 14),
          Text('Syncing with Health Connect…',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
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
                    'Calorie offset: ${r.stepCalorieOffset >= 0 ? '+' : ''}${r.stepCalorieOffset} kcal',
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
