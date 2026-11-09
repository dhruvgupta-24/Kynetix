import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/workout_service.dart';

/// The fatigue-load band on the Train tab. A lighter week once read as
/// "Extreme" in red because every ratio under 0.8 fell through to it, and a
/// new user's first fortnight read as a huge spike.
void main() {
  final now = DateTime(2026, 11, 10, 9);
  final svc = WorkoutService.instance;
  const ex = Exercise(
    id: 'acwr_lat_pulldown',
    name: 'Lat Pulldown',
    muscleGroup: 'Back',
    type: ExerciseType.cableMachine,
  );

  Future<void> trainOn(int daysAgo, {double weight = 60}) => svc.saveSession(WorkoutSession(
        id: 'acwr_$daysAgo',
        date: now.subtract(Duration(days: daysAgo)),
        splitDayName: 'Back',
        entries: [
          ExerciseEntry(
            exercise: ex,
            sets: [SetEntry(weight: weight, reps: 10, setType: SetType.normal)],
          ),
        ],
      ));

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await svc.clearAll();
  });

  test('no history, or under three weeks of it, is a baseline still building', () async {
    expect(svc.acwrBandAt(now), AcwrBand.building);
    for (final d in [1, 3, 5, 8, 10, 12]) {
      await trainOn(d);
    }
    expect(svc.acwrBandAt(now), AcwrBand.building, reason: 'would otherwise read as a 2x spike');
    expect(AcwrBand.building.hasRatio, isFalse);
  });

  test('a week off after steady training is light, not extreme', () async {
    for (final d in [8, 10, 12, 15, 17, 19, 22, 24, 26]) {
      await trainOn(d);
    }
    // Nothing in the last 7 days: ACWR 0.
    expect(svc.acwrBandAt(now), AcwrBand.low);
    expect(AcwrBand.low.label, 'Light');
  });

  test('steady weeks are normal; a sudden pile-up is extreme', () async {
    for (final d in [1, 3, 5, 8, 10, 12, 15, 17, 19, 22, 24, 26]) {
      await trainOn(d);
    }
    expect(svc.acwrBandAt(now), AcwrBand.normal);

    await svc.clearAll();
    for (final d in [22, 26]) {
      await trainOn(d);
    }
    for (final d in [0, 1, 2, 3, 4, 5]) {
      await trainOn(d, weight: 100);
    }
    expect(svc.acwrBandAt(now), AcwrBand.extreme);
  });

  test('a month with no training at all after older history is light', () async {
    await trainOn(40);
    expect(svc.acwrBandAt(now), AcwrBand.low);
  });

  test('coaching copy keeps the voice rules', () {
    for (final b in AcwrBand.values) {
      final t = '${b.label} ${b.coachingInsight}';
      expect(t.contains('!') || t.contains('—') || t.contains('–'), isFalse, reason: t);
    }
  });
}
