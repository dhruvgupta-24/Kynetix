import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard_screen.dart';
import 'app_shell.dart';
import '../config/app_theme.dart';
import '../services/persistence_service.dart';
import '../services/profile_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/nutrition_hydration_guard.dart';
import '../services/eating_pattern_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── User profile model ───────────────────────────────────────────────────────

typedef Goal = String;
const kFatLoss       = 'Fat Loss / Cut';
const kMaintenance   = 'Maintenance';
const kLeanBulk      = 'Lean Bulk';
const kBulk          = 'Bulk / Gain';
const kRecomposition = 'Recomposition';

// ─── Portion anchor model ───────────────────────────────────────────────────────

/// Describes how a user anchors portions in a mixed Indian meal.
/// Captured during onboarding Step 4 (optional; null = not specified).
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

  // ── Portion behaviour (onboarding Step 4) ────────────────────────────────
  /// How the user anchors portions in a mixed Indian meal.
  /// Null for users who completed onboarding before this field was added.
  /// Treated as [PortionAnchor.balanced] in estimation when null.
  final PortionAnchor? portionAnchor;

  // ── Health Connect fields (all nullable / defaulted) ───────────────────────
  final int?      averageDailySteps; // from Health Connect sync
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

  /// Returns a copy with health-sync fields updated.
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

  /// Returns a copy with any overridden fields.
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

  // ── JSON serialization ──────────────────────────────────────────────────────

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
    // Defensive numeric parsing: Supabase can return numeric columns as
    // String on some legacy rows, and optional fields may be absent entirely.
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

/// Global in-memory store — replace with SharedPreferences when ready.
UserProfile? currentUserProfile;

// ─── Workout frequency options ────────────────────────────────────────────────

class _WorkoutOption {
  final String label;
  final String subtitle;
  final int    daysMin;
  final int    daysMax;
  const _WorkoutOption(this.label, this.subtitle, this.daysMin, this.daysMax);
}

const _workoutOptions = [
  _WorkoutOption('0–1 days',  'Mostly sedentary',         0, 1),
  _WorkoutOption('2–3 days',  'Light activity',            2, 3),
  _WorkoutOption('4–5 days',  'Moderately active',         4, 5),
  _WorkoutOption('5–6 days',  'Very active',               5, 6),
  _WorkoutOption('6–7 days',  'Athlete / daily training',  6, 7),
];

// ─── Goal options ─────────────────────────────────────────────────────────────

class _GoalOption {
  final Goal     value;
  final String   subtitle;
  final IconData icon;
  const _GoalOption(this.value, this.subtitle, this.icon);
}

