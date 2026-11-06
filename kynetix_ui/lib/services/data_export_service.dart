import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../models/day_log.dart';
import '../models/workout_session.dart';
import 'body_metrics_service.dart';
import 'profile_service.dart';
import 'workout_service.dart';

/// Everything the user has logged, as files they own: one JSON with all of
/// it, and plain CSVs (meals, sets, weight) that open in any spreadsheet.
/// The workout CSV uses Hevy's column names, which most lifting apps read.
class DataExportService {
  const DataExportService._();
  static const instance = DataExportService._();

  /// File name to contents. Reads local data only: it works offline and
  /// shows exactly what this phone holds.
  Map<String, String> buildFiles({DateTime? now}) {
    final stamp = _day(now ?? DateTime.now());
    return {
      'kynetix-$stamp.json': const JsonEncoder.withIndent('  ').convert(_everything(now ?? DateTime.now())),
      'kynetix-meals-$stamp.csv': mealsCsv(dayLogStore),
      'kynetix-workouts-$stamp.csv': workoutsCsv(WorkoutService.instance.sessions),
      'kynetix-weight-$stamp.csv': weightCsv(),
    };
  }

  /// Opens the share sheet with the export files.
  Future<ShareResultStatus> share() async {
    final files = buildFiles();
    final result = await SharePlus.instance.share(ShareParams(
      title: 'Your Kynetix data',
      files: [
        for (final e in files.entries)
          XFile.fromData(
            Uint8List.fromList(utf8.encode(e.value)),
            name: e.key,
            mimeType: e.key.endsWith('.json') ? 'application/json' : 'text/csv',
          ),
      ],
    ));
    return result.status;
  }

  Map<String, dynamic> _everything(DateTime now) {
    final ws = WorkoutService.instance;
    final keys = dayLogStore.keys.toList()..sort();
    return {
      'format': 'kynetix-export',
      'version': 1,
      'exportedAt': now.toUtc().toIso8601String(),
      'profile': ProfileService.instance.currentUserProfile?.toJson(),
      'days': {
        for (final k in keys)
          if (dayLogStore[k]!.allEntries.isNotEmpty || dayLogStore[k]!.targetCalories != null) k: dayLogStore[k]!.toJson(),
      },
      'workouts': [for (final s in ws.sessions) s.toJson()],
      'split': ws.split.toJson(),
      'customExercises': [for (final e in ws.customExercises) e.toJson()],
      'weighIns': [
        for (final r in BodyMetricsService.instance.manualReadings().reversed)
          {'date': dateKey(r.recordedAt), 'kg': r.kg},
      ],
    };
  }

  // ── CSV ───────────────────────────────────────────────────────────────────

  static String mealsCsv(Map<String, DayLog> logs) {
    final b = StringBuffer('date,meal,time,food,kcal,protein_g,carbs_g,fat_g,fiber_g\n');
    final keys = logs.keys.toList()..sort();
    for (final k in keys) {
      final log = logs[k]!;
      for (final e in log.allEntries) {
        final r = e.result;
        b.writeln([
          k,
          e.section.displayName,
          _hm(e.addedAt),
          e.finalSavedInput.isEmpty ? e.rawInput : e.finalSavedInput,
          _n(r.calories.mid),
          _n(r.protein.mid),
          _n(r.carbohydrates?.mid),
          _n(r.fat?.mid),
          _n(r.fiber?.mid),
        ].map(_cell).join(','));
      }
    }
    return b.toString();
  }

  static String workoutsCsv(List<WorkoutSession> sessions) {
    final b = StringBuffer(
        'title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe\n');
    final sorted = [...sessions]..sort((a, c) => a.date.compareTo(c.date));
    for (final s in sorted) {
      final end = s.date.add(Duration(minutes: s.durationMinutes ?? 0));
      for (final e in s.entries) {
        if (e.isSkipped) continue;
        var i = 0;
        for (final g in e.logicalSets) {
          for (final set in [g.mainSet, ...g.subSets]) {
            final type = switch (set.setType) {
              SetType.warmUp => 'warmup',
              SetType.dropSet => 'dropset',
              SetType.normal => g.isWarmUp ? 'warmup' : 'normal',
            };
            b.writeln([
              s.splitDayName,
              _stamp(s.date),
              _stamp(end),
              s.notes ?? '',
              e.exercise.name,
              '',
              e.notes ?? '',
              '${i++}',
              type,
              _n(set.externalLoadKg ?? set.weight),
              '${set.reps}',
              set.distanceMeters == null ? '' : _n(set.distanceMeters! / 1000),
              set.durationSeconds?.toString() ?? '',
              set.rpe == null ? '' : _n(set.rpe),
            ].map(_cell).join(','));
          }
        }
      }
    }
    return b.toString();
  }

  static String weightCsv() {
    final b = StringBuffer('date,weight_kg\n');
    for (final r in BodyMetricsService.instance.manualReadings().reversed) {
      b.writeln('${dateKey(r.recordedAt)},${_n(r.kg)}');
    }
    return b.toString();
  }

  /// Quotes a cell when it holds a comma, quote or line break.
  static String _cell(String v) =>
      v.contains(RegExp(r'[",\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;

  static String _n(double? v) {
    if (v == null) return '';
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  static String _stamp(DateTime d) => '${_day(d)} ${_hm(d)}';
}
