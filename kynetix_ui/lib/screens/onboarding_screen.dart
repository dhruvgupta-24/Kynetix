import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_shell.dart';
import 'connect_chatgpt_screen.dart';
import 'onboarding/consent_panel.dart';
import 'onboarding/prologue.dart';
import 'onboarding/scene_backdrop.dart';
import 'onboarding/welcome_moment.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import '../services/persistence_service.dart';
import '../services/profile_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/nutrition_hydration_guard.dart';
import '../services/eating_pattern_service.dart';
import '../ui/k_rolling.dart';
import '../widgets/kyno_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

export '../models/user_profile.dart';

UserProfile? get currentUserProfile =>
    ProfileService.instance.currentUserProfile;
set currentUserProfile(UserProfile? p) =>
    ProfileService.instance.currentUserProfile = p;

// ─── Workout frequency options ────────────────────────────────────────────────

class _WorkoutOption {
  final String label;
  final String subtitle;
  final int daysMin;
  final int daysMax;
  const _WorkoutOption(this.label, this.subtitle, this.daysMin, this.daysMax);
}

const _workoutOptions = [
  _WorkoutOption('0 to 1 days', 'Mostly resting for now', 0, 1),
  _WorkoutOption('2 to 3 days', 'Easing into it', 2, 3),
  _WorkoutOption('4 to 5 days', 'A steady routine', 4, 5),
  _WorkoutOption('5 to 6 days', 'Training most days', 5, 6),
  _WorkoutOption('6 to 7 days', 'Basically every day', 6, 7),
];

// ─── Goal options ─────────────────────────────────────────────────────────────

class _GoalOption {
  final Goal value;
  final String subtitle;
  final IconData icon;
  const _GoalOption(this.value, this.subtitle, this.icon);
}

const _goalOptions = [
  _GoalOption(
    kFatLoss,
    'A steady deficit to lose fat',
    Icons.trending_down_rounded,
  ),
  _GoalOption(
    kMaintenance,
    'Hold your weight, keep training',
    Icons.balance_rounded,
  ),
  _GoalOption(
    kLeanBulk,
    'A small surplus, minimal fat gain',
    Icons.fitness_center_rounded,
  ),
  _GoalOption(
    kBulk,
    'A bigger surplus to gain size',
    Icons.trending_up_rounded,
  ),
  _GoalOption(
    kRecomposition,
    'Lose fat while building muscle',
    Icons.autorenew_rounded,
  ),
];

// ─── Chapters ─────────────────────────────────────────────────────────────────
// Five question chapters, then the optional "Bring your own AI" chapter. Each
// chapter has its own scene: gym photos for you and your training, food
// photos for how you eat and what you'll eat. Neighbouring chapters never
// share a frame, so every step reads as a new shot.

class _Chapter {
  const _Chapter(this.title, this.subtitle, this.scene, this.align, this.tone);
  final String title;
  final String subtitle;
  final String scene;
  final Alignment align;
  final KTone tone;
}

const _chapters = [
  _Chapter(
    'A bit about you',
    "Real food. Real lifts. Let's get you set up.",
    KScene.lifter,
    Alignment(0.3, -0.3),
    KTone.neutral,
  ),
  _Chapter(
    'Height and weight',
    'Helps us size your targets.',
    KScene.rack,
    Alignment(0, -0.2),
    KTone.neutral,
  ),
  _Chapter(
    'How do you train?',
    "Pick what's true most weeks.",
    KScene.lifter,
    Alignment(-0.6, 0.2),
    KTone.train,
  ),
  _Chapter(
    'How do you eat?',
    'Roti or rice with dal or sabzi. Which one leads?',
    KScene.roti,
    Alignment(0, -0.1),
    KTone.fuel,
  ),
  _Chapter(
    'Your targets',
    "Here's where you start.",
    KScene.thali,
    Alignment(0, 0.1),
    KTone.kyno,
  ),
  _Chapter(
    'Bring your own AI',
    'Optional. Use your own ChatGPT account for Kyno. You can do this later in Settings.',
    KScene.rack,
    Alignment(0.5, 0.3),
    KTone.kyno,
  ),
];

/// Index of the optional ChatGPT chapter (always the last one).
const _aiChapter = 5;

