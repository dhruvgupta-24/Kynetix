import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/models/quick_add_item.dart';
import 'package:kynetix/services/quick_add_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';

/// Startup / sign-in loading: background decoding must give exactly the same
/// logs, never leak across accounts, and concurrent loads must not race.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = 'startup-user-a';
  const userB = 'startup-user-b';

  Map<String, dynamic> logsFor(int days) {
    final out = <String, dynamic>{};
    for (var i = 0; i < days; i++) {
      final log = DayLog()..targetCalories = 2000 + i.toDouble();
      log.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'meal $i',
          addedAt: DateTime(2026, 1, 1).add(Duration(days: i, hours: 13)),
          section: MealSection.lunch,
          dayOfWeek: 1,
          parsedFoods: ['meal $i'],
          finalSavedInput: 'meal $i',
          result: NutritionResult.createCustom(
            canonicalMeal: 'meal $i',
            calories: 400 + i.toDouble(),
            protein: 20,
            source: 'test',
            userCorrected: true,
          ),
        ),
      );
      final d = DateTime(2026, 1, 1).add(Duration(days: i));
      out[dateKey(d)] = log.toJson();
    }
    return out;
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await GlobalFoodService.instance.init(fetchRemote: false);
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  tearDown(() {
    PersistenceService.isolateDecodeThresholdChars = 64 * 1024;
  });

  test('background-isolate decode loads exactly the stored logs', () async {
    final stored = logsFor(40);
    SharedPreferences.setMockInitialValues({
      'migration_verified_v1_$userA': true,
      'day_logs_v1_$userA': jsonEncode(stored),
    });
    final prefs = await SharedPreferences.getInstance();

    // Force the isolate path even for this small store.
    PersistenceService.isolateDecodeThresholdChars = 0;
    await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);
    final viaIsolate = {for (final e in dayLogStore.entries) e.key: jsonEncode(e.value.toJson())};

    await UserSessionCoordinator.instance.clearAllUserServices();
    PersistenceService.isolateDecodeThresholdChars = 1 << 30; // inline
    await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);
    final inline = {for (final e in dayLogStore.entries) e.key: jsonEncode(e.value.toJson())};

    expect(viaIsolate.length, 40);
    expect(viaIsolate, inline);
  });

  test('sign-out during the background decode never leaks the logs', () async {
    SharedPreferences.setMockInitialValues({
      'migration_verified_v1_$userA': true,
      'day_logs_v1_$userA': jsonEncode(logsFor(30)),
    });
    final prefs = await SharedPreferences.getInstance();
    PersistenceService.isolateDecodeThresholdChars = 0;

    await PersistenceService.setCachedOwnerId(userA);
    final load = PersistenceService.loadForUser(userA, prefsOverride: prefs);
    // Sign out while the decode is still running in the background isolate.
    await UserSessionCoordinator.instance.clearAllUserServices();
    await load;

    expect(dayLogStore, isEmpty,
        reason: "A signed-out user's logs must not land after the boundary flush");
  });

  test('concurrent initializeForUser calls for one user share one load', () async {
    SharedPreferences.setMockInitialValues({
      'migration_verified_v1_$userB': true,
      'onboarding_done_v1_$userB': true,
      'day_logs_v1_$userB': jsonEncode(logsFor(3)),
    });
    final prefs = await SharedPreferences.getInstance();

    final first = UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);
    expect(UserSessionCoordinator.instance.isReadyFor(userB), isFalse,
        reason: 'currentUserId is set at once, but data is not ready yet');
    final second = UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);
    await Future.wait([first, second]);

    expect(UserSessionCoordinator.instance.isReadyFor(userB), isTrue);
    expect(dayLogStore.length, 3);
    expect(PersistenceService.isOnboardingDone, isTrue);

    await UserSessionCoordinator.instance.clearAllUserServices();
    expect(UserSessionCoordinator.instance.isReadyFor(userB), isFalse);
  });

  test('Quick Add delete and save update memory before the disk write', () async {
    SharedPreferences.setMockInitialValues({'migration_verified_v1_$userA': true});
    final prefs = await SharedPreferences.getInstance();
    await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);

    final item = QuickAddItem(
      id: 'qa-test-1',
      name: 'Protein shake',
      calories: 180,
      protein: 30,
      emoji: '⚡',
      builtIn: false,
    );
    final saved = QuickAddService.instance.saveItem(item);
    expect(QuickAddService.instance.customItems.any((i) => i.id == item.id), isTrue,
        reason: 'The new chip must be visible on the same frame');
    await saved;

    final deleted = QuickAddService.instance.deleteItem(item);
    expect(QuickAddService.instance.customItems.any((i) => i.id == item.id), isFalse,
        reason: 'The deleted chip must disappear on the same frame');
    await deleted;
  });
}
