import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("Developer's Choice is the default split, day for day", () {
    final s = defaultWorkoutSplit;
    expect(s.name, developersChoiceName);
    expect(s.days.map((d) => d.name).toList(), [
      'Chest + Triceps', 'Back + Biceps', 'Shoulders', 'Legs', 'Push', 'Pull', 'Rest Day',
    ]);
    expect(s.dayFor(1)!.exercises.first.name, 'Flat Bench Press');
    expect(s.dayFor(5)!.exercises.map((e) => e.name), contains('Rod Tricep Pushdown'));
    expect(s.dayFor(7)!.isRestDay, isTrue);
    expect(isUnchangedDevelopersChoice(s), isTrue);
  });

  test('editing it changes only that user', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ws = WorkoutService.instance;

    await ws.initForUser('user-a', prefsOverride: prefs);
    expect(ws.split.name, developersChoiceName);
    final days = [...ws.split.days];
    days[0] = days[0].copyWith(name: 'Arms', exercises: [days[0].exercises.last]);
    await ws.saveSplit(ws.split.copyWith(name: 'My Split', days: days));
    expect(ws.split.dayFor(1)!.name, 'Arms');

    ws.clearMemory();
    await ws.initForUser('user-b', prefsOverride: prefs);
    expect(ws.split.name, developersChoiceName);
    expect(ws.split.dayFor(1)!.name, 'Chest + Triceps');
    expect(ws.isSetupDone, isFalse);

    ws.clearMemory();
    await ws.initForUser('user-a', prefsOverride: prefs);
    expect(ws.split.dayFor(1)!.name, 'Arms');
  });
}
