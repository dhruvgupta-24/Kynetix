import '../models/workout_split.dart';

// ─── Exercise classification ─────────────────────────────────────────────────
//
// One source of truth for "what kind of exercise is this?". Three answers:
//   • the equipment it is loaded with (barbell, cable, machine, bodyweight…)
//   • whether it is a compound or an isolation movement
//   • the ExerciseType that drives progression (increments, rep ranges)
//
// It works from the name alone (saved splits, old sessions, custom moves),
// and is more precise when the library's equipment string is known, either
// passed in or registered by ExerciseLibraryService once the library loads.
//
// The bundled library's `exerciseType` values are generated from these same
// rules, and a test keeps the two in step.

/// What an exercise is loaded with. Order is not persisted.
enum EquipmentKind {
  bodyweight,
  barbell,
  ezBar,
  trapBar,
  smithMachine,
  dumbbell,
  kettlebell,
  cable,
  machine,

  /// Saved as "cable or machine" with nothing in the name to tell which.
  cableOrMachine,
  cardioMachine,
  band,
  plate,
  medicineBall,
  conditioning,
  unknown,
}

class ExerciseClassification {
  final EquipmentKind equipment;
  final bool isCompound;

  /// A bodyweight movement with load added (belt, vest, plate, dumbbell).
  final bool isWeighted;

  /// Assisted by a machine counterweight, a band or a partner.
  final bool isAssisted;

  const ExerciseClassification({
    required this.equipment,
    required this.isCompound,
    this.isWeighted = false,
    this.isAssisted = false,
  });

  bool get isBodyweight => equipment == EquipmentKind.bodyweight;

  /// The progression type. Equipment decides the increment; compound vs
  /// isolation decides whether a bar lift progresses by load or reps first.
  ExerciseType get type => switch (equipment) {
        EquipmentKind.bodyweight => ExerciseType.bodyweight,
        EquipmentKind.barbell ||
        EquipmentKind.ezBar ||
        EquipmentKind.trapBar ||
        EquipmentKind.smithMachine =>
          isCompound ? ExerciseType.barbellCompound : ExerciseType.isolation,
        EquipmentKind.dumbbell || EquipmentKind.kettlebell => ExerciseType.dumbbell,
        EquipmentKind.cable ||
        EquipmentKind.machine ||
        EquipmentKind.cableOrMachine ||
        EquipmentKind.cardioMachine =>
          ExerciseType.cableMachine,
        EquipmentKind.band ||
        EquipmentKind.plate ||
        EquipmentKind.medicineBall ||
        EquipmentKind.conditioning ||
        EquipmentKind.unknown =>
          ExerciseType.isolation,
      };

  /// Logging mode for a bodyweight movement, null for everything else.
  ExerciseExecutionMode? get bodyweightMode {
    if (!isBodyweight) return null;
    return isWeighted
        ? ExerciseExecutionMode.weightedBodyweight
        : ExerciseExecutionMode.bodyweightReps;
  }

  String get _shape => isCompound ? 'compound' : 'isolation';

  /// Short, honest, sentence case label for the UI.
  String get label => switch (equipment) {
        EquipmentKind.bodyweight => isWeighted
            ? 'Bodyweight, weighted'
            : isAssisted
                ? 'Bodyweight, assisted'
                : 'Bodyweight',
        EquipmentKind.barbell => 'Barbell, $_shape',
        EquipmentKind.ezBar => 'EZ bar, $_shape',
        EquipmentKind.trapBar => 'Trap bar, $_shape',
        EquipmentKind.smithMachine => 'Smith machine',
        EquipmentKind.dumbbell => 'Dumbbell, $_shape',
        EquipmentKind.kettlebell => 'Kettlebell',
        EquipmentKind.cable => 'Cable',
        EquipmentKind.machine => isAssisted ? 'Machine, assisted' : 'Machine',
        EquipmentKind.cableOrMachine => 'Cable or machine',
        EquipmentKind.cardioMachine => 'Cardio machine',
        EquipmentKind.band => 'Band',
        EquipmentKind.plate => 'Weight plate',
        EquipmentKind.medicineBall => 'Medicine ball',
        EquipmentKind.conditioning => 'Conditioning',
        EquipmentKind.unknown => isCompound ? 'Compound' : 'Isolation',
      };

