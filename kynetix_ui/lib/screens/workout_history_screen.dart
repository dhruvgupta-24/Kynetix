import 'dart:math' show max, min;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/workout_session.dart';
import '../models/workout_history_view_model.dart';
import '../services/workout_service.dart';
import '../services/achievement_engine.dart' show AchievementInfo;

// ─── WorkoutHistoryScreen ─────────────────────────────────────────────────────
//
// Dedicated screen for viewing all workout history and dashboard analytics.
// Uses a cached WorkoutHistoryViewModel to avoid redundant computations.
//
// Tabs:
//   1. Analytics — Bento stats grid, contribution heatmap, achievements,
//                  muscle group balance, and exercise trends.
//   2. Sessions  — Chronological list grouped by week/period with calendar strip
//                  and search functionality.

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen>
    with SingleTickerProviderStateMixin {
  final _svc = WorkoutService.instance;

  // Selected time filter
  TimeRangeFilter _selectedFilter = TimeRangeFilter.last30Days;
  // Selected heatmap year
  int _selectedHeatmapYear = DateTime.now().year;

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
      heatmapYear: _selectedHeatmapYear,
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
              selectedHeatmapYear: _selectedHeatmapYear,
              onFilterChanged: (filter) {
                setState(() {
                  _selectedFilter = filter;
                  _cachedVm = null; // Invalidate cache
                });
              },
              onHeatmapYearChanged: (year) {
                setState(() {
                  _selectedHeatmapYear = year;
                  _cachedVm = null; // Invalidate cache
                });
              },
            ),
            _SessionsTab(
              vm: vm,
              service: _svc,
            ),
          ],
        ),
      ),
    );
  }

}

// ─── Analytics Tab ────────────────────────────────────────────────────────────

