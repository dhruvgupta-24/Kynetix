import 'package:shared_preferences/shared_preferences.dart';

import '../models/day_log.dart';
import '../models/user_profile.dart';
import 'internal/scoped_prefs.dart';
import 'nutrition_target_engine.dart';
import 'user_session_coordinator.dart';

// ─── Nutrition momentum ───────────────────────────────────────────────────────
//
// What keeps logging going, computed from the logs alone (nothing new is
// stored except which finished challenges were already celebrated):
//
// - the logging streak, calendar-correct, with today "still open" rather
//   than broken before anything is logged;
// - three weekly challenges, Monday to Sunday, sized from the person's own
//   last week (a stretch of one more day, never a jump), so a new user gets
//   reachable ones and a seven-day logger is not asked for five.
//
// Every rule matches the rest of the app: a protein day is 90% of that day's
// target from NutritionTargetEngine, exactly like the Insights streak and
// badges. No challenge asks anyone to eat less; teens get the same set.

/// A calendar date with no time, so day arithmetic never trips on hours.
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _logged(Map<String, DayLog> logs, DateTime d) {
  final log = logs[dateKey(d)];
  return log != null && !log.isEmpty;
}

/// The logging streak as the home screen shows it.
class StreakSnapshot {
  /// Days in a row with at least one meal logged, ending today when today
  /// is logged, else yesterday (today is still open, not missed).
  final int days;

  /// The longest run ever, calendar-correct.
  final int best;

  final bool todayLogged;

  /// The last seven days, oldest first, ending today: true logged, false
  /// missed. Today is null while it is still open (nothing logged yet).
  final List<bool?> last7;

  /// Days in a row hitting the protein target (90%), counted the same way.
  final int proteinDays;

  const StreakSnapshot({
    required this.days,
    required this.best,
    required this.todayLogged,
    required this.last7,
    required this.proteinDays,
  });

  /// The streak is alive but today hasn't joined it yet.
  bool get atRisk => days > 0 && !todayLogged;
}

enum ChallengeKind { logDays, proteinDays, breakfastDays, fiberDays, fullDays }

/// One weekly challenge with live progress.
class WeeklyChallenge {
  final ChallengeKind kind;
  final int progress;
  final int goal;

  /// Days left in the week, today included.
  final int daysLeft;

  /// The week it belongs to, "2026-W45".
  final String weekKey;

  const WeeklyChallenge({
    required this.kind,
    required this.progress,
    required this.goal,
    required this.daysLeft,
    required this.weekKey,
    this.week = const [],
  });

  /// Monday to Sunday: true the day counted, false it didn't, null still
  /// ahead.
  final List<bool?> week;

  String get id => '$weekKey:${kind.name}';
  bool get done => progress >= goal;

  /// Can still be finished this week.
  bool get reachable => done || progress + daysLeft >= goal;

  double get fraction => goal <= 0 ? 0 : (progress / goal).clamp(0.0, 1.0);

  String get title => switch (kind) {
        ChallengeKind.logDays => 'Log $goal days',
        ChallengeKind.proteinDays => 'Hit protein on $goal days',
        ChallengeKind.breakfastDays => 'Breakfast on $goal days',
        ChallengeKind.fiberDays => 'Fiber target on $goal days',
        ChallengeKind.fullDays => 'Three meals logged on $goal days',
      };

  /// How it counts, in one line.
  String get rule => switch (kind) {
        ChallengeKind.logDays => 'Any meal counts. The days don\'t have to be in a row.',
        ChallengeKind.proteinDays => '90% of the day\'s protein target, the same rule as your streak.',
        ChallengeKind.breakfastDays => 'Anything logged under breakfast. Chai and a banana count.',
        ChallengeKind.fiberDays => 'Dal, chana, sabzi, fruit and whole grains do the heavy lifting.',
        ChallengeKind.fullDays => 'Food logged in three different meals of the day.',
      };

  /// Where it stands, honestly, in the app's voice.
  String get status {
    if (done) return 'Done. Nice work.';
    final left = goal - progress;
    if (!reachable) return '$progress of $goal. Fresh set on Monday.';
    if (left == daysLeft) return '$progress of $goal. Every day left counts now.';
    return '$progress of $goal so far';
  }
}

/// Everything the home screen needs, in one pass over the logs.
class NutritionMomentum {
  final StreakSnapshot streak;
  final List<WeeklyChallenge> challenges;

  const NutritionMomentum({required this.streak, required this.challenges});

  int get doneCount => challenges.where((c) => c.done).length;

