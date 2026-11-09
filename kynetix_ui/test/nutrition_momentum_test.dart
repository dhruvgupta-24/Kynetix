import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/nutrition_momentum.dart';

void main() {
  const profile = UserProfile(
    name: 'Arjun',
    age: 24,
    gender: 'male',
    height: 175,
    weight: 72,
    workoutDaysMin: 4,
    workoutDaysMax: 5,
    goal: 'Maintenance',
  );

  // Wednesday 11 Nov 2026, mid-afternoon.
  final now = DateTime(2026, 11, 11, 15);

  MealEntry meal(DateTime d, {double protein = 20, double kcal = 400, MealSection section = MealSection.lunch}) => MealEntry(
        rawInput: 'dal roti',
        result: NutritionResult.createCustom(canonicalMeal: 'dal roti', calories: kcal, protein: protein, source: 'test'),
        addedAt: d,
        section: section,
        dayOfWeek: d.weekday,
        parsedFoods: const ['dal', 'roti'],
        finalSavedInput: 'dal roti',
      );

  Map<String, DayLog> logsFor(Map<int, List<MealEntry> Function(DateTime)> daysAgo) {
    final logs = <String, DayLog>{};
    daysAgo.forEach((ago, make) {
      final d = DateTime(now.year, now.month, now.day - ago, 12);
      final log = DayLog();
      for (final e in make(d)) {
        log.add(e.section, e);
      }
      logs[dateKey(d)] = log;
    });
    return logs;
  }

  NutritionMomentum compute(Map<String, DayLog> logs) =>
      NutritionMomentum.compute(logs: logs, profile: profile, now: now);

  group('streak', () {
    test('today still open does not break the streak', () {
      final m = compute(logsFor({1: (d) => [meal(d)], 2: (d) => [meal(d)], 3: (d) => [meal(d)]}));
      expect(m.streak.days, 3);
      expect(m.streak.todayLogged, isFalse);
      expect(m.streak.atRisk, isTrue);
      expect(m.streak.last7.last, isNull, reason: 'today is an open ring');
    });

    test('today joins once logged', () {
      final m = compute(logsFor({0: (d) => [meal(d)], 1: (d) => [meal(d)]}));
      expect(m.streak.days, 2);
      expect(m.streak.atRisk, isFalse);
      expect(m.streak.last7.last, isTrue);
    });

    test('a missed day ends it; best run survives', () {
      final m = compute(logsFor({
        1: (d) => [meal(d)],
        3: (d) => [meal(d)], 4: (d) => [meal(d)], 5: (d) => [meal(d)], 6: (d) => [meal(d)],
      }));
      expect(m.streak.days, 1);
      expect(m.streak.best, 4);
      expect(m.streak.last7, [true, true, true, true, false, true, null]);
    });

    test('an empty log (all meals deleted) is not a logged day', () {
      final logs = logsFor({1: (d) => [meal(d)]});
      logs[dateKey(DateTime(now.year, now.month, now.day - 2))] = DayLog();
      logs.addAll(logsFor({3: (d) => [meal(d)]}));
      expect(compute(logs).streak.days, 1);
    });

    test('protein days count only days at 90% of target, today once hit', () {
      final m = compute(logsFor({
        0: (d) => [meal(d, protein: 5)], // today, not there yet
        1: (d) => [meal(d, protein: 300)],
        2: (d) => [meal(d, protein: 300)],
        3: (d) => [meal(d, protein: 5)],
      }));
      expect(m.streak.proteinDays, 2, reason: 'today is still open, not a miss');
    });
  });

  group('weekly challenges', () {
    test('three challenges, Monday to Sunday, with honest day marks', () {
      // Mon 9 and Tue 10 logged, Wed (today) not yet.
      final m = compute(logsFor({1: (d) => [meal(d)], 2: (d) => [meal(d)]}));
      expect(m.challenges, hasLength(3));
      final log = m.challenges.first;
      expect(log.kind, ChallengeKind.logDays);
      expect(log.progress, 2);
      expect(log.daysLeft, 5, reason: 'Wednesday to Sunday');
      expect(log.week, [true, true, false, null, null, null, null]);
      expect(log.weekKey, NutritionMomentum.weekKey(now));
    });

    test('goals stretch one past last week, inside bounds', () {
      // Last week: logged all 7 days, protein hit on 5.
      final days = <int, List<MealEntry> Function(DateTime)>{};
      for (var ago = 3; ago <= 9; ago++) {
        days[ago] = (d) => [meal(d, protein: ago <= 7 ? 300 : 5)];
      }
      final m = compute(logsFor(days));
      expect(m.challenges[0].goal, 7, reason: '7 + 1, capped at 7');
      expect(m.challenges[1].goal, 6, reason: '5 + 1');
    });

    test('a brand new user gets reachable floors', () {
      final m = compute({});
      expect(m.challenges[0].goal, 3);
      expect(m.challenges[1].goal, 2);
      expect(m.challenges.every((c) => c.reachable), isTrue);
      expect(m.streak.days, 0);
    });

    test('status says when it can no longer be finished, without blame', () {
      const c = WeeklyChallenge(kind: ChallengeKind.logDays, progress: 1, goal: 6, daysLeft: 2, weekKey: '2026-W46');
      expect(c.reachable, isFalse);
      expect(c.status, '1 of 6. Fresh set on Monday.');
      const d = WeeklyChallenge(kind: ChallengeKind.logDays, progress: 4, goal: 6, daysLeft: 2, weekKey: '2026-W46');
      expect(d.status, contains('Every day left counts'));
    });

    test('copy has no em or en dashes and no exclamation marks', () {
      for (final k in ChallengeKind.values) {
        final c = WeeklyChallenge(kind: k, progress: 1, goal: 3, daysLeft: 4, weekKey: '2026-W46');
        for (final s in [c.title, c.rule, c.status]) {
          expect(s.contains('—') || s.contains('–') || s.contains('!'), isFalse, reason: s);
        }
      }
    });

    test('ISO week keys across the year end', () {
      expect(NutritionMomentum.weekKey(DateTime(2026, 12, 31)), '2026-W53');
      expect(NutritionMomentum.weekKey(DateTime(2027, 1, 4)), '2027-W01');
      expect(NutritionMomentum.weekStart(DateTime(2026, 11, 15)), DateTime(2026, 11, 9));
    });
  });

  group('celebrations', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a finished challenge is celebrated once', () async {
      const done = WeeklyChallenge(kind: ChallengeKind.logDays, progress: 3, goal: 3, daysLeft: 3, weekKey: '2026-W46');
      const open = WeeklyChallenge(kind: ChallengeKind.proteinDays, progress: 1, goal: 3, daysLeft: 3, weekKey: '2026-W46');
      final first = await ChallengeCelebrations.instance.takeNewlyDone([done, open]);
      expect(first.map((c) => c.kind), [ChallengeKind.logDays]);
      final again = await ChallengeCelebrations.instance.takeNewlyDone([done, open]);
      expect(again, isEmpty);
    });
  });
}
