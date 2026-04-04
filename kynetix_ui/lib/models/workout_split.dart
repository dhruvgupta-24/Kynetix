import 'dart:convert';

// ─── ExerciseType ─────────────────────────────────────────────────────────────
//
// Used to drive progression logic:
//   barbellCompound → +2.5 kg increments when earned
//   dumbbell        → +2 kg increments (nearest DB increment)
//   cableMachine    → +5 kg stack increments
//   isolation       → reps-first before weight jump
//
// This matters: don't suggest the same progression for a deadlift and a
// cable lateral raise. The type drives coaching, not just labelling.

enum ExerciseType {
  barbellCompound, // index 0
  dumbbell, // index 1
  cableMachine, // index 2
  isolation, // index 3
  bodyweight, // index 4 — rep-first progression
}

// ─── Exercise ─────────────────────────────────────────────────────────────────

class Exercise {
  final String id;
  final String name;
  final String muscleGroup;
  final ExerciseType type;
  final int? defaultRepMin;
  final int? defaultRepMax;
  final String? notes;

  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.type,
    this.defaultRepMin,
    this.defaultRepMax,
    this.notes,
  });

  int get targetRepMin =>
      defaultRepMin ??
      switch (type) {
        ExerciseType.barbellCompound => 5,
        ExerciseType.dumbbell => 8,
        ExerciseType.cableMachine => 10,
        ExerciseType.isolation => 10,
        ExerciseType.bodyweight => 8,
      };

  int get targetRepMax =>
      defaultRepMax ??
      switch (type) {
        ExerciseType.barbellCompound => 8,
        ExerciseType.dumbbell => 12,
        ExerciseType.cableMachine => 15,
        ExerciseType.isolation => 15,
        ExerciseType.bodyweight => 15,
      };

  String get repRangeLabel => '$targetRepMin–$targetRepMax reps';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'muscleGroup': muscleGroup,
    'type': type.index,
    if (defaultRepMin != null) 'defaultRepMin': defaultRepMin,
    if (defaultRepMax != null) 'defaultRepMax': defaultRepMax,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
  };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    muscleGroup: j['muscleGroup'] as String? ?? '',
    type:
        ExerciseType.values[(j['type'] as int?)?.clamp(
              0,
              ExerciseType.values.length - 1,
            ) ??
            0],
    defaultRepMin: (j['defaultRepMin'] as num?)?.toInt(),
    defaultRepMax: (j['defaultRepMax'] as num?)?.toInt(),
    notes: j['notes'] as String?,
  );

  @override
  bool operator ==(Object other) => other is Exercise && other.id == id;
  @override
  int get hashCode => id.hashCode;

  Exercise copyWith({
    String? name,
    String? muscleGroup,
    ExerciseType? type,
    int? defaultRepMin,
    int? defaultRepMax,
    String? notes,
  }) => Exercise(
    id: id,
    name: name ?? this.name,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    type: type ?? this.type,
    defaultRepMin: defaultRepMin ?? this.defaultRepMin,
    defaultRepMax: defaultRepMax ?? this.defaultRepMax,
    notes: notes ?? this.notes,
  );
}

// ─── SplitDay ─────────────────────────────────────────────────────────────────

class SplitDay {
  /// weekday matches DateTime.weekday: 1=Monday … 7=Sunday
  final int weekday;
  final String name;
  final List<Exercise> exercises;

  const SplitDay({
    required this.weekday,
    required this.name,
    required this.exercises,
  });

  bool get isRestDay => exercises.isEmpty;

