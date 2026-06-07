import 'dart:convert';

typedef Goal = String;
const kFatLoss       = 'Fat Loss / Cut';
const kMaintenance   = 'Maintenance';
const kLeanBulk      = 'Lean Bulk';
const kBulk          = 'Bulk / Gain';
const kRecomposition = 'Recomposition';

/// Describes how a user anchors portions in a mixed Indian meal.
enum PortionAnchor {
  /// Carb-first: eats a fixed amount of roti/rice, uses sabzi/dal as
  /// accompaniment. Dal/sabzi portion ≈ 2–3 tbsp per roti (condiment role).
  carbAnchored,

  /// Curry-first: eats until the dal/sabzi runs out, regardless of carb count.
  /// Dal/sabzi consumed as a full katori (~150 ml) per sitting.
  curryAnchored,

  /// Balanced: eats similar amounts of both simultaneously. Midpoint estimate.
  balanced;

  String toJson() => name;

  static PortionAnchor fromJson(String s) =>
      PortionAnchor.values.firstWhere(
        (e) => e.name == s,
        orElse: () => PortionAnchor.balanced,
      );

  /// Human-readable label for Profile settings display.
  String get displayLabel => switch (this) {
    carbAnchored  => 'Carb-anchored (roti/rice first)',
    curryAnchored => 'Curry-anchored (dal/sabzi first)',
    balanced      => 'Balanced',
  };

  /// Short AI context hint injected into Kyno system prompt.
  String get aiHint => switch (this) {
    carbAnchored  =>
      'User eats a fixed roti/rice amount and uses sabzi or dal as a condiment '
      '(~2–3 tbsp per roti). Do NOT assume a full katori of dal/sabzi unless '
      'the user explicitly mentions a large serving.',
    curryAnchored =>
      'User eats until the dal/sabzi runs out, treating it as the main dish. '
      'Assume a full serving (~150 ml katori) of dal/sabzi per meal.',
    balanced      =>
      'User eats balanced portions of carbs and sides. Use standard Indian '
      'hostel meal estimates for roti+dal/sabzi.',
  };
}

class TargetChangeRecord {
  final DateTime timestamp;
  final String sourceType; // "System Calculated" or "Custom Targets"
  final double? maintenanceCalories;
  final double? trainingDayCalories;
  final double? restDayCalories;
  final double? proteinTarget;
  final Map<String, dynamic>? previousValues;

  const TargetChangeRecord({
    required this.timestamp,
    required this.sourceType,
    this.maintenanceCalories,
    this.trainingDayCalories,
    this.restDayCalories,
    this.proteinTarget,
    this.previousValues,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'sourceType': sourceType,
    if (maintenanceCalories != null) 'maintenanceCalories': maintenanceCalories,
    if (trainingDayCalories != null) 'trainingDayCalories': trainingDayCalories,
    if (restDayCalories != null) 'restDayCalories': restDayCalories,
    if (proteinTarget != null) 'proteinTarget': proteinTarget,
    if (previousValues != null) 'previousValues': previousValues,
  };

  factory TargetChangeRecord.fromJson(Map<String, dynamic> json) => TargetChangeRecord(
    timestamp: DateTime.parse(json['timestamp'] as String),
    sourceType: json['sourceType'] as String,
    maintenanceCalories: (json['maintenanceCalories'] as num?)?.toDouble(),
    trainingDayCalories: (json['trainingDayCalories'] as num?)?.toDouble(),
    restDayCalories: (json['restDayCalories'] as num?)?.toDouble(),
    proteinTarget: (json['proteinTarget'] as num?)?.toDouble(),
    previousValues: json['previousValues'] as Map<String, dynamic>?,
  );
}

class UserProfile {
  final String   name;
  final int      age;
  final String   gender;
  final double   height;        // always stored as cm
  final double   weight;        // kg
  final int      workoutDaysMin;
  final int      workoutDaysMax;
  final Goal     goal;

  // ── Portion behaviour ────────────────────────────────
  final PortionAnchor? portionAnchor;

  // ── Health Connect fields ───────────────────────
  final int?      averageDailySteps;
  final bool      healthSyncEnabled;
  final DateTime? lastHealthSyncAt;

  // ── Custom nutrition target & Carry-Forward customization ──────────────────
  final bool useCustomTargets;
  final double? customMaintenanceCalories;
  final double? customTrainingDayCalories;
  final double? customRestDayCalories;
  final double? customProteinTarget;
  final List<TargetChangeRecord> targetChangeHistory;

  final bool carryForwardEnabled;
  final int carryForwardThreshold; // defaults to 100 kcal

  const UserProfile({
    required this.name,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    required this.workoutDaysMin,
    required this.workoutDaysMax,
    required this.goal,
    this.portionAnchor,
    this.averageDailySteps,
    this.healthSyncEnabled = false,
    this.lastHealthSyncAt,
    this.useCustomTargets = false,
    this.customMaintenanceCalories,
    this.customTrainingDayCalories,
    this.customRestDayCalories,
    this.customProteinTarget,
    this.targetChangeHistory = const [],
    this.carryForwardEnabled = false,
    this.carryForwardThreshold = 100,
  });

  UserProfile copyWithHealth({
    required int      averageDailySteps,
    required DateTime lastHealthSyncAt,
  }) => UserProfile(
    name:              name,
    age:               age,
    gender:            gender,
    height:            height,
    weight:            weight,
    workoutDaysMin:    workoutDaysMin,
    workoutDaysMax:    workoutDaysMax,
    goal:              goal,
    portionAnchor:     portionAnchor,
    averageDailySteps: averageDailySteps,
    healthSyncEnabled: true,
    lastHealthSyncAt:  lastHealthSyncAt,
    useCustomTargets:  useCustomTargets,
    customMaintenanceCalories: customMaintenanceCalories,
    customTrainingDayCalories: customTrainingDayCalories,
    customRestDayCalories: customRestDayCalories,
    customProteinTarget: customProteinTarget,
    targetChangeHistory: targetChangeHistory,
    carryForwardEnabled: carryForwardEnabled,
    carryForwardThreshold: carryForwardThreshold,
  );

