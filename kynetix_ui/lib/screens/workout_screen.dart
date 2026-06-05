import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../models/workout_view_model.dart';
import '../services/workout_service.dart';
import '../services/recovery_service.dart';
import 'workout_setup_screen.dart';
import 'workout_session_screen.dart';
import 'workout_history_screen.dart';

// ─── WorkoutScreen ────────────────────────────────────────────────────────────
//
// Primary Train tab. Displays the training dashboard using a CustomScrollView
// with slivers to completely eliminate layout overflow issues by design.
//
// States:
//   1. Not Ready   → Sleek skeleton pulse loader
//   2. Setup Needed → Premium onboarding prompt
//   3. Dashboard   → Unified scroll view displaying rings, splits, recovery, and trends.

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final _svc = WorkoutService.instance;
  WorkoutDashboardViewModel? _viewModel;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onServiceChange);
    if (_svc.isReady) {
      _viewModel = WorkoutDashboardViewModel.from(_svc);
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceChange() {
    if (mounted) {
      setState(() {
        if (_svc.isReady) {
          _viewModel = WorkoutDashboardViewModel.from(_svc);
        }
      });
    }
  }

  // ── Navigation Methods ────────────────────────────────────────────────────

  Future<void> _openSetup({bool editMode = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutSetupScreen(editMode: editMode),
        fullscreenDialog: true,
      ),
    );
    if (mounted) setState(() {});
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen()),
    );
  }

  Future<void> _startWorkout() async {
    final picked = await _pickWorkoutDay();
    if (!mounted || picked == null) return;
    final prev = _svc.lastSessionFor(picked.splitDay.name);
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutSessionScreen(
          splitDay: picked.splitDay,
          date: DateTime.now(),
          previousSession: prev,
          wasManuallySelected: picked.wasManual,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == true && mounted) setState(() {});
  }

  Future<void> _resumeWorkout(WorkoutSession draft) async {
    final splitDay = _svc.split.days.firstWhere(
      (d) => d.name == draft.splitDayName,
      orElse: () => SplitDay(
        name: draft.splitDayName,
        weekday: draft.splitDayWeekday ?? 0,
        exercises: draft.entries.map((e) => e.exercise).toList(),
      ),
    );

    final prev = _svc.lastSessionFor(splitDay.name);
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutSessionScreen(
          splitDay: splitDay,
          date: draft.date,
          previousSession: prev,
          wasManuallySelected: draft.wasManuallySelected,
          draftSession: draft,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == true && mounted) setState(() {});
  }

  Future<_WorkoutStartSelection?> _pickWorkoutDay() async {
    return showModalBottomSheet<_WorkoutStartSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkoutDayPickerSheet(service: _svc),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_svc.isReady) {
      return const _WorkoutDashboardSkeleton();
    }

    if (!_svc.isSetupDone) return _buildSetupPrompt();

    final vm = _viewModel ?? WorkoutDashboardViewModel.from(_svc);
    final todaySplit = _svc.todaySplitDay;

    return Scaffold(
      backgroundColor: KColor.bg,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              backgroundColor: KColor.surface,
              surfaceTintColor: Colors.transparent,
              pinned: true,
              expandedHeight: 110,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                title: Text(
                  'Train',
                  style: KText.h1.copyWith(color: Colors.white, fontSize: 20),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.history_rounded, color: Colors.white),
                  tooltip: 'Workout History',
                  onPressed: _openHistory,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
                  tooltip: 'Edit Split',
                  onPressed: () => _openSetup(editMode: true),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 1. Weekly Progress Bento Card
                  _WeeklyRingCard(viewModel: vm),
                  const SizedBox(height: 16),

                  // 2. Quick Stats Row
                  _QuickStatsRow(viewModel: vm),
                  const SizedBox(height: 16),

                  // 3. Draft Session Alert Card
                  if (_svc.draftSession != null) ...[
                    _DraftSessionCard(
                      session: _svc.draftSession!,
                      onResume: () => _resumeWorkout(_svc.draftSession!),
                      onDiscard: () => _svc.clearDraftSession(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4. Today's Plan vs Recovery Card
                  if (todaySplit != null) ...[
                    _TodaySplitCard(
                      splitDay: todaySplit,
                      viewModel: vm,
                      onStart: _startWorkout,
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    _RecoveryBannerCard(
                      viewModel: vm,
                      onStartManual: _startWorkout,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 5. Recent Workout Card
                  _RecentWorkoutCard(
                    viewModel: vm,
                    onViewDetails: (session) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SessionDetailPage(session: session, service: _svc),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 6. Recovery Insights
                  _RecoveryInsightsCard(viewModel: vm),
                  const SizedBox(height: 16),

                  // 7. Analytics & Trends
                  _AnalyticsCard(viewModel: vm),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Setup Prompt Redesign ──────────────────────────────────────────────────

  Widget _buildSetupPrompt() => Scaffold(
    backgroundColor: KColor.bg,
    body: Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.3),
          radius: 1.2,
          colors: [
            Color(0xFF132F23), // deep brand green glow
            Color(0xFF0F0F1A),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: KColor.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: KColor.green.withValues(alpha: 0.25),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: KColor.green,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Transform Your Training',
                  textAlign: TextAlign.center,
                  style: KText.display.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 14),
                Text(
                  'Set up a custom workout split tailored to your experience level and goals. Track volume trends, e1RM progression, and recovery details.',
                  textAlign: TextAlign.center,
                  style: KText.body.copyWith(
                    color: KColor.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: KButton(
                    label: 'Get Started',
                    icon: Icons.arrow_forward_rounded,
                    onTap: _openSetup,
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

// ─── _WeeklyRingCard ─────────────────────────────────────────────────────────

class _WeeklyRingCard extends StatefulWidget {
  final WorkoutDashboardViewModel viewModel;
  const _WeeklyRingCard({required this.viewModel});

  @override
  State<_WeeklyRingCard> createState() => _WeeklyRingCardState();
}

class _WeeklyRingCardState extends State<_WeeklyRingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_WeeklyRingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel.completedDaysThisWeek != widget.viewModel.completedDaysThisWeek) {
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
    final fraction = widget.viewModel.weekCompletionFraction;
    final label = widget.viewModel.weekCompletionLabel;

    return KCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WEEKLY PROGRESS',
                style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
              ),
              Text(
                label,
                style: KText.caption.copyWith(color: KColor.green, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Progress Ring
              SizedBox(
                width: 76,
                height: 76,
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: fraction * _anim.value,
                          strokeWidth: 8,
                          backgroundColor: KColor.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(KColor.green),
                          strokeCap: StrokeCap.round,
                        ),
                        Text(
                          '${(fraction * _anim.value * 100).toStringAsFixed(0)}%',
                          style: KText.h2.copyWith(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              // 2x2 Bento stats grid
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _BentoStat(
                          label: 'Volume',
                          value: '${widget.viewModel.totalVolumeThisWeek.toStringAsFixed(0)} kg',
                          icon: Icons.fitness_center_rounded,
                          iconColor: KColor.green,
                        ),
                        const SizedBox(width: 8),
                        _BentoStat(
                          label: 'Sets',
                          value: '${widget.viewModel.totalSetsThisWeek}',
                          icon: Icons.playlist_add_check_rounded,
                          iconColor: KColor.blue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _BentoStat(
                          label: 'Streak',
                          value: '${widget.viewModel.currentStreak} day${widget.viewModel.currentStreak == 1 ? "" : "s"}',
                          icon: Icons.local_fire_department_rounded,
                          iconColor: KColor.amber,
                        ),
                        const SizedBox(width: 8),
                        _BentoStat(
                          label: 'Consistency',
                          value: widget.viewModel.consistencyLabel,
                          icon: Icons.analytics_rounded,
                          iconColor: KColor.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.viewModel.musclesThisWeek.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: KColor.border, height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.viewModel.musclesThisWeek.map((m) => KChip(m)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _BentoStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _BentoStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: KColor.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KColor.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: KText.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ─── _QuickStatsRow ──────────────────────────────────────────────────────────

class _QuickStatsRow extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;

  const _QuickStatsRow({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QuickStatCard(
          label: 'Total PRs',
          value: viewModel.totalPrsAllTime,
          suffix: '',
          icon: Icons.workspace_premium_rounded,
          color: KColor.amber,
        ),
        const SizedBox(width: 8),
        _QuickStatCard(
          label: 'Weekly Vol',
          value: viewModel.totalVolumeThisWeek,
          suffix: ' kg',
          icon: Icons.fitness_center_rounded,
          color: KColor.green,
          isVolume: true,
        ),
        const SizedBox(width: 8),
        _QuickStatCard(
          label: 'Weekly Sets',
          value: viewModel.totalSetsThisWeek,
          suffix: '',
          icon: Icons.playlist_add_check_rounded,
          color: KColor.blue,
        ),
        const SizedBox(width: 8),
        _QuickStatCard(
          label: 'Streak',
          value: viewModel.currentStreak,
          suffix: 'd',
          icon: Icons.local_fire_department_rounded,
          color: KColor.amber,
        ),
      ],
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final String label;
  final num value;
  final String suffix;
  final IconData icon;
  final Color color;
  final bool isVolume;

  const _QuickStatCard({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
    this.isVolume = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: KColor.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KColor.border, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, val, child) {
                String valStr = val.toStringAsFixed(0);
                if (isVolume && val >= 1000) {
                  valStr = '${(val / 1000).toStringAsFixed(1)}k';
                }
                return Text(
                  '$valStr$suffix',
                  style: KText.h2.copyWith(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 8.5),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _DraftSessionCard ───────────────────────────────────────────────────────

class _DraftSessionCard extends StatelessWidget {
  final WorkoutSession session;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  const _DraftSessionCard({
    required this.session,
    required this.onResume,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pause_circle_filled_rounded,
                color: KColor.amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Workout in progress',
                  style: KText.h3.copyWith(color: Colors.white),
                ),
              ),
              Text(
                '${session.totalSets} set${session.totalSets == 1 ? "" : "s"}',
                style: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You paused "${session.splitDayName}". Resume to finish logging your sets.',
            style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onResume();
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Resume Workout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KColor.amber,
                    foregroundColor: KColor.bg,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onDiscard();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KColor.danger,
                    side: const BorderSide(color: KColor.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Discard', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── _TodaySplitCard ─────────────────────────────────────────────────────────

class _TodaySplitCard extends StatelessWidget {
  final SplitDay splitDay;
  final WorkoutDashboardViewModel viewModel;
  final VoidCallback onStart;

  const _TodaySplitCard({
    required this.splitDay,
    required this.viewModel,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final todaySession = viewModel.recentSessions.where((s) {
      return s.splitDayName == splitDay.name &&
          DateUtils.isSameDay(s.date, DateTime.now());
    }).firstOrNull;
    final done = todaySession != null;

    final muscles = splitDay.exercises.map((e) => e.muscleGroup).toSet().toList();
    final musclesStr = muscles.isEmpty ? 'All Muscles' : muscles.join(' • ');
    final duration = splitDay.exercises.length * 9;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [const Color(0xFF102A1E), const Color(0xFF131F1A)]
              : [const Color(0xFF1A1F36), const Color(0xFF141624)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? KColor.green.withValues(alpha: 0.3)
              : KColor.green.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(done ? '✅' : '⚡', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    done ? 'Workout Done Today' : "TODAY'S PLANNED SPLIT",
                    style: KText.label.copyWith(
                      color: done ? KColor.green : KColor.green,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.fitness_center_rounded, color: Colors.white24, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            splitDay.name.toUpperCase(),
            style: KText.display.copyWith(fontSize: 24, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            musclesStr,
            style: KText.bodyMedium.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.format_list_bulleted_rounded, color: KColor.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(
                '${splitDay.exercises.length} exercises',
                style: KText.caption.copyWith(color: KColor.textSecondary),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.schedule_rounded, color: KColor.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(
                '~$duration min',
                style: KText.caption.copyWith(color: KColor.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (done) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: KColor.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KColor.green.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: KColor.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Logged: ${todaySession.totalSets} sets (${todaySession.totalWorkingVolume.toStringAsFixed(0)} kg volume)',
                      style: KText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: done ? 'Log Another Session' : 'Start Workout',
              icon: done ? Icons.refresh_rounded : Icons.play_arrow_rounded,
              outlined: done,
              onTap: () {
                HapticFeedback.lightImpact();
                onStart();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _RecoveryBannerCard ─────────────────────────────────────────────────────

class _RecoveryBannerCard extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;
  final VoidCallback onStartManual;

  const _RecoveryBannerCard({
    required this.viewModel,
    required this.onStartManual,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF131D33), Color(0xFF0F0F1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('😴', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    "TODAY IS A REST DAY",
                    style: KText.label.copyWith(color: KColor.amber, fontSize: 10, letterSpacing: 0.5),
                  ),
                ],
              ),
              const Icon(Icons.spa_rounded, color: Colors.white24, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Rest & Recovery',
            style: KText.display.copyWith(fontSize: 24, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'No split planned today. Relax and let muscles recover. Focus on nutrition and mobility.',
            style: KText.caption.copyWith(color: KColor.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'Start Split Manually',
              icon: Icons.play_arrow_rounded,
              color: KColor.border,
              onTap: () {
                HapticFeedback.lightImpact();
                onStartManual();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _RecentWorkoutCard ──────────────────────────────────────────────────────

class _RecentWorkoutCard extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;
  final ValueChanged<WorkoutSession> onViewDetails;

  const _RecentWorkoutCard({
    required this.viewModel,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final recent = viewModel.recentSessions;
    if (recent.isEmpty) {
      return KCard(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.history_rounded, color: KColor.textMuted, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Workout History',
                    style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your training stats will appear here as soon as you save your first session.',
                    style: KText.caption.copyWith(color: KColor.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final session = recent.first;
    final d = session.date;
    final dateStr = '${d.day}/${d.month}/${d.year % 100}';
    final durationStr = session.durationMinutes != null 
        ? '${session.durationMinutes} min' 
        : '45 min';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LAST WORKOUT PERFORMED',
                style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: KColor.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  dateStr,
                  style: KText.caption.copyWith(
                    color: KColor.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            session.splitDayName,
            style: KText.h2.copyWith(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _RecentStat(label: 'Volume', value: '${session.totalVolume.toStringAsFixed(0)} kg'),
              _RecentStat(label: 'Sets', value: '${session.totalSets} sets'),
              _RecentStat(label: 'Duration', value: durationStr),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'View Details',
              icon: Icons.arrow_forward_rounded,
              outlined: true,
              onTap: () {
                HapticFeedback.lightImpact();
                onViewDetails(session);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentStat extends StatelessWidget {
  final String label;
  final String value;
  const _RecentStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─── _RecoveryInsightsCard ───────────────────────────────────────────────────

class _RecoveryInsightsCard extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;
  const _RecoveryInsightsCard({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final recovery = viewModel.recovery;
    final overall = recovery.overallReadiness;
    final label = recovery.readinessLabel;

    final lastSession = viewModel.recentSessions.firstOrNull;
    final daysSinceLast = lastSession != null 
        ? DateTime.now().difference(lastSession.date).inDays 
        : -1;
    final daysStr = daysSinceLast == -1 
        ? 'No workouts yet' 
        : daysSinceLast == 0 
            ? 'Today' 
            : '$daysSinceLast day${daysSinceLast == 1 ? "" : "s"} ago';

    return KCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECOVERY STATUS',
                style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
              ),
              Row(
                children: [
                  const Icon(Icons.history_rounded, size: 12, color: KColor.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Last workout: $daysStr',
                    style: KText.caption.copyWith(color: KColor.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Readiness Score',
            style: KText.caption.copyWith(color: KColor.textMuted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: overall >= 0.8
                      ? KColor.green
                      : overall >= 0.6
                          ? KColor.amber
                          : KColor.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(overall * 100).toStringAsFixed(0)}% — $label',
                style: KText.h2.copyWith(color: Colors.white, fontSize: 15),
              ),
            ],
          ),
          if (recovery.muscles.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: KColor.border, height: 1),
            const SizedBox(height: 12),
            SizedBox(
              height: 28,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recovery.muscles.length,
                itemBuilder: (context, i) {
                  final m = recovery.muscles[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: KChip(
                      '${m.muscleGroup} (${m.hoursSinceLastTraining}h ago)',
                      color: m.state == RecoveryState.recovering
                          ? KColor.danger
                          : m.state == RecoveryState.ready
                              ? KColor.amber
                              : KColor.green,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── _AnalyticsCard ──────────────────────────────────────────────────────────

class _AnalyticsCard extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;
  const _AnalyticsCard({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Training Trends',
            style: KText.h2.copyWith(color: Colors.white),
          ),
          if (viewModel.latestPr != null) ...[
            const SizedBox(height: 14),
            _HighlightCard(
              title: viewModel.latestPr!.title,
              detail: viewModel.latestPr!.detail,
            ),
          ],
          const SizedBox(height: 18),
          _TrendBlock(
            title: 'Weekly Volume Trend',
            values: viewModel.volumeTrend,
            valueFormatter: (v) => '${v.toStringAsFixed(0)} kg',
          ),
          const SizedBox(height: 14),
          _TrendBlock(
            title: 'Workout Consistency',
            values: viewModel.consistencyTrend.map((v) => v.toDouble()).toList(),
            valueFormatter: (v) => '${v.toInt()} workouts',
          ),
        ],
      ),
    );
  }
}

// ─── _HighlightCard ──────────────────────────────────────────────────────────

class _HighlightCard extends StatelessWidget {
  final String title;
  final String detail;
  const _HighlightCard({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: KColor.amber.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: KColor.amber.withValues(alpha: 0.22)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.workspace_premium_rounded,
          color: KColor.amber,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: KText.caption.copyWith(color: KColor.textSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}



// ─── _TrendBlock ─────────────────────────────────────────────────────────────

class _TrendBlock extends StatelessWidget {
  final String title;
  final List<double> values;
  final String Function(double value) valueFormatter;
  const _TrendBlock({
    required this.title,
    required this.values,
    required this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final latest = values.isNotEmpty ? values.last : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: KText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              valueFormatter(latest),
              style: KText.caption.copyWith(color: KColor.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _MiniBarChart(values: values),
      ],
    );
  }
}

// ─── _MiniBarChart ───────────────────────────────────────────────────────────

class _MiniBarChart extends StatelessWidget {
  final List<double> values;
  const _MiniBarChart({required this.values});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Container(
        height: 44,
        alignment: Alignment.centerLeft,
        child: Text(
          'Not enough data yet',
          style: KText.caption.copyWith(color: KColor.textMuted),
        ),
      );
    }
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final value in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: maxValue <= 0
                        ? 6
                        : (value / maxValue * 42).clamp(6, 42),
                    decoration: BoxDecoration(
                      color: KColor.green.withValues(
                        alpha: value == values.last ? 0.95 : 0.40,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── _WorkoutDashboardSkeleton ───────────────────────────────────────────────

class _WorkoutDashboardSkeleton extends StatefulWidget {
  const _WorkoutDashboardSkeleton();

  @override
  State<_WorkoutDashboardSkeleton> createState() => _WorkoutDashboardSkeletonState();
}

class _WorkoutDashboardSkeletonState extends State<_WorkoutDashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.3 + (_controller.value * 0.4);
        return Opacity(
          opacity: opacity,
          child: child,
        );
      },
      child: Scaffold(
        backgroundColor: KColor.bg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _skeletonCard(height: 120),
              const SizedBox(height: 16),
              _skeletonCard(height: 50),
              const SizedBox(height: 16),
              _skeletonCard(height: 160),
              const SizedBox(height: 16),
              _skeletonCard(height: 140),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonCard({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
    );
  }
}

// ─── Picker sheet helpers ────────────────────────────────────────────────────

class _WorkoutStartSelection {
  final SplitDay splitDay;
  final bool wasManual;
  const _WorkoutStartSelection({
    required this.splitDay,
    required this.wasManual,
  });
}

class _WorkoutDayPickerSheet extends StatelessWidget {
  final WorkoutService service;
  const _WorkoutDayPickerSheet({required this.service});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final planned = service.splitDayFor(today);
    final selectable = service.selectableWorkoutDaysFor(today);

    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: true,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Text(
                        'Start Workout',
                        style: KText.h2.copyWith(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose today’s planned split or pick another manually.',
                        style: KText.caption.copyWith(color: KColor.textSecondary),
                      ),
                      const SizedBox(height: 18),

                      // Today's Planned Workout Card
                      if (planned != null) ...[
                        _buildTodayPlannedCard(context, planned),
                      ] else ...[
                        _buildTodayRestCard(context),
                      ],

                      const SizedBox(height: 24),
                      Text(
                        'OTHER WORKOUT DAYS',
                        style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 10),

                      // Selectable split days
                      ...selectable
                          .where((d) => d.weekday != planned?.weekday)
                          .map(
                            (d) => _buildOtherWorkoutTile(context, d),
                          ),

                      const SizedBox(height: 24),
                      Text(
                        'CUSTOM WORKOUT',
                        style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 10),

                      // Custom empty workout
                      _buildCustomWorkoutTile(context),
                    ],
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: KColor.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTodayPlannedCard(BuildContext context, SplitDay planned) {
    final muscles = planned.exercises.map((e) => e.muscleGroup).toSet().toList();
    final musclesStr = muscles.isEmpty ? 'All Muscles' : muscles.join(' • ');
    final duration = planned.exercises.length * 9;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F3C2C), Color(0xFF131F1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.green.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "TODAY'S PLANNED WORKOUT",
                style: KText.label.copyWith(color: KColor.green, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.star_rounded, color: KColor.green, size: 16),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            planned.name,
            style: KText.display.copyWith(color: Colors.white, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            musclesStr,
            style: KText.bodyMedium.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.format_list_bulleted_rounded, color: KColor.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(
                '${planned.exercises.length} exercises',
                style: KText.caption.copyWith(color: KColor.textSecondary),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.schedule_rounded, color: KColor.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(
                '~$duration min',
                style: KText.caption.copyWith(color: KColor.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'Start Planned Workout',
              icon: Icons.play_arrow_rounded,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(
                  _WorkoutStartSelection(splitDay: planned, wasManual: false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayRestCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('😴', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                "TODAY IS A REST DAY",
                style: KText.label.copyWith(color: KColor.amber, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Scheduled Rest',
            style: KText.h2.copyWith(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Muscles grow when you rest. Focus on recovery today or choose another split day manually below.',
            style: KText.caption.copyWith(color: KColor.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherWorkoutTile(BuildContext context, SplitDay d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop(
            _WorkoutStartSelection(splitDay: d, wasManual: true),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d.exercises.length} exercises • ~${d.exercises.length * 9} min',
                      style: KText.caption.copyWith(color: KColor.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: KColor.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _weekdayLabel(d.weekday),
                  style: KText.caption.copyWith(
                    color: KColor.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomWorkoutTile(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop(
            _WorkoutStartSelection(
              splitDay: service.customWorkoutDay(),
              wasManual: true,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KColor.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: KColor.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom / Empty Workout',
                      style: KText.bodyMedium.copyWith(
                        color: KColor.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Start from scratch and log sets dynamically',
                      style: KText.caption.copyWith(color: KColor.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: KColor.textMuted, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    1 => 'Mon',
    2 => 'Tue',
    3 => 'Wed',
    4 => 'Thu',
    5 => 'Fri',
    6 => 'Sat',
    7 => 'Sun',
    _ => 'Any day',
  };
}