// ─── Screen ───────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.onFinished,
    this.onConsent,
    this.onSignOut,
    this.showPrologue = false,
  });

  /// Open with the three-beat story (plate, lift, Kyno) before the first
  /// question. AuthGate turns it on for brand-new accounts.
  final bool showPrologue;

  /// Called once the whole journey is done (profile saved, optional ChatGPT
  /// step finished or skipped, welcome moment played or skipped). AuthGate
  /// uses it to cross-fade into the app; without it the screen replaces
  /// itself with [AppShell].
  final VoidCallback? onFinished;

  /// When set, onboarding opens with the privacy step (short notice, "I agree
  /// to the Privacy Policy" and "I'm 18 or older", both required) before the
  /// first question chapter. Called on agreement to record consent; AuthGate
  /// passes it for users who haven't agreed to the current policy yet. The
  /// step isn't counted in "Step x of 6".
  final Future<void> Function({required bool ageConfirmedAdult})? onConsent;

  /// Sign-out for the privacy step's "I don't agree" state. Defaults to
  /// [AuthService.signOut].
  final Future<void> Function()? onSignOut;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  /// Question chapters (the profile is saved after the last one).
  static const _questionSteps = 5;

  /// All chapters, including the optional ChatGPT one.
  static const _totalSteps = 6;

  int _currentStep = 0;

  /// Direction of the last step change (drives the shared-axis direction).
  bool _forward = true;

  /// Profile save in flight (the "Save my targets" button shows its loader).
  bool _saving = false;

  /// The ChatGPT chapter reported done or skipped; guards double callbacks.
  bool _aiDone = false;

  /// Showing the closing "You're all set" moment.
  bool _welcome = false;

  /// The journey has handed off to the app; guards double callbacks.
  bool _finished = false;

  /// The privacy step is behind us (or was never needed).
  late bool _consentDone = widget.onConsent == null;

  /// The opening story has played (or was skipped / not asked for).
  late bool _prologueDone = !widget.showPrologue;

  /// What Kyno says on the current chapter. It reacts to answers that are
  /// taps (goal, training days, eating style); typed fields don't change it
  /// mid-word.
  (String, KynoMood) get _kyno {
    final first = _nameCtrl.text.trim().split(' ').first;
    final hi = first.isEmpty ? '' : ', $first';
    switch (_currentStep) {
      case 0:
        return (
          "I'm Kyno, your coach in here. Food and training, both. Start with your name.",
          KynoMood.happy,
        );
      case 1:
        return (
          'Good to meet you$hi. Height and weight size your targets. Only you see them.',
          KynoMood.listening,
        );
      case 2:
        final days = _workoutOptions[_workoutIdx].daysMax;
        final goalLine = switch (_goal) {
          kFatLoss =>
            'A cut. Protein stays high so the weight that goes is fat.',
          kLeanBulk => 'Lean bulk. A small surplus, so most of it is muscle.',
          kBulk => 'A proper bulk. We eat with a plan, not a free pass.',
          kRecomposition =>
            'Recomp. Slow and steady, and it needs consistent training.',
          _ => 'Maintenance. Same weight, better body. Good place to start.',
        };
        final mood = (_goal == kBulk || _goal == kLeanBulk)
            ? KynoMood.celebrate
            : (days <= 1 ? KynoMood.concerned : KynoMood.happy);
        return (goalLine, mood);
      case 3:
        return _portionAnchor == null
            ? (
                'Roti or rice? It changes what "one plate" means when you log.',
                KynoMood.thinking,
              )
            : (
                'Noted. I will read your plates that way from day one.',
                KynoMood.happy,
              );
      case 4:
        return (
          "Here's where you start$hi. I adjust it as I learn how you eat and train.",
          KynoMood.celebrate,
        );
      default:
        return (
          'Optional: bring your own ChatGPT and I run on it. Skip if you like.',
          KynoMood.talking,
        );
    }
  }

  /// Runs alongside the step transition so a second tap can't start another
  /// transition mid-flight (two copies of a step's Form would collide).
  late final AnimationController _navLock;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy initialiser would first run inside dispose()
    // when the user never changed step, which throws on a deactivated element.
    _navLock = AnimationController(vsync: this);
  }

  // Step 1 — Personal
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _gender = 'Male';

  // Step 2 — Body
  bool _useCm = true;
  final _heightCmCtrl = TextEditingController();
  final _heightFtCtrl = TextEditingController();
  final _heightInCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  // Step 3 — Lifestyle
  int _workoutIdx = 1; // default: 2–3 days
  String _goal = kMaintenance;

  // Step 4 — Eating style (optional; null = not answered)
  PortionAnchor? _portionAnchor;

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  UserProfile _buildTemporaryProfile() {
    final opt = _workoutOptions[_workoutIdx];
    return UserProfile(
      name: _nameCtrl.text.trim(),
      age: int.tryParse(_ageCtrl.text.trim()) ?? 25,
      gender: _gender,
      height: _resolvedHeightCm(),
      weight: double.tryParse(_weightCtrl.text.trim()) ?? 70.0,
      workoutDaysMin: opt.daysMin,
      workoutDaysMax: opt.daysMax,
      goal: _goal,
      portionAnchor: _portionAnchor,
    );
  }

  WeeklyTargetPlan _calculateTargets() {
    final tempProfile = _buildTemporaryProfile();
    return NutritionTargetEngine().weeklyPlan(tempProfile);
  }

  @override
  void dispose() {
    _navLock.dispose();
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

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    final d = KMotion.of(context, KMotion.emphasized);
    setState(() {
      _forward = step > _currentStep;
      _currentStep = step;
    });
    if (d > Duration.zero) {
      _navLock.duration = d;
      _navLock.forward(from: 0);
    }
  }

  void _nextStep() {
    if (_navLock.isAnimating || _saving) return;
    final valid = switch (_currentStep) {
      0 => _step1Key.currentState?.validate() ?? false,
      1 => _step2Key.currentState?.validate() ?? false,
      _ => true,
    };
    if (!valid) {
      KHaptics.reject();
      return;
    }

    if (_currentStep < _questionSteps - 1) {
      _goTo(_currentStep + 1);
      // The plan reveal is the payoff of the questions.
      if (_currentStep == _questionSteps - 1) KHaptics.success();
    } else if (_currentStep == _questionSteps - 1) {
      _submit();
    }
  }

  void _prevStep() {
    if (_navLock.isAnimating || _saving) return;
    // Once the profile is saved the questions are behind you.
    if (_currentStep > 0 && _currentStep < _questionSteps) {
      _goTo(_currentStep - 1);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    final opt = _workoutOptions[_workoutIdx];
    currentUserProfile = UserProfile(
      name: _nameCtrl.text.trim(),
      age: int.tryParse(_ageCtrl.text.trim()) ?? 25,
      gender: _gender,
      height: _resolvedHeightCm(),
      weight: double.tryParse(_weightCtrl.text.trim()) ?? 70.0,
      workoutDaysMin: opt.daysMin,
      workoutDaysMax: opt.daysMax,
      goal: _goal,
      portionAnchor: _portionAnchor, // null if user skipped Step 4
    );

    // Persist before moving on so a quick kill won't lose profile.
    // Local write; the cloud backup starts right away (see lastUpload).
    await ProfileService.instance.save(currentUserProfile!);
    await PersistenceService.setOnboardingDone();

    // Mark hydration complete since this is a new onboarding flow with fresh/empty memory
    final userId = Supabase.instance.client.auth.currentUser?.id;
    NutritionHydrationGuard.instance.markComplete(userId);

    // Fire & forget cloud update. Consent is written to the profile row once
    // that row exists (best effort; it stays recorded locally either way).
    ProfileService.instance.lastUpload.then((_) {
      if (userId != null) ConsentService.instance.syncToCloud(userId).ignore();
    }).ignore();

    // Seed eating pattern scalars from the declared eating style so the
    // scalar system is active from day one, not after 3+ corrections.
    if (_portionAnchor != null) {
      EatingPatternService.instance.seedFromPortionAnchor(_portionAnchor!);
      EatingPatternService.instance.save().ignore();
    }

    if (!mounted) return;
    setState(() => _saving = false);
    // Saved: on to the optional last chapter.
    _goTo(_aiChapter);
  }

  /// The ChatGPT chapter finished (connected or skipped): play the welcome.
  void _finishAiChapter() {
    if (_aiDone || !mounted) return;
    _aiDone = true;
    FocusScope.of(context).unfocus();
    setState(() => _welcome = true);
  }

  /// The welcome moment ended or was skipped: hand off to the app.
  void _enterApp() {
    if (_finished || !mounted) return;
    _finished = true;
    final onFinished = widget.onFinished;
    if (onFinished != null) {
      onFinished();
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement(kFadeThroughRoute(builder: (_) => const AppShell()));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  Widget _stepAt(int step, WeeklyTargetPlan plan) => switch (step) {
    0 => _StepPersonal(
      formKey: _step1Key,
      nameCtrl: _nameCtrl,
      ageCtrl: _ageCtrl,
      gender: _gender,
      onGender: (v) => setState(() => _gender = v),
    ),
    1 => _StepBody(
      formKey: _step2Key,
      useCm: _useCm,
      heightCmCtrl: _heightCmCtrl,
      heightFtCtrl: _heightFtCtrl,
      heightInCtrl: _heightInCtrl,
      weightCtrl: _weightCtrl,
      onToggleUnit: () => setState(() => _useCm = !_useCm),
    ),
    2 => _StepLifestyle(
      workoutIdx: _workoutIdx,
      goal: _goal,
      onWorkout: (i) => setState(() => _workoutIdx = i),
      onGoal: (v) => setState(() => _goal = v),
    ),
    3 => _StepEatingStyle(
      selected: _portionAnchor,
      onSelect: (v) => setState(() => _portionAnchor = v),
      onSkip: () {
        setState(() => _portionAnchor = null);
        _nextStep();
      },
    ),
    4 => _StepSummary(plan: plan),
    _ => _StepConnectAi(onFinished: _finishAiChapter),
  };

  Future<void> _agreeToPrivacy({required bool ageConfirmedAdult}) async {
    final record = widget.onConsent;
    if (record != null) await record(ageConfirmedAdult: ageConfirmedAdult);
    if (!mounted) return;
    setState(() => _consentDone = true);
  }

  Widget _buildConsentStep(double lead) {
    return Column(
      key: const ValueKey('onboarding-consent'),
      children: [
        SizedBox(height: lead),
        const _ConsentHeader(),
        Expanded(
          child: ConsentPanel(
            onAgree: _agreeToPrivacy,
            onSignOut: widget.onSignOut ?? () => const AuthService().signOut(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: KMotion.of(context, KMotion.emphasized),
      switchInCurve: KMotion.decelerate,
      switchOutCurve: KMotion.accelerate,
      child: _prologueDone
          ? KeyedSubtree(
              key: const ValueKey('onboarding-main'),
              child: _buildMain(context),
            )
          : OnboardingPrologue(
              key: const ValueKey('onboarding-prologue'),
              onDone: () => setState(() => _prologueDone = true),
            ),
    );
  }

  Widget _buildMain(BuildContext context) {
    final plan = _calculateTargets();
    final chapter = _chapters[_currentStep];
    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    // With the keyboard up the hero gives its room back to the field.
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
    final heroH = (size.height * 0.42).clamp(260.0, 420.0);
    final lead = compact ? 0.0 : heroH * 0.30;

    return KPage(
      tone: chapter.tone,
      intensity: 0.35,
      body: Stack(
        children: [
          // Moment: chapter change. The scene cross-fades (and settles) in
          // step with the shared-axis content below.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH + topInset,
            child: KSceneBackdrop(
              asset: chapter.scene,
              alignment: chapter.align,
            ),
          ),
          SafeArea(
            child: AnimatedSwitcher(
              duration: KMotion.of(context, KMotion.emphasized),
              switchInCurve: KMotion.decelerate,
              switchOutCurve: KMotion.accelerate,
              child: !_consentDone
                  ? _buildConsentStep(lead)
                  : Column(
                      key: const ValueKey('onboarding-chapters'),
                      children: [
                        AnimatedContainer(
                          duration: KMotion.of(context, KMotion.standard),
                          curve: KMotion.emphasizedCurve,
                          height: lead,
                        ),
                        _Header(
                          currentStep: _currentStep,
                          totalSteps: _totalSteps,
                          forward: _forward,
                          compact: compact,
                          kynoLine: _kyno.$1,
                          kynoMood: _kyno.$2,
                        ),
                        Expanded(
                          // Moment: step change. Shared-axis X — forward pushes left,
                          // back pulls right. Reduced motion: instant swap.
                          child: PageTransitionSwitcher(
                            duration: KMotion.of(context, KMotion.emphasized),
                            reverse: !_forward,
                            // Steps are top-aligned (the default centres short steps).
                            layoutBuilder: (entries) => Stack(
                              alignment: Alignment.topCenter,
                              children: entries,
                            ),
                            transitionBuilder: (child, primary, secondary) =>
                                SharedAxisTransition(
                                  animation: primary,
                                  secondaryAnimation: secondary,
                                  transitionType:
                                      SharedAxisTransitionType.horizontal,
                                  fillColor: Colors.transparent,
                                  child: child,
                                ),
                            child: KeyedSubtree(
                              key: ValueKey<int>(_currentStep),
                              child: _stepAt(_currentStep, plan),
                            ),
                          ),
                        ),
                        _Footer(
                          currentStep: _currentStep,
                          saving: _saving,
                          onNext: _nextStep,
                          onBack: _prevStep,
                        ),
                      ],
                    ),
            ),
          ),
          if (_welcome)
            Positioned.fill(
              child: WelcomeMoment(name: _nameCtrl.text, onDone: _enterApp),
            ),
        ],
      ),
    );
  }
}

// ─── Privacy step (before chapter 1) ──────────────────────────────────────────
// Shown only when AuthGate asks for consent. Same header rhythm as a chapter,
// without the progress bar (it isn't one of the six chapters).

class _ConsentHeader extends StatelessWidget {
  const _ConsentHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.xxl,
        KSpacing.lg,
        KSpacing.xxl,
        KSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before we start',
            style: KText.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: KColor.textSecondary,
            ),
          ),
          const SizedBox(height: KSpacing.sm),
          Semantics(
            header: true,
            child: Text('Your data, your call', style: KText.display),
          ),
          Padding(
            padding: const EdgeInsets.only(top: KSpacing.xs),
            child: Text(
              'Here is what Kynetix keeps and why. Kynetix is for adults 18 and over.',
              style: KText.body.copyWith(
                color: KColor.textSecondary,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chapter progress ─────────────────────────────────────────────────────────
// One segment per chapter. Done and current segments fill with ink (the fill
// slides in on each step); the last, optional chapter's segment is shorter and
// its label says so, so progress never pretends it's mandatory.

class _ChapterProgress extends StatelessWidget {
  const _ChapterProgress({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final track = KColor.fg.withValues(alpha: KColor.isDark ? 0.16 : 0.12);
    final dur = KMotion.of(context, KMotion.emphasized);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: KSpacing.xs + 2),
          Expanded(
            flex: i == total - 1 ? 1 : 2,
            child: ClipRRect(
              borderRadius: KRadius.pill,
              child: SizedBox(
                height: 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: track),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: i <= current ? 1.0 : 0.0),
                      duration: dur,
                      curve: KMotion.emphasizedCurve,
                      builder: (context, v, _) => FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: v,
                        child: ColoredBox(color: KColor.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final bool forward;
  final bool compact;
  final String kynoLine;
  final KynoMood kynoMood;

  const _Header({
    required this.currentStep,
    required this.totalSteps,
    required this.forward,
    required this.compact,
    required this.kynoLine,
    required this.kynoMood,
  });

  @override
  Widget build(BuildContext context) {
    final dir = forward ? 1.0 : -1.0;
    final chapter = _chapters[currentStep];
    final isLast = currentStep == totalSteps - 1;
    final stepLabel = isLast
        ? 'Last step, optional'
        : 'Step ${currentStep + 1} of $totalSteps';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.xxl,
        KSpacing.lg,
        KSpacing.xxl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            label: stepLabel,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    stepLabel,
                    key: ValueKey(stepLabel),
                    style: KText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: KColor.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: KSpacing.sm),
                _ChapterProgress(current: currentStep, total: totalSteps),
              ],
            ),
          ),
          SizedBox(height: compact ? KSpacing.md : KSpacing.lg),
          AnimatedSwitcher(
            duration: KMotion.of(context, KMotion.standard),
            switchInCurve: KMotion.decelerate,
            switchOutCurve: KMotion.accelerate,
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.topStart,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey(currentStep);
              final offset = Tween<Offset>(
                begin: Offset((incoming ? 0.08 : -0.08) * dir, 0),
                end: Offset.zero,
              ).animate(anim);
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: Column(
              key: ValueKey(currentStep),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(chapter.title, style: KText.display),
                ),
                AnimatedSize(
                  duration: KMotion.of(context, KMotion.standard),
                  curve: KMotion.emphasizedCurve,
                  alignment: Alignment.topLeft,
                  child: compact
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: KSpacing.sm),
                          child: _KynoSays(line: kynoLine, mood: kynoMood),
                        ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? KSpacing.md : KSpacing.xl),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final int currentStep;
  final bool saving;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _Footer({
    required this.currentStep,
    required this.saving,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    // The optional ChatGPT chapter brings its own actions (connect, and
    // "Skip for now" in every resting state), so the footer steps aside.
    if (currentStep == _aiChapter)
      return const SizedBox(width: double.infinity);
    final isSave = currentStep == _OnboardingScreenState._questionSteps - 1;
    final child = Row(
      key: const ValueKey('footer-questions'),
      children: [
        if (currentStep > 0)
          Expanded(
            child: KButton(
              label: 'Back',
              outlined: true,
              onTap: saving ? null : onBack,
            ),
          ),
        if (currentStep > 0) const SizedBox(width: KSpacing.md),
        Expanded(
          flex: 2,
          child: KButton(
            label: isSave ? 'Save my targets' : 'Continue',
            icon: isSave ? Icons.check_rounded : null,
            loading: saving,
            onTap: onNext,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.xxl,
        KSpacing.md,
        KSpacing.xxl,
        KSpacing.lg,
      ),
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.standard),
        switchInCurve: KMotion.decelerate,
        switchOutCurve: KMotion.accelerate,
        child: child,
      ),
    );
  }
}

// ─── Chapter 6: Bring your own AI (optional) ─────────────────────────────────
// The ChatGPT connect flow, embedded. It reports back through onFinished on a
// successful connection or on its "Skip for now"; either way the welcome
// moment plays and the user lands on home.

class _StepConnectAi extends StatelessWidget {
  const _StepConnectAi({required this.onFinished});
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return ConnectChatGptScreen(embedded: true, onFinished: onFinished);
  }
}

// ─── Step 1 — Personal ────────────────────────────────────────────────────────

class _StepPersonal extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController ageCtrl;
  final String gender;
  final ValueChanged<String> onGender;

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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FieldLabel('Name'),
            const SizedBox(height: KSpacing.sm),
            OnboardingTextField(
              controller: nameCtrl,
              hint: 'e.g. Dhruv',
              capitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Add your name so we know what to call you.'
                  : null,
            ),
            const SizedBox(height: KSpacing.xl),
            const _FieldLabel('Age'),
            const SizedBox(height: KSpacing.sm),
            OnboardingTextField(
              controller: ageCtrl,
              hint: 'e.g. 20',
              suffix: 'years',
              keyboardType: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n > 100) return 'Enter an age from 18 to 100.';
                if (n < 18) return 'Kynetix is for adults 18 and over.';
                return null;
              },
            ),
            const SizedBox(height: KSpacing.xl),
            const _FieldLabel('Gender'),
            const SizedBox(height: KSpacing.sm),
            _GenderSelector(selected: gender, onChanged: onGender),
            const SizedBox(height: KSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}

// ─── Step 2 — Body ────────────────────────────────────────────────────────────

class _StepBody extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool useCm;
  final TextEditingController heightCmCtrl;
  final TextEditingController heightFtCtrl;
  final TextEditingController heightInCtrl;
  final TextEditingController weightCtrl;
  final VoidCallback onToggleUnit;

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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Height ──────────────────────────────────────────
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: KSpacing.sm,
              spacing: KSpacing.md,
              children: [
                const _FieldLabel('Height'),
                _UnitToggle(useCm: useCm, onToggle: onToggleUnit),
              ],
            ),
            const SizedBox(height: KSpacing.sm),
            AnimatedSwitcher(
              duration: KMotion.of(context, KMotion.standard),
              switchInCurve: KMotion.decelerate,
              switchOutCurve: KMotion.accelerate,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: useCm
                  ? _CmHeightField(
                      key: const ValueKey('cm'),
                      ctrl: heightCmCtrl,
                    )
                  : _FtInHeightFields(
                      key: const ValueKey('ftin'),
                      ftCtrl: heightFtCtrl,
                      inCtrl: heightInCtrl,
                    ),
            ),
            const SizedBox(height: KSpacing.xl),
            // ── Weight ──────────────────────────────────────────
            const _FieldLabel('Weight'),
            const SizedBox(height: KSpacing.sm),
            OnboardingTextField(
              controller: weightCtrl,
              hint: 'e.g. 65',
              suffix: 'kg',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n < 20 || n > 300)
                  return 'Enter a weight from 20 to 300 kg.';
                return null;
              },
            ),
            const SizedBox(height: KSpacing.md),
            Text(
              'Only used to size your calorie and protein targets.',
              style: KText.caption.copyWith(color: KColor.textMuted),
            ),
            const SizedBox(height: KSpacing.xxxl),
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
        if (n == null || n < 100 || n > 250)
          return 'Enter a height from 100 to 250 cm.';
        return null;
      },
    );
  }
}