  UserProfile copyWith({
    String? name,
    int? age,
    String? gender,
    double? height,
    double? weight,
    int? workoutDaysMin,
    int? workoutDaysMax,
    Goal? goal,
    PortionAnchor? portionAnchor,
    int? averageDailySteps,
    bool? healthSyncEnabled,
    DateTime? lastHealthSyncAt,
    bool? useCustomTargets,
    double? customMaintenanceCalories,
    double? customTrainingDayCalories,
    double? customRestDayCalories,
    double? customProteinTarget,
    List<TargetChangeRecord>? targetChangeHistory,
    bool? carryForwardEnabled,
    int? carryForwardThreshold,
  }) => UserProfile(
    name:              name ?? this.name,
    age:               age ?? this.age,
    gender:            gender ?? this.gender,
    height:            height ?? this.height,
    weight:            weight ?? this.weight,
    workoutDaysMin:    workoutDaysMin ?? this.workoutDaysMin,
    workoutDaysMax:    workoutDaysMax ?? this.workoutDaysMax,
    goal:              goal ?? this.goal,
    portionAnchor:     portionAnchor ?? this.portionAnchor,
    averageDailySteps: averageDailySteps ?? this.averageDailySteps,
    healthSyncEnabled: healthSyncEnabled ?? this.healthSyncEnabled,
    lastHealthSyncAt:  lastHealthSyncAt ?? this.lastHealthSyncAt,
    useCustomTargets:  useCustomTargets ?? this.useCustomTargets,
    customMaintenanceCalories: customMaintenanceCalories ?? this.customMaintenanceCalories,
    customTrainingDayCalories: customTrainingDayCalories ?? this.customTrainingDayCalories,
    customRestDayCalories: customRestDayCalories ?? this.customRestDayCalories,
    customProteinTarget: customProteinTarget ?? this.customProteinTarget,
    targetChangeHistory: targetChangeHistory ?? this.targetChangeHistory,
    carryForwardEnabled: carryForwardEnabled ?? this.carryForwardEnabled,
    carryForwardThreshold: carryForwardThreshold ?? this.carryForwardThreshold,
  );

  Map<String, dynamic> toJson() => {
    'name':              name,
    'age':               age,
    'gender':            gender,
    'height':            height,
    'weight':            weight,
    'workoutDaysMin':    workoutDaysMin,
    'workoutDaysMax':    workoutDaysMax,
    'goal':              goal,
    if (portionAnchor != null) 'portionAnchor': portionAnchor!.toJson(),
    if (averageDailySteps != null) 'averageDailySteps': averageDailySteps,
    'healthSyncEnabled': healthSyncEnabled,
    if (lastHealthSyncAt != null) 'lastHealthSyncAt': lastHealthSyncAt!.toIso8601String(),
    'useCustomTargets':  useCustomTargets,
    if (customMaintenanceCalories != null) 'customMaintenanceCalories': customMaintenanceCalories,
    if (customTrainingDayCalories != null) 'customTrainingDayCalories': customTrainingDayCalories,
    if (customRestDayCalories != null) 'customRestDayCalories': customRestDayCalories,
    if (customProteinTarget != null) 'customProteinTarget': customProteinTarget,
    'targetChangeHistory': targetChangeHistory.map((e) => e.toJson()).toList(),
    'carryForwardEnabled': carryForwardEnabled,
    'carryForwardThreshold': carryForwardThreshold,
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    double _d(dynamic v, double fallback) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }
    int _i(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }
    return UserProfile(
      name:              (j['name'] as String?) ?? '',
      age:               _i(j['age'], 25),
      gender:            (j['gender'] as String?) ?? 'Male',
      height:            _d(j['height'], 170.0),
      weight:            _d(j['weight'], 70.0),
      workoutDaysMin:    _i(j['workoutDaysMin'], 2),
      workoutDaysMax:    _i(j['workoutDaysMax'], 3),
      goal:              (j['goal'] as String?) ?? kMaintenance,
      portionAnchor:     j['portionAnchor'] != null
          ? PortionAnchor.fromJson(j['portionAnchor'].toString())
          : null,
      averageDailySteps: j['averageDailySteps'] != null ? _i(j['averageDailySteps'], 0) : null,
      healthSyncEnabled: j['healthSyncEnabled'] as bool? ?? false,
      lastHealthSyncAt:  DateTime.tryParse((j['lastHealthSyncAt'] as String?) ?? ''),
      useCustomTargets:  j['useCustomTargets'] as bool? ?? false,
      customMaintenanceCalories: j['customMaintenanceCalories'] != null ? _d(j['customMaintenanceCalories'], 0) : null,
      customTrainingDayCalories: j['customTrainingDayCalories'] != null ? _d(j['customTrainingDayCalories'], 0) : null,
      customRestDayCalories: j['customRestDayCalories'] != null ? _d(j['customRestDayCalories'], 0) : null,
      customProteinTarget: j['customProteinTarget'] != null ? _d(j['customProteinTarget'], 0) : null,
      targetChangeHistory: (j['targetChangeHistory'] as List<dynamic>?)
              ?.map((e) => TargetChangeRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      carryForwardEnabled: j['carryForwardEnabled'] as bool? ?? false,
      carryForwardThreshold: _i(j['carryForwardThreshold'], 100),
    );
  }

  double get bmi => weight / ((height / 100) * (height / 100));
}
