import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import 'dashboard_screen.dart';
import 'workout_screen.dart';
import 'workout_session_screen.dart';
import 'ai_coach_screen.dart';
import 'profile_tab.dart';
import '../widgets/k_avatar.dart';

// ─── AppShell ─────────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

  /// The Nutrition tab's primary action ("Add meal"), registered by the
  /// dashboard. The dock shows it as a round ink button beside the pill, so it
  /// never floats over content.
  static final addMealAction = ValueNotifier<VoidCallback?>(null);

  /// The open tab: 0 Nutrition, 1 Train, 2 Kyno, 3 Profile. Tabs listen to
  /// refresh when they come back into view.
  static final currentTab = ValueNotifier<int>(0);

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _tab = 0;
  static const _channel = MethodChannel('com.kynetix.app/widget');
  static AppShellState? _handlerOwner;

  @override
  void initState() {
    super.initState();
    _handlerOwner = this;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        _handleWidgetAction(call.arguments as String?);
      }
    });
    _checkPendingAction();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppShell.currentTab.value = _tab;
      _checkAndShowResumeDialog();
    });
  }

  void _expandDock() => _compact.value = false;

  @override
  void dispose() {
    _coverAnim?.removeStatusListener(_onCovered);
    _compact.dispose();
    // The handler captures this state. A replacement shell can mount before
    // this one is disposed, so only clear it if no newer shell took over.
    if (identical(_handlerOwner, this)) {
      _channel.setMethodCallHandler(null);
      _handlerOwner = null;
    }
    super.dispose();
  }

  void _checkAndShowResumeDialog() async {
    final service = WorkoutService.instance;
    if (service.draftSession == null) return;

    final draft = service.draftSession!;
    final startedAt = service.draftStartedAt ?? draft.date;
    final duration = DateTime.now().difference(startedAt);
    final totalSets = draft.totalSets;
    final totalVolume = draft.totalWorkingVolume;

    final performed = draft.entries
        .where((e) => !e.isSkipped && e.sets.isNotEmpty)
        .map((e) => e.exercise.name)
        .toList();
    final skipped = draft.entries
        .where((e) => e.isSkipped)
        .map((e) => e.exercise.name)
        .toList();
    final added = draft.entries
        .where((e) => e.isTemporaryAddition)
        .map((e) => e.exercise.name)
        .toList();

    final prefs = await SharedPreferences.getInstance();
    final recoveryJson = prefs.getString(WorkoutService.instance.recoveryPrefKey);
    String lastActiveName = 'None';
    if (recoveryJson != null) {
      try {
        final data = jsonDecode(recoveryJson) as Map<String, dynamic>;
        final lastIdx = data['selectedIndex'] as int? ?? 0;
        if (lastIdx >= 0 && lastIdx < draft.entries.length) {
          lastActiveName = draft.entries[lastIdx].exercise.name;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: KColor.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: KRadius.xl,
            side: BorderSide(
              color: KColor.isDark
                  ? KColor.fg.withValues(alpha: 0.08)
                  : KColor.border,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: KColor.ink.withValues(
                    alpha: KColor.isDark ? 0.10 : 0.07,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: KColor.ink,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('You left a workout open', style: KText.h2)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '"${draft.splitDayName}" is right where you left it.',
                  style: KText.bodyMedium,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  decoration: BoxDecoration(
                    color: KColor.cardHigh.withValues(
                      alpha: KColor.isDark ? 0.7 : 1,
                    ),
                    borderRadius: KRadius.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecoveryStatRow(
                        'Started',
                        '${duration.inHours}h ${duration.inMinutes % 60}m ago (${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')})',
                      ),
                      _buildRecoveryStatRow('Total sets', '$totalSets logged'),
                      _buildRecoveryStatRow(
                        'Total volume',
                        '${totalVolume.toStringAsFixed(0)} kg',
                      ),
                      _buildRecoveryStatRow('Last active', lastActiveName),
                    ],
                  ),
                ),
                if (performed.isNotEmpty)
                  _buildRecoveryListRow('Performed', performed.join(', ')),
                if (skipped.isNotEmpty)
                  _buildRecoveryListRow('Skipped', skipped.join(', ')),
                if (added.isNotEmpty)
                  _buildRecoveryListRow('Added', added.join(', ')),

                const SizedBox(height: 16),
                Text(
                  'Pick up where you left off, or wrap it up.',
                  style: KText.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowButtonSpacing: 8,
          actions: [
            KButton(
              label: 'Resume workout',
              icon: Icons.play_arrow_rounded,
              width: double.infinity,
              onTap: () {
                Navigator.pop(ctx);
                switchToTab(1);
                Future.delayed(const Duration(milliseconds: 100), () {
                  _resumeWorkoutDirectly(draft);
                });
              },
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _finishWorkoutDirectly(draft, WorkoutStatus.completed);
                },
                style: _secondaryStyle(),
                icon: Icon(Icons.check_rounded, size: 18, color: KColor.green),
                label: const Text('Finish workout'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _finishWorkoutDirectly(draft, WorkoutStatus.partial);
                },
                style: _secondaryStyle(),
                icon: Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: KColor.warning,
                ),
                label: const Text('Save as partial'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (confirmCtx) {
                      return AlertDialog(
                        backgroundColor: KColor.surface,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: KRadius.xl,
                          side: BorderSide(
                            color: KColor.isDark
                                ? KColor.fg.withValues(alpha: 0.08)
                                : KColor.border,
                          ),
                        ),
                        title: Text('Discard this workout?', style: KText.h2),
                        content: Text(
                          'This deletes the draft and every set in it. This can\'t be undone.',
                          style: KText.body.copyWith(
                            color: KColor.textSecondary,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmCtx, false),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(64, 48),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontFamily: KText.family,
                                color: KColor.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(confirmCtx, true),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(64, 48),
                            ),
                            child: Text(
                              'Discard',
                              style: TextStyle(
                                fontFamily: KText.family,
                                color: KColor.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirm == true) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove(WorkoutService.instance.recoveryPrefKey);
                    await service.clearDraftSession();
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: KColor.danger,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: TextStyle(
                    fontFamily: KText.family,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('Discard workout'),
              ),
            ),
          ],
        );
      },
    );
  }

  ButtonStyle _secondaryStyle() => OutlinedButton.styleFrom(
    foregroundColor: KColor.textPrimary,
    minimumSize: const Size.fromHeight(52),
    side: BorderSide(
      color: KColor.fg.withValues(alpha: KColor.isDark ? 0.18 : 0.2),
    ),
    shape: const StadiumBorder(),
    textStyle: TextStyle(
      fontFamily: KText.family,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _buildRecoveryStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: KText.caption.copyWith(
              color: KColor.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              val,
              textAlign: TextAlign.right,
              style: KText.numSmall.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecoveryListRow(String label, String items) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: KText.caption.copyWith(
              color: KColor.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            items,
            style: KText.caption.copyWith(
              color: KColor.textSecondary,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _resumeWorkoutDirectly(WorkoutSession draft) async {
    final service = WorkoutService.instance;
    final splitDay = service.split.days.firstWhere(
      (d) => d.name == draft.splitDayName,
      orElse: () => SplitDay(
        name: draft.splitDayName,
        weekday: draft.splitDayWeekday ?? 0,
        exercises: draft.entries.map((e) => e.exercise).toList(),
      ),
    );

    final prev = service.lastSessionFor(splitDay.name);

    // Runs after a short delay from the resume dialog: the shell may be gone
    // (e.g. signed out) by then.
    if (!mounted) return;
    await Navigator.of(context).push(
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
  }

  Future<void> _finishWorkoutDirectly(
    WorkoutSession draft,
    WorkoutStatus status,
  ) async {
    final service = WorkoutService.instance;
    final entries = draft.entries;

    final session = WorkoutSession(
      id: draft.id.startsWith('ws_draft_')
          ? 'ws_${DateTime.now().millisecondsSinceEpoch}'
          : draft.id,
      date: draft.date,
      splitDayName: draft.splitDayName,
      splitDayWeekday: draft.splitDayWeekday,
      wasManuallySelected: draft.wasManuallySelected,
      entries: entries,
      notes: draft.notes,
      durationMinutes: DateTime.now()
          .difference(service.draftStartedAt ?? draft.date)
          .inMinutes,
      status: status,
      plannedExercises: service.split
          .dayFor(draft.splitDayWeekday ?? 0)
          ?.exercises,
    );

    await service.saveSession(session);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(WorkoutService.instance.recoveryPrefKey);
    await service.clearDraftSession();

    if (mounted) {
      showKToast(
        context,
        status == WorkoutStatus.partial
            ? 'Saved as partial. Every set still counts.'
            : 'Workout saved. Solid session.',
        kind: KToastKind.success,
      );
    }
  }

  Future<void> _checkPendingAction() async {
    try {
      final action = await _channel.invokeMethod<String>('getPendingAction');
      _handleWidgetAction(action);
    } catch (e) {
      debugPrint('[AppShell] Error checking pending action: $e');
    }
  }

  /// Home-screen widget taps: open Nutrition, or open it with the
  /// "Log a meal" sheet up.
  void _handleWidgetAction(String? action) {
    if (action != 'open_nutrition' && action != 'log_meal') return;
    switchToTab(0);
    if (action != 'log_meal') return;
    // On a cold start the dashboard registers its action after it mounts.
    final ready = AppShell.addMealAction.value;
    if (ready != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => AppShell.addMealAction.value?.call());
      return;
    }
    void once() {
      final cb = AppShell.addMealAction.value;
      if (cb == null) return;
      AppShell.addMealAction.removeListener(once);
      WidgetsBinding.instance.addPostFrameCallback((_) => cb());
    }
    AppShell.addMealAction.addListener(once);
  }

  void switchToTab(int index) {
    if (!mounted) return;
    if (index == _tab) {
      _compact.value = false;
      return;
    }
    KHaptics.select();
    _compact.value = false;
    setState(() => _tab = index);
    AppShell.currentTab.value = index;
  }

  // ── The island follows the scroll ─────────────────────────────────────────
  // Scrolling down a tab shrinks the dock to the open tab; scrolling up, or
  // reaching the top, grows it back. Only vertical scrolls of the page itself
  // count (not horizontal strips or nested lists).

  // A notifier, not State: a threshold crossing rebuilds only the dock, never
  // the shell, the aurora or the tabs. ValueNotifier ignores same-value sets,
  // so scroll updates that don't cross a threshold cost nothing.
  final _compact = ValueNotifier<bool>(false);

  // Another screen on top (a pushed page or sheet) owns the scroll; its
  // movement, or the dashboard settling underneath it, must not shrink the
  // dock. Coming back always shows the full dock.
  Animation<double>? _coverAnim;

  void _onCovered(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _compact.value = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final anim = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(anim, _coverAnim)) {
      _coverAnim?.removeStatusListener(_onCovered);
      _coverAnim = anim?..addStatusListener(_onCovered);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || n is! ScrollUpdateNotification) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final d = n.scrollDelta ?? 0;
    final px = n.metrics.pixels;
    final now = _compact.value;
    final next = px < 80 ? false : (d > 6 ? true : (d < -6 ? false : now));
    if (next != now) _compact.value = next;
    return false;
  }

  // Kyno is the real coach (model + the app's brief), with the on-device
  // reader as its offline fallback.
  static final _pages = [
    const DashboardScreen(),
    const WorkoutScreen(),
    AiCoachScreen.tab(),
    const ProfileTab(),
  ];

  static const _tones = [KTone.fuel, KTone.train, KTone.kyno, KTone.neutral];

  @override
  Widget build(BuildContext context) {
    return KAurora(
      tone: _tones[_tab],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Content scrolls beneath the floating glass dock; Scaffold adds the
        // dock height to the body's MediaQuery bottom padding.
        extendBody: true,
        body: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: _FadeThroughTabs(
            index: _tab,
            // Each tab keeps its own world, whichever one is showing.
            children: [
              for (var i = 0; i < _pages.length; i++) KToneScope(tone: _tones[i], child: _pages[i]),
            ],
          ),
        ),
        // Own layer: the dock's morph and press feedback never repaint the
        // tab content scrolling beneath it.
        bottomNavigationBar: RepaintBoundary(
          child: ValueListenableBuilder<VoidCallback?>(
            valueListenable: AppShell.addMealAction,
            builder: (context, addMeal, _) => ValueListenableBuilder<bool>(
              valueListenable: _compact,
              builder: (context, compact, _) => _KDock(
                currentIndex: _tab,
                onTap: switchToTab,
                compact: compact,
                onExpand: _expandDock,
                action: _tab == 0 ? addMeal : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _FadeThroughTabs ─────────────────────────────────────────────────────────
// IndexedStack semantics (every tab keeps its state) with a fade-through
// between tabs: the old tab fades out fast, the new one fades in while
// settling from 98% scale. Inactive tabs are offstage with tickers muted, so
// their animations don't run in the background.
//
// Cost: the transitions are FadeTransition / ScaleTransition driven straight
// by the controller, so a frame only updates an opacity and a transform layer
// over each tab's cached RepaintBoundary. Nothing rebuilds per frame; the
// tree only rebuilds when a switch starts and when it ends.

class _FadeThroughTabs extends StatefulWidget {
  const _FadeThroughTabs({required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<_FadeThroughTabs> createState() => _FadeThroughTabsState();
}

class _FadeThroughTabsState extends State<_FadeThroughTabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: KMotion.tab,
    value: 1,
  )..addStatusListener(_onStatus);

  // The incoming tab: fades in after a short beat, scales 0.98 to 1.
  static const _inFade = Interval(0.18, 1, curve: KMotion.easeOut);
  late final Animation<double> _inOpacity = _ctrl.drive(CurveTween(curve: _inFade));
  late final Animation<double> _inScale = _ctrl.drive(
    Tween(begin: 0.98, end: 1.0).chain(CurveTween(curve: KMotion.easeOut)),
  );

  // The outgoing tab: gone in the first ~45%, so the two never read as a
  // double exposure. Starts from whatever opacity it had (a switch can
  // interrupt a switch).
  static const _outFade = Interval(0, 0.45, curve: KMotion.easeOut);
  Animation<double> _outOpacity = kAlwaysDismissedAnimation;

  int _prev = -1;

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && _prev != -1 && mounted) {
      setState(() => _prev = -1);
    }
  }

  @override
  void didUpdateWidget(covariant _FadeThroughTabs old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    if (KMotion.reduced(context)) {
      _prev = -1;
      _ctrl.value = 1;
      return;
    }
    final from = _inOpacity.value;
    _prev = old.index;
    _outOpacity = _ctrl.drive(
      Tween(begin: from, end: 0.0).chain(CurveTween(curve: _outFade)),
    );
    _ctrl.duration = KMotion.tab;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _layer(i, widget.children[i]),
      ],
    );
  }

  Widget _layer(int i, Widget child) {
    final active = i == widget.index;
    final leaving = i == _prev;
    // The same widget shape for every role, so a tab's state is never
    // remounted when it changes role.
    return Offstage(
      offstage: !(active || leaving),
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: ScaleTransition(
              scale: active ? _inScale : kAlwaysCompleteAnimation,
              child: FadeTransition(
                opacity: active
                    ? _inOpacity
                    : (leaving ? _outOpacity : kAlwaysDismissedAnimation),
                // Each tab paints into its own layer, so the fade only
                // re-composites it, and repaints inside one tab never dirty
                // the shell.
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _KDock ───────────────────────────────────────────────────────────────────
// A floating island at the bottom, after the iOS 26 tab bar: one capsule with
// the four places. The open tab is a solid ink pill with its name; the others
// are icons. Scrolling down shrinks the island to just the open tab, so the
// content gets the screen; scrolling up (or a tap) grows it back. The round
// "+" beside it is the Nutrition tab's action and slides away elsewhere.
//
// Smoothness: the whole bar is one layout computed every frame from three
// eased values (which tab, how shrunk, whether "+" is there) and the
// capsule's actual width. Nothing animates on its own clock, so the pill,
// the icons, the label and the capsule edge can never drift apart. Fades are
// folded into colour alpha (no Opacity layers), and the width is measured
// once outside the animation, not re-laid out by a LayoutBuilder per frame.

class _KDock extends StatelessWidget {
  const _KDock({
    required this.currentIndex,
    required this.onTap,
    required this.compact,
    required this.onExpand,
    this.action,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Shrunk to the open tab while the content scrolls down.
  final bool compact;
  final VoidCallback onExpand;

  /// Optional primary action shown as a round button right of the island.
  final VoidCallback? action;

  static const _items = [
    _NavItemData(icon: KIcons.plate, label: 'Nutrition'),
    _NavItemData(icon: KIcons.train, label: 'Train'),
    _NavItemData(icon: KIcons.kyno, label: 'Kyno', kind: _NavKind.kyno),
    _NavItemData(icon: Icons.person_rounded, label: 'Profile', kind: _NavKind.avatar),
  ];

  static const _height = 64.0;
  static const _inset = 6.0;
  static const _iconSlot = 54.0;
  static const _actionGap = 10.0;
  static const _compactWidth = _iconSlot + _inset * 2 + 6;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final dur = KMotion.of(context, KMotion.emphasized);
    const curve = KMotion.emphasizedCurve;
    // Content dissolves into the page colour before it reaches the island,
    // so nothing reads through the gaps around the floating chrome.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [KColor.bg.withValues(alpha: 0), KColor.bg.withValues(alpha: 0.85), KColor.bg],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 12),
        child: SizedBox(
          height: _height,
          child: LayoutBuilder(
            builder: (context, box) => TweenAnimationBuilder<double>(
              tween: Tween(end: currentIndex.toDouble()),
              duration: dur,
              curve: curve,
              builder: (context, sel, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: compact ? 1 : 0),
                duration: dur,
                curve: curve,
                builder: (context, shrink, _) => TweenAnimationBuilder<double>(
                  tween: Tween(end: action == null ? 0 : 1),
                  duration: dur,
                  curve: curve,
                  builder: (context, act, _) => _frame(box.maxWidth, sel, shrink, act),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How much of tab [i]'s name shows when it is [f] open. The tab being
  /// left lets go of its name early, the tab being opened unrolls its name
  /// over the last stretch, so mid-slide the pill only carries an icon and
  /// two half names never share it.
  static double _reveal(double f, bool arriving) {
    final t = arriving ? (f - 0.45) / 0.55 : (f - 0.7) / 0.3;
    final c = t.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  /// One frame of the bar for the eased values [sel] (fractional tab),
  /// [shrink] (0 full, 1 compact) and [act] (0 no "+", 1 "+" shown).
  Widget _frame(double maxW, double sel, double shrink, double act) {
    final n = _items.length;
    final full = maxW - act * (_height + _actionGap);
    final capW = full + (_compactWidth - full) * shrink;
    final capLeft = (full - capW) / 2 * shrink;
    final inner = capW - _inset * 2;
    final open = sel.round().clamp(0, n - 1);

    // How "open" each tab is right now: 1 for the tab the pill sits on,
    // shared between two neighbours while it slides.
    final f = [for (var i = 0; i < n; i++) (1 - (i - sel).abs()).clamp(0.0, 1.0)];
    final selFull = inner - _iconSlot * (n - 1);
    final widths = <double>[];
    for (var i = 0; i < n; i++) {
      final expanded = _iconSlot + (selFull - _iconSlot) * f[i];
      final compactW = i == open ? inner : 0.0;
      widths.add(expanded + (compactW - expanded) * shrink);
    }
    final lefts = <double>[];
    var x = _inset;
    for (final w in widths) {
      lefts.add(x);
      x += w;
    }
    // The pill follows the open tab's slot, gliding between neighbours.
    var pillL = 0.0;
    var pillW = 0.0;
    for (var i = 0; i < n; i++) {
      pillL += lefts[i] * f[i];
      pillW += widths[i] * f[i];
    }

    final dark = KColor.isDark;
    final iconsFade = (1 - shrink).clamp(0.0, 1.0);
    final a = act.clamp(0.0, 1.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: capLeft,
          top: 0,
          bottom: 0,
          width: capW,
          child: GestureDetector(
            // A tap anywhere on the shrunk island grows it back.
            onTap: shrink > 0.5 ? onExpand : null,
            behavior: HitTestBehavior.opaque,
            child: CustomPaint(
              // Carbon: the island's machined top rim, as on cards.
              foregroundPainter: dark ? KRimPainter(radius: KRadius.pill, alpha: 0.06) : null,
              child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: KRadius.pill,
                color: dark ? KColor.cardHigh : KColor.card,
                border: Border.all(color: KColor.border),
              ),
              child: ClipRRect(
                borderRadius: KRadius.pill,
                child: Stack(
                  children: [
                    Positioned(
                      left: pillL,
                      top: _inset,
                      bottom: _inset,
                      width: pillW,
                      child: DecoratedBox(
                        decoration: BoxDecoration(borderRadius: KRadius.pill, color: KColor.ink),
                      ),
                    ),
                    for (var i = 0; i < n; i++)
                      if (widths[i] > 0.5)
                        Positioned(
                          left: lefts[i],
                          top: _inset,
                          bottom: _inset,
                          width: widths[i],
                          child: IgnorePointer(
                            ignoring: shrink > 0.5,
                            child: _NavItem(
                              data: _items[i],
                              selected: i == currentIndex,
                              openness: f[i],
                              // The open tab stays; the others fade with
                              // the shrink, through their colour alpha.
                              fade: i == open ? 1 : iconsFade,
                              labelReveal: _reveal(f[i], i == currentIndex) * (1 - shrink),
                              onTap: () => onTap(i),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
        // The "+" slides in from the right edge with the same easing.
        if (act > 0.01)
          Positioned(
            right: -(1 - act) * (_height + 20),
            top: 0,
            bottom: 0,
            width: _height,
            child: _DockAction(onTap: action, fade: a),
          ),
      ],
    );
  }
}

/// Round ember button beside the island (Nutrition: "Log a meal").
class _DockAction extends StatelessWidget {
  const _DockAction({required this.onTap, required this.fade});
  final VoidCallback? onTap;

  /// 0 gone, 1 fully shown; folded into the fill and glyph alpha.
  final double fade;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Pressable(
      onTap: tap == null
          ? null
          : () {
              KHaptics.select();
              tap();
            },
      semanticLabel: 'Log a meal',
      scale: 0.92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: KColor.ember.withValues(alpha: KColor.ember.a * fade),
        ),
        child: SizedBox.square(
          dimension: 64,
          child: Icon(
            KIcons.add,
            color: KColor.onAccent.withValues(alpha: KColor.onAccent.a * fade),
            size: 28,
          ),
        ),
      ),
    );
  }
}

enum _NavKind { icon, kyno, avatar }

class _NavItemData {
  final IconData icon;
  final String label;
  final _NavKind kind;
  const _NavItemData({required this.icon, required this.label, this.kind = _NavKind.icon});
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.openness,
    required this.fade,
    required this.labelReveal,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;

  /// 0 an icon in the bar, 1 sitting on the ink pill; in between while the
  /// pill slides.
  final double openness;

  /// Overall visibility (0 hidden, 1 shown), folded into colour alpha.
  final double fade;

  /// How much of the label shows (0 none, 1 all).
  final double labelReveal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = Color.lerp(KColor.textSecondary, KColor.onInk, openness)!;
    final color = base.withValues(alpha: base.a * fade);
    final Widget glyph = switch (data.kind) {
      _NavKind.kyno => KynoMark(size: 22, outlined: true, alive: true, selected: selected, color: color),
      // A photo can't take a colour, so the avatar alone keeps an Opacity
      // (32 px, and only while the island shrinks). It wears today's rings;
      // const, so the dock's per-frame rebuilds skip it entirely.
      _NavKind.avatar => Opacity(
          opacity: fade,
          child: const KFuelAvatar(size: 32),
        ),
      _NavKind.icon => Icon(data.icon, color: color, size: 22),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  glyph,
                  // The name unrolls from the icon as the tab opens: its
                  // width and alpha follow the same eased value.
                  if (labelReveal > 0.01)
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: labelReveal,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            data.label,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontFamily: KText.family,
                              color: color.withValues(alpha: color.a * labelReveal),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
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
}
