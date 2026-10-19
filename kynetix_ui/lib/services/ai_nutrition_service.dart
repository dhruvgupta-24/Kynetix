import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/nutrition_result.dart';
import 'profile_service.dart';
import '../services/chatgpt_link_service.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;
import 'user_nutrition_memory.dart';
import 'personal_nutrition_memory.dart';
import 'meal_memory.dart';
import 'ai_router_error.dart';
import 'internal/net_timeouts.dart';

class AiEscalationContext {
  final String localInterpretation;
  final double localMatchConfidence;
  final double localCoverageConfidence;
  final double overallLocalConfidence;
  final List<String> flags;
  /// The whole meal as the user typed it, when the text being estimated is
  /// one item of a larger meal. Used only to size accompaniments.
  final String? mealContext;

  const AiEscalationContext({
    required this.localInterpretation,
    required this.localMatchConfidence,
    required this.localCoverageConfidence,
    required this.overallLocalConfidence,
    this.flags = const [],
    this.mealContext,
  });
}

// ─── AI Nutrition Service (OpenRouter) ───────────────────────────────────────
//
// Provider-agnostic wrapper around the OpenRouter OpenAI-compatible API.
// API key: --dart-define=OPENROUTER_API_KEY=sk-or-...

class AiNutritionService {
  AiNutritionService._();
  static final AiNutritionService instance = AiNutritionService._();

  // Test delegate to override the AI estimation behavior during tests.
  Future<NutritionResult> Function(String, {AiEscalationContext? context})? mockEstimate;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Always configured — routing handled by backend ai-chat-router.
  bool get isConfigured => true;

  static String get modelName => 'ai-chat-router';

  Future<NutritionResult> estimate(String rawInput) async {
    return estimateWithContext(rawInput);
  }

  Future<NutritionResult> estimateWithContext(
    String rawInput, {
    AiEscalationContext? context,
  }) async {
    if (mockEstimate != null) {
      return mockEstimate!(rawInput, context: context);
    }
    debugPrint('[AI] estimating: "$rawInput"');

    // ── Route through backend ai-chat-router ─────────────────────────────────
    // The backend handles provider selection and owns the system prompt
    // (purpose 'meal_estimate'). No API keys or provider logic on the client.
    final body = buildRequestBody(rawInput, context: context);

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final stopwatch = Stopwatch()..start();
    try {
      final FunctionResponse res;
      try {
        res = await Supabase.instance.client.functions.invoke(
          'ai-chat-router',
          body: body,
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ).within(NetTimeouts.ai, 'AI meal estimate');
      } on FunctionException catch (e) {
        // 429 / 413 / 400 etc. — typed and calm, never the raw body.
        throw AiRouterException.from(e);
      }

      final data = res.data is Map ? (res.data as Map).cast<String, dynamic>() : null;
      if (data == null || data['success'] != true) {
        debugPrint('[AI] ❌ router error: ${data?['error'] ?? 'no data'}');
        throw AiRouterException.fromResponse(res.status, data);
      }

      stopwatch.stop();
      final providerUsed  = data['provider_used'] as String? ?? 'unknown';
      final fallbackUsed  = data['fallback_used'] == true;
      final text          = data['response'] as String? ?? '';

      ChatGptLinkService.recordAiRequestSuccess(
        providerUsed,
        stopwatch.elapsedMilliseconds.toDouble(),
      ).ignore();
      lastError.value = null;

      debugPrint('[AI] provider=$providerUsed fallback=$fallbackUsed');
      debugPrint('[AI] raw response (first 600): '
          '${text.substring(0, text.length.clamp(0, 600))}');

      return _parse(text, rawInput);
    } on AiRouterException catch (e) {
      debugPrint('[AI] ❌ $e');
      lastError.value = e;
      ChatGptLinkService.recordAiRequestFailure().ignore();
      rethrow;
    } catch (e) {
      ChatGptLinkService.recordAiRequestFailure().ignore();
      rethrow;
    }
  }

