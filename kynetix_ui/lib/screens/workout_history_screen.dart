import 'dart:math' show max, min;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../models/workout_history_view_model.dart';
import '../services/workout_service.dart';

// ─── WorkoutHistoryScreen ─────────────────────────────────────────────────────
//
// Dedicated screen for viewing all workout history and dashboard analytics.
// Uses a cached WorkoutHistoryViewModel to avoid redundant computations.
//
// Tabs:
//   1. Analytics — Bento stats grid, contribution heatmap, achievements,
//                  muscle group balance, and exercise trends.
//   2. Sessions  — Chronological list grouped by week with calendar strip
//                  and search functionality.

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen>
    with SingleTickerProviderStateMixin {
  final _svc = WorkoutService.instance;

  // Selected calendar date (null = show all)
  DateTime? _selectedDate;
  // Selected time filter
  TimeRangeFilter _selectedFilter = TimeRangeFilter.last30Days;
  // Search query for sessions
  String _searchQuery = '';

  late final TabController _tabCtrl;
  WorkoutHistoryViewModel? _cachedVm;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _svc.addListener(_onServiceChange);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _svc.removeListener(_onServiceChange);
    super.dispose();
  }

  void _onServiceChange() {
    if (mounted) {
      setState(() {
        _cachedVm = null; // Invalidate cache
      });
    }
  }

  WorkoutHistoryViewModel _getVm() {
    _cachedVm ??= WorkoutHistoryViewModel.compute(
      service: _svc,
      filter: _selectedFilter,
    );
    return _cachedVm!;
  }

  @override
  Widget build(BuildContext context) {
    final vm = _getVm();

    return Scaffold(
      backgroundColor: KColor.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
          SliverAppBar(
            backgroundColor: KColor.surface,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            title: const Text(
              'Workout Report & Analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            bottom: TabBar(
              controller: _tabCtrl,
              labelColor: KColor.green,
              unselectedLabelColor: KColor.textMuted,
              indicatorColor: KColor.green,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: 'Analytics'),
                Tab(text: 'Sessions'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _AnalyticsTab(
              vm: vm,
              onFilterChanged: (filter) {
                setState(() {
                  _selectedFilter = filter;
                  _cachedVm = null; // Invalidate cache
                });
              },
            ),
            _SessionsTab(
              vm: vm,
              selectedDate: _selectedDate,
              onDateSelected: (date) {
                setState(() {
                  _selectedDate = _selectedDate != null &&
                          _dateKey(_selectedDate!) == _dateKey(date)
                      ? null
                      : date;
                });
              },
              searchQuery: _searchQuery,
              onSearchChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              service: _svc,
            ),
          ],
        ),
      ),
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─── Analytics Tab ────────────────────────────────────────────────────────────

class _AnalyticsTab extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  final ValueChanged<TimeRangeFilter> onFilterChanged;

  const _AnalyticsTab({
    required this.vm,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (vm.allSessions.isEmpty) {
      return const Center(
        child: _EmptyHistoryPlaceholder(
          title: 'No analytics data yet',
          subtitle: 'Log your first workout to generate insights and track progression.',
          ctaText: 'Start First Workout',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Time filter chip row
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: TimeRangeFilter.values.map((f) {
              final selected = vm.filter == f;
              return GestureDetector(
                onTap: () => onFilterChanged(f),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? KColor.green : KColor.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? KColor.green : KColor.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    f.label,
                    style: TextStyle(
                      color: selected ? Colors.white : KColor.textSecondary,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Bento Stats Grid
        const Text(
          'Overview',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            _BentoCard(
              title: 'Workouts',
              value: vm.totalWorkouts,
              icon: Icons.fitness_center_rounded,
              color: const Color(0xFF60A5FA),
              formatter: (val) => val.toStringAsFixed(0),
            ),
            _BentoCard(
              title: 'Sets Logged',
              value: vm.totalSets,
              icon: Icons.playlist_add_check_rounded,
              color: const Color(0xFF34D399),
              formatter: (val) => val.toStringAsFixed(0),
            ),
            _BentoCard(
              title: 'Volume',
              value: vm.totalVolume,
              icon: Icons.scale_rounded,
              color: const Color(0xFFFFB347),
              formatter: (val) => '${(val / 1000).toStringAsFixed(1)}k kg',
            ),
            _BentoCard(
              title: 'Training Hours',
              value: vm.totalHours,
              icon: Icons.timer_rounded,
              color: const Color(0xFFF472B6),
              formatter: (val) => '${val.toStringAsFixed(1)}h',
            ),
            _BentoCard(
              title: 'Current Streak',
              value: vm.currentStreak,
              icon: Icons.local_fire_department_rounded,
              color: const Color(0xFFEF4444),
              formatter: (val) => '${val.toStringAsFixed(0)}d',
              subtitle: 'Longest: ${vm.longestStreak}d',
            ),
            _BentoCard(
              title: 'Total PRs',
              value: vm.totalPrs,
              icon: Icons.emoji_events_rounded,
              color: const Color(0xFFFFD700),
              formatter: (val) => val.toStringAsFixed(0),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _HighlightInfoRow(
          mostTrainedMuscle: vm.mostTrainedMuscle,
          mostPerformedExercise: vm.mostPerformedExercise,
        ),
        const SizedBox(height: 20),

        // Workout heatmap contribution graph
        const Text(
          'Workout Consistency',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _HeatmapGrid(vm: vm),
        const SizedBox(height: 20),

        // Muscle Analytics & neglect detection
        const Text(
          'Muscle Balance & Neglect',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _MuscleAnalyticsCard(vm: vm),
        const SizedBox(height: 20),

        // Achievements Section
        const Text(
          'Unlocked Achievements',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _AchievementsList(achievements: vm.achievements),
        const SizedBox(height: 20),

        // Exercise progression trends directory
        const Text(
          'Exercise Progression Trends',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _ExerciseAnalyticsList(vm: vm),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ─── Sessions Tab ─────────────────────────────────────────────────────────────

class _SessionsTab extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final WorkoutService service;

  const _SessionsTab({
    required this.vm,
    required this.selectedDate,
    required this.onDateSelected,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.service,
  });

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // Filter sessions by search query and selected date
    final query = searchQuery.trim().toLowerCase();
    final searchFiltered = vm.allSessions.where((s) {
      // Date filter
      if (selectedDate != null) {
        if (_dateKey(s.date) != _dateKey(selectedDate!)) return false;
      }
      // Query filter
      if (query.isEmpty) return true;
      if (s.splitDayName.toLowerCase().contains(query)) return true;
      if (s.entries.any((e) => e.exercise.name.toLowerCase().contains(query))) return true;
      return false;
    }).toList();

    // Group by week
    final grouped = <String, List<WorkoutSession>>{};
    for (final s in searchFiltered) {
      final monday = s.date.subtract(Duration(days: s.date.weekday - 1));
      final key = _dateKey(monday);
      grouped.putIfAbsent(key, () => []).add(s);
    }

    return CustomScrollView(
      slivers: [
        // Calendar mini-strip
        SliverToBoxAdapter(
          child: _CalendarStrip(
            sessions: vm.allSessions,
            selectedDate: selectedDate,
            onDateSelected: onDateSelected,
          ),
        ),
        // Search bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by exercise, split name...',
                hintStyle: const TextStyle(color: KColor.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: KColor.textMuted, size: 18),
                filled: true,
                fillColor: KColor.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: KColor.border.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: KColor.green),
                ),
              ),
            ),
          ),
        ),
        if (vm.allSessions.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: _EmptyHistoryPlaceholder(
                title: 'No workouts logged yet',
                subtitle: 'Log a workout session to see your progress charts and history tiles.',
                ctaText: 'Start Workout',
              ),
            ),
          )
        else if (grouped.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.event_busy_rounded, color: KColor.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No sessions match search/filters',
                    style: TextStyle(color: KColor.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      onSearchChanged('');
                      if (selectedDate != null) onDateSelected(selectedDate!);
                    },
                    child: const Text('Clear search & filters', style: TextStyle(color: KColor.green)),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
                if (i >= keys.length) return null;
                final weekKey = keys[i];
                final sessions = grouped[weekKey]!;
                final monday = DateTime.parse(weekKey);
                return _WeekGroup(
                  monday: monday,
                  sessions: sessions,
                  service: service,
                );
              },
              childCount: grouped.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
      ],
    );
  }
}

// ─── Bento Card Stat ──────────────────────────────────────────────────────────

class _BentoCard extends StatefulWidget {
  final String title;
  final num value;
  final IconData icon;
  final Color color;
  final String Function(num) formatter;
  final String? subtitle;

  const _BentoCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.formatter,
    this.subtitle,
  });

  @override
  State<_BentoCard> createState() => _BentoCardState();
}

class _BentoCardState extends State<_BentoCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  num _oldVal = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _anim = Tween<double>(begin: 0, end: widget.value.toDouble()).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_BentoCard old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _oldVal = old.value;
      _anim = Tween<double>(begin: _oldVal.toDouble(), end: widget.value.toDouble()).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      );
      _ctrl.reset();
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: const TextStyle(color: KColor.textMuted, fontSize: 11)),
              Icon(widget.icon, color: widget.color.withValues(alpha: 0.8), size: 16),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: _anim,
                builder: (context, child) {
                  return Text(
                    widget.formatter(_anim.value),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(widget.subtitle!, style: const TextStyle(color: KColor.textSecondary, fontSize: 10)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Highlight Info Row ───────────────────────────────────────────────────────

class _HighlightInfoRow extends StatelessWidget {
  final String mostTrainedMuscle;
  final String mostPerformedExercise;

  const _HighlightInfoRow({
    required this.mostTrainedMuscle,
    required this.mostPerformedExercise,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.incomplete_circle_rounded, color: Color(0xFF60A5FA), size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Most Trained Muscle', style: TextStyle(color: KColor.textMuted, fontSize: 10)),
                      Text(mostTrainedMuscle, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 24, color: KColor.border),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.flash_on_rounded, color: Color(0xFFFFB347), size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top Performed Exercise', style: TextStyle(color: KColor.textMuted, fontSize: 10)),
                      Text(mostPerformedExercise, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
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

// ─── Heatmap Contribution Graph ───────────────────────────────────────────────

class _HeatmapGrid extends StatefulWidget {
  final WorkoutHistoryViewModel vm;
  const _HeatmapGrid({required this.vm});

  @override
  State<_HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<_HeatmapGrid> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Group days into columns of 7 (Monday-Sunday)
    final cols = <List<HeatmapDay>>[];
    for (int i = 0; i < widget.vm.heatmapDays.length; i += 7) {
      final end = min(i + 7, widget.vm.heatmapDays.length);
      cols.add(widget.vm.heatmapDays.sublist(i, end));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Weekly Logs', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  const Text('Less ', style: TextStyle(color: KColor.textMuted, fontSize: 9)),
                  _HeatmapCellColor(level: 0),
                  const SizedBox(width: 2),
                  _HeatmapCellColor(level: 1),
                  const SizedBox(width: 2),
                  _HeatmapCellColor(level: 2),
                  const SizedBox(width: 2),
                  _HeatmapCellColor(level: 3),
                  const SizedBox(width: 2),
                  _HeatmapCellColor(level: 4),
                  const Text(' More', style: TextStyle(color: KColor.textMuted, fontSize: 9)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 105,
            child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: cols.length,
              itemBuilder: (context, colIdx) {
                final col = cols[colIdx];
                return Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Column(
                    children: col.map((day) {
                      final hasWorkout = day.sessions.isNotEmpty;
                      final maxVol = widget.vm.maxDailyVolume;
                      double relative = 0;
                      if (hasWorkout && maxVol > 0) {
                        relative = day.totalVolume / maxVol;
                      }

                      Color cellColor;
                      if (!hasWorkout) {
                        cellColor = const Color(0xFF1E293B);
                      } else if (relative < 0.25) {
                        cellColor = KColor.green.withOpacity(0.2);
                      } else if (relative < 0.50) {
                        cellColor = KColor.green.withOpacity(0.45);
                      } else if (relative < 0.75) {
                        cellColor = KColor.green.withOpacity(0.75);
                      } else {
                        cellColor = KColor.green;
                      }

                      return GestureDetector(
                        onTap: () => _showDayDetails(day),
                        child: Container(
                          width: 11,
                          height: 11,
                          margin: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(
                            color: cellColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDayDetails(HeatmapDay day) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KColor.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final dateStr = '${day.date.day} ${_monthName(day.date.month)} ${day.date.year}';
        final hasWorkouts = day.sessions.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(hasWorkouts ? '${day.sessions.length} Workout(s)' : 'Rest Day',
                      style: TextStyle(color: KColor.green, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: KColor.border, height: 1),
              const SizedBox(height: 16),
              if (!hasWorkouts)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Column(
                      children: [
                        const Text('💤', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 12),
                        const Text(
                          'No workout logged for this day.',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rest is vital for muscle protein synthesis and recovery.',
                          style: TextStyle(color: KColor.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...day.sessions.map((s) {
                  final totalSets = s.totalSets;
                  final prCount = s.entries.fold<int>(0, (sum, entry) {
                    final top = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
                    if (top == null) return sum;
                    final prev = widget.vm.allSessions.any((p) => p.date.isBefore(s.date) && p.entries.any((e) => e.exercise.id == entry.exercise.id && (e.topProgressionSet?.estimatedOneRepMax ?? 0) >= top.estimatedOneRepMax));
                    return sum + (prev ? 0 : 1);
                  });

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KColor.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: KColor.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(s.splitDayName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            if (prCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB347).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('🏆 $prCount PRs', style: const TextStyle(color: Color(0xFFFFB347), fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _DayDetailChip(icon: Icons.fitness_center_rounded, text: '$totalSets sets'),
                            const SizedBox(width: 12),
                            _DayDetailChip(icon: Icons.scale_rounded, text: '${s.totalWorkingVolume.toStringAsFixed(0)} kg'),
                            if (s.durationMinutes != null) ...[
                              const SizedBox(width: 12),
                              _DayDetailChip(icon: Icons.timer_rounded, text: '${s.durationMinutes} min'),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  static String _monthName(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

class _HeatmapCellColor extends StatelessWidget {
  final int level;
  const _HeatmapCellColor({required this.level});

  @override
  Widget build(BuildContext context) {
    Color c = switch (level) {
      0 => const Color(0xFF1E293B),
      1 => KColor.green.withOpacity(0.2),
      2 => KColor.green.withOpacity(0.45),
      3 => KColor.green.withOpacity(0.75),
      _ => KColor.green,
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(1.5)),
    );
  }
}

class _DayDetailChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DayDetailChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: KColor.textMuted, size: 12),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: KColor.textSecondary, fontSize: 11)),
      ],
    );
  }
}

// ─── Muscle Analytics & Neglect Card ─────────────────────────────────────────

class _MuscleAnalyticsCard extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  const _MuscleAnalyticsCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final pushPct = (vm.pushPullRatio * 100).toStringAsFixed(0);
    final pullPct = ((1.0 - vm.pushPullRatio) * 100).toStringAsFixed(0);
    final upperPct = (vm.upperLowerRatio * 100).toStringAsFixed(0);
    final lowerPct = ((1.0 - vm.upperLowerRatio) * 100).toStringAsFixed(0);

    // List of neglected muscles (> 10 days)
    final neglected = vm.neglectedMuscles.where((m) => m.daysSinceLastTrained > 10).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Training Volume Balance', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _BalanceBar(
            title: 'Push vs Pull',
            leftPct: vm.pushPullRatio,
            leftLabel: 'Push ($pushPct%)',
            rightLabel: 'Pull ($pullPct%)',
            leftColor: KColor.green,
            rightColor: const Color(0xFF60A5FA),
          ),
          const SizedBox(height: 12),
          _BalanceBar(
            title: 'Upper vs Lower',
            leftPct: vm.upperLowerRatio,
            leftLabel: 'Upper ($upperPct%)',
            rightLabel: 'Lower ($lowerPct%)',
            leftColor: const Color(0xFFFFB347),
            rightColor: const Color(0xFFF472B6),
          ),
          const SizedBox(height: 16),
          const Text('Muscle Group Neglect Alert', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (neglected.isEmpty)
            Text('All key muscle groups trained recently. Good split distribution!',
                style: TextStyle(color: KColor.textSecondary, fontSize: 11))
          else
            SizedBox(
              height: 28,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: neglected.length,
                itemBuilder: (context, i) {
                  final item = neglected[i];
                  final label = item.daysSinceLastTrained == 999
                      ? '${item.muscleGroup}: Never trained ⚠️'
                      : '${item.muscleGroup}: ${item.daysSinceLastTrained}d ago ⚠️';
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Center(
                      child: Text(label, style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BalanceBar extends StatelessWidget {
  final String title;
  final double leftPct;
  final String leftLabel;
  final String rightLabel;
  final Color leftColor;
  final Color rightColor;

  const _BalanceBar({
    required this.title,
    required this.leftPct,
    required this.leftLabel,
    required this.rightLabel,
    required this.leftColor,
    required this.rightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: KColor.textMuted, fontSize: 10)),
            Text('$leftLabel vs $rightLabel', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  flex: (leftPct * 100).round().clamp(5, 95),
                  child: Container(color: leftColor),
                ),
                Expanded(
                  flex: ((1.0 - leftPct) * 100).round().clamp(5, 95),
                  child: Container(color: rightColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Achievements Section ─────────────────────────────────────────────────────

class _AchievementsList extends StatelessWidget {
  final List<AchievementInfo> achievements;
  const _AchievementsList({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: achievements.length,
        itemBuilder: (context, i) {
          final item = achievements[i];
          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: item.achieved
                    ? KColor.green.withOpacity(0.3)
                    : KColor.border.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Opacity(
                  opacity: item.achieved ? 1.0 : 0.25,
                  child: Text(item.icon, style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          color: item.achieved ? Colors.white : KColor.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: TextStyle(
                          color: KColor.textSecondary,
                          fontSize: 8,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Exercise Trends Directory ────────────────────────────────────────────────

class _ExerciseAnalyticsList extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  const _ExerciseAnalyticsList({required this.vm});

  @override
  Widget build(BuildContext context) {
    final list = vm.exerciseAnalytics;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final item = list[i];
        final deltaLabel = item.currentTrend > 0
            ? '+${item.currentTrend.toStringAsFixed(1)} kg'
            : '${item.currentTrend.toStringAsFixed(1)} kg';

        return GestureDetector(
          onTap: () => _openExerciseDetails(context, item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.exercise.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text('${item.exercise.muscleGroup} · ${item.totalSessions} Sessions',
                          style: const TextStyle(color: KColor.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      deltaLabel,
                      style: TextStyle(
                        color: item.currentTrend > 0
                            ? KColor.green
                            : item.currentTrend < 0
                                ? Colors.red
                                : KColor.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('Recent e1RM delta', style: TextStyle(color: KColor.textMuted, fontSize: 8)),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: KColor.textMuted, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openExerciseDetails(BuildContext context, ExerciseAnalyticInfo info) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KColor.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        // Find recent history values for line chart
        final history = WorkoutService.instance.historyFor(info.exercise.id, limit: 10);
        final values = history.reversed
            .map((h) => h.entry.topProgressionSet?.estimatedOneRepMax ?? h.entry.topWorkingSet?.estimatedOneRepMax ?? 0.0)
            .toList();
        final dates = history.reversed.map((h) => h.date).toList();

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.exercise.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(info.exercise.muscleGroup, style: const TextStyle(color: KColor.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: KColor.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: KColor.border, height: 1),
                const SizedBox(height: 16),

                // Stats Bento Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _DetailStatBox(title: 'Lifetime Volume', value: '${(info.lifetimeVolume / 1000).toStringAsFixed(1)}k kg'),
                    _DetailStatBox(title: 'Total Sessions', value: '${info.totalSessions}'),
                    _DetailStatBox(
                      title: 'Best Set Today',
                      value: info.bestSet != null
                          ? '${info.bestSet!.weight.toStringAsFixed(0)}x${info.bestSet!.reps}'
                          : 'N/A',
                    ),
                    _DetailStatBox(title: 'Best Estimated 1RM', value: '${info.bestE1rm.toStringAsFixed(1)} kg'),
                  ],
                ),
                const SizedBox(height: 20),

                // Insights section
                if (info.insights.isNotEmpty) ...[
                  const Text('Automatic Insights', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Column(
                    children: info.insights.map((insight) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KColor.greenDark.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: KColor.green.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_rounded, color: KColor.green, size: 14),
                            const SizedBox(width: 8),
                            Expanded(child: Text(insight, style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.4))),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Interactive Chart
                const Text('Estimated 1RM Progression', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (values.length < 2)
                  Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: KColor.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KColor.border),
                    ),
                    child: const Center(
                      child: Text('Complete more sessions to display graph.', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
                    ),
                  )
                else
                  _InteractiveLineChart(values: values, dates: dates),
                const SizedBox(height: 32),
              ],
            );
          },
        );
      },
    );
  }
}

class _DetailStatBox extends StatelessWidget {
  final String title;
  final String value;
  const _DetailStatBox({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: KColor.textMuted, fontSize: 9)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─── Custom Interactive Line Chart ───────────────────────────────────────────

class _InteractiveLineChart extends StatefulWidget {
  final List<double> values;
  final List<DateTime> dates;
  const _InteractiveLineChart({required this.values, required this.dates});

  @override
  State<_InteractiveLineChart> createState() => _InteractiveLineChartState();
}

class _InteractiveLineChartState extends State<_InteractiveLineChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.values.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onPanUpdate: (details) => _handleTouch(details.localPosition),
      onPanDown: (details) => _handleTouch(details.localPosition),
      onTapUp: (_) => setState(() => _selectedIndex = null),
      onPanEnd: (_) => setState(() => _selectedIndex = null),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KColor.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            if (_selectedIndex != null && _selectedIndex! < widget.values.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: KColor.greenDark,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_formatDate(widget.dates[_selectedIndex!])}: ${widget.values[_selectedIndex!].toStringAsFixed(1)} kg',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'Tap & drag to inspect values',
                  style: TextStyle(color: KColor.textMuted, fontSize: 10),
                ),
              ),
            SizedBox(
              height: 110,
              width: double.infinity,
              child: CustomPaint(
                painter: _LineChartPainter(
                  values: widget.values,
                  selectedIndex: _selectedIndex,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTouch(Offset localPos) {
    final width = context.size?.width ?? 300;
    final step = width / (widget.values.length - 1 == 0 ? 1 : widget.values.length - 1);
    final idx = (localPos.dx / step).round().clamp(0, widget.values.length - 1);
    if (idx != _selectedIndex) {
      setState(() {
        _selectedIndex = idx;
      });
    }
  }

  String _formatDate(DateTime d) => '${d.day} ${_shortMonth(d.month)}';
  static String _shortMonth(int m) =>
      ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m];
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final int? selectedIndex;
  _LineChartPainter({required this.values, required this.selectedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.reduce(max);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    final points = <Offset>[];
    final step = size.width / (values.length - 1 == 0 ? 1 : values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final relativeY = (values[i] - minVal) / range;
      final y = size.height - (relativeY * (size.height - 24) + 12);
      points.add(Offset(x, y));
    }

    // Draw grid lines
    final gridPaint = Paint()
      ..color = KColor.border.withOpacity(0.08)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, 12), Offset(size.width, 12), gridPaint);
    canvas.drawLine(Offset(0, size.height - 12), Offset(size.width, size.height - 12), gridPaint);

    // Draw area gradient path
    if (points.length > 1) {
      final areaPath = Path()..moveTo(points.first.dx, size.height);
      for (final pt in points) {
        areaPath.lineTo(pt.dx, pt.dy);
      }
      areaPath.lineTo(points.last.dx, size.height);
      areaPath.close();

      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KColor.green.withOpacity(0.25),
            KColor.green.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(areaPath, areaPaint);
    }

    // Draw main line path
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final linePaint = Paint()
      ..color = KColor.green
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);

    // Draw circles at data points
    final dotPaint = Paint()
      ..color = KColor.surface
      ..style = PaintingStyle.fill;
    final dotStrokePaint = Paint()
      ..color = KColor.green
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final isSelected = selectedIndex == i;
      canvas.drawCircle(points[i], isSelected ? 5.5 : 3.5, dotPaint);
      canvas.drawCircle(
        points[i],
        isSelected ? 5.5 : 3.5,
        isSelected
            ? (Paint()
              ..color = Colors.white
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke)
            : dotStrokePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Calendar Strip (3-month scrollable) ──────────────────────────────────────

class _CalendarStrip extends StatefulWidget {
  final List<WorkoutSession> sessions;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const _CalendarStrip({
    required this.sessions,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<_CalendarStrip> createState() => _CalendarStripState();
}

class _CalendarStripState extends State<_CalendarStrip> {
  late DateTime _displayMonth;
  late final Set<String> _sessionDates;

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _displayMonth = DateTime.now();
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(_CalendarStrip old) {
    super.didUpdateWidget(old);
    if (old.sessions.length != widget.sessions.length) _rebuildIndex();
  }

  void _rebuildIndex() {
    _sessionDates = widget.sessions.map((s) => _dateKey(s.date)).toSet();
  }

  bool _hasSession(DateTime d) => _sessionDates.contains(_dateKey(d));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDay = DateTime(_displayMonth.year, _displayMonth.month, 1);
    // Pad so grid starts on Monday
    final startOffset = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: KColor.textSecondary),
                onPressed: () => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              Text(
                '${_monthName(_displayMonth.month)} ${_displayMonth.year}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: KColor.textSecondary),
                onPressed: () => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Day headers
          Row(
            children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            color: KColor.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          // Grid
          for (int row = 0; row < rows; row++)
            Row(
              children: List.generate(7, (col) {
                final cell = row * 7 + col;
                if (cell < startOffset || cell >= startOffset + daysInMonth) {
                  return const Expanded(child: SizedBox(height: 32));
                }
                final day = cell - startOffset + 1;
                final date = DateTime(_displayMonth.year, _displayMonth.month, day);
                final trained = _hasSession(date);
                final isToday = _dateKey(date) == _dateKey(now);
                final isSelected = widget.selectedDate != null &&
                    _dateKey(date) == _dateKey(widget.selectedDate!);

                return Expanded(
                  child: GestureDetector(
                    onTap: trained ? () => widget.onDateSelected(date) : null,
                    child: Container(
                      margin: const EdgeInsets.all(1.5),
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? KColor.green
                            : isToday
                                ? KColor.greenDark.withValues(alpha: 0.3)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: isToday && !isSelected
                            ? Border.all(color: KColor.green.withValues(alpha: 0.4))
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : trained
                                      ? Colors.white
                                      : KColor.textMuted,
                              fontSize: 11,
                              fontWeight: trained ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          if (trained && !isSelected)
                            Container(
                              margin: const EdgeInsets.only(top: 1),
                              width: 3.5,
                              height: 3.5,
                              decoration: BoxDecoration(
                                color: KColor.green,
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
        ],
      ),
    );
  }

  static String _monthName(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ─── Week Group ───────────────────────────────────────────────────────────────

class _WeekGroup extends StatelessWidget {
  final DateTime monday;
  final List<WorkoutSession> sessions;
  final WorkoutService service;

  const _WeekGroup({
    required this.monday,
    required this.sessions,
    required this.service,
  });

  String _weekLabel() {
    final now = DateTime.now();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    final thisKey = '${thisMonday.year}-${thisMonday.month}-${thisMonday.day}';
    final monKey = '${monday.year}-${monday.month}-${monday.day}';
    if (thisKey == monKey) return 'This week';
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final lastKey = '${lastMonday.year}-${lastMonday.month}-${lastMonday.day}';
    if (lastKey == monKey) return 'Last week';
    return '${_shortMonth(monday.month)} ${monday.day}';
  }

  static String _shortMonth(int m) =>
      ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m];

  @override
  Widget build(BuildContext context) {
    final totalVol = sessions.fold<double>(0, (s, w) => s + w.totalWorkingVolume);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _weekLabel(),
                  style: const TextStyle(
                    color: KColor.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '${totalVol.toStringAsFixed(0)} kg total',
                  style: const TextStyle(color: KColor.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          for (final session in sessions)
            _SessionTile(session: session, service: service),
        ],
      ),
    );
  }
}

// ─── Session Tile ─────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final WorkoutSession session;
  final WorkoutService service;

  const _SessionTile({required this.session, required this.service});

  String _formatDate(DateTime d) {
    final days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday]}, ${months[d.month]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final totalSets = session.totalSets;
    final volume = session.totalWorkingVolume;
    final duration = session.durationMinutes;
    final prs = _countPrsInSession();

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _SessionDetailPage(session: session, service: service),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KColor.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: prs > 0
                ? KColor.green.withValues(alpha: 0.25)
                : KColor.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            // Day indicator
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: KColor.greenDark.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${session.date.day}',
                    style: const TextStyle(
                      color: KColor.green,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][session.date.month],
                    style: const TextStyle(color: KColor.textMuted, fontSize: 8.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.splitDayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (prs > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '🏆 $prs PR${prs > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Color(0xFFFFB347),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatDate(session.date),
                    style: const TextStyle(color: KColor.textMuted, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StatChip(icon: Icons.fitness_center_rounded, label: '$totalSets sets'),
                      const SizedBox(width: 8),
                      _StatChip(icon: Icons.scale_rounded, label: '${volume.toStringAsFixed(0)} kg'),
                      if (duration != null) ...[
                        const SizedBox(width: 8),
                        _StatChip(icon: Icons.timer_rounded, label: '${duration}m'),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: KColor.textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  int _countPrsInSession() {
    int count = 0;
    for (final entry in session.entries) {
      final top = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
      if (top == null) continue;
      final prev = service.bestSetBefore(entry.exercise.id, session.date);
      if (prev == null || top.estimatedOneRepMax > prev.estimatedOneRepMax + 0.01) {
        count++;
      }
    }
    return count;
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: KColor.textMuted, size: 10),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(color: KColor.textMuted, fontSize: 10)),
        ],
      );
}

// ─── Session Detail & Edit Page ───────────────────────────────────────────────

class _SessionDetailPage extends StatefulWidget {
  final WorkoutSession session;
  final WorkoutService service;

  const _SessionDetailPage({required this.session, required this.service});

  @override
  State<_SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<_SessionDetailPage> {
  late WorkoutSession _currentSession;

  @override
  void initState() {
    super.initState();
    _currentSession = widget.session;
  }

  String _formatDate(DateTime d) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${days[d.weekday]}, ${months[d.month]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _currentSession.durationMinutes;
    final volume = _currentSession.totalWorkingVolume;

    return Scaffold(
      backgroundColor: KColor.bg,
      appBar: AppBar(
        backgroundColor: KColor.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _currentSession.splitDayName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
        leading: const BackButton(color: KColor.textSecondary),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit_rounded, color: KColor.green, size: 16),
            label: const Text('Edit', style: TextStyle(color: KColor.green, fontSize: 13, fontWeight: FontWeight.bold)),
            onPressed: _openEditSessionScreen,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Session meta
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(_currentSession.date),
                  style: const TextStyle(color: KColor.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _DetailStat(label: 'Volume', value: '${volume.toStringAsFixed(0)} kg'),
                    _DetailStat(label: 'Total sets', value: '${_currentSession.totalSets}'),
                    if (duration != null) _DetailStat(label: 'Duration', value: '${duration}m'),
                  ],
                ),
                if (_currentSession.notes != null && _currentSession.notes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: KColor.border, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notes_rounded, color: KColor.textMuted, size: 13),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentSession.notes!,
                          style: const TextStyle(color: KColor.textSecondary, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Exercise breakdown timeline
          const Text(
            'Exercises Breakdown',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final entry in _currentSession.entries)
            if (!entry.isEmpty)
              _ExerciseDetailCard(
                entry: entry,
                service: widget.service,
                sessionDate: _currentSession.date,
              ),
        ],
      ),
    );
  }

  void _openEditSessionScreen() async {
    final updated = await Navigator.of(context).push<WorkoutSession>(
      MaterialPageRoute(
        builder: (_) => _EditSessionScreen(session: _currentSession),
      ),
    );
    if (updated != null) {
      await widget.service.saveSession(updated);
      setState(() {
        _currentSession = updated;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session updated successfully!'), backgroundColor: KColor.greenDark),
        );
      }
    }
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;
  const _DetailStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: KColor.textMuted, fontSize: 10)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      );
}

// ─── Edit Workout Session Screen ──────────────────────────────────────────────

class _EditSessionScreen extends StatefulWidget {
  final WorkoutSession session;
  const _EditSessionScreen({required this.session});

  @override
  State<_EditSessionScreen> createState() => _EditSessionScreenState();
}

class _EditSessionScreenState extends State<_EditSessionScreen> {
  late final TextEditingController _durationCtrl;
  late final TextEditingController _notesCtrl;
  late List<ExerciseEntry> _entries;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _durationCtrl = TextEditingController(text: widget.session.durationMinutes?.toString() ?? '45');
    _notesCtrl = TextEditingController(text: widget.session.notes ?? '');
    _date = widget.session.date;

    // Deep copy entries list
    _entries = widget.session.entries.map((e) {
      return ExerciseEntry(
        exercise: e.exercise,
        sets: List<SetEntry>.from(e.sets),
      );
    }).toList();
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColor.bg,
      appBar: AppBar(
        backgroundColor: KColor.surface,
        title: const Text('Edit Session Report', style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: KColor.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: KColor.green),
            onPressed: _saveChanges,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Basic fields
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Workout Date', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month, color: KColor.green, size: 14),
                      label: Text(
                        '${_date.day}/${_date.month}/${_date.year}',
                        style: const TextStyle(color: KColor.green, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _selectDate,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Duration (mins)', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _durationCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: KColor.bg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Session Notes', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: KColor.bg,
                    hintText: 'Add workout description or recovery state...',
                    hintStyle: const TextStyle(color: KColor.textMuted, fontSize: 11),
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Exercise Sets editor
          const Text('Sets Editor', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...List.generate(_entries.length, (exIdx) {
            final entry = _entries[exIdx];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KColor.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: KColor.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(entry.exercise.name,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                        onPressed: () {
                          setState(() {
                            _entries.removeAt(exIdx);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(entry.sets.length, (setIdx) {
                    final set = entry.sets[setIdx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Row(
                        children: [
                          Text('${setIdx + 1}', style: const TextStyle(color: KColor.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _EditTextField(
                              label: 'kg',
                              initialValue: set.weight.toString(),
                              onChanged: (val) {
                                final d = double.tryParse(val) ?? 0.0;
                                entry.sets[setIdx] = SetEntry(weight: d, reps: set.reps, rpe: set.rpe, setType: set.setType);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EditTextField(
                              label: 'reps',
                              initialValue: set.reps.toString(),
                              onChanged: (val) {
                                final r = int.tryParse(val) ?? 0;
                                entry.sets[setIdx] = SetEntry(weight: set.weight, reps: r, rpe: set.rpe, setType: set.setType);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _EditTextField(
                              label: 'RPE',
                              initialValue: set.rpe?.toString() ?? '',
                              onChanged: (val) {
                                final r = double.tryParse(val);
                                entry.sets[setIdx] = SetEntry(weight: set.weight, reps: set.reps, rpe: r, setType: set.setType);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          DropdownButton<SetType>(
                            value: set.setType,
                            dropdownColor: KColor.surface,
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(color: KColor.green, fontSize: 10, fontWeight: FontWeight.bold),
                            items: SetType.values.map((t) {
                              return DropdownMenuItem(value: t, child: Text(t.shortLabel));
                            }).toList(),
                            onChanged: (newType) {
                              if (newType != null) {
                                setState(() {
                                  entry.sets[setIdx] = SetEntry(weight: set.weight, reps: set.reps, rpe: set.rpe, setType: newType);
                                });
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: KColor.textMuted, size: 14),
                            onPressed: () {
                              setState(() {
                                entry.sets.removeAt(setIdx);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 12, color: KColor.green),
                    label: const Text('Add Set', style: TextStyle(color: KColor.green, fontSize: 11)),
                    onPressed: () {
                      setState(() {
                        final lastSet = entry.sets.isNotEmpty ? entry.sets.last : const SetEntry(weight: 20, reps: 10);
                        entry.sets.add(SetEntry(weight: lastSet.weight, reps: lastSet.reps, setType: SetType.normal));
                      });
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _selectDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: KColor.green,
              onPrimary: Colors.black,
              surface: KColor.surface,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (d != null) {
      setState(() {
        _date = d;
      });
    }
  }

  void _saveChanges() {
    final dur = int.tryParse(_durationCtrl.text) ?? 45;
    final updated = WorkoutSession(
      id: widget.session.id,
      date: _date,
      splitDayName: widget.session.splitDayName,
      splitDayWeekday: widget.session.splitDayWeekday,
      wasManuallySelected: widget.session.wasManuallySelected,
      entries: _entries,
      notes: _notesCtrl.text.trim(),
      durationMinutes: dur,
    );
    Navigator.of(context).pop(updated);
  }
}

class _EditTextField extends StatelessWidget {
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _EditTextField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: TextEditingController(text: initialValue)..selection = TextSelection.fromPosition(TextPosition(offset: initialValue.length)),
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: KColor.textMuted, fontSize: 9),
          filled: true,
          fillColor: KColor.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

// ─── Exercise Detail Card ─────────────────────────────────────────────────────

class _ExerciseDetailCard extends StatelessWidget {
  final ExerciseEntry entry;
  final WorkoutService service;
  final DateTime sessionDate;

  const _ExerciseDetailCard({
    required this.entry,
    required this.service,
    required this.sessionDate,
  });

  @override
  Widget build(BuildContext context) {
    final topSet = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
    final prevBest = service.bestSetBefore(entry.exercise.id, sessionDate);
    final isPr = topSet != null &&
        (prevBest == null || topSet.estimatedOneRepMax > prevBest.estimatedOneRepMax + 0.01);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPr ? const Color(0xFFFFB347).withValues(alpha: 0.25) : KColor.border.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.exercise.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              if (isPr)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    '🏆 New PR',
                    style: TextStyle(color: Color(0xFFFFB347), fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            entry.exercise.muscleGroup,
            style: const TextStyle(color: KColor.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 8),
          // Set list
          for (final set in entry.sets) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: _setTypeColor(set.setType).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      set.setType.shortLabel,
                      style: TextStyle(color: _setTypeColor(set.setType), fontSize: 8.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${set.weight.toStringAsFixed(set.weight == set.weight.truncateToDouble() ? 0 : 1)} kg × ${set.reps} reps',
                    style: const TextStyle(color: KColor.textSecondary, fontSize: 12),
                  ),
                  if (set.rpe != null) ...[
                    const SizedBox(width: 8),
                    Text('RPE ${set.rpe!.toStringAsFixed(1)}', style: const TextStyle(color: KColor.textMuted, fontSize: 10)),
                  ],
                  const Spacer(),
                  Text('${set.estimatedOneRepMax.toStringAsFixed(1)} e1RM', style: const TextStyle(color: KColor.textMuted, fontSize: 9)),
                ],
              ),
            ),
          ],
          // Volume sparkline for this exercise
          const SizedBox(height: 6),
          _ExerciseSparkline(exerciseId: entry.exercise.id, service: service),
        ],
      ),
    );
  }

  Color _setTypeColor(SetType t) => switch (t) {
        SetType.normal => KColor.green,
        SetType.warmUp => const Color(0xFF60A5FA),
        SetType.dropSet => const Color(0xFFFF6B6B),
        SetType.supersetA => const Color(0xFFFFB347),
        SetType.supersetB => const Color(0xFFDDA0DD),
        SetType.burnout => const Color(0xFFFF6B6B),
      };
}

// ─── Exercise Sparkline (e1RM trend) ─────────────────────────────────────────

class _ExerciseSparkline extends StatelessWidget {
  final String exerciseId;
  final WorkoutService service;

  const _ExerciseSparkline({required this.exerciseId, required this.service});

  @override
  Widget build(BuildContext context) {
    final history = service.exerciseOneRmTrend(exerciseId, limit: 6);
    if (history.isEmpty || history.every((v) => v == 0)) {
      return const SizedBox.shrink();
    }
    final maxVal = history.reduce(max);
    if (maxVal == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('e1RM history', style: TextStyle(color: KColor.textMuted, fontSize: 9)),
        const SizedBox(height: 3),
        SizedBox(
          height: 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: history
                .map((v) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          height: v == 0 ? 3 : (v / maxVal * 20).clamp(3, 20),
                          decoration: BoxDecoration(
                            color: v == history.last ? KColor.green : KColor.green.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Premium Empty Placeholder ────────────────────────────────────────────────

class _EmptyHistoryPlaceholder extends StatelessWidget {
  final String title;
  final String subtitle;
  final String ctaText;

  const _EmptyHistoryPlaceholder({
    required this.title,
    required this.subtitle,
    required this.ctaText,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.analytics_rounded, color: KColor.textMuted, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KColor.textMuted, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: KColor.green,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              // Trigger navigation to workout split/wizard or pop back to log
              Navigator.pop(context);
            },
            child: Text(ctaText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      );
}
