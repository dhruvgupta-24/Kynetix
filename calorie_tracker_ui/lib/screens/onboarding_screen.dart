import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard_screen.dart';
import '../services/persistence_service.dart';

// ─── User profile model ───────────────────────────────────────────────────────

typedef Goal = String;
const kFatLoss           = 'Fat Loss';
const kMaintenance       = 'Maintenance';
const kMuscleGain        = 'Muscle Gain';
const kBodyRecomposition = 'Body Recomposition';

class UserProfile {
  final String   name;
  final int      age;
  final String   gender;
  final double   height;        // always stored as cm
  final double   weight;        // kg
  final int      workoutDaysMin;
  final int      workoutDaysMax;
  final Goal     goal;

  // ── Health Connect fields (all nullable / defaulted) ───────────────────────
  final int?      averageDailySteps; // from Health Connect sync
  final bool      healthSyncEnabled;
  final DateTime? lastHealthSyncAt;

  const UserProfile({
    required this.name,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    required this.workoutDaysMin,
    required this.workoutDaysMax,
    required this.goal,
    this.averageDailySteps,
    this.healthSyncEnabled = false,
    this.lastHealthSyncAt,
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
    averageDailySteps: averageDailySteps,
    healthSyncEnabled: true,
    lastHealthSyncAt:  lastHealthSyncAt,
  );

  /// Returns a copy with any overridden fields.
  UserProfile copyWith({double? weight}) => UserProfile(
    name:              name,
    age:               age,
    gender:            gender,
    height:            height,
    weight:            weight ?? this.weight,
    workoutDaysMin:    workoutDaysMin,
    workoutDaysMax:    workoutDaysMax,
    goal:              goal,
    averageDailySteps: averageDailySteps,
    healthSyncEnabled: healthSyncEnabled,
    lastHealthSyncAt:  lastHealthSyncAt,
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
    if (averageDailySteps != null) 'averageDailySteps': averageDailySteps,
    'healthSyncEnabled': healthSyncEnabled,
    if (lastHealthSyncAt != null) 'lastHealthSyncAt': lastHealthSyncAt!.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name:              j['name']           as String,
    age:               j['age']            as int,
    gender:            j['gender']         as String,
    height:            (j['height']        as num).toDouble(),
    weight:            (j['weight']        as num).toDouble(),
    workoutDaysMin:    j['workoutDaysMin'] as int,
    workoutDaysMax:    j['workoutDaysMax'] as int,
    goal:              j['goal']           as String,
    averageDailySteps: j['averageDailySteps'] as int?,
    healthSyncEnabled: j['healthSyncEnabled'] as bool? ?? false,
    lastHealthSyncAt:  DateTime.tryParse(j['lastHealthSyncAt'] as String? ?? ''),
  );

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
  _GoalOption(kFatLoss,           'Calorie deficit (−500 kcal)',   Icons.trending_down_rounded),
  _GoalOption(kMaintenance,       'Stay at current weight',         Icons.balance_rounded),
  _GoalOption(kMuscleGain,        'Calorie surplus (+300 kcal)',    Icons.trending_up_rounded),
  _GoalOption(kBodyRecomposition, 'Slight deficit (−200 kcal)',     Icons.autorenew_rounded),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _totalSteps = 3;

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

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

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
      return double.parse(_heightCmCtrl.text.trim());
    }
    final ft = double.tryParse(_heightFtCtrl.text.trim()) ?? 0;
    final inch = double.tryParse(_heightInCtrl.text.trim()) ?? 0;
    return (ft * 12 + inch) * 2.54;
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
      age:            int.parse(_ageCtrl.text.trim()),
      gender:         _gender,
      height:         _resolvedHeightCm(),
      weight:         double.parse(_weightCtrl.text.trim()),
      workoutDaysMin: opt.daysMin,
      workoutDaysMax: opt.daysMax,
      goal:           _goal,
    );

    // Persist before navigating so a quick kill won't lose profile.
    await PersistenceService.saveProfile(currentUserProfile!);
    await PersistenceService.setOnboardingDone();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) =>
            const DashboardScreen(),
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
      backgroundColor: const Color(0xFF13131F),
      body: SafeArea(
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
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _Header({required this.currentStep, required this.totalSteps});

  static const _titles    = ['About You',        'Your Body',              'Your Goals'];
  static const _subtitles = [
    'Tell us a little about yourself',
    'Help us estimate your needs',
    'What do you want to achieve?',
  ];

  @override
  Widget build(BuildContext context) {
    final progress = (currentStep + 1) / totalSteps;

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
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (_, value, child) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value, minHeight: 5,
                backgroundColor: const Color(0xFF2E2E3E),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF52B788)),
              ),
            ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel('Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration:
                  const InputDecoration(hintText: 'e.g. Dhruv'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 22),
            _FieldLabel('Age'),
            const SizedBox(height: 8),
            TextFormField(
              controller: ageCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                  hintText: 'e.g. 20', suffixText: 'years'),
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
            TextFormField(
              controller: weightCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                  hintText: 'e.g. 65', suffixText: 'kg'),
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
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration:
          const InputDecoration(hintText: 'e.g. 170', suffixText: 'cm'),
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
          child: TextFormField(
            controller: ftCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration:
                const InputDecoration(hintText: 'e.g. 5', suffixText: 'ft'),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n < 3 || n > 8) return 'Invalid';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: inCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: const InputDecoration(
                hintText: 'e.g. 10', suffixText: 'in'),
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