class _FtInHeightFields extends StatelessWidget {
  final TextEditingController ftCtrl;
  final TextEditingController inCtrl;
  const _FtInHeightFields({
    super.key,
    required this.ftCtrl,
    required this.inCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: OnboardingTextField(
            controller: ftCtrl,
            hint: 'e.g. 5',
            suffix: 'ft',
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n < 3 || n > 8) return '3 to 8 ft';
              return null;
            },
          ),
        ),
        const SizedBox(width: KSpacing.md),
        Expanded(
          child: OnboardingTextField(
            controller: inCtrl,
            hint: 'e.g. 10',
            suffix: 'in',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n < 0 || n >= 12) return '0 to 11 in';
              return null;
            },
          ),
        ),
      ],
    );
  }
}

// ─── OnboardingTextField — focus-glow input ───────────────────────────────────
// Numeric inputs get the tabular display face so every number in onboarding
// reads like the measurements they are.

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
      if (!mounted || _focusNode.hasFocus == _focused) return;
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _numeric => widget.keyboardType.index == TextInputType.number.index;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: KRadius.md,
      borderSide: BorderSide(color: c, width: w),
    );
    final inputStyle = _numeric
        ? KText.numMedium.copyWith(fontSize: 20)
        : KText.bodyMedium.copyWith(fontSize: 16);
    final dark = KColor.isDark;
    final rest = dark ? KColor.fg.withValues(alpha: 0.10) : KColor.border;
    final ring = KColor.fg.withValues(alpha: dark ? 0.10 : 0.07);
    return AnimatedContainer(
      duration: KMotion.of(context, KMotion.quick),
      curve: KMotion.emphasizedCurve,
      decoration: BoxDecoration(
        borderRadius: KRadius.md,
        boxShadow: [
          BoxShadow(
            color: _focused ? ring : ring.withValues(alpha: 0),
            blurRadius: 0,
            spreadRadius: 4,
          ),
        ],
      ),
      child: TextFormField(
        // Enter moves to the next field (Name → Age, Height → Weight).
        textInputAction: TextInputAction.next,
        controller: widget.controller,
        focusNode: _focusNode,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.formatters,
        validator: widget.validator,
        textCapitalization: widget.capitalization,
        style: inputStyle,
        cursorColor: KColor.ink,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: inputStyle.copyWith(color: KColor.textDisabled),
          suffixText: widget.suffix,
          suffixStyle: KText.bodyMedium.copyWith(
            color: KColor.textMuted,
            fontSize: 14,
          ),
          filled: true,
          fillColor: dark ? KColor.fg.withValues(alpha: 0.04) : KColor.card,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KSpacing.lg,
            vertical: 16,
          ),
          border: border(rest),
          enabledBorder: border(rest),
          focusedBorder: border(KColor.ink, 1.5),
          errorBorder: border(KColor.danger),
          focusedErrorBorder: border(KColor.danger, 1.5),
          errorStyle: KText.caption.copyWith(
            color: KColor.danger,
            fontSize: 12,
          ),
          errorMaxLines: 2,
        ),
      ),
    );
  }
}

