import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── AiCoachResponse ──────────────────────────────────────────────────────────

class AiCoachContext {
  final bool   isGymDay;
  final int    targetCal;
  final int    targetPro;
  final int    consumedCal;
  final int    consumedPro;
  final int    remainCal;
  final int    remainPro;

  const AiCoachContext({
    required this.isGymDay,
    required this.targetCal,
    required this.targetPro,
    required this.consumedCal,
    required this.consumedPro,
    required this.remainCal,
    required this.remainPro,
  });

  factory AiCoachContext.fromJson(Map<String, dynamic> j) => AiCoachContext(
    isGymDay:    j['is_gym_day']   as bool? ?? false,
    targetCal:   j['target_cal']   as int?  ?? 0,
    targetPro:   j['target_pro']   as int?  ?? 0,
    consumedCal: j['consumed_cal'] as int?  ?? 0,
    consumedPro: j['consumed_pro'] as int?  ?? 0,
    remainCal:   j['remain_cal']   as int?  ?? 0,
    remainPro:   j['remain_pro']   as int?  ?? 0,
  );
}

class AiCoachResponse {
  final String         message;
  final String         providerUsed;   // 'openai' | 'openrouter' | 'none'
  final bool           fallbackUsed;
  final AiCoachContext? context;

  const AiCoachResponse({
    required this.message,
    required this.providerUsed,
    required this.fallbackUsed,
    this.context,
  });

  factory AiCoachResponse.fromJson(Map<String, dynamic> j) => AiCoachResponse(
    message:      j['message']       as String? ?? '',
    providerUsed: j['provider_used'] as String? ?? 'unknown',
    fallbackUsed: j['fallback_used'] as bool?   ?? false,
    context:      j['context'] != null
        ? AiCoachContext.fromJson(j['context'] as Map<String, dynamic>)
        : null,
  );
}

// ─── AiCoachService ───────────────────────────────────────────────────────────

class AiCoachService {
  AiCoachService._();
  static final AiCoachService instance = AiCoachService._();

  /// Sends a message (and optional image) to ai-meal-coach.
  /// The backend injects all meal/nutrition context automatically.
  Future<AiCoachResponse> sendMessage({
    required String message,
    Uint8List?      imageBytes,
    String?         dateKey,  // YYYYMMDD — defaults to today on backend if null
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    // Build request body
    final Map<String, dynamic> body = {
      'message': message,
    };

    // Date key — must match YYYY-MM-DD format used by cloud_sync_service / day_logs table.
    if (dateKey != null) {
      body['date_key'] = dateKey;
    } else {
      final now = DateTime.now();
      body['date_key'] = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
    }

    // Image encoding
    if (imageBytes != null) {
      body['image_base64'] = base64Encode(imageBytes);
      debugPrint('[AiCoachService] attaching image ${imageBytes.length} bytes');
    }

    debugPrint('[AiCoachService] → ai-meal-coach message="${message.substring(0, message.length.clamp(0, 80))}"');

    final res = await Supabase.instance.client.functions.invoke(
      'ai-meal-coach',
      body:    body,
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );

    final data = res.data as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('ai-meal-coach returned no data');
    }
    if (data['success'] != true) {
      final err = data['error'] ?? 'Unknown error from ai-meal-coach';
      debugPrint('[AiCoachService] ✖ error: $err');
      throw Exception(err);
    }

    final response = AiCoachResponse.fromJson(data);
    debugPrint('[AiCoachService] ✔ provider=${response.providerUsed} fallback=${response.fallbackUsed}');
    return response;
  }
}
