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

// ─── AppShell ─────────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _tab = 0;
  static const _channel = MethodChannel('com.kynetix.app/widget');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final action = call.arguments as String?;
        if (action == 'open_nutrition') {
          switchToTab(0);
        }
      }
    });
    _checkPendingAction();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowResumeDialog();
    });
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
    final recoveryJson = prefs.getString('kynetix_workout_recovery');
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
          backgroundColor: const Color(0xFF13131F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: KColor.border, width: 0.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: KColor.green, size: 20),
              SizedBox(width: 8),
              Text('Active Workout Found', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '"${draft.splitDayName}" is currently active.',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                _buildRecoveryStatRow('Started', '${duration.inHours}h ${duration.inMinutes % 60}m ago (${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')})'),
                _buildRecoveryStatRow('Total Sets', '$totalSets logged'),
                _buildRecoveryStatRow('Total Volume', '${totalVolume.toStringAsFixed(0)} kg'),
                _buildRecoveryStatRow('Last Active', lastActiveName),
                
                if (performed.isNotEmpty)
                  _buildRecoveryListRow('Performed', performed.join(', ')),
                if (skipped.isNotEmpty)
                  _buildRecoveryListRow('Skipped', skipped.join(', ')),
                if (added.isNotEmpty)
                  _buildRecoveryListRow('Added', added.join(', ')),
                  
                const SizedBox(height: 16),
                const Text(
                  'What would you like to do with this workout?',
                  style: TextStyle(color: KColor.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowButtonSpacing: 8,
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  switchToTab(1);
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _resumeWorkoutDirectly(draft);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColor.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Resume Workout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _finishWorkoutDirectly(draft, WorkoutStatus.completed);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: KColor.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_rounded, size: 16, color: KColor.green),
                label: const Text('Finish Workout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _finishWorkoutDirectly(draft, WorkoutStatus.partial);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: KColor.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFFFB347)),
                label: const Text('Finish As Partial Workout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                        backgroundColor: const Color(0xFF13131F),
                        title: const Text('Discard Workout?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        content: const Text('Are you sure you want to permanently discard this workout draft? This action cannot be undone.', style: TextStyle(color: KColor.textSecondary, fontSize: 13)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmCtx, false),
                            child: const Text('Cancel', style: TextStyle(color: KColor.textMuted)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(confirmCtx, true),
                            child: const Text('Discard', style: TextStyle(color: KColor.danger, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      );
                    },
                  );
                  
                  if (confirm == true) {
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('kynetix_workout_recovery');
                    await service.clearDraftSession();
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: KColor.danger,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                label: const Text('Discard Workout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecoveryStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: KColor.textMuted, fontSize: 11.5)),
          Text(val, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecoveryListRow(String label, String items) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: KColor.textMuted, fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(
            items,
            style: const TextStyle(color: KColor.textSecondary, fontSize: 11.5),
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

  Future<void> _finishWorkoutDirectly(WorkoutSession draft, WorkoutStatus status) async {
    final service = WorkoutService.instance;
    final entries = draft.entries;
    
    final session = WorkoutSession(
      id: draft.id.startsWith('ws_draft_') ? 'ws_${DateTime.now().millisecondsSinceEpoch}' : draft.id,
      date: draft.date,
      splitDayName: draft.splitDayName,
      splitDayWeekday: draft.splitDayWeekday,
      wasManuallySelected: draft.wasManuallySelected,
      entries: entries,
      notes: draft.notes,
      durationMinutes: DateTime.now().difference(service.draftStartedAt ?? draft.date).inMinutes,
      status: status,
      plannedExercises: service.split.dayFor(draft.splitDayWeekday ?? 0)?.exercises,
    );

    await service.saveSession(session);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kynetix_workout_recovery');
    await service.clearDraftSession();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${draft.splitDayName}" as ${status.name}.'),
          backgroundColor: KColor.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkPendingAction() async {
    try {
      final action = await _channel.invokeMethod<String>('getPendingAction');
      if (action == 'open_nutrition') {
        switchToTab(0);
      }
    } catch (e) {
      debugPrint('[AppShell] Error checking pending action: $e');
    }
  }

  void switchToTab(int index) {
    if (!mounted || index == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = index);
  }

  static const _pages = [
    DashboardScreen(),
    WorkoutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColor.bg,
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: _AnimatedBottomNav(
        currentIndex: _tab,
        onTap: switchToTab,
      ),
    );
  }
}

// ─── _AnimatedBottomNav ───────────────────────────────────────────────────────

class _AnimatedBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _AnimatedBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItemData(icon: Icons.restaurant_rounded,    label: 'Nutrition'),
    _NavItemData(icon: Icons.fitness_center_rounded, label: 'Train'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: KColor.surface,
        border: Border(
          top: BorderSide(color: KColor.border.withValues(alpha: 0.8), width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20, offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (i) => Expanded(
              child: _NavItem(
                data:     _items[i],
                selected: currentIndex == i,
                onTap:    () => onTap(i),
              ),
            )),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String   label;
  const _NavItemData({required this.icon, required this.label});
}

class _NavItem extends StatefulWidget {
  final _NavItemData data;
  final bool         selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scaleAnim;
  late final Animation<double>   _colorAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 250),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _colorAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    if (widget.selected) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      widget.selected ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final color = Color.lerp(KColor.textDisabled, KColor.green, _colorAnim.value)!;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pill indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.selected
                      ? KColor.greenDark.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: KRadius.pill,
                ),
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Icon(widget.data.icon, color: color, size: 22),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                style: TextStyle(
                  color:      color,
                  fontSize:   10.5,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.3,
                ),
                duration: const Duration(milliseconds: 200),
                child: Text(widget.data.label),
              ),
            ],
          );
        },
      ),
    );
  }
}