const _goalOptions = [
  _GoalOption(kFatLoss,       'Calorie deficit (−500 kcal)',  Icons.trending_down_rounded),
  _GoalOption(kMaintenance,   'Stay at current weight',       Icons.balance_rounded),
  _GoalOption(kLeanBulk,      'Slight surplus (+200 kcal)',   Icons.fitness_center_rounded),
  _GoalOption(kBulk,          'Larger surplus (+400 kcal)',   Icons.trending_up_rounded),
  _GoalOption(kRecomposition, 'Slight deficit (−200 kcal)',   Icons.autorenew_rounded),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _totalSteps = 5;

  final _pageController = PageController();
  int _currentStep = 0;

  // Step 1 — Personal
  final _nameCtrl = TextEditingController();
  final _ageCtrl  = TextEditingController();
  String _gender  = 'Male';

  // Step 2 — Body
  bool   _useCm       = true;
  final _heightCmCtrl  = TextEditingController();
  final _heightFtCtrl  = TextEditingController();
  final _heightInCtrl  = TextEditingController();
  final _weightCtrl    = TextEditingController();

  // Step 3 — Lifestyle
  int _workoutIdx = 1;   // default: 2–3 days
  String _goal    = kMaintenance;

  // Step 4 — Eating style (optional; null = not answered)
  PortionAnchor? _portionAnchor;

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  UserProfile _buildTemporaryProfile() {
    final opt = _workoutOptions[_workoutIdx];
    return UserProfile(
      name:           _nameCtrl.text.trim(),
      age:            int.tryParse(_ageCtrl.text.trim()) ?? 25,
      gender:         _gender,
      height:         _resolvedHeightCm(),
      weight:         double.tryParse(_weightCtrl.text.trim()) ?? 70.0,
      workoutDaysMin: opt.daysMin,
      workoutDaysMax: opt.daysMax,
      goal:           _goal,
      portionAnchor:  _portionAnchor,
    );
  }

  WeeklyTargetPlan _calculateTargets() {
    final tempProfile = _buildTemporaryProfile();
    return NutritionTargetEngine().weeklyPlan(tempProfile);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _heightCmCtrl.dispose();
    _heightFtCtrl.dispose();
    _heightInCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  // ── Height conversion ────────────────────────────────────────────────────────

  double _resolvedHeightCm() {
    if (_useCm) {
      // Defensive: return fallback if field is empty or non-numeric
      return double.tryParse(_heightCmCtrl.text.trim()) ?? 170.0;
    }
    final ft = double.tryParse(_heightFtCtrl.text.trim()) ?? 0;
    final inch = double.tryParse(_heightInCtrl.text.trim()) ?? 0;
    final cm = (ft * 12 + inch) * 2.54;
    return cm > 0 ? cm : 170.0;
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  void _nextStep() {
    final valid = switch (_currentStep) {
      0 => _step1Key.currentState?.validate() ?? false,
      1 => _step2Key.currentState?.validate() ?? false,
      _ => true,
    };
    if (!valid) return;

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _submit();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _submit() async {
    final opt = _workoutOptions[_workoutIdx];
    currentUserProfile = UserProfile(
      name:           _nameCtrl.text.trim(),
      age:            int.tryParse(_ageCtrl.text.trim()) ?? 25,
      gender:         _gender,
      height:         _resolvedHeightCm(),
      weight:         double.tryParse(_weightCtrl.text.trim()) ?? 70.0,
      workoutDaysMin: opt.daysMin,
      workoutDaysMax: opt.daysMax,
      goal:           _goal,
      portionAnchor:  _portionAnchor,   // null if user skipped Step 4
    );

    // Persist before navigating so a quick kill won't lose profile.
    await PersistenceService.saveProfile(currentUserProfile!);
    await PersistenceService.setOnboardingDone();

    // Mark hydration complete since this is a new onboarding flow with fresh/empty memory
    final userId = Supabase.instance.client.auth.currentUser?.id;
    NutritionHydrationGuard.instance.markComplete(userId);

    // Fire & forget cloud update
    ProfileService.instance.upsertProfile(currentUserProfile!);

    // Seed eating pattern scalars from the declared eating style so the
    // scalar system is active from day one, not after 3+ corrections.
    if (_portionAnchor != null) {
      EatingPatternService.instance.seedFromPortionAnchor(_portionAnchor!);
      EatingPatternService.instance.save().ignore();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) =>
            const AppShell(),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07070C),
      body: Stack(
        children: [
          // Background linear mesh gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F0F1A),
                    Color(0xFF07070C),
                    Color(0xFF0A1411),
                  ],
                ),
              ),
            ),
          ),
          // Glowing radial orbs
          Positioned(
            top: -150,
            left: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF52B788).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -200,
            right: -200,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF6B35).withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _Header(currentStep: _currentStep, totalSteps: _totalSteps),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentStep = i),
                    children: [
                      _StepPersonal(
                        formKey:  _step1Key,
                        nameCtrl: _nameCtrl,
                        ageCtrl:  _ageCtrl,
                        gender:   _gender,
                        onGender: (v) => setState(() => _gender = v),
                      ),
                      _StepBody(
                        formKey:       _step2Key,
                        useCm:         _useCm,
                        heightCmCtrl:  _heightCmCtrl,
                        heightFtCtrl:  _heightFtCtrl,
                        heightInCtrl:  _heightInCtrl,
                        weightCtrl:    _weightCtrl,
                        onToggleUnit:  () => setState(() => _useCm = !_useCm),
                      ),
                      _StepLifestyle(
                        workoutIdx:       _workoutIdx,
                        goal:             _goal,
                        onWorkout:        (i) => setState(() => _workoutIdx = i),
                        onGoal:           (v) => setState(() => _goal = v),
                      ),
                      _StepEatingStyle(
                        selected: _portionAnchor,
                        onSelect: (v) => setState(() => _portionAnchor = v),
                        onSkip: () {
                          setState(() => _portionAnchor = null);
                          _nextStep();
                        },
                      ),
                      _StepSummary(
                        plan: _calculateTargets(),
                      ),
                    ],
                  ),
                ),
                _Footer(
                  currentStep: _currentStep,
                  totalSteps:  _totalSteps,
                  onNext:      _nextStep,
                  onBack:      _prevStep,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _Header({required this.currentStep, required this.totalSteps});

  static const _titles    = ['About You',        'Your Body',              'Your Goals',             'Eating Style',           'Your Targets'];
  static const _subtitles = [
    'Tell us a little about yourself',
    'Help us estimate your needs',
    'What do you want to achieve?',
    'How do you eat roti or rice?',
    'Here are your daily target goals',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.restaurant_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Step ${currentStep + 1} of $totalSteps',
                style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Column(
              key: ValueKey(currentStep),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titles[currentStep],
                    style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800,
                      color: Colors.white, height: 1.15,
                    )),
                const SizedBox(height: 5),
                Text(_subtitles[currentStep],
                    style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(totalSteps, (i) {
              final active = currentStep == i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                margin: const EdgeInsets.only(right: 6),
                height: 5,
                width: active ? 24 : 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: active ? const Color(0xFF52B788) : const Color(0xFF2E2E3E),
                  boxShadow: active ? [
                    BoxShadow(
                      color: const Color(0xFF52B788).withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    )
                  ] : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _Footer({
    required this.currentStep,
    required this.totalSteps,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = currentStep == totalSteps - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Row(
        children: [
          if (currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9CA3AF),
                  side: const BorderSide(color: Color(0xFF2E2E3E)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Back',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          if (currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: onNext,
              child: Text(isLast ? 'Get Started' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 1 — Personal ────────────────────────────────────────────────────────

class _StepPersonal extends StatelessWidget {
  final GlobalKey<FormState>   formKey;
  final TextEditingController  nameCtrl;
  final TextEditingController  ageCtrl;
  final String                 gender;
  final ValueChanged<String>   onGender;

  const _StepPersonal({
    required this.formKey,
    required this.nameCtrl,
    required this.ageCtrl,
    required this.gender,
    required this.onGender,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel('Name'),
            const SizedBox(height: 8),
            OnboardingTextField(
              controller: nameCtrl,
              hint: 'e.g. Dhruv',
              capitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 22),
            _FieldLabel('Age'),
            const SizedBox(height: 8),
            OnboardingTextField(
              controller: ageCtrl,
              hint: 'e.g. 20',
              suffix: 'years',
              keyboardType: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 10 || n > 100) return 'Enter a valid age';
                return null;
              },
            ),
            const SizedBox(height: 22),
            _FieldLabel('Gender'),
            const SizedBox(height: 10),
            _GenderSelector(selected: gender, onChanged: onGender),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Step 2 — Body ────────────────────────────────────────────────────────────

class _StepBody extends StatelessWidget {
  final GlobalKey<FormState>   formKey;
  final bool                   useCm;
  final TextEditingController  heightCmCtrl;
  final TextEditingController  heightFtCtrl;
  final TextEditingController  heightInCtrl;
  final TextEditingController  weightCtrl;
  final VoidCallback           onToggleUnit;

  const _StepBody({
    required this.formKey,
    required this.useCm,
    required this.heightCmCtrl,
    required this.heightFtCtrl,
    required this.heightInCtrl,
    required this.weightCtrl,
    required this.onToggleUnit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Height ──────────────────────────────────────────
            Row(
              children: [
                const Expanded(child: _FieldLabel('Height')),
                _UnitToggle(useCm: useCm, onToggle: onToggleUnit),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: useCm
                  ? _CmHeightField(key: const ValueKey('cm'), ctrl: heightCmCtrl)
                  : _FtInHeightFields(
                      key: const ValueKey('ftin'),
                      ftCtrl: heightFtCtrl,
                      inCtrl: heightInCtrl,
                    ),
            ),
            const SizedBox(height: 22),
            // ── Weight ──────────────────────────────────────────
            _FieldLabel('Weight'),
            const SizedBox(height: 8),
            OnboardingTextField(
              controller: weightCtrl,
              hint: 'e.g. 65',
              suffix: 'kg',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n < 20 || n > 300) return 'Enter a valid weight';
                return null;
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _CmHeightField extends StatelessWidget {
  final TextEditingController ctrl;
  const _CmHeightField({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return OnboardingTextField(
      controller: ctrl,
      hint: 'e.g. 170',
      suffix: 'cm',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        final n = double.tryParse(v ?? '');
        if (n == null || n < 100 || n > 250) return 'Enter a valid height';
        return null;
      },
    );
  }
}

class _FtInHeightFields extends StatelessWidget {
  final TextEditingController ftCtrl;
  final TextEditingController inCtrl;
  const _FtInHeightFields(
      {super.key, required this.ftCtrl, required this.inCtrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OnboardingTextField(
            controller: ftCtrl,
            hint: 'e.g. 5',
            suffix: 'ft',
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n < 3 || n > 8) return 'Invalid';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OnboardingTextField(
            controller: inCtrl,
            hint: 'e.g. 10',
            suffix: 'in',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n < 0 || n >= 12) return 'Invalid';
              return null;
            },
          ),
        ),
      ],
    );
  }
}

// ─── OnboardingTextField — premium active border glows ─────────────────────────

class OnboardingTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? formatters;
  final String? Function(String?)? validator;
  final TextCapitalization capitalization;

  const OnboardingTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.suffix,
    this.keyboardType = TextInputType.text,
    this.formatters,
    this.validator,
    this.capitalization = TextCapitalization.none,
  });

  @override
  State<OnboardingTextField> createState() => _OnboardingTextFieldState();
}

class _OnboardingTextFieldState extends State<OnboardingTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: _focused ? KShadow.glow(const Color(0xFF52B788)) : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.formatters,
        validator: widget.validator,
        textCapitalization: widget.capitalization,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Color(0xFF4B5563), fontSize: 14),
          suffixText: widget.suffix,
          suffixStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          filled: true,
          fillColor: const Color(0xFF13131F),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2E2E3E), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2E2E3E), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF52B788), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          errorStyle: const TextStyle(color: Color(0xFFEF4444), fontSize: 11),
        ),
      ),
    );
  }
}

