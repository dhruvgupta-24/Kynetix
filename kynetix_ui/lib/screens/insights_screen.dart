import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/insights_models.dart';
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../services/insights_report_service.dart';
import '../services/insights_engine.dart';
import '../services/nutrition_target_engine.dart';
import '../services/workout_service.dart';
import '../screens/onboarding_screen.dart'; // UserProfile

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _selectedTab = 0; // 0 = Week, 1 = Month, 2 = Year

  // Selected keys for period navigation
  String? _selectedWeekKey;
  String? _selectedMonthKey;
  String? _selectedYearKey;

  // Cache achievements in local state to preserve "isNew" flag during this screen session
  List<Achievement> _localAchievements = [];

  bool _isRecomputing = false;

  @override
  void initState() {
    super.initState();
    _localAchievements = List.from(InsightsReportService.instance.achievements);
    _initializeSelectedKeys();

    // Mark achievements as viewed after a 3-second delay so user sees the pulse animation
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        InsightsReportService.instance.markAchievementsViewed();
      }
    });
  }

  void _initializeSelectedKeys() {
    final weeklyKeys = InsightsReportService.instance.weeklyCache.keys.toList()..sort();
    final monthlyKeys = InsightsReportService.instance.monthlyCache.keys.toList()..sort();
    final yearlyKeys = InsightsReportService.instance.yearlyCache.keys.toList()..sort();

    final now = DateTime.now();
    _selectedWeekKey = weeklyKeys.isNotEmpty ? weeklyKeys.last : InsightsEngine.weekKeyOf(now);
    _selectedMonthKey = monthlyKeys.isNotEmpty ? monthlyKeys.last : InsightsEngine.monthKeyOf(now);
    _selectedYearKey = yearlyKeys.isNotEmpty ? yearlyKeys.last : now.year.toString();
  }

  Future<void> _handleRefresh() async {
    if (_isRecomputing) return;
    setState(() => _isRecomputing = true);
    kHapticMedium();
    try {
      final profile = currentUserProfile;
      if (profile != null) {
        await InsightsReportService.instance.forceRecompute(profile);
        // Refresh local achievements copy in case new ones were earned
        setState(() {
          _localAchievements = List.from(InsightsReportService.instance.achievements);
          _initializeSelectedKeys();
        });
      }
    } catch (e) {
      debugPrint('[InsightsScreen] Refresh error: $e');
    } finally {
      if (mounted) {
        setState(() => _isRecomputing = false);
      }
    }
  }

  // ─── Formatting helpers ─────────────────────────────────────────────────────

  String _formatWeekKey(String weekKey, WeeklyReport? report) {
    if (report == null) return weekKey;
    final start = report.weekStart;
    final end = start.add(const Duration(days: 6));
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[start.month - 1]} ${start.day} – ${months[end.month - 1]} ${end.day}, ${start.year}';
  }

  String _formatMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length < 2) return monthKey;
    final year = parts[0];
    final monthInt = int.tryParse(parts[1]) ?? 1;
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[monthInt - 1]} $year';
  }

  String _friendlyAge(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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

  // ─── Tabs UI ────────────────────────────────────────────────────────────────

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = (constraints.maxWidth) / 3;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: _selectedTab * tabWidth,
                width: tabWidth,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: KColor.cardHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildTabButton(0, 'Week'),
                  _buildTabButton(1, 'Month'),
                  _buildTabButton(2, 'Year'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          kHapticSelect();
          setState(() {
            _selectedTab = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: isSelected ? Colors.white : KColor.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
              fontFamily: 'Inter',
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  // ─── Shared UI blocks ────────────────────────────────────────────────────────

  Widget _buildConsistencyHeroCard(ConsistencyScore score, PeriodDelta? delta) {
    final loggingStreak = InsightsReportService.instance.getLoggingStreak();
    final profile = currentUserProfile;
    final proteinStreak = profile != null ? InsightsReportService.instance.getProteinStreak(profile) : 0;
    final calorieStreak = profile != null ? InsightsReportService.instance.getCalorieStreak(profile) : 0;

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CONSISTENCY SCORE', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${score.score}', style: KText.display.copyWith(fontSize: 36, color: KColor.green)),
                      const Text('/100', style: TextStyle(fontSize: 14, color: KColor.textMuted)),
                      const SizedBox(width: 8),
                      if (delta?.consistencyScoreDelta != null)
                        _buildDeltaChip(delta!.consistencyScoreDelta!),
                    ],
                  ),
                ],
              ),
              // Big circle progress indicator
              SizedBox(
                width: 64,
                height: 64,
                child: KGradientCircularProgress(
                  progress: score.score / 100.0,
                  strokeWidth: 6,
                  colors: const [KColor.greenDark, KColor.green],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: KColor.divider, height: 1),
          const SizedBox(height: 12),
          _buildMetricRow('Tracking Consistency', score.loggingConsistency, '${(score.loggingConsistency * 100).round()}%', KColor.blue),
          _buildMetricRow('Protein Target Hit Rate', score.proteinAdherence, '${(score.proteinAdherence * 100).round()}%', KColor.protein),
          _buildMetricRow('Calorie Target Hit Rate', score.calorieAdherence, '${(score.calorieAdherence * 100).round()}%', KColor.calorie),
          _buildMetricRow('Workout Consistency', score.gymAttendance, '${(score.gymAttendance * 100).round()}%', KColor.amber),
          if (score.mealQuality > 0)
            _buildMetricRow('Meal Quality', score.mealQuality, '${(score.mealQuality * 100).round()}', const Color(0xFFA78BFA)),
          const SizedBox(height: 16),
          const Divider(color: KColor.divider, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStreakChip('Log Streak', loggingStreak, KColor.blue, '🔥'),
              const SizedBox(width: 8),
              _buildStreakChip('Protein Streak', proteinStreak, KColor.protein, '⚡'),
              const SizedBox(width: 8),
              _buildStreakChip('Calorie Streak', calorieStreak, KColor.calorie, '🎯'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStreakChip(String label, int count, Color color, String emoji) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Column(
          children: [
            Text(
              '$emoji $count ${count == 1 ? "day" : "days"}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 8,
                color: KColor.textMuted,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, double value, String detail, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
            Text(detail, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: KColor.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDeltaChip(int delta) {
    final isPositive = delta > 0;
    if (delta == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPositive
            ? const Color(0xFF52B788).withValues(alpha: 0.12)
            : const Color(0xFFFF4D4D).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${isPositive ? '+' : ''}$delta ${isPositive ? '↑' : '↓'}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isPositive ? const Color(0xFF52B788) : const Color(0xFFFF4D4D),
        ),
      ),
    );
  }

  Widget _buildTopImprovementCard(TopImprovement? improvement) {
    if (improvement == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(KSpacing.lg),
        decoration: BoxDecoration(
          color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          children: [
            const Text('🚀', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOP IMPROVEMENT', style: TextStyle(fontSize: 9, color: KColor.green, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text(
                    improvement.label,
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegressionsList(List<RegressionAlert> regressions) {
    if (regressions.isEmpty) return const SizedBox.shrink();
    return Column(
      children: regressions.map((alert) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(KSpacing.lg),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.25), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Area to Improve', style: TextStyle(fontSize: 9, color: KColor.amber, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(
                        alert.message,
                        style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDeltaStrips(PeriodDelta? delta) {
    if (delta == null) return const SizedBox.shrink();

    Widget buildStrip(String label, double? dVal) {
      if (dVal == null || dVal == 0.0) return const SizedBox.shrink();
      final isPositive = dVal > 0;
      final pct = (dVal * 100).round().abs();
      final color = isPositive ? KColor.green : KColor.danger;
      final sign = isPositive ? '+' : '-';
      final arrow = isPositive ? '↑' : '↓';

      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Text(
          '$label $sign$pct% $arrow',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            buildStrip('Protein', delta.proteinAdherenceDelta),
            buildStrip('Calories', delta.calorieAdherenceDelta),
            buildStrip('Logging', delta.loggingConsistencyDelta),
            if (delta.mealQualityDelta != null)
              buildStrip('Meal Quality', delta.mealQualityDelta! / 100.0),
          ],
        ),
      ),
    );
  }

  // ─── Week View ──────────────────────────────────────────────────────────────

  Widget _buildWeekView() {
    final cache = InsightsReportService.instance.weeklyCache;
    final report = cache[_selectedWeekKey];

    if (report == null) {
      return _buildEmptyState('No report generated for this week yet. Log meals 3+ days to compute insights.');
    }

    final aiSummary = InsightsReportService.instance.aiSummaryFor(report.weekKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPeriodNavRow(
          label: _formatWeekKey(report.weekKey, report),
          onPrev: () => _navigateWeek(false),
          onNext: () => _navigateWeek(true),
        ),
        const SizedBox(height: 12),

        // AI Narrative card (highest visual priority)
        if (aiSummary != null && aiSummary.narrative.isNotEmpty && !aiSummary.isStale) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2D6A4F).withValues(alpha: 0.25),
                  KColor.card.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.2), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🧠', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      'KYNO COACH INSIGHT',
                      style: KText.label.copyWith(color: KColor.green, letterSpacing: 1.0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  aiSummary.narrative,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        _buildConsistencyHeroCard(report.consistencyScore, report.deltaVsPrior),
        _buildDeltaStrips(report.deltaVsPrior),
        _buildTopImprovementCard(report.topImprovement),
        _buildRegressionsList(report.regressions),
        const SizedBox(height: 16),

        _buildGymAttendanceRow(report),
        const SizedBox(height: 16),

        _buildMacroSummaryRow(report.avgCalories, report.avgProtein, report.avgFiber),
        const SizedBox(height: 16),

        _buildOutcomeDistributionRow(report),
      ],
    );
  }

  Widget _buildPeriodNavRow({required String label, required VoidCallback onPrev, required VoidCallback onNext}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
          onPressed: onPrev,
        ),
        Expanded(
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
          onPressed: onNext,
        ),
      ],
    );
  }

  Widget _buildGymAttendanceRow(WeeklyReport report) {
    final weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WORKOUT CONSISTENCY', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final date = report.weekStart.add(Duration(days: i));
              final dKey = InsightsEngine.dateKeyOf(date);
              final log = dayLogStore[dKey];
              final didGym = log?.gymDay?.didGym == true;

              return Column(
                children: [
                  Text(weekdays[i], style: const TextStyle(fontSize: 11, color: KColor.textSecondary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: didGym ? KColor.green.withValues(alpha: 0.15) : KColor.border,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: didGym ? KColor.green : Colors.transparent,
                        width: didGym ? 1.5 : 0,
                      ),
                    ),
                    child: Center(
                      child: didGym
                          ? const Icon(Icons.check_rounded, size: 16, color: KColor.green)
                          : const Icon(Icons.close_rounded, size: 14, color: KColor.textMuted),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSummaryRow(double calories, double protein, double fiber) {
    return Row(
      children: [
        Expanded(
          child: KCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('CALORIES', style: TextStyle(fontSize: 9, color: KColor.textMuted, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${calories.round()}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: KColor.calorie)),
                const Text('kcal/day', style: TextStyle(fontSize: 9, color: KColor.textSecondary)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: KCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('PROTEIN', style: TextStyle(fontSize: 9, color: KColor.textMuted, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${protein.round()}g', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: KColor.protein)),
                const Text('protein/day', style: TextStyle(fontSize: 9, color: KColor.textSecondary)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: KCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('FIBER', style: TextStyle(fontSize: 9, color: KColor.textMuted, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${fiber.round()}g', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: KColor.blue)),
                const Text('fiber/day', style: TextStyle(fontSize: 9, color: KColor.textSecondary)),
              ],
            ),
          ),
        ),
      ],
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
        final isGymDay = log.gymDay?.didGym == true;
        final target = NutritionTargetEngine.instance.dayTarget(
          currentUserProfile!,
          isGymDay: isGymDay,
          workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
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

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DAILY GOAL STATUS', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Horizontal stacked progress bar representing outcomes in the week
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: counts.entries.map((entry) {
                  final outcome = entry.key;
                  final count = entry.value;
                  final details = _getOutcomeDetails(outcome);

                  return Expanded(
                    flex: count,
                    child: Container(color: details.color),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend list
          Column(
            children: counts.entries.map((entry) {
              final outcome = entry.key;
              final count = entry.value;
              final details = _getOutcomeDetails(outcome);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: details.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(details.emoji, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        details.label,
                        style: const TextStyle(fontSize: 11, color: KColor.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '$count ${count == 1 ? 'day' : 'days'}',
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  ({String label, String emoji, Color color}) _getOutcomeDetails(DayOutcome outcome) {
    return switch (outcome) {
      DayOutcome.hitCaloriesAndProtein => (label: 'Calories & Protein Met', emoji: '✨', color: KColor.green),
      DayOutcome.hitCaloriesMissedProtein => (label: 'Hit Calories, Low Protein', emoji: '🎯', color: KColor.amber),
      DayOutcome.hitProteinOverCalories => (label: 'Protein Met, High Calories', emoji: '🥩', color: KColor.calorie),
      DayOutcome.underCaloriesUnderProtein => (label: 'Under Calories & Protein', emoji: '📉', color: KColor.blue),
      DayOutcome.overCaloriesSignificantly => (label: 'Calorie Surplus', emoji: '🍕', color: KColor.danger),
      DayOutcome.veryGoodFatLoss => (label: 'Fat Loss Optimal', emoji: '🔥', color: KColor.green),
      DayOutcome.maintenanceLike => (label: 'Maintenance Day', emoji: '⚖️', color: KColor.textSecondary),
      DayOutcome.incomplete => (label: 'Incomplete Log', emoji: '⏳', color: KColor.textMuted),
      DayOutcome.unlogged => (label: 'Not Logged', emoji: '💤', color: KColor.textDisabled),
    };
  }

  // ─── Month View ─────────────────────────────────────────────────────────────

  Widget _buildMonthView() {
    final cache = InsightsReportService.instance.monthlyCache;
    final report = cache[_selectedMonthKey];

    if (report == null) {
      return _buildEmptyState('No report generated for this month yet. Log meals 10+ days to compute insights.');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPeriodNavRow(
          label: _formatMonthKey(report.monthKey),
          onPrev: () => _navigateMonth(false),
          onNext: () => _navigateMonth(true),
        ),
        const SizedBox(height: 12),

        _buildConsistencyHeroCard(report.consistencyScore, report.deltaVsPrior),
        _buildDeltaStrips(report.deltaVsPrior),
        _buildTopImprovementCard(report.topImprovement),
        _buildRegressionsList(report.regressions),
        const SizedBox(height: 16),

        if (monthWeeks.isNotEmpty) ...[
          _buildWeeklyScoresSparkline(monthWeeks),
          const SizedBox(height: 16),
        ],

        _buildBestWorstWeeks(report),
        const SizedBox(height: 16),

        _buildOverviewTotalsCard(
          logged: report.totalLoggedDays,
          maxDays: DateTime(year, month + 1, 0).day,
          gym: report.totalGymDays,
        ),
      ],
    );
  }

  Widget _buildWeeklyScoresSparkline(List<WeeklyReport> reports) {
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WEEKLY SCORES IN MONTH', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: reports.map((r) {
                final score = r.consistencyScore.score;
                final heightFraction = score / 100.0;
                final parts = r.weekKey.split('-W');
                final wNum = parts.length > 1 ? parts[1] : '';

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('$score', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Container(
                        height: 60 * heightFraction,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [KColor.greenDark, KColor.green],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('W$wNum', style: const TextStyle(fontSize: 9, color: KColor.textSecondary)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBestWorstWeeks(MonthlyReport report) {
    final bestWeek = report.bestWeekKey != null ? InsightsReportService.instance.weeklyFor(report.bestWeekKey!) : null;
    final worstWeek = report.worstWeekKey != null ? InsightsReportService.instance.weeklyFor(report.worstWeekKey!) : null;

    if (bestWeek == null && worstWeek == null) return const SizedBox.shrink();

    return Row(
      children: [
        if (bestWeek != null)
          Expanded(
            child: KCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🏆', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      const Text('BEST WEEK', style: TextStyle(fontSize: 9, color: KColor.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Week ${bestWeek.weekKey.split('-W')[1]}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Score: ${bestWeek.consistencyScore.score}', style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                ],
              ),
            ),
          ),
        if (bestWeek != null && worstWeek != null) const SizedBox(width: 8),
        if (worstWeek != null)
          Expanded(
            child: KCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⏳', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      const Text('WORST WEEK', style: TextStyle(fontSize: 9, color: KColor.calorie, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Week ${worstWeek.weekKey.split('-W')[1]}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Score: ${worstWeek.consistencyScore.score}', style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOverviewTotalsCard({required int logged, required int maxDays, required int gym}) {
    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MONTHLY TOTALS', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Logged Days', style: TextStyle(fontSize: 11, color: KColor.textSecondary)),
                  const SizedBox(height: 4),
                  Text('$logged / $maxDays days', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gym Sessions', style: TextStyle(fontSize: 11, color: KColor.textSecondary)),
                  const SizedBox(height: 4),
                  Text('$gym workouts', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Year View ──────────────────────────────────────────────────────────────

  Widget _buildYearView() {
    final cache = InsightsReportService.instance.yearlyCache;
    final report = cache[_selectedYearKey];

    if (report == null) {
      return _buildEmptyState('No report generated for this year yet. Log meals 60+ days to compute insights.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPeriodNavRow(
          label: 'Year ${report.yearKey}',
          onPrev: () => _navigateYear(false),
          onNext: () => _navigateYear(true),
        ),
        const SizedBox(height: 12),

        _buildConsistencyHeroCard(report.consistencyScore, null),
        const SizedBox(height: 16),

        _buildMonthlyScoresSparkline(report.monthlyScores),
        const SizedBox(height: 16),

        _buildBestWorstMonths(report),
        const SizedBox(height: 16),

        _buildOverviewTotalsCard(
          logged: report.totalLoggedDays,
          maxDays: 365,
          gym: report.totalGymDays,
        ),
      ],
    );
  }

  Widget _buildMonthlyScoresSparkline(Map<String, int> monthlyScores) {
    if (monthlyScores.isEmpty) return const SizedBox.shrink();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final sortedMonths = monthlyScores.keys.toList()..sort();

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MONTHLY SCORES IN YEAR', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sortedMonths.length,
              itemBuilder: (context, index) {
                final mKey = sortedMonths[index];
                final score = monthlyScores[mKey] ?? 0;
                final heightFraction = score / 100.0;
                final parts = mKey.split('-');
                final mInt = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
                final mLabel = months[mInt - 1];

                return Container(
                  width: 48,
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('$score', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Container(
                        height: 60 * heightFraction,
                        width: 14,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [KColor.greenDark, KColor.green],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(mLabel, style: const TextStyle(fontSize: 9, color: KColor.textSecondary)),
                    ],
                  ),
                );
              },
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
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return months[mInt - 1];
    }

    return Row(
      children: [
        if (bestKey != null)
          Expanded(
            child: KCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🏆', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      const Text('BEST MONTH', style: TextStyle(fontSize: 9, color: KColor.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(mName(bestKey), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Score: ${report.monthlyScores[bestKey]}', style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                ],
              ),
            ),
          ),
        if (bestKey != null && worstKey != null) const SizedBox(width: 8),
        if (worstKey != null)
          Expanded(
            child: KCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⏳', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      const Text('WORST MONTH', style: TextStyle(fontSize: 9, color: KColor.calorie, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(mName(worstKey), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Score: ${report.monthlyScores[worstKey]}', style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── Personal Bests ─────────────────────────────────────────────────────────

  Widget _buildPersonalBestsCard(PersonalBests? pbs, WeeklyReport? report) {
    if (pbs == null) return const SizedBox.shrink();

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String formatDateKey(String? dateKey) {
      if (dateKey == null) return '—';
      final parts = dateKey.split('-');
      if (parts.length < 3) return dateKey;
      final m = int.tryParse(parts[1]) ?? 1;
      final d = int.tryParse(parts[2]) ?? 1;
      return '${months[m - 1]} $d';
    }

    String formatWeekKey(String? wKey) {
      if (wKey == null) return '—';
      final parts = wKey.split('-W');
      if (parts.length < 2) return wKey;
      return 'Week ${parts[1]}';
    }

    String formatMonthKey(String? mKey) {
      if (mKey == null) return '—';
      final parts = mKey.split('-');
      if (parts.length < 2) return mKey;
      final m = int.tryParse(parts[1]) ?? 1;
      return months[m - 1];
    }

    // Helper to render PB Row
    Widget buildPbRow(String label, String value, String dateDesc, bool highlight) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                  const SizedBox(height: 2),
                  Text(dateDesc, style: const TextStyle(fontSize: 9, color: KColor.textMuted)),
                ],
              ),
            ),
            Row(
              children: [
                if (highlight)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: KColor.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                    child: const Text('🏆 NEW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: KColor.green)),
                  ),
                Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ],
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

    return KCard(
      padding: const EdgeInsets.all(KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PERSONAL BESTS', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          buildPbRow(
            'Protein Peak',
            pbs.highestProteinDay != null ? '${pbs.highestProteinDay!.round()}g' : '—',
            formatDateKey(pbs.highestProteinDayKey),
            isHighestProteinThisWeek,
          ),
          const Divider(color: KColor.divider, height: 16),
          buildPbRow(
            'Longest Tracking Streak',
            '${pbs.longestLoggingStreak} days',
            'All-time consecutive tracking',
            false,
          ),
          const Divider(color: KColor.divider, height: 16),
          buildPbRow(
            'Best Weekly Food Quality',
            pbs.bestMealQualityWeekScore != null ? '${pbs.bestMealQualityWeekScore}/100' : '—',
            formatWeekKey(pbs.bestMealQualityWeekKey),
            isBestWeekThisWeek,
          ),
          const Divider(color: KColor.divider, height: 16),
          buildPbRow(
            'Step Record (Week)',
            pbs.highestAvgStepsWeek != null ? '${pbs.highestAvgStepsWeek}/day avg' : '—',
            formatWeekKey(pbs.highestAvgStepsWeekKey),
            false,
          ),
          const Divider(color: KColor.divider, height: 16),
          buildPbRow(
            'Most Consistent Month',
            pbs.mostConsistentMonthScore != null ? '${pbs.mostConsistentMonthScore}/100' : '—',
            formatMonthKey(pbs.mostConsistentMonthKey),
            false,
          ),
        ],
      ),
    );
  }

  Widget _buildExercisePersonalRecordsCard() {
    final prs = WorkoutService.instance.getPersonalRecords();
    if (prs.isEmpty) {
      return const SizedBox.shrink();
    }

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String formatDateKey(String? dateKey) {
      if (dateKey == null) return '—';
      final parts = dateKey.split('-');
      if (parts.length < 3) return dateKey;
      final m = int.tryParse(parts[1]) ?? 1;
      final d = int.tryParse(parts[2]) ?? 1;
      return '${months[m - 1]} $d';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EXERCISE PERSONAL RECORDS',
          style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Column(
          children: prs.map((pr) {
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

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: KCard(
                padding: const EdgeInsets.all(KSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          pr.exerciseName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: KColor.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🏆 RECORD',
                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: KColor.green),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildPrDetailRow('Best Weight', '${pr.bestWeight.toStringAsFixed(pr.bestWeight == pr.bestWeight.truncateToDouble() ? 0 : 1)} kg', formatDateKey(pr.bestWeightDate)),
                    const Divider(color: KColor.divider, height: 12),
                    _buildPrDetailRow('Best Volume', '${pr.bestVolume.toStringAsFixed(pr.bestVolume == pr.bestVolume.truncateToDouble() ? 0 : 1)} kg', formatDateKey(pr.bestVolumeDate)),
                    const Divider(color: KColor.divider, height: 12),
                    _buildPrDetailRow('Best Est. 1RM', '${pr.bestEstimatedOneRepMax.toStringAsFixed(pr.bestEstimatedOneRepMax == pr.bestEstimatedOneRepMax.truncateToDouble() ? 0 : 1)} kg', formatDateKey(pr.bestEstimatedOneRepMaxDate)),
                    if (topReps > 0) ...[
                      const Divider(color: KColor.divider, height: 12),
                      _buildPrDetailRow(
                        'Most Reps',
                        '$topReps reps @ ${topRepsWeight.toStringAsFixed(topRepsWeight == topRepsWeight.truncateToDouble() ? 0 : 1)} kg',
                        formatDateKey(topRepsDate),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPrDetailRow(String label, String value, String dateDesc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
            const SizedBox(height: 2),
            Text(dateDesc, style: const TextStyle(fontSize: 9, color: KColor.textMuted)),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
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

    return FutureBuilder<bool>(
      future: wService.hasRecoveryDeterioration(),
      builder: (context, snapshot) {
        final recoveryDeteriorated = snapshot.data ?? false;
        final hasPlateaus = plateaus.isNotEmpty;
        final hasAnyAlert = hasPlateaus || recoveryDeteriorated;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WORKOUT PERFORMANCE & INSIGHTS',
              style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            if (hasAnyAlert) ...[
              if (recoveryDeteriorated)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(KSpacing.lg),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4D4D).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFF4D4D).withValues(alpha: 0.25), width: 1),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🚨', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recovery Alert', style: TextStyle(fontSize: 9, color: Color(0xFFFF4D4D), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text(
                              'Low readiness scores detected for 3 consecutive days. Consider a deload or prioritizing sleep and active recovery.',
                              style: TextStyle(fontSize: 12.5, color: Colors.white, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (hasPlateaus)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(KSpacing.lg),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB347).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.25), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚠️', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Plateau Warning', style: TextStyle(fontSize: 9, color: KColor.amber, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text(
                              'Progress stalled on: ${plateaus.join(", ")}. Consider varying exercise order, changing reps, or adding a deload.',
                              style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            KCard(
              padding: const EdgeInsets.all(KSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MUSCLE GROUP TRENDS', style: TextStyle(fontSize: 11, color: KColor.textMuted, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (freqTrends.isEmpty)
                    const Text('No training frequency data yet.', style: TextStyle(fontSize: 12, color: KColor.textSecondary))
                  else
                    Column(
                      children: freqTrends.entries.map((entry) {
                        final muscle = entry.key;
                        final freq = entry.value;
                        final wow = wowVolume[muscle] ?? 0.0;
                        final wowStr = wow >= 0 ? '+${wow.toStringAsFixed(0)}%' : '${wow.toStringAsFixed(0)}%';
                        final wowColor = wow >= 0 ? KColor.green : KColor.danger;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(muscle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 2),
                                  Text('Avg Frequency: ${freq.toStringAsFixed(1)}x/week', style: const TextStyle(fontSize: 10, color: KColor.textMuted)),
                                ],
                              ),
                              Row(
                                children: [
                                  const Text(
                                    'WoW Vol: ',
                                    style: TextStyle(fontSize: 10, color: KColor.textMuted),
                                  ),
                                  Text(
                                    wowStr,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: wowColor),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Achievements UI ────────────────────────────────────────────────────────

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ACHIEVEMENTS',
          style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // 1. Earned achievements
        if (earned.isNotEmpty) ...[
          const Text('EARNED', style: TextStyle(fontSize: 10, color: KColor.textMuted, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Column(
            children: earned.reversed.map((achievement) {
              final isNew = achievement.isNew;
              final tile = Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: KCard(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Text(achievement.emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(achievement.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text(achievement.description, style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (isNew)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: KColor.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                              child: const Text('NEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: KColor.green)),
                            ),
                          Text(
                            _formatDate(achievement.earnedAt),
                            style: const TextStyle(fontSize: 10, color: KColor.textMuted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );

              return isNew ? _PulsingBadge(child: tile) : tile;
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // 2. In Progress achievements
        if (progressList.isNotEmpty) ...[
          const Text('IN PROGRESS', style: TextStyle(fontSize: 10, color: KColor.textMuted, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Column(
            children: progressList.map((progress) {
              final meta = AchievementRegistry.fromId(progress.id);
              if (meta == null) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: KCard(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(meta.emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(meta.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(height: 2),
                                Text(meta.description, style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            progress.label,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress.fraction,
                          minHeight: 4,
                          backgroundColor: KColor.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(KColor.green),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // 3. Locked achievements
        if (lockedIds.isNotEmpty) ...[
          const Text('LOCKED', style: TextStyle(fontSize: 10, color: KColor.textMuted, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Column(
            children: lockedIds.map((id) {
              final meta = AchievementRegistry.fromId(id);
              if (meta == null) return const SizedBox.shrink();

              return Opacity(
                opacity: 0.5,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: KCard(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Row(
                      children: [
                        Text(meta.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(meta.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(meta.description, style: const TextStyle(fontSize: 11, color: KColor.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: KCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('📊', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(
              msg,
              style: const TextStyle(color: KColor.textSecondary, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastComputed = InsightsReportService.instance.lastComputed;
    final weeklyReport = InsightsReportService.instance.weeklyFor(_selectedWeekKey ?? '');

    return Scaffold(
      backgroundColor: KColor.bg,
      appBar: AppBar(
        backgroundColor: KColor.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Insights & Progress',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: _isRecomputing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KColor.green,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _handleRefresh,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: KColor.green,
          backgroundColor: KColor.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            children: [
              // Data Freshness Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: KColor.green, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Last updated ${_friendlyAge(lastComputed)}',
                    style: const TextStyle(fontSize: 11, color: KColor.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildTabs(),
              const SizedBox(height: 16),

              // Sub-views based on Tab selection
              if (_selectedTab == 0)
                _buildWeekView()
              else if (_selectedTab == 1)
                _buildMonthView()
              else if (_selectedTab == 2)
                _buildYearView(),

              const SizedBox(height: 24),
              _buildPersonalBestsCard(InsightsReportService.instance.personalBests, weeklyReport),

              const SizedBox(height: 24),
              _buildExercisePersonalRecordsCard(),

              const SizedBox(height: 24),
              _buildWorkoutPerformanceInsights(),

              const SizedBox(height: 24),
              _buildAchievementsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pulsing Badge Widget (Micro-animation) ───────────────────────────────────

class _PulsingBadge extends StatefulWidget {
  final Widget child;
  const _PulsingBadge({required this.child});

  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + _ctrl.value * 0.015,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
