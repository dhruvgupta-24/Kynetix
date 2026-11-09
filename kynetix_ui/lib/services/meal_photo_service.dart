import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nutrition_result.dart';
import 'ai_router_error.dart';
import 'item_parser.dart';
import 'nutrition_pipeline.dart';

/// One food Kyno saw on the plate. Every number is Kyno's estimate until the
/// person confirms the rows in the review screen; nothing here is logged as-is.
@immutable
class MealPhotoFood {
  /// Plain lowercase name the app's parser understands ("dal tadka").
  final String name;

  /// Pieces for foods eaten by the piece (roti, egg, idli), else null.
  final double? count;

  /// 'piece', 'g' or 'ml'.
  final String unit;

  /// Edible weight (or volume) Kyno saw, for all pieces together.
  final double grams;

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;

  /// 0 to 1: how sure Kyno is of the food and its amount.
  final double confidence;

  const MealPhotoFood({
    required this.name,
    required this.unit,
    required this.grams,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.confidence,
    this.count,
  });

  bool get byPiece => unit == 'piece' && count != null;

  /// Low confidence is worth a second look in the review screen.
  bool get unsure => confidence < 0.55;

  /// How a person would type it: "3 roti", "150 g dal tadka", "250 ml lassi".
  String get line {
    if (byPiece) return '${_fmt(count!)} $name';
    final amount = grams.round();
    return '$amount ${unit == 'ml' ? 'ml' : 'g'} $name';
  }

  /// Short amount for display: "3 pcs", "150 g", "250 ml".
  String get amountLabel {
    if (byPiece) {
      final c = _fmt(count!);
      return count == 1 ? '1 pc' : '$c pcs';
    }
    return '${grams.round()} ${unit == 'ml' ? 'ml' : 'g'}';
  }

  /// 3 -> "3", 1.5 -> "1.5", 0.25 -> "0.25" (counts come in quarters).
  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    if (v * 2 == (v * 2).roundToDouble()) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  /// The parsed form the pipeline consumes. The app's own parser reads the
  /// line (so "150 g dal tadka" is 150 g of "dal tadka", with the same
  /// spelling fixes as typed input); a name the parser would split in two
  /// ("bread and butter") is kept whole.
  ParsedFoodItem get parsed {
    final p = ItemParser.parse(line);
    if (p.length == 1 && p.first.normalizedName.trim().isNotEmpty) return p.first;
    return ParsedFoodItem(
      rawChunk: line,
      normalizedName: name,
      quantity: byPiece ? count! : grams.roundToDouble(),
      unit: byPiece ? 'serving' : (unit == 'ml' ? 'ml' : 'g'),
    );
  }

  /// Kyno's numbers as a pipeline item at the parsed amount.
  NutritionItem toItem(ParsedFoodItem p) {
    NutrientRange r(double v) => NutrientRange(min: v, max: v);
    return NutritionItem(
      name: p.normalizedName,
      quantity: p.quantity,
      unit: p.unit,
      estimated: true,
      mode: EstimationMode.directQuantity,
      calories: r(kcal),
      protein: r(proteinG),
      carbohydrates: r(carbsG),
      fat: r(fatG),
      fiber: r(fiberG),
    );
  }

  /// Parses one canonical item from the router. The server already
  /// validated it; this re-checks, because a client must not trust a
  /// response shape blindly. Null when unusable.
  static MealPhotoFood? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    double? n(Object? v, double max) {
      final d = v is num ? v.toDouble() : null;
      return d != null && d.isFinite && d >= 0 && d <= max ? d : null;
    }