// ─── Step 3 — Lifestyle ───────────────────────────────────────────────────────

class _StepLifestyle extends StatelessWidget {
  final int workoutIdx;
  final String goal;
  final ValueChanged<int> onWorkout;
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
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Training days per week'),
          const SizedBox(height: KSpacing.sm),
          ...List.generate(_workoutOptions.length, (i) {
            final opt = _workoutOptions[i];
            return _OptionCard(
              title: opt.label,
              subtitle: opt.subtitle,
              leading: Icon(_workoutIcon(i), size: 20),
              accent: KGradient.train,
              selected: workoutIdx == i,
              onTap: () => onWorkout(i),
            );
          }),
          const SizedBox(height: KSpacing.lg),
          const _FieldLabel('Your goal'),
          const SizedBox(height: KSpacing.sm),
          ..._goalOptions.map(
            (opt) => _OptionCard(
              title: opt.value,
              subtitle: opt.subtitle,
              leading: Icon(opt.icon, size: 20),
              accent: KGradient.primary,
              selected: goal == opt.value,
              onTap: () => onGoal(opt.value),
            ),
          ),
          const SizedBox(height: KSpacing.xxl),
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
      text,
      style: KText.caption.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: KColor.textSecondary,
      ),
    );
  }
}

// ── Unit toggle (CM / FT·IN) ─────────────────────────────────────────────────