  /// Library-style equipment string, for exercises built outside the library.
  String get equipmentName => switch (equipment) {
        EquipmentKind.bodyweight => isWeighted ? 'Weighted' : 'Bodyweight',
        EquipmentKind.barbell => 'Barbell',
        EquipmentKind.ezBar => 'EZ Barbell',
        EquipmentKind.trapBar => 'Trap Bar',
        EquipmentKind.smithMachine => 'Smith Machine',
        EquipmentKind.dumbbell => 'Dumbbell',
        EquipmentKind.kettlebell => 'Kettlebell',
        EquipmentKind.cable || EquipmentKind.cableOrMachine => 'Cable',
        EquipmentKind.machine || EquipmentKind.cardioMachine => 'Machine',
        EquipmentKind.band => 'Band',
        EquipmentKind.plate => 'Weighted',
        EquipmentKind.medicineBall => 'Medicine Ball',
        EquipmentKind.conditioning || EquipmentKind.unknown => 'Other',
      };

  /// The picker's filter group (Barbell, Dumbbell, Cable, Machine,
  /// Bodyweight, Band, Kettlebell, Accessories).
  String get equipmentGroup => switch (equipment) {
        EquipmentKind.bodyweight => 'Bodyweight',
        EquipmentKind.barbell || EquipmentKind.ezBar || EquipmentKind.trapBar => 'Barbell',
        EquipmentKind.dumbbell => 'Dumbbell',
        EquipmentKind.kettlebell => 'Kettlebell',
        EquipmentKind.cable || EquipmentKind.cableOrMachine => 'Cable',
        EquipmentKind.smithMachine ||
        EquipmentKind.machine ||
        EquipmentKind.cardioMachine =>
          'Machine',
        EquipmentKind.band => 'Band',
        EquipmentKind.plate ||
        EquipmentKind.medicineBall ||
        EquipmentKind.conditioning ||
        EquipmentKind.unknown =>
          'Accessories',
      };

  @override
  String toString() => 'ExerciseClassification($label, $type)';
}

class ExerciseClassifier {
  ExerciseClassifier._();

  // Library equipment by exercise id, filled by ExerciseLibraryService.
  static final Map<String, String> _libraryEquipment = {};

  /// Called once the bundled library is parsed.
  static void registerLibraryEquipment(Map<String, String> equipmentById) {
    _libraryEquipment
      ..clear()
      ..addAll(equipmentById);
  }

  // The built-in templates, so they classify the same before the library
  // has loaded (saved splits are parsed at sign-in, often earlier).
  static const Map<String, String> _builtInEquipment = {
    'bench_press': 'Barbell',
    'flat_bench_press': 'Barbell',
    'incline_bench_press': 'Barbell',
    'close_grip_bench': 'Barbell',
    'ohp': 'Barbell',
    'bb_row': 'Barbell',
    'bb_curl': 'Barbell',
    'rdl': 'Barbell',
    'deadlift': 'Barbell',
    'squat': 'Barbell',
    'skullcrusher': 'EZ Barbell',
    'incline_db_press': 'Dumbbell',
    'incline_db_curl': 'Dumbbell',
    'hammer_curl': 'Dumbbell',
    'db_shoulder_press': 'Dumbbell',
    'lateral_raise': 'Dumbbell',
    'shrugs': 'Dumbbell',
    'arnold_press': 'Dumbbell',
    'db_row': 'Dumbbell',
    'cable_chest_fly': 'Cable',
    'tri_pushdown': 'Cable',
    'rod_tricep_pushdown': 'Cable',
    'overhead_tri_ext': 'Cable',
    'lat_pulldown': 'Cable',
    'seated_cable_row': 'Cable',
    'close_grip_cable_row': 'Cable',
    'wide_grip_seated_row': 'Cable',
    'cable_pullover': 'Cable',
    'cable_lateral_raise': 'Cable',
    'face_pull': 'Cable',
    'cable_curl': 'Cable',
    'pec_dec': 'Leverage Machine',
    'tbar_row': 'Leverage Machine',
    'rear_delt_fly': 'Leverage Machine',
    'leg_extension': 'Leverage Machine',
    'leg_curl': 'Leverage Machine',
    'adductor_machine': 'Leverage Machine',
    'calf_raise': 'Leverage Machine',
    'standing_calf': 'Leverage Machine',
    'machine_preacher_curl': 'Leverage Machine',
    'machine_shoulder_press': 'Leverage Machine',
    'leg_press': 'Sled Machine',
    'hack_squat': 'Sled Machine',
    'pullups': 'Body Weight',
    'dips': 'Body Weight',
    'chest_dip': 'Body Weight',
  };

