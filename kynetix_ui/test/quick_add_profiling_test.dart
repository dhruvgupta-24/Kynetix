import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/services/quick_add_service.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearAll();
    WorkoutService.instance.resetReadyForTesting();
    await WorkoutService.instance.init();
    await PersistenceService.load();
  });

  test('Profile QuickAddService.addMealToDay execution pipeline', () async {
    final testDate = DateTime(2026, 7, 29);
    
    final sw = Stopwatch()..start();
    final entry = await QuickAddService.instance.addMealToDay(
      date: testDate,
      name: '1 scoop whey',
      calories: 115,
      protein: 22,
      section: MealSection.breakfast,
    );
    sw.stop();

    expect(entry.finalSavedInput, equals('1 scoop whey'));
    expect(entry.result.calories.mid, equals(115.0));
    expect(entry.result.protein.mid, equals(22.0));

    final log = logFor(testDate);
    expect(log.entriesFor(MealSection.breakfast).length, equals(1));
  });
}
