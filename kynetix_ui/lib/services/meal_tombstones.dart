import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/day_log.dart';

/// Per-user record of meal entries the user removed (or replaced) locally
/// whose deletion has not reached the cloud yet.
///
/// The day upload (`merge_day_log`) sends these as server-side tombstones
/// (`day_logs.deleted_meal_ids`), which then persist and keep every device
/// from re-adding the meal. Until the upload lands, hydration skips cloud
/// copies these suppress; a successful upload clears the tombstones that were
/// part of that upload's snapshot.
///
/// Identity = [MealEntry.id]. Tombstones written before ids existed are keyed
/// `rawInput|addedAtMillis` and carry no deletion time; they are still read
/// (and always suppress), and hydration upgrades them to id tombstones when it
/// meets the matching cloud entry.
///
/// Stored in prefs `meal_tombstones_v1_<userId>` (wiped by account deletion's
/// per-user key sweep). Never deletes or changes meal data itself.
class MealTombstones {
  MealTombstones._();
  static final MealTombstones instance = MealTombstones._();

  static const String keyPrefix = 'meal_tombstones_v1';
  static String prefsKeyFor(String userId) => '${keyPrefix}_$userId';

  static String identityOf(MealEntry e) => e.id;

  /// The pre-id identity (`rawInput|addedAtMillis`).
  static String legacyIdentityOf(MealEntry e) => identity(e.rawInput, e.addedAt);
  static String identity(String rawInput, DateTime addedAt) =>
      '$rawInput|${addedAt.millisecondsSinceEpoch}';

  String? _ownerUserId;
  String? get ownerUserId => _ownerUserId;

  /// dateKey -> identity -> tombstone. The stamp is a counter value unique
  /// per recording, so a re-recording after an Undo is distinguishable from
  /// the snapshot one.
  final Map<String, Map<String, _Tomb>> _byDay = {};
  int _stamp = 0;

  SharedPreferences? _prefs;
  Future<void> _writeChain = Future.value();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> loadForUser(String userId, {SharedPreferences? prefsOverride}) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    _ownerUserId = userId;
    _byDay.clear();
    final raw = prefs.getString(prefsKeyFor(userId));
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((day, ids) {
        final m = <String, _Tomb>{};
        (ids as Map<String, dynamic>).forEach((id, value) {
          final t = _Tomb.fromJson(value);
          if (t == null) return;
          m[id] = t;
          if (t.stamp > _stamp) _stamp = t.stamp;
        });
        if (m.isNotEmpty) _byDay[day] = m;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[MealTombstones] unreadable store ignored: $e');
    }
  }

  /// Forget in-memory state (logout / user switch). Disk is untouched.
  void clearMemory() {
    _byDay.clear();
    _ownerUserId = null;
    _prefs = null;
  }

  /// Completes when every write issued so far has landed.
  Future<void> flush() => _writeChain;

  // ── Recording ─────────────────────────────────────────────────────────────

  /// The user removed [entry] from day [dayKey] (at [at], default now).
  void recordRemoval(String dayKey, MealEntry entry, {DateTime? at}) =>
      _record(dayKey, identityOf(entry), at ?? DateTime.now());

  /// The user replaced [oldEntry] with [newEntry]. Only an identity change
  /// leaves an old copy behind; a section move or value edit keeps the id and
  /// is resolved by the per-entry merge (newer `updatedAt` wins).
  void recordReplace(String dayKey, MealEntry oldEntry, MealEntry newEntry, {DateTime? at}) {
    final oldId = identityOf(oldEntry);
    if (oldId == identityOf(newEntry)) return;
    _record(dayKey, oldId, at ?? DateTime.now());
  }

  /// Undo re-added [entry]: it is live again, so it must not be suppressed.
  /// (The restored copy should also be [MealEntry.touched] so it beats a
  /// deletion that already reached the cloud.)
  void forgive(String dayKey, MealEntry entry) {
    final day = _byDay[dayKey];
    if (day == null) return;
    final a = day.remove(identityOf(entry));
    final b = day.remove(legacyIdentityOf(entry));
    if (a == null && b == null) return;
    if (day.isEmpty) _byDay.remove(dayKey);
    _persist();
  }