  /// Classifies a saved or in-memory [Exercise]. Its stored type is only a
  /// hint, used when nothing else says what the exercise is.
  static ExerciseClassification forExercise(Exercise e) => classify(
        id: e.id,
        name: e.name,
        muscle: e.muscleGroup,
        storedType: e.type,
      );

  /// [equipment] is the library's equipment string when known. [storedType]
  /// is whatever type was saved with the exercise, null when it was missing.
  static ExerciseClassification classify({
    String id = '',
    required String name,
    String? equipment,
    String? muscle,
    ExerciseType? storedType,
  }) {
    final n = _normalize(name);
    final compound = _isCompound(n, muscle);
    final libEq = (equipment != null && equipment.trim().isNotEmpty)
        ? equipment
        : (_libraryEquipment[id] ?? _builtInEquipment[id]);

    if (libEq != null) {
      final fromLib = _fromLibraryEquipment(libEq.toLowerCase().trim(), n, compound);
      if (fromLib != null) return fromLib;
    }
    return _fromName(n, compound, storedType);
  }

  /// Label for a bare progression type (the custom exercise type picker).
  static String typeLabel(ExerciseType type) => switch (type) {
        ExerciseType.barbellCompound => 'Barbell, compound',
        ExerciseType.dumbbell => 'Dumbbell or kettlebell',
        ExerciseType.cableMachine => 'Cable or machine',
        ExerciseType.isolation => 'Isolation',
        ExerciseType.bodyweight => 'Bodyweight',
      };

  // ── Rules ────────────────────────────────────────────────────────────────

  static String _normalize(String s) => ' ${s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';

  static bool _has(String n, RegExp re) => re.hasMatch(n);

  // Movements where the body is the load. Strong enough to override a
  // saved type (old data saved Pull-ups as a barbell lift).
  static final _bodyweightMove = RegExp(
    r'\b(pull ?ups?|chin ?ups?|chins|dips?|push ?ups?|press ?ups?|muscle ?ups?|'
    r'inverted rows?|australian pull ?ups?|planks?|sit ?ups?|burpees?|handstands?|'
    r'l sits?|pistol squats?|nordic|mountain climbers?|jumping jacks?|hanging|dead hangs?|'
    r'crunch(es)?|v ups?|hollow|superman|dead bugs?|bird dogs?|flutter kicks?|bear crawls?|'
    r'wall sits?|toes to bar|knee raises?|leg raises?|otis ups?|air squats?|jump squats?|'
    r'squat jumps?|box jumps?|pike|inchworms?|skin the cat|front lever|back lever|'
    r'human flag|dragon flags?|bodyweight squats?)\b',
  );

  // Push-up style moves where a dumbbell, ball or bell is a prop, not load.
  static final _propMove = RegExp(r'\b(push ?ups?|press ?ups?|pike)\b');

  // The kit is the load in its own right (a fly from a side plank).
  static final _kitMove =
      RegExp(r'\b(fly|flys|flyes|flies|raises?|rows?|curls?|extensions?|kickbacks?)\b');

  // Usually bodyweight, but a saved type may say otherwise.
  static final _likelyBodyweight = RegExp(
    r'\b(lunges?|step ?ups?|glute bridges?|bridges?|hyperextensions?|back extensions?|'
    r'reverse hypers?|running|run|jog|jogging|sprints?|skaters?|calisthenics)\b',
  );

