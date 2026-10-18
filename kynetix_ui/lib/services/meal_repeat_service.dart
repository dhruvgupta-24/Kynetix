// One-tap repeats: log a food you had recently, or all of yesterday, again.
//
// Copies keep the exact numbers of the entry they copy (no re-estimate), get
// fresh timestamps so they are new entries, and save through the normal day
// pipeline (target freeze, widget, cloud upload). Undo removes exactly the
// copies, with tombstones so a sync can't bring them back.

import '../models/day_log.dart';
import 'meal_tombstones.dart';
import 'persistence_service.dart';

/// A food from recent days, with the newest entry to copy.
class RecentFood {
  const RecentFood({required this.name, required this.entry, required this.times});
  final String name;
  final MealEntry entry;
  final int times;

  double get kcal => entry.calMid;
  double get protein => entry.protMid;
}

abstract final class MealRepeatService {
  /// The foods logged most often in the [days] before [date] (newest copy of
  /// each), skipping anything already logged on [date].
  static List<RecentFood> recentFoods({
    required DateTime date,
    Map<String, DayLog>? store,
    int days = 14,
    int max = 6,
  }) {
    final logs = store ?? dayLogStore;
    final day = DateTime(date.year, date.month, date.day);
    final already = {
      for (final e in logs[dateKey(day)]?.allEntries ?? const <MealEntry>[]) _key(e),
    };
    final counts = <String, int>{};
    final newest = <String, MealEntry>{};
    for (var i = 1; i <= days; i++) {
      final log = logs[dateKey(day.subtract(Duration(days: i)))];
      if (log == null) continue;
      for (final e in log.allEntries) {
        final k = _key(e);
        if (k.isEmpty || already.contains(k) || e.calMid <= 0) continue;
        counts[k] = (counts[k] ?? 0) + 1;
        final prev = newest[k];
        if (prev == null || e.addedAt.isAfter(prev.addedAt)) newest[k] = e;
      }
    }
    final keys = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : newest[b]!.addedAt.compareTo(newest[a]!.addedAt);
      });
    return [
      for (final k in keys.take(max))
        RecentFood(name: _name(newest[k]!), entry: newest[k]!, times: counts[k]!),
    ];
  }

  /// Entries from the day before [date], if any.
  static List<MealEntry> yesterday(DateTime date, {Map<String, DayLog>? store}) {
    final logs = store ?? dayLogStore;
    final y = DateTime(date.year, date.month, date.day).subtract(const Duration(days: 1));
    return logs[dateKey(y)]?.allEntries.toList() ?? const [];
  }

  /// Logs copies of [sources] on [date]. [section] moves them all to one meal;
  /// null keeps each entry's own meal. Returns the new entries (for Undo).
  static Future<List<MealEntry>> relog(
    DateTime date,
    List<MealEntry> sources, {
    MealSection? section,
    bool persist = true,
  }) async {
    final log = logFor(date);
    final base = DateTime.now();
    final added = <MealEntry>[];
    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      final copy = src.copyWith(
        addedAt: base.add(Duration(milliseconds: i)),
        section: section ?? src.section,
        dayOfWeek: date.weekday,
      );
      log.add(copy.section, copy);
      added.add(copy);
    }
    if (persist && added.isNotEmpty) {
      await PersistenceService.saveDay(date);
      PersistenceService.notifyLogsChanged();
    }
    return added;
  }

  /// Removes exactly [added] from [date].
  static Future<void> undo(DateTime date, List<MealEntry> added, {bool persist = true}) async {
    final log = logFor(date);
    for (final e in added) {
      log.remove(e.section, e);
      MealTombstones.instance.recordRemoval(dateKey(date), e);
    }
    if (persist) {
      await PersistenceService.saveDayLogsAndSync(date);
      PersistenceService.notifyLogsChanged();
    }
  }

  static String _name(MealEntry e) =>
      (e.finalSavedInput.isNotEmpty ? e.finalSavedInput : e.rawInput).trim();

  static String _key(MealEntry e) =>
      _name(e).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