  /// A pre-id tombstone matching [entry] becomes an id tombstone, so the
  /// next upload can carry it to the cloud. Returns true when upgraded.
  bool upgradeLegacy(String dayKey, MealEntry entry) {
    final day = _byDay[dayKey];
    if (day == null) return false;
    final legacy = legacyIdentityOf(entry);
    if (legacy == identityOf(entry) || day.remove(legacy) == null) return false;
    day[identityOf(entry)] ??= _Tomb(++_stamp, DateTime.now().toUtc());
    _persist();
    return true;
  }

  void _record(String dayKey, String id, DateTime at) {
    _byDay.putIfAbsent(dayKey, () => {})[id] = _Tomb(++_stamp, at.toUtc());
    _persist();
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// A tombstone (id or legacy) exists for [entry] on [dayKey].
  bool isTombstoned(String dayKey, MealEntry entry) {
    final day = _byDay[dayKey];
    if (day == null) return false;
    return day.containsKey(identityOf(entry)) ||
        day.containsKey(legacyIdentityOf(entry));
  }

  /// True when [entry] (a cloud copy) must stay out of the local day: it is
  /// tombstoned here and was not changed after the deletion.
  bool suppresses(String dayKey, MealEntry entry) {
    final day = _byDay[dayKey];
    if (day == null) return false;
    if (day.containsKey(legacyIdentityOf(entry))) return true;
    final t = day[identityOf(entry)];
    if (t == null) return false;
    final at = t.at;
    final updated = entry.updatedAt;
    return at == null || updated == null || !updated.isAfter(at);
  }

  bool get isEmpty => _byDay.isEmpty;

  /// Id tombstones of [dayKey] as `{id: deletedAt ISO-8601 UTC}` (the upload's
  /// `deleted_meal_ids`). Legacy tombstones are not included: their id is
  /// unknown until hydration upgrades them.
  Map<String, String> deletionsFor(String dayKey) => {
        for (final e in (_byDay[dayKey] ?? const <String, _Tomb>{}).entries)
          if (e.value.at != null) e.key: e.value.at!.toIso8601String(),
      };

  /// Tombstones of [dayKey] as they are right now (taken with an upload's
  /// snapshot of the day).
  Map<String, int> snapshotFor(String dayKey) => {
        for (final e in (_byDay[dayKey] ?? const <String, _Tomb>{}).entries)
          e.key: e.value.stamp,
      };

  /// After a successful upload of [dayKey] by [userId], drop only the
  /// tombstones that were in that upload's [snapshot] (and were sent: legacy
  /// ones are kept until upgraded). Anything recorded (or re-recorded) since
  /// then survives.
  void clearUploaded(String dayKey, Map<String, int> snapshot, {required String userId}) {
    if (snapshot.isEmpty || userId != _ownerUserId) return;
    final day = _byDay[dayKey];
    if (day == null) return;
    var changed = false;
    snapshot.forEach((id, stamp) {
      final t = day[id];
      if (t != null && t.stamp == stamp && t.at != null) {
        day.remove(id);
        changed = true;
      }
    });
    if (day.isEmpty) _byDay.remove(dayKey);
    if (changed) _persist();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  void _persist() {
    final owner = _ownerUserId;
    if (owner == null) return; // Signed out: nothing syncs, nothing to guard.
    final payload = _byDay.isEmpty
        ? null
        : jsonEncode({
            for (final d in _byDay.entries)
              d.key: {for (final t in d.value.entries) t.key: t.value.toJson()},
          });
    _writeChain = _writeChain.then((_) async {
      try {
        final prefs = _prefs ??= await SharedPreferences.getInstance();
        final key = prefsKeyFor(owner);
        if (payload == null) {
          await prefs.remove(key);
        } else {
          await prefs.setString(key, payload);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[MealTombstones] write failed: $e');
      }
    });
  }
}

/// One tombstone: its recording stamp and deletion time (null for pre-id
/// tombstones, which were stored as a bare stamp).
class _Tomb {
  const _Tomb(this.stamp, this.at);
  final int stamp;
  final DateTime? at;

  Object toJson() =>
      at == null ? stamp : {'s': stamp, 'at': at!.toIso8601String()};

  static _Tomb? fromJson(Object? v) {
    if (v is num) return _Tomb(v.toInt(), null);
    if (v is Map) {
      final s = v['s'];
      if (s is! num) return null;
      final at = v['at'];
      return _Tomb(s.toInt(), at is String ? DateTime.tryParse(at)?.toUtc() : null);
    }
    return null;
  }
}