  static final _assistedPullOrDip = RegExp(r'\b(pull ?ups?|chin ?ups?|dips?|muscle ?ups?)\b');

  // A plate or weight held in the hands rather than worn.
  static final _heldWeightMove = RegExp(
    r'\b(front raises?|lateral raises?|curls?|svend|round arm|squeeze|swings?|roller|rollerer)\b',
  );

  static final _isolationMove = RegExp(
    r'\b(curls?|extensions?|raises?|fly|flys|flyes|flies|kickbacks?|push ?downs?|'
    r'shrugs?|calf|calves|wrists?|crunch(es)?|pec dec|pec deck|crossovers?|pullovers?|'
    r'pull overs?|skull ?crushers?|lying triceps? press|triceps? press|face pulls?|adduct\w*|abduct\w*|'
    r'twists?|side bends?|stretch\w*|holds?|planks?|rotations?|wood ?chops?|pallof|'
    r'roll ?outs?|rollerouts?|sit ?ups?|v ups?|hollow|dead bugs?|bird dogs?|superman|'
    r'flutter|squeeze|tibialis|svend|round arm|jm press|tate press|dead hangs?|'
    r'wall sits?|l sits?|straight arm|toes to bar|french press|skull press|femoral)\b',
  );

  static final _compoundMove = RegExp(
    r'\b(press|presses|bench|squats?|deadlifts?|rdl|rows?|pull ?ups?|chin ?ups?|chins|'
    r'pull ?downs?|dips?|lunges?|step ?ups?|cleans?|snatch\w*|jerks?|thrusts?|thrusters?|'
    r'good ?mornings?|push ?ups?|press ?ups?|muscle ?ups?|swings?|burpees?|carry|carries|'
    r'farmers?|rack pulls?|get ?ups?|climbs?|climbers?|sled|tire flip|slams?|throws?|'
    r'pass|bridges?|pistol|jumps?|sprints?|bear crawls?|man makers?|inchworms?|'
    r'hyperextensions?|reverse hypers?)\b',
  );

  static const _isolationMuscles = {
    'biceps', 'triceps', 'forearms', 'calves', 'abs', 'core', 'obliques', 'neck',
    'waist', 'shoulders', 'rear delts', 'traps', 'adductors', 'abductors',
  };

  static bool _isCompound(String n, String? muscle) {
    if (_has(n, _isolationMove)) return false;
    if (_has(n, _compoundMove)) return true;
    final m = (muscle ?? '').toLowerCase().trim();
    if (m.isEmpty || _isolationMuscles.contains(m)) return false;
    return const {
      'chest', 'back', 'lats', 'upper back', 'lower back', 'quads', 'glutes',
      'hamstrings', 'legs', 'full body',
    }.contains(m);
  }

  static ExerciseClassification _bw(String n, {bool weighted = false}) =>
      ExerciseClassification(
        equipment: EquipmentKind.bodyweight,
        isCompound: _isCompound(n, null),
        isWeighted: weighted,
        isAssisted: !weighted && n.contains(' assisted '),
      );

  static ExerciseClassification _kind(EquipmentKind k, bool compound,
          {bool assisted = false}) =>
      ExerciseClassification(equipment: k, isCompound: compound, isAssisted: assisted);

  /// A free weight or band used with a bodyweight move: a prop for push-ups,
  /// help when it says assisted, otherwise added load (bands never count as
  /// load, a banded crunch stays a band exercise).
  static ExerciseClassification? _bodyweightWithKit(String n, {bool canLoad = true}) {
    if (!_has(n, _bodyweightMove)) return null;
    if (n.contains(' assisted ')) return _bw(n);
    if (_has(n, _propMove)) return _bw(n);
    if (!canLoad || _has(n, _kitMove)) return null;
    return _bw(n, weighted: true);
  }

