import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/quick_add_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';

/// Quick Add no longer ships hard-coded items. New accounts start empty;
/// people already using the app keep the two former defaults, now deletable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await GlobalFoodService.instance.init(fetchRemote: false);
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  List<String> names() =>
      QuickAddService.instance.customItems.map((i) => i.name).toList();

  test('a brand-new account starts with an empty Quick Add list', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await UserSessionCoordinator.instance.initializeForUser('new-user', prefsOverride: prefs);
    expect(QuickAddService.instance.customItems, isEmpty);
  });

  test('an existing user keeps the two items, and can delete them for good', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Existing user: has logged before.
    await UserSessionCoordinator.instance.initializeForUser('old-user', prefsOverride: prefs);
    dayLogStore['2026-09-01'] = DayLog()..targetCalories = 2000;
    await PersistenceService.saveDayLogs();
    await PersistenceService.setOnboardingDone();
    await UserSessionCoordinator.instance.clearAllUserServices();
    await prefs.remove('quick_add_defaults_materialized_v1_old-user');

    await UserSessionCoordinator.instance.initializeForUser('old-user', prefsOverride: prefs);
    expect(names(), containsAll(['1 scoop whey', '4 egg whites + 400ml milk']));
    expect(QuickAddService.instance.customItems.every((i) => !i.builtIn), isTrue,
        reason: 'They are ordinary items now, so they can be deleted');

    // Delete one; it must not come back on the next launch.
    final whey = QuickAddService.instance.customItems
        .firstWhere((i) => i.name == '1 scoop whey');
    await QuickAddService.instance.deleteItem(whey);
    await UserSessionCoordinator.instance.clearAllUserServices();
    await UserSessionCoordinator.instance.initializeForUser('old-user', prefsOverride: prefs);
    expect(names(), isNot(contains('1 scoop whey')));
    expect(names(), contains('4 egg whites + 400ml milk'));
  });

  test("a new account never inherits the device's unscoped Quick Add list", () async {
    SharedPreferences.setMockInitialValues({
      'quick_add_custom_items_v2': [
        '{"id":"x","name":"Someone else\'s paneer","calories":300,"protein":20,"emoji":"🧀","builtIn":false}',
      ],
      UserSessionCoordinator.legacyOwnerKey: 'device-owner',
    });
    final prefs = await SharedPreferences.getInstance();
    await UserSessionCoordinator.instance.initializeForUser('someone-new', prefsOverride: prefs);
    expect(names(), isNot(contains("Someone else's paneer")));
  });
}