  /// Monday of the week holding [d].
  static DateTime weekStart(DateTime d) {
    final day = _day(d);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// ISO week key, "2026-W45".
  static String weekKey(DateTime d) {
    final day = _day(d);
    final thursday = day.add(Duration(days: 4 - day.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    final week = 1 + thursday.difference(jan1).inDays ~/ 7;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  static NutritionMomentum compute({
    required Map<String, DayLog> logs,
    required UserProfile profile,
    required DateTime now,
    double fiberTargetG = 25,
    NutritionTargetEngine? engine,
  }) {
    final targets = engine ?? NutritionTargetEngine.instance;
    final today = _day(now);

    bool proteinHit(DateTime d) {
      final log = logs[dateKey(d)];
      if (log == null || log.isEmpty) return false;
      final t = targets.effectiveTargetForDate(d, profile: profile, log: log).protein;
      return log.totalProteinMid / (t < 1 ? 1 : t) >= 0.90;
    }

    // ── Streak ────────────────────────────────────────────────────────────
    final todayLogged = _logged(logs, today);
    int run(bool Function(DateTime) ok) {
      // Today joins the run only once it qualifies; until then the run
      // ends yesterday and is still alive.
      var d = ok(today) ? today : today.subtract(const Duration(days: 1));
      var n = 0;
      while (ok(d) && n < 3650) {
        n++;
        d = d.subtract(const Duration(days: 1));
      }
      return n;
    }

    final days = run((d) => _logged(logs, d));
    final proteinDays = run(proteinHit);

    var best = 0;
    var current = 0;
    DateTime? prev;
    final keys = logs.keys.where((k) => !(logs[k]?.isEmpty ?? true)).toList()..sort();
    for (final k in keys) {
      final d = DateTime.tryParse(k);
      if (d == null) continue;
      final day = _day(d);
      current = (prev != null && day.difference(prev).inDays == 1) ? current + 1 : 1;
      if (current > best) best = current;
      prev = day;
    }
    if (days > best) best = days;

    final last7 = <bool?>[
      for (var i = 6; i >= 0; i--)
        if (i == 0 && !todayLogged) null else _logged(logs, today.subtract(Duration(days: i))),
    ];

    // ── Challenges ────────────────────────────────────────────────────────
    final monday = weekStart(today);
    final key = weekKey(today);
    final daysLeft = 7 - (today.difference(monday).inDays);
    final thisWeek = [
      for (var i = 0; i < 7; i++)
        if (!monday.add(Duration(days: i)).isAfter(today)) monday.add(Duration(days: i)),
    ];
    final lastWeek = [for (var i = 1; i <= 7; i++) monday.subtract(Duration(days: i))];

    int count(List<DateTime> ds, bool Function(DateTime) ok) => ds.where(ok).length;
    List<bool?> marks(bool Function(DateTime) ok) => [
          for (var i = 0; i < 7; i++)
            if (monday.add(Duration(days: i)).isAfter(today)) null else ok(monday.add(Duration(days: i))),
        ];
    bool breakfast(DateTime d) => logs[dateKey(d)]?.entriesFor(MealSection.breakfast).isNotEmpty ?? false;
    bool fiber(DateTime d) {
      final log = logs[dateKey(d)];
      return log != null && !log.isEmpty && log.totalFiberMid >= fiberTargetG;
    }

    bool fullDay(DateTime d) {
      final log = logs[dateKey(d)];
      if (log == null || log.isEmpty) return false;
      return MealSection.values.where((s) => log.entriesFor(s).isNotEmpty).length >= 3;
    }

    // Goals: one more than last week, inside sensible bounds.
    int stretch(int last, int lo, int hi) => (last + 1).clamp(lo, hi);
    final logGoal = stretch(count(lastWeek, (d) => _logged(logs, d)), 3, 7);
    final proteinGoal = stretch(count(lastWeek, proteinHit), 2, 6);

    // The third one rotates by week so the set stays fresh.
    final rotation = int.parse(key.substring(key.length - 2)) % 3;
    final WeeklyChallenge third = switch (rotation) {
      0 => WeeklyChallenge(
          kind: ChallengeKind.breakfastDays,
          progress: count(thisWeek, breakfast),
          week: marks(breakfast),
          goal: stretch(count(lastWeek, breakfast), 3, 6),
          daysLeft: daysLeft,
          weekKey: key,
        ),
      1 => WeeklyChallenge(
          kind: ChallengeKind.fiberDays,
          progress: count(thisWeek, fiber),
          week: marks(fiber),
          goal: stretch(count(lastWeek, fiber), 2, 5),
          daysLeft: daysLeft,
          weekKey: key,
        ),
      _ => WeeklyChallenge(
          kind: ChallengeKind.fullDays,
          progress: count(thisWeek, fullDay),
          week: marks(fullDay),
          goal: stretch(count(lastWeek, fullDay), 2, 6),
          daysLeft: daysLeft,
          weekKey: key,
        ),
    };

    return NutritionMomentum(
      streak: StreakSnapshot(
        days: days,
        best: best,
        todayLogged: todayLogged,
        last7: last7,
        proteinDays: proteinDays,
      ),
      challenges: [
        WeeklyChallenge(
          kind: ChallengeKind.logDays,
          progress: count(thisWeek, (d) => _logged(logs, d)),
          week: marks((d) => _logged(logs, d)),
          goal: logGoal,
          daysLeft: daysLeft,
          weekKey: key,
        ),
        WeeklyChallenge(
          kind: ChallengeKind.proteinDays,
          progress: count(thisWeek, proteinHit),
          week: marks(proteinHit),
          goal: proteinGoal,
          daysLeft: daysLeft,
          weekKey: key,
        ),
        third,
      ],
    );
  }
}

/// Remembers which finished challenges were already celebrated, per user,
/// so the moment plays once (and not again on another rebuild or device
/// restart). Old weeks are pruned.
class ChallengeCelebrations {
  ChallengeCelebrations._();
  static final ChallengeCelebrations instance = ChallengeCelebrations._();

  static const _base = 'challenge_celebrated_v1';

  /// Challenges in [challenges] that are done and not yet celebrated; marks
  /// them celebrated. Empty when there is nothing new.
  Future<List<WeeklyChallenge>> takeNewlyDone(List<WeeklyChallenge> challenges) async {
    final done = challenges.where((c) => c.done).toList();
    if (done.isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = UserSessionCoordinator.instance.currentUserId;
      final k = ScopedPrefs.key(_base, uid);
      final seen = (prefs.getStringList(k) ?? const <String>[]).toSet();
      final fresh = done.where((c) => !seen.contains(c.id)).toList();
      if (fresh.isEmpty) return const [];
      final week = done.first.weekKey;
      // Keep only this week's ids: the set never grows past three.
      final kept = {
        for (final id in seen)
          if (id.startsWith('$week:')) id,
        for (final c in fresh) c.id,
      };
      await prefs.setStringList(k, kept.toList());
      return fresh;
    } catch (_) {
      return const [];
    }
  }
}
