import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import 'dashboard_screen.dart';
import 'workout_screen.dart';

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
