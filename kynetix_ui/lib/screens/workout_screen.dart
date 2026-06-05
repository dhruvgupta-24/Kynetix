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
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WorkoutDayPickerSheet(service: _svc),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_svc.isReady) {
      return const Scaffold(
        backgroundColor: KColor.bg,
        body: Center(
          child: KPulseLoader(size: 48, color: KColor.green),
        ),
      );
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
                  // 1. Weekly Progress Ring Card
                  _WeeklyRingCard(viewModel: vm),
                  const SizedBox(height: 16),

                  // 2. Draft Session Alert Card
                  if (_svc.draftSession != null) ...[
                    _DraftSessionCard(
                      session: _svc.draftSession!,
                      onResume: () => _resumeWorkout(_svc.draftSession!),
                      onDiscard: () => _svc.clearDraftSession(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 3. Today's Plan vs Recovery Banner
                  if (todaySplit != null) ...[
                    _TodaySplitCard(
                      splitDay: todaySplit,
                      viewModel: vm,
                      onStart: _startWorkout,
                    ),
                    const SizedBox(height: 16),
                    _ExercisePreviewCard(splitDay: todaySplit),
                    const SizedBox(height: 16),
                  ] else ...[
                    _RecoveryBannerCard(
                      viewModel: vm,
                      onStartManual: _startWorkout,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4. Analytics & Trends
                  _AnalyticsCard(viewModel: vm),
                  const SizedBox(height: 24),

                  // 5. Recent Sessions
                  _RecentSection(viewModel: vm),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: fraction * _anim.value,
                          strokeWidth: 7,
                          backgroundColor: KColor.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(KColor.green),
                          strokeCap: StrokeCap.round,
                        ),
                        Text(
                          '${(fraction * _anim.value * 100).toStringAsFixed(0)}%',
                          style: KText.h3.copyWith(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Progress',
                      style: KText.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: KText.body.copyWith(color: KColor.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department_rounded, color: KColor.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Streak: ${widget.viewModel.currentStreak} day${widget.viewModel.currentStreak == 1 ? "" : "s"}',
                          style: KText.caption.copyWith(color: KColor.amber, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.viewModel.musclesThisWeek.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: KColor.border, height: 1),
            const SizedBox(height: 12),
            Text(
              'MUSCLES TRAINED',
              style: KText.label.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 8),
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
                  onPressed: onResume,
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
                  onPressed: onDiscard,
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [const Color(0xFF102A1E), KColor.surface]
              : [const Color(0xFF131D33), KColor.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? KColor.green.withValues(alpha: 0.3)
              : KColor.blue.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(done ? '✅' : '⚡', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                done ? 'Workout done today' : "Today's split",
                style: KText.caption.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            splitDay.name,
            style: KText.display.copyWith(fontSize: 22, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            '${splitDay.exercises.length} exercises planned',
            style: KText.caption.copyWith(color: KColor.textMuted),
          ),
          const SizedBox(height: 10),
          if (done) ...[
            Container(
              padding: const EdgeInsets.all(12),
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
                      'Logged: ${todaySession.totalSets} sets (${todaySession.totalWorkingVolume.toStringAsFixed(0)} kg working volume)',
                      style: KText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: done ? 'Log Another Session' : 'Start Workout',
              icon: done ? Icons.refresh_rounded : Icons.play_arrow_rounded,
              outlined: done,
              onTap: onStart,
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
    final recovery = viewModel.recovery;
    final overall = recovery.overallReadiness;
    final label = recovery.readinessLabel;

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('😴', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rest & Recovery',
                      style: KText.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No split planned today. Relax and let muscles recover.',
                      style: KText.caption.copyWith(color: KColor.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: KColor.border, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Readiness Score',
                style: KText.caption.copyWith(color: KColor.textMuted),
              ),
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
                  const SizedBox(width: 6),
                  Text(
                    '${(overall * 100).toStringAsFixed(0)}% — $label',
                    style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          if (recovery.muscles.isNotEmpty) ...[
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'Start Split Manually',
              icon: Icons.play_arrow_rounded,
              color: KColor.border,
              onTap: onStartManual,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _ExercisePreviewCard ────────────────────────────────────────────────────

class _ExercisePreviewCard extends StatelessWidget {
  final SplitDay splitDay;
  const _ExercisePreviewCard({required this.splitDay});

  @override
  Widget build(BuildContext context) => KCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exercise Plan',
          style: KText.label.copyWith(fontSize: 10, letterSpacing: 0.5),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < splitDay.exercises.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: KColor.border,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: KColor.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    splitDay.exercises[i].name,
                    style: KText.bodyMedium.copyWith(color: Colors.white),
                  ),
                ),
                Text(
                  splitDay.exercises[i].muscleGroup,
                  style: KText.caption.copyWith(color: KColor.textMuted),
                ),
              ],
            ),
          ),
      ],
    ),
  );
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
            'Training Dashboard',
            style: KText.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniStat(
                label: 'Consistency',
                value: viewModel.consistencyLabel,
              ),
              const SizedBox(width: 10),
              _MiniStat(
                label: 'This Week',
                value: '${viewModel.workoutsThisWeek} workouts',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(
                label: 'Sets Logged',
                value: '${viewModel.totalSetsThisWeek} sets',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                label: 'Working Volume',
                value: '${viewModel.totalVolumeThisWeek.toStringAsFixed(0)} kg',
              ),
            ],
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

// ─── _MiniStat ───────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColor.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: KText.caption.copyWith(color: KColor.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: KText.bodyMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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

// ─── _RecentSection ──────────────────────────────────────────────────────────

class _RecentSection extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;
  const _RecentSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final recent = viewModel.recentSessions;
    if (recent.isEmpty) {
      return KCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: KColor.textMuted, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your workout history will appear here.',
                  style: KText.caption.copyWith(color: KColor.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Workouts',
          style: KText.h2.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 12),
        for (final s in recent) ...[
          _RecentWorkoutTile(session: s),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ─── _RecentWorkoutTile ──────────────────────────────────────────────────────

class _RecentWorkoutTile extends StatelessWidget {
  final WorkoutSession session;
  const _RecentWorkoutTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final d = session.date;
    final dateStr = '${d.day}/${d.month}/${d.year % 100}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.splitDayName,
                  style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: KText.caption.copyWith(color: KColor.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${session.totalSets} sets',
                style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                '${session.totalVolume.toStringAsFixed(0)} kg',
                style: KText.caption.copyWith(color: KColor.textMuted),
              ),
            ],
          ),
        ],
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start workout',
              style: KText.h2.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose today’s planned split or pick another manually.',
              style: KText.caption.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: 16),
            if (planned != null)
              _WorkoutDayOption(
                title: 'Today’s planned split',
                subtitle: planned.name,
                badge: _weekdayLabel(planned.weekday),
                onTap: () => Navigator.of(context).pop(
                  _WorkoutStartSelection(splitDay: planned, wasManual: false),
                ),
              ),
            ...selectable
                .where((d) => d.weekday != planned?.weekday)
                .map(
                  (d) => _WorkoutDayOption(
                    title: d.name,
                    subtitle: '${d.exercises.length} exercises',
                    badge: _weekdayLabel(d.weekday),
                    onTap: () => Navigator.of(context).pop(
                      _WorkoutStartSelection(splitDay: d, wasManual: true),
                    ),
                  ),
                ),
            _WorkoutDayOption(
              title: 'Custom / Empty Workout',
              subtitle: 'Start a session from scratch and add exercises manually',
              badge: 'Custom',
              onTap: () => Navigator.of(context).pop(
                _WorkoutStartSelection(
                  splitDay: service.customWorkoutDay(),
                  wasManual: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutDayOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;
  const _WorkoutDayOption({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KText.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
              badge,
              style: KText.caption.copyWith(
                color: KColor.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
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
