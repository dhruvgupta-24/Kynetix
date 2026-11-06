import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/exercise_classification.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import 'exercise_library_service.dart';
import 'exercise_search_engine.dart';
import 'workout_service.dart';

// ─── Import from other lifting apps ───────────────────────────────────────────
//
// Reads the CSV that Strong, Hevy (and Kynetix's own export) write, so a lifter
// can bring their history across. Columns are found by name, not position,
// since each app (and each app version) orders and names them differently.
// Pounds are converted to kg. Importing the same file twice adds nothing: a
// workout already here (same start minute) is skipped.

/// One imported set, before it is matched to an exercise.
class ImportedSet {
  const ImportedSet({
    required this.weightKg,
    required this.reps,
    this.type = SetType.normal,
    this.rpe,
    this.seconds,
    this.distanceM,
  });
  final double weightKg;
  final int reps;
  final SetType type;
  final double? rpe;
  final int? seconds;
  final double? distanceM;
}

/// One imported workout.
class ImportedWorkout {
  ImportedWorkout({required this.title, required this.start, this.minutes, this.notes});
  final String title;
  final DateTime start;
  final int? minutes;
  final String? notes;

  /// Exercise name to its sets, in the order they appear.
  final Map<String, List<ImportedSet>> exercises = {};
}

/// What the parser understood.
class ImportParse {
  const ImportParse({required this.source, required this.workouts, this.skippedRows = 0});
  final String source;
  final List<ImportedWorkout> workouts;
  final int skippedRows;
}

/// What an import did.
class ImportReport {
  const ImportReport({
    required this.source,
    required this.added,
    required this.alreadyHere,
    required this.overCap,
    required this.newCustomExercises,
    required this.skippedRows,
  });
  final String source;
  final int added;
  final int alreadyHere;
  final int overCap;
  final int newCustomExercises;
  final int skippedRows;

  String get summary {
    final parts = <String>['Added $added ${added == 1 ? 'workout' : 'workouts'} from $source'];
    if (alreadyHere > 0) parts.add('$alreadyHere already here');
    if (overCap > 0) parts.add('$overCap older ones left out (history keeps the latest ${WorkoutImportService.maxSessions})');
    if (newCustomExercises > 0) parts.add('$newCustomExercises new custom ${newCustomExercises == 1 ? 'exercise' : 'exercises'}');
    return '${parts.join('. ')}.';
  }
}

class WorkoutImportService {
  WorkoutImportService._();
  static final WorkoutImportService instance = WorkoutImportService._();

