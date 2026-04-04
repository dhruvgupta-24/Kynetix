import 'package:flutter/material.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import 'workout_setup_screen.dart';
import 'workout_session_screen.dart';

// ─── WorkoutScreen ────────────────────────────────────────────────────────────
//
// Primary Train tab. Shows one of three states:
//   A) Setup needed → CTA to WorkoutSetupScreen
//   B) Rest day     → Rest message + recent history
//   C) Training day → Today's split day + start/edit session
//
// After WorkoutSetupScreen completes, NavigatorStack.pop(true) triggers
// a setState so this widget re-evaluates.

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final _svc = WorkoutService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onServiceChange);
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceChange);
    super.dispose();
  }

  void _onServiceChange() {
    if (mounted) setState(() {});
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  Future<void> _openSetup({bool editMode = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutSetupScreen(editMode: editMode),
        fullscreenDialog: true,
      ),
    );
    if (mounted) setState(() {});
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
    if (!_svc.isSetupDone) return _buildSetupPrompt();

    final todaySplit = _svc.todaySplitDay;
    if (todaySplit == null) return _buildRestDay();
    return _buildTrainingDay(todaySplit);
  }

  // ── State A: Setup needed ─────────────────────────────────────────────────

  Widget _buildSetupPrompt() => Scaffold(
    backgroundColor: const Color(0xFF13131F),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: Color(0xFF52B788),
                  size: 34,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Set up your training',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Configure your workout split once.\nThen just open the app and log your sets.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text(
                    'Set Up Training',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _openSetup,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // ── State B: Rest day ─────────────────────────────────────────────────────

  Widget _buildRestDay() => Scaffold(
    backgroundColor: const Color(0xFF13131F),
    appBar: _WorkoutAppBar(onEdit: () => _openSetup(editMode: true)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _RestDayCard(),
        const SizedBox(height: 16),
        _WeeklyProgressCard(service: _svc),
        const SizedBox(height: 24),
        _buildRecentSection(),
      ],
    ),
  );

  // ── State C: Training day ─────────────────────────────────────────────────

  Widget _buildTrainingDay(SplitDay splitDay) {
    final todaySession = _svc.sessionForDateAndSplit(
      DateTime.now(),
      splitDay.name,
    );
    final lastSession = _svc.lastSessionFor(splitDay.name);
    final latestPr = _svc.latestPersonalBest();

    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: _WorkoutAppBar(onEdit: () => _openSetup(editMode: true)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _WeeklyProgressCard(service: _svc),
          const SizedBox(height: 16),
          if (_svc.draftSession != null)
            _DraftSessionCard(
              session: _svc.draftSession!,
              onResume: () => _resumeWorkout(_svc.draftSession!),
              onDiscard: () => _svc.clearDraftSession(),
            )
          else
            _WorkoutLaunchCard(service: _svc, onStart: _startWorkout),
          const SizedBox(height: 16),
          // Today's split info
          _TodaySplitCard(
            splitDay: splitDay,
            todaySession: todaySession,
            onStart: todaySession == null ? _startWorkout : null,
            onRedo: todaySession != null ? _startWorkout : null,
          ),
          const SizedBox(height: 16),

          // Last session reference
          if (lastSession != null && todaySession == null) ...[
            _LastSessionCard(session: lastSession),
            const SizedBox(height: 16),
          ],

          // Today's completed session stats
          if (todaySession != null) ...[
            _CompletedSessionCard(session: todaySession),
            const SizedBox(height: 16),
          ],

          // Exercise quick preview
          _ExercisePreviewCard(splitDay: splitDay),
          if (latestPr != null) ...[
            const SizedBox(height: 16),
            _HighlightCard(title: latestPr.title, detail: latestPr.detail),
          ],
          const SizedBox(height: 16),
          _TrainingAnalyticsCard(service: _svc),
          const SizedBox(height: 24),

          // Recent history
          _buildRecentSection(),
        ],
      ),
    );
  }

  Widget _buildRecentSection() {
    final recent = _svc.recentSessions(limit: 5);
    if (recent.isEmpty) {
      return const _InfoCard(
        icon: Icons.history_rounded,
        text: 'Your workout history will appear here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Recent Workouts',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final s in recent) ...[
          _RecentWorkoutTile(session: s),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ─── Shared AppBar ────────────────────────────────────────────────────────────

class _WorkoutAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onEdit;
  const _WorkoutAppBar({required this.onEdit});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: const Color(0xFF13131F),
    surfaceTintColor: Colors.transparent,
    automaticallyImplyLeading: false,
    title: const Text(
      'Train',
      style: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF6B7280)),
        tooltip: 'Edit split',
        onPressed: onEdit,
      ),
    ],
  );
}

