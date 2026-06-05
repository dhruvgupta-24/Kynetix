
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

  /// Manual override for the day's calorie target
  final double? targetCaloriesOverride;

  const GymDay({
    required this.didGym,
    this.workoutType,
    this.splitDayName,
    this.splitOverridden = false,
    this.targetCaloriesOverride,
  });

  /// Returns a copy with the user's manually-chosen split day name and type.
  /// This explicitly updates the `splitDayName` to match the chip they clicked,
  /// preserving context for the target engine, while marking it as an override.
  GymDay withUserOverride({required String? splitName, required WorkoutType type}) => GymDay(
    didGym:          true,
    workoutType:     type,
    splitDayName:    splitName,
    splitOverridden: true,
    targetCaloriesOverride: targetCaloriesOverride,
  );

  /// Returns a copy that marks the day as gym without changing the split prefill.
  GymDay withGym(bool did) => GymDay(
    didGym:          did,
    workoutType:     did ? workoutType : null,
    splitDayName:    splitDayName,
    splitOverridden: did ? splitOverridden : false,
    targetCaloriesOverride: targetCaloriesOverride,
  );

  /// Returns a copy with a new calorie override. Set to null to clear.
  GymDay withTargetCaloriesOverride(double? override) => GymDay(
    didGym:          didGym,
    workoutType:     workoutType,
    splitDayName:    splitDayName,
    splitOverridden: splitOverridden,
    targetCaloriesOverride: override,
  );

  Map<String, dynamic> toJson() => {
    'didGym':          didGym,
    if (workoutType  != null) 'workoutType':     workoutType!.name,
    if (splitDayName != null) 'splitDayName':    splitDayName,
    if (splitOverridden)      'splitOverridden': splitOverridden,
    if (targetCaloriesOverride != null) 'targetCaloriesOverride': targetCaloriesOverride,
  };

  factory GymDay.fromJson(Map<String, dynamic> j) => GymDay(
    didGym:          j['didGym']          as bool?   ?? false,
    workoutType:     j['workoutType'] != null
        ? _safeWorkoutType(j['workoutType'] as String)
        : null,
    splitDayName:    j['splitDayName']    as String?,
    splitOverridden: j['splitOverridden'] as bool?   ?? false,
    targetCaloriesOverride: (j['targetCaloriesOverride'] as num?)?.toDouble(),
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
  final bool             userCorrected;

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
    this.userCorrected = false,
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
    bool? userCorrected,
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
    userCorrected: userCorrected ?? this.userCorrected,
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
    'userCorrected': userCorrected || result.userCorrected,
  };

  factory MealEntry.fromJson(Map<String, dynamic> j) {
    final res = NutritionResult.fromJson(j['result'] as Map<String, dynamic>? ?? {});
    return MealEntry(
      rawInput: j['rawInput'] as String? ?? '',
      addedAt:  DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
      section: MealSection.values.byName(j['section'] as String? ?? MealSection.breakfast.name),
      dayOfWeek: j['dayOfWeek'] as int? ?? DateTime.now().weekday,
      parsedFoods: List<String>.from(j['parsedFoods'] as List<dynamic>? ?? const []),
      edited: j['edited'] as bool? ?? false,
      editCount: j['editCount'] as int? ?? 0,
      finalSavedInput: j['finalSavedInput'] as String? ?? j['rawInput'] as String? ?? '',
      result:   res,
      userCorrected: j['userCorrected'] as bool? ?? res.userCorrected,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MealEntry &&
          runtimeType == other.runtimeType &&
          addedAt.isAtSameMomentAs(other.addedAt);

  @override
  int get hashCode => addedAt.hashCode;
}

// ─── DayLog ───────────────────────────────────────────────────────────────────

class DayLog {
  final Map<MealSection, List<MealEntry>> _sections = {
    for (final s in MealSection.values) s: [],
  };

  /// Gym status for this day — mutable, set from DayDetailScreen.
  GymDay? gymDay;

  /// Calorie carry-forward adjustment applied to this day (optional).
  double? carryForwardAdjustment;

  List<MealEntry> entriesFor(MealSection section) =>
      List.unmodifiable(_sections[section]!);

  void add(MealSection section, MealEntry entry) =>
      _sections[section]!.add(entry);

  void replace(MealSection oldSection, MealEntry oldEntry, MealEntry newEntry) {
    final oldList = _sections[oldSection]!;
    final index = oldList.indexWhere((e) => e.addedAt.isAtSameMomentAs(oldEntry.addedAt) || e == oldEntry);
    if (index >= 0) {
      oldList.removeAt(index);
    } else {
      oldList.removeWhere((e) => e.addedAt.isAtSameMomentAs(oldEntry.addedAt) || e == oldEntry);
    }
    // Safeguard: also clear any potential duplicates matching this entry in the target section
    _sections[newEntry.section]!.removeWhere((e) => e.addedAt.isAtSameMomentAs(oldEntry.addedAt) || e == oldEntry);
    
    _sections[newEntry.section]!.insert(
      index >= 0 ? index.clamp(0, _sections[newEntry.section]!.length) : _sections[newEntry.section]!.length,
      newEntry,
    );
  }

  void remove(MealSection section, MealEntry entry) =>
      _sections[section]!.remove(entry);

  double get totalCaloriesMin => _all.fold(0, (s, e) => s + e.result.calories.min);
  double get totalCaloriesMax => _all.fold(0, (s, e) => s + e.result.calories.max);
  double get totalProteinMin  => _all.fold(0, (s, e) => s + e.result.protein.min);
  double get totalProteinMax  => _all.fold(0, (s, e) => s + e.result.protein.max);

  double get totalCaloriesMid => (totalCaloriesMin + totalCaloriesMax) / 2;
  double get totalProteinMid  => (totalProteinMin  + totalProteinMax)  / 2;

  // Secondary & optional macro aggregation
  double get totalCarbsMin => _all.fold(0, (s, e) => s + (e.result.carbohydrates?.min ?? 0));
  double get totalCarbsMax => _all.fold(0, (s, e) => s + (e.result.carbohydrates?.max ?? 0));
  double get totalCarbsMid => (totalCarbsMin + totalCarbsMax) / 2;

  double get totalFatMin => _all.fold(0, (s, e) => s + (e.result.fat?.min ?? 0));
  double get totalFatMax => _all.fold(0, (s, e) => s + (e.result.fat?.max ?? 0));
  double get totalFatMid => (totalFatMin + totalFatMax) / 2;

  double get totalFiberMin => _all.fold(0, (s, e) => s + (e.result.fiber?.min ?? 0));
  double get totalFiberMax => _all.fold(0, (s, e) => s + (e.result.fiber?.max ?? 0));
  double get totalFiberMid => (totalFiberMin + totalFiberMax) / 2;

  double get totalSugarMin => _all.fold(0, (s, e) => s + (e.result.sugar?.min ?? 0));
  double get totalSugarMax => _all.fold(0, (s, e) => s + (e.result.sugar?.max ?? 0));
  double get totalSugarMid => (totalSugarMin + totalSugarMax) / 2;

  double get totalSaturatedFatMin => _all.fold(0, (s, e) => s + (e.result.saturatedFat?.min ?? 0));
  double get totalSaturatedFatMax => _all.fold(0, (s, e) => s + (e.result.saturatedFat?.max ?? 0));
  double get totalSaturatedFatMid => (totalSaturatedFatMin + totalSaturatedFatMax) / 2;

  double get totalSodiumMin => _all.fold(0, (s, e) => s + (e.result.sodium?.min ?? 0));
  double get totalSodiumMax => _all.fold(0, (s, e) => s + (e.result.sodium?.max ?? 0));
  double get totalSodiumMid => (totalSodiumMin + totalSodiumMax) / 2;

  int? get dailyNutritionScore {
    final entriesWithScore = _all.where((e) => e.result.mealQualityScore != null).toList();
    if (entriesWithScore.isEmpty) return null;

    double weightedSum = 0;
    double totalCaloriesWithScore = 0;

    for (final e in entriesWithScore) {
      final score = e.result.mealQualityScore!;
      final cals = e.calMid;
      weightedSum += score * cals;
      totalCaloriesWithScore += cals;
    }

    if (totalCaloriesWithScore > 0) {
      return (weightedSum / totalCaloriesWithScore).round().clamp(0, 100);
    }

    final sumScores = entriesWithScore.fold<double>(0.0, (s, e) => s + e.result.mealQualityScore!);
    return (sumScores / entriesWithScore.length).round().clamp(0, 100);
  }

  List<String> getDailyNutritionInsights(double targetCal, double targetPro, double targetFib) {
    final insights = <String>[];
    if (isEmpty) return ['No meals logged today yet. Log some meals to get insights.'];

    final calMidVal = totalCaloriesMid;
    final proMidVal = totalProteinMid;
    final fibMidVal = totalFiberMid;

    final calPct = targetCal > 0 ? (calMidVal / targetCal * 100) : 0.0;
    final proPct = targetPro > 0 ? (proMidVal / targetPro * 100) : 0.0;
    final fibPct = targetFib > 0 ? (fibMidVal / targetFib * 100) : 0.0;

    // Calorie insight
    if (calPct > 105) {
      insights.add('Calories slightly above target (${calPct.toStringAsFixed(0)}%). Consider lighter snacks.');
    } else if (calPct >= 90) {
      insights.add('Excellent calorie control today!');
    } else if (calPct < 70) {
      insights.add('Calories are low (${calPct.toStringAsFixed(0)}%). Ensure you fuel properly.');
    }

    // Protein insight
    if (proPct >= 90) {
      insights.add('Fantastic job on protein! You hit ${proPct.toStringAsFixed(0)}% of your target.');
    } else if (proPct < 70) {
      insights.add('Protein is low (${proPct.toStringAsFixed(0)}%). Add lean protein sources.');
    }

    // Fiber insight
    if (fibPct >= 90) {
      insights.add('Superb fiber intake! You reached ${fibPct.toStringAsFixed(0)}% of your target.');
    } else if (fibPct < 60) {
      insights.add('Fiber is low (${fibPct.toStringAsFixed(0)}%). Boost with oats, fruit, or veggies.');
    }

    // Quality score insight
    final dailyScore = dailyNutritionScore;
    if (dailyScore != null) {
      if (dailyScore >= 80) {
        insights.add('Great food quality ($dailyScore/100)! You are nourishing your body with high-grade fuel.');
      } else if (dailyScore < 60) {
        insights.add('Food quality score is moderate ($dailyScore/100). Focus on more whole foods.');
      }
    }

    return insights;
  }

  List<MealEntry> get _all =>
      _sections.values.expand((e) => e).toList();

  bool get isEmpty => _all.isEmpty;

  // ── JSON serialization ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    if (gymDay != null) 'gymDay': gymDay!.toJson(),
    if (carryForwardAdjustment != null) 'carryForwardAdjustment': carryForwardAdjustment,
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
    if (j['carryForwardAdjustment'] != null) {
      log.carryForwardAdjustment = (j['carryForwardAdjustment'] as num).toDouble();
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