  static const maxSessions = 200;
  static const _lbToKg = 0.45359237;

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Parses a Strong / Hevy / Kynetix workout CSV. Throws [FormatException]
  /// when the file isn't one of those.
  static ImportParse parse(String text) {
    final rows = _csv(text.replaceFirst('﻿', ''));
    if (rows.isEmpty) throw const FormatException('The file is empty.');
    final head = [for (final h in rows.first) h.trim().toLowerCase()];
    int col(List<String> names) {
      for (final n in names) {
        final i = head.indexOf(n);
        if (i >= 0) return i;
      }
      for (final n in names) {
        final i = head.indexWhere((h) => h.startsWith(n));
        if (i >= 0) return i;
      }
      return -1;
    }

    final hevy = head.contains('exercise_title');
    final cTitle = col(hevy ? ['title'] : ['workout name']);
    final cStart = col(hevy ? ['start_time'] : ['date']);
    final cEnd = col(['end_time']);
    final cDur = col(['duration (sec)', 'duration']);
    final cExercise = col(hevy ? ['exercise_title'] : ['exercise name']);
    final cOrder = col(['set order']);
    final cType = col(['set_type']);
    final cKg = col(['weight_kg', 'weight (kg)']);
    final cLb = col(['weight_lbs', 'weight (lbs)']);
    final cWeight = col(['weight']);
    final cUnit = col(['weight unit']);
    final cReps = col(['reps']);
    final cRpe = col(['rpe']);
    final cSec = col(['duration_seconds', 'seconds']);
    final cDistKm = col(['distance_km']);
    final cDistM = col(['distance (meters)', 'distance']);
    final cNotes = col(hevy ? ['description'] : ['workout notes']);

    if (cExercise < 0 || cStart < 0 || cReps < 0) {
      throw const FormatException('This doesn\'t look like a Strong or Hevy export. Export workouts as CSV from that app and pick that file.');
    }
    final source = hevy ? 'Hevy' : 'Strong';

    final byKey = <String, ImportedWorkout>{};
    var skipped = 0;
    String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';
    for (final r in rows.skip(1)) {
      if (r.every((c) => c.trim().isEmpty)) continue;
      final start = parseDate(cell(r, cStart));
      final name = cell(r, cExercise);
      if (start == null || name.isEmpty) {
        skipped++;
        continue;
      }
      final title = cell(r, cTitle).isEmpty ? 'Workout' : cell(r, cTitle);
      final key = '${start.toIso8601String()}|$title';
      final w = byKey.putIfAbsent(key, () {
        int? minutes;
        final end = parseDate(cell(r, cEnd));
        if (end != null && end.isAfter(start)) minutes = end.difference(start).inMinutes;
        final dur = cell(r, cDur);
        minutes ??= _duration(dur);
        final notes = cell(r, cNotes);
        return ImportedWorkout(title: title, start: start, minutes: minutes, notes: notes.isEmpty ? null : notes);
      });

      double? weight;
      if (cKg >= 0 && cell(r, cKg).isNotEmpty) {
        weight = _num(cell(r, cKg));
      } else if (cLb >= 0 && cell(r, cLb).isNotEmpty) {
        weight = (_num(cell(r, cLb)) ?? 0) * _lbToKg;
      } else if (cWeight >= 0) {
        final v = _num(cell(r, cWeight));
        final lbs = cUnit >= 0 && cell(r, cUnit).toLowerCase().startsWith('lb');
        weight = v == null ? null : (lbs ? v * _lbToKg : v);
      }
      final reps = _num(cell(r, cReps))?.round() ?? 0;
      final sec = _num(cell(r, cSec))?.round();
      final dist = cDistKm >= 0 && cell(r, cDistKm).isNotEmpty
          ? (_num(cell(r, cDistKm)) ?? 0) * 1000
          : _num(cell(r, cDistM));
      if (reps <= 0 && (sec ?? 0) <= 0 && (dist ?? 0) <= 0) {
        // Rest-timer rows and empty placeholders carry no set.
        skipped++;
        continue;
      }
      final typeText = (cType >= 0 ? cell(r, cType) : cell(r, cOrder)).toLowerCase();
      final type = typeText.startsWith('w')
          ? SetType.warmUp
          : typeText.startsWith('d')
              ? SetType.dropSet
              : SetType.normal;
      final rpe = _num(cell(r, cRpe));
      w.exercises.putIfAbsent(name, () => []).add(ImportedSet(
            weightKg: ((weight ?? 0) * 10).round() / 10,
            reps: reps,
            type: type,
            rpe: rpe != null && rpe > 0 && rpe <= 10 ? rpe : null,
            seconds: sec != null && sec > 0 ? sec : null,
            distanceM: dist != null && dist > 0 ? dist : null,
          ));
    }
    final workouts = byKey.values.where((w) => w.exercises.isNotEmpty).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (workouts.isEmpty) throw const FormatException('No workouts found in this file.');
    return ImportParse(source: source, workouts: workouts, skippedRows: skipped);
  }

