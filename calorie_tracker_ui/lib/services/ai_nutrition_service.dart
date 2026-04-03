import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/mess_calibration.dart';
import '../models/nutrition_result.dart';
import '../screens/onboarding_screen.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;
import '../config/secrets.dart';

// ─── AI Nutrition Service (OpenRouter) ───────────────────────────────────────
//
// Provider-agnostic wrapper around the OpenRouter OpenAI-compatible API.
// API key: --dart-define=OPENROUTER_API_KEY=sk-or-...

class AiNutritionService {
  AiNutritionService._();
  static final AiNutritionService instance = AiNutritionService._();

  static const _apiKey = AppSecrets.openRouterApiKey;

  static const _model    = 'deepseek/deepseek-chat-v3-0324';
  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  // ── Public API ────────────────────────────────────────────────────────────

  bool get isConfigured => _apiKey.isNotEmpty && _apiKey != 'YOUR_OPENROUTER_API_KEY_HERE';

  static String get modelName => _model;

  Future<NutritionResult> estimate(String rawInput) async {
    debugPrint('[AI] estimating: "$rawInput"');

    final url = Uri.parse(_endpoint);

    final requestBody = jsonEncode({
      'model':    _model,
      'messages': [
        {'role': 'system', 'content': _systemPrompt()},
        {
          'role': 'user',
          'content': _userPrompt(rawInput),
        },
      ],
      'temperature':     0.15,
      'max_tokens':      1200,
      'response_format': {'type': 'json_object'},
    });

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type':  'application/json',
        'HTTP-Referer':  'https://kynetix.local',
        'X-Title':       'Kynetix',
      },
      body: requestBody,
    ).timeout(const Duration(seconds: 20));

    debugPrint('[AI] HTTP status: ${response.statusCode}');

    if (response.statusCode != 200) {
      final snippet = response.body.substring(
          0, response.body.length.clamp(0, 500));
      debugPrint('[AI] ❌ error body: $snippet');
      throw Exception('AI HTTP ${response.statusCode}: $snippet');
    }

    // OpenAI-compatible response: choices[0].message.content
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text    = decoded['choices']?[0]?['message']?['content']
        as String? ?? '';
    debugPrint('[AI] raw response (first 600): '
        '${text.substring(0, text.length.clamp(0, 600))}');

    return _parse(text, rawInput);
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

    for (final k in ['canonicalMeal', 'items', 'calories', 'protein', 'confidence']) {
      if (!json.containsKey(k)) {
        throw FormatException('AI response missing key: "$k"');
      }
    }

    final calMap  = json['calories'] as Map<String, dynamic>? ?? {};
    final proMap  = json['protein']  as Map<String, dynamic>? ?? {};
    final rawConf = (json['confidence'] as num?)?.toDouble() ?? 0.7;

    final items = (json['items'] as List<dynamic>? ?? [])
        .map((el) => NutritionItem.fromJson(el as Map<String, dynamic>))
        .toList();

    // Cross-check: use item sums when they diverge from stated totals >15%.
    final sumCal = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + i.calories.min, max: a.max + i.calories.max),
    );
    final sumPro = items.fold(
      (min: 0.0, max: 0.0),
      (a, i) => (min: a.min + i.protein.min,  max: a.max + i.protein.max),
    );

    final calTotal = _rng(calMap);
    final proTotal = _rng(proMap);
    final useCal   = _within15(calTotal, sumCal)
        ? calTotal
        : NutrientRange(min: _r(sumCal.min), max: _r(sumCal.max));
    final usePro   = _within15(proTotal, sumPro)
        ? proTotal
        : NutrientRange(min: _r(sumPro.min), max: _r(sumPro.max));

    debugPrint('[AI] ✅ parse success: '
        '${useCal.min.toInt()}–${useCal.max.toInt()} kcal  '
        '${usePro.min.toInt()}–${usePro.max.toInt()}g protein');

    return NutritionResult(
      canonicalMeal: json['canonicalMeal'] as String? ?? rawInput,
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
    ).normalizedUncertainty();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  NutrientRange _rng(Map<String, dynamic> m) => NutrientRange(
        min: (m['min'] as num?)?.toDouble() ?? 0,
        max: (m['max'] as num?)?.toDouble() ?? 0,
      );

  bool _within15(NutrientRange g, ({double min, double max}) s) {
    if (g.max == 0 && s.max == 0) return true;
    final ref = s.max > 0 ? s.max : g.max;
    return (g.max - s.max).abs() / ref < 0.15;
  }

  double _r(double v) => double.parse(v.toStringAsFixed(1));

  // ── System prompt ─────────────────────────────────────────────────────────

  String _systemPrompt() => '''
You are the backend intelligence layer for an Indian-first fat-loss nutrition coach.
Estimate meals with deterministic realism. Profile context refines estimates only — do not over-personalize.

═══════════════════════════════════════════════════
PRODUCT RULES
═══════════════════════════════════════════════════
- Realism over fake precision.
- Fast logging over database-style micromanagement.
- Return one realistic center estimate with a tight range (not wide guesses).
- When uncertain, lean conservative — slightly less than maximum, not minimum.
- Exact known foods / branded macros must be preserved when given.
- Coaching text: short, direct, practical, safe for mobile UI.

═══════════════════════════════════════════════════
INDIAN FOOD CONTEXT
═══════════════════════════════════════════════════
${MessCalibration.toPromptContext()}

═══════════════════════════════════════════════════
MESS / HOSTEL EATING BEHAVIOUR (critical)
═══════════════════════════════════════════════════
ESTIMATE WHAT WAS CONSUMED — not what was served.

ROTI / RICE:
- Estimate by count / ladle exactly as stated.
- 1 roti = 100 kcal, 3g protein.
- 1 rice ladle = 130 kcal, 3g protein (≈85–90g cooked).

DAL / SABZI alongside roti or rice:
- Treat as accompaniment, NOT a full katori/bowl.
- User eats only enough dal/sabzi to finish the roti/rice.
- Rajma/chole alongside 2 roti: estimate ~70–90g consumed = 155–195 kcal, 7–9g protein.
- Plain dal alongside 2 roti: estimate ~70–85 ml consumed = 95–130 kcal, 5–7g protein.
- Do NOT assume a full 250ml bowl unless explicitly stated.

PANEER DISHES (mess context):
- User eats ALL paneer pieces/cubes.
- User leaves ~30–40% of the surrounding gravy/oil on the plate.
- Therefore: estimate the PANEER SOLID portion fully, but discount the gravy/oil by ~35%.
- One mess serving of paneer dish (90–150g dish): ~220–290 kcal, 11–15g protein.
- Do NOT estimate a mess paneer dish at 350–500 kcal unless explicitly heavy/restaurant.

THALI COMPARTMENTS (most important rule):
- "N compartments" without a size qualifier = N SMALL COMPARTMENTS.
- Small compartment = 60–80g of food.
- Large/rectangular compartment = 120–155g of food.
- "3 compartments paneer" in mess context ≠ 3 full restaurant bowls.
- "3 small compartments paneer" → ~180–240g dish total → ~420–520 kcal consumed, ~18–22g protein.
- The 800 kcal combined floor for a paneer thali only applies when the FULL THALI is logged in one entry (roti + rice + curry together).

RESTAURANT / OUTSIDE FOOD:
- Always higher: assume larger portions, more oil, richer gravy.
- Restaurant paneer curry: ~350–500 kcal per serving.
- Restaurant thali: ~900–1200 kcal.

MILK:
- DEFAULT: Indian TONED milk = 58 kcal/100ml, 3.4g protein/100ml.
- 400 ml toned milk = 232 kcal, 13.6g protein.
- Do NOT use 46 kcal/100ml (that is double-toned/low-fat — only if explicitly stated).
- Respect explicit ml amounts exactly.

═══════════════════════════════════════════════════
DETERMINISTIC BASELINES
═══════════════════════════════════════════════════
- 1 egg white:  17 kcal, 3.6g protein
- 1 whole egg:  75 kcal, 6.5g protein
- 100 ml toned milk: 58 kcal, 3.4g protein
- 100 ml double-toned milk: 46 kcal, 3.0g protein (only if user says so)
- 100 ml full-cream milk: 65 kcal, 3.2g protein
- 1 roti (mess/home): 100 kcal, 3g protein
- 1 rice ladle (mess): 130 kcal, 3g protein
- 1 medium bowl cooked rice: ~210 kcal, 4g protein
- 1 katori plain dal: ~130 kcal, 6g protein (consumed alongside roti)
- 1 katori rajma/chole alongside roti: ~170 kcal, 8g protein (consumed portion)
- 1 katori dal makhani: ~230 kcal, 9g protein
- 1 mess serving paneer dish: ~250 kcal, 12g protein (pieces eaten, partial gravy)
- 100g paneer dish (restaurant): ~290–340 kcal, 14–18g protein
- 100g tofu: ~135–150 kcal, 14–16g protein
- 100g curd: 60 kcal, 3.5g protein
- 1 scoop whey (30g, water): 120 kcal, 24g protein
- 150g tofu: 206 kcal, 22g protein
- 1 tbsp peanut butter: 95 kcal, 3.5g protein
- 1 bread slice (packaged): 80 kcal, 2.8g protein
- 1 banana: 90 kcal, 1.2g protein
- 1 brownie (mess/home, medium): ~200–260 kcal, 3–4g protein

═══════════════════════════════════════════════════
ESTIMATION MODES
═══════════════════════════════════════════════════
- direct_quantity    → explicit amount given (400 ml milk, 4 egg whites, 150g tofu)
- contextual_intake  → sabzi/dal alongside roti/rice (estimate consumed, not served)
- packaged_known     → branded foods (bread, oats, whey, milk packet)
- outside_restaurant → restaurant/fast food (assume higher oil, larger portions)

═══════════════════════════════════════════════════
ACCURACY RULES (NON-NEGOTIABLE)
═══════════════════════════════════════════════════
1. NEVER double-count. "4 egg whites" = ONLY egg whites.
2. Explicit quantity + simple food → spread ≤ 3% (min ≈ max). Confidence ≥ 0.88.
3. Unknown quantity → spread ≤ 12%.
4. COMPOUND MEALS: total must be ≥ sum of each item's individual floor.
   Example: '4 egg whites + 400ml milk' ≥ 68 + 232 = 300 kcal.
5. DEFAULT MILK: toned (58 kcal/100ml). Never use 46 kcal/100ml as default.
6. COMPARTMENT MEALS: N compartments (no size) = N small compartments (~65–75g each).
7. Dal/sabzi alongside roti = contextual_intake (consumed to finish carbs, not a full bowl).
8. Paneer = pieces fully consumed but gravy/oil ~35% left → net ≈ 220–290 kcal/mess serving.
9. "Thoda"/"little"/"small" → reduce by ~25–30%, not 50%.
10. Restaurant food → outside_restaurant mode with calorie uplift.
11. Warnings: only when genuinely needed — keep sparse.
12. Prefer tight realistic ranges. Do NOT return fantasy-wide ranges.
13. Coaching text: ≤ 12 words. Practical. No jargon. No internal language.

═══════════════════════════════════════════════════
OUTPUT FORMAT — RETURN ONLY VALID JSON
═══════════════════════════════════════════════════
{
  "canonicalMeal": "short readable meal name",
  "mealCategory": "breakfast|lunch|snack|dinner|mixed|unknown",
  "mealDensity": "light|moderate|dense|very_dense",
  "riskFlags": ["hidden_oil", "restaurant_portion"],
  "coachSummary": "short one-line practical meal-level note",
  "bestNextFoods": ["1 scoop whey", "150g tofu"],
  "items": [
    {
      "name": "string",
      "quantity": 1.0,
      "unit": "string",
      "estimated": false,
      "estimationMode": "direct_quantity",
      "calories": {"min": 0, "max": 0},
      "protein":  {"min": 0, "max": 0}
    }
  ],
  "calories":   {"min": 0, "max": 0},
  "protein":    {"min": 0, "max": 0},
  "confidence": 0.0,
  "warnings":   []
}''';

  String _userPrompt(String rawInput) {
    final profile = currentUserProfile;
    final profileContext = profile == null
        ? 'No user profile available. Use generalized defaults only.'
        : '''User profile for calibration only:
- Sex: ${profile.gender}
- Age: ${profile.age}
- Height: ${profile.height.toStringAsFixed(0)} cm
- Weight: ${profile.weight.toStringAsFixed(1)} kg
- Workout frequency: ${profile.workoutDaysMin}-${profile.workoutDaysMax} days/week
- Goal: ${profile.goal}
- Health sync enabled: ${profile.healthSyncEnabled ? 'yes' : 'no'}''';

    return '''$profileContext

Estimate nutrition for this meal text:
$rawInput

Return JSON only.''';
  }
}