class _AnalyticsTab extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  final int selectedHeatmapYear;
  final ValueChanged<TimeRangeFilter> onFilterChanged;
  final ValueChanged<int> onHeatmapYearChanged;

  const _AnalyticsTab({
    required this.vm,
    required this.selectedHeatmapYear,
    required this.onFilterChanged,
    required this.onHeatmapYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (vm.allSessions.isEmpty) {
      return const Center(
        child: _EmptyHistoryPlaceholder(
          title: 'No workouts logged yet',
          subtitle: 'Log your first workout session to unlock progression charts and dashboard analytics.',
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
          'Workout Consistency Heatmap',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _HeatmapGrid(
          vm: vm,
          selectedYear: selectedHeatmapYear,
          onYearChanged: onHeatmapYearChanged,
        ),
        const SizedBox(height: 20),

        // Consistency Analytics Dashboard Card
        const Text(
          'Behavioral Consistency Dashboard',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _ConsistencyDashboardCard(vm: vm),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Achievements & Milestones',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KColor.greenDark.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KColor.green.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${vm.achievements.where((a) => a.achieved).length} of ${vm.achievements.length} Unlocked',
                style: const TextStyle(color: KColor.green, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AchievementsList(achievements: vm.achievements),
        const SizedBox(height: 20),

        // Exercise Rankings Card
        const Text(
          'Exercise Rankings',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _ExerciseRankingsCard(vm: vm),
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

class _SessionsTab extends StatefulWidget {
  final WorkoutHistoryViewModel vm;
  final WorkoutService service;

  const _SessionsTab({
    required this.vm,
    required this.service,
  });

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  DateTime? _selectedDate;
  String _searchQuery = '';

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _weekdayName(int weekday) => const [
        '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ][weekday];

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredGroups = <String, List<WorkoutSession>>{};

    widget.vm.chronologicalGroups.forEach((groupName, sessions) {
      final filteredList = sessions.where((s) {
        // Date filter
        if (_selectedDate != null) {
          if (_dateKey(s.date) != _dateKey(_selectedDate!)) return false;
        }
        // Query filter
        if (query.isEmpty) return true;
        if (s.splitDayName.toLowerCase().contains(query)) return true;
        if (s.entries.any((e) => e.exercise.name.toLowerCase().contains(query))) return true;
        if (widget.service.split.name.toLowerCase().contains(query)) return true;
        final wdName = _weekdayName(s.date.weekday).toLowerCase();
        if (wdName.contains(query)) return true;
        if (s.notes?.toLowerCase().contains(query) ?? false) return true;
        return false;
      }).toList();

      if (filteredList.isNotEmpty) {
        filteredGroups[groupName] = filteredList;
      }
    });

    final orderedKeys = ['Today', 'Yesterday', 'This Week', 'Last Week', 'Older']
        .where((k) => filteredGroups.containsKey(k))
        .toList();

    return CustomScrollView(
      slivers: [
        // Calendar mini-strip
        SliverToBoxAdapter(
          child: _CalendarStrip(
            sessions: widget.vm.allSessions,
            selectedDate: _selectedDate,
            onDateSelected: (date) {
              setState(() {
                _selectedDate = _selectedDate != null &&
                        _dateKey(_selectedDate!) == _dateKey(date)
                    ? null
                    : date;
              });
            },
          ),
        ),
        // Search bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by exercise, split, day, notes...',
                hintStyle: const TextStyle(color: KColor.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: KColor.textMuted, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: KColor.textMuted, size: 16),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
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
        if (widget.vm.allSessions.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: _EmptyHistoryPlaceholder(
                title: 'No workouts logged yet',
                subtitle: 'Log a workout session to see your progress charts and history tiles.',
                ctaText: 'Start Workout',
              ),
            ),
          )
        else if (orderedKeys.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.event_busy_rounded, color: KColor.textMuted, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'No sessions match search or filters',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Try widening your search terms or clearing selected calendar date.',
                    style: TextStyle(color: KColor.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KColor.green,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                        _selectedDate = null;
                      });
                    },
                    child: const Text('Clear Search & Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final key = orderedKeys[i];
                final sessions = filteredGroups[key]!;
                return _SessionGroupSection(
                  title: key,
                  sessions: sessions,
                  service: widget.service,
                );
              },
              childCount: orderedKeys.length,
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

class _HeatmapGrid extends StatefulWidget {
  final WorkoutHistoryViewModel vm;
  final int selectedYear;
  final ValueChanged<int> onYearChanged;

  const _HeatmapGrid({
    required this.vm,
    required this.selectedYear,
    required this.onYearChanged,
  });

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

  void _jumpToMonth(int month) {
    final days = widget.vm.heatmapDays;
    int dayIdx = days.indexWhere((d) => d.date.month == month && d.date.year == widget.selectedYear);
    if (dayIdx != -1) {
      final colIdx = (dayIdx / 7).floor();
      final offset = (colIdx * 14.0).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
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
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20),
                    onPressed: () => widget.onYearChanged(widget.selectedYear - 1),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  Text(
                    '${widget.selectedYear}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
                    onPressed: widget.selectedYear >= DateTime.now().year
                        ? null
                        : () => widget.onYearChanged(widget.selectedYear + 1),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              PopupMenuButton<int>(
                icon: const Icon(Icons.calendar_month_rounded, color: KColor.green, size: 18),
                color: KColor.surface,
                tooltip: 'Jump to Month',
                onSelected: _jumpToMonth,
                itemBuilder: (context) {
                  final months = [
                    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                  ];
                  return List.generate(12, (index) {
                    return PopupMenuItem<int>(
                      value: index + 1,
                      child: Text(months[index], style: const TextStyle(color: Colors.white, fontSize: 12)),
                    );
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Weekly Logs', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
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
                      final refVol = widget.vm.percentileVolume90;
                      double relative = 0;
                      if (hasWorkout && refVol > 0) {
                        relative = (day.totalVolume / refVol).clamp(0.0, 1.0);
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
                    final prev = WorkoutService.instance.bestSetBefore(entry.exercise.id, s.date);
                    final isPr = prev == null || top.estimatedOneRepMax > prev.estimatedOneRepMax + 0.01;
                    return sum + (isPr ? 1 : 0);
                  });

                  final workoutProgramName = s.splitDayWeekday == null
                      ? 'Custom Workout'
                      : WorkoutService.instance.split.name;

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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    workoutProgramName,
                                    style: const TextStyle(color: KColor.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    s.splitDayName,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            if (prCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB347).withValues(alpha: 0.15),
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

class _AchievementsList extends StatelessWidget {
  final List<AchievementInfo> achievements;
  const _AchievementsList({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: achievements.length,
        itemBuilder: (context, i) {
          final item = achievements[i];
          final progressRatio = item.targetProgress > 0
              ? (item.currentProgress / item.targetProgress).clamp(0.0, 1.0)
              : 0.0;

          return Container(
            width: 150,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: item.achieved
                    ? KColor.green.withValues(alpha: 0.3)
                    : KColor.border.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Opacity(
                  opacity: item.achieved ? 1.0 : 0.3,
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
                      const SizedBox(height: 1),
                      Text(
                        item.description,
                        style: TextStyle(
                          color: KColor.textSecondary,
                          fontSize: 8,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (!item.achieved && item.targetProgress > 0) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progressRatio,
                            minHeight: 3,
                            backgroundColor: KColor.bg,
                            valueColor: const AlwaysStoppedAnimation<Color>(KColor.green),
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        item.progressLabel,
                        style: TextStyle(
                          color: item.achieved ? KColor.green : KColor.textMuted,
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                        ),
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
        // Find recent history values for line chart, excluding skipped entries
        final history = WorkoutService.instance.historyFor(info.exercise.id, limit: 10)
            .where((h) => !h.entry.isSkipped)
            .toList();
        final values = history.reversed
            .map((h) => h.entry.topProgressionSet?.estimatedOneRepMax ?? h.entry.topWorkingSet?.estimatedOneRepMax ?? h.entry.topSet?.estimatedOneRepMax ?? 0.0)
            .toList();
        final dates = history.reversed.map((h) => h.date).toList();
        final entriesList = history.reversed.map((h) => h.entry).toList();

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
                  _InteractiveLineChart(values: values, dates: dates, entries: entriesList),
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
  final List<ExerciseEntry>? entries;
  const _InteractiveLineChart({required this.values, required this.dates, this.entries});

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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_formatDate(widget.dates[_selectedIndex!])}: ${widget.values[_selectedIndex!].toStringAsFixed(1)} kg',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      if (widget.entries != null && _selectedIndex! < widget.entries!.length) ...[
                        if (widget.entries![_selectedIndex!].isSubstitution) ...[
                          const SizedBox(height: 2),
                          const Text(
                            '🔄 Substituted',
                            style: TextStyle(color: KColor.blue, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                        if (widget.entries![_selectedIndex!].isTemporaryAddition) ...[
                          const SizedBox(height: 2),
                          const Text(
                            '➕ Manually Added',
                            style: TextStyle(color: KColor.amber, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ]
                    ],
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
                  entries: widget.entries,
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
  final List<ExerciseEntry>? entries;
  _LineChartPainter({required this.values, required this.selectedIndex, this.entries});

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

    for (int i = 0; i < points.length; i++) {
      final isSelected = selectedIndex == i;
      Color dotColor = KColor.green;
      if (entries != null && i < entries!.length) {
        final ent = entries![i];
        if (ent.isSubstitution) {
          dotColor = KColor.blue;
        } else if (ent.isTemporaryAddition) {
          dotColor = KColor.amber;
        }
      }
      final dotStrokePaint = Paint()
        ..color = dotColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

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

// ─── Session Group Section ───────────────────────────────────────────────────

class _SessionGroupSection extends StatelessWidget {
  final String title;
  final List<WorkoutSession> sessions;
  final WorkoutService service;

  const _SessionGroupSection({
    required this.title,
    required this.sessions,
    required this.service,
  });


  @override
  Widget build(BuildContext context) {
    final totalVol = sessions.fold<double>(0, (s, w) => s + w.totalWorkingVolume);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: KColor.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
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
          builder: (_) => SessionDetailPage(session: session, service: service),
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

class SessionDetailPage extends StatefulWidget {
  final WorkoutSession session;
  final WorkoutService service;

  const SessionDetailPage({super.key, required this.session, required this.service});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
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
          _buildProgressionContext(),

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

  Widget _buildProgressionContext() {
    WorkoutSession? prevSession;
    final sameSplitSessions = widget.service.sessionsForSplitDay(_currentSession.splitDayName);
    for (final s in sameSplitSessions) {
      if (s.date.isBefore(_currentSession.date)) {
        prevSession = s;
        break;
      }
    }

    int prCount = 0;
    for (final entry in _currentSession.entries) {
      final top = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
      if (top == null) continue;
      final prevBest = widget.service.bestSetBefore(entry.exercise.id, _currentSession.date);
      final isPr = prevBest == null || top.estimatedOneRepMax > prevBest.estimatedOneRepMax + 0.01;
      if (isPr) prCount++;
    }

    if (prevSession == null && prCount == 0) {
      return const SizedBox.shrink();
    }

    final double curVol = _currentSession.totalWorkingVolume;
    final double prevVol = prevSession?.totalWorkingVolume ?? 0;
    final double volDiff = curVol - prevVol;
    final double volDiffPct = prevVol > 0 ? (volDiff / prevVol * 100) : 0;

    final int curSets = _currentSession.totalSets;
    final int prevSets = prevSession?.totalSets ?? 0;
    final int setsDiff = curSets - prevSets;
    final double setsDiffPct = prevSets > 0 ? (setsDiff.toDouble() / prevSets * 100) : 0;

    final int? curDur = _currentSession.durationMinutes;
    final int? prevDur = prevSession?.durationMinutes;
    final int durDiff = (curDur != null && prevDur != null) ? (curDur - prevDur) : 0;
    final double durDiffPct = (prevDur != null && prevDur > 0) ? (durDiff.toDouble() / prevDur * 100) : 0;

    String formatSign(double val) => val >= 0 ? '+${val.toStringAsFixed(0)}%' : '${val.toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Progression Context',
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
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
              if (prevSession != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'vs. Last ${_currentSession.splitDayName} Session',
                      style: const TextStyle(color: KColor.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${prevSession.date.day}/${prevSession.date.month}/${prevSession.date.year}',
                      style: const TextStyle(color: KColor.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ProgressionIndicatorCard(
                      title: 'Volume',
                      pctText: formatSign(volDiffPct),
                      detailText: '${volDiff.abs().toStringAsFixed(0)} kg ${volDiff >= 0 ? 'more' : 'less'}',
                      isPositive: volDiff >= 0,
                    ),
                    const SizedBox(width: 8),
                    _ProgressionIndicatorCard(
                      title: 'Sets',
                      pctText: formatSign(setsDiffPct),
                      detailText: '${setsDiff.abs()} set${setsDiff.abs() == 1 ? '' : 's'} ${setsDiff >= 0 ? 'more' : 'less'}',
                      isPositive: setsDiff >= 0,
                    ),
                    if (curDur != null && prevDur != null) ...[
                      const SizedBox(width: 8),
                      _ProgressionIndicatorCard(
                        title: 'Duration',
                        pctText: formatSign(durDiffPct),
                        detailText: '${durDiff.abs()} min ${durDiff >= 0 ? 'longer' : 'shorter'}',
                        isPositive: durDiff >= 0,
                      ),
                    ],
                  ],
                ),
              ],
              if (prCount > 0) ...[
                if (prevSession != null) ...[
                  const SizedBox(height: 12),
                  const Divider(color: KColor.border, height: 1),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$prCount Personal Record${prCount == 1 ? '' : 's'} broken!',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 1),
                          const Text(
                            'You pushed past your lifetime limits in this session. Keep building!',
                            style: TextStyle(color: KColor.textMuted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
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

class _ProgressionIndicatorCard extends StatelessWidget {
  final String title;
  final String pctText;
  final String detailText;
  final bool isPositive;

  const _ProgressionIndicatorCard({
    required this.title,
    required this.pctText,
    required this.detailText,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = isPositive ? KColor.green : Colors.red;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KColor.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KColor.border.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: KColor.textMuted, fontSize: 9, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: displayColor,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  pctText,
                  style: TextStyle(
                    color: displayColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              detailText,
              style: const TextStyle(color: KColor.textSecondary, fontSize: 8),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
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
        notes: e.notes,
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
                              key: ValueKey('ex-$exIdx-set-$setIdx-weight'),
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
                              key: ValueKey('ex-$exIdx-set-$setIdx-reps'),
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
                              key: ValueKey('ex-$exIdx-set-$setIdx-rpe'),
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

class _EditTextField extends StatefulWidget {
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _EditTextField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_EditTextField> createState() => _EditTextFieldState();
}

class _EditTextFieldState extends State<_EditTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_EditTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: widget.onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        decoration: InputDecoration(
          labelText: widget.label,
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
    final isPr = !entry.isSkipped && topSet != null &&
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.exercise.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.exercise.muscleGroup,
                      style: const TextStyle(color: KColor.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (entry.isSkipped)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        entry.skipReason != null && entry.skipReason!.isNotEmpty
                            ? '🚫 Skipped: ${entry.skipReason}'
                            : '🚫 Skipped',
                        style: const TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (entry.isSubstitution)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: KColor.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        entry.substitutedForExerciseName != null
                            ? '🔄 Substituted for ${entry.substitutedForExerciseName}'
                            : '🔄 Substituted',
                        style: const TextStyle(color: KColor.blue, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (entry.isTemporaryAddition)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: KColor.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '➕ Manually Added',
                        style: TextStyle(color: KColor.green, fontSize: 9, fontWeight: FontWeight.w700),
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
            ],
          ),
          const SizedBox(height: 8),
          if (entry.isSkipped)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Exercise was skipped during workout session.',
                style: TextStyle(color: KColor.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            )
          else ...[
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

class _ConsistencyDashboardCard extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  const _ConsistencyDashboardCard({required this.vm});

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: KColor.green, size: 16),
              const SizedBox(width: 8),
              const Text('Consistency Metrics', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ConsistencyMetricBox(
                title: 'Workouts/Week',
                value: vm.workoutsPerWeek.toStringAsFixed(1),
                icon: Icons.calendar_today_rounded,
                color: const Color(0xFF60A5FA),
              ),
              const SizedBox(width: 8),
              _ConsistencyMetricBox(
                title: 'Avg Day Gap',
                value: vm.averageDaysBetweenWorkouts == 0
                    ? 'N/A'
                    : '${vm.averageDaysBetweenWorkouts.toStringAsFixed(1)}d',
                icon: Icons.hourglass_empty_rounded,
                color: const Color(0xFF34D399),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ConsistencyMetricBox(
                title: 'Missed Sessions',
                value: '${vm.missedPlannedWorkouts}',
                icon: Icons.event_busy_rounded,
                color: const Color(0xFFEF4444),
                subtitle: 'Planned days missed',
              ),
              const SizedBox(width: 8),
              _ConsistencyMetricBox(
                title: 'Top Training Day',
                value: vm.mostCommonTrainingDay,
                icon: Icons.star_border_rounded,
                color: const Color(0xFFFFB347),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConsistencyMetricBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _ConsistencyMetricBox({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KColor.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KColor.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: KColor.textMuted, fontSize: 9)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!, style: const TextStyle(color: KColor.textSecondary, fontSize: 7)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseRankingsCard extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  const _ExerciseRankingsCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final hasRankings = vm.mostTrainedExercise != null ||
        vm.highestVolumeExercise != null ||
        vm.strongestExercise != null;

    if (!hasRankings) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KColor.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
        ),
        child: const Center(
          child: Text(
            'Log some workouts with exercises to see rankings.',
            style: TextStyle(color: KColor.textMuted, fontSize: 11),
          ),
        ),
      );
    }

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
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 16),
              const SizedBox(width: 8),
              const Text('Exercise Records & Rankings', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (vm.mostTrainedExercise != null)
            _RankingRow(
              medal: '🏃',
              title: 'Most Trained',
              exerciseName: vm.mostTrainedExercise!.exercise.name,
              score: '${vm.mostTrainedExercise!.totalSessions} sessions',
            ),
          if (vm.highestVolumeExercise != null) ...[
            const SizedBox(height: 10),
            _RankingRow(
              medal: '🏋️',
              title: 'Highest Volume',
              exerciseName: vm.highestVolumeExercise!.exercise.name,
              score: '${(vm.highestVolumeExercise!.lifetimeVolume / 1000).toStringAsFixed(1)}k kg',
            ),
          ],
          if (vm.strongestExercise != null) ...[
            const SizedBox(height: 10),
            _RankingRow(
              medal: '💪',
              title: 'Strongest (Best 1RM)',
              exerciseName: vm.strongestExercise!.exercise.name,
              score: '${vm.strongestExercise!.bestE1rm.toStringAsFixed(1)} kg',
            ),
          ],
          if (vm.fastestGrowingExercise != null) ...[
            const SizedBox(height: 10),
            _RankingRow(
              medal: '⚡',
              title: 'Fastest Growing',
              exerciseName: vm.fastestGrowingExercise!.exercise.name,
              score: '+${vm.fastestGrowingExercise!.currentTrend.toStringAsFixed(1)} kg recently',
            ),
          ],
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final String medal;
  final String title;
  final String exerciseName;
  final String score;

  const _RankingRow({
    required this.medal,
    required this.title,
    required this.exerciseName,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(medal, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: KColor.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
              const SizedBox(height: 1),
              Text(exerciseName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Text(score, style: const TextStyle(color: KColor.green, fontSize: 11, fontWeight: FontWeight.bold)),
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
