import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../models/workout_view_model.dart';
import '../services/persistence_service.dart';
import '../services/workout_service.dart';
import '../services/recovery_service.dart';
import 'workout_setup_screen.dart';
import 'workout_session_screen.dart';
import 'workout_history_screen.dart';
import '../widgets/muscle_body_map.dart';

// ─── WorkoutScreen ────────────────────────────────────────────────────────────
//
// Primary Train tab (tab root inside AppShell). The shell paints the flat
// base, so this Scaffold is transparent.
//
// States (resolved in one place, [build]):
//   1. Not Ready    → shimmer skeleton shaped like the dashboard
//   2. Setup Needed → onboarding prompt
//   3. Dashboard    → today's session hero, weekly ring, recovery and trends
//
// Motion moments:
//   • Entrance  — one staggered reveal of the dashboard sections (plays once).
//   • Hero CTA  — the accent "Start workout" pill (the log action). Static:
//                 Graphite draws no glow, so nothing loops. Every other
//                 surface stays monochrome.
//   • Data      — weekly ring springs to value, numbers count, bars grow.
//   • State     — the draft card and hero state cross-fade (AnimatedSwitcher).

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  /// Bumped by other tabs (Nutrition's "Start workout") to open today's
  /// session, or resume the paused one, straight away.
  static final startRequests = ValueNotifier<int>(0);

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  void _onStartRequest() {
    if (!mounted || !_svc.isReady || !_svc.isSetupDone) return;
    // After the tab switch settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final draft = _svc.draftSession;
      if (draft != null) {
        _resumeWorkout(draft);
      } else {
        _startWorkout();
      }
    });
  }

  final _svc = WorkoutService.instance;
  WorkoutDashboardViewModel? _viewModel;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onServiceChange);
    WorkoutScreen.startRequests.addListener(_onStartRequest);
    // The day's pick on the Nutrition tab (Push, Pull, rest) drives the hero.
    PersistenceService.dayLogNotifier.addListener(_onServiceChange);
    if (_svc.isReady) {
      _viewModel = WorkoutDashboardViewModel.from(_svc);
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceChange);
    WorkoutScreen.startRequests.removeListener(_onStartRequest);
    PersistenceService.dayLogNotifier.removeListener(_onServiceChange);
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

  bool _adopting = false;

  Future<void> _adoptDevelopersChoice() async {
    if (_adopting) return;
    setState(() => _adopting = true);
    try {
      await _svc.adoptDevelopersChoice();
      KHaptics.success();
    } finally {
      if (mounted) setState(() => _adopting = false);
    }
  }

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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen()));
  }

  /// Starts today's planned session straight away (no confirmation sheet).
  /// On a rest day there is no plan, so it opens the day picker instead.
  Future<void> _startWorkout() async {
    final planned = _svc.todaySplitDay;
    if (planned == null) return _pickAnotherDay();
    await _launch(_WorkoutStartSelection(splitDay: planned, wasManual: false));
  }

  /// Secondary path: choose another split day or a custom session.
  Future<void> _pickAnotherDay() async {
    final picked = await _pickWorkoutDay();
    if (!mounted || picked == null) return;
    await _launch(picked);
  }

  Future<void> _launch(_WorkoutStartSelection picked) async {
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
    return showKSheet<_WorkoutStartSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkoutDayPickerSheet(service: _svc),
    );
  }

  double _bottomClearance(BuildContext context) => math.max(
    KSpacing.dockClearance,
    MediaQuery.paddingOf(context).bottom + KSpacing.lg,
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_svc.isReady) {
      return const _WorkoutDashboardSkeleton();
    }

    if (!_svc.isSetupDone) return _buildSetupPrompt();

    final vm = _viewModel ?? WorkoutDashboardViewModel.from(_svc);
    final todaySplit = _svc.todaySplitDay;
    final draft = _svc.draftSession;

    final sections = <Widget>[
      // 1. Draft session (only while a workout is paused)
      _AnimatedSlot(
        key: const ValueKey('draft-slot'),
        child: draft == null
            ? const SizedBox(key: ValueKey('no-draft'), width: double.infinity)
            : Padding(
                key: ValueKey('draft-${draft.id}'),
                padding: const EdgeInsets.only(bottom: KSpacing.lg),
                child: _DraftSessionCard(
                  session: draft,
                  onResume: () => _resumeWorkout(_svc.draftSession!),
                  onDiscard: () => _svc.clearDraftSession(),
                ),
              ),
      ),

      // 2. Hero: today's session or a rest day
      Padding(
        key: const ValueKey('hero'),
        padding: const EdgeInsets.only(bottom: KSpacing.lg),
        child: todaySplit != null
            ? _TodaySplitCard(
                splitDay: todaySplit,
                viewModel: vm,
                onStart: _startWorkout,
                onPickAnother: _pickAnotherDay,
                hasDraft: draft != null,
              )
            : _RecoveryBannerCard(viewModel: vm, onStartManual: _pickAnotherDay),
      ),

      // 3. Weekly consistency ring
      Padding(
        key: const ValueKey('weekly'),
        padding: const EdgeInsets.fromLTRB(4, KSpacing.md, 4, KSpacing.lg),
        child: _WeeklyRingCard(viewModel: vm, service: _svc),
      ),

      // 4. Quick stats
      Padding(
        key: const ValueKey('stats'),
        padding: const EdgeInsets.fromLTRB(4, 0, 4, KSpacing.xxl),
        child: _QuickStatsRow(viewModel: vm),
      ),

      // 5. Last workout
      Padding(
        key: const ValueKey('recent'),
        padding: const EdgeInsets.only(bottom: KSpacing.lg),
        child: _RecentWorkoutCard(
          viewModel: vm,
          onStart: _startWorkout,
          onViewDetails: (session) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SessionDetailPage(session: session, service: _svc),
              ),
            );
          },
        ),
      ),

      // 6. Recovery insights
      Padding(
        key: const ValueKey('recovery'),
        padding: const EdgeInsets.fromLTRB(4, KSpacing.lg, 4, KSpacing.xxl),
        child: _RecoveryInsightsCard(viewModel: vm),
      ),

      // 7. Analytics & trends
      Padding(
        key: const ValueKey('analytics'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _AnalyticsCard(viewModel: vm),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: KReveal(
                child: _TrainHeader(
                  onHistory: _openHistory,
                  onEditSplit: () => _openSetup(editMode: true),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              KSpacing.p,
              KSpacing.sm,
              KSpacing.p,
              _bottomClearance(context),
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                for (var i = 0; i < sections.length; i++)
                  KReveal(
                    key: sections[i].key,
                    index: i + 1,
                    child: sections[i],
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Setup Prompt ───────────────────────────────────────────────────────────

  Widget _buildSetupPrompt() => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      bottom: false,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            KSpacing.xxxl,
            KSpacing.xxl,
            KSpacing.xxxl,
            _bottomClearance(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: kStagger([
              const _SetupEmblem(),
              Padding(
                padding: const EdgeInsets.only(top: KSpacing.xxxl),
                child: Text(
                  'Build your training split',
                  textAlign: TextAlign.center,
                  style: KText.display,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  "Start on the split Kynetix's developer runs, or answer three questions and we'll build one around you. Either way it's yours to change.",
                  textAlign: TextAlign.center,
                  style: KText.body.copyWith(color: KColor.textSecondary),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child: _DevelopersChoicePreview(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: KButton(
                    label: "Use Developer's Choice",
                    icon: Icons.arrow_forward_rounded,
                    loading: _adopting,
                    onTap: _adoptDevelopersChoice,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: KButton(
                    label: 'Build my own',
                    outlined: true,
                    onTap: _openSetup,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// The seven days of the Developer's Choice, as a strip of chips.
class _DevelopersChoicePreview extends StatelessWidget {
  const _DevelopersChoicePreview();

  @override
  Widget build(BuildContext context) {
    final days = developersChoiceSplit.days;
    return Container(
      padding: const EdgeInsets.all(KSpacing.md),
      decoration: _trainSurface(radius: KRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, size: 16, color: KColor.ink),
              const SizedBox(width: 6),
              Text(developersChoiceName, style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('6 days', style: KText.caption.copyWith(color: KColor.textMuted)),
            ],
          ),
          const SizedBox(height: KSpacing.sm),
          for (final d in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      _weekdayLong[d.weekday - 1].substring(0, 3),
                      style: KText.caption.copyWith(color: KColor.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      d.isRestDay ? 'Rest' : d.name,
                      style: KText.body.copyWith(
                        fontSize: 14,
                        color: d.isRestDay ? KColor.textMuted : KColor.textPrimary,
                      ),
                    ),
                  ),
                  if (!d.isRestDay)
                    Text(
                      '${d.exercises.length} lifts',
                      style: KText.caption.copyWith(
                        color: KColor.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
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

// ─── Shared private helpers ──────────────────────────────────────────────────

const _weekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _weekdayInitial = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Card surface for Train hero cards. Train colour is an accent, not a wash:
/// only a faint corner tint that fades into the plain card by mid-card.
BoxDecoration _trainSurface({
  double tint = 0.16,
  Color? borderColor,
  BorderRadius radius = KRadius.xl,
  List<BoxShadow>? shadow,
}) {
  // Graphite: flat card and hairline. [tint] is kept for the call sites;
  // colour lives in the content, not the surface.
  return BoxDecoration(
    borderRadius: radius,
    color: KColor.card,
    border: Border.all(color: borderColor ?? KColor.hairline),
    boxShadow: shadow,
  );
}

/// Small sentence-case eyebrow label.
class _Eyebrow extends StatelessWidget {
  final String text;
  final Color? _color;
  Color get color => _color ?? KColor.textMuted;
  const _Eyebrow(this.text, {Color? color}) : _color = color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: KText.label.copyWith(
        color: color,
        fontSize: 12,
        letterSpacing: 0.2,
      ),
    );
  }
}

/// Cross-fades and resizes when its child (by key) changes.
class _AnimatedSlot extends StatelessWidget {
  final Widget child;
  const _AnimatedSlot({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: KMotion.of(context, KMotion.standard),
      switchInCurve: KMotion.emphasizedCurve,
      switchOutCurve: KMotion.accelerate,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(
          sizeFactor: anim,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Compact action button: filled (ink or a semantic colour) or outlined.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final List<Color> colors;
  final Color foreground;
  final bool outlined;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.colors,
    required this.foreground,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      borderRadius: KRadius.md,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: KRadius.md,
          gradient: outlined ? null : LinearGradient(colors: colors),
          border: Border.all(
            color: outlined
                ? colors.first.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: KText.h3.copyWith(color: foreground, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _TrainHeader ────────────────────────────────────────────────────────────

class _TrainHeader extends StatelessWidget {
  final VoidCallback onHistory;
  final VoidCallback onEditSplit;

  const _TrainHeader({required this.onHistory, required this.onEditSplit});

  @override
  Widget build(BuildContext context) {
    final today = _weekdayLong[DateTime.now().weekday - 1];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.p,
        KSpacing.lg,
        KSpacing.md,
        KSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Eyebrow(today, color: KColor.textSecondary),
                const SizedBox(height: KSpacing.xs),
                Semantics(
                  header: true,
                  child: Text(
                    'Train',
                    style: KText.display.copyWith(fontSize: 32),
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            icon: Icons.history_rounded,
            tooltip: 'Workout history',
            onPressed: onHistory,
          ),
          const SizedBox(width: KSpacing.sm),
          _HeaderAction(
            icon: Icons.edit_note_rounded,
            tooltip: 'Edit split',
            onPressed: onEditSplit,
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: KColor.textPrimary),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: KColor.isDark
            ? KColor.fg.withValues(alpha: 0.06)
            : KColor.card,
        side: BorderSide(
          color: KColor.isDark
              ? KColor.fg.withValues(alpha: 0.09)
              : KColor.border,
        ),
      ),
    );
  }
}

// ─── _TodaySplitCard (hero) ──────────────────────────────────────────────────
// The one card on the tab with a tint: today's session is a real object. The
// primary action starts it directly; "Pick another day" is the quiet escape.

class _TodaySplitCard extends StatelessWidget {
  final SplitDay splitDay;
  final WorkoutDashboardViewModel viewModel;
  final VoidCallback onStart;
  final VoidCallback onPickAnother;
  final bool hasDraft;

  const _TodaySplitCard({
    required this.splitDay,
    required this.viewModel,
    required this.onStart,
    required this.onPickAnother,
    this.hasDraft = false,
  });

  @override
  Widget build(BuildContext context) {
    final todaySession = viewModel.recentSessions.where((s) {
      return s.splitDayName == splitDay.name &&
          DateUtils.isSameDay(s.date, DateTime.now());
    }).firstOrNull;
    final done = todaySession != null;

    final muscles = splitDay.exercises
        .map((e) => e.muscleGroup)
        .toSet()
        .toList();
    final musclesStr = muscles.isEmpty ? 'All muscles' : muscles.join(', ');
    final duration = splitDay.exercises.length * 9;

    // Done reads in ink with a check; the plan dot is the one accent.
    final done2 = KColor.ink;
    return KHeroSurface(
      tone: KTone.train,
      padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.xl, KSpacing.xl, KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status eyebrow
          AnimatedSwitcher(
            duration: KMotion.of(context, KMotion.quick),
            child: Row(
              key: ValueKey(done),
              children: [
                if (done)
                  KIcon(KIcons.done, color: done2, size: KIcons.sm)
                else
                  KGlowDot(color: KColor.ember),
                const SizedBox(width: KSpacing.sm),
                Expanded(
                  child: _Eyebrow(
                    done ? 'Done for today' : 'On the plan today',
                    color: done ? done2 : KColor.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            splitDay.name,
            style: KText.display.copyWith(fontSize: 38, height: 1.04, color: KHeroInk.primary),
          ),
          const SizedBox(height: 6),
          Text(
            musclesStr,
            style: KText.bodyMedium.copyWith(color: KHeroInk.secondary),
          ),
          const SizedBox(height: KSpacing.lg),
          Wrap(
            spacing: KSpacing.xxl,
            runSpacing: KSpacing.md,
            children: [
              _HeroMetric(
                value: splitDay.exercises.length,
                label: splitDay.exercises.length == 1 ? 'exercise' : 'exercises',
                icon: Icons.format_list_bulleted_rounded,
              ),
              _HeroMetric(
                value: duration,
                prefix: '~',
                label: 'min',
                icon: KIcons.timer,
              ),
            ],
          ),
          const SizedBox(height: KSpacing.lg),
          AnimatedSwitcher(
            duration: KMotion.of(context, KMotion.standard),
            switchInCurve: KMotion.emphasizedCurve,
            child: done
                ? Column(
                    key: const ValueKey('done'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: KSpacing.lg),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: KIcon(KIcons.done, color: done2, size: KIcons.sm),
                            ),
                            const SizedBox(width: KSpacing.sm),
                            Expanded(
                              child: Text(
                                todaySession.totalWorkingVolume > 0
                                    ? 'Logged ${plural(todaySession.totalSets, 'set')}, ${thousands(todaySession.totalWorkingVolume)} kg moved.'
                                    : 'Logged ${plural(todaySession.totalSets, 'set')}, all bodyweight.',
                                style: KText.bodyMedium.copyWith(
                                  color: KHeroInk.primary,
                                  fontSize: 14,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      KButton(
                        label: 'Log another session',
                        icon: Icons.refresh_rounded,
                        outlined: true,
                        onTap: onPickAnother,
                      ),
                      const SizedBox(height: KSpacing.sm),
                    ],
                  )
                : Column(
                    key: const ValueKey('start'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TrainCta(
                        label: 'Start workout',
                        // When a paused workout exists, Resume owns the glow.
                        glow: false,
                        onTap: onStart,
                      ),
                      const SizedBox(height: KSpacing.xs),
                      Center(
                        child: TextButton(
                          onPressed: onPickAnother,
                          style: TextButton.styleFrom(
                            foregroundColor: KHeroInk.secondary,
                            minimumSize: const Size(48, 48),
                            shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
                          ),
                          child: Text(
                            'Pick another day',
                            style: KText.bodyMedium.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: KHeroInk.secondary,
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
}

class _HeroMetric extends StatelessWidget {
  final int value;
  final String label;
  final String prefix;
  final IconData icon;

  const _HeroMetric({
    required this.value,
    required this.label,
    required this.icon,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        KIcon(icon, color: KHeroInk.muted, size: KIcons.sm),
        const SizedBox(width: 6),
        KAnimatedCount(
          value: value,
          prefix: prefix,
          style: KText.numMedium.copyWith(fontSize: 24, color: KHeroInk.primary),
        ),
        const SizedBox(width: KSpacing.xs),
        Text(label, style: KText.caption.copyWith(color: KHeroInk.muted)),
      ],
    );
  }
}

// ─── _TrainCta ───────────────────────────────────────────────────────────────
// The hero's primary action: a solid accent pill, the log action. Graphite
// draws no glow, so there is no halo and no breathing loop: the pill is
// static and costs nothing per frame. [glow] is kept for call sites.

class _TrainCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool glow;

  const _TrainCta({
    required this.label,
    required this.onTap,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final face = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.xl,
        vertical: 14,
      ),
      // Train's one coloured action: the log action wears the accent.
      decoration: BoxDecoration(
        borderRadius: KRadius.pill,
        color: KColor.ember,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_arrow_rounded, color: KColor.onAccent, size: KIcons.lg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: KText.h3.copyWith(
                color: KColor.onAccent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );

    void activate() {
      KHaptics.commit();
      onTap();
    }

    // Its own semantics node (container) with a tap action, so a screen
    // reader can find and activate Start inside the hero card.
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: activate,
      excludeSemantics: true,
      child: Pressable(
        borderRadius: KRadius.pill,
        onTap: activate,
        child: face,
      ),
    );
  }
}

// ─── _RecoveryBannerCard (rest-day hero) ─────────────────────────────────────

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
      padding: const EdgeInsets.all(KSpacing.xl),
      decoration: _trainSurface(tint: 0.14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bedtime_rounded, color: KColor.textSecondary, size: 16),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: _Eyebrow('Rest day', color: KColor.textSecondary),
              ),
              ExcludeSemantics(
                child: Icon(
                  Icons.spa_rounded,
                  color: KColor.textDisabled,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Rest and recovery',
            style: KText.display.copyWith(fontSize: 32, height: 1.05),
          ),
          const SizedBox(height: KSpacing.sm),
          Text(
            'Nothing on the plan today. Eat well, sleep well, maybe some light mobility. Growth happens here too.',
            style: KText.body.copyWith(color: KColor.textSecondary),
          ),
          const SizedBox(height: KSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'Start a workout anyway',
              icon: Icons.play_arrow_rounded,
              outlined: true,
              onTap: onStartManual,
            ),
          ),
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
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      borderRadius: KRadius.lg,
      border: Border.all(
        color: KColor.warning.withValues(alpha: KColor.isDark ? 0.35 : 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pause_circle_filled_rounded,
                color: KColor.warning,
                size: 20,
              ),
              const SizedBox(width: KSpacing.sm),
              Expanded(child: Text('Workout in progress', style: KText.h3)),
              const SizedBox(width: KSpacing.sm),
              Text(
                plural(session.totalSets, 'set'),
                style: KText.numSmall.copyWith(fontSize: 13, color: KColor.warning),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You paused "${session.splitDayName}". Pick up right where you left off.',
            style: KText.body.copyWith(
              color: KColor.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _ActionButton(
                  label: 'Resume workout',
                  icon: Icons.play_arrow_rounded,
                  colors: [KColor.ink, KColor.ink],
                  foreground: KColor.onInk,
                  onTap: () {
                    KHaptics.commit();
                    onResume();
                  },
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                flex: 1,
                child: _ActionButton(
                  label: 'Discard',
                  icon: Icons.close_rounded,
                  colors: [KColor.danger],
                  foreground: KColor.danger,
                  outlined: true,
                  onTap: () {
                    KHaptics.commit();
                    onDiscard();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── _Section ────────────────────────────────────────────────────────────────
// Editorial grouping: a sentence-case heading and an optional trailing value,
// then content on the page itself. No card.

class _Section extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget child;

  const _Section({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: KText.h2.copyWith(fontSize: 20)),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: KText.numSmall.copyWith(
                  fontSize: 14,
                  color: KColor.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: KSpacing.md),
        child,
      ],
    );
  }
}

Color _rule() => KColor.isDark ? KColor.fg.withValues(alpha: 0.09) : KColor.border;

// ─── _WeeklyRingCard ─────────────────────────────────────────────────────────
// "This week": a Mon–Sun strip where each day's state is told by shape
// (check done, ring planned, dash rest), one slim bar for the week, and the
// consistency read. Typography and hairlines, no container.

class _WeeklyRingCard extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;
  final WorkoutService service;

  const _WeeklyRingCard({required this.viewModel, required this.service});

  @override
  Widget build(BuildContext context) {
    final fraction = viewModel.weekCompletionFraction;
    final label = viewModel.weekCompletionLabel;
    final todayWd = DateTime.now().weekday;

    return _Section(
      title: 'This week',
      trailing: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var wd = 1; wd <= 7; wd++)
                Expanded(
                  child: _DayPip(
                    initial: _weekdayInitial[wd - 1],
                    day: service.split.dayFor(wd),
                    // Done = a workout was logged ON that date (whatever
                    // split day it was), not "that split day was done
                    // somewhere this week".
                    done: () {
                      final now = DateTime.now();
                      final date = DateTime(now.year, now.month, now.day)
                          .subtract(Duration(days: todayWd - wd));
                      return service.sessionsForDate(date).any((s) => !s.isEmpty);
                    }(),
                    isToday: wd == todayWd,
                  ),
                ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          KBar(
            progress: fraction,
            colors: KGradient.primary,
            height: 4,
          ),
          const SizedBox(height: KSpacing.sm),
          Text(
            'Consistency: ${viewModel.consistencyLabel}',
            style: KText.caption.copyWith(color: KColor.textSecondary),
          ),
          if (viewModel.musclesThisWeek.isNotEmpty) ...[
            const SizedBox(height: KSpacing.md),
            // One body, front and back, with this week's muscles lit, then
            // their names as plain words.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (viewModel.musclesThisWeek.any(MuscleThumb.canShow)) ...[
                  SizedBox(
                    width: 104,
                    child: MuscleBodyMap(
                      view: BodyView.sideBySide,
                      highlightedMuscles: viewModel.musclesThisWeek.toSet(),
                      height: 96,
                    ),
                  ),
                  const SizedBox(width: KSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trained this week',
                        style: KText.caption.copyWith(color: KColor.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        viewModel.musclesThisWeek.join(', '),
                        style: KText.bodyMedium.copyWith(color: KColor.textPrimary, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DayPip extends StatelessWidget {
  final String initial;
  final SplitDay? day;
  final bool done;
  final bool isToday;

  const _DayPip({
    required this.initial,
    required this.day,
    required this.done,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final training = day != null && !day!.isRestDay;
    final state = done ? 'done' : (training ? 'planned' : 'rest');
    return Semantics(
      label: '$initial ${day?.name ?? 'Rest day'}, $state',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            initial,
            style: KText.label.copyWith(
              color: isToday ? KColor.textPrimary : KColor.textMuted,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: KMotion.of(context, KMotion.standard),
            curve: KMotion.overshoot,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? KColor.ink : null,
              border: done
                  ? null
                  : Border.all(
                      color: training
                          ? KColor.ink.withValues(
                              alpha: isToday ? 0.9 : 0.45,
                            )
                          : KColor.fg.withValues(
                              alpha: KColor.isDark ? 0.12 : 0.14,
                            ),
                      width: isToday ? 2 : 1.2,
                    ),
            ),
            child: Center(
              child: done
                  ? Icon(Icons.check_rounded, size: 14, color: KColor.onInk)
                  : training
                  ? null
                  : Container(width: 8, height: 2, color: KColor.textDisabled),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _QuickStatsRow ──────────────────────────────────────────────────────────
// Four numbers on one hairline-ruled row. The numbers are the content; no
// tiles, no icons.

class _QuickStatsRow extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;

  const _QuickStatsRow({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final vol = viewModel.totalVolumeThisWeek;
    final big = vol >= 1000;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _rule()),
          bottom: BorderSide(color: _rule()),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _QuickStatCard(
              label: 'kg lifted',
              value: big ? vol / 1000 : vol,
              decimals: big ? 1 : 0,
              suffix: big ? 'k' : '',
            ),
            const _StatRule(),
            _QuickStatCard(
              label: viewModel.totalSetsThisWeek == 1 ? 'set' : 'sets',
              value: viewModel.totalSetsThisWeek,
            ),
            const _StatRule(),
            _QuickStatCard(
              label: 'day streak',
              value: viewModel.currentStreak,
            ),
            const _StatRule(),
            _QuickStatCard(
              label: viewModel.totalPrsAllTime == 1 ? 'PR, all time' : 'PRs, all time',
              value: viewModel.totalPrsAllTime,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRule extends StatelessWidget {
  const _StatRule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.sm),
        child: VerticalDivider(width: 1, thickness: 1, color: _rule()),
      );
}

class _QuickStatCard extends StatelessWidget {
  final String label;
  final num value;
  final int decimals;
  final String suffix;

  const _QuickStatCard({
    required this.label,
    required this.value,
    this.decimals = 0,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KAnimatedCount(
            value: value,
            decimalPlaces: decimals,
            suffix: suffix,
            style: KText.numMedium.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: KText.caption.copyWith(color: KColor.textSecondary, fontSize: 12),
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
  final VoidCallback? onStart;

  const _RecentWorkoutCard({
    required this.viewModel,
    required this.onViewDetails,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final recent = viewModel.recentSessions;
    if (recent.isEmpty) {
      return KCard(
        padding: EdgeInsets.zero,
        borderRadius: KRadius.xl,
        child: KEmptyState(
          type: KEmptyStateType.workout,
          title: 'Nothing logged yet',
          message:
              'Your first session sets the tone. Stats show up here once you save one.',
          actionLabel: onStart == null ? null : 'Start workout',
          onAction: onStart,
          kyno: true,
        ),
      );
    }

    final session = recent.first;
    final d = session.date;
    final dateStr = '${d.day}/${d.month}/${d.year % 100}';
    final durationStr = session.durationMinutes != null
        ? '${session.durationMinutes} min'
        : '-';

    return KCard(
      padding: const EdgeInsets.all(18),
      borderRadius: KRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _Eyebrow('Last workout')),
              const SizedBox(width: KSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: KColor.fg.withValues(
                    alpha: KColor.isDark ? 0.06 : 0.05,
                  ),
                  borderRadius: KRadius.pill,
                ),
                child: Text(
                  dateStr,
                  style: KText.numSmall.copyWith(
                    color: KColor.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          Text(session.splitDayName, style: KText.h2),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RecentStat(
                label: 'Volume',
                value: '${whole(session.totalVolume)} kg',
              ),
              _RecentStat(label: 'Sets', value: plural(session.totalSets, 'set')),
              _RecentStat(label: 'Duration', value: durationStr),
            ],
          ),
          const SizedBox(height: KSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: KButton(
              label: 'View session details',
              icon: Icons.arrow_forward_rounded,
              outlined: true,
              onTap: () => onViewDetails(session),
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
            style: KText.caption.copyWith(
              color: KColor.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: KSpacing.xs),
          Text(value, style: KText.numSmall.copyWith(fontSize: 15)),
        ],
      ),
    );
  }
}

// ─── _RecoveryInsightsCard ───────────────────────────────────────────────────
// Readiness, sleep, HRV and fatigue load as one editorial section: a bar, three
// plain figures and a single coaching line. Colour marks state and always
// travels with an icon and a word.

class _RecoveryInsightsCard extends StatelessWidget {
  final WorkoutDashboardViewModel viewModel;
  const _RecoveryInsightsCard({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final recovery = viewModel.recovery;
    final overall = recovery.overallReadiness;
    final label = recovery.readinessLabel;
    final sleepScore = recovery.sleepScore;
    final hrvScore = recovery.hrvScore;
    final sleepHours = WorkoutService.instance.sleepHours;
    final hrvRmssd = WorkoutService.instance.hrvRmssd;
    final acwrBand = viewModel.acwrBand;

    final lastSession = viewModel.recentSessions.firstOrNull;
    final daysSinceLast = lastSession != null
        ? DateTime.now().difference(lastSession.date).inDays
        : -1;
    final daysStr = daysSinceLast == -1
        ? 'nothing logged yet'
        : daysSinceLast == 0
        ? 'today'
        : '${plural(daysSinceLast, 'day')} ago';

    final (acwrColor, acwrIcon) = switch (acwrBand) {
      AcwrBand.normal => (KColor.green, Icons.check_circle_outline_rounded),
      AcwrBand.elevated => (KColor.warning, Icons.trending_up_rounded),
      AcwrBand.high => (KColor.danger, Icons.warning_amber_rounded),
      AcwrBand.extreme => (KColor.danger, Icons.report_outlined),
    };

    final (readyColor, readyIcon) = overall >= 0.8
        ? (KColor.green, Icons.check_circle_outline_rounded)
        : overall >= 0.6
        ? (KColor.warning, Icons.adjust_rounded)
        : (KColor.danger, Icons.error_outline_rounded);

    return _Section(
      title: 'Recovery',
      trailing: 'Last workout $daysStr',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KIcon(readyIcon, color: readyColor, size: KIcons.md),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '${(overall * 100).toStringAsFixed(0)}% ready',
                      style: KText.h3.copyWith(
                        fontSize: 17,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '  $label',
                      style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 14),
                    ),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          KBar(
            progress: overall,
            colors: [readyColor.withValues(alpha: 0.7), readyColor],
            height: 4,
          ),
          const SizedBox(height: KSpacing.lg),

          // Recovery metrics: plain figures under small labels.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Muscles',
                  value: recovery.muscles.isEmpty ? 'Fresh' : 'Recovering',
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'Sleep',
                  value: sleepHours != null && sleepScore != null
                      ? '${sleepHours.toStringAsFixed(1)} h, ${(sleepScore * 100).toStringAsFixed(0)}%'
                      : 'Not synced',
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'HRV (RMSSD)',
                  value: hrvRmssd != null && hrvScore != null
                      ? '${hrvRmssd.toStringAsFixed(0)} ms, ${(hrvScore * 100).toStringAsFixed(0)}%'
                      : 'Not synced',
                ),
              ),
            ],
          ),

          if (recovery.muscles.isNotEmpty) ...[
            const SizedBox(height: KSpacing.md),
            for (final m in recovery.muscles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    KIcon(
                      m.state == RecoveryState.recovering
                          ? Icons.hourglass_bottom_rounded
                          : m.state == RecoveryState.ready
                          ? Icons.adjust_rounded
                          : Icons.check_rounded,
                      size: KIcons.sm,
                      color: m.state == RecoveryState.recovering
                          ? KColor.danger
                          : m.state == RecoveryState.ready
                          ? KColor.warning
                          : KColor.green,
                    ),
                    const SizedBox(width: KSpacing.sm),
                    Expanded(
                      child: Text(
                        m.muscleGroup,
                        style: KText.bodyMedium.copyWith(fontSize: 14),
                      ),
                    ),
                    Text(
                      '${m.hoursSinceLastTraining} h ago',
                      style: KText.numSmall.copyWith(fontSize: 13, color: KColor.textSecondary),
                    ),
                  ],
                ),
              ),
          ],

          const SizedBox(height: KSpacing.lg),

          // Fatigue load: one line of coaching, keyed by icon and colour.
          Container(
            padding: const EdgeInsets.only(top: KSpacing.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _rule())),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: KIcon(acwrIcon, color: acwrColor, size: KIcons.md),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Fatigue load: ${acwrBand.label}',
                              style: KText.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            'ACWR ${WorkoutService.instance.calculateAcwr().toStringAsFixed(2)}',
                            style: KText.numSmall.copyWith(
                              color: KColor.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(acwrBand.coachingInsight, style: KText.caption),
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

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: KSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: KText.caption.copyWith(
              color: KColor.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: KText.numSmall.copyWith(fontSize: 14)),
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
    return _Section(
      title: 'Training trends',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewModel.latestPr != null) ...[
            _HighlightCard(
              title: viewModel.latestPr!.title,
              detail: viewModel.latestPr!.detail,
            ),
            const SizedBox(height: KSpacing.lg),
          ],
          _TrendBlock(
            title: 'Weekly volume',
            values: viewModel.volumeTrend,
            valueFormatter: (v) => '${whole(v)} kg',
          ),
          const SizedBox(height: KSpacing.lg),
          _TrendBlock(
            title: 'Workout consistency',
            values: viewModel.consistencyTrend
                .map((v) => v.toDouble())
                .toList(),
            valueFormatter: (v) => plural(v.round(), 'workout'),
          ),
        ],
      ),
    );
  }
}

// ─── _HighlightCard ──────────────────────────────────────────────────────────
// Latest personal record: accent mark, plain words.

class _HighlightCard extends StatelessWidget {
  final String title;
  final String detail;
  const _HighlightCard({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: KIcon(KIcons.record, color: KColor.ember, size: KIcons.md),
      ),
      const SizedBox(width: KSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: KText.numSmall.copyWith(fontSize: 13, color: KColor.textSecondary),
            ),
          ],
        ),
      ),
    ],
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: KText.caption.copyWith(
                  color: KColor.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: KSpacing.sm),
            Text(
              valueFormatter(latest),
              style: KText.numSmall.copyWith(
                color: KColor.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: KSpacing.sm),
        _MiniBarChart(values: values),
      ],
    );
  }
}

// ─── _MiniBarChart ───────────────────────────────────────────────────────────
// Bars grow from the baseline once (and re-grow when values change). The
// latest bar carries the train gradient; older bars are neutral ink at low
// alpha, so colour marks only the value that matters now. A hairline baseline
// anchors the bars on both Carbon and Paper.

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
          'Not enough sessions yet. Give it a week.',
          style: KText.caption.copyWith(color: KColor.textSecondary),
        ),
      );
    }
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final restBar = KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.12);
    return Container(
      height: 49,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: KColor.fg.withValues(alpha: KColor.isDark ? 0.1 : 0.12),
          ),
        ),
      ),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(Object.hashAll(values)),
        tween: Tween(begin: 0, end: 1),
        duration: KMotion.of(context, KMotion.slow),
        curve: KMotion.emphasizedCurve,
        builder: (context, t, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height:
                          (maxValue <= 0
                              ? 6.0
                              : (values[i] / maxValue * 42).clamp(6.0, 42.0)) *
                          (0.15 + 0.85 * t),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        color: i == values.length - 1
                            ? KColor.ink
                            : restBar,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── _WorkoutDashboardSkeleton ───────────────────────────────────────────────
// Shimmer shaped like the dashboard (header, hero, ring card, stats). The
// shimmer loop is owned by KShimmer and gated by ambient motion.

class _WorkoutDashboardSkeleton extends StatelessWidget {
  const _WorkoutDashboardSkeleton();

  static Widget _box({
    double? width,
    required double height,
    BorderRadius radius = KRadius.md,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: radius),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(
      KSpacing.dockClearance,
      MediaQuery.paddingOf(context).bottom + KSpacing.lg,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Semantics(
          label: 'Warming up…',
          child: KShimmer(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                KSpacing.p,
                KSpacing.lg,
                KSpacing.p,
                bottom,
              ),
              children: [
                _box(width: 80, height: 10, radius: KRadius.pill),
                const SizedBox(height: 10),
                _box(width: 120, height: 30),
                const SizedBox(height: KSpacing.xl),
                // Hero
                _box(height: 230, radius: KRadius.xl),
                const SizedBox(height: KSpacing.lg),
                // Ring card
                Row(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: KSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _box(width: 90, height: 10, radius: KRadius.pill),
                          const SizedBox(height: 10),
                          _box(width: 120, height: 20),
                          const SizedBox(height: 10),
                          _box(width: 140, height: 10, radius: KRadius.pill),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.lg),
                Row(
                  children: [
                    Expanded(child: _box(height: 92, radius: KRadius.lg)),
                    const SizedBox(width: KSpacing.sm),
                    Expanded(child: _box(height: 92, radius: KRadius.lg)),
                  ],
                ),
                const SizedBox(height: KSpacing.lg),
                _box(height: 150, radius: KRadius.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _SetupEmblem ────────────────────────────────────────────────────────────

class _SetupEmblem extends StatelessWidget {
  const _SetupEmblem();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: KRing(
          progress: 0.72,
          colors: KGradient.primary,
          size: 104,
          stroke: 6,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KColor.ink.withValues(alpha: KColor.isDark ? 0.08 : 0.06),
              border: Border.all(
                color: KColor.ink.withValues(alpha: KColor.isDark ? 0.24 : 0.20),
              ),
            ),
            child: Icon(
              Icons.fitness_center_rounded,
              color: KColor.ink,
              size: 34,
            ),
          ),
        ),
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

/// "Pick a day": every training day as one hairline row (today's plan first,
/// marked "Today"), then a custom session. It never repeats the hero card; the
/// hero already starts today's plan directly.
class _WorkoutDayPickerSheet extends StatelessWidget {
  final WorkoutService service;
  const _WorkoutDayPickerSheet({required this.service});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final planned = service.splitDayFor(today);
    final selectable = service.selectableWorkoutDaysFor(today);
    final others = selectable
        .where((d) => d.weekday != planned?.weekday)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: true,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: KColor.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: KColor.isDark
                    ? KColor.fg.withValues(alpha: 0.08)
                    : KColor.border,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                KSheetHeader(
                  'Pick a day',
                  subtitle: planned == null
                      ? "Rest day on the plan. Train anyway if you're up for it."
                      : 'Train a different day from your split.',
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      KSpacing.p,
                      KSpacing.sm,
                      KSpacing.p,
                      KSpacing.xxl,
                    ),
                    children: [
                      if (planned != null)
                        _dayRow(context, planned, isToday: true),
                      for (final d in others) _dayRow(context, d),
                      _customRow(context),
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

  Widget _row(
    BuildContext context, {
    required String semanticLabel,
    required VoidCallback onTap,
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final hairline = KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: hairline)),
          ),
          child: Row(
            children: [
              SizedBox(width: 28, child: leading),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: KText.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: KSpacing.md),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayRow(BuildContext context, SplitDay d, {bool isToday = false}) {
    final n = d.exercises.length;
    final when = isToday ? 'Today' : _weekdayLabel(d.weekday);
    return _row(
      context,
      semanticLabel: '${d.name}, $when, ${plural(n, 'exercise')}',
      onTap: () {
        KHaptics.select();
        Navigator.of(context).pop(
          _WorkoutStartSelection(splitDay: d, wasManual: !isToday),
        );
      },
      leading: KIcon(
        KIcons.split(d.name),
        size: KIcons.md,
        color: isToday ? KColor.ink : KColor.textSecondary,
      ),
      title: d.name,
      subtitle: '${plural(n, 'exercise')}, about ${n * 9} min',
      trailing: Text(
        when,
        style: KText.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: isToday ? KColor.textPrimary : KColor.textMuted,
        ),
      ),
    );
  }

  Widget _customRow(BuildContext context) {
    return _row(
      context,
      semanticLabel: 'Custom or empty workout',
      onTap: () {
        KHaptics.select();
        Navigator.of(context).pop(
          _WorkoutStartSelection(
            splitDay: service.customWorkoutDay(),
            wasManual: true,
          ),
        );
      },
      leading: KIcon(KIcons.add, size: KIcons.md, color: KColor.textPrimary),
      title: 'Custom or empty workout',
      subtitle: 'Start empty and add exercises as you go',
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