// ─── Step 3 — Lifestyle ───────────────────────────────────────────────────────

class _StepLifestyle extends StatelessWidget {
  final int                workoutIdx;
  final String             goal;
  final ValueChanged<int>  onWorkout;
  final ValueChanged<String> onGoal;

  const _StepLifestyle({
    required this.workoutIdx,
    required this.goal,
    required this.onWorkout,
    required this.onGoal,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel('Workout Frequency per Week'),
          const SizedBox(height: 10),
          ...List.generate(_workoutOptions.length, (i) {
            final opt = _workoutOptions[i];
            return _SelectTile(
              label:    opt.label,
              icon:     _workoutIcon(i),
              subtitle: opt.subtitle,
              selected: workoutIdx == i,
              onTap:    () => onWorkout(i),
            );
          }),
          const SizedBox(height: 20),
          _FieldLabel('Goal'),
          const SizedBox(height: 10),
          ..._goalOptions.map((opt) => _SelectTile(
                label:    opt.value,
                icon:     opt.icon,
                subtitle: opt.subtitle,
                selected: goal == opt.value,
                onTap:    () => onGoal(opt.value),
              )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  IconData _workoutIcon(int i) => switch (i) {
        0 => Icons.weekend_rounded,
        1 => Icons.directions_walk_rounded,
        2 => Icons.directions_bike_rounded,
        3 => Icons.fitness_center_rounded,
        _ => Icons.sports_martial_arts_rounded,
      };
}

// ─── Reusable sub-widgets ─────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: Color(0xFF6B7280), letterSpacing: 1.1,
      ),
    );
  }
}

