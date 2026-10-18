import '../models/day_log.dart';
import '../models/user_profile.dart';
import 'health_service.dart';
import 'nutrition_target_engine.dart';
import 'profile_service.dart';

// ─── Display totals ───────────────────────────────────────────────────────────
// What the screen adds up is exactly what the rows show: every meal row prints
// its rounded kcal, and every total is the sum of those printed numbers.

int displayKcal(DayLog log) =>
    log.allEntries.fold<int>(0, (s, e) => s + e.calMid.round());

int displayProtein(DayLog log) =>
    log.allEntries.fold<int>(0, (s, e) => s + e.result.protein.mid.round());

/// A day's eaten totals against its target: the numbers the dashboard's fuel
/// rings print, for anything else that wears them (the profile avatar).
class DayFuel {
  const DayFuel({
    required this.kcal,
    required this.targetKcal,
    required this.protein,
    required this.targetProtein,
  });

  static const empty = DayFuel(kcal: 0, targetKcal: 0, protein: 0, targetProtein: 0);

  final int kcal;
  final int targetKcal;
  final int protein;
  final int targetProtein;

  /// Share of the target eaten, unclamped (over 1 when over target).
  double get kcalRatio => targetKcal > 0 ? kcal / targetKcal : 0.0;
  double get proteinRatio => targetProtein > 0 ? protein / targetProtein : 0.0;

  /// [day]'s totals with the same target call the dashboard makes. Read-only:
  /// a day with no log reads as an empty one and nothing is added to the
  /// store.
  static DayFuel of(DateTime day, {UserProfile? profile, HealthSyncResult? health}) {
    final prof = profile ?? ProfileService.instance.currentUserProfile;
    if (prof == null) return empty;
    final log = dayLogStore[dateKey(day)] ?? DayLog();
    final t = NutritionTargetEngine().effectiveTargetForDate(day, profile: prof, health: health, log: log);
    return DayFuel(
      kcal: displayKcal(log),
      targetKcal: t.calories.round(),
      protein: displayProtein(log),
      targetProtein: t.protein.round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DayFuel &&
      other.kcal == kcal &&
      other.targetKcal == targetKcal &&
      other.protein == protein &&
      other.targetProtein == targetProtein;

  @override
  int get hashCode => Object.hash(kcal, targetKcal, protein, targetProtein);
}
