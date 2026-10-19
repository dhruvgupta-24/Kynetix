import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../ui/k_segmented.dart';
import '../models/workout_history_view_model.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/achievement_engine.dart' show AchievementInfo;
import '../services/workout_service.dart';
import '../widgets/muscle_body_map.dart';

// ─── WorkoutHistoryScreen ─────────────────────────────────────────────────────
//
// Dedicated screen for viewing all workout history and dashboard analytics.
// Uses a cached WorkoutHistoryViewModel to avoid redundant computations.
//
// Lives in the Train world. Chrome is monochrome (ink selected states,
// hairlines); data is drawn in ink (series lines, the heatmap, the latest
// bar). PRs wear the ember accent and always carry a trophy glyph and a
// label, never colour alone.
//
// Tabs:
//   1. Analytics — Bento stats grid, contribution heatmap, achievements,
//                  muscle group balance, and exercise trends.
//   2. Sessions  — Timeline of sessions grouped by week with calendar strip
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

  /// Identity of the history the cached view model was computed from. The
  /// service also notifies for things the history screen doesn't show (draft
  /// edits, sleep/HRV sync), and recomputing the view model is the most
  /// expensive thing on this screen, so it's only rebuilt when this changes.
  Object? _vmSource;

  Object _historySignature() => (
    _svc.lastWorkoutsChangedAt,
    _svc.sessions.length,
    _svc.isReady,
    _svc.split.name,
    _svc.trainingDays.map((d) => d.weekday).join(','),
  );

  void _onServiceChange() {
    if (!mounted) return;
    if (_cachedVm != null && _vmSource == _historySignature()) return;
    setState(() {
      _cachedVm = null; // Invalidate cache
    });
  }

  WorkoutHistoryViewModel _getVm() {
    if (_cachedVm == null) _vmSource = _historySignature();
    _cachedVm ??= WorkoutHistoryViewModel.compute(
      service: _svc,
      filter: _selectedFilter,
      heatmapYear: _selectedHeatmapYear,
    );
    return _cachedVm!;
  }

  @override
  Widget build(BuildContext context) {
    // History lives in WorkoutService; until it has hydrated, an empty view
    // model would wrongly read as "nothing logged yet".
    final ready = _svc.isReady;
    return KPage(
      tone: KTone.train,
      body: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.standard),
        switchInCurve: KMotion.emphasizedCurve,
        switchOutCurve: KMotion.accelerate,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: ready
            ? KeyedSubtree(
                key: const ValueKey('history-ready'),
                child: _buildHistory(context, _getVm()),
              )
            : const _HistoryLoading(key: ValueKey('history-loading')),
      ),
    );
  }

  Widget _buildHistory(BuildContext context, WorkoutHistoryViewModel vm) {
    return NestedScrollView(
      headerSliverBuilder: (context, inner) => [
        SliverAppBar(
          backgroundColor: KColor.bg.withValues(alpha: 0.86),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          pinned: true,
          toolbarHeight: 64,
          iconTheme: IconThemeData(color: KColor.textPrimary),
          titleSpacing: 0,
          title: Text(
            'Workout history',
            maxLines: 2,
            style: KText.h2.copyWith(fontSize: 17, height: 1.15),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpacing.lg,
                2,
                KSpacing.lg,
                10,
              ),
              child: _SegmentedTabs(controller: _tabCtrl),
            ),
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
          _SessionsTab(vm: vm, service: _svc),
        ],
      ),
    );
  }
}

/// Waiting state while workout history hydrates: back button, title and the
/// rep loader with an honest line about what is happening.
class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          toolbarHeight: 64,
          iconTheme: IconThemeData(color: KColor.textPrimary),
          titleSpacing: 0,
          title: Text(
            'Workout history',
            style: KText.h2.copyWith(fontSize: 17, height: 1.15),
          ),
        ),
        const Expanded(
          child: KLoaderPanel(
            loader: KRepLoader(size: 64, semanticsLabel: null),
            messages: ['Pulling your history…'],
            semanticsLabel: 'Loading workout history',
          ),
        ),
      ],
    );
  }
}

// ─── Shared private building blocks ──────────────────────────────────────────

const _kTabular = [FontFeature.tabularFigures()];

const _kMonthsShort = [
  '',
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

/// Tabular numeric style at an arbitrary size.
TextStyle _num(
  double size, {
  Color? color,
  FontWeight weight = FontWeight.w700,
}) => KText.numSmall.copyWith(
  fontSize: size,
  color: color ?? KColor.textPrimary,
  fontWeight: weight,
);

/// Card / row hairline: a light seam on Carbon, the warm border on Paper.
/// A getter so it follows the active theme.
Color get _hairline =>
    KColor.isDark ? KColor.fg.withValues(alpha: 0.07) : KColor.border;

/// Chart gridline: faint on Carbon, a touch firmer on Paper so it survives
/// the warm white.
Color get _gridline => KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.1);

/// Neutral inset fill for a row or tile inside a card.
Color get _insetFill =>
    KColor.fg.withValues(alpha: KColor.isDark ? 0.03 : 0.025);

/// Sentence-case form field label.
TextStyle get _formLabel => KText.caption.copyWith(
  fontSize: 13,
  color: KColor.textSecondary,
  fontWeight: FontWeight.w600,
);

/// Analytics / Sessions switch. The thumb rides the TabController's
/// animation, so it tracks a swipe between the two pages.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => KSegmented<int>(
        segments: const [
          KSegment(0, 'Analytics'),
          KSegment(1, 'Sessions'),
        ],
        value: controller.index,
        height: 44,
        position: controller.animation,
        onChanged: (i) => controller.animateTo(
          i,
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.emphasizedCurve,
        ),
      ),
    );
  }
}

/// Section heading with a short ink tick.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: KSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: KRadius.pill,
              color: KColor.ink,
            ),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: KText.h3.copyWith(fontSize: 16)),
            ),
          ),
          if (trailing case final t?) ...[
            const SizedBox(width: KSpacing.sm),
            t,
          ],
        ],
      ),
    );
  }
}

/// Small pill badge: icon + label, tinted by [color]. The icon/label carry
/// the meaning; colour only decorates.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: KColor.isDark ? 0.14 : 0.1),
        borderRadius: KRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: Icon(icon, size: 12, color: color)),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              style: KText.caption.copyWith(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                fontFeatures: _kTabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accent PR marker. Always icon + label.
class _PrBadge extends StatelessWidget {
  const _PrBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => _Badge(
    label: label,
    color: KColor.ember,
    icon: Icons.emoji_events_rounded,
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final WorkoutStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, String label, IconData icon) = switch (status) {
      WorkoutStatus.completed => (
        KColor.green,
        'Completed',
        Icons.check_circle_rounded,
      ),
      WorkoutStatus.partial => (
        KColor.textSecondary,
        'Partial',
        Icons.timelapse_rounded,
      ),
      WorkoutStatus.abandoned => (
        KColor.textMuted,
        'Abandoned',
        Icons.cancel_outlined,
      ),
      WorkoutStatus.active => (
        KColor.ember,
        'Active',
        Icons.play_circle_fill_rounded,
      ),
    };
    return _Badge(label: label, color: color, icon: icon);
  }
}

/// Rounded neutral square holding an icon; only the glyph carries [color].
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color, this.size = 30});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.05),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      ),
    );
  }
}

/// Keeps a tab's subtree (scroll position, one-shot entrance) alive while the
/// other tab is shown.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Plays a one-shot 0→1 draw-in the first time it mounts; cut to the end state
/// under reduced motion. The animation is handed to painters as `repaint:`.
class _DrawIn extends StatefulWidget {
  const _DrawIn({required this.builder});
  final Widget Function(BuildContext context, Animation<double> progress)
  builder;

  @override
  State<_DrawIn> createState() => _DrawInState();
}

class _DrawInState extends State<_DrawIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: KMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final d = KMotion.of(context, KMotion.slow);
    if (d == Duration.zero) {
      _ctrl.value = 1;
    } else {
      _ctrl.duration = d;
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ctrl);
}

/// Shared series renderer: an ink line with a fading ink area, revealed along
/// its path length. Subclasses supply the point offsets for a size.
abstract class _RevealSeriesPainter extends CustomPainter {
  _RevealSeriesPainter(this.reveal) : super(repaint: reveal);

  final Animation<double> reveal;

  /// Palette at construction (painters are rebuilt every build). Compared in
  /// subclasses' shouldRepaint so a theme switch repaints the gridlines.
  final bool dark = KColor.isDark;

  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _area = Paint()..style = PaintingStyle.fill;

  Size? _laidOut;
  List<Offset> offsets = const [];
  Path _linePath = Path();
  Path _areaPath = Path();
  ui.PathMetric? _metric;

  double get strokeWidth => 2.0;
  double get areaAlpha => KColor.isDark ? 0.24 : 0.14;

  List<Offset> computeOffsets(Size size);

  void ensureLayout(Size size) {
    if (_laidOut == size) return;
    _laidOut = size;
    offsets = computeOffsets(size);
    if (offsets.isEmpty) return;
    _linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      _linePath.lineTo(offsets[i].dx, offsets[i].dy);
    }
    _areaPath = Path.from(_linePath)
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();
    final metrics = _linePath.computeMetrics().toList();
    _metric = metrics.isEmpty ? null : metrics.first;
    final rect = Offset.zero & size;
    _line
      ..strokeWidth = strokeWidth
      ..shader = null
      ..color = KColor.ink;
    _area.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        KColor.ink.withValues(alpha: areaAlpha * 0.6),
        KColor.ink.withValues(alpha: 0.0),
      ],
    ).createShader(rect);
  }

  /// Paints the revealed series and returns the x of the line's tip.
  double paintSeries(Canvas canvas, Size size) {
    final metric = _metric;
    if (offsets.length < 2 || metric == null) return size.width;
    final t = KMotion.emphasizedCurve.transform(reveal.value.clamp(0.0, 1.0));
    final done = t >= 1.0;
    final len = metric.length * t;
    final tipX = done
        ? size.width
        : (metric.getTangentForOffset(len)?.position.dx ?? size.width);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, tipX + 0.5, size.height));
    canvas.drawPath(_areaPath, _area);
    canvas.restore();
    canvas.drawPath(done ? _linePath : metric.extractPath(0, len), _line);
    return tipX;
  }

  bool get revealDone => reveal.value >= 1.0;
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
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: const Center(
              child: _EmptyHistoryPlaceholder(
                title: 'Nothing logged yet',
                subtitle:
                    'Your first session sets the tone. Charts, streaks and PRs show up once you save one.',
                ctaText: 'Back to Train',
              ),
            ),
          ),
        ),
      );
    }

    final bottom = MediaQuery.paddingOf(context).bottom + KSpacing.xxxl;
    final unlocked = vm.achievements.where((a) => a.achieved).length;

    // Slivers: the fixed sections lay out lazily, and the exercise directory
    // (one card per exercise, can be dozens) is a lazy builder instead of a
    // shrink-wrapped list that built every card the moment it scrolled near.
    return _KeepAlive(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.lg,
              KSpacing.md,
              KSpacing.lg,
              0,
            ),
            sliver: SliverList.list(
              children: [
                // Time filter chip row
                KReveal(
                  index: 0,
                  child: _FilterChips(
                    selected: vm.filter,
                    onChanged: onFilterChanged,
                  ),
                ),
                const SizedBox(height: KSpacing.lg),

                // Bento Stats Grid
                _KeepAlive(
                  child: KReveal(
                    index: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionHeader('Overview'),
                        _BentoGrid(vm: vm),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KSpacing.sm),
                KReveal(
                  index: 2,
                  child: _HighlightInfoRow(
                    mostTrainedMuscle: vm.mostTrainedMuscle,
                    mostPerformedExercise: vm.mostPerformedExercise,
                  ),
                ),
                const SizedBox(height: KSpacing.xxl),

                // Workout heatmap contribution graph
                _KeepAlive(
                  child: KReveal(
                    index: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionHeader('Workout consistency'),
                        _HeatmapGrid(
                          vm: vm,
                          selectedYear: selectedHeatmapYear,
                          onYearChanged: onHeatmapYearChanged,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KSpacing.xxl),

                // Consistency Analytics Dashboard Card
                const _SectionHeader('Training habits'),
                _KeepAlive(child: _ConsistencyDashboardCard(vm: vm)),
                const SizedBox(height: KSpacing.xxl),

                // Muscle Analytics & neglect detection
                const _SectionHeader('Muscle balance'),
                _KeepAlive(child: _MuscleAnalyticsCard(vm: vm)),
                const SizedBox(height: KSpacing.xxl),

                // Achievements Section
                _SectionHeader(
                  'Achievements',
                  trailing: _Badge(
                    label: '$unlocked of ${vm.achievements.length} unlocked',
                    color: KColor.textSecondary,
                    icon: Icons.lock_open_rounded,
                  ),
                ),
                _KeepAlive(
                  child: _AchievementsList(achievements: vm.achievements),
                ),
                const SizedBox(height: KSpacing.xxl),

                // Exercise Rankings Card
                const _SectionHeader('Exercise rankings'),
                _KeepAlive(child: _ExerciseRankingsCard(vm: vm)),
                const SizedBox(height: KSpacing.xxl),

                // Exercise progression trends directory
                const _SectionHeader('Exercise progression'),
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(KSpacing.lg, 0, KSpacing.lg, bottom),
            sliver: _ExerciseAnalyticsList(vm: vm),
          ),
        ],
      ),
    );
  }
}

