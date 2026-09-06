import 'workout_split.dart';

/// Rich exercise definition from the master 1,300+ exercise library.
/// Provides rich anatomical metadata, step-by-step instructions, equipment grouping,
/// search aliases, and seamless conversion to Kynetix [Exercise] models.
class ExerciseDefinition {
  final String id;
  final String name;
  final String category; // Chest, Back, Shoulders, Arms, Legs, Core, Cardio, Other
  final String bodyPart; // Chest, Back, Shoulders, Upper Arms, Lower Arms, Waist, Upper Legs, Lower Legs, Cardio, Neck
  final String equipment; // Barbell, Dumbbell, Cable, Machine, Bodyweight, Band, Kettlebell, etc.
  final String equipmentGroup; // High-level group: Barbell, Dumbbell, Cable, Machine, Bodyweight, Band, Kettlebell, Accessories
  final String targetMuscle; // Primary agonist (e.g. Chest, Lats, Shoulders, Biceps, Quads, Hamstrings)
  final String muscleGroup;
  final List<String> secondaryMuscles; // Synergists & stabilizers
  final List<String> instructions; // Step-by-step execution cues
  final List<String> aliases; // Multi-token search aliases
  final ExerciseType exerciseType; // Kynetix progression engine type
  final String? imageRef; // Asset/remote image filename
  final String? gifRef; // Asset/remote demonstration filename
  final int defaultTargetSets;
  final int defaultRepMin;
  final int defaultRepMax;

  final String? notes; // Optional persistent standing notes (e.g. seat height, pin position)

  const ExerciseDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.bodyPart,
    required this.equipment,
    required this.equipmentGroup,
    required this.targetMuscle,
    required this.muscleGroup,
    this.secondaryMuscles = const [],
    this.instructions = const [],
    this.aliases = const [],
    this.exerciseType = ExerciseType.isolation,
    this.imageRef,
    this.gifRef,
    this.notes,
    this.defaultTargetSets = 3,
    this.defaultRepMin = 8,
    this.defaultRepMax = 12,
  });

  /// Seamlessly convert to Kynetix [Exercise] instance for active workouts and splits.
  Exercise toExercise({String? customNotes}) {
    return Exercise(
      id: id,
      name: name,
      muscleGroup: targetMuscle.isNotEmpty ? targetMuscle : category,
      type: exerciseType,
      defaultRepMin: defaultRepMin,
      defaultRepMax: defaultRepMax,
      defaultTargetSets: defaultTargetSets,
      notes: customNotes,
    );
  }

  factory ExerciseDefinition.fromExercise(Exercise ex) {
    return ExerciseDefinition(
      id: ex.id,
      name: ex.name,
      category: _inferCategory(ex.muscleGroup),
      bodyPart: ex.muscleGroup,
      equipment: _inferEquipment(ex.type),
      equipmentGroup: _inferEquipmentGroup(ex.type),
      targetMuscle: ex.muscleGroup,
      muscleGroup: ex.muscleGroup,
      secondaryMuscles: const [],
      instructions: const [],
      aliases: [ex.name.toLowerCase(), ex.muscleGroup.toLowerCase()],
      exerciseType: ex.type,
      defaultTargetSets: ex.targetSets,
      defaultRepMin: ex.targetRepMin,
      defaultRepMax: ex.targetRepMax,
      notes: ex.notes,
    );
  }

  factory ExerciseDefinition.fromJson(Map<String, dynamic> json) {
    final typeIdx = (json['exerciseType'] as num?)?.toInt() ?? 3;
    final exType = ExerciseType.values[typeIdx.clamp(0, ExerciseType.values.length - 1)];

    return ExerciseDefinition(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'Other',
      bodyPart: json['bodyPart'] as String? ?? '',
      equipment: json['equipment'] as String? ?? 'Bodyweight',
      equipmentGroup: json['equipmentGroup'] as String? ?? 'Bodyweight',
      targetMuscle: json['targetMuscle'] as String? ?? '',
      muscleGroup: json['muscleGroup'] as String? ?? '',
      secondaryMuscles: (json['secondaryMuscles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      instructions: (json['instructions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      aliases: (json['aliases'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      exerciseType: exType,
      imageRef: json['imageRef'] as String?,
      gifRef: json['gifRef'] as String?,
      defaultTargetSets: (json['defaultTargetSets'] as num?)?.toInt() ?? 3,
      defaultRepMin: (json['defaultRepMin'] as num?)?.toInt() ?? 8,
      defaultRepMax: (json['defaultRepMax'] as num?)?.toInt() ?? 12,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'bodyPart': bodyPart,
        'equipment': equipment,
        'equipmentGroup': equipmentGroup,
        'targetMuscle': targetMuscle,
        'muscleGroup': muscleGroup,
        'secondaryMuscles': secondaryMuscles,
        'instructions': instructions,
        'aliases': aliases,
        'exerciseType': exerciseType.index,
        if (imageRef != null) 'imageRef': imageRef,
        if (gifRef != null) 'gifRef': gifRef,
        'defaultTargetSets': defaultTargetSets,
        'defaultRepMin': defaultRepMin,
        'defaultRepMax': defaultRepMax,
      };

  static String _inferCategory(String muscle) {
    final m = muscle.toLowerCase();
    if (m.contains('chest') || m.contains('pec')) return 'Chest';
    if (m.contains('back') || m.contains('lat') || m.contains('trap')) return 'Back';
    if (m.contains('shoulder') || m.contains('delt')) return 'Shoulders';
    if (m.contains('bicep') || m.contains('tricep') || m.contains('arm') || m.contains('forearm')) return 'Arms';
    if (m.contains('leg') || m.contains('quad') || m.contains('ham') || m.contains('glute') || m.contains('calf')) return 'Legs';
    if (m.contains('core') || m.contains('abs') || m.contains('waist')) return 'Core';
    if (m.contains('cardio')) return 'Cardio';
    return 'Other';
  }

  static String _inferEquipment(ExerciseType type) {
    return switch (type) {
      ExerciseType.barbellCompound => 'Barbell',
      ExerciseType.dumbbell => 'Dumbbell',
      ExerciseType.cableMachine => 'Cable',
      ExerciseType.isolation => 'Machine',
      ExerciseType.bodyweight => 'Bodyweight',
    };
  }

  static String _inferEquipmentGroup(ExerciseType type) {
    return switch (type) {
      ExerciseType.barbellCompound => 'Barbell',
      ExerciseType.dumbbell => 'Dumbbell',
      ExerciseType.cableMachine => 'Cable',
      ExerciseType.isolation => 'Machine',
      ExerciseType.bodyweight => 'Bodyweight',
    };
  }
}
