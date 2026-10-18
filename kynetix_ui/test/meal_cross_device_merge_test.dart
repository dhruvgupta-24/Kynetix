import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/cloud_sync_service.dart';
import 'package:kynetix/services/meal_tombstones.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-device meal sync: per-entry merge (stable ids, newest `updatedAt`
/// wins) with server-side tombstones. The fake server below mirrors
/// `public.kx_merge_meal_sections` (migration 20261017200000).
class FakeDayServer {
  Map<String, dynamic> sections = {};
  Map<String, String> deleted = {};

  static String entryId(Map<String, dynamic> e) {
    final id = e['id'];
    if (id is String && id.isNotEmpty) return id;
    return MealEntry.legacyIdFor(e['addedAt'] as String? ?? '', e['rawInput'] as String? ?? '');
  }

  static DateTime? ts(Object? v) => v is String ? DateTime.tryParse(v) : null;

  /// One `merge_day_log` call (params as the app sends them, JSON round-tripped).
  void merge(Map<String, dynamic> params) {
    final p = jsonDecode(jsonEncode(params)) as Map<String, dynamic>;
    // Tombstones: latest deletion per id.
    final tombs = <String, String>{...deleted};
    (p['p_deleted'] as Map<String, dynamic>).forEach((id, at) {
      final cur = tombs[id];
      if (cur == null || ts(at)!.isAfter(ts(cur)!)) tombs[id] = at as String;
    });
    // Entries: (section, entry, src) — server src 0, incoming src 1.
    final all = <(String, Map<String, dynamic>, int)>[];
    void collect(Map<String, dynamic> secs, int src) => secs.forEach((sec, list) {
          for (final e in list as List) {
            all.add((sec, e as Map<String, dynamic>, src));
          }
        });
    collect(sections, 0);
    collect(p['p_sections'] as Map<String, dynamic>, 1);
    final winners = <String, (String, Map<String, dynamic>, int)>{};
    for (final c in all) {
      final id = entryId(c.$2);
      final cur = winners[id];
      if (cur == null) {
        winners[id] = c;
        continue;
      }
      final a = ts(c.$2['updatedAt']);
      final b = ts(cur.$2['updatedAt']);
      final newer = (a != null && (b == null || a.isAfter(b))) ||
          ((a == null && b == null || a != null && b != null && a.isAtSameMomentAs(b)) && c.$3 > cur.$3);
      if (newer) winners[id] = c;
    }
    final out = <String, List<Map<String, dynamic>>>{};
    winners.forEach((id, w) {
      final t = ts(tombs[id]);
      final u = ts(w.$2['updatedAt']);
      if (t != null && (u == null || !u.isAfter(t))) return;
      out.putIfAbsent(w.$1, () => []).add(w.$2);
    });
    sections = out;
    deleted = tombs;
  }

  Map<String, dynamic> row(String dk) => jsonDecode(jsonEncode({
        'date_key': dk,
        'gym_day_json': null,
        'sections_json': sections,
        'deleted_meal_ids': deleted,
        'target_calories': null,
        'target_protein': null,
      })) as Map<String, dynamic>;
}

class Device {
  Device(this.name);
  final String name;
  DayLog log = DayLog();
  String? storedTombstones;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = 'user-a';
  final day = DateTime(2026, 10, 14);
  final dk = dateKey(day);

  late SharedPreferences prefs;
  late FakeDayServer server;
  Device? current;

  MealEntry meal(String raw, {MealSection section = MealSection.lunch, int minute = 0}) => MealEntry(
        rawInput: raw,
        result: NutritionResult.createCustom(canonicalMeal: raw, calories: 400, protein: 30, source: 'test'),
        addedAt: DateTime(2026, 10, 14, 12, minute, 7, 123),
        section: section,
        dayOfWeek: day.weekday,
        parsedFoods: [raw],
        finalSavedInput: raw,
      );

  List<String> labels(DayLog log) => [
        for (final s in MealSection.values)
          for (final e in log.entriesFor(s)) '${s.name}:${e.finalSavedInput}',
      ];

  List<String> serverLabels() => [
        for (final s in MealSection.values)
          for (final e in (server.sections[s.name] as List? ?? const []))
            '${s.name}:${(e as Map)['finalSavedInput']}',
      ];