class _UnitToggle extends StatelessWidget {
  final bool useCm;
  final VoidCallback onToggle;
  const _UnitToggle({required this.useCm, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Height unit',
      value: useCm ? 'Centimetres' : 'Feet and inches',
      hint: 'Switch unit',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          KHaptics.select();
          onToggle();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: KColor.isDark
                    ? KColor.fg.withValues(alpha: 0.05)
                    : KColor.card,
                borderRadius: KRadius.pill,
                border: Border.all(
                  color: KColor.isDark
                      ? KColor.fg.withValues(alpha: 0.08)
                      : KColor.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToggleSegment(label: 'cm', active: useCm),
                  _ToggleSegment(label: 'ft/in', active: !useCm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  final String label;
  final bool active;
  const _ToggleSegment({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: KMotion.of(context, KMotion.quick),
      curve: KMotion.emphasizedCurve,
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.md + 2,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: KGradient.primary,
              )
            : null,
        borderRadius: KRadius.pill,
      ),
      child: Text(
        label,
        style: KText.caption.copyWith(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? KColor.onInk : KColor.textMuted,
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
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: g == 'Male' ? KSpacing.md : 0,
            ),
            child: _OptionCard(
              title: g,
              leading: Icon(
                g == 'Male' ? Icons.male_rounded : Icons.female_rounded,
                size: 22,
              ),
              accent: KGradient.primary,
              selected: isSelected,
              vertical: true,
              onTap: () => onChanged(g),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Option card ───────────────────────────────────────────────────────────────
// A plain choice. Moment: select. Press squashes (Pressable) and the commit
// fires one selection haptic. Selected is ink, like every selected state in
// the app: a 1.5dp ink outline, full-strength type and a filled check, so it
// never depends on colour alone. No icon tiles, no gradients, no shadow.

class _OptionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget leading;
  final List<Color> accent;
  final bool selected;
  final bool vertical;
  final VoidCallback onTap;

  const _OptionCard({
    required this.title,
    this.subtitle,
    required this.leading,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final dur = KMotion.of(context, KMotion.standard);
    final dark = KColor.isDark;

    final check = AnimatedScale(
      duration: dur,
      curve: selected ? KMotion.overshoot : KMotion.accelerate,
      scale: selected ? 1 : 0.85,
      child: Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 22,
        color: selected ? KColor.ink : KColor.textDisabled,
      ),
    );

    final titleText = Text(
      title,
      textAlign: vertical ? TextAlign.center : TextAlign.start,
      style: KText.h3.copyWith(
        fontSize: vertical ? 17 : 16,
        color: selected ? KColor.textPrimary : KColor.textSecondary,
      ),
    );

    // Vertical options (gender) are type only: the word is the choice.
    final content = vertical
        ? Center(child: titleText)
        : Row(
            children: [
              IconTheme.merge(
                data: IconThemeData(
                  color: selected ? KColor.textPrimary : KColor.textMuted,
                ),
                child: SizedBox(width: 24, child: Center(child: leading)),
              ),
              const SizedBox(width: KSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleText,
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: KText.caption.copyWith(
                          color: KColor.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              check,
            ],
          );

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: vertical ? 0 : KSpacing.sm + 2),
        child: Pressable(
          scale: 0.98,
          borderRadius: KRadius.md,
          onTap: () {
            if (!selected) KHaptics.select();
            onTap();
          },
          child: AnimatedContainer(
            duration: dur,
            curve: KMotion.emphasizedCurve,
            constraints: BoxConstraints(minHeight: vertical ? 56 : 64),
            padding: EdgeInsets.symmetric(
              horizontal: KSpacing.lg,
              vertical: vertical ? KSpacing.md : KSpacing.md,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? KColor.card
                  : KColor.card.withValues(alpha: dark ? 0.5 : 0.6),
              borderRadius: KRadius.md,
              border: Border.all(
                color: selected
                    ? KColor.ink
                    : KColor.fg.withValues(alpha: dark ? 0.14 : 0.14),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: content,
          ),
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
    Widget option(
      IconData icon,
      String title,
      String subtitle,
      PortionAnchor value,
    ) {
      return _OptionCard(
        title: title,
        subtitle: subtitle,
        leading: Icon(icon, size: 20),
        accent: KGradient.fuel,
        selected: selected == value,
        onTap: () => onSelect(value),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This helps Kyno estimate your dal, sabzi and curry portions.',
            style: KText.caption.copyWith(
              color: KColor.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: KSpacing.md),

          option(
            Icons.bakery_dining_outlined,
            'Roti or rice first',
            'I have a set amount of roti or rice, and dal or sabzi goes with it.',
            PortionAnchor.carbAnchored,
          ),
          option(
            Icons.soup_kitchen_outlined,
            'Dal or curry first',
            "I eat till the dal or curry's done, then stop.",
            PortionAnchor.curryAnchored,
          ),
          option(
            Icons.balance_rounded,
            'Balanced',
            'Roughly equal amounts of both.',
            PortionAnchor.balanced,
          ),
          const SizedBox(height: KSpacing.sm),

          // Skip link — does not affect existing data
          Center(
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: KColor.textMuted,
              ),
              child: Text(
                'Skip for now',
                style: KText.bodyMedium.copyWith(
                  fontSize: 13,
                  color: KColor.textMuted,
                  decoration: TextDecoration.underline,
                  decorationColor: KColor.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: KSpacing.lg),
        ],
      ),
    );
  }
}

// ─── Step 5: Summary — the plan reveal ───────────────────────────────────────
// Moment: success / payoff. Trigger: arriving on the last step (success haptic
// fires in _nextStep on the commit frame). The cards rise in a single stagger
// and the numbers count up. Reduced motion: everything is already in place.

class _StepSummary extends StatelessWidget {
  final WeeklyTargetPlan plan;

  const _StepSummary({required this.plan});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KSpacing.xxl,
        0,
        KSpacing.xxl,
        KSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: kStagger(
          [
            Text(
              'Built from your body, training and goal.',
              style: KText.body.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: KSpacing.lg),
            _HeroTarget(
              icon: Icons.local_fire_department_rounded,
              label: 'Daily calories',
              value: plan.avgDailyCalories,
              suffix: ' kcal',
              colors: KGradient.fuel,
            ),
            const SizedBox(height: KSpacing.md),
            _HeroTarget(
              icon: Icons.egg_outlined,
              label: 'Daily protein',
              value: plan.avgDailyProtein,
              suffix: ' g',
              colors: KGradient.protein,
            ),
            const SizedBox(height: KSpacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: KColor.isDark
                        ? KColor.fg.withValues(alpha: 0.1)
                        : KColor.divider,
                  ),
                  bottom: BorderSide(
                    color: KColor.isDark
                        ? KColor.fg.withValues(alpha: 0.1)
                        : KColor.divider,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _TargetRow(
                    icon: Icons.fitness_center_rounded,
                    label: 'Training days',
                    value: '${whole(plan.trainingDayCalories)} kcal',
                  ),
                  Divider(
                    color: KColor.isDark
                        ? KColor.fg.withValues(alpha: 0.07)
                        : KColor.divider,
                    height: KSpacing.xl,
                  ),
                  _TargetRow(
                    icon: Icons.bedtime_outlined,
                    label: 'Rest days',
                    value: '${whole(plan.restDayCalories)} kcal',
                  ),
                  Divider(
                    color: KColor.isDark
                        ? KColor.fg.withValues(alpha: 0.07)
                        : KColor.divider,
                    height: KSpacing.xl,
                  ),
                  _TargetRow(
                    icon: Icons.balance_rounded,
                    label: 'Maintenance',
                    value: '${whole(plan.maintenanceCalories)} kcal',
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: KSpacing.md),
            Text(
              'These are estimates. Tweak them anytime in your profile.',
              style: KText.caption.copyWith(color: KColor.textMuted),
            ),
          ],
          delay: const Duration(milliseconds: 120),
          stagger: const Duration(milliseconds: 70),
          fromScale: 0.97,
        ),
      ),
    );
  }
}

class _HeroTarget extends StatelessWidget {
  const _HeroTarget({
    required this.icon,
    required this.label,
    required this.value,
    required this.suffix,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final double value;
  final String suffix;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    // The payoff, set as a statement: a heavy rule, the label with its meaning
    // dot, and the number large. No tinted card, no gradient tile.
    final c = colors.first;
    return Semantics(
      container: true,
      label: '$label: ${whole(value)}$suffix',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.only(top: KSpacing.md, bottom: KSpacing.sm),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: KColor.textPrimary, width: 1.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                KDot(color: c, size: 7),
                const SizedBox(width: KSpacing.sm),
                Text(
                  label,
                  style: KText.bodyMedium.copyWith(
                    color: KColor.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: KSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  KRollingNumber.int(
                    value.round(),
                    fromZero: true,
                    duration: KMotion.slow,
                    style: KText.numDisplay.copyWith(
                      fontSize: 52,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    suffix,
                    style: KText.numDisplay.copyWith(
                      fontSize: 52,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _TargetRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: KColor.textMuted),
        const SizedBox(width: KSpacing.md),
        Expanded(
          child: Text(
            label,
            style: KText.bodyMedium.copyWith(
              color: KColor.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: KSpacing.sm),
        Text(value, style: KText.numSmall.copyWith(fontSize: 14)),
      ],
    );
  }
}

// ─── Kyno, narrating ──────────────────────────────────────────────────────────
// Kyno speaks each chapter's line. A new line types itself out (about 18 ms a
// character) next to Kyno's face, which shifts mood with it. Reduced motion:
// the line is just there.

class _KynoSays extends StatelessWidget {
  const _KynoSays({required this.line, required this.mood});
  final String line;
  final KynoMood mood;

  @override
  Widget build(BuildContext context) {
    final reduced = KMotion.reduced(context);
    final style = KText.body.copyWith(
      color: KColor.textSecondary,
      fontSize: 15,
      height: 1.4,
    );
    return Semantics(
      label: 'Kyno says: $line',
      liveRegion: true,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KynoAvatar(size: 34, mood: mood, showBody: false),
          const SizedBox(width: KSpacing.sm),
          Expanded(
            child: reduced
                ? Text(line, style: style)
                : TweenAnimationBuilder<int>(
                    key: ValueKey(line),
                    tween: IntTween(begin: 0, end: line.length),
                    duration: Duration(
                      milliseconds: (line.length * 18).clamp(200, 1400),
                    ),
                    builder: (context, n, _) => Stack(
                      children: [
                        // Reserve the full height so nothing below jumps.
                        Opacity(opacity: 0, child: Text(line, style: style)),
                        Text(line.substring(0, n), style: style),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
