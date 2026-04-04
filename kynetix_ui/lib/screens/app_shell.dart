import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'workout_screen.dart';

// ─── AppShell ─────────────────────────────────────────────────────────────────
//
// Root shell with a persistent bottom navigation bar.
// Two tabs:
//   0 → Nutrition  (existing DashboardScreen)
//   1 → Train      (new WorkoutScreen)
//
// Profile is accessed via the avatar badge already present in DashboardScreen's
// header — no need for a 3rd tab.
//
// Design: dark, minimal — matches the app's existing look.

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
    if (!mounted) return;
    setState(() => _tab = index);
  }

  // Keep screens alive when switching tabs so DashboardScreen's state
  // (calendar, health sync, etc.) is never rebuilt unnecessarily.
  static const _pages = [
    DashboardScreen(),
    WorkoutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: _BottomNav(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

// ─── _BottomNav ───────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int            currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF2E2E3E).withValues(alpha: 0.8),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(
                icon:     Icons.restaurant_rounded,
                label:    'Nutrition',
                selected: currentIndex == 0,
                onTap:    () => onTap(0),
              ),
              _NavItem(
                icon:     Icons.fitness_center_rounded,
                label:    'Train',
                selected: currentIndex == 1,
                onTap:    () => onTap(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xFF52B788)
        : const Color(0xFF4B5563);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF2D6A4F).withValues(alpha: 0.25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color:      color,
                fontSize:   10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