  static ExerciseClassification? _fromLibraryEquipment(String eq, String n, bool compound) {
    switch (eq) {
      case 'body weight':
      case 'bodyweight':
      case 'assisted':
      case 'stability ball':
      case 'bosu ball':
      case 'roller':
      case 'wheel roller':
        return _bw(n);
      case 'rope':
        if (n.contains(' battling ') || n.contains(' battle ') || n.contains(' jump rope ')) {
          return _kind(EquipmentKind.conditioning, compound);
        }
        return _bw(n);
      case 'weighted':
        if (_has(n, _heldWeightMove)) return _kind(EquipmentKind.plate, compound);
        return _bw(n, weighted: true);
      case 'barbell':
      case 'olympic barbell':
        return _kind(EquipmentKind.barbell, compound);
      case 'ez barbell':
      case 'ez bar':
        return _kind(EquipmentKind.ezBar, compound);
      case 'trap bar':
        return _kind(EquipmentKind.trapBar, compound);
      case 'smith machine':
        return _kind(EquipmentKind.smithMachine, compound);
      case 'dumbbell':
        return _bodyweightWithKit(n) ?? _kind(EquipmentKind.dumbbell, compound);
      case 'kettlebell':
        return _bodyweightWithKit(n) ?? _kind(EquipmentKind.kettlebell, compound);
      case 'medicine ball':
        return _bodyweightWithKit(n) ?? _kind(EquipmentKind.medicineBall, compound);
      case 'band':
      case 'resistance band':
        return _bodyweightWithKit(n, canLoad: false) ?? _kind(EquipmentKind.band, compound);
      case 'cable':
        return _kind(EquipmentKind.cable, compound);
      case 'leverage machine':
      case 'sled machine':
      case 'machine':
        if (_has(n, _cardioMachineName)) return _kind(EquipmentKind.cardioMachine, true);
        return _kind(EquipmentKind.machine, compound, assisted: n.contains(' assisted '));
      case 'elliptical machine':
      case 'skierg machine':
      case 'stationary bike':
      case 'stepmill machine':
      case 'upper body ergometer':
        return _kind(EquipmentKind.cardioMachine, true);
      case 'hammer':
      case 'tire':
        return _kind(EquipmentKind.conditioning, compound);
    }
    return null;
  }

  static final _cardioMachineName = RegExp(
    r'\b(treadmill|elliptical|stationary bike|exercise bike|spin bike|cycling|rower|'
    r'rowing machine|rowing|ski ?erg|stair ?master|stair climber|stepmill|cross trainer|ergometer)\b',
  );

  static final _impliedMachine = RegExp(
    r'\b(leg press|hack squats?|pec dec|pec deck|leg extensions?|leg curls?|hamstring curls?|'
    r'adductors?|abductors?|hip adduction|hip abduction|chest press|seated calf raises?|'
    r'calf press|t ?bar rows?|reverse pec)\b',
  );

  static final _impliedCable = RegExp(
    r'\b(lat pull ?downs?|pull ?downs?|push ?downs?|crossovers?|face pulls?|seated rows?|'
    r'cable rows?|wood ?chops?|pallof)\b',
  );

  static final _impliedBarbell = RegExp(
    r'\b(bench press|bench|squats?|deadlifts?|rdl|romanian deadlifts?|overhead press|ohp|'
    r'military press|bent over rows?|pendlay rows?|good ?mornings?|power cleans?|cleans?|'
    r'snatch\w*|jerks?|hip thrusts?|skull ?crushers?|rack pulls?|zercher|upright rows?)\b',
  );

  static final _impliedDumbbell = RegExp(
    r'\b(lateral raises?|side raises?|arnold|hammer curls?|concentration curls?|kickbacks?|'
    r'rear delt fly|rear delt flyes?|flyes?|flys|shrugs?)\b',
  );

