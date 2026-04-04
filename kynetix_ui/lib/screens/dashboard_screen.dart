import 'package:flutter/material.dart';
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
    _initHealth();
  }

  Future<void> _initHealth() async {
    final available = await HealthService().isAvailable();
    if (!mounted) return;
    setState(() => _hcAvailable = available);

    // Auto-refresh if user already granted permission previously
    if (available && (currentUserProfile?.healthSyncEnabled == true)) {
      _doSync();
    }
  }

  Future<void> _doSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    // Ask for permission if not yet granted
    final hasPerm = await HealthService().hasPermission();
    if (!hasPerm) {
      final granted = await HealthService().requestPermission();
      if (!granted) {
        if (mounted) setState(() => _syncing = false);
        return;
      }
    }

    final result = await HealthService().sync();
    if (!mounted) return;

    if (!result.hasError && result.hasData) {
      // Write step data back into UserProfile so TDEE recalculates.
      currentUserProfile = currentUserProfile!.copyWithHealth(
        averageDailySteps: result.effectiveAverageSteps!.toInt(),
        lastHealthSyncAt:  result.syncedAt,
      );
      // Persist updated profile so HC step data survives restart.
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
    final emoji = _profile.gender == 'Male' ? '💪' : '🌟';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, ${_profile.name} $emoji',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Today\'s Overview',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          // Tapping the avatar badge opens the profile screen.
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    onProfileChanged: () => setState(() {}),
                  ),
                ),
              );
              setState(() {}); // re-read possibly updated profile
            },
            child: _AvatarBadge(profile: _profile),
          ),
        ],
      ),
    );
  }

  // ── Calendar ─────────────────────────────────────────────────────────────────

  Widget _buildCalendar() {
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
              focusedMonth: _focusedMonth,
              selectedDate: _selectedDate,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    );
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

  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onSelect,
  });

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    // weekday: 1=Mon … 7=Sun; shift so Mon=0
    final startOffset = (firstDay.weekday - 1) % 7;
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        // Weekday labels
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
        // Day grid
        for (int row = 0; row < rows; row++)
          Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final dayNum = cellIndex - startOffset + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const Expanded(child: SizedBox(height: 36));
              }
              final date = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
              final isToday   = date.year == today.year && date.month == today.month && date.day == today.day;
              final isSelected = date.year == selectedDate.year &&
                  date.month == selectedDate.month &&
                  date.day == selectedDate.day;

              final hasGym = dayLogStore[dateKey(date)]?.gymDay?.didGym == true;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(date),
                  child: Container(
                    height: 36,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF2D6A4F)
                          : isToday
                              ? const Color(0xFF52B788).withValues(alpha: 0.15)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: isToday && !isSelected
                          ? Border.all(color: const Color(0xFF52B788), width: 1.5)
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday || isSelected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : isToday
                                    ? const Color(0xFF52B788)
                                    : const Color(0xFF9CA3AF),
                          ),
                        ),
                        if (hasGym)
                          Positioned(
                            bottom: 3,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                color: Color(0xFF52B788),
                                shape: BoxShape.circle,
                              ),
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
    final ratio = (consumed / target).clamp(0.0, 1.0);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, child) => CircularProgressIndicator(
                    value: value,
                    strokeWidth: 7,
                    backgroundColor: const Color(0xFF2E2E3E),
                    valueColor: AlwaysStoppedAnimation(color),
                    strokeCap: StrokeCap.round,
                  ),
                ),
              ),
              Text(
                '${(ratio * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${consumed.toInt()} / ${target.toInt()} $unit',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
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
    return _Card(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    )),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2D6A4F), Color(0xFF52B788)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(27),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
