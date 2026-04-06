import 'nutrition_result.dart';

// ─── Workout types ────────────────────────────────────────────────────────────

enum WorkoutType {
  push,
  pull,
  legs,
  upper,
  cardio,
  rest,
  other;

  String get displayName => switch (this) {
        WorkoutType.push   => 'Push',
        WorkoutType.pull   => 'Pull',
        WorkoutType.legs   => 'Legs',
        WorkoutType.upper  => 'Upper',
        WorkoutType.cardio => 'Cardio',
        WorkoutType.rest   => 'Rest',
        WorkoutType.other  => 'Other',
      };

  String get emoji => switch (this) {
        WorkoutType.push   => '\u{1FAB8}',
        WorkoutType.pull   => '\u{1FAB7}',
        WorkoutType.legs   => '🦵',
        WorkoutType.upper  => '💪',
        WorkoutType.cardio => '🏃',
        WorkoutType.rest   => '😴',
        WorkoutType.other  => '🏋️',
      };

  /// Map a free-text split-day name to the nearest WorkoutType for UI chips
  /// and calorie cycle categorisation.  Non-exact matches fall through to
  /// [other] rather than null so callers never need to guard.
  static WorkoutType fromSplitName(String name) {
    final lc = name.toLowerCase();
    if (lc.contains('push') || lc.contains('chest') || lc.contains('tricep')) {
      return WorkoutType.push;
    }
    if (lc.contains('pull') || lc.contains('back') || lc.contains('bicep')) {
      return WorkoutType.pull;
    }
    if (lc.contains('leg') || lc.contains('quad') || lc.contains('hamstring') ||
        lc.contains('glute')) {
      return WorkoutType.legs;
    }
    if (lc.contains('upper') || lc.contains('shoulder') || lc.contains('delt')) {
      return WorkoutType.upper;
    }
    if (lc.contains('cardio') || lc.contains('run') || lc.contains('cycle') ||
        lc.contains('swim')) {
      return WorkoutType.cardio;
    }
    if (lc.contains('rest')) {
      return WorkoutType.rest;
    }
    return WorkoutType.other;
  }
}


// ─── GymDay ───────────────────────────────────────────────────────────────────

class GymDay {
  final bool         didGym;
  final WorkoutType? workoutType;

  /// Raw split-day name from the configured WorkoutSplit
  /// (e.g. "Chest + Triceps", "Back + Biceps", "Legs", "Push", "Pull").
  /// Set automatically from the split; never null when derived from split.
  /// Preserved across user type-overrides so the engine always has context.
  final String? splitDayName;

  /// True when the user manually changed the workout type from the split
  /// default. Used to distinguish a deliberate override from a prefill.
  final bool splitOverridden;

  const GymDay({
    required this.didGym,
    this.workoutType,
    this.splitDayName,
    this.splitOverridden = false,
  });

  /// Returns a copy with the user's manually-chosen split day name and type.
  /// This explicitly updates the `splitDayName` to match the chip they clicked,
  /// preserving context for the target engine, while marking it as an override.
  GymDay withUserOverride({required String? splitName, required WorkoutType type}) => GymDay(
    didGym:          true,
    workoutType:     type,
    splitDayName:    splitName,
    splitOverridden: true,
  );

  /// Returns a copy that marks the day as gym without changing the split prefill.
  GymDay withGym(bool did) => GymDay(
    didGym:          did,
    workoutType:     did ? workoutType : null,
    splitDayName:    splitDayName,
    splitOverridden: did ? splitOverridden : false,
  );

  Map<String, dynamic> toJson() => {
    'didGym':          didGym,
    if (workoutType  != null) 'workoutType':     workoutType!.name,
    if (splitDayName != null) 'splitDayName':    splitDayName,
    if (splitOverridden)      'splitOverridden': splitOverridden,
  };

  factory GymDay.fromJson(Map<String, dynamic> j) => GymDay(
    didGym:          j['didGym']          as bool?   ?? false,
    workoutType:     j['workoutType'] != null
        ? _safeWorkoutType(j['workoutType'] as String)
        : null,
    splitDayName:    j['splitDayName']    as String?,
    splitOverridden: j['splitOverridden'] as bool?   ?? false,
  );

  static WorkoutType? _safeWorkoutType(String name) {
    try {
      return WorkoutType.values.byName(name);
    } catch (_) {
      return null;
    }
  }
}


// ─── Meal sections ────────────────────────────────────────────────────────────

enum MealSection {
  breakfast,
  lunch,
  eveningSnack,
  dinner,
  lateNight;

  String get displayName => switch (this) {
        MealSection.breakfast    => 'Breakfast',
        MealSection.lunch        => 'Lunch',
        MealSection.eveningSnack => 'Evening Snack',
        MealSection.dinner       => 'Dinner',
        MealSection.lateNight    => 'Late Night',
      };

  String get emoji => switch (this) {
        MealSection.breakfast    => '🌅',
        MealSection.lunch        => '☀️',
        MealSection.eveningSnack => '🍵',
        MealSection.dinner       => '🌙',
        MealSection.lateNight    => '🌛',
      };
}

// ─── MealEntry ────────────────────────────────────────────────────────────────

class MealEntry {
  final String           rawInput;
  final NutritionResult  result;
  final DateTime         addedAt;
  final MealSection      section;
  final int              dayOfWeek;
  final List<String>     parsedFoods;
  final bool             edited;
  final int              editCount;
  final String           finalSavedInput;