    final name = j['name'] is String ? (j['name'] as String).trim() : '';
    if (name.length < 2 || name.length > 40 || !RegExp(r"^[a-z0-9 &'\-]+$").hasMatch(name)) {
      return null;
    }
    final grams = n(j['grams'], 2000);
    final kcal = n(j['kcal'], 2500);
    final p = n(j['protein_g'], 200);
    final c = n(j['carbs_g'], 400);
    final f = n(j['fat_g'], 200);
    if (grams == null || grams < 1 || kcal == null || p == null || c == null || f == null) {
      return null;
    }
    final unitRaw = j['unit'];
    final count = n(j['count'], 30);
    final unit = unitRaw == 'piece' && count != null && count > 0
        ? 'piece'
        : unitRaw == 'ml'
            ? 'ml'
            : 'g';
    return MealPhotoFood(
      name: name,
      count: unit == 'piece' ? count : null,
      unit: unit,
      grams: grams,
      kcal: kcal,
      proteinG: p,
      carbsG: c,
      fatG: f,
      fiberG: n(j['fiber_g'], 100) ?? 0,
      confidence: (n(j['confidence'], 1) ?? 0.5),
    );
  }
}

/// Everything Kyno read off one meal photo.
@immutable
class MealPhotoReading {
  /// A short name for the plate ("dal chawal with salad"), when Kyno gave one.
  final String? title;
  final List<MealPhotoFood> foods;

  const MealPhotoReading({required this.foods, this.title});

  /// The meal as a person would type it, used as the composer text and the
  /// meal's saved input: "3 roti, 150 g dal tadka, 100 g jeera rice".
  String get mealText => foods.map((f) => f.line).join(', ');

  double get kcal => foods.fold(0, (a, f) => a + f.kcal);

  static MealPhotoReading? tryParse(String text) {
    Object? decoded;
    try {
      var t = text.trim();
      if (t.startsWith('```')) {
        t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '');
        t = t.replaceFirst(RegExp(r'```\s*$'), '');
      }
      decoded = jsonDecode(t.trim());
    } catch (_) {
      return null;
    }
    if (decoded is! Map || decoded['is_food'] != true) return null;
    final items = decoded['items'];
    if (items is! List) return null;
    final foods = <MealPhotoFood>[];
    final seen = <String>{};
    for (final raw in items.take(12)) {
      final f = MealPhotoFood.tryParse(raw);
      if (f != null && seen.add(f.name)) foods.add(f);
    }
    if (foods.isEmpty) return null;
    final title = decoded['title'];
    return MealPhotoReading(
      foods: foods,
      title: title is String && title.trim().isNotEmpty && title.length <= 60 ? title.trim() : null,
    );
  }

  /// Runs the foods through the app's own pipeline, exactly like a typed
  /// meal: the person's saved numbers, the curry table and the food library
  /// come first, and Kyno's photo numbers fill in only what the app does
  /// not know. [pipeline] is injectable for tests.
  Future<NutritionResult> estimate({NutritionPipeline? pipeline}) async {
    final parsed = <ParsedFoodItem>[];
    final estimates = <String, NutritionItem>{};
    for (final f in foods) {
      final p = f.parsed;
      parsed.add(p);
      estimates[p.normalizedName.toLowerCase().trim()] = f.toItem(p);
    }
    return (pipeline ?? NutritionPipeline.instance).estimateMeal(
      mealText,
      preParsed: parsed,
      photoEstimates: estimates,
    );
  }
}

/// Why a meal photo could not be read, in terms the UI can act on.
enum MealPhotoFailure { notFood, unreadable, rateLimited, tooLarge, teenMode, offline }

class MealPhotoException implements Exception {
  final MealPhotoFailure kind;

  /// The router's own calm copy for rate limits (minute, day or photos).
  final String? limitMessage;

  const MealPhotoException(this.kind, {this.limitMessage});

