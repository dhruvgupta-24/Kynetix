import '../models/workout_session.dart';

/// "What did I do last time for this set?"
///
/// Sets are matched by type and ordinal, the way a lifter reads a log: the
/// 2nd working set today lines up with the 2nd working set last session,
/// warm-ups with warm-ups and drops with drops. Matching by raw index would
/// compare today's first working set with last week's warm-up.
abstract class PreviousSetLookup {
  /// The [ordinal]-th (0-based) set of [type] in [previousSets], or null.
  static SetEntry? forOrdinal(List<SetEntry> previousSets, SetType type, int ordinal) {
    if (ordinal < 0) return null;
    var seen = 0;
    for (final s in previousSets) {
      if (s.setType != type) continue;
      if (seen == ordinal) return s;
      seen++;
    }
    return null;
  }

  /// The previous value for the set about to be logged: the next ordinal of
  /// [nextType] after what is already in [todaySets].
  static SetEntry? forNextSet({
    required List<SetEntry> previousSets,
    required List<SetEntry> todaySets,
    required SetType nextType,
  }) {
    final ordinal = todaySets.where((s) => s.setType == nextType).length;
    return forOrdinal(previousSets, nextType, ordinal);
  }

  /// The previous value for an already-logged set at [indexInToday].
  static SetEntry? forLoggedSet({
    required List<SetEntry> previousSets,
    required List<SetEntry> todaySets,
    required int indexInToday,
  }) {
    if (indexInToday < 0 || indexInToday >= todaySets.length) return null;
    final type = todaySets[indexInToday].setType;
    var ordinal = 0;
    for (var i = 0; i < indexInToday; i++) {
      if (todaySets[i].setType == type) ordinal++;
    }
    return forOrdinal(previousSets, type, ordinal);
  }

  /// "62.5 × 8" (or "BW × 12" for an unloaded bodyweight set).
  static String format(SetEntry s) {
    final ext = s.externalLoadKg;
    if (ext != null) {
      return ext > 0 ? 'BW+${_num(ext)} × ${s.reps}' : 'BW × ${s.reps}';
    }
    return '${_num(s.weight)} × ${s.reps}';
  }

  static String _num(double v) {
    final r = (v * 100).round() / 100;
    if (r == r.roundToDouble()) return r.toInt().toString();
    final s = r.toStringAsFixed(2);
    return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
  }
}