  SplitDay copyWith({String? name, List<Exercise>? exercises}) => SplitDay(
    weekday: weekday,
    name: name ?? this.name,
    exercises: exercises ?? this.exercises,
  );

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'name': name,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  factory SplitDay.fromJson(Map<String, dynamic> j) => SplitDay(
    weekday: j['weekday'] as int? ?? 1,
    name: j['name'] as String? ?? '',
    exercises: (j['exercises'] as List<dynamic>? ?? [])
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// ─── WorkoutSplit ─────────────────────────────────────────────────────────────

class WorkoutSplit {
  final String id;
  final String name;
  final List<SplitDay> days;

  const WorkoutSplit({
    required this.id,
    required this.name,
    required this.days,
  });

  SplitDay? dayFor(int weekday) {
    for (final d in days) {
      if (d.weekday == weekday) return d;
    }
    return null;
  }

  WorkoutSplit copyWith({String? name, List<SplitDay>? days}) =>
      WorkoutSplit(id: id, name: name ?? this.name, days: days ?? this.days);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'days': days.map((d) => d.toJson()).toList(),
  };

  factory WorkoutSplit.fromJson(Map<String, dynamic> j) => WorkoutSplit(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? 'My Split',
    days: (j['days'] as List<dynamic>? ?? [])
        .map((d) => SplitDay.fromJson(d as Map<String, dynamic>))
        .toList(),
  );

  String encode() => jsonEncode(toJson());
}

// ─── Exercise library ─────────────────────────────────────────────────────────
//
// Curated defaults for each common split day.
// Reflects hypertrophy-oriented training — realistic for a natty lifter
// doing 6-day PPL+Legs style programming.
//
// Grouped by day type so the setup screen can look up by day name.

const Map<String, List<Exercise>> exerciseLibraryByDay = {
  'Chest + Triceps': [
    Exercise(
      id: 'bench_press',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'incline_db_press',
      name: 'Incline DB Press',
      muscleGroup: 'Chest',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'cable_chest_fly',
      name: 'Cable Chest Fly',
      muscleGroup: 'Chest',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'pec_dec',
      name: 'Pec Dec',
      muscleGroup: 'Chest',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'tri_pushdown',
      name: 'Tricep Pushdown',
      muscleGroup: 'Triceps',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'overhead_tri_ext',
      name: 'Overhead Tricep Extension',
      muscleGroup: 'Triceps',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'dips',
      name: 'Dips',
      muscleGroup: 'Triceps',
      type: ExerciseType.barbellCompound,
    ),
  ],
  'Back + Biceps': [
    Exercise(
      id: 'lat_pulldown',
      name: 'Lat Pulldown',
      muscleGroup: 'Back',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'seated_cable_row',
      name: 'Seated Cable Row',
      muscleGroup: 'Back',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'tbar_row',
      name: 'T-Bar Row',
      muscleGroup: 'Back',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'bb_row',
      name: 'Barbell Row',
      muscleGroup: 'Back',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'cable_pullover',
      name: 'Cable Pullover',
      muscleGroup: 'Lats',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'bb_curl',
      name: 'Barbell Curl',
      muscleGroup: 'Biceps',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'incline_db_curl',
      name: 'Incline DB Curl',
      muscleGroup: 'Biceps',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'hammer_curl',
      name: 'Hammer Curl',
      muscleGroup: 'Biceps',
      type: ExerciseType.dumbbell,
    ),
  ],
  'Shoulders': [
    Exercise(
      id: 'db_shoulder_press',
      name: 'DB Shoulder Press',
      muscleGroup: 'Shoulders',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'lateral_raise',
      name: 'Lateral Raise',
      muscleGroup: 'Shoulders',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'cable_lateral_raise',
      name: 'Cable Lateral Raise',
      muscleGroup: 'Shoulders',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'face_pull',
      name: 'Face Pull',
      muscleGroup: 'Rear Delts',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'rear_delt_fly',
      name: 'Rear Delt Fly',
      muscleGroup: 'Rear Delts',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'shrugs',
      name: 'Shrugs',
      muscleGroup: 'Traps',
      type: ExerciseType.dumbbell,
    ),
  ],
  'Legs': [
    Exercise(
      id: 'leg_extension',
      name: 'Leg Extension',
      muscleGroup: 'Quads',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'leg_press',
      name: 'Leg Press',
      muscleGroup: 'Quads',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'hack_squat',
      name: 'Hack Squat',
      muscleGroup: 'Quads',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'leg_curl',
      name: 'Leg Curl',
      muscleGroup: 'Hamstrings',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'rdl',
      name: 'Romanian Deadlift',
      muscleGroup: 'Hamstrings',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'adductor_machine',
      name: 'Adductor Machine',
      muscleGroup: 'Adductors',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'calf_raise',
      name: 'Seated Calf Raise',
      muscleGroup: 'Calves',
      type: ExerciseType.cableMachine,
    ),
  ],
  'Push': [
    Exercise(
      id: 'bench_press',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'ohp',
      name: 'Overhead Press',
      muscleGroup: 'Shoulders',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'incline_db_press',
      name: 'Incline DB Press',
      muscleGroup: 'Chest',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'cable_chest_fly',
      name: 'Cable Chest Fly',
      muscleGroup: 'Chest',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'lateral_raise',
      name: 'Lateral Raise',
      muscleGroup: 'Shoulders',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'tri_pushdown',
      name: 'Tricep Pushdown',
      muscleGroup: 'Triceps',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'overhead_tri_ext',
      name: 'Overhead Tricep Extension',
      muscleGroup: 'Triceps',
      type: ExerciseType.cableMachine,
    ),
  ],
  'Pull': [
    Exercise(
      id: 'pullups',
      name: 'Pull-ups',
      muscleGroup: 'Back',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'lat_pulldown',
      name: 'Lat Pulldown',
      muscleGroup: 'Back',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'seated_cable_row',
      name: 'Seated Cable Row',
      muscleGroup: 'Back',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'bb_row',
      name: 'Barbell Row',
      muscleGroup: 'Back',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'cable_pullover',
      name: 'Cable Pullover',
      muscleGroup: 'Lats',
      type: ExerciseType.cableMachine,
    ),
    Exercise(
      id: 'bb_curl',
      name: 'Barbell Curl',
      muscleGroup: 'Biceps',
      type: ExerciseType.barbellCompound,
    ),
    Exercise(
      id: 'hammer_curl',
      name: 'Hammer Curl',
      muscleGroup: 'Biceps',
      type: ExerciseType.dumbbell,
    ),
    Exercise(
      id: 'face_pull',
      name: 'Face Pull',
      muscleGroup: 'Rear Delts',
      type: ExerciseType.cableMachine,
    ),
  ],
};

// Full exercise library (union of all days) — used by the exercise picker.
final List<Exercise> fullExerciseLibrary = [
  ...exerciseLibraryByDay.values.expand((e) => e),
  // Extra exercises not in default days
  const Exercise(
    id: 'deadlift',
    name: 'Deadlift',
    muscleGroup: 'Back',
    type: ExerciseType.barbellCompound,
  ),
  const Exercise(
    id: 'squat',
    name: 'Squat',
    muscleGroup: 'Quads',
    type: ExerciseType.barbellCompound,
  ),
  const Exercise(
    id: 'cable_curl',
    name: 'Cable Curl',
    muscleGroup: 'Biceps',
    type: ExerciseType.cableMachine,
  ),
  const Exercise(
    id: 'skullcrusher',
    name: 'Skull Crusher',
    muscleGroup: 'Triceps',
    type: ExerciseType.barbellCompound,
  ),
  const Exercise(
    id: 'close_grip_bench',
    name: 'Close-Grip Bench',
    muscleGroup: 'Triceps',
    type: ExerciseType.barbellCompound,
  ),
  const Exercise(
    id: 'arnold_press',
    name: 'Arnold Press',
    muscleGroup: 'Shoulders',
    type: ExerciseType.dumbbell,
  ),
  const Exercise(
    id: 'db_row',
    name: 'DB Row',
    muscleGroup: 'Back',
    type: ExerciseType.dumbbell,
  ),
  const Exercise(
    id: 'chest_dip',
    name: 'Chest Dip',
    muscleGroup: 'Chest',
    type: ExerciseType.barbellCompound,
  ),
  const Exercise(
    id: 'standing_calf',
    name: 'Standing Calf Raise',
    muscleGroup: 'Calves',
    type: ExerciseType.cableMachine,
  ),
];

// Remove duplicate IDs from the full library.
List<Exercise> get deduplicatedLibrary {
  final seen = <String>{};
  return fullExerciseLibrary.where((e) => seen.add(e.id)).toList();
}

// ─── Default split (user's PPL + Legs programme) ─────────────────────────────

WorkoutSplit get defaultWorkoutSplit => WorkoutSplit(
  id: 'default_ppl_legs',
  name: 'PPL + Legs',
  days: [
    SplitDay(
      weekday: 1,
      name: 'Chest + Triceps',
      exercises: exerciseLibraryByDay['Chest + Triceps']!,
    ),
    SplitDay(
      weekday: 2,
      name: 'Back + Biceps',
      exercises: exerciseLibraryByDay['Back + Biceps']!,
    ),
    SplitDay(
      weekday: 3,
      name: 'Shoulders',
      exercises: exerciseLibraryByDay['Shoulders']!,
    ),
    SplitDay(
      weekday: 4,
      name: 'Legs',
      exercises: exerciseLibraryByDay['Legs']!,
    ),
    SplitDay(
      weekday: 5,
      name: 'Push',
      exercises: exerciseLibraryByDay['Push']!,
    ),
    SplitDay(
      weekday: 6,
      name: 'Pull',
      exercises: exerciseLibraryByDay['Pull']!,
    ),
    const SplitDay(weekday: 7, name: 'Rest Day', exercises: []),
  ],
);
