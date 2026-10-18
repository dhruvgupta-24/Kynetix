import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import 'dashboard_screen.dart';
import 'workout_screen.dart';
import 'workout_session_screen.dart';
import 'ai_coach_screen.dart';

// ─── AppShell ─────────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

  /// The Nutrition tab's primary action ("Add meal"), registered by the
  /// dashboard. The dock shows it as a round ink button beside the pill, so it
  /// never floats over content.
  static final addMealAction = ValueNotifier<VoidCallback?>(null);

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
      _checkAndShowResumeDialog();
    });
  }

  @override
  void dispose() {
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
                  color: KColor.violet.withValues(
                    alpha: KColor.isDark ? 0.16 : 0.1,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: KColor.violet,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == WorkoutStatus.partial
                ? 'Saved as partial. Every set still counts.'
                : 'Workout saved. Solid session.',
          ),
        ),
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
    if (!mounted || index == _tab) return;
    KHaptics.select();
    setState(() => _tab = index);
  }

  // Kyno is the real coach (model + the app's brief), with the on-device
  // reader as its offline fallback.
  static final _pages = [
    const DashboardScreen(),
    const WorkoutScreen(),
    AiCoachScreen.tab(),
  ];

  static const _tones = [KTone.fuel, KTone.train, KTone.kyno];

  @override
  Widget build(BuildContext context) {
    return KAurora(
      tone: _tones[_tab],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Content scrolls beneath the floating glass dock; Scaffold adds the
        // dock height to the body's MediaQuery bottom padding.
        extendBody: true,
        body: _FadeThroughTabs(
          index: _tab,
          // Each tab keeps its own world, whichever one is showing.
          children: [
            for (var i = 0; i < _pages.length; i++) KToneScope(tone: _tones[i], child: _pages[i]),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder<VoidCallback?>(
          valueListenable: AppShell.addMealAction,
          // Own layer: the dock's spring indicator and press feedback never
          // repaint the tab content scrolling beneath it.
          builder: (context, addMeal, _) => RepaintBoundary(
            child: _KDock(
              currentIndex: _tab,
              onTap: switchToTab,
              action: _tab == 0 ? addMeal : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _FadeThroughTabs ─────────────────────────────────────────────────────────
// IndexedStack semantics (every tab keeps its state) with a Material
// fade-through between tabs: the old tab fades out quickly, the new one fades
// in while settling from 97% scale. Inactive tabs are offstage with tickers
// muted, so their animations don't run in the background.

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
    duration: KMotion.emphasized,
    value: 1,
  );
  int _prev = -1;

  @override
  void didUpdateWidget(covariant _FadeThroughTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _prev = old.index;
      _ctrl.duration = KMotion.of(context, KMotion.emphasized);
      _ctrl.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted) setState(() => _prev = -1);
      });
    }
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
    final visible = active || leaving;
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          child: AnimatedBuilder(
            animation: _ctrl,
            // Each tab paints into its own layer, so the fade-through only
            // re-composites it (no repaint of the tab's content per frame),
            // and repaints inside one tab never dirty the shell.
            child: RepaintBoundary(child: child),
            builder: (context, child) {
              final t = _ctrl.value;
              double opacity;
              double scale;
              if (active) {
                final v = KMotion.decelerate.transform(
                  ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                );
                opacity = v;
                scale = 0.97 + 0.03 * v;
              } else if (leaving) {
                opacity =
                    1 - KMotion.accelerate.transform((t / 0.3).clamp(0.0, 1.0));
                scale = 1.0;
              } else {
                opacity = 0;
                scale = 1.0;
              }
              return Opacity(
                opacity: opacity,
                child: Transform.scale(scale: scale, child: child),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── _KDock ───────────────────────────────────────────────────────────────────
// Floating glass pill. Every tab shows its icon and its word; an indicator
// slides to the active one on a spring and takes that world's accent
// (Nutrition ember, Train violet, Kyno cyan), so you always know where you are.

class _KDock extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _KDock({required this.currentIndex, required this.onTap, this.action});

  /// Optional primary action shown as a round ink button right of the pill.
  final VoidCallback? action;

  static List<_NavItemData> get _items => const [
    _NavItemData(icon: KIcons.plate, label: 'Nutrition'),
    _NavItemData(icon: KIcons.train, label: 'Train'),
    _NavItemData(icon: KIcons.kyno, label: 'Kyno', kyno: true),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final dark = KColor.isDark;
    // Content dissolves into the page colour before it reaches the dock, so
    // nothing reads through the gaps around the floating chrome.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KColor.bg.withValues(alpha: 0),
            KColor.bg.withValues(alpha: 0.85),
            KColor.bg,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 12),
        child: Row(
          children: [
            Expanded(child: _pill(context, dark)),
            AnimatedSize(
              duration: KMotion.of(context, KMotion.standard),
              curve: KMotion.emphasizedCurve,
              child: action == null
                  ? const SizedBox(height: 64)
                  : Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _DockAction(onTap: action!),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, bool dark) {
    // A solid capsule one step above the page, edged with a hairline. No
    // blur, no shadow.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: KRadius.pill,
        color: dark ? KColor.cardHigh : KColor.card,
        border: Border.all(color: dark ? const Color(0xFF2C2C30) : KColor.border),
      ),
        child: SizedBox(
          // Grows with the text size instead of clipping the labels.
          height: (46 + MediaQuery.textScalerOf(context).scale(13.5)).clamp(64.0, 120.0),
          child: LayoutBuilder(
            builder: (context, box) {
              // Every tab shows its icon and its word, so the shares are
              // equal; the ink indicator slides between them.
              const activeWeight = 1.0;
              final unit = box.maxWidth / (_items.length - 1 + activeWeight);
              double widthOf(int i) =>
                  i == currentIndex ? unit * activeWeight : unit;
              double leftOf(int i) {
                var x = 0.0;
                for (var j = 0; j < i; j++) {
                  x += widthOf(j);
                }
                return x;
              }

              final dur = KMotion.of(
                context,
                const Duration(milliseconds: 620),
              );
              return Stack(
                children: [
                  // Accent indicator
                  AnimatedPositioned(
                    duration: dur,
                    curve: KMotion.spring,
                    left: leftOf(currentIndex) + 6,
                    top: 7,
                    bottom: 7,
                    width: widthOf(currentIndex) - 12,
                    child: AnimatedContainer(
                      duration: KMotion.of(context, KMotion.standard),
                      curve: KMotion.emphasizedCurve,
                      // The selected tab is a solid ink pill.
                      decoration: BoxDecoration(
                        borderRadius: KRadius.pill,
                        color: KColor.ink,
                      ),
                    ),
                  ),
                  for (var i = 0; i < _items.length; i++)
                    AnimatedPositioned(
                      duration: dur,
                      curve: KMotion.spring,
                      left: leftOf(i),
                      top: 0,
                      bottom: 0,
                      width: widthOf(i),
                      child: _NavItem(
                        data: _items[i],
                        selected: currentIndex == i,
                        accent: KColor.tabAccent(i),
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
    );
  }
}

/// Round ember button docked beside the nav pill (Nutrition → "Add meal").
class _DockAction extends StatelessWidget {
  const _DockAction({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        KHaptics.select();
        onTap();
      },
      semanticLabel: 'Log a meal',
      scale: 0.92,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(shape: BoxShape.circle, color: KColor.ember),
        child: const Icon(KIcons.add, color: Colors.white, size: 28),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;

  /// Draw Kyno's mark instead of [icon].
  final bool kyno;
  const _NavItemData({
    required this.icon,
    required this.label,
    this.kyno = false,
  });
}

class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _NavItem({
    required this.data,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Selected sits on the ink pill.
    final color = selected ? KColor.onInk : KColor.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            data.kyno
                ? KynoMark(
                    size: 20,
                    // Outlined on the gradient pill too: a filled white disc
                    // would hide the "k".
                    outlined: true,
                    color: color,
                  )
                : TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: color),
                    duration: KMotion.of(context, KMotion.quick),
                    builder: (context, c, _) => Icon(data.icon, color: c, size: 21),
                  ),
            const SizedBox(height: 2),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontFamily: KText.family,
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
