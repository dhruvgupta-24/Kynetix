import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_router_error.dart';

/// What Kyno read off a nutrition table. Every value is a suggestion until
/// the person confirms it in the form; nothing here is logged or saved as-is.
class LabelReading {
  final String? productName;
  final String? brand;

  /// 'g' or 'ml': what the table is printed per (per 100 g / per 100 ml).
  final String unit;

  /// Net contents of the pack, in [unit], when printed.
  final double? netQuantity;
  final double? servingSize;

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double? fiberG;
  final double? sugarG;

  const LabelReading({
    required this.unit,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.productName,
    this.brand,
    this.netQuantity,
    this.servingSize,
    this.fiberG,
    this.sugarG,
  });

  /// Parse the router's canonical JSON (already validated server-side; this
  /// re-checks because a client must not trust a response shape blindly).
  /// Returns null when it is not a readable label.
  static LabelReading? tryParse(String text) {
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
    if (decoded is! Map) return null;
    final j = decoded.cast<String, dynamic>();
    if (j['readable'] != true) return null;
    final per = j['per_100'];
    if (per is! Map) return null;

    double? n(Object? v, {double max = 100000}) {
      final d = v is num ? v.toDouble() : null;
      return d != null && d.isFinite && d >= 0 && d <= max ? d : null;
    }

    String? str(Object? v) {
      final s = v is String ? v.trim() : '';
      return s.isEmpty ? null : (s.length > 80 ? s.substring(0, 80) : s);
    }

    final kcal = n(per['energy_kcal'], max: 900);
    final protein = n(per['protein_g'], max: 100);
    final carbs = n(per['carbohydrates_g'], max: 100);
    final fat = n(per['fat_g'], max: 100);
    if (kcal == null || protein == null || carbs == null || fat == null) {
      return null;
    }
    final basis = j['basis'];
    final unit = basis == 'per_100ml' || j['net_unit'] == 'ml' ? 'ml' : 'g';
    final net = n(j['net_quantity']);

    return LabelReading(
      productName: str(j['product_name']),
      brand: str(j['brand']),
      unit: unit,
      netQuantity: net != null && net > 0 ? net : null,
      servingSize: n(j['serving_size'], max: 1000),
      calories: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      fiberG: n(per['fibre_g'], max: 100),
      sugarG: n(per['sugar_g'], max: 100),
    );
  }
}

/// Why a label read failed, in terms the UI can act on.
enum LabelReadFailure { unreadable, rateLimited, tooLarge, offline }

class LabelReadException implements Exception {
  final LabelReadFailure kind;
  const LabelReadException(this.kind);

  /// Calm copy per VOICE.md: what happened, what to do.
  String get userMessage => switch (kind) {
        LabelReadFailure.unreadable =>
          "Couldn't read that label. Try a sharper photo of the nutrition table, or enter it yourself.",
        LabelReadFailure.rateLimited =>
          "That's today's AI limit for now. You can still enter it yourself.",
        LabelReadFailure.tooLarge =>
          'That photo is too large. Try again a little further from the pack.',
        LabelReadFailure.offline =>
          "Couldn't reach Kyno. Check your connection and try again.",
      };

  @override
  String toString() => 'LabelReadException(${kind.name})';
}

/// Sends one photo of a nutrition table to ai-chat-router with purpose
/// `label_read`. The server owns the prompt and validates the JSON it returns;
/// this only sends the photo and maps the answer.
class BarcodeLabelReader {
  BarcodeLabelReader._();
  static final BarcodeLabelReader instance = BarcodeLabelReader._();

  /// Fixed instruction text. The server prompt does the real work; this is
  /// just the user turn that carries the image.
  static const userText = 'Read this nutrition label.';

  /// Injectable for tests: receives the request body, returns the decoded
  /// router response (a Map) or throws.
  @visibleForTesting
  Future<Object?> Function(Map<String, dynamic> body)? invokeOverride;

  /// The router request body for one JPEG photo.
  @visibleForTesting
  static Map<String, dynamic> buildRequestBody(Uint8List jpeg) => {
        'purpose': 'label_read',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': userText},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,${base64Encode(jpeg)}',
                },
              },
            ],
          },
        ],
      };

  Future<LabelReading> read(Uint8List jpeg) async {
    final body = buildRequestBody(jpeg);
    Object? data;
    try {
      if (invokeOverride != null) {
        data = await invokeOverride!(body);
      } else {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          throw const LabelReadException(LabelReadFailure.offline);
        }
        final res = await Supabase.instance.client.functions.invoke(
          'ai-chat-router',
          body: body,
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ).timeout(const Duration(seconds: 25));
        // A stalled network times out into the "offline" failure, which
        // reveals the form so the user can type the values instead.
        data = res.data;
      }
    } on LabelReadException {
      rethrow;
    } on FunctionException catch (e) {
      throw _map(e.status, e.details);
    } catch (e) {
      debugPrint('[LabelRead] failed: $e');
      throw const LabelReadException(LabelReadFailure.offline);
    }

    final map = data is Map ? data.cast<String, dynamic>() : null;
    if (map == null || map['success'] != true) {
      throw _map(200, map);
    }
    final reading = LabelReading.tryParse('${map['response'] ?? ''}');
    if (reading == null) {
      throw const LabelReadException(LabelReadFailure.unreadable);
    }
    return reading;
  }

  static LabelReadException _map(int status, Object? details) {
    final err = AiRouterException.fromResponse(status, details);
    if (err.isRateLimited) {
      return const LabelReadException(LabelReadFailure.rateLimited);
    }
    if (err.kind == AiRouterErrorKind.tooLarge) {
      return const LabelReadException(LabelReadFailure.tooLarge);
    }
    if (err.code == 'label_unreadable' || status == 422) {
      return const LabelReadException(LabelReadFailure.unreadable);
    }
    return const LabelReadException(LabelReadFailure.offline);
  }
}