  const MealEntry({
    required this.rawInput,
    required this.result,
    required this.addedAt,
    required this.section,
    required this.dayOfWeek,
    required this.parsedFoods,
    this.edited = false,
    this.editCount = 0,
    required this.finalSavedInput,
  });

  MealEntry copyWith({
    String? rawInput,
    NutritionResult? result,
    DateTime? addedAt,
    MealSection? section,
    int? dayOfWeek,
    List<String>? parsedFoods,
    bool? edited,
    int? editCount,
    String? finalSavedInput,
  }) => MealEntry(
    rawInput: rawInput ?? this.rawInput,
    result: result ?? this.result,
    addedAt: addedAt ?? this.addedAt,
    section: section ?? this.section,
    dayOfWeek: dayOfWeek ?? this.dayOfWeek,
    parsedFoods: parsedFoods ?? this.parsedFoods,
    edited: edited ?? this.edited,
    editCount: editCount ?? this.editCount,
    finalSavedInput: finalSavedInput ?? this.finalSavedInput,
  );

  double get calMid  => (result.calories.min + result.calories.max) / 2;
  double get protMid => (result.protein.min  + result.protein.max)  / 2;

  Map<String, dynamic> toJson() => {
    'rawInput': rawInput,
    'addedAt':  addedAt.toIso8601String(),
    'section': section.name,
    'dayOfWeek': dayOfWeek,
    'parsedFoods': parsedFoods,
    'edited': edited,
    'editCount': editCount,
    'finalSavedInput': finalSavedInput,
    'result':   result.toJson(),
  };

  factory MealEntry.fromJson(Map<String, dynamic> j) => MealEntry(
    rawInput: j['rawInput'] as String? ?? '',
    addedAt:  DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
    section: MealSection.values.byName(j['section'] as String? ?? MealSection.breakfast.name),
    dayOfWeek: j['dayOfWeek'] as int? ?? DateTime.now().weekday,
    parsedFoods: List<String>.from(j['parsedFoods'] as List<dynamic>? ?? const []),
    edited: j['edited'] as bool? ?? false,
    editCount: j['editCount'] as int? ?? 0,
    finalSavedInput: j['finalSavedInput'] as String? ?? j['rawInput'] as String? ?? '',
    result:   NutritionResult.fromJson(j['result'] as Map<String, dynamic>? ?? {}),
  );
}

// ─── DayLog ───────────────────────────────────────────────────────────────────

class DayLog {
  final Map<MealSection, List<MealEntry>> _sections = {
    for (final s in MealSection.values) s: [],
  };

  /// Gym status for this day — mutable, set from DayDetailScreen.
  GymDay? gymDay;

  List<MealEntry> entriesFor(MealSection section) =>
      List.unmodifiable(_sections[section]!);

  void add(MealSection section, MealEntry entry) =>
      _sections[section]!.add(entry);

  void replace(MealSection oldSection, MealEntry oldEntry, MealEntry newEntry) {
    final oldList = _sections[oldSection]!;
    final index = oldList.indexOf(oldEntry);
    if (index >= 0) {
      oldList.removeAt(index);
    } else {
      oldList.remove(oldEntry);
    }
    _sections[newEntry.section]!.insert(index >= 0 ? index.clamp(0, _sections[newEntry.section]!.length) : _sections[newEntry.section]!.length, newEntry);
  }

  void remove(MealSection section, MealEntry entry) =>
      _sections[section]!.remove(entry);

  double get totalCaloriesMin => _all.fold(0, (s, e) => s + e.result.calories.min);
  double get totalCaloriesMax => _all.fold(0, (s, e) => s + e.result.calories.max);
  double get totalProteinMin  => _all.fold(0, (s, e) => s + e.result.protein.min);
  double get totalProteinMax  => _all.fold(0, (s, e) => s + e.result.protein.max);

  double get totalCaloriesMid => (totalCaloriesMin + totalCaloriesMax) / 2;
  double get totalProteinMid  => (totalProteinMin  + totalProteinMax)  / 2;

  List<MealEntry> get _all =>
      _sections.values.expand((e) => e).toList();

  bool get isEmpty => _all.isEmpty;

  // ── JSON serialization ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    if (gymDay != null) 'gymDay': gymDay!.toJson(),
    'sections': {
      for (final s in MealSection.values)
        s.name: _sections[s]!.map((e) => e.toJson()).toList(),
    },
  };

  static DayLog fromJson(Map<String, dynamic> j) {
    final log = DayLog();
    if (j['gymDay'] is Map<String, dynamic>) {
      log.gymDay = GymDay.fromJson(j['gymDay'] as Map<String, dynamic>);
    }
    final sections = j['sections'] as Map<String, dynamic>? ?? {};
    for (final s in MealSection.values) {
      final list = sections[s.name] as List<dynamic>? ?? [];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          log._sections[s]!.add(MealEntry.fromJson(item));
        }
      }
    }
    return log;
  }
}

// ─── Global store ─────────────────────────────────────────────────────────────

/// Key format: "yyyy-MM-dd"
final Map<String, DayLog> dayLogStore = {};

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DayLog logFor(DateTime d) {
  final key = dateKey(d);
  return dayLogStore.putIfAbsent(key, DayLog.new);
}
