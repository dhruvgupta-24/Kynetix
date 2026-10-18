import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/cloud_sync_service.dart';
import 'package:kynetix/services/meal_tombstones.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deleted / edited meals must not be resurrected by cloud hydration, which
/// unions cloud entries into the local day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = 'user-a';
  const userB = 'user-b';
  final day = DateTime(2026, 10, 14);
  final dk = dateKey(day);

  MealEntry meal(String raw, {MealSection section = MealSection.lunch, int minute = 0, String? saved}) => MealEntry(
        rawInput: raw,
        result: NutritionResult.createCustom(canonicalMeal: raw, calories: 400, protein: 30, source: 'test'),
        addedAt: DateTime(2026, 10, 14, 12, minute, 7, 123),
        section: section,
        dayOfWeek: day.weekday,
        parsedFoods: [raw],
        finalSavedInput: saved ?? raw,
      );

  /// The cloud `day_logs` row as the uploader writes it.
  Map<String, dynamic> cloudRow(List<MealEntry> entries) => {
        'date_key': dk,
        'gym_day_json': null,
        'sections_json': {
          for (final s in MealSection.values)
            s.name: entries.where((e) => e.section == s).map((e) => e.toJson()).toList(),
        },
        'target_calories': null,
        'target_protein': null,
      };

  List<String> labels(DayLog log) => [
        for (final s in MealSection.values)
          for (final e in log.entriesFor(s)) '${s.name}:${e.finalSavedInput}',
      ];

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    MealTombstones.instance.clearMemory();
    await MealTombstones.instance.loadForUser(userA, prefsOverride: prefs);
    dayLogStore.clear();
  });

  test('without a tombstone hydration still adds cloud-only entries', () {
    final rice = meal('rice');
    final merged = CloudSyncService.mergeCloudDayRow(dk, cloudRow([rice]), DayLog());
    expect(labels(merged), ['lunch:rice']);
  });

  test('a deleted meal is not resurrected while the cloud still holds it', () async {
    final rice = meal('rice');
    final eggs = meal('eggs', minute: 1);
    final log = DayLog()
      ..add(MealSection.lunch, rice)
      ..add(MealSection.lunch, eggs);

    log.remove(MealSection.lunch, rice);
    MealTombstones.instance.recordRemoval(dk, rice);

    final merged = CloudSyncService.mergeCloudDayRow(dk, cloudRow([rice, eggs]), log);
    expect(labels(merged), ['lunch:eggs']);

    // Survives a relaunch (reload from prefs).
    await MealTombstones.instance.flush();
    MealTombstones.instance.clearMemory();
    await MealTombstones.instance.loadForUser(userA, prefsOverride: prefs);
    final relaunched = CloudSyncService.mergeCloudDayRow(dk, cloudRow([rice, eggs]), DayLog()..add(MealSection.lunch, eggs));
    expect(labels(relaunched), ['lunch:eggs']);
  });

  test('editing a meal does not duplicate it on hydration', () {
    final original = meal('rice');
    final log = DayLog()..add(MealSection.lunch, original);

    // Text edit (new identity) — the generic replace contract.
    final retexted = original.copyWith(rawInput: 'rice and dal', finalSavedInput: 'rice and dal');
    log.replace(MealSection.lunch, original, retexted);
    MealTombstones.instance.recordReplace(dk, original, retexted);
    expect(labels(CloudSyncService.mergeCloudDayRow(dk, cloudRow([original]), log)), ['lunch:rice and dal']);

    // Section move with the same identity (what AddMealScreen does on edit).
    final moved = MealEntry(
      rawInput: retexted.rawInput,
      result: retexted.result,
      addedAt: retexted.addedAt,
      section: MealSection.dinner,
      dayOfWeek: retexted.dayOfWeek,
      parsedFoods: retexted.parsedFoods,
      finalSavedInput: 'rice and dal (dinner)',
    );
    log.replace(MealSection.lunch, retexted, moved);
    MealTombstones.instance.recordReplace(dk, retexted, moved);
    expect(labels(CloudSyncService.mergeCloudDayRow(dk, cloudRow([retexted]), log)), ['dinner:rice and dal (dinner)']);
  });

  test('an edit that keeps identity and section records nothing', () {
    final original = meal('rice');
    final edited = MealEntry(
      rawInput: original.rawInput,
      result: original.result,
      addedAt: original.addedAt,
      section: original.section,
      dayOfWeek: original.dayOfWeek,
      parsedFoods: original.parsedFoods,
      finalSavedInput: 'rice 200g',
    );
    MealTombstones.instance.recordReplace(dk, original, edited);
    expect(MealTombstones.instance.isEmpty, isTrue);
  });

  test('Undo forgives the tombstone so the entry syncs normally', () async {
    final rice = meal('rice');
    MealTombstones.instance.recordRemoval(dk, rice);
    MealTombstones.instance.forgive(dk, rice);
    expect(MealTombstones.instance.isTombstoned(dk, rice), isFalse);

    // Restored on this device, another device's hydration-equivalent: cloud
    // copy is accepted again.
    final merged = CloudSyncService.mergeCloudDayRow(dk, cloudRow([rice]), DayLog());
    expect(labels(merged), ['lunch:rice']);
    await MealTombstones.instance.flush();
    expect(prefs.getString(MealTombstones.prefsKeyFor(userA)), isNull);
  });

  test('a successful upload clears only the tombstones in its snapshot', () async {
    final rice = meal('rice');
    final eggs = meal('eggs', minute: 1);
    MealTombstones.instance.recordRemoval(dk, rice);

    final snapshot = MealTombstones.instance.snapshotFor(dk); // upload starts
    MealTombstones.instance.recordRemoval(dk, eggs); // deleted mid-upload
    MealTombstones.instance.clearUploaded(dk, snapshot, userId: userA); // upload ok

    expect(MealTombstones.instance.isTombstoned(dk, rice), isFalse);
    expect(MealTombstones.instance.isTombstoned(dk, eggs), isTrue);

    await MealTombstones.instance.flush();
    final stored = jsonDecode(prefs.getString(MealTombstones.prefsKeyFor(userA))!) as Map<String, dynamic>;
    expect((stored[dk] as Map).keys, [MealTombstones.identityOf(eggs)]);
  });

  test('delete → undo → delete during an upload keeps the newer tombstone', () {
    final rice = meal('rice');
    MealTombstones.instance.recordRemoval(dk, rice);
    final snapshot = MealTombstones.instance.snapshotFor(dk);
    MealTombstones.instance.forgive(dk, rice);
    MealTombstones.instance.recordRemoval(dk, rice);
    MealTombstones.instance.clearUploaded(dk, snapshot, userId: userA);
    expect(MealTombstones.instance.isTombstoned(dk, rice), isTrue);
  });

  test('an upload by another user never clears this user\'s tombstones', () {
    final rice = meal('rice');
    MealTombstones.instance.recordRemoval(dk, rice);
    MealTombstones.instance.clearUploaded(dk, MealTombstones.instance.snapshotFor(dk), userId: userB);
    expect(MealTombstones.instance.isTombstoned(dk, rice), isTrue);
  });

  test('tombstones are per user', () async {
    final rice = meal('rice');
    MealTombstones.instance.recordRemoval(dk, rice);
    await MealTombstones.instance.flush();
    expect(prefs.containsKey(MealTombstones.prefsKeyFor(userA)), isTrue);

    // Switch to user B: A's deletions do not affect B's hydration.
    MealTombstones.instance.clearMemory();
    await MealTombstones.instance.loadForUser(userB, prefsOverride: prefs);
    expect(MealTombstones.instance.isTombstoned(dk, rice), isFalse);
    expect(labels(CloudSyncService.mergeCloudDayRow(dk, cloudRow([rice]), DayLog())), ['lunch:rice']);
    expect(prefs.containsKey(MealTombstones.prefsKeyFor(userB)), isFalse);

    // Back to A: still tombstoned.
    MealTombstones.instance.clearMemory();
    await MealTombstones.instance.loadForUser(userA, prefsOverride: prefs);
    expect(MealTombstones.instance.isTombstoned(dk, rice), isTrue);

    // Account deletion's per-user sweep removes it.
    final removed = await PersistenceService.removeKeysForUser(userA, prefsOverride: prefs);
    expect(removed, contains(MealTombstones.prefsKeyFor(userA)));
  });

  test('tombstones are scoped to their day', () {
    final rice = meal('rice');
    MealTombstones.instance.recordRemoval(dk, rice);
    final otherDay = dateKey(DateTime(2026, 10, 15));
    expect(MealTombstones.instance.isTombstoned(otherDay, rice), isFalse);
  });
}