  /// Strong: "2024-01-15 07:30:00". Hevy: "15 Jan 2024, 07:30". Kynetix:
  /// "2024-01-15 07:30". ISO works too.
  static DateTime? parseDate(String s) {
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{1,2}) ([A-Za-z]{3})[a-z]* (\d{4}),? (\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final mo = months.indexOf(m.group(2)!.toLowerCase());
    if (mo < 0) return null;
    return DateTime(int.parse(m.group(3)!), mo + 1, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!));
  }

  /// "3600", "1h 5m", "45m", "1:05:00".
  static int? _duration(String s) {
    if (s.isEmpty) return null;
    final secs = int.tryParse(s);
    if (secs != null) return (secs / 60).round();
    final hm = RegExp(r'(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?').firstMatch(s);
    if (hm != null && (hm.group(1) != null || hm.group(2) != null)) {
      return int.parse(hm.group(1) ?? '0') * 60 + int.parse(hm.group(2) ?? '0');
    }
    final parts = s.split(':').map(int.tryParse).toList();
    if (parts.length == 3 && !parts.contains(null)) return parts[0]! * 60 + parts[1]!;
    return null;
  }

  static double? _num(String s) => s.isEmpty ? null : double.tryParse(s.replaceAll(',', '.'));

  /// Minimal RFC 4180 reader; also accepts Strong's older semicolon files.
  static List<List<String>> _csv(String text) {
    final firstLine = text.split('\n').first;
    final sep = firstLine.split(';').length > firstLine.split(',').length ? ';' : ',';
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == sep) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  // ── Importing ─────────────────────────────────────────────────────────────

  /// Matches each exercise name to the library (or makes a custom exercise)
  /// and saves the workouts. Newest first, up to the history cap.
  Future<ImportReport> import(ImportParse parse) async {
    final ws = WorkoutService.instance;
    final lib = ExerciseLibraryService.instance;
    await lib.initialize();

    final existingMinutes = {for (final s in ws.sessions) _minute(s.date)};
    final fresh = parse.workouts.where((w) => !existingMinutes.contains(_minute(w.start))).toList();
    final alreadyHere = parse.workouts.length - fresh.length;
    final room = (maxSessions - ws.sessions.length).clamp(0, maxSessions);
    final newest = fresh.reversed.take(room).toList().reversed.toList();
    final overCap = fresh.length - newest.length;

    final resolved = <String, Exercise>{};
    var newCustom = 0;
    Future<Exercise> exerciseFor(String name) async {
      final hit = resolved[name];
      if (hit != null) return hit;
      final own = ws.customExercises.where((e) => e.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      Exercise ex;
      if (own != null) {
        ex = own;
      } else {
        final results = lib.searchDetailed(query: name, limit: 1);
        final top = results.isEmpty ? null : results.first;
        if (top != null && top.isBestMatch && top.matchReason.type != MatchReasonType.typoCorrection) {
          ex = top.definition.toExercise();
        } else {
          final c = ExerciseClassifier.classify(name: name, muscle: 'Other');
          ex = Exercise(
            id: 'custom_import_${_hash(name)}',
            name: name,
            muscleGroup: 'Other',
            type: c.type,
          );
          await ws.addCustomExercise(ex);
          newCustom++;
        }
      }
      resolved[name] = ex;
      return ex;
    }

    for (final w in newest) {
      final entries = <ExerciseEntry>[];
      for (final e in w.exercises.entries) {
        final ex = await exerciseFor(e.key);
        entries.add(ExerciseEntry(
          exercise: ex,
          sets: [
            for (final s in e.value)
              SetEntry(
                weight: s.weightKg,
                reps: s.reps,
                rpe: s.rpe,
                setType: s.type,
                durationSeconds: s.seconds,
                distanceMeters: s.distanceM,
              ),
          ],
        ));
      }
      await ws.saveSession(WorkoutSession(
        id: 'ws_import_${_hash('${w.start.toIso8601String()}|${w.title}')}',
        date: w.start,
        splitDayName: w.title,
        entries: entries,
        notes: w.notes,
        durationMinutes: w.minutes,
      ));
    }

    return ImportReport(
      source: parse.source,
      added: newest.length,
      alreadyHere: alreadyHere,
      overCap: overCap,
      newCustomExercises: newCustom,
      skippedRows: parse.skippedRows,
    );
  }

  static String _minute(DateTime d) => '${d.year}-${d.month}-${d.day} ${d.hour}:${d.minute}';
  static String _hash(String s) => sha1.convert(utf8.encode(s)).toString().substring(0, 12);
}