  /// Switch the process to [d] (its own tombstone store; same signed-in user).
  Future<void> use(Device d) async {
    final t = MealTombstones.instance;
    await t.flush();
    final key = MealTombstones.prefsKeyFor(user);
    if (current != null) current!.storedTombstones = prefs.getString(key);
    if (d.storedTombstones == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, d.storedTombstones!);
    }
    t.clearMemory();
    await t.loadForUser(user, prefsOverride: prefs);
    current = d;
  }

  Future<void> upload(Device d) async {
    await use(d);
    final t = MealTombstones.instance;
    final snapshot = t.snapshotFor(dk);
    server.merge(CloudSyncService.dayMergeParams(dk, d.log, t.deletionsFor(dk)));
    t.clearUploaded(dk, snapshot, userId: user);
  }

  Future<void> hydrate(Device d) async {
    await use(d);
    d.log = CloudSyncService.mergeCloudDayRow(dk, server.row(dk), d.log);
  }

  Future<void> deleteOn(Device d, MealEntry e, {DateTime? at}) async {
    await use(d);
    final live = d.log.allEntries.firstWhere((x) => x.id == e.id);
    d.log.remove(live.section, live);
    MealTombstones.instance.recordRemoval(dk, live, at: at);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    server = FakeDayServer();
    current = null;
    MealTombstones.instance.clearMemory();
    dayLogStore.clear();
  });

  group('two devices', () {
    test('delete on A, stale upload from B, hydrate: stays deleted everywhere', () async {
      final a = Device('A'), b = Device('B');
      final rice = meal('rice'), eggs = meal('eggs', minute: 1);
      a.log..add(MealSection.lunch, rice)..add(MealSection.lunch, eggs);
      await upload(a);
      await hydrate(b);
      expect(labels(b.log), ['lunch:rice', 'lunch:eggs']);

      await deleteOn(a, rice);
      await upload(a);
      expect(serverLabels(), ['lunch:eggs']);
      expect(server.deleted.keys, [rice.id]);
      // A's local pending tombstone is cleared; the server one persists.
      expect(MealTombstones.instance.isEmpty, isTrue);

      // B never hydrated in between and uploads its stale day.
      await upload(b);
      expect(serverLabels(), ['lunch:eggs']);

      await hydrate(b);
      expect(labels(b.log), ['lunch:eggs']);
      await hydrate(a);
      expect(labels(a.log), ['lunch:eggs']);
    });

    test('concurrent adds from both devices survive', () async {
      final a = Device('A'), b = Device('B');
      final rice = meal('rice');
      a.log.add(MealSection.lunch, rice);
      await upload(a);
      await hydrate(b);

      a.log.add(MealSection.dinner, meal('dal', section: MealSection.dinner, minute: 5));
      b.log.add(MealSection.breakfast, meal('toast', section: MealSection.breakfast, minute: 6));
      await upload(a);
      await upload(b); // B has not seen dal: must not drop it.
      expect(serverLabels(), ['breakfast:toast', 'lunch:rice', 'dinner:dal']);

      await hydrate(a);
      await hydrate(b);
      expect(labels(a.log), ['breakfast:toast', 'lunch:rice', 'dinner:dal']);
      expect(labels(b.log), ['breakfast:toast', 'lunch:rice', 'dinner:dal']);
    });

    test('the newer edit wins, in either upload order, and moves sections', () async {
      final a = Device('A'), b = Device('B');
      final eggs = meal('eggs');
      a.log.add(MealSection.lunch, eggs);
      await upload(a);
      await hydrate(b);

      // B edits (as AddMealScreen does: same id, stamped, may move section).
      final edited = eggs.copyWith(
        finalSavedInput: '3 eggs',
        section: MealSection.dinner,
        updatedAt: DateTime.utc(2026, 10, 14, 14),
      );
      b.log.replace(MealSection.lunch, b.log.allEntries.single, edited);
      await upload(b);
      await upload(a); // A's stale unedited copy.
      expect(serverLabels(), ['dinner:3 eggs']);

      await hydrate(a);
      expect(labels(a.log), ['dinner:3 eggs']);

      // An older edit uploaded later loses to the newer one.
      final olderEdit = eggs.copyWith(finalSavedInput: '2 eggs', updatedAt: DateTime.utc(2026, 10, 14, 13));
      final c = Device('C')..log.add(MealSection.lunch, olderEdit);
      await upload(c);
      expect(serverLabels(), ['dinner:3 eggs']);
      await hydrate(c);
      expect(labels(c.log), ['dinner:3 eggs']);
    });

    test('an edit made after a deletion elsewhere wins over the tombstone', () async {
      final a = Device('A'), b = Device('B');
      final eggs = meal('eggs');
      a.log.add(MealSection.lunch, eggs);
      await upload(a);
      await hydrate(b);

      await deleteOn(a, eggs, at: DateTime.utc(2026, 10, 14, 13));
      await upload(a);
      final edited = eggs.copyWith(finalSavedInput: 'eggs edited', updatedAt: DateTime.utc(2026, 10, 14, 13, 30));
      b.log.replace(MealSection.lunch, b.log.allEntries.single, edited);
      await upload(b);
      expect(serverLabels(), ['lunch:eggs edited']);
      await hydrate(a);
      expect(labels(a.log), ['lunch:eggs edited']);
    });

    test('Undo after the deletion reached the cloud restores it everywhere', () async {
      final a = Device('A'), b = Device('B');
      final rice = meal('rice');
      a.log.add(MealSection.lunch, rice);
      await upload(a);
      await hydrate(b);

      await deleteOn(a, rice, at: DateTime.now().subtract(const Duration(seconds: 2)));
      await upload(a); // deletion lands before the user taps Undo
      expect(serverLabels(), isEmpty);

      // Undo as DayDetailScreen does it.
      a.log.add(MealSection.lunch, rice.touched());
      MealTombstones.instance.forgive(dk, rice);
      await upload(a);
      expect(serverLabels(), ['lunch:rice']);

      await hydrate(b);
      expect(labels(b.log), ['lunch:rice']);
      await hydrate(a);
      expect(labels(a.log), ['lunch:rice']);
    });

    test('a deletion not yet uploaded is not undone by hydration', () async {
      final a = Device('A');
      final rice = meal('rice'), eggs = meal('eggs', minute: 1);
      a.log..add(MealSection.lunch, rice)..add(MealSection.lunch, eggs);
      await upload(a);
      await deleteOn(a, rice); // offline: no upload
      await hydrate(a);
      expect(labels(a.log), ['lunch:eggs']);
      await upload(a);
      expect(serverLabels(), ['lunch:eggs']);
    });

    test('a newer local edit is kept when the cloud copy is older', () async {
      final a = Device('A');
      final eggs = meal('eggs');
      a.log.add(MealSection.lunch, eggs);
      await upload(a);
      final edited = eggs.copyWith(finalSavedInput: 'eggs v2', updatedAt: DateTime.utc(2026, 10, 14, 15));
      a.log.replace(MealSection.lunch, eggs, edited);
      await hydrate(a); // before the edit uploads
      expect(labels(a.log), ['lunch:eggs v2']);
    });
  });

  group('legacy data keeps its identity', () {
    test('ids derive like the server (md5 parity with kx_meal_entry_id)', () {
      // Value computed by public.kx_meal_entry_id on the live database.
      expect(MealEntry.legacyIdFor('2026-10-14T12:00:07.123456', 'dal chawal'),
          'l-f44750a9c95bf3b2347187ac99cceb6c');
    });

    test('a legacy json (no id) keeps its derived id through a round trip', () {
      final legacy = meal('rice').toJson()
        ..remove('id')
        ..remove('updatedAt');
      final e = MealEntry.fromJson(legacy);
      expect(e.id, MealEntry.legacyIdFor(legacy['addedAt'] as String, 'rice'));
      expect(e.id, meal('rice').id);
      final again = MealEntry.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(again.id, e.id);
      expect(again.updatedAt, isNull);
      // Old fields still written unchanged.
      expect(e.toJson()['rawInput'], 'rice');
      expect(e.toJson()['addedAt'], legacy['addedAt']);
    });

    test('copyWith keeps the id unless addedAt changes', () {
      final e = meal('rice');
      expect(e.copyWith(rawInput: 'rice 2', finalSavedInput: 'x').id, e.id);
      expect(e.copyWith(section: MealSection.dinner).id, e.id);
      final relogged = e.copyWith(addedAt: DateTime(2026, 10, 15, 9));
      expect(relogged.id, isNot(e.id));
      expect(e.touched().id, e.id);
      expect(e.touched().updatedAt, isNotNull);
    });

    test('old-client cloud rows (no ids) merge without duplicates', () async {
      final a = Device('A');
      final rice = meal('rice');
      final legacyJson = rice.toJson()..remove('id');
      server.sections = {'lunch': [legacyJson]};
      a.log.add(MealSection.lunch, MealEntry.fromJson(Map.of(legacyJson)));
      await hydrate(a);
      expect(labels(a.log), ['lunch:rice']);
      await upload(a);
      expect(serverLabels(), ['lunch:rice']);
    });

    test('a pre-id tombstone still suppresses and is upgraded for upload', () async {
      final a = Device('A');
      final rice = meal('rice');
      final legacyJson = rice.toJson()..remove('id');
      server.sections = {'lunch': [legacyJson]};
      // Store written by the previous app version: identity -> bare stamp.
      a.storedTombstones = jsonEncode({
        dk: {MealTombstones.legacyIdentityOf(rice): 3},
      });
      await hydrate(a);
      expect(labels(a.log), isEmpty);
      expect(MealTombstones.instance.deletionsFor(dk).keys, [rice.id]);
      await upload(a);
      expect(serverLabels(), isEmpty);
      expect(server.deleted.keys, [rice.id]);
      await hydrate(a);
      expect(labels(a.log), isEmpty);
    });
  });
}
