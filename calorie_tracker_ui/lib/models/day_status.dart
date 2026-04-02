import 'package:flutter/material.dart';
import '../models/day_log.dart';
import '../services/nutrition_target_engine.dart';

// ─── DayOutcome ───────────────────────────────────────────────────────────────
//
// Classifies the current state of a logged day.
//
// Design rules:
//   • All thresholds are TARGET-RELATIVE. No hardcoded absolute values.
//   • Time is a SOFT signal only — used to distinguish "in-progress" from
//     "done" but never the primary classification axis.
//   • Meal count is a stronger signal than clock time for "completeness".
//   • The labels must be trustworthy — no stupid misclassification from late
//     loggers or users who eat late.

enum DayOutcome {
  hitCaloriesAndProtein,
  hitCaloriesMissedProtein,
  hitProteinOverCalories,
  underCaloriesUnderProtein,
  overCaloriesSignificantly,
  veryGoodFatLoss,
  maintenanceLike,
  incomplete,
  unlogged,
}

// ─── DayOutcomeResult ─────────────────────────────────────────────────────────

class DayOutcomeResult {
  final DayOutcome outcome;
  final String     label;
  final String     emoji;
  final Color      color;
  final bool       isPositive;
  final String     note;
  final bool       trained;

  const DayOutcomeResult({
    required this.outcome,
    required this.label,
    required this.emoji,
    required this.color,
    required this.isPositive,
    required this.note,
    this.trained = false,
  });
}

// ─── DayStatusEngine ─────────────────────────────────────────────────────────

class DayStatusEngine {
  DayStatusEngine._();

  static DayOutcomeResult classify(
    DayLog    log,
    DayTarget target, {
    DateTime? now,
  }) {
    // ── Step 0: empty check ───────────────────────────────────────────────────
    if (log.isEmpty) return _result(DayOutcome.unlogged);

    final cal       = log.totalCaloriesMid;
    final pro       = log.totalProteinMid;
    final calRat    = cal / target.calories.clamp(1, double.infinity);
    final proRat    = pro / target.protein .clamp(1, double.infinity);
    final hour      = (now ?? DateTime.now()).hour;
    final mealCount = _countMeals(log);
    final trained   = log.gymDay?.didGym == true;

    final progressScore = _dayProgressScore(hour: hour, mealCount: mealCount, calRat: calRat, proRat: proRat);
    final looksComplete = progressScore >= 0.68;
    final caloriesHit = calRat >= 0.88 && calRat <= 1.08;
    final proteinHit = proRat >= 0.9;
    final caloriesOver = calRat > 1.08;
    final caloriesVeryOver = calRat > 1.18;
    final underBoth = calRat < 0.72 && proRat < 0.72;

    if (caloriesVeryOver) return _result(DayOutcome.overCaloriesSignificantly, trained: trained);
    if (proteinHit && calRat >= 0.84 && calRat <= 1.00) return _result(DayOutcome.veryGoodFatLoss, trained: trained);
    if (caloriesHit && proteinHit) return _result(DayOutcome.hitCaloriesAndProtein, trained: trained);
    if (caloriesHit && proRat < 0.82 && looksComplete) return _result(DayOutcome.hitCaloriesMissedProtein, trained: trained);
    if (proteinHit && caloriesOver) return _result(DayOutcome.hitProteinOverCalories, trained: trained);
    if (caloriesOver && !caloriesVeryOver) return _result(DayOutcome.maintenanceLike, trained: trained);
    if (underBoth && looksComplete) return _result(DayOutcome.underCaloriesUnderProtein, trained: trained);
    return _result(DayOutcome.incomplete, trained: trained);
  }

  static double _dayProgressScore({
    required int hour,
    required int mealCount,
    required double calRat,
    required double proRat,
  }) {
    final timeSignal = (hour / 24).clamp(0.25, 1.0);
    final mealSignal = (mealCount / 4).clamp(0.0, 1.0);
    final intakeSignal = ((calRat + proRat) / 2).clamp(0.0, 1.0);
    return (timeSignal * 0.2) + (mealSignal * 0.45) + (intakeSignal * 0.35);
  }