// ── Unit toggle (CM / FT·IN) ─────────────────────────────────────────────────

class _UnitToggle extends StatelessWidget {
  final bool         useCm;
  final VoidCallback onToggle;
  const _UnitToggle({required this.useCm, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2E2E3E)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleSegment(label: 'CM',     active: useCm),
            _ToggleSegment(label: 'FT/IN',  active: !useCm),
          ],
        ),
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  final String label;
  final bool   active;
  const _ToggleSegment({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2D6A4F) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : const Color(0xFF6B7280),
        ),
      ),
    );
  }
}

// ── Gender selector ────────────────────────────────────────────────────────

class _GenderSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _GenderSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['Male', 'Female'].map((g) {
        final isSelected = selected == g;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(g),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: g == 'Male' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2D6A4F)
                    : const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF52B788)
                      : const Color(0xFF2E2E3E),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    g == 'Male' ? Icons.male_rounded : Icons.female_rounded,
                    size: 18,
                    color:
                        isSelected ? Colors.white : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 6),
                  Text(g,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF6B7280),
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 14,
                      )),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Select tile ───────────────────────────────────────────────────────────────

class _SelectTile extends StatelessWidget {
  final String    label;
  final IconData  icon;
  final String    subtitle;
  final bool      selected;
  final VoidCallback onTap;

