import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A remembered food the user deleted must not come back from the cloud.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = 'override-user';
  final memory = UserNutritionMemory.instance;
  late List<Set<String>> cloudDeletes;
  late bool cloudDeleteSucceeds;

  UserMealOverride cloud(String name, {int kcal = 100}) => UserMealOverride(
        canonicalMeal: name,
        caloriesPerUnit: kcal.toDouble(),
        proteinPerUnit: 5,
        savedAt: DateTime.now().add(const Duration(days: 1)), // "newer" than local
      );

  Set<String> names() => memory.allOverrides.map((o) => o.canonicalMeal).toSet();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Signed-out mock client: sync-back uploads no-op (no current user).
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'cached_owner_user_id_v1': user});
    NutritionHydrationGuard.instance.reset();
    NutritionHydrationGuard.instance.currentUserIdOverride = user;
    NutritionHydrationGuard.instance.markComplete(user);
    cloudDeletes = [];
    cloudDeleteSucceeds = false; // offline by default
    memory.cloudDeleterOverride = (n, uid) async {
      expect(uid, user);
      cloudDeletes.add(Set.of(n));
      return cloudDeleteSucceeds;
    };
    memory.clearMemory();
    await memory.initForUser(user);
  });

  tearDown(() {
    memory.cloudDeleterOverride = null;
    NutritionHydrationGuard.instance.reset();
  });

  test('a deleted override is not resurrected by cloud merge (offline delete)', () async {
    await memory.saveOverride('paneer tikka', 2.5, 0.2);
    final name = memory.allOverrides.single.canonicalMeal;

    await memory.deleteOverride('paneer tikka');
    await memory.waitForCloudDeletes();
    expect(cloudDeletes.single, {name});
    expect(memory.deletedOverrideTombstones, {name});

    await memory.mergeFromCloud([cloud(name), cloud('oats')]);
    expect(names(), {'oats'});

    // Survives a relaunch.
    memory.clearMemory();
    await memory.initForUser(user);
    await memory.waitForCloudDeletes();
    await memory.mergeFromCloud([cloud(name)]);
    expect(names().contains(name), isFalse);
  });

  test('bulk delete tombstones every name', () async {
    await memory.saveOverride('greek yogurt', 0.6, 0.1);
    await memory.saveOverride('whey scoop', 120, 24);
    final all = names();
    await memory.deleteOverrides(['greek yogurt', 'whey scoop']);
    await memory.waitForCloudDeletes();
    await memory.mergeFromCloud(all.map(cloud).toList());
    expect(names(), isEmpty);
  });

  test('a successful cloud delete clears the tombstone', () async {
    cloudDeleteSucceeds = true;
    await memory.saveOverride('banana', 0.9, 0.01);
    await memory.deleteOverride('banana');
    await memory.waitForCloudDeletes();
    expect(memory.deletedOverrideTombstones, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(UserNutritionMemory.tombstonePrefKeyFor(user)), isNull);
  });

  test('a failed delete is retried on the next merge, then cleared', () async {
    await memory.saveOverride('banana', 0.9, 0.01);
    final name = names().single;
    await memory.deleteOverride('banana');
    await memory.waitForCloudDeletes();
    expect(memory.deletedOverrideTombstones, {name});

    cloudDeleteSucceeds = true; // back online
    await memory.mergeFromCloud([cloud(name)]);
    await memory.waitForCloudDeletes();
    expect(cloudDeletes.length, 2);
    expect(memory.deletedOverrideTombstones, isEmpty);
    expect(names(), isEmpty);
  });

  test('re-saving a deleted food clears its tombstone', () async {
    await memory.saveOverride('dal makhani', 1.4, 0.06);
    final name = names().single;
    await memory.deleteOverride('dal makhani');
    await memory.waitForCloudDeletes();
    expect(memory.deletedOverrideTombstones, {name});

    await memory.saveOverride('dal makhani', 1.5, 0.07);
    expect(memory.deletedOverrideTombstones, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(UserNutritionMemory.tombstonePrefKeyFor(user)), isNull);

    // Cloud copies of it merge normally again.
    await memory.mergeFromCloud([cloud(name, kcal: 200)]);
    expect(names(), {name});
  });

  test('override tombstones are per user', () async {
    await memory.saveOverride('rajma', 1.2, 0.08);
    final name = names().single;
    await memory.deleteOverride('rajma');
    await memory.waitForCloudDeletes();

    const other = 'other-user';
    NutritionHydrationGuard.instance.reset();
    NutritionHydrationGuard.instance.currentUserIdOverride = other;
    NutritionHydrationGuard.instance.markComplete(other);
    memory.clearMemory();
    await memory.initForUser(other);
    expect(memory.deletedOverrideTombstones, isEmpty);
    await memory.mergeFromCloud([cloud(name)]);
    expect(names(), {name});
  });
}