  static int _countMeals(DayLog log) {
    int count = 0;
    for (final s in MealSection.values) {
      count += log.entriesFor(s).length;
    }
    return count;
  }

  static DayOutcomeResult _result(DayOutcome outcome, {bool trained = false}) => switch (outcome) {
        DayOutcome.hitCaloriesAndProtein => const DayOutcomeResult(
            outcome:    DayOutcome.hitCaloriesAndProtein,
            label:      'Targets hit',
            emoji:      '✓',
            color:      Color(0xFF60A5FA),
            isPositive: true,
            note:       'Calories and protein both landed well.',
            trained:    false,
          ),
        DayOutcome.hitCaloriesMissedProtein => DayOutcomeResult(
            outcome:    DayOutcome.hitCaloriesMissedProtein,
            label:      trained ? 'Trained, protein missed' : 'Calories hit, protein missed',
            emoji:      '⚡',
            color:      Color(0xFFA78BFA),
            isPositive: false,
            note:       trained ? 'You trained today, so the protein miss matters more.' : 'Calories were fine, but protein fell short.',
            trained:    trained,
          ),
        DayOutcome.hitProteinOverCalories => DayOutcomeResult(
            outcome:    DayOutcome.hitProteinOverCalories,
            label:      trained ? 'Trained, calories high' : 'Protein hit, calories high',
            emoji:      '↗',
            color:      Color(0xFFFFB347),
            isPositive: false,
            note:       'Protein was covered, but calories drifted high.',
            trained:    trained,
          ),
        DayOutcome.underCaloriesUnderProtein => DayOutcomeResult(
            outcome:    DayOutcome.underCaloriesUnderProtein,
            label:      trained ? 'Trained, under-fuelled' : 'Under on both',
            emoji:      '…',
            color:      Color(0xFF9CA3AF),
            isPositive: false,
            note:       trained ? 'Training day recovery likely needs more food and protein.' : 'This day likely needed one more proper meal.',
            trained:    trained,
          ),
        DayOutcome.overCaloriesSignificantly => DayOutcomeResult(
            outcome:    DayOutcome.overCaloriesSignificantly,
            label:      'Significantly over',
            emoji:      '⚠',
            color:      Color(0xFFFF8C42),
            isPositive: false,
            note:       'This landed clearly above your fat-loss target.',
            trained:    trained,
          ),
        DayOutcome.veryGoodFatLoss => DayOutcomeResult(
            outcome:    DayOutcome.veryGoodFatLoss,
            label:      trained ? 'Strong training day' : 'Very good fat-loss day',
            emoji:      '🔥',
            color:      Color(0xFF52B788),
            isPositive: true,
            note:       trained ? 'You trained and still covered protein without overshooting calories.' : 'Protein was covered without overshooting calories.',
            trained:    trained,
          ),
        DayOutcome.maintenanceLike => DayOutcomeResult(
            outcome:    DayOutcome.maintenanceLike,
            label:      'Maintenance-like',
            emoji:      '〜',
            color:      Color(0xFFFFB347),
            isPositive: false,
            note:       'Close to maintenance rather than a fat-loss finish.',
            trained:    trained,
          ),
        DayOutcome.incomplete => DayOutcomeResult(
            outcome:    DayOutcome.incomplete,
            label:      'In progress',
            emoji:      '…',
            color:      Color(0xFF4B5563),
            isPositive: true,
            note:       '',
            trained:    trained,
          ),
        DayOutcome.unlogged => const DayOutcomeResult(
            outcome:    DayOutcome.unlogged,
            label:      'No meals logged',
            emoji:      '—',
            color:      Color(0xFF4B5563),
            isPositive: false,
            note:       '',
          ),
      };
}