  /// The most recent AI estimate failure (rate limit, too long, generic), or
  /// null after a success. The meal pipeline falls back to a local estimate
  /// when AI fails, so the UI can read this to explain why.
  final ValueNotifier<AiRouterException?> lastError =
      ValueNotifier<AiRouterException?>(null);

  /// The ai-chat-router request body. The server owns the system prompt for
  /// purpose 'meal_estimate', so only the user message is sent, plus the
  /// user's portion anchor (enum name) when set.
  @visibleForTesting
  Map<String, dynamic> buildRequestBody(
    String rawInput, {
    AiEscalationContext? context,
  }) {
    final relevantMemory = _getRelevantFoodMemory(rawInput);
    final anchor = ProfileService.instance.currentUserProfile?.portionAnchor;
    return {
      'purpose': 'meal_estimate',
      'portion_anchor': ?anchor?.name,
      'messages': [
        {'role': 'user', 'content': _userPrompt(rawInput, context: context, foodMemoryBlock: relevantMemory)},
      ],
    };
  }

  // ── Response parsing ──────────────────────────────────────────────────────

  NutritionResult _parse(String raw, String rawInput) {
    var text = raw.trim();

    // Strip markdown fences defensively.
    text = text
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*',     multiLine: true), '')
        .replaceAll(RegExp(r'\s*```$',     multiLine: true), '')
        .trim();

    // Extract JSON object if surrounded by stray prose.
    final s = text.indexOf('{');
    final e = text.lastIndexOf('}');
    if (s >= 0 && e > s) text = text.substring(s, e + 1);

    Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (ex) {
      debugPrint('[AI] ❌ JSON decode failed: $ex\nraw: $text');
      throw FormatException('AI returned non-JSON: $text');
    }

    // Normalize snake_case keys to camelCase.
    Map<String, dynamic> normalizeKeys(Map<String, dynamic> map) {
      final result = <String, dynamic>{};
      map.forEach((k, v) {
        var newKey = k;
        if (k == 'canonical_meal') {
          newKey = 'canonicalMeal';
        } else if (k == 'coach_summary') {
          newKey = 'coachSummary';
        } else if (k == 'best_next_foods') {
          newKey = 'bestNextFoods';
        } else if (k == 'meal_category') {
          newKey = 'mealCategory';
        } else if (k == 'meal_density') {
          newKey = 'mealDensity';
        } else if (k == 'risk_flags') {
          newKey = 'riskFlags';
        } else if (k == 'estimation_mode') {
          newKey = 'estimationMode';
        } else if (k == 'meal_quality_score') {
          newKey = 'mealQualityScore';
        } else if (k == 'meal_quality_explanation') {
          newKey = 'mealQualityExplanation';
        } else if (k == 'meal_quality_positive') {
          newKey = 'mealQualityPositive';
        } else if (k == 'meal_quality_improvement') {
          newKey = 'mealQualityImprovement';
        } else if (k == 'saturated_fat') {
          newKey = 'saturatedFat';
        }
        
        if (v is Map<String, dynamic>) {
          result[newKey] = normalizeKeys(v);
        } else if (v is List) {
          result[newKey] = v.map((item) {
            if (item is Map<String, dynamic>) {
              return normalizeKeys(item);
            }
            return item;
          }).toList();
        } else {
          result[newKey] = v;
        }
      });
      return result;
    }

    json = normalizeKeys(json);

    final canonicalMeal = json['canonicalMeal'] as String? ?? rawInput;
    final itemsList = json['items'] as List<dynamic>? ?? [];
    final rawConf = (json['confidence'] as num?)?.toDouble() ?? 0.85;

    final items = itemsList.map((el) {
      if (el is Map<String, dynamic>) {
        var itemMap = Map<String, dynamic>.from(el);
        if (itemMap['calories'] is num) {
          final c = (itemMap['calories'] as num).toDouble();
          itemMap['calories'] = {'min': c, 'max': c};
        }
        if (itemMap['protein'] is num) {
          final p = (itemMap['protein'] as num).toDouble();
          itemMap['protein'] = {'min': p, 'max': p};
        }
        for (final key in ['carbohydrates', 'fat', 'fiber', 'sugar', 'saturatedFat', 'sodium']) {
          if (itemMap[key] is num) {
            final val = (itemMap[key] as num).toDouble();
            itemMap[key] = {'min': val, 'max': val};
          }
        }
        return NutritionItem.fromJson(itemMap);
      }
      return NutritionItem.fromJson(const {});
    }).toList();

    // Cross-check: use item sums when they diverge from stated totals >15%.
    final sumCal = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + i.calories.min, max: a.max + i.calories.max),
    );
    final sumPro = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + i.protein.min,  max: a.max + i.protein.max),
    );
    final sumCarbs = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + (i.carbohydrates?.min ?? 0), max: a.max + (i.carbohydrates?.max ?? 0)),
    );
    final sumFat = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + (i.fat?.min ?? 0), max: a.max + (i.fat?.max ?? 0)),
    );
    final sumFiber = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + (i.fiber?.min ?? 0), max: a.max + (i.fiber?.max ?? 0)),
    );
    final sumSugar = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + (i.sugar?.min ?? 0), max: a.max + (i.sugar?.max ?? 0)),
    );
    final sumSatFat = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + (i.saturatedFat?.min ?? 0), max: a.max + (i.saturatedFat?.max ?? 0)),
    );
    final sumSodium = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + (i.sodium?.min ?? 0), max: a.max + (i.sodium?.max ?? 0)),
    );

    NutrientRange parseRange(dynamic raw, ({double min, double max}) sumDefault) {
      if (raw == null) return NutrientRange(min: sumDefault.min, max: sumDefault.max);
      if (raw is num) {
        final val = raw.toDouble();
        return NutrientRange(min: val, max: val);
      }
      if (raw is Map<String, dynamic>) {
        final minVal = (raw['min'] ?? raw['minimum'] ?? sumDefault.min) as num?;
        final maxVal = (raw['max'] ?? raw['maximum'] ?? sumDefault.max) as num?;
        return NutrientRange(
          min: minVal?.toDouble() ?? sumDefault.min,
          max: maxVal?.toDouble() ?? sumDefault.max,
        );
      }
      return NutrientRange(min: sumDefault.min, max: sumDefault.max);
    }

    final calTotal = parseRange(json['calories'], sumCal);
    final proTotal = parseRange(json['protein'], sumPro);

    final useCal   = _within15(calTotal, sumCal)
        ? calTotal
        : NutrientRange(min: _r(sumCal.min), max: _r(sumCal.max));
    final usePro   = _within15(proTotal, sumPro)
        ? proTotal
        : NutrientRange(min: _r(sumPro.min), max: _r(sumPro.max));

    final carbsTotal = json['carbohydrates'] != null ? parseRange(json['carbohydrates'], sumCarbs) : null;
    final fatTotal = json['fat'] != null ? parseRange(json['fat'], sumFat) : null;
    final fiberTotal = json['fiber'] != null ? parseRange(json['fiber'], sumFiber) : null;
    final sugarTotal = json['sugar'] != null ? parseRange(json['sugar'], sumSugar) : null;
    final satFatTotal = json['saturatedFat'] != null ? parseRange(json['saturatedFat'], sumSatFat) : null;
    final sodiumTotal = json['sodium'] != null ? parseRange(json['sodium'], sumSodium) : null;

    debugPrint('[AI] ✅ parse success: '
        '${useCal.min.round()}-${useCal.max.round()} kcal  '
        '${usePro.min.round()}-${usePro.max.round()}g protein');

    // Tolerate 72.5 or "72" from the model; only used for logging.
    final rawScore = json['mealQualityScore'];
    final int? aiScore = rawScore is num
        ? rawScore.round()
        : rawScore is String ? num.tryParse(rawScore.trim())?.round() : null;
    final localScore = NutritionResult.calculateLocalQualityScore(
      useCal.mid,
      usePro.mid,
      canonicalMeal,
      carbs: carbsTotal?.mid,
      fat: fatTotal?.mid,
      fiber: fiberTotal?.mid,
    );

    if (aiScore != null) {
      final divergence = (aiScore - localScore).abs();
      debugPrint('[Scoring] Meal: "$canonicalMeal" | AI Score: $aiScore | Local Score: $localScore | Divergence: $divergence');
    }

    final aiExplanation = json['mealQualityExplanation'] as String?;
    final aiPositive = json['mealQualityPositive'] as String?;
    final aiImprovement = json['mealQualityImprovement'] as String?;

    return NutritionResult(
      canonicalMeal: canonicalMeal,
      items:         items,
      calories:      useCal,
      protein:       usePro,
      confidence:    rawConf.clamp(0.0, 1.0),
      warnings:      List<String>.from(json['warnings'] as List<dynamic>? ?? []),
      coachSummary:  json['coachSummary'] as String?,
      bestNextFoods: List<String>.from(json['bestNextFoods'] as List<dynamic>? ?? const []),
      mealCategory:  json['mealCategory'] as String?,
      mealDensity:   json['mealDensity'] as String?,
      riskFlags:     List<String>.from(json['riskFlags'] as List<dynamic>? ?? const []),
      source:        'ai',
      createdAt:     DateTime.now(),
      carbohydrates: carbsTotal,
      fat:            fatTotal,
      fiber:          fiberTotal,
      sugar:          sugarTotal,
      saturatedFat:   satFatTotal,
      sodium:         sodiumTotal,
      mealQualityScore: localScore,
      mealQualityExplanation: aiExplanation != null && aiExplanation.isNotEmpty ? aiExplanation : NutritionResult.getLocalQualityExplanation(localScore, canonicalMeal),
      mealQualityPositive: aiPositive != null && aiPositive.isNotEmpty ? aiPositive : NutritionResult.getLocalQualityPositive(localScore, canonicalMeal),
      mealQualityImprovement: aiImprovement != null && aiImprovement.isNotEmpty ? aiImprovement : NutritionResult.getLocalQualityImprovement(localScore, canonicalMeal),
    ).normalizedUncertainty();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // NOTE: _dispatchAiHttp removed — all provider dispatch is now in the
  // ai-chat-router Supabase Edge Function. No HTTP calls to AI providers
  // from the Flutter client.


  bool _within15(NutrientRange g, ({double min, double max}) s) {
    if (g.max == 0 && s.max == 0) return true;
    final ref = s.max > 0 ? s.max : g.max;
    return (g.max - s.max).abs() / ref < 0.15;
  }

  double _r(double v) {
    if (v.isNaN || v.isInfinite) return 0.0;
    return double.tryParse(v.toStringAsFixed(1)) ?? 0.0;
  }

  // The meal-estimate system prompt (mess calibration, portion-anchor rules,
  // output schema) is server-owned: supabase/functions/shared/
  // meal_estimate_prompt.ts. The client sends only the user message.

  String _userPrompt(String rawInput, {
    AiEscalationContext? context,
    String? foodMemoryBlock,
  }) {
    final profile = ProfileService.instance.currentUserProfile;
    final profileContext = profile == null
        ? 'No user profile available. Use generalized defaults only.'
        : '''User profile for calibration only:
- Sex: ${profile.gender}
- Age: ${profile.age}
- Height: ${profile.height.toStringAsFixed(0)} cm
- Weight: ${profile.weight.toStringAsFixed(1)} kg
- Workout frequency: ${profile.workoutDaysMin}-${profile.workoutDaysMax} days/week

- Goal: ${profile.goal}''';

  final contextBlock = context == null
    ? 'No local pre-interpretation was available.'
    : '''Hybrid local context (validate and refine this, do not ignore):
- local_interpretation: ${context.localInterpretation}
- local_match_confidence: ${context.localMatchConfidence.toStringAsFixed(3)}
- local_coverage_confidence: ${context.localCoverageConfidence.toStringAsFixed(3)}
- local_overall_confidence: ${context.overallLocalConfidence.toStringAsFixed(3)}
- complexity_flags: ${context.flags.isEmpty ? 'none' : context.flags.join(', ')}

Use this context as prior evidence:
- If local interpretation is correct, keep it and tighten ranges.
- If local missed components, decompose and add them.
- If local collapsed multi-item meals, reconstruct full meal items.
- Never drop obvious components (e.g., drink in combo meals).''';

  final memorySection = foodMemoryBlock == null || foodMemoryBlock.isEmpty
      ? ''
      : '''
══ USER FOOD MEMORY ══
Entries marked "User Override" or "Saved Food/Recipe" are confirmed by the
user: when the same food appears, use their per-unit values and scale
linearly to the quantity in this meal. "Known Food" and "History Match"
entries are earlier estimates: use them as a prior only. Never reuse a
memory total when the quantity differs.

$foodMemoryBlock
═══════════════════════════════════════════════════''';

    final mealContext = context?.mealContext?.trim();
    final mealContextBlock = mealContext == null || mealContext.isEmpty
        ? ''
        : '''

This is ONE item from a bigger meal. Whole meal as typed: "$mealContext"
Return exactly one item, for "$rawInput" only. Do not include the roti,
rice or anything else from the rest of the meal in its numbers or as extra
items; use them only to size how much of this item was eaten (accompaniment
rules, eater type).''';

    return '''$profileContext

$memorySection

$contextBlock

Estimate nutrition for this meal text:
$rawInput$mealContextBlock

Return JSON only.''';
  }

  String _getRelevantFoodMemory(String queryText) {
    final fillerWords = {'and', 'with', 'some', 'a', 'an', 'of', 'the', 'in', 'at', 'on', 'for', 'to', 'my', 'had', 'ate', 'eaten', 'having'};
    
    Set<String> tokenize(String text) {
      return text
          .toLowerCase()
          .replaceAll(RegExp(r"[',.\-!?+&]"), '')
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty && !fillerWords.contains(t))
          .toSet();
    }

    final queryTokens = tokenize(queryText);
    if (queryTokens.isEmpty) return '';

    // List of candidates
    final candidates = <_MemoryCandidate>[];

    // 1. User overrides (UserNutritionMemory)
    for (final override in UserNutritionMemory.instance.allOverrides) {
      final name = override.canonicalMeal;
      final tokens = tokenize(name);
      candidates.add(_MemoryCandidate(
        name: name,
        calories: override.caloriesPerUnit * override.referenceQuantity,
        protein: override.proteinPerUnit * override.referenceQuantity,
        unit: override.referenceUnit,
        quantity: override.referenceQuantity,
        tokens: tokens,
        source: 'User Override',
        priority: 0.3,
        timesUsed: override.correctionCount,
        updatedAt: override.savedAt,
      ));
    }

    // 2. Personal overrides (PersonalNutritionMemory user overrides)
    for (final map in PersonalNutritionMemory.instance.allUserOverrides) {
      final name = map['label'] as String? ?? '';
      final tokens = tokenize(name);
      candidates.add(_MemoryCandidate(
        name: name,
        calories: (map['kcal'] as num?)?.toDouble() ?? 0,
        protein: (map['protein'] as num?)?.toDouble() ?? 0,
        unit: 'serving',
        quantity: 1,
        tokens: tokens,
        source: 'Saved Food/Recipe',
        priority: 0.2,
        timesUsed: 1,
        updatedAt: DateTime.now(),
      ));
    }

    // 3. Known Foods (MealMemory._knownFoods)
    for (final entry in MealMemory.instance.allKnownFoods.entries) {
      final name = entry.key;
      final tokens = tokenize(name);
      final result = entry.value;
      candidates.add(_MemoryCandidate(
        name: name,
        calories: result.calories.mid,
        protein: result.protein.mid,
        unit: result.items.isNotEmpty ? result.items.first.unit : 'serving',
        quantity: result.items.isNotEmpty ? result.items.first.quantity : 1,
        tokens: tokens,
        source: 'Known Food',
        priority: 0.1,
        timesUsed: 1,
        updatedAt: DateTime.now(),
      ));
    }

    // 4. Cached / Recurring history (MealMemory._store)
    for (final entry in MealMemory.instance.allEntries) {
      final name = entry.rawInput;
      final tokens = tokenize(name);
      candidates.add(_MemoryCandidate(
        name: name,
        calories: entry.result.calories.mid,
        protein: entry.result.protein.mid,
        unit: entry.result.items.isNotEmpty ? entry.result.items.first.unit : 'serving',
        quantity: entry.result.items.isNotEmpty ? entry.result.items.first.quantity : 1,
        tokens: tokens,
        source: 'History Match',
        priority: 0.0,
        timesUsed: entry.timesUsed,
        updatedAt: entry.updatedAt,
      ));
    }

    // Score and filter
    final scored = <_ScoredCandidate>[];
    final now = DateTime.now();

    for (final cand in candidates) {
      if (cand.tokens.isEmpty) continue;

      final intersection = queryTokens.intersection(cand.tokens);
      if (intersection.isEmpty) continue;

      final union = queryTokens.union(cand.tokens);
      final similarity = intersection.length / union.length;

      // Exact containment bonus
      double exactBonus = 0;
      final qLower = queryText.toLowerCase();
      final nameLower = cand.name.toLowerCase();
      if (qLower.contains(nameLower) || nameLower.contains(qLower)) {
        exactBonus = 0.3;
      }

      // Frequency bonus
      final freqBonus = (cand.timesUsed * 0.01).clamp(0.0, 0.2);

      // Recency bonus
      double recencyBonus = 0;
      final diffDays = now.difference(cand.updatedAt).inDays;
      if (diffDays <= 1) {
        recencyBonus = 0.2;
      } else if (diffDays <= 7) {
        recencyBonus = 0.1;
      }

      final score = similarity + exactBonus + cand.priority + freqBonus + recencyBonus;
      scored.add(_ScoredCandidate(candidate: cand, score: score));
    }

    // Sort descending by score
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Format top 5 matches
    final buffer = StringBuffer();
    final seen = <String>{};
    int count = 0;

    for (final item in scored) {
      if (count >= 5) break;
      final name = item.candidate.name;
      if (seen.contains(name.toLowerCase())) continue;
      seen.add(name.toLowerCase());

      final cand = item.candidate;
      final cal = cand.calories.round();
      final pro = cand.protein.round();
      buffer.writeln('• ${cand.name} = ${_fmtQty(cand.quantity)} ${cand.unit}: $cal kcal, ${pro}g protein (${cand.source})');
      count++;
    }

    return buffer.toString().trim();
  }

  /// 1.0 -> "1", 1.5 -> "1.5", 0.333 -> "0.33".
  static String _fmtQty(double q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return double.parse(q.toStringAsFixed(2)).toString();
  }
}

class _MemoryCandidate {
  final String name;
  final double calories;
  final double protein;
  final String unit;
  final double quantity;
  final Set<String> tokens;
  final String source;
  final double priority;
  final int timesUsed;
  final DateTime updatedAt;

  _MemoryCandidate({
    required this.name,
    required this.calories,
    required this.protein,
    required this.unit,
    required this.quantity,
    required this.tokens,
    required this.source,
    required this.priority,
    required this.timesUsed,
    required this.updatedAt,
  });
}

class _ScoredCandidate {
  final _MemoryCandidate candidate;
  final double score;

  _ScoredCandidate({required this.candidate, required this.score});
}