  const _SelectTile({
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2D6A4F).withValues(alpha: 0.25)
              : const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF52B788)
                : const Color(0xFF2E2E3E),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF52B788).withValues(alpha: 0.18)
                    : const Color(0xFF2E2E3E),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon,
                  size: 18,
                  color: selected
                      ? const Color(0xFF52B788)
                      : const Color(0xFF6B7280)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF9CA3AF),
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280),
                      )),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: Color(0xFF52B788)),
          ],
        ),
      ),
    );
  }
}

// ─── Step 4: Eating Style (PortionAnchor) ────────────────────────────────────

class _StepEatingStyle extends StatelessWidget {
  final PortionAnchor? selected;
  final ValueChanged<PortionAnchor> onSelect;
  final VoidCallback onSkip;

  const _StepEatingStyle({
    required this.selected,
    required this.onSelect,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Eating Style',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'How do you usually eat a meal with roti or rice?',
            style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF), height: 1.4),
          ),
          const SizedBox(height: 28),

          _PortionOption(
            emoji: '🍽️',
            title: 'Roti/rice first',
            subtitle: 'I eat a set amount of roti or rice, then use sabzi\nor dal to finish it (carb-anchored)',
            value:    PortionAnchor.carbAnchored,
            selected: selected == PortionAnchor.carbAnchored,
            onTap:    onSelect,
          ),
          const SizedBox(height: 12),

          _PortionOption(
            emoji: '🥘',
            title: 'Curry/dal first',
            subtitle: 'I eat until the curry or dal runs out, then stop\n(curry-anchored)',
            value:    PortionAnchor.curryAnchored,
            selected: selected == PortionAnchor.curryAnchored,
            onTap:    onSelect,
          ),
          const SizedBox(height: 12),

          _PortionOption(
            emoji: '⚖️',
            title: 'Balanced',
            subtitle: 'I naturally eat similar amounts of both together',
            value:    PortionAnchor.balanced,
            selected: selected == PortionAnchor.balanced,
            onTap:    onSelect,
          ),
          const SizedBox(height: 28),

          // Skip link \u2014 does not affect existing data
          Center(
            child: GestureDetector(
              onTap: onSkip,
              child: const Text(
                'Skip this step',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF6B7280),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortionOption extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final PortionAnchor value;
  final bool selected;
  final ValueChanged<PortionAnchor> onTap;

  const _PortionOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF52B788).withValues(alpha: 0.12)
              : const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF52B788)
                : const Color(0xFF2D3048),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : const Color(0xFF9CA3AF),
                      )),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      )),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  size: 20, color: Color(0xFF52B788)),
          ],
        ),
      ),
    );
  }
}

// ─── Step 5: Summary targets screen with Count-Up animation ────────────────

class _StepSummary extends StatelessWidget {
  final WeeklyTargetPlan plan;

  const _StepSummary({required this.plan});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calibrating Complete',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Based on your body composition and goals, your primary targets are ready.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          
          // Calorie card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: KColor.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: KColor.border, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: KColor.calorie.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_fire_department_rounded, color: KColor.calorie, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DAILY TARGET CALORIES',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      KAnimatedCount(
                        value: plan.avgDailyCalories,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                        suffix: ' kcal',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Protein card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: KColor.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: KColor.border, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: KColor.protein.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.egg_outlined, color: KColor.protein, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DAILY PROTEIN TARGET',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      KAnimatedCount(
                        value: plan.avgDailyProtein,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                        suffix: ' g',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          // Detailed targets list
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF13131F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2E3E), width: 0.5),
            ),
            child: Column(
              children: [
                _TargetRow(
                  label: 'Training Day Target',
                  value: '${plan.trainingDayCalories.toStringAsFixed(0)} kcal',
                ),
                const Divider(color: Color(0xFF2E2E3E), height: 24),
                _TargetRow(
                  label: 'Rest Day Target',
                  value: '${plan.restDayCalories.toStringAsFixed(0)} kcal',
                ),
                const Divider(color: Color(0xFF2E2E3E), height: 24),
                _TargetRow(
                  label: 'Maintenance baseline',
                  value: '${plan.maintenanceCalories.toStringAsFixed(0)} kcal',
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _TargetRow({required this.label, required this.value, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