// ─── Cards ────────────────────────────────────────────────────────────────────

class _RestDayCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E2C),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2E2E3E)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text('😴', style: TextStyle(fontSize: 32)),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rest Day',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'No training scheduled today. Recover, eat well, sleep.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => (_findState(context)?._startWorkout()),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start another split manually'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D6A4F),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );

  _WorkoutScreenState? _findState(BuildContext context) =>
      context.findAncestorStateOfType<_WorkoutScreenState>();
}

class _TodaySplitCard extends StatelessWidget {
  final SplitDay splitDay;
  final WorkoutSession? todaySession;
  final VoidCallback? onStart;
  final VoidCallback? onRedo;

  const _TodaySplitCard({
    required this.splitDay,
    this.todaySession,
    this.onStart,
    this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    final done = todaySession != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [const Color(0xFF1A3A2A), const Color(0xFF1E1E2C)]
              : [const Color(0xFF1A2040), const Color(0xFF1E1E2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? const Color(0xFF52B788).withValues(alpha: 0.3)
              : const Color(0xFF60A5FA).withValues(alpha: 0.2),
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
                done ? 'Workout done today' : "Today's workout",
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            splitDay.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${splitDay.exercises.length} exercises',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Planned for ${_weekdayLabel(splitDay.weekday)} • ${splitDay.exercises.take(3).map((e) => e.name).join(', ')}${splitDay.exercises.length > 3 ? '…' : ''}',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF13131F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2E3E)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.event_note_rounded,
                  color: Color(0xFF60A5FA),
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Planned split and actual workout are separate. You can log any day when life shifts.',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!done && onStart != null)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Start Workout',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onStart,
              ),
            )
          else if (done && onRedo != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text(
                'Log Another Session',
                style: TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF9CA3AF),
                side: const BorderSide(color: Color(0xFF2E2E3E)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onRedo,
            ),
        ],
      ),
    );
  }
}