  /// Calm copy per VOICE.md: what happened, what to do.
  String get userMessage => switch (kind) {
        MealPhotoFailure.notFood => "That doesn't look like food. Try a photo of the plate.",
        MealPhotoFailure.unreadable =>
          "Couldn't make out that meal. Try a clearer photo from above, or describe it instead.",
        MealPhotoFailure.rateLimited =>
          limitMessage ?? "That's today's photo limit. You can still describe the meal.",
        MealPhotoFailure.tooLarge => 'That photo is too large. Try again, a little further back.',
        MealPhotoFailure.teenMode => AiRouterException.teenModeMessage,
        MealPhotoFailure.offline => "Couldn't reach Kyno. Check your connection and try again.",
      };

  /// Retake helps for these; for the others, describing the meal is the way on.
  bool get retakeHelps =>
      kind == MealPhotoFailure.notFood ||
      kind == MealPhotoFailure.unreadable ||
      kind == MealPhotoFailure.tooLarge;

  @override
  String toString() => 'MealPhotoException(${kind.name})';
}

/// Sends one meal photo to ai-chat-router with purpose `meal_photo`. The
/// server owns the prompt and validates the JSON it returns; this only sends
/// the photo (and the person's optional note) and maps the answer.
class MealPhotoService {
  MealPhotoService._();
  static final MealPhotoService instance = MealPhotoService._();

  /// Fixed instruction text; the server prompt does the real work.
  static const userText = 'Log this meal.';

  /// Longest note sent with a photo ("mutton, not chicken").
  static const maxNote = 200;

  /// Injectable for tests: receives the request body, returns the decoded
  /// router response (a Map) or throws.
  @visibleForTesting
  Future<Object?> Function(Map<String, dynamic> body)? invokeOverride;

  @visibleForTesting
  static Map<String, dynamic> buildRequestBody(Uint8List jpeg, {String? note}) {
    final n = (note ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final clipped = n.length > maxNote ? n.substring(0, maxNote) : n;
    return {
      'purpose': 'meal_photo',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': clipped.isEmpty ? userText : '$userText Note from me: $clipped',
            },
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(jpeg)}'},
            },
          ],
        },
      ],
    };
  }

  Future<MealPhotoReading> read(Uint8List jpeg, {String? note}) async {
    final body = buildRequestBody(jpeg, note: note);
    Object? data;
    try {
      if (invokeOverride != null) {
        data = await invokeOverride!(body);
      } else {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) throw const MealPhotoException(MealPhotoFailure.offline);
        final res = await Supabase.instance.client.functions
            .invoke(
              'ai-chat-router',
              body: body,
              headers: {'Authorization': 'Bearer ${session.accessToken}'},
            )
            .timeout(const Duration(seconds: 60));
        data = res.data;
      }
    } on MealPhotoException {
      rethrow;
    } on FunctionException catch (e) {
      throw _map(e.status, e.details);
    } catch (e) {
      debugPrint('[MealPhoto] failed: ${e.runtimeType}');
      throw const MealPhotoException(MealPhotoFailure.offline);
    }

    final map = data is Map ? data.cast<String, dynamic>() : null;
    if (map == null || map['success'] != true) throw _map(200, map);
    final reading = MealPhotoReading.tryParse('${map['response'] ?? ''}');
    if (reading == null) throw const MealPhotoException(MealPhotoFailure.unreadable);
    return reading;
  }

  static MealPhotoException _map(int status, Object? details) {
    final err = AiRouterException.fromResponse(status, details);
    if (err.isRateLimited) {
      return MealPhotoException(MealPhotoFailure.rateLimited, limitMessage: err.userMessage);
    }
    if (err.kind == AiRouterErrorKind.teenMode) return const MealPhotoException(MealPhotoFailure.teenMode);
    if (err.kind == AiRouterErrorKind.tooLarge) return const MealPhotoException(MealPhotoFailure.tooLarge);
    if (err.code == 'not_food') return const MealPhotoException(MealPhotoFailure.notFood);
    if (err.code == 'photo_unreadable' || status == 422) {
      return const MealPhotoException(MealPhotoFailure.unreadable);
    }
    return const MealPhotoException(MealPhotoFailure.offline);
  }
}