  static final _smithName = RegExp(r'\bsmith\b');
  static final _trapBarName = RegExp(r'\b(trap|hex) ?bar\b');
  static final _ezBarName = RegExp(r'\bez ?(bar|barbell|curl)\b');
  static final _barbellName = RegExp(r'\b(barbell|bb|landmine|olympic bar)\b');
  static final _dumbbellName = RegExp(r'\b(dumbbells?|db|dbs)\b');
  static final _kettlebellName = RegExp(r'\b(kettlebells?|kb)\b');
  static final _cableName = RegExp(r'\bcables?\b');
  static final _bandName = RegExp(r'\b(resistance bands?|bands?|banded)\b');
  static final _machineName =
      RegExp(r'\b(machine|lever|leverage|sled|selectorized|plate loaded|hammer strength)\b');
  static final _medicineBallName = RegExp(r'\b(medicine|med|slam) ?balls?\b');
  static final _bodyweightName = RegExp(r'\b(body ?weight|bw)\b');
  static final _weightedName = RegExp(r'\b(weighted|vest|belt)\b');
  static final _plateName = RegExp(r'\bplates?\b');

  static ExerciseClassification _fromName(String n, bool compound, ExerciseType? storedType) {
    // 1. Equipment named outright.
    if (_has(n, _smithName)) return _kind(EquipmentKind.smithMachine, compound);
    if (_has(n, _trapBarName)) return _kind(EquipmentKind.trapBar, compound);
    if (_has(n, _ezBarName)) return _kind(EquipmentKind.ezBar, compound);
    if (_has(n, _barbellName)) return _kind(EquipmentKind.barbell, compound);
    if (_has(n, _dumbbellName)) {
      return _bodyweightWithKit(n) ?? _kind(EquipmentKind.dumbbell, compound);
    }
    if (_has(n, _kettlebellName)) {
      return _bodyweightWithKit(n) ?? _kind(EquipmentKind.kettlebell, compound);
    }
    if (_has(n, _cableName)) return _kind(EquipmentKind.cable, compound);
    if (_has(n, _bandName)) {
      return _bodyweightWithKit(n, canLoad: false) ?? _kind(EquipmentKind.band, compound);
    }
    if (_has(n, _cardioMachineName)) return _kind(EquipmentKind.cardioMachine, true);
    final assisted = n.contains(' assisted ');
    if (_has(n, _machineName)) {
      return _kind(EquipmentKind.machine, compound, assisted: assisted);
    }
    if (_has(n, _medicineBallName)) {
      return _bodyweightWithKit(n) ?? _kind(EquipmentKind.medicineBall, compound);
    }
    if (_has(n, _bodyweightName)) return _bw(n);

    // 2. Assisted pull-ups and dips without a band are the counterweight machine.
    if (assisted && _has(n, _assistedPullOrDip)) {
      return _kind(EquipmentKind.machine, true, assisted: true);
    }

    // 3. Weighted bodyweight and plain bodyweight movements.
    final weighted = _has(n, _weightedName);
    if (_has(n, _bodyweightMove)) return _bw(n, weighted: weighted);
    if (weighted && _has(n, _likelyBodyweight)) return _bw(n, weighted: true);
    if (_has(n, _plateName)) return _kind(EquipmentKind.plate, compound);

    // 4. Names that only come on one piece of kit.
    if (_has(n, _impliedMachine)) return _kind(EquipmentKind.machine, compound);
    if (_has(n, _impliedCable)) return _kind(EquipmentKind.cable, compound);

    // 5. What was saved, when the name does not say.
    switch (storedType) {
      case ExerciseType.bodyweight:
        return _bw(n);
      case ExerciseType.barbellCompound:
        return _kind(EquipmentKind.barbell, compound);
      case ExerciseType.dumbbell:
        return _kind(EquipmentKind.dumbbell, compound);
      case ExerciseType.cableMachine:
        return _kind(EquipmentKind.cableOrMachine, compound);
      case ExerciseType.isolation:
      case null:
        break;
    }

    // 6. Sensible defaults by movement.
    if (_has(n, _likelyBodyweight)) return _bw(n);
    if (_has(n, _impliedBarbell)) return _kind(EquipmentKind.barbell, compound);
    if (_has(n, _impliedDumbbell)) return _kind(EquipmentKind.dumbbell, compound);

    // Nothing to go on: never guess a heavy barbell lift.
    return _kind(EquipmentKind.unknown, storedType == ExerciseType.isolation ? false : compound);
  }
}