// ─── Time filter chips ────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});
  final TimeRangeFilter selected;
  final ValueChanged<TimeRangeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: TimeRangeFilter.values.map((f) {
          final isSelected = selected == f;
          return Padding(
            padding: const EdgeInsets.only(right: KSpacing.sm),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: '${f.label} range',
              excludeSemantics: true,
              child: Pressable(
                borderRadius: KRadius.pill,
                onTap: () {
                  KHaptics.select();
                  onChanged(f);
                },
                child: AnimatedContainer(
                  duration: KMotion.of(context, KMotion.quick),
                  curve: KMotion.emphasizedCurve,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? KColor.ink
                        : (KColor.isDark
                              ? KColor.fg.withValues(alpha: 0.05)
                              : KColor.card),
                    borderRadius: KRadius.pill,
                    border: Border.all(
                      color: isSelected ? KColor.ink : _hairline,
                    ),
                  ),
                  child: Text(
                    f.label,
                    style: KText.caption.copyWith(
                      fontSize: 13,
                      color: isSelected ? KColor.onInk : KColor.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Bento Grid ───────────────────────────────────────────────────────────────
//
// Hierarchy: one hero (workouts), two compact satellites (streak, PRs), one
// wide strip (volume with a per-session area trend), and a footer pair.

class _BentoGrid extends StatelessWidget {
  const _BentoGrid({required this.vm});
  final WorkoutHistoryViewModel vm;

  @override
  Widget build(BuildContext context) {
    final sorted = [...vm.filteredSessions]
      ..sort((a, b) => a.date.compareTo(b.date));
    final volumes = [for (final s in sorted) s.totalWorkingVolume];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 11,
                child: _BentoHero(
                  workouts: vm.totalWorkouts,
                  filterLabel: vm.filter.label,
                  averageDuration: vm.averageDuration,
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                flex: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _BentoCard(
                        title: 'Current streak',
                        value: vm.currentStreak,
                        icon: Icons.local_fire_department_rounded,
                        color: KColor.textSecondary,
                        suffix: 'd',
                        subtitle: vm.currentStreak == 0
                            ? 'Next session starts one'
                            : 'Longest: ${vm.longestStreak}d',
                      ),
                    ),
                    const SizedBox(height: KSpacing.sm),
                    Expanded(
                      child: _BentoCard(
                        title: 'Total PRs',
                        value: vm.totalPrs,
                        icon: Icons.emoji_events_rounded,
                        color: KColor.ember,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KSpacing.sm),
        _BentoVolume(totalVolume: vm.totalVolume, volumes: volumes),
        const SizedBox(height: KSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _BentoCard(
                  title: 'Sets logged',
                  value: vm.totalSets,
                  icon: Icons.playlist_add_check_rounded,
                  color: KColor.textSecondary,
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: _BentoCard(
                  title: 'Training hours',
                  value: vm.totalHours,
                  icon: Icons.timer_rounded,
                  color: KColor.textSecondary,
                  decimals: 1,
                  suffix: 'h',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BentoHero extends StatelessWidget {
  const _BentoHero({
    required this.workouts,
    required this.filterLabel,
    required this.averageDuration,
  });

  final int workouts;
  final String filterLabel;
  final double averageDuration;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Workouts: $workouts in $filterLabel',
      excludeSemantics: true,
      child: KCard(
        padding: const EdgeInsets.all(KSpacing.lg),
        borderRadius: KRadius.xl,
        border: Border.all(
          color: KColor.hairline,
        ),
        color: KColor.card,
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -18,
              child: ExcludeSemantics(
                child: Icon(
                  Icons.fitness_center_rounded,
                  size: 84,
                  color: KColor.ink.withValues(
                    alpha: KColor.isDark ? 0.06 : 0.05,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Workouts',
                  style: KText.caption.copyWith(color: KColor.textSecondary),
                ),
                const SizedBox(height: KSpacing.sm),
                // Solid ink figure: numbers are the hero, never gradient text.
                KAnimatedCount(
                  value: workouts,
                  style: KText.numDisplay.copyWith(fontSize: 48),
                ),
                const SizedBox(height: KSpacing.sm),
                _Badge(
                  label: filterLabel,
                  color: KColor.ink,
                  icon: Icons.date_range_rounded,
                ),
                if (averageDuration > 0) ...[
                  const SizedBox(height: KSpacing.sm),
                  Text(
                    'Avg ${averageDuration.toStringAsFixed(0)} min / session',
                    style: KText.caption.copyWith(
                      fontSize: 12,
                      color: KColor.textSecondary,
                      fontFeatures: _kTabular,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bento Card Stat ──────────────────────────────────────────────────────────

class _BentoCard extends StatelessWidget {
  final String title;
  final num value;
  final IconData icon;
  final Color color;
  final int decimals;
  final String suffix;
  final String? subtitle;

  const _BentoCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.decimals = 0,
    this.suffix = '',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = '${value.toStringAsFixed(decimals)}$suffix';
    return Semantics(
      container: true,
      label: '$title: $valueText${subtitle != null ? ', $subtitle' : ''}',
      excludeSemantics: true,
      child: KCard(
        padding: const EdgeInsets.all(KSpacing.md),
        borderRadius: KRadius.lg,
        boxShadow: const [],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: KText.caption.copyWith(
                      fontSize: 12,
                      color: KColor.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _IconTile(icon: icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: KSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KAnimatedCount(
                  value: value,
                  decimalPlaces: decimals,
                  suffix: suffix,
                  style: KText.numMedium.copyWith(fontSize: 24),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: KText.caption.copyWith(
                      fontSize: 11.5,
                      fontFeatures: _kTabular,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BentoVolume extends StatelessWidget {
  const _BentoVolume({required this.totalVolume, required this.volumes});
  final double totalVolume;
  final List<double> volumes;

  @override
  Widget build(BuildContext context) {
    final hasTrend = volumes.length >= 2;
    final hairline = 1.0 / MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      container: true,
      label:
          'Volume: ${(totalVolume / 1000).toStringAsFixed(1)}k kg across ${plural(volumes.length, 'session')}',
      excludeSemantics: true,
      child: KCard(
        padding: const EdgeInsets.fromLTRB(
          KSpacing.lg,
          KSpacing.md,
          KSpacing.lg,
          KSpacing.md,
        ),
        borderRadius: KRadius.lg,
        boxShadow: const [],
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _IconTile(
                        icon: Icons.scale_rounded,
                        color: KColor.textSecondary,
                        size: 24,
                      ),
                      const SizedBox(width: KSpacing.sm),
                      Flexible(
                        child: Text(
                          'Volume',
                          style: KText.caption.copyWith(
                            fontSize: 12,
                            color: KColor.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KSpacing.sm),
                  KAnimatedCount(
                    value: totalVolume / 1000,
                    decimalPlaces: 1,
                    suffix: 'k kg',
                    style: KText.numMedium.copyWith(fontSize: 24),
                  ),
                ],
              ),
            ),
            if (hasTrend) ...[
              const SizedBox(width: KSpacing.md),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 48,
                      child: RepaintBoundary(
                        child: _DrawIn(
                          builder: (context, progress) => CustomPaint(
                            size: Size.infinite,
                            painter: _SparkPainter(
                              scene: _SparkScene(
                                values: volumes,
                                hairline: hairline,
                              ),
                              reveal: progress,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Per-session volume',
                      style: KText.caption.copyWith(
                        fontSize: 11,
                        color: KColor.textMuted,
                      ),
                    ),
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

@immutable
class _SparkScene {
  const _SparkScene({required this.values, required this.hairline});
  final List<double> values;
  final double hairline;

  @override
  bool operator ==(Object other) =>
      other is _SparkScene &&
      other.hairline == hairline &&
      listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(hairline, Object.hashAll(values));
}

class _SparkPainter extends _RevealSeriesPainter {
  _SparkPainter({required this.scene, required Animation<double> reveal})
    : super(reveal);

  final _SparkScene scene;
  final Paint _base = Paint()..style = PaintingStyle.stroke;
  final Paint _dot = Paint()..style = PaintingStyle.fill;

  @override
  double get strokeWidth => 1.8;

  @override
  List<Offset> computeOffsets(Size size) {
    final v = scene.values;
    if (v.length < 2) return const [];
    final hi = v.reduce(max);
    final lo = min(0.0, v.reduce(min));
    final range = hi - lo == 0 ? 1.0 : hi - lo;
    const pad = 4.0;
    final step = (size.width - 2 * pad) / (v.length - 1);
    return [
      for (var i = 0; i < v.length; i++)
        Offset(
          pad + i * step,
          size.height - pad - ((v[i] - lo) / range) * (size.height - 2 * pad),
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    ensureLayout(size);
    _base
      ..strokeWidth = scene.hairline
      ..color = _gridline;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      _base,
    );
    final tip = paintSeries(canvas, size);
    if (offsets.isNotEmpty && offsets.last.dx <= tip + 0.5) {
      _dot.color = KColor.ember;
      canvas.drawCircle(offsets.last, 3, _dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.dark != dark;
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
    Widget half(IconData icon, Color color, String label, String value) =>
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconTile(icon: icon, color: color, size: 26),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: KText.caption.copyWith(
                        fontSize: 11.5,
                        color: KColor.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: KText.caption.copyWith(
                        fontSize: 13.5,
                        color: KColor.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return KCard(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: KSpacing.md,
      ),
      borderRadius: KRadius.md,
      boxShadow: const [],
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            half(
              Icons.incomplete_circle_rounded,
              KColor.ink,
              'Most trained muscle',
              mostTrainedMuscle,
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: KSpacing.md),
              color: _hairline,
            ),
            half(
              Icons.flash_on_rounded,
              KColor.textSecondary,
              'Most performed exercise',
              mostPerformedExercise,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Heatmap ──────────────────────────────────────────────────────────────────

/// Sequential single-hue ramp in ink, level 0 = empty. The empty cell is a
/// faint ink step so the grid reads on both Graphite and Paper.
List<Color> get _kHeatRamp => [
  KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.08),
  KColor.ink.withValues(alpha: KColor.isDark ? 0.28 : 0.24),
  KColor.ink.withValues(alpha: KColor.isDark ? 0.50 : 0.46),
  KColor.ink.withValues(alpha: KColor.isDark ? 0.74 : 0.70),
  KColor.ink,
];

const double _kHeatCell = 11.0;
const double _kHeatPitch = 14.0;

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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToMonth(int month) {
    final days = widget.vm.heatmapDays;
    int dayIdx = days.indexWhere(
      (d) => d.date.month == month && d.date.year == widget.selectedYear,
    );
    if (dayIdx != -1) {
      final colIdx = (dayIdx / 7).floor();
      final offset = (colIdx * _kHeatPitch).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      final d = KMotion.of(context, KMotion.standard);
      if (d == Duration.zero) {
        _scroll.jumpTo(offset);
      } else {
        _scroll.animateTo(offset, duration: d, curve: KMotion.emphasizedCurve);
      }
    }
  }

  int _levelFor(HeatmapDay day) {
    final hasWorkout = day.sessions.isNotEmpty;
    if (!hasWorkout) return 0;
    final refVol = widget.vm.percentileVolume90;
    double relative = 0;
    if (refVol > 0) {
      relative = (day.totalVolume / refVol).clamp(0.0, 1.0);
    }
    if (relative < 0.25) return 1;
    if (relative < 0.50) return 2;
    if (relative < 0.75) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.vm.heatmapDays;
    final cols = (days.length / 7).ceil();
    final levels = [for (final d in days) _levelFor(d)];
    final trainedDays = levels.where((l) => l > 0).length;

    final now = DateTime.now();
    final todayIndex = days.indexWhere(
      (d) =>
          d.date.year == now.year &&
          d.date.month == now.month &&
          d.date.day == now.day,
    );

    // Month labels at the column that contains the 1st of each month.
    final monthLabels = <(int, String)>[];
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < 7; r++) {
        final i = c * 7 + r;
        if (i >= days.length) break;
        if (days[i].date.day == 1) {
          if (monthLabels.isEmpty || c - monthLabels.last.$1 >= 3) {
            monthLabels.add((c, _kMonthsShort[days[i].date.month]));
          }
          break;
        }
      }
    }

    final width = max(cols * _kHeatPitch, 0.0);
    final scene = _HeatScene(levels: levels, todayIndex: todayIndex);
    final canGoForward = widget.selectedYear < DateTime.now().year;

    return KCard(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.sm,
        KSpacing.sm,
        KSpacing.md,
        KSpacing.md,
      ),
      borderRadius: KRadius.lg,
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous year',
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: KColor.textPrimary,
                  size: 22,
                ),
                onPressed: () {
                  KHaptics.select();
                  widget.onYearChanged(widget.selectedYear - 1);
                },
              ),
              Text('${widget.selectedYear}', style: _num(15)),
              IconButton(
                tooltip: 'Next year',
                icon: Icon(
                  Icons.chevron_right_rounded,
                  color: canGoForward
                      ? KColor.textPrimary
                      : KColor.textDisabled,
                  size: 22,
                ),
                onPressed: !canGoForward
                    ? null
                    : () {
                        KHaptics.select();
                        widget.onYearChanged(widget.selectedYear + 1);
                      },
              ),
              const Spacer(),
              PopupMenuButton<int>(
                icon: Icon(
                  Icons.calendar_month_rounded,
                  color: KColor.textSecondary,
                  size: 20,
                ),
                color: KColor.surface,
                shape: const RoundedRectangleBorder(borderRadius: KRadius.md),
                tooltip: 'Jump to month',
                onSelected: _jumpToMonth,
                itemBuilder: (context) {
                  final months = [
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
                  return List.generate(12, (index) {
                    return PopupMenuItem<int>(
                      value: index + 1,
                      child: Text(
                        months[index],
                        style: KText.body.copyWith(fontSize: 13),
                      ),
                    );
                  });
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: KSpacing.sm),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: KSpacing.md,
              runSpacing: 6,
              children: [
                Text(
                  '$trainedDays training days',
                  style: KText.caption.copyWith(
                    fontSize: 12,
                    color: KColor.textSecondary,
                    fontFeatures: _kTabular,
                  ),
                ),
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Less ',
                        style: KText.caption.copyWith(
                          fontSize: 10.5,
                          color: KColor.textMuted,
                        ),
                      ),
                      for (var l = 0; l <= 4; l++) ...[
                        _HeatmapCellColor(level: l),
                        if (l < 4) const SizedBox(width: 2),
                      ],
                      Text(
                        ' More',
                        style: KText.caption.copyWith(
                          fontSize: 10.5,
                          color: KColor.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            label:
                'Workout heatmap for ${widget.selectedYear}: $trainedDays training days. '
                'Use the Sessions tab calendar for day-by-day detail.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Weekday axis labels (Mon, Wed, Fri).
                ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: KSpacing.sm,
                      right: 6,
                      top: _kHeatPitch,
                    ),
                    child: Column(
                      children: [
                        for (final d in const ['M', '', 'W', '', 'F', '', ''])
                          SizedBox(
                            height: _kHeatPitch,
                            child: Text(
                              d,
                              style: KText.caption.copyWith(
                                fontSize: 10,
                                color: KColor.textSecondary,
                                height: 1.2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ExcludeSemantics(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: _kHeatPitch,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final (c, label) in monthLabels)
                                    Positioned(
                                      left: c * _kHeatPitch,
                                      top: 0,
                                      child: Text(
                                        label,
                                        style: KText.caption.copyWith(
                                          fontSize: 10,
                                          color: KColor.textSecondary,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) {
                                final p = details.localPosition;
                                final col = (p.dx / _kHeatPitch).floor();
                                final row = (p.dy / _kHeatPitch).floor();
                                if (col < 0 || row < 0 || row > 6) return;
                                final idx = col * 7 + row;
                                if (idx < 0 || idx >= days.length) return;
                                _showDayDetails(days[idx]);
                              },
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  size: Size(width, 7 * _kHeatPitch),
                                  painter: _HeatmapPainter(scene),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDayDetails(HeatmapDay day) {
    KHaptics.select();
    showKSheet(
      context: context,
      isScrollControlled: false,
      builder: (context) {
        final dateStr =
            '${day.date.day} ${_monthName(day.date.month)} ${day.date.year}';
        final hasWorkouts = day.sessions.isNotEmpty;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            KSpacing.xl,
            0,
            KSpacing.xl,
            MediaQuery.paddingOf(context).bottom + KSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KDragHandle(),
              const SizedBox(height: KSpacing.sm),
              Row(
                children: [
                  Expanded(child: Text(dateStr, style: KText.h2)),
                  const SizedBox(width: KSpacing.sm),
                  _Badge(
                    label: hasWorkouts
                        ? '${day.sessions.length} workout${day.sessions.length == 1 ? '' : 's'}'
                        : 'Rest day',
                    color: hasWorkouts ? KColor.ink : KColor.textMuted,
                    icon: hasWorkouts
                        ? Icons.fitness_center_rounded
                        : Icons.bedtime_rounded,
                  ),
                ],
              ),
              const SizedBox(height: KSpacing.lg),
              if (!hasWorkouts)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: KSpacing.xl),
                    child: Column(
                      children: [
                        _IconTile(
                          icon: Icons.bedtime_rounded,
                          color: KColor.textSecondary,
                          size: 52,
                        ),
                        const SizedBox(height: KSpacing.md),
                        Text(
                          'Nothing logged this day.',
                          textAlign: TextAlign.center,
                          style: KText.h3.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Rest days count too. That's when the muscle gets built.",
                          textAlign: TextAlign.center,
                          style: KText.caption.copyWith(
                            fontSize: 13,
                            color: KColor.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...day.sessions.map((s) {
                  final totalSets = s.totalSets;
                  final prCount = s.entries.fold<int>(0, (sum, entry) {
                    final top =
                        entry.topProgressionSet ??
                        entry.topWorkingSet ??
                        entry.topSet;
                    if (top == null) return sum;
                    final prev = WorkoutService.instance.bestSetBefore(
                      entry.exercise.id,
                      s.date,
                    );
                    final isPr =
                        prev == null ||
                        top.estimatedOneRepMax > prev.estimatedOneRepMax + 0.01;
                    return sum + (isPr ? 1 : 0);
                  });

                  final workoutProgramName = s.splitDayWeekday == null
                      ? 'Custom workout'
                      : WorkoutService.instance.split.name;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: KSpacing.md),
                    child: KCard(
                      padding: const EdgeInsets.all(14),
                      borderRadius: KRadius.md,
                      boxShadow: const [],
                      border: Border.all(
                        color: prCount > 0
                            ? KColor.ember.withValues(alpha: 0.35)
                            : _hairline,
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
                                      workoutProgramName,
                                      style: KText.caption.copyWith(
                                        fontSize: 12,
                                        color: KColor.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(s.splitDayName, style: KText.h3),
                                  ],
                                ),
                              ),
                              if (prCount > 0) ...[
                                const SizedBox(width: KSpacing.sm),
                                _PrBadge(prCount == 1 ? '1 PR' : '$prCount PRs'),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: KSpacing.md,
                            runSpacing: 6,
                            children: [
                              _DayDetailChip(
                                icon: Icons.fitness_center_rounded,
                                text: plural(totalSets, 'set'),
                              ),
                              _DayDetailChip(
                                icon: Icons.scale_rounded,
                                text:
                                    '${s.totalWorkingVolume.toStringAsFixed(0)} kg',
                              ),
                              if (s.durationMinutes != null)
                                _DayDetailChip(
                                  icon: Icons.timer_rounded,
                                  text: '${s.durationMinutes} min',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  static String _monthName(int m) => const [
    '',
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
  ][m];
}

@immutable
class _HeatScene {
  const _HeatScene({required this.levels, required this.todayIndex});
  final List<int> levels;
  final int todayIndex;

  @override
  bool operator ==(Object other) =>
      other is _HeatScene &&
      other.todayIndex == todayIndex &&
      listEquals(other.levels, levels);

  @override
  int get hashCode => Object.hash(todayIndex, Object.hashAll(levels));
}

/// Paints the whole year grid in one pass (lattice geometry: col = i ~/ 7,
/// row = i % 7) instead of hundreds of Container widgets.
class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter(this.scene);
  final _HeatScene scene;

  /// Palette at construction; a theme switch repaints the empty cells.
  final bool dark = KColor.isDark;

  final Paint _cell = Paint()..style = PaintingStyle.fill;
  final Paint _today = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = KColor.ember;

  static const _radius = Radius.circular(2.5);

  @override
  void paint(Canvas canvas, Size size) {
    final levels = scene.levels;
    for (var i = 0; i < levels.length; i++) {
      final col = i ~/ 7;
      final row = i % 7;
      final rect = Rect.fromLTWH(
        col * _kHeatPitch,
        row * _kHeatPitch,
        _kHeatCell,
        _kHeatCell,
      );
      _cell.color = _kHeatRamp[levels[i].clamp(0, 4)];
      canvas.drawRRect(RRect.fromRectAndRadius(rect, _radius), _cell);
      if (i == scene.todayIndex) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(1.2), _radius),
          _today,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.dark != dark;
}

class _HeatmapCellColor extends StatelessWidget {
  final int level;
  const _HeatmapCellColor({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: _kHeatRamp[level.clamp(0, 4)],
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, color: KColor.textMuted, size: 13)),
        const SizedBox(width: 4),
        Text(
          text,
          style: _num(12, color: KColor.textSecondary, weight: FontWeight.w600),
        ),
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
    final neglected = vm.neglectedMuscles
        .where((m) => m.daysSinceLastTrained > 10)
        .toList();

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      borderRadius: KRadius.xl,
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Training volume balance',
            style: KText.caption.copyWith(
              fontSize: 13,
              color: KColor.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),

          // Anatomical Body Heatmap
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: MuscleBodyMap(
                view: BodyView.sideBySide,
                muscleHeatmap: _computeMuscleHeatmap(vm),
                height: 160,
              ),
            ),
          ),
          const SizedBox(height: KSpacing.lg),

          _BalanceBar(
            title: 'Push vs Pull',
            leftPct: vm.pushPullRatio,
            leftLabel: 'Push ($pushPct%)',
            rightLabel: 'Pull ($pullPct%)',
            leftColor: KColor.ink,
            rightColor: KColor.fat,
          ),
          const SizedBox(height: KSpacing.lg),
          _BalanceBar(
            title: 'Upper vs Lower',
            leftPct: vm.upperLowerRatio,
            leftLabel: 'Upper ($upperPct%)',
            rightLabel: 'Lower ($lowerPct%)',
            leftColor: KColor.ink,
            rightColor: KColor.fat,
          ),
          const SizedBox(height: KSpacing.lg),
          Container(height: 1, color: KColor.divider),
          const SizedBox(height: KSpacing.md),
          Text(
            'Due for some attention',
            style: KText.caption.copyWith(
              color: KColor.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: KSpacing.sm),
          if (neglected.isEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.verified_rounded,
                    color: KColor.green,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Every key muscle group got work recently. Nicely balanced.',
                    style: KText.caption.copyWith(fontSize: 12.5),
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: KSpacing.sm,
              runSpacing: KSpacing.sm,
              children: [
                for (final item in neglected)
                  _Badge(
                    label: item.daysSinceLastTrained == 999
                        ? '${item.muscleGroup}: not yet'
                        : '${item.muscleGroup}: ${item.daysSinceLastTrained}d ago',
                    color: KColor.danger,
                    icon: Icons.warning_amber_rounded,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Map<String, double> _computeMuscleHeatmap(WorkoutHistoryViewModel vm) {
    final heatmap = <String, double>{};
    final maxVol = vm.muscleVolumes.values.fold(0.0, (m, v) => v > m ? v : m);
    if (maxVol <= 0) return heatmap;

    for (final entry in vm.muscleVolumes.entries) {
      final canonical = entry.key.toLowerCase();
      final intensity = (entry.value / maxVol).clamp(0.1, 1.0);
      heatmap[canonical] = intensity;
    }
    return heatmap;
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
    final target = leftPct.isFinite ? leftPct.clamp(0.05, 0.95) : 0.5;
    return Semantics(
      label: '$title: $leftLabel vs $rightLabel',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: KText.caption.copyWith(
              fontSize: 12,
              color: KColor.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 8,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: target),
              duration: KMotion.of(context, KMotion.slow),
              curve: KMotion.emphasizedCurve,
              builder: (context, v, _) => Row(
                children: [
                  Expanded(
                    flex: (v * 1000).round(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: leftColor,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: ((1 - v) * 1000).round(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: rightColor,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _dot(leftColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  leftLabel,
                  style: _num(
                    12,
                    color: KColor.textPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              const Spacer(),
              Flexible(
                child: Text(
                  rightLabel,
                  textAlign: TextAlign.end,
                  style: _num(
                    12,
                    color: KColor.textPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _dot(rightColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

/// Achievement marks from the shared icon language (the engine still carries
/// its legacy emoji; the screen never shows them).
IconData _achievementIcon(String title) {
  final s = title.toLowerCase();
  if (s.contains('streak')) return KIcons.calories;
  if (s.contains('record')) return KIcons.record;
  if (s.contains('heavy')) return KIcons.train;
  if (s.contains('century')) return KIcons.target;
  if (s.contains('first')) return KIcons.baseline;
  return KIcons.record;
}

/// "First Workout" -> "First workout". Display only.
String _sentenceCase(String s) {
  if (s.isEmpty) return s;
  return s[0] + s.substring(1).toLowerCase();
}

class _AchievementsList extends StatelessWidget {
  final List<AchievementInfo> achievements;
  const _AchievementsList({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: achievements.length,
        itemBuilder: (context, i) {
          final item = achievements[i];
          final progressRatio = item.targetProgress > 0
              ? (item.currentProgress / item.targetProgress).clamp(0.0, 1.0)
              : 0.0;

          return Padding(
            padding: const EdgeInsets.only(right: KSpacing.sm),
            child: Semantics(
              container: true,
              label:
                  '${item.title}, ${item.achieved ? 'unlocked' : 'locked'}. ${item.description}. ${item.progressLabel}',
              excludeSemantics: true,
              child: Container(
                width: 172,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: item.achieved ? KColor.cardHigh : KColor.card,
                  borderRadius: KRadius.md,
                  border: Border.all(
                    color: item.achieved
                        ? KColor.ink.withValues(alpha: 0.30)
                        : _hairline,
                  ),
                  boxShadow: KShadow.card,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 30,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Locked badges fade via the glyph colour (no
                          // Opacity layer per list row).
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: KIcon(
                              _achievementIcon(item.title),
                              size: KIcons.lg,
                              color: item.achieved ? KColor.ink : KColor.textMuted.withValues(alpha: KColor.textMuted.a * 0.3),
                            ),
                          ),
                          if (!item.achieved)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Icon(
                                Icons.lock_rounded,
                                size: 12,
                                color: KColor.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: KSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _sentenceCase(item.title),
                            style: KText.caption.copyWith(
                              fontSize: 12.5,
                              color: item.achieved
                                  ? KColor.textPrimary
                                  : KColor.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.description,
                            style: KText.caption.copyWith(
                              fontSize: 11,
                              color: KColor.textSecondary,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          if (!item.achieved && item.targetProgress > 0) ...[
                            KBar(
                              progress: progressRatio,
                              colors: KGradient.primary,
                              height: 4,
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            item.progressLabel,
                            maxLines: 1,
                            style: _num(
                              11,
                              color: item.achieved
                                  ? KColor.textPrimary
                                  : KColor.textMuted,
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
    return SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final item = list[i];
        final deltaLabel = item.currentTrend > 0
            ? '+${item.currentTrend.toStringAsFixed(1)} kg'
            : '${item.currentTrend.toStringAsFixed(1)} kg';
        final trendColor = item.currentTrend > 0
            ? KColor.green
            : item.currentTrend < 0
            ? KColor.danger
            : KColor.textMuted;
        final trendIcon = item.currentTrend > 0
            ? Icons.trending_up_rounded
            : item.currentTrend < 0
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;

        return Padding(
          padding: const EdgeInsets.only(bottom: KSpacing.sm),
          child: Pressable(
            semanticLabel:
                '${item.exercise.name}, ${plural(item.totalSessions, 'session')}, '
                'recent e1RM change $deltaLabel. Open details',
            borderRadius: KRadius.md,
            scale: 0.98,
            onTap: () => _openExerciseDetails(context, item),
            child: KCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: KSpacing.md,
              ),
              borderRadius: KRadius.md,
              boxShadow: const [],
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.exercise.name,
                          style: KText.h3.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${item.exercise.muscleGroup}, ${plural(item.totalSessions, 'session')}',
                          style: KText.caption.copyWith(
                            fontSize: 12,
                            color: KColor.textSecondary,
                            fontFeatures: _kTabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(trendIcon, size: 14, color: trendColor),
                          ),
                          const SizedBox(width: 3),
                          Text(deltaLabel, style: _num(13, color: trendColor)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Recent e1RM change',
                        style: KText.caption.copyWith(
                          fontSize: 11,
                          color: KColor.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: KColor.textMuted,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openExerciseDetails(BuildContext context, ExerciseAnalyticInfo info) {
    showKSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        // Find recent history values for line chart, excluding skipped entries
        final history = WorkoutService.instance
            .historyFor(info.exercise.id, limit: 10)
            .where((h) => !h.entry.isSkipped)
            .toList();
        final values = history.reversed
            .map(
              (h) =>
                  h.entry.topProgressionSet?.estimatedOneRepMax ??
                  h.entry.topWorkingSet?.estimatedOneRepMax ??
                  h.entry.topSet?.estimatedOneRepMax ??
                  0.0,
            )
            .toList();
        final dates = history.reversed.map((h) => h.date).toList();
        final entriesList = history.reversed.map((h) => h.entry).toList();

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollCtrl) {
            return Column(
              children: [
                Stack(
                  children: [
                    KSheetHeader(
                      info.exercise.name,
                      subtitle: info.exercise.muscleGroup,
                    ),
                    Positioned(
                      top: 0,
                      right: KSpacing.sm,
                      child: IconButton(
                        tooltip: 'Close',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          color: KColor.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      KSpacing.xl,
                      0,
                      KSpacing.xl,
                      MediaQuery.paddingOf(context).bottom + KSpacing.xxxl,
                    ),
                    children: [
                      const SizedBox(height: KSpacing.md),

                      // Stats bento: varied emphasis — best e1RM leads.
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _DetailStatBox(
                                title: 'Best estimated 1RM',
                                value: '${info.bestE1rm.toStringAsFixed(1)} kg',
                                emphasis: true,
                              ),
                            ),
                            const SizedBox(width: KSpacing.sm),
                            Expanded(
                              child: _DetailStatBox(
                                title: 'Total sessions',
                                value: '${info.totalSessions}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: KSpacing.sm),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _DetailStatBox(
                                title: 'Lifetime volume',
                                value:
                                    '${(info.lifetimeVolume / 1000).toStringAsFixed(1)}k kg',
                              ),
                            ),
                            const SizedBox(width: KSpacing.sm),
                            Expanded(
                              child: _DetailStatBox(
                                title: 'Best set',
                                value: info.bestSet != null
                                    ? '${info.bestSet!.weight.toStringAsFixed(0)}x${info.bestSet!.reps}'
                                    : '-',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: KSpacing.xl),

                      // Insights section
                      if (info.insights.isNotEmpty) ...[
                        const _SectionHeader('Insights'),
                        Column(
                          children: info.insights.map((insight) {
                            return Container(
                              margin: const EdgeInsets.only(
                                bottom: KSpacing.sm,
                              ),
                              padding: const EdgeInsets.all(KSpacing.md),
                              decoration: BoxDecoration(
                                color: KColor.ink.withValues(
                                  alpha: KColor.isDark ? 0.05 : 0.04,
                                ),
                                borderRadius: KRadius.sm,
                                border: Border.all(
                                  color: KColor.ink.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ExcludeSemantics(
                                    child: Icon(
                                      Icons.lightbulb_rounded,
                                      color: KColor.ink,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: KSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      insight,
                                      style: KText.caption.copyWith(
                                        fontSize: 13,
                                        color: KColor.textPrimary,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: KSpacing.lg),
                      ],

                      // Interactive Chart
                      const _SectionHeader('Estimated 1RM over time'),
                      if (values.length < 2)
                        Container(
                          height: 100,
                          padding: const EdgeInsets.symmetric(
                            horizontal: KSpacing.lg,
                          ),
                          decoration: BoxDecoration(
                            color: KColor.card,
                            borderRadius: KRadius.md,
                            border: Border.all(color: _hairline),
                          ),
                          child: Center(
                            child: Text(
                              'One more session and the trend shows up here.',
                              textAlign: TextAlign.center,
                              style: KText.caption.copyWith(
                                fontSize: 13,
                                color: KColor.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else
                        _InteractiveLineChart(
                          values: values,
                          dates: dates,
                          entries: entriesList,
                        ),
                    ],
                  ),
                ),
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
  final bool emphasis;
  const _DetailStatBox({
    required this.title,
    required this.value,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KSpacing.md),
      decoration: BoxDecoration(
        color: emphasis ? KColor.cardHigh : KColor.card,
        borderRadius: KRadius.md,
        border: Border.all(
          color: emphasis ? KColor.ink.withValues(alpha: 0.30) : _hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: KText.caption.copyWith(
              fontSize: 12,
              color: KColor.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: emphasis ? KText.numMedium.copyWith(fontSize: 20) : _num(16),
          ),
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
  const _InteractiveLineChart({
    required this.values,
    required this.dates,
    this.entries,
  });

  @override
  State<_InteractiveLineChart> createState() => _InteractiveLineChartState();
}

class _InteractiveLineChartState extends State<_InteractiveLineChart>
    with SingleTickerProviderStateMixin {
  int? _selectedIndex;
  late final AnimationController _reveal;
  bool _revealStarted = false;

  static const double _plotHeight = 150;
  static const double _axisWidth = 36;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this, duration: KMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_revealStarted) return;
    _revealStarted = true;
    final d = KMotion.of(context, KMotion.slow);
    if (d == Duration.zero) {
      _reveal.value = 1;
    } else {
      _reveal.duration = d;
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  List<int> get _markers {
    final entries = widget.entries;
    return [
      for (var i = 0; i < widget.values.length; i++)
        if (entries != null && i < entries.length && entries[i].isSubstitution)
          1
        else if (entries != null &&
            i < entries.length &&
            entries[i].isTemporaryAddition)
          2
        else
          0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.values.isEmpty) return const SizedBox.shrink();
    final values = widget.values;
    final markers = _markers;
    final hasSubs = markers.contains(1);
    final hasAdded = markers.contains(2);

    final hi = values.reduce(max);
    final lo = values.reduce(min);
    final decimals = (hi - lo) < 10 ? 1 : 0;
    final scene = _LineScene(
      values: values,
      markers: markers,
      selectedIndex: _selectedIndex,
      hairline: 1.0 / MediaQuery.devicePixelRatioOf(context),
    );
    final sel = _selectedIndex;
    final axisStyle = _num(
      10.5,
      color: KColor.textSecondary,
      weight: FontWeight.w600,
    );

    return KCard(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.md,
        14,
        KSpacing.lg,
        KSpacing.md,
      ),
      borderRadius: KRadius.lg,
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scrub tooltip / hint
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: (sel != null && sel < values.length)
                  ? Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: KColor.cardHigh,
                          borderRadius: KRadius.sm,
                          border: Border.all(color: _hairline),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatDate(widget.dates[sel])}: ${values[sel].toStringAsFixed(1)} kg',
                              style: _num(13),
                            ),
                            if (widget.entries != null &&
                                sel < widget.entries!.length) ...[
                              if (widget.entries![sel].isSubstitution) ...[
                                const SizedBox(height: 2),
                                const _MarkerLabel(
                                  kind: 1,
                                  text: 'Substituted',
                                ),
                              ],
                              if (widget.entries![sel].isTemporaryAddition) ...[
                                const SizedBox(height: 2),
                                const _MarkerLabel(
                                  kind: 2,
                                  text: 'Manually added',
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    )
                  : Text(
                      'Touch and drag to inspect each session',
                      style: KText.caption.copyWith(
                        fontSize: 12,
                        color: KColor.textSecondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: KSpacing.sm),
          SizedBox(
            height: _plotHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Y axis (kg) labels at the three hairline levels.
                SizedBox(
                  width: _axisWidth,
                  child: ExcludeSemantics(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final (y, v) in _LineGeometry.axisLevels(
                          _plotHeight,
                          hi,
                          lo,
                        ))
                          Positioned(
                            right: 6,
                            top: y - 7,
                            child: Text(
                              v.toStringAsFixed(decimals),
                              style: axisStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final geo = _LineGeometry(
                        box.maxWidth,
                        _plotHeight,
                        values.length,
                      );
                      return Semantics(
                        label:
                            'Estimated 1RM chart: ${values.first.toStringAsFixed(1)} kg on '
                            '${_formatDate(widget.dates.first)} to ${values.last.toStringAsFixed(1)} kg on '
                            '${_formatDate(widget.dates.last)}, ${plural(values.length, 'session')}',
                        child: ExcludeSemantics(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) => _handleTouch(
                              geo.indexAt(details.localPosition.dx),
                            ),
                            onPanDown: (details) => _handleTouch(
                              geo.indexAt(details.localPosition.dx),
                            ),
                            onTapUp: (_) =>
                                setState(() => _selectedIndex = null),
                            onPanEnd: (_) =>
                                setState(() => _selectedIndex = null),
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: Size(box.maxWidth, _plotHeight),
                                isComplex: true,
                                painter: _LineChartPainter(
                                  scene: scene,
                                  reveal: _reveal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // X axis (date) labels.
          Padding(
            padding: const EdgeInsets.only(left: _axisWidth),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Text(_formatDate(widget.dates.first), style: axisStyle),
                  Expanded(
                    child: Text(
                      'kg · e1RM',
                      textAlign: TextAlign.center,
                      style: KText.caption.copyWith(
                        fontSize: 10.5,
                        color: KColor.textMuted,
                      ),
                    ),
                  ),
                  Text(_formatDate(widget.dates.last), style: axisStyle),
                ],
              ),
            ),
          ),
          if (hasSubs || hasAdded) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: KSpacing.md,
              runSpacing: 4,
              children: [
                if (hasSubs) const _MarkerLabel(kind: 1, text: 'Substituted'),
                if (hasAdded)
                  const _MarkerLabel(kind: 2, text: 'Manually added'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _handleTouch(int? idx) {
    if (idx == null) return;
    if (idx != _selectedIndex) {
      KHaptics.select();
      setState(() {
        _selectedIndex = idx;
      });
    }
  }

  String _formatDate(DateTime d) => '${d.day} ${_shortMonth(d.month)}';
  static String _shortMonth(int m) => [
    '',
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
  ][m];
}

/// Legend / tooltip marker: shape + colour + word (substituted = diamond,
/// manually added = square).
class _MarkerLabel extends StatelessWidget {
  const _MarkerLabel({required this.kind, required this.text});
  final int kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = kind == 1 ? KColor.blue : KColor.ember;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Transform.rotate(
            angle: kind == 1 ? 0.785398 : 0,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(Radius.circular(1.5)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: KText.caption.copyWith(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The single index ↔ pixel mapping shared by painter and touch handler.
@immutable
class _LineGeometry {
  const _LineGeometry(this.width, this.height, this.count);
  final double width;
  final double height;
  final int count;

  static const double insetX = 8;
  static const double padY = 12;

  double get _step => count <= 1 ? 0 : (width - 2 * insetX) / (count - 1);

  double xFor(int i) => count <= 1 ? width / 2 : insetX + i * _step;

  double yFor(double v, double hi, double lo) {
    if (hi == lo) return height / 2;
    return height - padY - ((v - lo) / (hi - lo)) * (height - 2 * padY);
  }

  int? indexAt(double dx) {
    if (count <= 0 || width <= 0) return null;
    if (count == 1) return 0;
    return ((dx - insetX) / _step).round().clamp(0, count - 1);
  }

  /// Gridline y positions with their axis values (top, middle, bottom).
  static List<(double, double)> axisLevels(
    double height,
    double hi,
    double lo,
  ) {
    if (hi == lo) return [(height / 2, hi)];
    return [(padY, hi), (height / 2, (hi + lo) / 2), (height - padY, lo)];
  }
}

@immutable
class _LineScene {
  const _LineScene({
    required this.values,
    required this.markers,
    required this.selectedIndex,
    required this.hairline,
  });

  final List<double> values;
  final List<int> markers;
  final int? selectedIndex;
  final double hairline;

  @override
  bool operator ==(Object other) =>
      other is _LineScene &&
      other.selectedIndex == selectedIndex &&
      other.hairline == hairline &&
      listEquals(other.values, values) &&
      listEquals(other.markers, markers);

  @override
  int get hashCode => Object.hash(
    selectedIndex,
    hairline,
    Object.hashAll(values),
    Object.hashAll(markers),
  );
}

class _LineChartPainter extends _RevealSeriesPainter {
  _LineChartPainter({required this.scene, required Animation<double> reveal})
    : super(reveal);

  final _LineScene scene;

  final Paint _grid = Paint()..style = PaintingStyle.stroke;
  final Paint _dotFill = Paint()..style = PaintingStyle.fill;
  final Paint _dotStroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  final Paint _cross = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Path _shape = Path();
  List<double> _gridYs = const [];

  @override
  List<Offset> computeOffsets(Size size) {
    final v = scene.values;
    if (v.isEmpty) return const [];
    final hi = v.reduce(max);
    final lo = v.reduce(min);
    _gridYs = [
      for (final (y, _) in _LineGeometry.axisLevels(size.height, hi, lo)) y,
    ];
    final geo = _LineGeometry(size.width, size.height, v.length);
    return [
      for (var i = 0; i < v.length; i++)
        Offset(geo.xFor(i), geo.yFor(v[i], hi, lo)),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.values.isEmpty || size.isEmpty) return;
    ensureLayout(size);

    // Hairline grid at the labelled axis levels.
    _grid
      ..strokeWidth = scene.hairline
      ..color = _gridline;
    for (final y in _gridYs) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _grid);
    }

    final tip = offsets.length > 1 ? paintSeries(canvas, size) : size.width;

    final sel = scene.selectedIndex;
    if (sel != null && sel < offsets.length && revealDone) {
      _cross.color = KColor.fg.withValues(alpha: dark ? 0.22 : 0.26);
      canvas.drawLine(
        Offset(offsets[sel].dx, 0),
        Offset(offsets[sel].dx, size.height),
        _cross,
      );
    }

    for (var i = 0; i < offsets.length; i++) {
      final pt = offsets[i];
      if (pt.dx > tip + 0.5) break;
      final isSelected = sel == i;
      final kind = i < scene.markers.length ? scene.markers[i] : 0;
      final color = switch (kind) {
        1 => KColor.blue,
        2 => KColor.ember,
        _ => KColor.ink,
      };
      final r = isSelected ? 5.5 : 3.8;

      if (isSelected) {
        _dotFill.color = KColor.ink.withValues(alpha: dark ? 0.18 : 0.12);
        canvas.drawCircle(pt, 11, _dotFill);
      }
      _dotFill.color = KColor.card;
      _dotStroke.color = isSelected ? KColor.textPrimary : color;

      if (kind == 0) {
        canvas.drawCircle(pt, r, _dotFill);
        canvas.drawCircle(pt, r, _dotStroke);
      } else {
        // Diamond (substituted) or square (manually added) — shape, not only hue.
        _shape.reset();
        if (kind == 1) {
          _shape
            ..moveTo(pt.dx, pt.dy - r - 1)
            ..lineTo(pt.dx + r + 1, pt.dy)
            ..lineTo(pt.dx, pt.dy + r + 1)
            ..lineTo(pt.dx - r - 1, pt.dy)
            ..close();
        } else {
          _shape.addRect(Rect.fromCircle(center: pt, radius: r));
        }
        canvas.drawPath(_shape, _dotFill);
        canvas.drawPath(_shape, _dotStroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.dark != dark;
}

// ─── Calendar Strip (month view) ──────────────────────────────────────────────

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
  late Set<String> _sessionDates;

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
    final daysInMonth = DateTime(
      _displayMonth.year,
      _displayMonth.month + 1,
      0,
    ).day;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();
    var trainedThisMonth = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      if (_hasSession(DateTime(_displayMonth.year, _displayMonth.month, d))) {
        trainedThisMonth++;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.lg,
        KSpacing.md,
        KSpacing.lg,
        KSpacing.sm,
      ),
      child: KCard(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, KSpacing.md),
        borderRadius: KRadius.xl,
        boxShadow: const [],
        child: Column(
          children: [
            // Month navigation
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: KColor.textSecondary,
                  ),
                  onPressed: () {
                    KHaptics.select();
                    setState(
                      () => _displayMonth = DateTime(
                        _displayMonth.year,
                        _displayMonth.month - 1,
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${_monthName(_displayMonth.month)} ${_displayMonth.year}',
                        textAlign: TextAlign.center,
                        style: KText.h3.copyWith(fontFeatures: _kTabular),
                      ),
                      Text(
                        '$trainedThisMonth training ${trainedThisMonth == 1 ? 'day' : 'days'}',
                        textAlign: TextAlign.center,
                        style: KText.caption.copyWith(
                          fontSize: 12,
                          color: KColor.textSecondary,
                          fontFeatures: _kTabular,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: KColor.textSecondary,
                  ),
                  onPressed: () {
                    KHaptics.select();
                    setState(
                      () => _displayMonth = DateTime(
                        _displayMonth.year,
                        _displayMonth.month + 1,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Day headers
            ExcludeSemantics(
              child: Row(
                children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: KText.label.copyWith(
                              fontSize: 11,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 4),
            // Grid
            for (int row = 0; row < rows; row++)
              Row(
                children: List.generate(7, (col) {
                  final cell = row * 7 + col;
                  if (cell < startOffset || cell >= startOffset + daysInMonth) {
                    return const Expanded(child: SizedBox(height: 40));
                  }
                  final day = cell - startOffset + 1;
                  final date = DateTime(
                    _displayMonth.year,
                    _displayMonth.month,
                    day,
                  );
                  final trained = _hasSession(date);
                  final isToday = _dateKey(date) == _dateKey(now);
                  final isSelected =
                      widget.selectedDate != null &&
                      _dateKey(date) == _dateKey(widget.selectedDate!);

                  return Expanded(
                    child: Semantics(
                      button: trained,
                      selected: isSelected,
                      label:
                          '$day ${_monthName(_displayMonth.month)}'
                          '${trained ? ', workout logged' : ''}${isToday ? ', today' : ''}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: trained
                            ? () {
                                KHaptics.select();
                                widget.onDateSelected(date);
                              }
                            : null,
                        child: AnimatedContainer(
                          duration: KMotion.of(context, KMotion.quick),
                          curve: KMotion.emphasizedCurve,
                          margin: const EdgeInsets.all(2),
                          height: 36,
                          // Selected = ink; trained = an ink tint + dot;
                          // today = a hairline ring.
                          decoration: BoxDecoration(
                            color: isSelected
                                ? KColor.ink
                                : trained
                                ? KColor.ink.withValues(
                                    alpha: KColor.isDark ? 0.10 : 0.07,
                                  )
                                : Colors.transparent,
                            borderRadius: KRadius.sm,
                            border: isToday && !isSelected
                                ? Border.all(
                                    color: KColor.fg.withValues(alpha: 0.45),
                                  )
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: _num(
                                  12,
                                  color: isSelected
                                      ? KColor.onInk
                                      : trained
                                      ? KColor.textPrimary
                                      : KColor.textMuted,
                                  weight: trained
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              if (trained && !isSelected)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: KColor.ink,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  static String _monthName(int m) => const [
    '',
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
  ][m];
}

// ─── Sessions Tab ─────────────────────────────────────────────────────────────

class _SessionsTab extends StatefulWidget {
  final WorkoutHistoryViewModel vm;
  final WorkoutService service;

  const _SessionsTab({required this.vm, required this.service});

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  DateTime? _selectedDate;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _weekdayName(int weekday) => const [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Splits the "Older" bucket into calendar weeks (Monday start) so the
  /// timeline reads week by week. Other groups keep their existing labels.
  static List<(String, List<WorkoutSession>)> _weekBuckets(
    List<String> orderedKeys,
    Map<String, List<WorkoutSession>> groups,
  ) {
    final now = DateTime.now();
    final out = <(String, List<WorkoutSession>)>[];
    for (final key in orderedKeys) {
      final sessions = groups[key]!;
      if (key != 'Older') {
        out.add((key, sessions));
        continue;
      }
      final byWeek = <String, List<WorkoutSession>>{};
      final titles = <String, String>{};
      for (final s in sessions) {
        final day = DateTime(s.date.year, s.date.month, s.date.day);
        final monday = day.subtract(Duration(days: day.weekday - 1));
        final k = _dateKey(monday);
        byWeek.putIfAbsent(k, () => []).add(s);
        titles[k] =
            'Week of ${monday.day} ${_kMonthsShort[monday.month]}'
            '${monday.year != now.year ? ' ${monday.year}' : ''}';
      }
      byWeek.forEach((k, list) => out.add((titles[k]!, list)));
    }
    return out;
  }

  void _clearAll() {
    setState(() {
      _searchQuery = '';
      _selectedDate = null;
      _searchCtrl.clear();
    });
  }

  // Filtered buckets, memoised on what they depend on: the calendar tap,
  // focus changes and parent rebuilds no longer re-filter and re-bucket the
  // whole history; a keystroke filters once.
  Object? _bucketsKey;
  List<(String, List<WorkoutSession>)> _bucketsCache = const [];

  List<(String, List<WorkoutSession>)> _filteredBuckets() {
    final query = _searchQuery.trim().toLowerCase();
    final key = (widget.vm, widget.service.split.name, query, _selectedDate == null ? null : _dateKey(_selectedDate!));
    if (key == _bucketsKey) return _bucketsCache;
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
        if (s.entries.any(
          (e) => e.exercise.name.toLowerCase().contains(query),
        )) {
          return true;
        }
        if (widget.service.split.name.toLowerCase().contains(query)) {
          return true;
        }
        final wdName = _weekdayName(s.date.weekday).toLowerCase();
        if (wdName.contains(query)) return true;
        if (s.notes?.toLowerCase().contains(query) ?? false) return true;
        return false;
      }).toList();

      if (filteredList.isNotEmpty) {
        filteredGroups[groupName] = filteredList;
      }
    });

    final orderedKeys = [
      'Today',
      'Yesterday',
      'This Week',
      'Last Week',
      'Older',
    ].where((k) => filteredGroups.containsKey(k)).toList();
    _bucketsKey = key;
    return _bucketsCache = _weekBuckets(orderedKeys, filteredGroups);
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _filteredBuckets();
    final bottom = MediaQuery.paddingOf(context).bottom + 48;

    return CustomScrollView(
      slivers: [
        // Calendar mini-strip
        SliverToBoxAdapter(
          child: _CalendarStrip(
            sessions: widget.vm.allSessions,
            selectedDate: _selectedDate,
            onDateSelected: (date) {
              setState(() {
                _selectedDate =
                    _selectedDate != null &&
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
            padding: const EdgeInsets.symmetric(
              horizontal: KSpacing.lg,
              vertical: KSpacing.sm,
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: KText.body.copyWith(fontSize: 14),
              cursorColor: KColor.ink,
              decoration: InputDecoration(
                hintText: 'Search exercise, split, day or notes…',
                hintStyle: KText.body.copyWith(
                  fontSize: 14,
                  color: KColor.textMuted,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: KColor.textMuted,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: Icon(
                          Icons.clear_rounded,
                          color: KColor.textMuted,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchCtrl.clear();
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: KColor.isDark
                    ? KColor.fg.withValues(alpha: 0.05)
                    : KColor.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: KRadius.pill,
                  borderSide: BorderSide(color: _hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: KRadius.pill,
                  borderSide: BorderSide(color: _hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: KRadius.pill,
                  borderSide: BorderSide(color: KColor.ink, width: 1.4),
                ),
              ),
            ),
          ),
        ),
        if (widget.vm.allSessions.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: _EmptyHistoryPlaceholder(
                title: 'Nothing logged yet',
                subtitle:
                    'Your sessions land here once you save one. The first one sets the tone.',
                ctaText: 'Back to Train',
              ),
            ),
          )
        else if (buckets.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: KEmptyState(
              type: KEmptyStateType.general,
              title: 'No matches',
              message: 'Try a different search, or clear the date you picked.',
              actionLabel: 'Clear filters',
              onAction: _clearAll,
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              final (title, sessions) = buckets[i];
              return _SessionGroupSection(
                title: title,
                sessions: sessions,
                service: widget.service,
              );
            }, childCount: buckets.length),
          ),
        SliverPadding(padding: EdgeInsets.only(bottom: bottom)),
      ],
    );
  }
}

// ─── Session Group Section (one week on the timeline) ─────────────────────────

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
    final totalVol = sessions.fold<double>(
      0,
      (s, w) => s + w.totalWorkingVolume,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, 0, KSpacing.lg, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, KSpacing.lg, 0, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    // Sentence case: 'This Week' → 'This week'; 'Week of …'
                    // already reads correctly.
                    child: Text(
                      title.replaceAll(' Week', ' week'),
                      style: KText.h3.copyWith(
                        fontSize: 14,
                        color: KColor.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KSpacing.sm),
                Flexible(
                  child: Text(
                    '${sessions.length} · ${totalVol.toStringAsFixed(0)} kg total',
                    textAlign: TextAlign.end,
                    style: _num(
                      12,
                      color: KColor.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < sessions.length; i++)
            _SessionTile(
              session: sessions[i],
              service: service,
              isFirst: i == 0,
              isLast: i == sessions.length - 1,
            ),
        ],
      ),
    );
  }
}

// ─── Session Tile (timeline node + card) ──────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final WorkoutSession session;
  final WorkoutService service;
  final bool isFirst;
  final bool isLast;

  const _SessionTile({
    required this.session,
    required this.service,
    this.isFirst = false,
    this.isLast = false,
  });

  String _formatDate(DateTime d) {
    final days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      '',
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
    return '${days[d.weekday]}, ${months[d.month]} ${d.day}';
  }

  static const double _rail = 26;

  @override
  Widget build(BuildContext context) {
    final totalSets = session.totalSets;
    final volume = session.totalWorkingVolume;
    final duration = session.durationMinutes;
    final prs = _countPrsInSession();
    final hasPr = prs > 0;
    final prLabel = '$prs PR${prs > 1 ? 's' : ''}';

    return Stack(
      children: [
        // Timeline rail
        if (!(isFirst && isLast))
          Positioned(
            left: 8,
            top: isFirst ? 22 : 0,
            bottom: isLast ? null : 0,
            height: isLast ? 22 : null,
            child: Container(
              width: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    KColor.ink.withValues(
                      alpha: KColor.isDark ? 0.40 : 0.32,
                    ),
                    KColor.ink.withValues(alpha: KColor.isDark ? 0.14 : 0.12),
                  ],
                ),
              ),
            ),
          ),
        // Node
        Positioned(
          left: hasPr ? 0 : 3.5,
          top: hasPr ? 13 : 17.5,
          child: ExcludeSemantics(
            child: hasPr
                ? Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: KColor.ember,
                      shape: BoxShape.circle,
                      border: Border.all(color: KColor.bg, width: 2),
                    ),
                    child: Icon(
                      Icons.emoji_events_rounded,
                      size: 11,
                      color: KColor.onAccent,
                    ),
                  )
                : Container(
                    width: 10.5,
                    height: 10.5,
                    decoration: BoxDecoration(
                      color: KColor.bg,
                      shape: BoxShape.circle,
                      border: Border.all(color: KColor.ink, width: 2),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _rail, bottom: KSpacing.sm),
          child: Pressable(
            semanticLabel:
                '${session.splitDayName}, ${_formatDate(session.date)}, '
                '${whole(volume)} kg, ${plural(totalSets, 'set')}'
                '${duration != null ? ', $duration minutes' : ''}'
                '${hasPr ? ', $prLabel' : ''}. Open session',
            borderRadius: KRadius.lg,
            scale: 0.98,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SessionDetailPage(session: session, service: service),
              ),
            ),
            child: KCard(
              padding: const EdgeInsets.all(14),
              borderRadius: KRadius.lg,
              boxShadow: const [],
              border: Border.all(
                color: hasPr
                    ? KColor.ember.withValues(alpha: 0.38)
                    : _hairline,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date block
                  Container(
                    width: 44,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: _insetFill,
                      borderRadius: KRadius.sm,
                      border: Border.all(color: _hairline),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${session.date.day}',
                          style: _num(17, weight: FontWeight.w800),
                        ),
                        Text(
                          _kMonthsShort[session.date.month],
                          style: KText.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: KColor.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.splitDayName,
                          style: KText.h3.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(session.date),
                          style: KText.caption.copyWith(
                            fontSize: 12,
                            color: KColor.textMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          children: [
                            if (duration != null)
                              _StatChip(
                                icon: Icons.timer_rounded,
                                label: '${duration}m',
                              ),
                            _StatChip(
                              icon: Icons.scale_rounded,
                              label: '${volume.toStringAsFixed(0)} kg',
                            ),
                            _StatChip(
                              icon: Icons.fitness_center_rounded,
                              label: plural(totalSets, 'set'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _StatusBadge(session.status),
                            if (hasPr) _PrBadge(prLabel),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: KColor.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// PR counts per session, valid while the workout history is unchanged.
  /// Counting walks the whole history for every exercise in the session, so
  /// it must not rerun every time a tile scrolls back into view.
  static final _prCache = Expando<(DateTime, int)>('sessionPrs');

  int _countPrsInSession() {
    final stamp = service.lastWorkoutsChangedAt;
    final cached = _prCache[session];
    if (cached != null && cached.$1 == stamp) return cached.$2;
    final count = _computePrs();
    _prCache[session] = (stamp, count);
    return count;
  }

  int _computePrs() {
    int count = 0;
    for (final entry in session.entries) {
      final top =
          entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
      if (top == null) continue;
      final prev = service.bestSetBefore(entry.exercise.id, session.date);
      if (prev == null ||
          top.estimatedOneRepMax > prev.estimatedOneRepMax + 0.01) {
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
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: Icon(icon, color: KColor.textMuted, size: 14)),
      const SizedBox(width: 4),
      Text(
        label,
        style: _num(13, color: KColor.textSecondary, weight: FontWeight.w600),
      ),
    ],
  );
}

// ─── Session Detail & Edit Page ───────────────────────────────────────────────

class SessionDetailPage extends StatefulWidget {
  final WorkoutSession session;
  final WorkoutService service;

  const SessionDetailPage({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  late WorkoutSession _currentSession;
  bool _enableRpeTracking = false;

  @override
  void initState() {
    super.initState();
    _currentSession = widget.session;
    _loadRpeSetting();
  }

  void _loadRpeSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _enableRpeTracking = prefs.getBool('enable_rpe_tracking') ?? false;
      });
    }
  }

  List<Widget> _buildPlannedList() {
    final style = KText.caption.copyWith(
      fontSize: 13,
      color: KColor.textSecondary,
      height: 1.35,
    );
    final list = _currentSession.plannedExercises;
    if (list == null || list.isEmpty) {
      final fallback = _currentSession.entries
          .where((e) => !e.isTemporaryAddition && !e.isSubstitution)
          .map((e) => e.exercise)
          .toList();
      if (fallback.isEmpty) {
        return [
          Text(
            'No plan recorded',
            style: KText.caption.copyWith(
              fontSize: 12.5,
              color: KColor.textMuted,
            ),
          ),
        ];
      }
      return List.generate(fallback.length, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${index + 1}. ${fallback[index].name}',
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      });
    }
    return List.generate(list.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          '${index + 1}. ${list[index].name}',
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    });
  }

  List<Widget> _buildExecutedList() {
    int displayIndex = 1;
    return _currentSession.entries.map((entry) {
      final name = entry.exercise.name;
      String statusText = '';
      Color statusColor = KColor.textPrimary;

      if (entry.isSkipped) {
        statusText = ' (Skipped)';
        statusColor = KColor.danger;
      } else if (entry.isTemporaryAddition) {
        statusText = ' (Added)';
        statusColor = KColor.green;
      } else if (entry.isSubstitution) {
        statusText = ' (Replaced)';
        statusColor = KColor.blue;
      }

      final idx = displayIndex++;

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(
            style: KText.caption.copyWith(fontSize: 13, height: 1.35),
            children: [
              TextSpan(
                text: '$idx. $name',
                style: TextStyle(
                  color: entry.isSkipped
                      ? KColor.textMuted
                      : KColor.textPrimary,
                  decoration: entry.isSkipped
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              if (statusText.isNotEmpty)
                TextSpan(
                  text: statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }).toList();
  }

  String _formatDate(DateTime d) {
    const days = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[d.weekday]}, ${months[d.month]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _currentSession.durationMinutes;
    final volume = _currentSession.totalWorkingVolume;
    final bottom = MediaQuery.paddingOf(context).bottom + 40;

    return KPage(
      tone: KTone.train,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Flexible(
              child: Text(
                _currentSession.splitDayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: KText.h3.copyWith(fontSize: 16),
              ),
            ),
            const SizedBox(width: KSpacing.sm),
            _StatusBadge(_currentSession.status),
          ],
        ),
        leading: BackButton(color: KColor.textSecondary),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: Icon(Icons.edit_rounded, color: KColor.textPrimary, size: 16),
            label: Text(
              'Edit',
              style: KText.bodyMedium.copyWith(
                color: KColor.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: _openEditSessionScreen,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          KSpacing.lg,
          KSpacing.sm,
          KSpacing.lg,
          bottom,
        ),
        children: [
          // Session meta (hero)
          KReveal(
            index: 0,
            child: KCard(
              padding: const EdgeInsets.all(KSpacing.lg),
              borderRadius: KRadius.xl,
              border: Border.all(
                color: KColor.hairline,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.event_rounded,
                          size: 14,
                          color: KColor.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _formatDate(_currentSession.date),
                          style: KText.caption.copyWith(
                            color: KColor.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailStat(
                        label: 'Volume',
                        value: '${volume.toStringAsFixed(0)} kg',
                      ),
                      _DetailStat(
                        label: 'Total sets',
                        value: '${_currentSession.totalSets}',
                      ),
                      if (duration != null)
                        _DetailStat(label: 'Duration', value: '${duration}m'),
                    ],
                  ),
                  if (_currentSession.notes != null &&
                      _currentSession.notes!.isNotEmpty) ...[
                    const SizedBox(height: KSpacing.md),
                    Container(height: 1, color: KColor.divider),
                    const SizedBox(height: KSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.notes_rounded,
                            color: KColor.textMuted,
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: KSpacing.sm),
                        Expanded(
                          child: Text(
                            _currentSession.notes!,
                            style: KText.caption.copyWith(
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: KSpacing.lg),

          // Planned vs Executed Structure Section
          KReveal(
            index: 1,
            child: KCard(
              padding: const EdgeInsets.all(KSpacing.lg),
              borderRadius: KRadius.lg,
              boxShadow: const [],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Planned vs. executed',
                    style: KText.h3.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: KSpacing.md),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Planned Workout Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Planned',
                                style: KText.caption.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: KColor.textMuted,
                                ),
                              ),
                              const SizedBox(height: KSpacing.sm),
                              ..._buildPlannedList(),
                            ],
                          ),
                        ),
                        const SizedBox(width: KSpacing.md),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: _hairline,
                        ),
                        const SizedBox(width: KSpacing.md),
                        // Executed Workout Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Executed',
                                style: KText.caption.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: KColor.textPrimary,
                                ),
                              ),
                              const SizedBox(height: KSpacing.sm),
                              ..._buildExecutedList(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KSpacing.lg),

          KReveal(index: 2, child: _buildProgressionContext()),

          // Exercise breakdown timeline
          const _SectionHeader('Exercises'),
          for (final entry in _currentSession.entries)
            if (!entry.isEmpty || entry.isSkipped || entry.isSubstitution)
              _ExerciseDetailCard(
                entry: entry,
                service: widget.service,
                sessionDate: _currentSession.date,
                splitDayName: _currentSession.splitDayName,
                enableRpeTracking: _enableRpeTracking,
              ),
        ],
      ),
    );
  }

  Widget _buildProgressionContext() {
    WorkoutSession? prevSession;
    final sameSplitSessions = widget.service.sessionsForSplitDay(
      _currentSession.splitDayName,
    );
    for (final s in sameSplitSessions) {
      if (s.date.isBefore(_currentSession.date)) {
        prevSession = s;
        break;
      }
    }

    int prCount = 0;
    for (final entry in _currentSession.entries) {
      final top =
          entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
      if (top == null) continue;
      final prevBest = widget.service.bestSetBefore(
        entry.exercise.id,
        _currentSession.date,
      );
      final isPr = WorkoutService.beatsPreviousBest(top, prevBest);
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
    final double setsDiffPct = prevSets > 0
        ? (setsDiff.toDouble() / prevSets * 100)
        : 0;

    final int? curDur = _currentSession.durationMinutes;
    final int? prevDur = prevSession?.durationMinutes;
    final int durDiff = (curDur != null && prevDur != null)
        ? (curDur - prevDur)
        : 0;
    final double durDiffPct = (prevDur != null && prevDur > 0)
        ? (durDiff.toDouble() / prevDur * 100)
        : 0;

    String formatSign(double val) =>
        val >= 0 ? '+${val.toStringAsFixed(0)}%' : '${val.toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Compared with last time'),
        KCard(
          padding: const EdgeInsets.all(KSpacing.lg),
          borderRadius: KRadius.lg,
          boxShadow: const [],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (prevSession != null) ...[
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: KSpacing.sm,
                  runSpacing: 4,
                  children: [
                    Text(
                      'vs. last ${_currentSession.splitDayName} session',
                      style: KText.caption.copyWith(
                        fontSize: 13,
                        color: KColor.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${prevSession.date.day}/${prevSession.date.month}/${prevSession.date.year}',
                      style: _num(
                        12,
                        color: KColor.textSecondary,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.md),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProgressionIndicatorCard(
                        title: 'Volume',
                        pctText: formatSign(volDiffPct),
                        detailText:
                            '${volDiff.abs().toStringAsFixed(0)} kg ${volDiff >= 0 ? 'more' : 'less'}',
                        isPositive: volDiff >= 0,
                      ),
                      const SizedBox(width: KSpacing.sm),
                      _ProgressionIndicatorCard(
                        title: 'Sets',
                        pctText: formatSign(setsDiffPct),
                        detailText:
                            '${setsDiff.abs()} set${setsDiff.abs() == 1 ? '' : 's'} ${setsDiff >= 0 ? 'more' : 'less'}',
                        isPositive: setsDiff >= 0,
                      ),
                      if (curDur != null && prevDur != null) ...[
                        const SizedBox(width: KSpacing.sm),
                        _ProgressionIndicatorCard(
                          title: 'Duration',
                          pctText: formatSign(durDiffPct),
                          detailText:
                              '${durDiff.abs()} min ${durDiff >= 0 ? 'longer' : 'shorter'}',
                          isPositive: durDiff >= 0,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (prCount > 0) ...[
                if (prevSession != null) ...[
                  const SizedBox(height: KSpacing.md),
                  Container(height: 1, color: KColor.divider),
                  const SizedBox(height: KSpacing.md),
                ],
                Container(
                  padding: const EdgeInsets.all(KSpacing.md),
                  decoration: BoxDecoration(
                    color: KColor.ember.withValues(
                      alpha: KColor.isDark ? 0.08 : 0.07,
                    ),
                    borderRadius: KRadius.md,
                    border: Border.all(
                      color: KColor.ember.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IconTile(
                        icon: Icons.emoji_events_rounded,
                        color: KColor.ember,
                        size: 32,
                      ),
                      const SizedBox(width: KSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$prCount personal record${prCount == 1 ? '' : 's'} broken',
                              style: KText.h3.copyWith(fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'New bests in this one. Keep building.',
                              style: KText.caption.copyWith(
                                fontSize: 12.5,
                                color: KColor.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: KSpacing.xxl),
      ],
    );
  }

  void _openEditSessionScreen() async {
    final toaster = KToaster.of(context);
    final updated = await Navigator.of(context).push<WorkoutSession>(
      kRiseRoute<WorkoutSession>(
        builder: (_) => _EditSessionScreen(session: _currentSession),
      ),
    );
    if (updated != null) {
      await widget.service.saveSession(updated);
      if (!mounted) return;
      setState(() {
        _currentSession = updated;
      });
      KHaptics.success();
      toaster.show('Changes saved.', kind: KToastKind.success);
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
    final displayColor = isPositive ? KColor.green : KColor.danger;
    return Expanded(
      child: Semantics(
        container: true,
        label: '$title $pctText, $detailText',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: KColor.bg.withValues(alpha: KColor.isDark ? 0.6 : 1),
            borderRadius: KRadius.sm,
            border: Border.all(color: _hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: KText.caption.copyWith(
                  fontSize: 12,
                  color: KColor.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isPositive
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: displayColor,
                    size: 14,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      pctText,
                      style: _num(
                        14.5,
                        color: displayColor,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                detailText,
                style: KText.caption.copyWith(
                  fontSize: 11,
                  color: KColor.textSecondary,
                  fontFeatures: _kTabular,
                ),
              ),
            ],
          ),
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
        Text(
          label,
          style: KText.caption.copyWith(
            fontSize: 12,
            color: KColor.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: KText.numMedium.copyWith(fontSize: 22)),
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
  late List<Exercise> _exercises;
  late List<List<SetEntry>> _editableSets;
  late List<String?> _exerciseNotes;
  late DateTime _date;
  bool _enableRpeTracking = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _durationCtrl = TextEditingController(
      text: widget.session.durationMinutes?.toString() ?? '45',
    );
    _notesCtrl = TextEditingController(text: widget.session.notes ?? '');
    _date = widget.session.date;
    _loadRpeSetting();

    _exercises = widget.session.entries.map((e) => e.exercise).toList();
    _exerciseNotes = widget.session.entries.map((e) => e.notes).toList();
    _editableSets = widget.session.entries
        .map((e) => List<SetEntry>.from(e.sets))
        .toList();
  }

  void _loadRpeSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _enableRpeTracking = prefs.getBool('enable_rpe_tracking') ?? false;
      });
    }
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<ExerciseEntry> _buildEntries() {
    return List.generate(_exercises.length, (i) {
      return ExerciseEntry(
        exercise: _exercises[i],
        sets: _editableSets[i],
        notes: _exerciseNotes[i],
      );
    });
  }

  InputDecoration _fieldDecoration({String? hint, String? suffix}) =>
      InputDecoration(
        filled: true,
        fillColor: KColor.isDark
            ? KColor.bg.withValues(alpha: 0.7)
            : KColor.cardHigh.withValues(alpha: 0.6),
        hintText: hint,
        hintStyle: KText.body.copyWith(fontSize: 13.5, color: KColor.textMuted),
        suffixText: suffix,
        suffixStyle: KText.caption.copyWith(
          fontSize: 12,
          color: KColor.textMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KSpacing.md,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: KRadius.sm,
          borderSide: BorderSide(color: _hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: KRadius.sm,
          borderSide: BorderSide(color: _hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: KRadius.sm,
          borderSide: BorderSide(color: KColor.ink, width: 1.4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return KPage(
      tone: KTone.train,
      intensity: 0.7,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text('Edit session', style: KText.h3.copyWith(fontSize: 16)),
        leading: IconButton(
          tooltip: 'Discard changes',
          icon: Icon(Icons.close, color: KColor.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: Icon(Icons.check, color: KColor.textPrimary),
            onPressed: _saving
                ? null
                : () {
                    KHaptics.commit();
                    _saveChanges();
                  },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          KSpacing.lg,
          KSpacing.md,
          KSpacing.lg,
          bottomInset + KSpacing.md,
        ),
        decoration: BoxDecoration(
          color: KColor.surface.withValues(alpha: 0.92),
          border: Border(top: BorderSide(color: KColor.divider)),
        ),
        child: KButton(
          label: 'Save changes',
          icon: Icons.check_rounded,
          loading: _saving,
          onTap: _saving ? null : _saveChanges,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          KSpacing.lg,
          KSpacing.sm,
          KSpacing.lg,
          KSpacing.xxl,
        ),
        children: [
          // Basic fields
          const _SectionHeader('Session details'),
          KCard(
            padding: const EdgeInsets.all(KSpacing.lg),
            borderRadius: KRadius.lg,
            boxShadow: const [],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Workout date', style: _formLabel),
                const SizedBox(height: 6),
                Pressable(
                  semanticLabel:
                      'Workout date ${_date.day}/${_date.month}/${_date.year}. Change date',
                  borderRadius: KRadius.sm,
                  scale: 0.98,
                  onTap: _selectDate,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: KSpacing.md,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: KColor.isDark
                          ? KColor.bg.withValues(alpha: 0.7)
                          : KColor.cardHigh.withValues(alpha: 0.6),
                      borderRadius: KRadius.sm,
                      border: Border.all(color: _hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          color: KColor.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_date.day}/${_date.month}/${_date.year}',
                            style: _num(14),
                          ),
                        ),
                        Text(
                          'Change',
                          style: KText.caption.copyWith(
                            fontSize: 13,
                            color: KColor.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KSpacing.lg),
                Text('Duration (mins)', style: _formLabel),
                const SizedBox(height: 6),
                TextField(
                  controller: _durationCtrl,
                  keyboardType: TextInputType.number,
                  style: _num(14),
                  cursorColor: KColor.ink,
                  decoration: _fieldDecoration(suffix: 'min'),
                ),
                const SizedBox(height: KSpacing.lg),
                Text('Session notes', style: _formLabel),
                const SizedBox(height: 6),
                TextField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  style: KText.body.copyWith(fontSize: 14),
                  cursorColor: KColor.ink,
                  decoration: _fieldDecoration(
                    hint: 'How did it feel? Anything to remember…',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KSpacing.xxl),

          // Exercise Sets editor
          const _SectionHeader('Sets'),
          ...List.generate(_exercises.length, (exIdx) {
            final exercise = _exercises[exIdx];
            final setsList = _editableSets[exIdx];
            return Padding(
              padding: const EdgeInsets.only(bottom: KSpacing.md),
              child: KCard(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, KSpacing.md),
                borderRadius: KRadius.lg,
                boxShadow: const [],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            exercise.name,
                            style: KText.h3.copyWith(fontSize: 14),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove ${exercise.name}',
                          icon: Icon(
                            Icons.delete_outline,
                            color: KColor.danger,
                            size: 18,
                          ),
                          onPressed: () {
                            KHaptics.select();
                            setState(() {
                              _exercises.removeAt(exIdx);
                              _editableSets.removeAt(exIdx);
                              _exerciseNotes.removeAt(exIdx);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    ...List.generate(setsList.length, (setIdx) {
                      final set = setsList[setIdx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6.0, right: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: KColor.fg.withValues(
                                  alpha: KColor.isDark ? 0.07 : 0.06,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${setIdx + 1}',
                                style: _num(11, color: KColor.textSecondary),
                              ),
                            ),
                            const SizedBox(width: KSpacing.sm),
                            Expanded(
                              child: _EditTextField(
                                key: ValueKey('ex-$exIdx-set-$setIdx-weight'),
                                label: 'kg',
                                initialValue: set.weight.toString(),
                                onChanged: (val) {
                                  final d = double.tryParse(val) ?? 0.0;
                                  final cur = setsList[setIdx];
                                  setsList[setIdx] = SetEntry(
                                    weight: d,
                                    reps: cur.reps,
                                    rpe: cur.rpe,
                                    setType: cur.setType,
                                  );
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
                                  final cur = setsList[setIdx];
                                  setsList[setIdx] = SetEntry(
                                    weight: cur.weight,
                                    reps: r,
                                    rpe: cur.rpe,
                                    setType: cur.setType,
                                  );
                                },
                              ),
                            ),
                            if (_enableRpeTracking) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: _EditTextField(
                                  key: ValueKey('ex-$exIdx-set-$setIdx-rpe'),
                                  label: 'RPE',
                                  initialValue: set.rpe?.toString() ?? '',
                                  onChanged: (val) {
                                    final r = double.tryParse(val);
                                    final cur = setsList[setIdx];
                                    setsList[setIdx] = SetEntry(
                                      weight: cur.weight,
                                      reps: cur.reps,
                                      rpe: r,
                                      setType: cur.setType,
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            DropdownButton<SetType>(
                              value: set.setType,
                              dropdownColor: KColor.surface,
                              isDense: true,
                              borderRadius: KRadius.sm,
                              underline: const SizedBox.shrink(),
                              iconSize: 18,
                              iconEnabledColor: KColor.textMuted,
                              style: KText.caption.copyWith(
                                color: KColor.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              items: SetType.values.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(t.shortLabel),
                                );
                              }).toList(),
                              onChanged: (newType) {
                                if (newType != null) {
                                  KHaptics.select();
                                  setState(() {
                                    final cur = setsList[setIdx];
                                    setsList[setIdx] = SetEntry(
                                      weight: cur.weight,
                                      reps: cur.reps,
                                      rpe: cur.rpe,
                                      setType: newType,
                                    );
                                  });
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Remove set ${setIdx + 1}',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: KColor.textMuted,
                                size: 17,
                              ),
                              onPressed: () {
                                setState(() {
                                  setsList.removeAt(setIdx);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: KColor.textPrimary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: KRadius.pill,
                        ),
                        side: BorderSide(
                          color: KColor.fg.withValues(
                            alpha: KColor.isDark ? 0.18 : 0.2,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        minimumSize: const Size(0, 48),
                      ),
                      icon: Icon(
                        Icons.add,
                        size: 16,
                        color: KColor.textPrimary,
                      ),
                      label: Text(
                        'Add set',
                        style: KText.caption.copyWith(
                          fontSize: 13,
                          color: KColor.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        KHaptics.select();
                        setState(() {
                          final lastSet = setsList.isNotEmpty
                              ? setsList.last
                              : const SetEntry(weight: 20, reps: 10);
                          setsList.add(
                            SetEntry(
                              weight: lastSet.weight,
                              reps: lastSet.reps,
                              setType: SetType.normal,
                            ),
                          );
                        });
                      },
                    ),
                  ],
                ),
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
          // Follows the active palette; the selected day is an ink pill.
          data: Theme.of(context).copyWith(
            colorScheme: KColor.isDark
                ? ColorScheme.dark(
                    primary: KColor.ink,
                    onPrimary: KColor.onInk,
                    surface: KColor.surface,
                    onSurface: KColor.textPrimary,
                  )
                : ColorScheme.light(
                    primary: KColor.ink,
                    onPrimary: KColor.onInk,
                    surface: KColor.surface,
                    onSurface: KColor.textPrimary,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (d != null && mounted) {
      setState(() => _date = d);
    }
  }

  Future<void> _saveChanges() async {
    if (_saving) return;
    setState(() => _saving = true);
    final dur = int.tryParse(_durationCtrl.text) ?? 45;
    final updated = WorkoutSession(
      id: widget.session.id,
      date: _date,
      splitDayName: widget.session.splitDayName,
      splitDayWeekday: widget.session.splitDayWeekday,
      wasManuallySelected: widget.session.wasManuallySelected,
      entries: _buildEntries(),
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      durationMinutes: dur,
      status: widget.session.status,
      plannedExercises: widget.session.plannedExercises,
    );

    await WorkoutService.instance.saveSession(updated);
    if (mounted) {
      // The detail page pushed this route typed <WorkoutSession>, so the
      // result must be the session (popping `true` would be a type error).
      Navigator.pop(context, updated);
    }
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
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: _num(14),
      cursorColor: KColor.ink,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: KColor.isDark
            ? KColor.bg.withValues(alpha: 0.7)
            : KColor.cardHigh.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KSpacing.sm,
          vertical: 11,
        ),
        suffixText: widget.label,
        suffixStyle: KText.caption.copyWith(
          fontSize: 11,
          color: KColor.textMuted,
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: _hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: _hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: KColor.ink, width: 1.4),
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
  final String splitDayName;
  final bool enableRpeTracking;

  const _ExerciseDetailCard({
    required this.entry,
    required this.service,
    required this.sessionDate,
    required this.splitDayName,
    required this.enableRpeTracking,
  });

  @override
  Widget build(BuildContext context) {
    final topSet =
        entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
    final prevBest = service.bestSetBefore(entry.exercise.id, sessionDate);
    final isPr =
        !entry.isSkipped &&
        topSet != null &&
        WorkoutService.beatsPreviousBest(topSet, prevBest);

    final badges = <Widget>[
      if (entry.isSkipped)
        _Badge(
          label: entry.skipReason != null && entry.skipReason!.isNotEmpty
              ? 'Skipped: ${entry.skipReason}'
              : 'Skipped',
          color: KColor.danger,
          icon: Icons.block_rounded,
        ),
      if (entry.isSubstitution)
        _Badge(
          label: entry.substitutedForExerciseName != null
              ? 'Substituted for ${entry.substitutedForExerciseName}'
              : 'Substituted',
          color: KColor.blue,
          icon: Icons.swap_horiz_rounded,
        ),
      if (entry.isTemporaryAddition)
        _Badge(
          label: 'Manually added',
          color: KColor.green,
          icon: Icons.add_circle_outline_rounded,
        ),
      if (!entry.isSkipped && entry.logicalSets.isNotEmpty)
        entry.isCompleted
            ? _Badge(
                label: 'Trained',
                color: KColor.green,
                icon: Icons.check_rounded,
              )
            : _Badge(
                label: 'Logged',
                color: KColor.textMuted,
                icon: Icons.edit_note_rounded,
              ),
      if (isPr) const _PrBadge('New PR'),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KCard(
        padding: const EdgeInsets.all(14),
        borderRadius: KRadius.lg,
        boxShadow: const [],
        border: Border.all(
          color: isPr ? KColor.ember.withValues(alpha: 0.40) : _hairline,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.exercise.name, style: KText.h3.copyWith(fontSize: 15.5)),
            const SizedBox(height: 2),
            Text(
              entry.exercise.muscleGroup,
              style: KText.caption.copyWith(
                fontSize: 12,
                color: KColor.textSecondary,
              ),
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: KSpacing.sm),
              Wrap(spacing: 6, runSpacing: 6, children: badges),
            ],
            const SizedBox(height: 10),
            if (entry.isSkipped)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  'Skipped this session.',
                  style: KText.caption.copyWith(
                    fontSize: 12.5,
                    color: KColor.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else ...[
              // Hierarchical set list
              for (int i = 0; i < entry.logicalSets.length; i++) ...[
                Builder(
                  builder: (context) {
                    final group = entry.logicalSets[i];
                    final set = group.mainSet;
                    final typeColor = _setTypeColor(set.setType);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                constraints: const BoxConstraints(minWidth: 24),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(
                                    alpha: KColor.isDark ? 0.14 : 0.1,
                                  ),
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  set.setType.shortLabel,
                                  style: KText.caption.copyWith(
                                    color: typeColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: KSpacing.sm),
                              Expanded(
                                child: Wrap(
                                  spacing: KSpacing.sm,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${set.loadLabel} × ${plural(set.reps, 'rep')}',
                                      style: _num(
                                        14,
                                        color: KColor.textPrimary,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                    if (enableRpeTracking && set.rpe != null)
                                      Text(
                                        'RPE ${set.rpe!.toStringAsFixed(1)}',
                                        style: _num(
                                          11.5,
                                          color: KColor.textMuted,
                                          weight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: KSpacing.sm),
                              Text(
                                '${set.estimatedOneRepMax.toStringAsFixed(1)} e1RM',
                                style: _num(
                                  11.5,
                                  color: KColor.textMuted,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (group.subSets.isNotEmpty) ...[
                            for (int d = 0; d < group.subSets.length; d++) ...[
                              Builder(
                                builder: (context) {
                                  final drop = group.subSets[d];
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      left: 18,
                                      top: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        ExcludeSemantics(
                                          child: Icon(
                                            Icons
                                                .subdirectory_arrow_right_rounded,
                                            color: KColor.ember,
                                            size: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: KColor.ember.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius:
                                                const BorderRadius.all(
                                                  Radius.circular(5),
                                                ),
                                          ),
                                          child: Text(
                                            group.subSets.length > 1
                                                ? 'Drop ${d + 1}'
                                                : 'Drop',
                                            style: KText.caption.copyWith(
                                              color: KColor.ember,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${drop.loadLabel} × ${plural(drop.reps, 'rep')}',
                                            style: _num(
                                              13,
                                              color: KColor.textSecondary,
                                              weight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: KSpacing.sm),
                                        Text(
                                          '${drop.volume.toStringAsFixed(0)} kg',
                                          style: _num(
                                            11,
                                            color: KColor.textMuted,
                                            weight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
              // e1RM trend for this exercise
              const SizedBox(height: 6),
              _ExerciseSparkline(
                exerciseId: entry.exercise.id,
                service: service,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _setTypeColor(SetType t) => switch (t) {
    SetType.normal => KColor.ink,
    SetType.warmUp => KColor.blue,
    SetType.dropSet => KColor.ember,
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

    return Semantics(
      label: 'e1RM history, latest ${history.last.toStringAsFixed(1)} kg',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: KColor.bg.withValues(alpha: 0.5),
          borderRadius: KRadius.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'e1RM history',
                    style: KText.caption.copyWith(
                      fontSize: 11,
                      color: KColor.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 24,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: history
                          .map(
                            (v) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                child: Container(
                                  height: v == 0
                                      ? 3
                                      : (v / maxVal * 22)
                                            .clamp(3, 22)
                                            .toDouble(),
                                  decoration: BoxDecoration(
                                    color: v == history.last
                                        ? KColor.ink
                                        : KColor.fg.withValues(
                                            alpha: KColor.isDark ? 0.14 : 0.12,
                                          ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KSpacing.md),
            Text(
              '${history.last.toStringAsFixed(1)} kg',
              style: _num(13, color: KColor.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsistencyDashboardCard extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  const _ConsistencyDashboardCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      borderRadius: KRadius.lg,
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(
                icon: Icons.analytics_outlined,
                color: KColor.ink,
                size: 26,
              ),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Text(
                  'Consistency',
                  style: KText.caption.copyWith(
                    color: KColor.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.lg),
          // Lead metric: cadence, the number that drives everything else.
          Semantics(
            container: true,
            label:
                'Workouts per week: ${vm.workoutsPerWeek.toStringAsFixed(1)}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  vm.workoutsPerWeek.toStringAsFixed(1),
                  style: KText.numDisplay.copyWith(fontSize: 38),
                ),
                const SizedBox(width: KSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'workouts a week',
                      style: KText.caption.copyWith(
                        fontSize: 13,
                        color: KColor.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ConsistencyMetricBox(
                  title: 'Average gap',
                  value: vm.averageDaysBetweenWorkouts == 0
                      ? '-'
                      : '${vm.averageDaysBetweenWorkouts.toStringAsFixed(1)}d',
                  icon: Icons.hourglass_empty_rounded,
                  color: KColor.textSecondary,
                ),
                const SizedBox(width: KSpacing.sm),
                _ConsistencyMetricBox(
                  title: 'Days off plan',
                  value: '${vm.missedPlannedWorkouts}',
                  icon: Icons.event_busy_rounded,
                  color: KColor.textSecondary,
                  subtitle: 'Life happens. The next one counts.',
                ),
              ],
            ),
          ),
          const SizedBox(height: KSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ConsistencyMetricBox(
                  title: 'Most common day',
                  value: vm.mostCommonTrainingDay,
                  icon: Icons.star_border_rounded,
                  color: KColor.ink,
                ),
              ],
            ),
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
      child: Semantics(
        container: true,
        label: '$title: $value${subtitle != null ? ', $subtitle' : ''}',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: KColor.bg.withValues(alpha: KColor.isDark ? 0.6 : 1),
            borderRadius: KRadius.md,
            border: Border.all(color: _hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconTile(icon: icon, color: color, size: 28),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: KText.caption.copyWith(
                        fontSize: 12,
                        color: KColor.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(value, style: _num(16)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: KText.caption.copyWith(
                          fontSize: 11,
                          color: KColor.textSecondary,
                        ),
                      ),
                    ],
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

class _ExerciseRankingsCard extends StatelessWidget {
  final WorkoutHistoryViewModel vm;
  const _ExerciseRankingsCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final hasRankings =
        vm.mostTrainedExercise != null ||
        vm.highestVolumeExercise != null ||
        vm.strongestExercise != null;

    if (!hasRankings) {
      return KCard(
        padding: const EdgeInsets.all(KSpacing.lg),
        borderRadius: KRadius.lg,
        boxShadow: const [],
        child: Center(
          child: Text(
            'Rankings show up after a few sessions with logged exercises.',
            textAlign: TextAlign.center,
            style: KText.caption.copyWith(
              fontSize: 13,
              color: KColor.textSecondary,
            ),
          ),
        ),
      );
    }

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      borderRadius: KRadius.lg,
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(
                icon: Icons.star_rounded,
                color: KColor.ember,
                size: 26,
              ),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Text(
                  'Records and rankings',
                  style: KText.caption.copyWith(
                    color: KColor.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.lg),
          if (vm.mostTrainedExercise != null)
            _RankingRow(
              icon: Icons.repeat_rounded,
              color: KColor.ink,
              title: 'Most trained',
              exerciseName: vm.mostTrainedExercise!.exercise.name,
              score: '${vm.mostTrainedExercise!.totalSessions} sessions',
            ),
          if (vm.highestVolumeExercise != null) ...[
            const SizedBox(height: KSpacing.md),
            _RankingRow(
              icon: Icons.fitness_center_rounded,
              color: KColor.textSecondary,
              title: 'Highest volume',
              exerciseName: vm.highestVolumeExercise!.exercise.name,
              score:
                  '${(vm.highestVolumeExercise!.lifetimeVolume / 1000).toStringAsFixed(1)}k kg',
            ),
          ],
          if (vm.strongestExercise != null) ...[
            const SizedBox(height: KSpacing.md),
            _RankingRow(
              icon: Icons.bolt_rounded,
              color: KColor.ember,
              title: 'Strongest (best 1RM)',
              exerciseName: vm.strongestExercise!.exercise.name,
              score: '${vm.strongestExercise!.bestE1rm.toStringAsFixed(1)} kg',
            ),
          ],
          if (vm.fastestGrowingExercise != null) ...[
            const SizedBox(height: KSpacing.md),
            _RankingRow(
              icon: Icons.trending_up_rounded,
              color: KColor.green,
              title: 'Fastest growing',
              exerciseName: vm.fastestGrowingExercise!.exercise.name,
              score:
                  '+${vm.fastestGrowingExercise!.currentTrend.toStringAsFixed(1)} kg recently',
            ),
          ],
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String exerciseName;
  final String score;

  const _RankingRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.exerciseName,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title: $exerciseName, $score',
      excludeSemantics: true,
      child: Row(
        children: [
          _IconTile(icon: icon, color: color, size: 32),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KText.caption.copyWith(
                    fontSize: 12,
                    color: KColor.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  exerciseName,
                  style: KText.caption.copyWith(
                    fontSize: 14,
                    color: KColor.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KSpacing.sm),
          Flexible(
            child: Text(
              score,
              textAlign: TextAlign.end,
              style: _num(13, color: KColor.textPrimary),
            ),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => KEmptyState(
    type: KEmptyStateType.workout,
    title: title,
    message: subtitle,
    actionLabel: ctaText,
    kyno: true,
    // The history screen is pushed from Train; going back is the honest way
    // to start a session from here.
    onAction: () => Navigator.maybePop(context),
  );
}
