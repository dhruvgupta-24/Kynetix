import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../ui/k_segmented.dart';
import '../models/insights_models.dart';
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../services/insights_report_service.dart';
import '../services/insights_engine.dart';
import '../services/nutrition_target_engine.dart';
import '../services/workout_service.dart';
import '../screens/onboarding_screen.dart'; // UserProfile

// ─── Local constants ──────────────────────────────────────────────────────────

const _kMonthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _kMonthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const _kTabular = [FontFeature.tabularFigures()];


class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0; // 0 = Week, 1 = Month, 2 = Year

  // Selected keys for period navigation
  String? _selectedWeekKey;
  String? _selectedMonthKey;
  String? _selectedYearKey;

  // Cache achievements in local state to preserve "isNew" flag during this screen session
  List<Achievement> _localAchievements = [];

  bool _isRecomputing = false;

  // ── UI-only state ──
  /// True while the very first background compute runs with no cache yet —
  /// drives the shaped skeleton instead of an "empty" message.
  bool _initialLoading = false;

  /// A manual refresh failed; the previous report stays on screen.
  bool _refreshFailed = false;

  /// The orchestrated entrance stagger plays once, for the first report shown.
  bool _revealDone = false;

  /// Cached so rebuilds don't re-fire the query (and flicker the alert).
  Future<bool>? _recoveryFuture;

  /// Spins the refresh glyph while a recompute is in flight.
  late final AnimationController _spin;

  /// Marks achievements viewed after the pulse; cancelled on dispose so a
  /// quick visit never leaves a timer behind.
  Timer? _viewedTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('[InsightsScreen] initState called.');
    debugPrint('  - lastComputed: ${InsightsReportService.instance.lastComputed}');
    debugPrint('  - weekly cache keys: ${InsightsReportService.instance.weeklyCache.keys}');

    _spin = AnimationController(vsync: this, duration: KMotion.slow);

    InsightsReportService.instance.addListener(_onInsightsChanged);
    _localAchievements = List.from(InsightsReportService.instance.achievements);
    _initializeSelectedKeys();

    // Trigger recompute if necessary on screen init
    final profile = currentUserProfile;
    if (profile != null) {
      _initialLoading = InsightsReportService.instance.lastComputed == null;
      InsightsReportService.instance.maybeRecompute(profile).whenComplete(() {
        if (mounted && _initialLoading) {
          setState(() => _initialLoading = false);
        }
      }).ignore();
    }

    // Mark achievements as viewed after a 3-second delay so user sees the pulse animation
    _viewedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        InsightsReportService.instance.markAchievementsViewed();
      }
    });
  }

  @override
  void dispose() {
    InsightsReportService.instance.removeListener(_onInsightsChanged);
    _viewedTimer?.cancel();
    _spin.dispose();
    super.dispose();
  }

  void _onInsightsChanged() {
    if (mounted) {
      setState(() {
        _localAchievements = List.from(InsightsReportService.instance.achievements);
        _initializeSelectedKeys();
        _initialLoading = false;
        _recoveryFuture = null;
      });
    }
  }

  void _initializeSelectedKeys() {
    final weeklyKeys = InsightsReportService.instance.weeklyCache.keys.toList()..sort();
    final monthlyKeys = InsightsReportService.instance.monthlyCache.keys.toList()..sort();
    final yearlyKeys = InsightsReportService.instance.yearlyCache.keys.toList()..sort();

    final now = DateTime.now();
    if (_selectedWeekKey == null || !weeklyKeys.contains(_selectedWeekKey)) {
      _selectedWeekKey = weeklyKeys.isNotEmpty ? weeklyKeys.last : InsightsEngine.weekKeyOf(now);
    }
    if (_selectedMonthKey == null || !monthlyKeys.contains(_selectedMonthKey)) {
      _selectedMonthKey = monthlyKeys.isNotEmpty ? monthlyKeys.last : InsightsEngine.monthKeyOf(now);
    }
    if (_selectedYearKey == null || !yearlyKeys.contains(_selectedYearKey)) {
      _selectedYearKey = yearlyKeys.isNotEmpty ? yearlyKeys.last : now.year.toString();
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRecomputing) return;
    setState(() {
      _isRecomputing = true;
      _refreshFailed = false;
    });
    kHapticMedium();
    if (KMotion.ambientAllowed(context)) _spin.repeat();
    try {
      final profile = currentUserProfile;
      if (profile != null) {
        await InsightsReportService.instance.forceRecompute(profile);
        // Refresh local achievements copy in case new ones were earned
        if (mounted) {
          setState(() {
            _localAchievements = List.from(InsightsReportService.instance.achievements);
            _initializeSelectedKeys();
            _recoveryFuture = null;
          });
        }
      }
    } catch (e) {
      debugPrint('[InsightsScreen] Refresh error: $e');
      if (mounted) setState(() => _refreshFailed = true);
    } finally {
      if (mounted) {
        setState(() => _isRecomputing = false);
        if (_spin.isAnimating) {
          // Finish the current turn instead of snapping back.
          _spin.stop();
          _spin
              .animateTo(1.0, duration: KMotion.of(context, KMotion.standard))
              .whenComplete(() {
            if (mounted) _spin.value = 0;
          });
        }
      }
    }
  }

  // ─── Formatting helpers ─────────────────────────────────────────────────────

  String _formatWeekKey(String weekKey, WeeklyReport? report) {
    if (report == null) return weekKey;
    final start = report.weekStart;
    final end = start.add(const Duration(days: 6));
    const months = _kMonthsShort;
    return '${months[start.month - 1]} ${start.day} to ${months[end.month - 1]} ${end.day}, ${start.year}';
  }

  String _formatMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length < 2) return monthKey;
    final year = parts[0];
    final monthInt = int.tryParse(parts[1]) ?? 1;
    return '${_kMonthsLong[monthInt - 1]} $year';
  }

  String _friendlyAge(DateTime? dt) {
    if (dt == null) return 'not yet';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _verdict(int score) {
    if (score >= 85) return 'Locked in';
    if (score >= 70) return 'Strong rhythm';
    if (score >= 50) return 'Building momentum';
    if (score >= 30) return 'Finding your feet';
    return 'Fresh start';
  }

  // ─── Period navigation ──────────────────────────────────────────────────────

  void _navigateWeek(bool next) {
    final keys = InsightsReportService.instance.weeklyCache.keys.toList()..sort();
    if (keys.isEmpty) return;
    kHapticSelect();
    final index = keys.indexOf(_selectedWeekKey ?? '');
    if (index == -1) {
      setState(() => _selectedWeekKey = keys.last);
    } else {
      final newIndex = (index + (next ? 1 : -1)).clamp(0, keys.length - 1);
      setState(() => _selectedWeekKey = keys[newIndex]);
    }
  }

  void _navigateMonth(bool next) {
    final keys = InsightsReportService.instance.monthlyCache.keys.toList()..sort();
    if (keys.isEmpty) return;
    kHapticSelect();
    final index = keys.indexOf(_selectedMonthKey ?? '');
    if (index == -1) {
      setState(() => _selectedMonthKey = keys.last);
    } else {
      final newIndex = (index + (next ? 1 : -1)).clamp(0, keys.length - 1);
      setState(() => _selectedMonthKey = keys[newIndex]);
    }
  }

  void _navigateYear(bool next) {
    final keys = InsightsReportService.instance.yearlyCache.keys.toList()..sort();
    if (keys.isEmpty) return;
    kHapticSelect();
    final index = keys.indexOf(_selectedYearKey ?? '');
    if (index == -1) {
      setState(() => _selectedYearKey = keys.last);
    } else {
      final newIndex = (index + (next ? 1 : -1)).clamp(0, keys.length - 1);
      setState(() => _selectedYearKey = keys[newIndex]);
    }
  }

  // ─── Motion helper ──────────────────────────────────────────────────────────

  /// One orchestrated entrance for the first report. Afterwards every section
  /// mounts already at rest (zero duration) — the tree shape never changes, so
  /// nothing remounts when the flag flips.
  Widget _reveal(int index, Widget child) {
    final play = !_revealDone;
    return KReveal(
      index: index,
      duration: play ? KMotion.emphasized : Duration.zero,
      stagger: play ? KMotion.stagger : Duration.zero,
      child: child,
    );
  }

  // ─── Tabs UI ────────────────────────────────────────────────────────────────

  Widget _buildTabs() {
    return KSegmented<int>(
      segments: const [
        KSegment(0, 'Week'),
        KSegment(1, 'Month'),
        KSegment(2, 'Year'),
      ],
      value: _selectedTab,
      onChanged: (index) {
        setState(() {
          _selectedTab = index;
        });
      },
    );
  }

  // ─── Shared UI blocks ────────────────────────────────────────────────────────

  Widget _buildConsistencyHeroCard(ConsistencyScore score, PeriodDelta? delta) {
    final loggingStreak = InsightsReportService.instance.getLoggingStreak();
    final profile = currentUserProfile;
    final proteinStreak = profile != null ? InsightsReportService.instance.getProteinStreak(profile) : 0;
    final calorieStreak = profile != null ? InsightsReportService.instance.getCalorieStreak(profile) : 0;
    final scoreDelta = delta?.consistencyScoreDelta;

    return KCard(
      padding: const EdgeInsets.all(KSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RepaintBoundary(
                child: KRing(
                  progress: score.score / 100.0,
                  colors: KGradient.primary,
                  size: 112,
                  stroke: 10,
                  semanticsLabel: 'Consistency score',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CountUp(
                        value: score.score,
                        style: KText.numDisplay.copyWith(fontSize: 34),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '/100',
                        style: KText.caption.copyWith(
                          color: KColor.textMuted,
                          fontFeatures: _kTabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: KSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Consistency score', style: KText.caption.copyWith(color: KColor.textSecondary)),
                    const SizedBox(height: 6),
                    Text(_verdict(score.score), style: KText.h2),
                    if (scoreDelta != null && scoreDelta != 0) ...[
                      const SizedBox(height: KSpacing.sm),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildDeltaChip(scoreDelta),
                          Text('vs previous', style: KText.caption.copyWith(fontSize: 11)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.xl),
          const _Hairline(),
          const SizedBox(height: KSpacing.lg),
          // Calories wear the accent and protein wears ink; the rest are ink
          // tints so the accent keeps one meaning. Every bar has its label.
          _buildMetricRow('Tracking consistency', score.loggingConsistency,
              '${(score.loggingConsistency * 100).round()}%', KColor.textPrimary, [KColor.fiber, KColor.fiber]),
          _buildMetricRow('Protein target hit rate', score.proteinAdherence,
              '${(score.proteinAdherence * 100).round()}%', KColor.protein, KGradient.protein),
          _buildMetricRow('Calorie target hit rate', score.calorieAdherence,
              '${(score.calorieAdherence * 100).round()}%', KColor.calorie, KGradient.fuel),
          _buildMetricRow('Workout consistency', score.gymAttendance,
              '${(score.gymAttendance * 100).round()}%', KColor.textPrimary, [KColor.fat, KColor.fat]),
          if (score.mealQuality > 0)
            _buildMetricRow('Meal quality', score.mealQuality,
                '${(score.mealQuality * 100).round()}', KColor.textPrimary, [KColor.carbs, KColor.carbs]),
          _buildDeltaStrips(delta),
          const SizedBox(height: KSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStreakChip('Log streak', loggingStreak, KColor.textSecondary, Icons.local_fire_department_rounded),
              const SizedBox(width: KSpacing.sm),
              _buildStreakChip('Protein streak', proteinStreak, KColor.protein, Icons.bolt_rounded),
              const SizedBox(width: KSpacing.sm),
              _buildStreakChip('Calorie streak', calorieStreak, KColor.calorie, Icons.track_changes_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStreakChip(String label, int count, Color color, IconData icon) {
    final unit = count == 1 ? 'day' : 'days';
    return Expanded(
      child: Semantics(
        label: '$label: $count $unit',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: KColor.fg.withValues(alpha: KColor.isDark ? 0.035 : 0.03),
            borderRadius: KRadius.sm,
            border: Border.all(color: _hairlineColor(), width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 6),
              Text('$count', style: KText.numMedium.copyWith(fontSize: 22, color: KColor.textPrimary)),
              Text(unit, style: KText.caption.copyWith(fontSize: 11, color: KColor.textMuted)),
              const SizedBox(height: 6),
              Text(
                label,
                style: KText.caption.copyWith(fontSize: 11, color: KColor.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, double value, String detail, Color accent, List<Color> gradient) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.md),
      child: Semantics(
        label: '$label: $detail',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text(label, style: KText.caption.copyWith(color: KColor.textSecondary))),
                const SizedBox(width: KSpacing.sm),
                Text(detail, style: KText.numSmall.copyWith(fontSize: 14, color: accent)),
              ],
            ),
            const SizedBox(height: 6),
            KBar(progress: value, colors: gradient, height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildDeltaChip(int delta) {
    final isPositive = delta > 0;
    if (delta == 0) return const SizedBox.shrink();
    final color = isPositive ? KColor.success : KColor.danger;

    return Semantics(
      label: '${isPositive ? 'Up' : 'Down'} ${delta.abs()} points',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: KRadius.pill,
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isPositive ? Icons.north_east_rounded : Icons.south_east_rounded, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              '${isPositive ? '+' : ''}$delta',
              style: KText.numSmall.copyWith(fontSize: 11.5, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopImprovementCard(TopImprovement? improvement) {
    if (improvement == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.md),
      child: _InferenceCallout(
        icon: Icons.trending_up_rounded,
        eyebrow: 'Top improvement',
        message: improvement.label,
        color: KColor.success,
      ),
    );
  }

  Widget _buildRegressionsList(List<RegressionAlert> regressions) {
    if (regressions.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final alert in regressions)
          Padding(
            padding: const EdgeInsets.only(top: KSpacing.md),
            child: _InferenceCallout(
              icon: Icons.flag_rounded,
              eyebrow: 'Area to improve',
              message: alert.message,
              color: KColor.warning,
            ),
          ),
      ],
    );
  }

  Widget _buildDeltaStrips(PeriodDelta? delta) {
    if (delta == null) return const SizedBox.shrink();

    Widget? buildStrip(String label, double? dVal) {
      if (dVal == null || dVal == 0.0) return null;
      final isPositive = dVal > 0;
      final pct = (dVal * 100).round().abs();
      final color = isPositive ? KColor.success : KColor.danger;
      final sign = isPositive ? '+' : '-';

      return Semantics(
        label: '$label ${isPositive ? 'up' : 'down'} $pct percent',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: KRadius.pill,
            border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                '$label $sign$pct%',
                style: KText.numSmall.copyWith(fontSize: 11.5, color: color),
              ),
            ],
          ),
        ),
      );
    }

    final strips = <Widget>[
      ?buildStrip('Protein', delta.proteinAdherenceDelta),
      ?buildStrip('Calories', delta.calorieAdherenceDelta),
      ?buildStrip('Logging', delta.loggingConsistencyDelta),
      if (delta.mealQualityDelta != null)
        ?buildStrip('Meal quality', delta.mealQualityDelta! / 100.0),
    ];
    if (strips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change vs previous', style: KText.caption.copyWith(color: KColor.textSecondary)),
          const SizedBox(height: KSpacing.sm),
          Wrap(spacing: KSpacing.sm, runSpacing: KSpacing.sm, children: strips),
        ],
      ),
    );
  }

  // ─── Section scaffolding ────────────────────────────────────────────────────

  Widget _kynoReadHeading() => _SectionHeading(
        eyebrow: 'Interpretation',
        title: "Kyno's read",
        caption: 'What your numbers hint at. Coaching, not measurements.',
        icon: Icons.lightbulb_outline_rounded,
      );

  Widget _numbersHeading() => _SectionHeading(
        eyebrow: 'Measured',
        title: 'The numbers',
        caption: 'Straight from your logs and sessions.',
        icon: Icons.insights_rounded,
      );

  // ─── Week View ──────────────────────────────────────────────────────────────

  Widget _buildWeekView(WeeklyReport? report) {
    debugPrint('[InsightsScreen] Rendering week view.');
    debugPrint('  - Selected key: $_selectedWeekKey');
    debugPrint('  - Report: ${report != null ? "found (score: ${report.consistencyScore.score})" : "null"}');
    if (report != null) {
      debugPrint('  - Week start: ${report.weekStart}');
      final monKey = InsightsEngine.dateKeyOf(report.weekStart);
      final friKey = InsightsEngine.dateKeyOf(report.weekStart.add(const Duration(days: 4)));
      debugPrint('  - Monday gym: ${InsightsEngine.isGymDay(date: report.weekStart, log: dayLogStore[monKey], session: WorkoutService.instance.sessionFor(report.weekStart))}');
      debugPrint('  - Friday gym: ${InsightsEngine.isGymDay(date: report.weekStart.add(const Duration(days: 4)), log: dayLogStore[friKey], session: WorkoutService.instance.sessionFor(report.weekStart.add(const Duration(days: 4))))}');
    }

    if (report == null) {
      return _buildEmptyState('Log meals on 3 or more days this week and your report shows up here.');
    }

    final aiSummary = InsightsReportService.instance.aiSummaryFor(report.weekKey);
    final showNarrative = aiSummary != null && aiSummary.narrative.isNotEmpty && !aiSummary.isStale;
    final hasCoaching = report.coachingWhatWentWell.isNotEmpty ||
        report.coachingNeedsImprovement.isNotEmpty ||
        report.coachingRecommendations.isNotEmpty;
    final hasInference = showNarrative ||
        report.topImprovement != null ||
        report.regressions.isNotEmpty ||
        hasCoaching;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reveal(2, _buildPeriodNavRow(
          label: _formatWeekKey(report.weekKey, report),
          caption: 'Weekly report',
          onPrev: () => _navigateWeek(false),
          onNext: () => _navigateWeek(true),
        )),
        const SizedBox(height: KSpacing.sm),

        _reveal(3, _buildConsistencyHeroCard(report.consistencyScore, report.deltaVsPrior)),

        // ── Inferences: Kyno's interpretation, clearly marked as such ──
        if (hasInference) ...[
          const SizedBox(height: KSpacing.xxxl),
          _reveal(4, Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kynoReadHeading(),
              const SizedBox(height: KSpacing.md),
              // AI Narrative card (highest visual priority)
              if (showNarrative) _buildNarrativeCard(aiSummary.narrative),
              _buildTopImprovementCard(report.topImprovement),
              _buildRegressionsList(report.regressions),
              if (hasCoaching) ...[
                const SizedBox(height: KSpacing.md),
                _buildCoachingSummaryCard(report),
              ],
            ],
          )),
        ],

        // ── Facts: measured numbers ──
        const SizedBox(height: KSpacing.xxxl),
        _reveal(5, _numbersHeading()),
        const SizedBox(height: KSpacing.md),
        _reveal(6, _buildMacroSummaryRow(report.avgCalories, report.avgProtein, report.avgFiber)),
        const SizedBox(height: KSpacing.md),
        _reveal(7, _buildGymAttendanceRow(report)),
        const SizedBox(height: KSpacing.md),
        _reveal(8, _buildOutcomeDistributionRow(report)),
        _reveal(9, _buildWeeklyTrainingReviewCard(report)),
      ],
    );
  }

  /// Kyno's written summary: the focal inference, on a plain card with a
  /// hairline. Labelled as Kyno's interpretation of this week's logs.
  Widget _buildNarrativeCard(String narrative) {
    return KCard(
      padding: const EdgeInsets.all(KSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 16, color: KColor.textSecondary),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Text(
                  "Kyno's summary of this week",
                  style: KText.caption.copyWith(
                    color: KColor.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          Text(
            narrative,
            style: KText.body.copyWith(
              fontSize: 16,
              height: 1.55,
              fontWeight: FontWeight.w500,
              color: KColor.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachingSummaryCard(WeeklyReport report) {
    return _InferenceCard(
      accent: KColor.textMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Coaching summary', style: KText.h3),
          const SizedBox(height: KSpacing.md),
          _buildCoachingSection('What went well', report.coachingWhatWentWell, Icons.check_circle_outline_rounded, KColor.success),
          _buildCoachingSection('What needs improvement', report.coachingNeedsImprovement, Icons.warning_amber_rounded, KColor.warning),
          _buildCoachingSection('Suggested changes for next week', report.coachingRecommendations, Icons.lightbulb_outline_rounded, KColor.textPrimary),
        ],
      ),
    );
  }

  Widget _buildWeeklyTrainingReviewCard(WeeklyReport report) {
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center_rounded, size: 15, color: KColor.textPrimary),
              const SizedBox(width: KSpacing.sm),
              Expanded(child: Text('Weekly training review', style: KText.h3)),
            ],
          ),
          const SizedBox(height: KSpacing.lg),

          _buildScoreItem('Training quality', report.trainingQualityScore, report.trainingQualityExplanation),
          _buildScoreItem('Recovery spacing', report.trainingRecoveryScore, report.trainingRecoveryExplanation),
          _buildScoreItem('Volume target', report.trainingVolumeScore, report.trainingVolumeExplanation),
          _buildScoreItem('Volume balance', report.trainingBalanceScore, report.trainingBalanceExplanation),
          _buildScoreItem('Workout consistency', report.trainingConsistencyScore, report.trainingConsistencyExplanation),

          if (report.muscleAnalyses.isNotEmpty) ...[
            const SizedBox(height: KSpacing.xs),
            const _Hairline(),
            const SizedBox(height: KSpacing.lg),
            _buildMuscleAnalysesTable(report.muscleAnalyses),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreItem(String label, int score, String explanation) {
    // Strong in ink, fair set back, low in the accent. The grade word says it
    // too, so colour is never the only signal.
    final Color color = score >= 85
        ? KColor.ink
        : (score >= 65 ? KColor.fat : KColor.ember);
    final Color gradeColor = score >= 65 && score < 85 ? KColor.textSecondary : color;
    final String grade = score >= 85 ? 'Strong' : (score >= 65 ? 'Fair' : 'Low');
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Text(grade, style: KText.caption.copyWith(fontSize: 11.5, color: gradeColor, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('$score', style: KText.numMedium.copyWith(fontSize: 20, color: KColor.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          KBar(progress: score / 100.0, colors: [color.withValues(alpha: 0.7), color], height: 5),
          const SizedBox(height: 6),
          Text(explanation, style: KText.caption.copyWith(fontSize: 11.5, color: KColor.textMuted, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildCoachingSection(String title, List<String> items, IconData icon, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: KText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(left: 21, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: KColor.textMuted, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: KSpacing.sm),
                Expanded(
                  child: Text(item, style: KText.body.copyWith(fontSize: 13, height: 1.45, color: KColor.textPrimary)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildMuscleAnalysesTable(List<MuscleGroupAnalysis> analyses) {
    if (analyses.isEmpty) return const SizedBox.shrink();
    final head = KText.caption.copyWith(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.w600);
    final cell = KText.caption.copyWith(fontSize: 11.5, color: KColor.textPrimary, fontFeatures: _kTabular);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Muscle group details', style: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: KSpacing.sm),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(3),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: KColor.divider)),
              ),
              children: [
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Muscle', style: head)),
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Sets', textAlign: TextAlign.right, style: head)),
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Freq', textAlign: TextAlign.right, style: head)),
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Spacing', textAlign: TextAlign.right, style: head)),
              ],
            ),
            ...analyses.map((a) {
              final double? gap = a.daysBetweenExposures;
              final String spacingLabel = gap == null
                  ? 'None'
                  : (gap < 2.0 ? '${gap.toStringAsFixed(1)}d · tight' : '${gap.toStringAsFixed(1)}d · good');
              final Color spacingColor = gap == null
                  ? KColor.textMuted
                  : (gap < 2.0 ? KColor.ember : KColor.textPrimary);

              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(a.muscleGroup, style: cell.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${a.hardSets}', style: cell.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.right),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${a.sessionsTrained}x', style: cell, textAlign: TextAlign.right),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(spacingLabel, style: cell.copyWith(color: spacingColor), textAlign: TextAlign.right),
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildPeriodNavRow({
    required String label,
    required String caption,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous period',
          icon: Icon(Icons.chevron_left_rounded, color: KColor.textPrimary, size: 28),
          onPressed: onPrev,
        ),
        Expanded(
          child: Column(
            children: [
              Text(caption, style: KText.caption.copyWith(color: KColor.textMuted), textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(
                label,
                style: KText.h3.copyWith(fontSize: 16, fontFeatures: _kTabular),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Next period',
          icon: Icon(Icons.chevron_right_rounded, color: KColor.textPrimary, size: 28),
          onPressed: onNext,
        ),
      ],
    );
  }

  Widget _buildGymAttendanceRow(WeeklyReport report) {
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_view_week_rounded, size: 15, color: KColor.textPrimary),
              const SizedBox(width: KSpacing.sm),
              Expanded(child: Text('Workout consistency', style: KText.h3)),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          Row(
            children: List.generate(7, (i) {
              final date = report.weekStart.add(Duration(days: i));
              final dKey = InsightsEngine.dateKeyOf(date);
              final log = dayLogStore[dKey];
              final session = WorkoutService.instance.sessionFor(date);
              final didGym = InsightsEngine.isGymDay(
                date: date,
                log: log,
                session: session,
              );

              return Expanded(
                child: Semantics(
                  label: '${weekdayNames[i]}: ${didGym ? 'trained' : 'rest'}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      Text(weekdays[i], style: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: KSpacing.sm),
                      // Trained = solid ink + check; rest = quiet outline +
                      // cross. Shape and icon carry it too.
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: didGym
                              ? KColor.ink
                              : KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.03),
                          shape: BoxShape.circle,
                          border: didGym ? null : Border.all(color: _hairlineColor(), width: 1),
                        ),
                        child: Center(
                          child: didGym
                              ? Icon(Icons.check_rounded, size: 17, color: KColor.onInk)
                              : Icon(Icons.close_rounded, size: 13, color: KColor.textDisabled),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSummaryRow(double calories, double protein, double fiber) {
    Widget cell(String label, String value, String unit, Color color, IconData icon) {
      return Expanded(
        child: Semantics(
          label: '$label: $value $unit',
          excludeSemantics: true,
          child: Column(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(height: 6),
              Text(label, style: KText.caption.copyWith(color: KColor.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(value, style: KText.numMedium.copyWith(fontSize: 22), textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(unit, style: KText.caption.copyWith(fontSize: 10.5, color: KColor.textMuted), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    Widget divider() => Container(
          width: 1,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: _hairlineColor(),
        );

    return KCard(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.lg, horizontal: KSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: KSpacing.sm, bottom: KSpacing.md),
            child: Text('Daily averages', style: KText.h3),
          ),
          Row(
            children: [
              cell('Calories', '${calories.round()}', 'kcal/day', KColor.calorie, Icons.local_fire_department_rounded),
              divider(),
              cell('Protein', '${protein.round()}g', 'protein/day', KColor.protein, Icons.egg_alt_rounded),
              divider(),
              cell('Fiber', '${fiber.round()}g', 'fiber/day', KColor.textSecondary, Icons.grass_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeDistributionRow(WeeklyReport report) {
    // Collect outcomes
    final outcomes = <DayOutcome>[];
    for (int i = 0; i < 7; i++) {
      final date = report.weekStart.add(Duration(days: i));
      final dKey = InsightsEngine.dateKeyOf(date);
      final log = dayLogStore[dKey];
      if (log != null && !log.isEmpty) {
        // Mock a day outcome by reading its status or classification
        // Let's classify it using the engine target
        final target = NutritionTargetEngine.instance.effectiveTargetForDate(
          date,
          profile: currentUserProfile,
        );
        final classification = DayStatusEngine.classify(log, target, now: date);
        outcomes.add(classification.outcome);
      }
    }

    if (outcomes.isEmpty) return const SizedBox.shrink();

    // Count outcomes
    final counts = <DayOutcome, int>{};
    for (final o in outcomes) {
      counts[o] = (counts[o] ?? 0) + 1;
    }
    final entries = counts.entries.toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.md),
      child: KCard(
        padding: const EdgeInsets.all(KSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily goal status', style: KText.h3),
            const SizedBox(height: KSpacing.md),
            // Horizontal stacked bar of the week's outcomes, 2px surface gaps
            ExcludeSemantics(
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      Expanded(
                        flex: entries[i].value,
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(end: i == entries.length - 1 ? 0 : 2),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _getOutcomeDetails(entries[i].key).color,
                              borderRadius: const BorderRadius.all(Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KSpacing.md),
            // Legend list
            for (final entry in entries)
              Builder(builder: (context) {
                final outcome = entry.key;
                final count = entry.value;
                final details = _getOutcomeDetails(outcome);
                final days = '$count ${count == 1 ? 'day' : 'days'}';

                return Semantics(
                  label: '${details.label}: $days',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: details.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(details.label, style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textPrimary)),
                        ),
                        const SizedBox(width: KSpacing.sm),
                        Text(days, style: KText.numSmall.copyWith(fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  ({String label, Color color}) _getOutcomeDetails(DayOutcome outcome) {
    return switch (outcome) {
      // Met days in ink, the surplus in the accent, the in-between days in
      // tints. The legend names every swatch.
      DayOutcome.hitCaloriesAndProtein => (label: 'Calories and protein met', color: KColor.ink),
      DayOutcome.hitCaloriesMissedProtein => (label: 'Calories hit, protein low', color: KColor.fat),
      DayOutcome.hitProteinOverCalories => (label: 'Protein met, calories high', color: KColor.carbs),
      DayOutcome.underCaloriesUnderProtein => (label: 'Under calories and protein', color: KColor.fiber),
      DayOutcome.overCaloriesSignificantly => (label: 'Calorie surplus', color: KColor.ember),
      DayOutcome.veryGoodFatLoss => (label: 'Fat loss on track', color: KColor.ink),
      DayOutcome.maintenanceLike => (label: 'Maintenance day', color: KColor.textSecondary),
      DayOutcome.incomplete => (label: 'Incomplete log', color: KColor.textMuted),
      DayOutcome.unlogged => (label: 'Not logged', color: KColor.textDisabled),
    };
  }

  // ─── Month View ─────────────────────────────────────────────────────────────

  Widget _buildMonthView(MonthlyReport? report) {
    if (report == null) {
      return _buildEmptyState('Log meals on 10 or more days this month and your report shows up here.');
    }

    // Get weeks belonging to this month to draw sparkline
    final parts = report.monthKey.split('-');
    final year = int.tryParse(parts[0]) ?? 2026;
    final month = int.tryParse(parts[1]) ?? 6;

    final weeklyCache = InsightsReportService.instance.weeklyCache;
    final monthWeeks = weeklyCache.values
        .where((w) => w.weekStart.year == year && w.weekStart.month == month)
        .toList()
      ..sort((a, b) => a.weekKey.compareTo(b.weekKey));

    final hasInference = report.topImprovement != null || report.regressions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reveal(2, _buildPeriodNavRow(
          label: _formatMonthKey(report.monthKey),
          caption: 'Monthly report',
          onPrev: () => _navigateMonth(false),
          onNext: () => _navigateMonth(true),
        )),
        const SizedBox(height: KSpacing.sm),

        _reveal(3, _buildConsistencyHeroCard(report.consistencyScore, report.deltaVsPrior)),

        if (hasInference) ...[
          const SizedBox(height: KSpacing.xxxl),
          _reveal(4, Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kynoReadHeading(),
              _buildTopImprovementCard(report.topImprovement),
              _buildRegressionsList(report.regressions),
            ],
          )),
        ],

        const SizedBox(height: KSpacing.xxxl),
        _reveal(5, _numbersHeading()),
        const SizedBox(height: KSpacing.md),

        if (monthWeeks.isNotEmpty) ...[
          _reveal(6, _buildWeeklyScoresSparkline(monthWeeks)),
          const SizedBox(height: KSpacing.md),
        ],

        _reveal(7, _buildBestWorstWeeks(report)),
        const SizedBox(height: KSpacing.md),

        _reveal(8, _buildOverviewTotalsCard(
          title: 'Monthly totals',
          logged: report.totalLoggedDays,
          maxDays: DateTime(year, month + 1, 0).day,
          gym: report.totalGymDays,
        )),
      ],
    );
  }

  Widget _buildWeeklyScoresSparkline(List<WeeklyReport> reports) {
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly scores this month', style: KText.h3),
          const SizedBox(height: KSpacing.lg),
          RepaintBoundary(
            child: SizedBox(
              height: 136,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: reports.map((r) {
                  final parts = r.weekKey.split('-W');
                  final wNum = parts.length > 1 ? parts[1] : '';
                  return Expanded(
                    child: _ScoreColumn(score: r.consistencyScore.score, label: 'W$wNum'),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBestWorstTile({
    required IconData icon,
    required String eyebrow,
    required Color color,
    required String title,
    required String scoreLine,
  }) {
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(eyebrow, style: KText.caption.copyWith(color: color, fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: KSpacing.sm),
          Text(title, style: KText.h2.copyWith(fontSize: 18)),
          const SizedBox(height: 2),
          Text(scoreLine, style: KText.caption.copyWith(color: KColor.textMuted, fontFeatures: _kTabular)),
        ],
      ),
    );
  }

  Widget _buildBestWorstWeeks(MonthlyReport report) {
    final bestWeek = report.bestWeekKey != null ? InsightsReportService.instance.weeklyFor(report.bestWeekKey!) : null;
    final worstWeek = report.worstWeekKey != null ? InsightsReportService.instance.weeklyFor(report.worstWeekKey!) : null;

    if (bestWeek == null && worstWeek == null) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bestWeek != null)
          Expanded(
            child: _buildBestWorstTile(
              icon: Icons.emoji_events_rounded,
              eyebrow: 'Best week',
              color: KColor.success,
              title: 'Week ${bestWeek.weekKey.split('-W')[1]}',
              scoreLine: 'Score: ${bestWeek.consistencyScore.score}',
            ),
          ),
        if (bestWeek != null && worstWeek != null) const SizedBox(width: KSpacing.sm),
        if (worstWeek != null)
          Expanded(
            child: _buildBestWorstTile(
              icon: Icons.hourglass_bottom_rounded,
              eyebrow: 'Weakest week',
              color: KColor.warning,
              title: 'Week ${worstWeek.weekKey.split('-W')[1]}',
              scoreLine: 'Score: ${worstWeek.consistencyScore.score}',
            ),
          ),
      ],
    );
  }

  Widget _buildOverviewTotalsCard({
    String title = 'Monthly totals',
    required int logged,
    required int maxDays,
    required int gym,
  }) {
    Widget stat(String label, String big, String small, Color color, IconData icon) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: KText.caption.copyWith(color: KColor.textSecondary))),
              ],
            ),
            const SizedBox(height: 6),
            Text(big, style: KText.numDisplay.copyWith(fontSize: 30)),
            Text(small, style: KText.caption.copyWith(fontSize: 11, color: KColor.textMuted)),
          ],
        ),
      );
    }

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: KText.h3),
          const SizedBox(height: KSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stat('Logged days', '$logged', 'of $maxDays days', KColor.textSecondary, Icons.edit_calendar_rounded),
              const SizedBox(width: KSpacing.md),
              stat('Gym sessions', '$gym', 'workouts', KColor.textSecondary, Icons.fitness_center_rounded),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Year View ──────────────────────────────────────────────────────────────

  Widget _buildYearView(YearlyReport? report) {
    if (report == null) {
      return _buildEmptyState('Log meals on 60 or more days this year and your report shows up here.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reveal(2, _buildPeriodNavRow(
          label: 'Year ${report.yearKey}',
          caption: 'Yearly report',
          onPrev: () => _navigateYear(false),
          onNext: () => _navigateYear(true),
        )),
        const SizedBox(height: KSpacing.sm),

        _reveal(3, _buildConsistencyHeroCard(report.consistencyScore, null)),

        const SizedBox(height: KSpacing.xxxl),
        _reveal(4, _numbersHeading()),
        const SizedBox(height: KSpacing.md),

        _reveal(5, _buildMonthlyScoresSparkline(report.monthlyScores)),
        if (report.monthlyScores.isNotEmpty) const SizedBox(height: KSpacing.md),

        _reveal(6, _buildBestWorstMonths(report)),
        const SizedBox(height: KSpacing.md),

        _reveal(7, _buildOverviewTotalsCard(
          title: 'Yearly totals',
          logged: report.totalLoggedDays,
          maxDays: 365,
          gym: report.totalGymDays,
        )),
      ],
    );
  }

  Widget _buildMonthlyScoresSparkline(Map<String, int> monthlyScores) {
    if (monthlyScores.isEmpty) return const SizedBox.shrink();
    final sortedMonths = monthlyScores.keys.toList()..sort();

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly scores this year', style: KText.h3),
          const SizedBox(height: KSpacing.lg),
          RepaintBoundary(
            child: SizedBox(
              height: 136,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: sortedMonths.length,
                itemBuilder: (context, index) {
                  final mKey = sortedMonths[index];
                  final score = monthlyScores[mKey] ?? 0;
                  final parts = mKey.split('-');
                  final mInt = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
                  final mLabel = _kMonthsShort[mInt - 1];

                  return SizedBox(
                    width: 46,
                    child: _ScoreColumn(score: score, label: mLabel),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBestWorstMonths(YearlyReport report) {
    final bestKey = report.bestMonthKey;
    final worstKey = report.worstMonthKey;

    if (bestKey == null && worstKey == null) return const SizedBox.shrink();

    String mName(String key) {
      final parts = key.split('-');
      if (parts.length < 2) return key;
      final mInt = int.tryParse(parts[1]) ?? 1;
      return _kMonthsShort[mInt - 1];
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bestKey != null)
          Expanded(
            child: _buildBestWorstTile(
              icon: Icons.emoji_events_rounded,
              eyebrow: 'Best month',
              color: KColor.success,
              title: mName(bestKey),
              scoreLine: 'Score: ${report.monthlyScores[bestKey]}',
            ),
          ),
        if (bestKey != null && worstKey != null) const SizedBox(width: KSpacing.sm),
        if (worstKey != null)
          Expanded(
            child: _buildBestWorstTile(
              icon: Icons.hourglass_bottom_rounded,
              eyebrow: 'Weakest month',
              color: KColor.warning,
              title: mName(worstKey),
              scoreLine: 'Score: ${report.monthlyScores[worstKey]}',
            ),
          ),
      ],
    );
  }

  // ─── Personal Bests ─────────────────────────────────────────────────────────

  Widget _buildPersonalBestsCard(PersonalBests? pbs, WeeklyReport? report) {
    if (pbs == null) return const SizedBox.shrink();

    String formatDateKey(String? dateKey) {
      if (dateKey == null) return '-';
      final parts = dateKey.split('-');
      if (parts.length < 3) return dateKey;
      final m = int.tryParse(parts[1]) ?? 1;
      final d = int.tryParse(parts[2]) ?? 1;
      return '${_kMonthsShort[m - 1]} $d';
    }

    String formatWeekKey(String? wKey) {
      if (wKey == null) return '-';
      final parts = wKey.split('-W');
      if (parts.length < 2) return wKey;
      return 'Week ${parts[1]}';
    }

    String formatMonthKey(String? mKey) {
      if (mKey == null) return '-';
      final parts = mKey.split('-');
      if (parts.length < 2) return mKey;
      final m = int.tryParse(parts[1]) ?? 1;
      return _kMonthsShort[m - 1];
    }

    // Helper to render PB Row: a meaning dot, the record, its date, the value.
    Widget buildPbRow(String label, String value, String dateDesc, bool highlight, IconData icon, Color color) {
      return MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(icon, size: KIcons.md, color: color == KColor.textSecondary ? KColor.textMuted : color),
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KText.bodyMedium.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(dateDesc, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (highlight)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _NewPill(label: 'New', color: KColor.ember),
                      ),
                    Text(value, style: KText.numSmall.copyWith(fontSize: 16), textAlign: TextAlign.end),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Check if the best day or week is during the currently viewed week
    bool isHighestProteinThisWeek = false;
    bool isBestWeekThisWeek = false;

    if (report != null) {
      if (pbs.highestProteinDayKey != null) {
        final pbDate = DateTime.tryParse(pbs.highestProteinDayKey!);
        if (pbDate != null) {
          final diff = pbDate.difference(report.weekStart).inDays;
          if (diff >= 0 && diff < 7) {
            isHighestProteinThisWeek = true;
          }
        }
      }
      if (pbs.bestMealQualityWeekKey == report.weekKey) {
        isBestWeekThisWeek = true;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          eyebrow: 'Personal bests',
          title: 'Your records',
          icon: Icons.emoji_events_outlined,
        ),
        const SizedBox(height: KSpacing.xs),
        Padding(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              buildPbRow(
                'Protein peak',
                pbs.highestProteinDay != null ? '${pbs.highestProteinDay!.round()}g' : '-',
                formatDateKey(pbs.highestProteinDayKey),
                isHighestProteinThisWeek,
                KIcons.protein,
                KColor.protein,
              ),
              const _Hairline(),
              buildPbRow(
                'Longest tracking streak',
                plural(pbs.longestLoggingStreak, 'day'),
                'All-time, back to back',
                false,
                KIcons.calendar,
                KColor.textSecondary,
              ),
              const _Hairline(),
              buildPbRow(
                'Best weekly food quality',
                pbs.bestMealQualityWeekScore != null ? '${pbs.bestMealQualityWeekScore} / 100' : '-',
                formatWeekKey(pbs.bestMealQualityWeekKey),
                isBestWeekThisWeek,
                KIcons.plate,
                KColor.textSecondary,
              ),
              const _Hairline(),
              buildPbRow(
                'Step record (week)',
                pbs.highestAvgStepsWeek != null ? '${pbs.highestAvgStepsWeek}/day avg' : '-',
                formatWeekKey(pbs.highestAvgStepsWeekKey),
                false,
                Icons.directions_walk_outlined,
                KColor.textSecondary,
              ),
              const _Hairline(),
              buildPbRow(
                'Most consistent month',
                pbs.mostConsistentMonthScore != null ? '${pbs.mostConsistentMonthScore} / 100' : '-',
                formatMonthKey(pbs.mostConsistentMonthKey),
                false,
                Icons.calendar_month_outlined,
                KColor.textSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExercisePersonalRecordsCard() {
    final prs = WorkoutService.instance.getPersonalRecords();
    if (prs.isEmpty) {
      return const SizedBox.shrink();
    }

    String formatDateKey(String? dateKey) {
      if (dateKey == null) return '-';
      final parts = dateKey.split('-');
      if (parts.length < 3) return dateKey;
      final m = int.tryParse(parts[1]) ?? 1;
      final d = int.tryParse(parts[2]) ?? 1;
      return '${_kMonthsShort[m - 1]} $d';
    }

    String kg(double v) => v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          eyebrow: 'Exercise personal records',
          title: 'Strength records',
          icon: Icons.fitness_center_rounded,
        ),
        const SizedBox(height: KSpacing.md),
        ...prs.map((pr) {
          double topRepsWeight = 0.0;
          int topReps = 0;
          String? topRepsDate;
          pr.maxRepsAtWeight.forEach((w, r) {
            if (r > topReps) {
              topReps = r;
              topRepsWeight = w;
              topRepsDate = pr.maxRepsAtWeightDate[w];
            }
          });

          return Padding(
            padding: const EdgeInsets.only(bottom: KSpacing.md),
            child: KCard(
              padding: const EdgeInsets.all(KSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(pr.exerciseName, style: KText.h3),
                      ),
                      const SizedBox(width: KSpacing.sm),
                      _NewPill(label: 'Record', color: KColor.textPrimary, icon: Icons.emoji_events_rounded),
                    ],
                  ),
                  const SizedBox(height: KSpacing.md),
                  _buildPrDetailRow('Best weight', '${kg(pr.bestWeight)} kg', formatDateKey(pr.bestWeightDate)),
                  const _Hairline(vertical: 8),
                  _buildPrDetailRow('Best volume', '${kg(pr.bestVolume)} kg', formatDateKey(pr.bestVolumeDate)),
                  const _Hairline(vertical: 8),
                  _buildPrDetailRow('Best est. 1RM', '${kg(pr.bestEstimatedOneRepMax)} kg', formatDateKey(pr.bestEstimatedOneRepMaxDate)),
                  if (topReps > 0) ...[
                    const _Hairline(vertical: 8),
                    _buildPrDetailRow(
                      'Most reps',
                      '$topReps reps @ ${kg(topRepsWeight)} kg',
                      formatDateKey(topRepsDate),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPrDetailRow(String label, String value, String dateDesc) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: KText.caption.copyWith(color: KColor.textSecondary)),
              const SizedBox(height: 2),
              Text(dateDesc, style: KText.caption.copyWith(fontSize: 10.5, color: KColor.textMuted)),
            ],
          ),
        ),
        const SizedBox(width: KSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: KText.numSmall.copyWith(fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutPerformanceInsights() {
    final wService = WorkoutService.instance;
    final plateaus = wService.getPlateauedExercises();
    final wowVolume = wService.getWeekOverWeekVolumeChangeByMuscle();
    final freqTrends = wService.getMuscleFrequencyTrends();
    final hasWorkoutHistory = wService.sessions.isNotEmpty;
    if (!hasWorkoutHistory) return const SizedBox.shrink();

    _recoveryFuture ??= wService.hasRecoveryDeterioration();

    return FutureBuilder<bool>(
      future: _recoveryFuture,
      builder: (context, snapshot) {
        final recoveryDeteriorated = snapshot.data ?? false;
        final hasPlateaus = plateaus.isNotEmpty;
        final hasAnyAlert = hasPlateaus || recoveryDeteriorated;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeading(
              eyebrow: 'Workout performance',
              title: 'Training trends',
              icon: Icons.show_chart_rounded,
            ),
            const SizedBox(height: KSpacing.md),

            if (hasAnyAlert) ...[
              if (recoveryDeteriorated)
                Padding(
                  padding: EdgeInsets.only(bottom: KSpacing.md),
                  child: _InferenceCallout(
                    icon: Icons.monitor_heart_rounded,
                    eyebrow: 'Recovery alert',
                    message: 'Readiness has been low 3 days running. A lighter session, more sleep or some easy movement could help.',
                    color: KColor.danger,
                  ),
                ),

              if (hasPlateaus)
                Padding(
                  padding: const EdgeInsets.only(bottom: KSpacing.md),
                  child: _InferenceCallout(
                    icon: Icons.trending_flat_rounded,
                    eyebrow: 'Plateau warning',
                    message: 'Progress has stalled on ${plateaus.join(", ")}. Try a new rep range, swap the order, or take a deload week.',
                    color: KColor.warning,
                  ),
                ),
            ],

            KCard(
              padding: const EdgeInsets.all(KSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Muscle group trends', style: KText.h3),
                  const SizedBox(height: KSpacing.sm),
                  if (freqTrends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
                      child: Text('No trends yet. A couple more logged sessions gets this going.', style: KText.caption),
                    )
                  else
                    ...freqTrends.entries.map((entry) {
                      final muscle = entry.key;
                      final freq = entry.value;
                      final wow = wowVolume[muscle] ?? 0.0;
                      final wowStr = wow >= 0 ? '+${wow.toStringAsFixed(0)}%' : '${wow.toStringAsFixed(0)}%';
                      final up = wow >= 0;
                      final wowColor = up ? KColor.success : KColor.danger;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(muscle, style: KText.bodyMedium.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Avg frequency: ${freq.toStringAsFixed(1)}x/week',
                                    style: KText.caption.copyWith(fontSize: 11, color: KColor.textMuted, fontFeatures: _kTabular),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: KSpacing.sm),
                            Semantics(
                              label: 'Week over week volume $wowStr',
                              excludeSemantics: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: wowColor),
                                  Text(wowStr, style: KText.numSmall.copyWith(fontSize: 13, color: wowColor)),
                                  Text(' volume vs last week', style: KText.caption.copyWith(fontSize: 10.5, color: KColor.textMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Achievements UI ────────────────────────────────────────────────────────

  void _showAchievementSheet(Achievement achievement) {
    KHaptics.select();
    showKSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: KSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetHeader('Badge unlocked'),
              const SizedBox(height: KSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Medallion(id: achievement.id, size: 76, state: _MedalState.earned),
                    const SizedBox(height: KSpacing.lg),
                    Text(achievement.title, style: KText.h1, textAlign: TextAlign.center),
                    const SizedBox(height: KSpacing.sm),
                    Text(
                      achievement.description,
                      style: KText.body.copyWith(color: KColor.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: KSpacing.md),
                    Text(
                      'Earned ${_formatDate(achievement.earnedAt)}',
                      style: KText.caption.copyWith(fontFeatures: _kTabular),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAchievementsSection() {
    final progressList = InsightsReportService.instance.progress;
    final earned = _localAchievements;

    final earnedIds = earned.map((a) => a.id).toSet();
    final progressIds = progressList.map((p) => p.id).toSet();

    // Locked achievements: in the registry, not earned, not in progress
    final lockedIds = AchievementRegistry.allIds
        .where((id) => !earnedIds.contains(id) && !progressIds.contains(id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          eyebrow: 'Achievements',
          title: 'Badges',
          caption: '${earned.length} earned',
          icon: Icons.military_tech_outlined,
        ),
        const SizedBox(height: KSpacing.lg),

        // 1. Earned achievements
        if (earned.isNotEmpty) ...[
          Text('Earned', style: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: KSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = KSpacing.md;
              final twoUp = (constraints.maxWidth - gap) / 2 >= 128;
              final tileWidth = twoUp ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: earned.reversed.map((achievement) {
                  final isNew = achievement.isNew;
                  final tile = _EarnedBadge(
                    achievement: achievement,
                    dateLabel: _formatDate(achievement.earnedAt),
                    onTap: () => _showAchievementSheet(achievement),
                  );
                  return SizedBox(
                    key: ValueKey('achievement_${achievement.id}'),
                    width: tileWidth,
                    child: isNew ? _PulsingBadge(child: tile) : tile,
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: KSpacing.xl),
        ],

        // 2. In progress: a ruled list, each with a hairline progress rule.
        if (progressList.isNotEmpty) ...[
          _BadgeListLabel('In progress'),
          ...progressList.map((progress) {
            final meta = AchievementRegistry.fromId(progress.id);
            if (meta == null) return const SizedBox.shrink();

            return MergeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _hairlineColor())),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Medallion(id: progress.id, size: 36, state: _MedalState.progress),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(meta.title, style: KText.h3.copyWith(fontSize: 15)),
                              ),
                              const SizedBox(width: KSpacing.sm),
                              Text(
                                progress.label,
                                style: KText.numSmall.copyWith(
                                  fontSize: 12.5,
                                  color: KColor.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            meta.description,
                            style: KText.caption.copyWith(fontSize: 12.5, height: 1.45),
                          ),
                          const SizedBox(height: KSpacing.sm + 2),
                          KBar(progress: progress.fraction, colors: KGradient.primary, height: 3),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: KSpacing.xl),
        ],

        // 3. Locked: quieter still, no surface at all.
        if (lockedIds.isNotEmpty) ...[
          _BadgeListLabel('Locked'),
          ...lockedIds.map((id) {
            final meta = AchievementRegistry.fromId(id);
            if (meta == null) return const SizedBox.shrink();

            return MergeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _hairlineColor())),
                ),
                child: Row(
                  children: [
                    _Medallion(id: id, size: 36, state: _MedalState.locked),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(meta.title, style: KText.h3.copyWith(fontSize: 14.5, color: KColor.textSecondary)),
                          const SizedBox(height: 2),
                          Text(meta.description, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: KSpacing.sm),
                    Icon(Icons.lock_outline_rounded, size: KIcons.sm, color: KColor.textMuted, semanticLabel: 'Locked'),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day} ${_kMonthsShort[dt.month - 1]}';
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
      child: KCard(
        padding: EdgeInsets.zero,
        child: KEmptyState(
          type: KEmptyStateType.general,
          title: 'Nothing to read yet',
          message: msg,
          kyno: true,
          actionLabel: 'Refresh insights',
          onAction: _handleRefresh,
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: Center(
            child: KLoadingLabel(
              messages: ['Pulling your history…', 'Crunching your week…'],
            ),
          ),
        ),
        KCardShimmer(height: 168),
        SizedBox(height: KSpacing.md),
        KChartShimmer(),
        SizedBox(height: KSpacing.md),
        KCardShimmer(),
      ],
    );
  }

  /// Resolves the selected period to exactly one of skeleton / empty / report,
  /// and crossfades between periods.
  Widget _buildPeriodBody() {
    final String periodKey;
    final bool hasReport;
    final Widget Function() content;
    switch (_selectedTab) {
      case 1:
        final r = InsightsReportService.instance.monthlyFor(_selectedMonthKey ?? '');
        periodKey = 'm|$_selectedMonthKey';
        hasReport = r != null;
        content = () => _buildMonthView(r);
      case 2:
        final r = InsightsReportService.instance.yearlyFor(_selectedYearKey ?? '');
        periodKey = 'y|$_selectedYearKey';
        hasReport = r != null;
        content = () => _buildYearView(r);
      default:
        final r = InsightsReportService.instance.weeklyFor(_selectedWeekKey ?? '');
        periodKey = 'w|$_selectedWeekKey';
        hasReport = r != null;
        content = () => _buildWeekView(r);
    }

    final skeleton = !hasReport && _initialLoading;
    final state = hasReport ? 'report' : (skeleton ? 'loading' : 'empty');

    if (!skeleton && !_revealDone) {
      // The entrance plays for this first resolved state only.
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealDone = true);
    }

    return AnimatedSwitcher(
      duration: KMotion.of(context, KMotion.standard),
      reverseDuration: KMotion.of(context, KMotion.quick),
      switchInCurve: KMotion.decelerate,
      switchOutCurve: KMotion.accelerate,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.012), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('$periodKey|$state'),
        child: skeleton
            ? Semantics(label: 'Loading your report', child: _buildLoadingSkeleton())
            : content(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastComputed = InsightsReportService.instance.lastComputed;
    final weeklyReport = InsightsReportService.instance.weeklyFor(_selectedWeekKey ?? '');
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return KPage(
      tone: KTone.kyno,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Insights', style: KText.h2),
        actions: [
          IconButton(
            tooltip: 'Refresh insights',
            icon: RotationTransition(
              turns: _spin,
              child: AnimatedOpacity(
                opacity: _isRecomputing ? 0.6 : 1.0,
                duration: KMotion.of(context, KMotion.quick),
                child: Icon(
                  Icons.refresh_rounded,
                  color: _isRecomputing ? KColor.textSecondary : KColor.textPrimary,
                ),
              ),
            ),
            onPressed: _handleRefresh,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: KColor.ink,
          backgroundColor: KColor.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, bottomInset + 48),
            children: [
              // Data Freshness Indicator
              _reveal(0, Semantics(
                liveRegion: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRecomputing ? Icons.sync_rounded : Icons.schedule_rounded,
                      size: 13,
                      color: KColor.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _isRecomputing
                            ? 'Updating from your logs…'
                            : 'Last updated ${_friendlyAge(lastComputed)}',
                        style: KText.caption.copyWith(fontFeatures: _kTabular),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: KSpacing.lg),

              _reveal(1, _buildTabs()),

              // Refresh failure keeps the previous report on screen.
              AnimatedSize(
                duration: KMotion.of(context, KMotion.standard),
                curve: KMotion.emphasizedCurve,
                alignment: Alignment.topCenter,
                child: _refreshFailed
                    ? Padding(
                        padding: const EdgeInsets.only(top: KSpacing.lg),
                        child: KErrorCard(
                          title: "Couldn't refresh insights",
                          message: 'Your last report is still shown below. Check your connection and try again.',
                          onRetry: _handleRefresh,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: KSpacing.lg),

              // Sub-views based on Tab selection
              _buildPeriodBody(),

              const SizedBox(height: KSpacing.xxxl),
              _reveal(10, _buildPersonalBestsCard(InsightsReportService.instance.personalBests, weeklyReport)),

              const SizedBox(height: KSpacing.xxxl),
              _reveal(10, _buildExercisePersonalRecordsCard()),

              const SizedBox(height: KSpacing.xxxl),
              _reveal(10, _buildWorkoutPerformanceInsights()),

              const SizedBox(height: KSpacing.xxxl),
              _reveal(10, _buildAchievementsSection()),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Private building blocks ──────────────────────────────────────────────────

/// Report section heading: monochrome icon tile, eyebrow, Geist title and an
/// optional caption. Editorial hierarchy, no colour.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.icon,
    this.caption,
  });

  final String eyebrow;
  final String title;
  final String? caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Typographic only: an eyebrow and a title under a full-width rule.
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(top: KSpacing.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: KColor.textPrimary, width: 1.5)),
            ),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: KText.caption.copyWith(color: KColor.textMuted)),
              const SizedBox(height: 2),
              Semantics(header: true, child: Text(title, style: KText.h1.copyWith(fontSize: 22))),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(caption!, style: KText.caption),
              ],
            ],
          ),
          ),
        ),
      ],
    );
  }
}

/// Small sentence-case label above a badge list.
class _BadgeListLabel extends StatelessWidget {
  const _BadgeListLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// An inference (Kyno's interpretation) — marked by an inset accent rule so it
/// never reads as a measured fact.
class _InferenceCard extends StatelessWidget {
  const _InferenceCard({required this.child, required this.accent});

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, KSpacing.lg, KSpacing.lg, KSpacing.lg),
            child: child,
          ),
          PositionedDirectional(
            start: 0,
            top: 18,
            bottom: 18,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                borderRadius: KRadius.pill,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InferenceCallout extends StatelessWidget {
  const _InferenceCallout({
    required this.icon,
    required this.eyebrow,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String eyebrow;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _InferenceCard(
      accent: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: KColor.isDark ? 0.14 : 0.1),
              borderRadius: KRadius.sm,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow, style: KText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(message, style: KText.body.copyWith(fontSize: 13.5, height: 1.45, color: KColor.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme-aware hairline colour: white-on-black on Carbon, warm border on
/// Paper. A function, never cached.
Color _hairlineColor() =>
    KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;

class _Hairline extends StatelessWidget {
  const _Hairline({this.vertical = 0});
  final double vertical;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: Container(height: 1, color: _hairlineColor()),
    );
  }
}

class _NewPill extends StatelessWidget {
  const _NewPill({required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // A coloured word with a dot, not a tinted pill.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 12, color: color)
        else
          KDot(color: color, size: 6),
        const SizedBox(width: 4),
        Text(label, style: KText.caption.copyWith(fontSize: 11.5, color: color, fontWeight: FontWeight.w600, height: 1.2)),
      ],
    );
  }
}

/// Number that counts up to its value (collapses to instant under reduced motion).
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: KMotion.of(context, KMotion.slow),
      curve: KMotion.emphasizedCurve,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Single bar in a score column chart: value on top, rounded data-end, label.
class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({required this.score, required this.label});
  final int score;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fraction = (score / 100.0).clamp(0.0, 1.0);
    return Semantics(
      label: '$label: score $score',
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$score', style: KText.numSmall.copyWith(fontSize: 12)),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: KMotion.of(context, KMotion.slow),
            curve: KMotion.emphasizedCurve,
            builder: (context, v, _) => Container(
              width: 18,
              height: 4 + 68 * v,
              // Scores are not protein: monochrome ink bars.
              decoration: BoxDecoration(
                color: KColor.ink.withValues(alpha: KColor.isDark ? 0.9 : 0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(2)),
              ),
            ),
          ),
          const SizedBox(height: KSpacing.sm),
          Text(label, style: KText.caption.copyWith(fontSize: 10.5, color: KColor.textMuted)),
        ],
      ),
    );
  }
}

enum _MedalState { earned, progress, locked }

/// Achievement medallion: one outlined glyph in a ring, from the shared icon
/// language (never emoji). Earned is a solid ink disc, in progress a hairline
/// ring, locked a faint ring with a muted glyph.
IconData _badgeIcon(String id) => switch (id) {
      'logged_first_day' => KIcons.baseline,
      'logged_7_days' || 'logged_30_days' || 'logged_100_days' => KIcons.calendar,
      'protein_target_3_row' || 'protein_target_7_row' || 'pb_protein_day' => KIcons.protein,
      'cal_adherence_week' => KIcons.target,
      'perfect_week' => Icons.check_circle_outline,
      'gym_3_row' || 'gym_30_total' => KIcons.train,
      'gym_100_total' => KIcons.record,
      'quality_score_80_week' => KIcons.plate,
      'first_monthly_report' => Icons.insert_chart_outlined,
      'improvement_month' => Icons.trending_up,
      _ => KIcons.record,
    };

class _Medallion extends StatelessWidget {
  const _Medallion({required this.id, required this.size, required this.state});
  final String id;
  final double size;
  final _MedalState state;

  @override
  Widget build(BuildContext context) {
    final earned = state == _MedalState.earned;
    final locked = state == _MedalState.locked;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: earned ? KColor.ink : null,
          border: earned
              ? null
              : Border.all(
                  color: KColor.fg.withValues(alpha: locked ? 0.12 : 0.28),
                  width: 1.2,
                ),
        ),
        alignment: Alignment.center,
        child: Icon(
          _badgeIcon(id),
          size: size * 0.46,
          color: earned
              ? KColor.onInk
              : (locked ? KColor.textMuted : KColor.textPrimary),
        ),
      ),
    );
  }
}

class _EarnedBadge extends StatelessWidget {
  const _EarnedBadge({
    required this.achievement,
    required this.dateLabel,
    required this.onTap,
  });

  final Achievement achievement;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isNew = achievement.isNew;
    return Pressable(
      onTap: onTap,
      borderRadius: KRadius.lg,
      semanticLabel:
          '${achievement.title}. ${achievement.description}. Earned $dateLabel${isNew ? '. New' : ''}',
      child: KCard(
        padding: const EdgeInsets.all(14),
        border: isNew ? Border.all(color: KColor.ember.withValues(alpha: 0.45), width: 1) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Medallion(id: achievement.id, size: 44, state: _MedalState.earned),
                const Spacer(),
                if (isNew) _NewPill(label: 'New', color: KColor.ember),
              ],
            ),
            const SizedBox(height: KSpacing.md),
            Text(achievement.title, style: KText.h3.copyWith(fontSize: 13.5)),
            const SizedBox(height: 3),
            Text(achievement.description, style: KText.caption.copyWith(fontSize: 11.5)),
            const SizedBox(height: KSpacing.sm),
            Text(
              dateLabel,
              style: KText.caption.copyWith(fontSize: 11, color: KColor.textMuted, fontFeatures: _kTabular),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pulsing Badge Widget (Micro-animation) ───────────────────────────────────
// Newly unlocked badge: a one-time sheen sweeps across it on mount, then a
// thin accent ring breathes while it is still "new" (no glow). The breathing loop only runs
// when ambient motion is allowed (off under reduced motion and in tests), is
// muted by TickerMode when the route is covered, and stops for good once the
// badge is no longer new (this widget is removed).

class _PulsingBadge extends StatefulWidget {
  final Widget child;
  const _PulsingBadge({required this.child});

  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge> with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _sheen;
  bool _sheenStarted = false;
  bool _pulseDone = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: KMotion.celebrate);
    _sheen = AnimationController(vsync: this, duration: KMotion.celebrate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KMotion.ambientAllowed(context)) {
      // A few breaths, then rest lit: an endless loop kept the screen
      // producing frames for as long as a badge was "new".
      if (!_pulse.isAnimating && !_pulseDone) {
        _pulseDone = true;
        _pulse.repeat(reverse: true, count: 6).whenCompleteOrCancel(() {
          if (mounted && !_pulse.isAnimating) _pulse.value = 1;
        });
      }
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
    if (!_sheenStarted) {
      _sheenStarted = true;
      if (!KMotion.reduced(context)) {
        _sheen.forward();
      } else {
        _sheen.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              // Own layer, so a breath repaints only the ring, not the badge.
              child: RepaintBoundary(
                child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: KRadius.lg,
                    border: Border.all(
                      color: KColor.ember.withValues(alpha: 0.2 + 0.4 * _pulse.value),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
