import '../models/day_log.dart';
import '../screens/onboarding_screen.dart';
import '../services/day_pattern_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/workout_service.dart';

// ─── MealSuggestion ───────────────────────────────────────────────────────────

class MealSuggestion {
  final String title;
  final String quantity;
  final String reason;
  final String? prefilledText;

  const MealSuggestion({
    required this.title,
    required this.quantity,
    required this.reason,
    this.prefilledText,
  });
}

// ─── MealSuggestionService ────────────────────────────────────────────────────
//
// Scoring-based "what to eat next" engine.
//
// Priority order (as specified):
//   1. Macro deficit fit     (40 pts)
//   2. Calorie fit           (20 pts)
//   3. Meal timing fit       (20 pts)
//   4. User familiarity      (10 pts)
//   5. Variety / recency     (10 pts)
//
// Anti-patterns (hard exclusions when protein gap is significant):
//   • Carb-heavy foods with < 10g protein are removed when protein gap > 25g.
//   • Recently eaten foods get a de-prioritization penalty.

class MealSuggestionService {
  const MealSuggestionService._();
  static const MealSuggestionService instance = MealSuggestionService._();

  List<MealSuggestion> suggestionsForDay({
    required DateTime date,
    required DayLog log,
    required DayTarget target,
    required UserProfile profile,
  }) {
    final remaining = _Remaining.compute(log, target);
    final sequencing = _mealSequencing(log, DateTime.now());
    final section = sequencing.targetSection;
    final history = _recentHistory(date);
    final patterns = DayPatternService.instance.snapshot(upTo: date);
    final ws = WorkoutService.instance;
    final bool isActuallyTraining = target.isTrainingDay;
    final bool isWorkoutDoneOrActive = 
        (ws.draftSession != null) || (ws.sessionFor(date) != null);
    final eatenToday = _foodsEatenToday(log);

    // ── State-aware shortcut paths ─────────────────────────────────────────
    //
    // Rather than always running the scoring engine, detect the macro state
    // first and apply targeted filtering before scoring.
    //
    //   State A: Both macros essentially covered → suggest stopping / light only.
    //   State B: Calories tight, protein still needed → lean protein only.
    //   State C: Normal (both low, or early in day) → full scoring engine.

    final calEssentiallyCovered = remaining.calories < 130;
    final protEssentiallyCovered = remaining.protein < 8;

    // STATE A: Both done — suggest stopping
    if (calEssentiallyCovered && protEssentiallyCovered) {
      return [
        MealSuggestion(
          title: 'You\'re basically done for today',
          quantity: 'Skip unnecessary snacking',
          reason:
              'Calories and protein are both covered. No extra meal is needed now.',
          prefilledText: null,
        ),
      ];
    }

    // STATE B: Calories tight but protein still needed → only lean options
    if (calEssentiallyCovered && !protEssentiallyCovered) {
      final leanProtein = _candidates
          .where(
            (c) =>
                c.isProteinFocused &&
                c.caloriesKcal <= 150 &&
                c.mealStyles.contains(_MealStyle.proteinCorrection),
          )
          .toList();
      return leanProtein
          .take(2)
          .map(
            (c) => MealSuggestion(
              title: c.title,
              quantity: c.quantity,
              reason:
                  'Calories are essentially done — only lean protein makes sense now. '
                  '${remaining.protein.toInt()}g protein still to go.',
              prefilledText: c.prefilledText,
            ),
          )
          .toList();
    }

    // STATE C: Normal scoring path
    final scored =
        _candidates
            .map(
              (c) => (
                candidate: c,
                score: _score(
                  c,
                  remaining,
                  sequencing,
                  isActuallyTraining,
                  eatenToday,
                  history,
                  patterns,
                  isWorkoutDoneOrActive,
                ),
              ),
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    // Hard filter: if protein gap > 25g, remove carb-heavy options with low protein
    final filtered = scored
        .where(
          (s) =>
              !(remaining.protein > 25 &&
                  s.candidate.isCarbHeavy &&
                  s.candidate.proteinG < 10),
        )
        .map((s) => s.candidate)
        .toList();

    // Also filter out carb-heavy foods when calories are nearly done (but protein isn't)
    final calFiltered = remaining.calories < 300
        ? filtered.where((c) => !c.isCarbHeavy || c.caloriesKcal < 250).toList()
        : filtered;

    final suggestions = <_SuggestionCandidate>[...calFiltered.take(3)];

    // History-based bonus: top recurring food in current section not already suggested
    if (history.length >= 2) {
      final historyCandidates = _historyCandidates(
        history,
        section,
        eatenToday,
      );
      for (final hc in historyCandidates) {
        if (!suggestions.any((c) => c.prefilledText == hc.prefilledText)) {
          suggestions.add(hc);
          break;
        }
      }
    }

    return suggestions
        .take(3)
        .map(
          (c) => _toSuggestion(c, remaining, target.isTrainingDay, sequencing),
        )
        .toList();
  }

  // ── Scoring ───────────────────────────────────────────────────────────────

  double _score(
    _SuggestionCandidate c,
    _Remaining r,
    _MealSequencing sequencing,
    bool isTrainingDay,
    Set<String> eatenToday,
    List<MealEntry> history,
    MealPatternSnapshot patterns,
    bool isWorkoutDoneOrActive,
  ) {
    var score = 0.0;
    final section = sequencing.targetSection;

    // Protein efficiency: g protein per 100 kcal. This is the key ranking signal
    // when the user needs protein but has limited calorie budget.
    // Whey: 20 g/100kcal | Egg whites: 20.6 | Tofu: 10.7 | Curd: 5.8 | Paneer: 5.1
    final efficiency = c.caloriesKcal > 0
        ? (c.proteinG / c.caloriesKcal * 100)
        : 0.0;

    // ─ 1. Macro deficit fit — efficiency-aware ──────────────────────────────
    if (r.protein > 25) {
      // Large protein gap: rank purely by protein-per-calorie efficiency.
      // This ensures whey/egg whites always win over paneer/dal when gap is high.
      if (efficiency >= 18) {
        score += 55; // elite: whey / egg whites
      } else if (efficiency >= 10) {
        score += 40; // good: tofu
      } else if (c.isProteinFocused && efficiency >= 5) {
        score += 28; // decent: paneer, soya, curd+whey
      } else if (c.isCarbHeavy) {
        score -= 30; // carbs when protein is the gap
      } else {
        score += 8;
      }
      // Absolute bonus for high absolute protein amount (closes gap faster)
      if (c.proteinG >= 22) {
        score += 8;
      }
    } else if (r.protein > 10) {
      // Mild protein gap — prefer protein-focused but carbs are acceptable
      if (efficiency >= 10) {
        score += 30;
      } else if (c.isProteinFocused) {
        score += 22;
      } else if (!c.isCarbHeavy) {
        score += 14;
      } else {
        score += 7;
      }
    } else {
      // Protein mostly covered — calorie match and variety take over
      score += 18;
    }

    // ─ 2. Calorie fit (20 pts) ─────────────────────────────────────────────
    if (r.calories <= 0) {
      score -= c.caloriesKcal > 100 ? 30 : 0; // over budget: penalise hard
    } else if (r.calories < 200 && c.caloriesKcal > 200) {
      score -= 20; // calories almost gone — high-cal foods don't fit
    } else if (c.caloriesKcal <= r.calories) {
      score += 20;
    } else if (c.caloriesKcal <= r.calories + 120) {
      score += 10;
    } else {
      score -= 5;
    }

    // ─ 3. Meal timing fit (20 pts cap) ───────────────────────────────────
    final timeBonus = c.timingBonus[_sectionKey(section)] ?? 0;
    score += timeBonus.clamp(0, 20).toDouble();

    if (sequencing.mode == _MealMode.meal &&
        c.mealStyles.contains(_MealStyle.meal)) {
      score += 18;
    }
    if (sequencing.mode == _MealMode.meal &&
        c.mealStyles.contains(sequencing.preferredStyle)) {
      score += 12;
    }
    if (sequencing.mode == _MealMode.proteinCorrection &&
        c.mealStyles.contains(_MealStyle.proteinCorrection)) {
      score += 22;
    }
    if (sequencing.mode == _MealMode.meal &&
        c.mealStyles.contains(_MealStyle.proteinCorrection) &&
        r.protein < 20) {
      score -= 12;
    }
    if (sequencing.mode == _MealMode.meal &&
        c.mealStyles.contains(_MealStyle.proteinCorrection) &&
        sequencing.loggedMealCount <= 1) {
      score -= 14;
    }
    if (sequencing.mode == _MealMode.proteinCorrection &&
        c.mealStyles.contains(_MealStyle.meal)) {
      score -= 18;
    }
    if (sequencing.hasDinnerLogged && c.mealStyles.contains(_MealStyle.lunch)) {
      score -= 20;
    }
    if (!sequencing.hasLunchLogged && c.mealStyles.contains(_MealStyle.lunch)) {
      score += 10;
    }
    if (sequencing.hasLunchLogged &&
        !sequencing.hasDinnerLogged &&
        c.mealStyles.contains(_MealStyle.dinner)) {
      score += 12;
    }

    // ─ 4. User familiarity (10 pts) ──────────────────────────────────────
    final historyCount = history
        .where(
          (h) =>
              h.finalSavedInput.toLowerCase() == c.prefilledText.toLowerCase(),
        )
        .length;
    score += historyCount.clamp(0, 3) * 3.0;
    if (patterns.commonFoodsBySection[section]?.any(
          (f) => f.toLowerCase() == c.prefilledText.toLowerCase(),
        ) ==
        true) {
      score += 4;
    }

    // ─ 5. Variety / recency (10 pts) ──────────────────────────────────────
    final recentlyEaten = history
        .take(6)
        .any(
          (h) =>
              h.finalSavedInput.toLowerCase() == c.prefilledText.toLowerCase(),
        );
    if (recentlyEaten) {
      score -= 8;
    }

    // ─ 6. Historical preference (last priority) ──────────────────────────
    if (patterns.daysLogged >= 4 && historyCount >= 3) {
      score += 2;
    }

    // Training day protein boost — decisive, not just a tiebreaker.
    // Base boost for planned training day (even before workout).
    if (isTrainingDay && c.isProteinFocused) {
      score += 14;
    }
    // Extra boost once workout is actually completed or currently active — recovery window matters.
    if (isWorkoutDoneOrActive) {
      if (c.isProteinFocused) {
        score += 12;
      }
      // If we are actively training or done, prioritize heavy high-cal protein if needed
      if (c.caloriesKcal >= 180 && !c.isCarbHeavy) {
        score += 6;
      }
    }

    // Additional variety guard.
    if (eatenToday.any(
      (f) => f.contains(c.prefilledText.split(' ').first.toLowerCase()),
    )) {
      score -= 10;
    }

    return score;
  }

  // ── Reason generation ─────────────────────────────────────────────────────

  MealSuggestion _toSuggestion(
    _SuggestionCandidate c,
    _Remaining r,
    bool isTrainingDay,
    _MealSequencing sequencing,
  ) {
    final String reason;
    final ws = WorkoutService.instance;
    final bool isWorkoutDoneOrActive = 
        (ws.draftSession != null) || (ws.sessionFor(DateTime.now()) != null);

    if (sequencing.mode == _MealMode.proteinCorrection && c.isProteinFocused) {
      reason = r.calories < 180
          ? 'The day is nearly done. Keep it to a lean protein correction only.'
          : 'A full meal is not necessary now. Use this to close the protein gap cleanly.';
    } else if (sequencing.targetSection == MealSection.lunch &&
        c.mealStyles.contains(_MealStyle.lunch)) {
      reason =
          'You still have lunch ahead. This fits better than a random snack.';
    } else if (sequencing.targetSection == MealSection.dinner &&
        c.mealStyles.contains(_MealStyle.dinner)) {
      reason = 'This works well as your next proper dinner-style meal.';
    } else if (r.protein > 25 && c.isProteinFocused) {
      reason = isWorkoutDoneOrActive
          ? 'You trained today and protein is still lagging — this closes the gap cleanly.'
          : 'Protein is still lagging — this closes the gap cleanly.';
    } else if (r.protein > 10 && c.isProteinFocused) {
      reason = 'Good fit for what you are actually missing right now.';
    } else if (isWorkoutDoneOrActive &&
        c.isProteinFocused &&
        c.caloriesKcal >= 180) {
      reason = 'Good recovery meal option around training.';
    } else if (r.calories < 200 && c.caloriesKcal < 150) {
      reason = 'Light option — fits within your remaining budget.';
    } else if (isTrainingDay && c.isProteinFocused) {
      reason = 'Training day — keep protein high through dinner.';
    } else {
      reason = c.defaultReason;
    }

    return MealSuggestion(
      title: c.title,
      quantity: c.quantity,
      reason: reason,
      prefilledText: c.prefilledText,
    );
  }

  // ── History-based candidates ──────────────────────────────────────────────

  List<_SuggestionCandidate> _historyCandidates(
    List<MealEntry> history,
    MealSection section,
    Set<String> eatenToday,
  ) {
    final freq = <String, int>{};
    for (final e in history) {
      if (e.section == section) {
        freq[e.finalSavedInput] = (freq[e.finalSavedInput] ?? 0) + 1;
      }
    }
    if (freq.isEmpty) {
      return const [];
    }

    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final out = <_SuggestionCandidate>[];
    for (final entry in sorted) {
      if (eatenToday.contains(entry.key.toLowerCase())) continue;
      // Infer protein-focus from common protein keywords
      final lc = entry.key.toLowerCase();
      final isProteinFood = const [
        'whey',
        'tofu',
        'paneer',
        'egg',
        'chicken',
        'curd',
      ].any(lc.contains);
      out.add(
        _SuggestionCandidate(
          title: entry.key,
          quantity: 'your usual amount',
          prefilledText: entry.key,
          proteinG: isProteinFood ? 18 : 8,
          caloriesKcal: isProteinFood ? 200 : 280,
          isProteinFocused: isProteinFood,
          isCarbHeavy: !isProteinFood,
          defaultReason: 'You often eat this ${_sectionKey(section)}.',
          timingBonus: {_sectionKey(section): 15},
          mealStyles: isProteinFood
              ? {
                  _MealStyle.snack,
                  _MealStyle.proteinCorrection,
                  _MealStyle.meal,
                }
              : {_MealStyle.meal, _MealStyle.lunch, _MealStyle.dinner},
        ),
      );
      if (out.length >= 2) break;
    }
    return out;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Set<String> _foodsEatenToday(DayLog log) {
    final foods = <String>{};
    for (final s in MealSection.values) {
      for (final e in log.entriesFor(s)) {
        foods.add(e.finalSavedInput.toLowerCase());
      }
    }
    return foods;
  }

  List<MealEntry> _recentHistory(DateTime date) {
    final entries = <MealEntry>[];
    for (final item in dayLogStore.entries) {
      final parsed = DateTime.tryParse(item.key);
      if (parsed == null || parsed.isAfter(date)) continue;
      for (final s in MealSection.values) {
        entries.addAll(item.value.entriesFor(s));
      }
    }
    entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return entries;
  }
}

MealSection _sectionForHour(int hour) {
  if (hour < 11) return MealSection.breakfast;
  if (hour < 16) return MealSection.lunch;
  if (hour < 19) return MealSection.eveningSnack;
  if (hour < 23) return MealSection.dinner;
  return MealSection.lateNight;
}

String _sectionKey(MealSection s) => switch (s) {
  MealSection.breakfast => 'morning',
  MealSection.lunch => 'lunch',
  MealSection.eveningSnack => 'evening',
  MealSection.dinner => 'dinner',
  MealSection.lateNight => 'late',
};

// ─── _Remaining ───────────────────────────────────────────────────────────────

class _Remaining {
  final double calories;
  final double protein;
  const _Remaining({required this.calories, required this.protein});

  factory _Remaining.compute(DayLog log, DayTarget target) => _Remaining(
    calories: (target.calories - log.totalCaloriesMid).clamp(0, 5000),
    protein: (target.protein - log.totalProteinMid).clamp(0, 500),
  );
}

// ─── _SuggestionCandidate ─────────────────────────────────────────────────────

class _SuggestionCandidate {
  final String title;
  final String quantity;
  final String prefilledText;
  final double proteinG;
  final double caloriesKcal;
  final bool isProteinFocused;
  final bool isCarbHeavy;
  final String defaultReason;
  final Map<String, int> timingBonus;
  final Set<_MealStyle> mealStyles;

  const _SuggestionCandidate({
    required this.title,
    required this.quantity,
    required this.prefilledText,
    required this.proteinG,
    required this.caloriesKcal,
    required this.isProteinFocused,
    required this.isCarbHeavy,
    required this.defaultReason,
    required this.timingBonus,
    required this.mealStyles,
  });
}

enum _MealStyle { lunch, dinner, snack, proteinCorrection, meal }

enum _MealMode { meal, proteinCorrection }

class _MealSequencing {
  final MealSection targetSection;
  final _MealMode mode;
  final _MealStyle preferredStyle;
  final int loggedMealCount;
  final bool hasLunchLogged;
  final bool hasDinnerLogged;

  const _MealSequencing({
    required this.targetSection,
    required this.mode,
    required this.preferredStyle,
    required this.loggedMealCount,
    required this.hasLunchLogged,
    required this.hasDinnerLogged,
  });
}

_MealSequencing _mealSequencing(DayLog log, DateTime now) {
  final breakfastCount = log.entriesFor(MealSection.breakfast).length;
  final lunchCount = log.entriesFor(MealSection.lunch).length;
  final dinnerCount = log.entriesFor(MealSection.dinner).length;
  final snackCount =
      log.entriesFor(MealSection.eveningSnack).length +
      log.entriesFor(MealSection.lateNight).length;
  final loggedMealCount =
      breakfastCount + lunchCount + dinnerCount + snackCount;
  final current = _sectionForHour(now.hour);

  if (dinnerCount > 0) {
    return _MealSequencing(
      targetSection: MealSection.lateNight,
      mode: _MealMode.proteinCorrection,
      preferredStyle: _MealStyle.proteinCorrection,
      loggedMealCount: loggedMealCount,
      hasLunchLogged: lunchCount > 0,
      hasDinnerLogged: true,
    );
  }
  if (breakfastCount > 0 && lunchCount == 0) {
    return _MealSequencing(
      targetSection: MealSection.lunch,
      mode: _MealMode.meal,
      preferredStyle: _MealStyle.lunch,
      loggedMealCount: loggedMealCount,
      hasLunchLogged: false,
      hasDinnerLogged: false,
    );
  }
  if (breakfastCount > 0 && lunchCount > 0) {
    return _MealSequencing(
      targetSection: MealSection.dinner,
      mode: _MealMode.meal,
      preferredStyle: _MealStyle.dinner,
      loggedMealCount: loggedMealCount,
      hasLunchLogged: true,
      hasDinnerLogged: false,
    );
  }
  return _MealSequencing(
    targetSection: current,
    mode: _MealMode.meal,
    preferredStyle: current == MealSection.lunch
        ? _MealStyle.lunch
        : current == MealSection.dinner
        ? _MealStyle.dinner
        : _MealStyle.snack,
    loggedMealCount: loggedMealCount,
    hasLunchLogged: lunchCount > 0,
    hasDinnerLogged: false,
  );
}

// ─── Candidate food library ───────────────────────────────────────────────────
//
// Generic foods common in Indian hostel / home / mess context.
// NOT user-specific — works for any user profile.

const _candidates = <_SuggestionCandidate>[
  _SuggestionCandidate(
    title: '1 scoop whey',
    quantity: '30 g in water or milk',
    prefilledText: '1 scoop whey',
    proteinG: 24,
    caloriesKcal: 120,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'Quick, high-protein, low-calorie.',
    timingBonus: {'morning': 18, 'evening': 12, 'dinner': 5},
    mealStyles: {_MealStyle.snack, _MealStyle.proteinCorrection},
  ),
  _SuggestionCandidate(
    title: 'Whey + milk',
    quantity: '1 scoop + 300 ml milk',
    prefilledText: '1 scoop whey 300ml milk',
    proteinG: 34,
    caloriesKcal: 294,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'High protein — covers a large chunk of the daily gap.',
    timingBonus: {'morning': 20, 'evening': 10},
    mealStyles: {_MealStyle.snack, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: '4 egg whites',
    quantity: '4 egg whites',
    prefilledText: '4 egg whites',
    proteinG: 14,
    caloriesKcal: 68,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'Very lean protein with minimal calories.',
    timingBonus: {'morning': 18, 'evening': 8},
    mealStyles: {_MealStyle.snack, _MealStyle.proteinCorrection},
  ),
  _SuggestionCandidate(
    title: 'Paneer sabzi',
    quantity: '150 g paneer',
    prefilledText: '150g paneer sabzi',
    proteinG: 18,
    caloriesKcal: 350,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'Good protein with a satisfying portion.',
    timingBonus: {'lunch': 15, 'dinner': 18},
    mealStyles: {_MealStyle.lunch, _MealStyle.dinner, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: 'Curd + fruit + whey',
    quantity: '200 g curd + 1 scoop whey',
    prefilledText: '200g curd 1 scoop whey',
    proteinG: 31,
    caloriesKcal: 240,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'Easy recovery-friendly protein hit.',
    timingBonus: {'evening': 18, 'late': 14},
    mealStyles: {_MealStyle.snack, _MealStyle.proteinCorrection},
  ),
  _SuggestionCandidate(
    title: 'Tofu stir-fry',
    quantity: '150 g tofu',
    prefilledText: '150g tofu',
    proteinG: 22,
    caloriesKcal: 206,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'High protein, moderate calories.',
    timingBonus: {'lunch': 15, 'dinner': 15},
    mealStyles: {_MealStyle.lunch, _MealStyle.dinner, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: 'Soya bhurji + 2 roti',
    quantity: '2 roti with soya bhurji',
    prefilledText: '2 roti soya bhurji',
    proteinG: 20,
    caloriesKcal: 340,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'Solid protein + carbs — good balanced meal.',
    timingBonus: {'dinner': 18, 'lunch': 12},
    mealStyles: {_MealStyle.dinner, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: '2 roti + soya for dinner',
    quantity: '2 roti + chilli soya, skip rice',
    prefilledText: '2 roti chilli soya skip rice',
    proteinG: 24,
    caloriesKcal: 360,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'Protein-first dinner without extra rice calories.',
    timingBonus: {'dinner': 20},
    mealStyles: {_MealStyle.dinner, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: 'Rice + dal + curd',
    quantity: '1 bowl rice + dal + curd',
    prefilledText: '1 bowl rice dal curd',
    proteinG: 16,
    caloriesKcal: 420,
    isProteinFocused: false,
    isCarbHeavy: false,
    defaultReason:
        'Better recovery meal when both calories and protein are low.',
    timingBonus: {'lunch': 14, 'dinner': 18},
    mealStyles: {_MealStyle.lunch, _MealStyle.dinner, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: 'Curd',
    quantity: '200 g curd',
    prefilledText: '200g curd',
    proteinG: 7,
    caloriesKcal: 120,
    isProteinFocused: false,
    isCarbHeavy: false,
    defaultReason: 'Light protein source — good filler.',
    timingBonus: {'evening': 12, 'lunch': 8},
    mealStyles: {_MealStyle.snack, _MealStyle.proteinCorrection},
  ),
  _SuggestionCandidate(
    title: '2 roti + dal',
    quantity: '2 roti with dal',
    prefilledText: '2 roti dal',
    proteinG: 12,
    caloriesKcal: 280,
    isProteinFocused: false,
    isCarbHeavy: true,
    defaultReason: 'Balanced carb-protein meal.',
    timingBonus: {'lunch': 15, 'dinner': 12},
    mealStyles: {_MealStyle.lunch, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: 'Dal chawal',
    quantity: '2 ladles rice + dal',
    prefilledText: '2 ladle rice dal',
    proteinG: 10,
    caloriesKcal: 330,
    isProteinFocused: false,
    isCarbHeavy: true,
    defaultReason: 'Standard mess meal — use only when protein is covered.',
    timingBonus: {'lunch': 18},
    mealStyles: {_MealStyle.lunch, _MealStyle.meal},
  ),
  _SuggestionCandidate(
    title: '3 egg whites + milk',
    quantity: '3 egg whites + 300 ml milk',
    prefilledText: '3 egg whites 300ml milk',
    proteinG: 21,
    caloriesKcal: 228,
    isProteinFocused: true,
    isCarbHeavy: false,
    defaultReason: 'High protein breakfast combination.',
    timingBonus: {'morning': 20},
    mealStyles: {_MealStyle.meal, _MealStyle.snack},
  ),
  _SuggestionCandidate(
    title: 'Light dinner — skip rice',
    quantity: '2 roti + sabzi',
    prefilledText: '2 roti sabzi',
    proteinG: 9,
    caloriesKcal: 220,
    isProteinFocused: false,
    isCarbHeavy: false,
    defaultReason: 'Keep dinner controlled when calories are almost done.',
    timingBonus: {'dinner': 10, 'late': 12},
    mealStyles: {_MealStyle.dinner, _MealStyle.snack},
  ),
];