class _CompletedSessionCard extends StatelessWidget {
  final WorkoutSession session;
  const _CompletedSessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final svc = WorkoutService.instance;
    final previous = svc
        .recentSessions(limit: 10)
        .where(
          (s) => s.id != session.id && s.splitDayName == session.splitDayName,
        )
        .cast<WorkoutSession?>()
        .firstWhere((s) => s != null, orElse: () => null);
    final delta = previous != null
        ? svc.compareWithPrevious(session, previous)
        : null;
    final best = session.bestSetToday;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF52B788).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF52B788).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF52B788),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Today's session",
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                ),
                Text(
                  '${session.totalSets} sets  ·  ${session.totalVolume.toStringAsFixed(0)} kg volume',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (best != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Best set: ${best.weight.toStringAsFixed(best.weight.truncateToDouble() == best.weight ? 0 : 1)}×${best.reps}${delta != null ? ' • ${delta.volumeLabel}' : ''}',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyProgressCard extends StatelessWidget {
  final WorkoutService service;
  const _WeeklyProgressCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final completion = service.splitCompletionThisWeek();
    final highlights = service.recentImprovementHighlights(limit: 2);
    final muscles = service.muscleGroupsTrainedThisWeek;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Training overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(
                label: 'This week',
                value: '${service.workoutsThisWeek} workouts',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                label: 'Streak',
                value:
                    '${service.currentStreak} day${service.currentStreak == 1 ? '' : 's'}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(
                label: 'Sets',
                value: '${service.totalSetsThisWeek} total',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                label: 'Volume',
                value: '${service.totalVolumeThisWeek.toStringAsFixed(0)} kg',
              ),
            ],
          ),
          if (muscles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Muscles trained: ${muscles.join(', ')}',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
            ),
          ],
          if (completion.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: completion.entries
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: e.value
                            ? const Color(0xFF52B788).withValues(alpha: 0.15)
                            : const Color(0xFF13131F),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: e.value
                              ? const Color(0xFF52B788).withValues(alpha: 0.4)
                              : const Color(0xFF2E2E3E),
                        ),
                      ),
                      child: Text(
                        '${e.value ? '✓' : '○'} ${e.key}',
                        style: TextStyle(
                          color: e.value
                              ? const Color(0xFF52B788)
                              : const Color(0xFF9CA3AF),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (highlights.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...highlights.map(
              (h) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $h',
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkoutLaunchCard extends StatelessWidget {
  final WorkoutService service;
  final VoidCallback onStart;
  const _WorkoutLaunchCard({required this.service, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final planned = service.todaySplitDay;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Start workout',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            planned != null
                ? 'Planned today: ${planned.name}. You can still switch to another split day or start an empty workout.'
                : 'No workout planned today. You can still log any split day or start a custom session.',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Choose workout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pause_circle_filled_rounded,
                color: Color(0xFFFFB347),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Workout in progress',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${session.totalSets} set${session.totalSets == 1 ? "" : "s"}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You paused ${session.splitDayName}. Resume to finish logging your sets.',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume Workout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB347),
                    foregroundColor: const Color(0xFF13131F),
                    elevation: 0,
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
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0xFF2E2E3E)),
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

class _HighlightCard extends StatelessWidget {
  final String title;
  final String detail;
  const _HighlightCard({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFB347).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: const Color(0xFFFFB347).withValues(alpha: 0.22),
      ),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.workspace_premium_rounded,
          color: Color(0xFFFFB347),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TrainingAnalyticsCard extends StatelessWidget {
  final WorkoutService service;
  const _TrainingAnalyticsCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final recent = service.recentSessions(limit: 1);
    final spotlight = recent.isNotEmpty && recent.first.entries.isNotEmpty
        ? recent.first.entries.first.exercise
        : null;
    final volumeTrend = service.weeklyVolumeTrend();
    final consistencyTrend = service.weeklyWorkoutCounts();
    final exerciseTrend = spotlight != null
        ? service.exerciseOneRmTrend(spotlight.id)
        : const <double>[];
    final note = spotlight != null
        ? service.exerciseProgressNote(spotlight, recent.first.splitDayName)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Training dashboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Consistency',
                  value: service.consistencyLabel(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Recent focus',
                  value: spotlight?.name ?? 'Log a workout',
                ),
              ),
            ],
          ),
          if (spotlight != null) ...[
            const SizedBox(height: 14),
            _ExerciseProgressPanel(
              service: service,
              exercise: spotlight,
              splitDayName: recent.first.splitDayName,
            ),
          ],
          const SizedBox(height: 14),
          _TrendBlock(
            title: 'Weekly volume trend',
            values: volumeTrend,
            valueFormatter: (v) => '${v.toStringAsFixed(0)} kg',
          ),
          const SizedBox(height: 12),
          _TrendBlock(
            title: 'Workout consistency',
            values: consistencyTrend.map((v) => v.toDouble()).toList(),
            valueFormatter: (v) => '${v.toInt()} workouts',
          ),
          if (exerciseTrend.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TrendBlock(
              title: '${spotlight!.name} 1RM trend',
              values: exerciseTrend,
              valueFormatter: (v) => '${v.toStringAsFixed(1)} kg',
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(
              note,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExerciseProgressPanel extends StatelessWidget {
  final WorkoutService service;
  final Exercise exercise;
  final String splitDayName;
  const _ExerciseProgressPanel({
    required this.service,
    required this.exercise,
    required this.splitDayName,
  });

  @override
  Widget build(BuildContext context) {
    final history = service.historyFor(exercise.id, limit: 3);
    final lastEntry = service.lastEntryFor(exercise.id, splitDayName);
    final trend = service.exerciseTrendLabel(exercise.id);
    final suggestion = _suggestionLabel(
      service.progressionHint(lastEntry, exercise),
    );
    final best = service.bestSetEver(exercise.id);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$trend • $suggestion',
                      style: const TextStyle(
                        color: Color(0xFF52B788),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (best != null)
                Text(
                  'Best: ${best.weight.toStringAsFixed(best.weight == best.weight.truncateToDouble() ? 0 : 1)}×${best.reps}',
                  style: const TextStyle(
                    color: Color(0xFFFFB347),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (history.isEmpty)
            const Text(
              'No recent sessions yet.',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            )
          else
            ...history.map((h) {
              final top =
                  h.entry.topProgressionSet ??
                  h.entry.topWorkingSet ??
                  h.entry.topSet;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${h.date.day}/${h.date.month}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        top == null
                            ? 'Logged'
                            : '${top.weight.toStringAsFixed(top.weight == top.weight.truncateToDouble() ? 0 : 1)} kg × ${top.reps} • 1RM ${top.estimatedOneRepMax.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _suggestionLabel(String hint) {
    final text = hint.toLowerCase();
    if (text.contains('increase') ||
        text.contains('step up') ||
        text.contains('add a plate')) {
      return 'Increase';
    }
    if (text.contains('same weight')) {
      return 'Repeat';
    }
    if (text.contains('beat reps')) {
      return 'Beat reps first';
    }
    if (text.contains('slightly down')) {
      return 'Reduce and reset';
    }
    return 'Repeat';
  }
}

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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              valueFormatter(latest),
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _MiniBarChart(values: values),
      ],
    );
  }
}

class _MiniBarChart extends StatelessWidget {
  final List<double> values;
  const _MiniBarChart({required this.values});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Container(
        height: 54,
        alignment: Alignment.centerLeft,
        child: const Text(
          'Not enough data yet',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 11.5),
        ),
      );
    }
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 58,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final value in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: maxValue <= 0
                        ? 8
                        : (value / maxValue * 52).clamp(8, 52),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFF52B788,
                      ).withValues(alpha: value == values.last ? 0.95 : 0.45),
                      borderRadius: BorderRadius.circular(8),
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10.5),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Start workout',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use today’s plan as reference, or choose another split day manually.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            if (planned != null)
              _WorkoutDayOption(
                title: 'Today’s planned workout',
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
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_WorkoutStartSelection(splitDay: d, wasManual: true)),
                  ),
                ),
            _WorkoutDayOption(
              title: 'Custom / Empty Workout',
              subtitle:
                  'Start with an empty workout and add exercises manually',
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Color(0xFF52B788),
                fontSize: 11.5,
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

class _LastSessionCard extends StatelessWidget {
  final WorkoutSession session;
  const _LastSessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().difference(session.date).inDays;
    final agoStr = ago == 0
        ? 'today'
        : ago == 1
        ? 'yesterday'
        : '${ago}d ago';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: Color(0xFF6B7280),
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'Last session — $agoStr',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: session.entries.map((e) {
              final top = e.topSet;
              if (top == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF13131F),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2E2E3E)),
                ),
                child: Text(
                  '${e.exercise.name}  ${top.weight.toStringAsFixed(0)}×${top.reps}',
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11.5,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ExercisePreviewCard extends StatelessWidget {
  final SplitDay splitDay;
  const _ExercisePreviewCard({required this.splitDay});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E2C),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF2E2E3E)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Exercise Plan',
          style: TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < splitDay.exercises.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E2E3E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    splitDay.exercises[i].name,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                Text(
                  splitDay.exercises[i].muscleGroup,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

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
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.splitDayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${session.totalSets} sets',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${session.totalVolume.toStringAsFixed(0)} kg',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E2C),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF2E2E3E)),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF4B5563), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
