import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_secrets.dart';

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

  // ─── Streaming ──────────────────────────────────────────────────────────────

  /// Streams tokens from ai-meal-coach word-by-word via SSE.
  /// Yields each content delta as it arrives from the AI provider.
  Stream<String> streamMessage({
    required String  message,
    Uint8List?       imageBytes,
    String?          dateKey,
  }) async* {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      'message': message,
      'stream':  true,
      'date_key': _isoToday(dateKey),
    };
    if (imageBytes != null) {
      body['image_base64'] = base64Encode(imageBytes);
    }

    debugPrint('[AiCoachService] ↔ streaming → ai-meal-coach');

    final url     = Uri.parse('${SupabaseSecrets.url}/functions/v1/ai-meal-coach');
    final request = http.Request('POST', url)
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..headers['Content-Type']  = 'application/json'
      ..body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedRes = await client.send(request);

      if (streamedRes.statusCode != 200) {
        final errBody = await streamedRes.stream.bytesToString();
        throw Exception('ai-meal-coach ${streamedRes.statusCode}: $errBody');
      }

      // Parse SSE stream line by line
      await for (final line in streamedRes.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') return;
        try {
          final json    = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;
          final delta   = (choices[0] as Map<String, dynamic>)['delta']
              as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) yield content;
        } catch (_) {
          // skip malformed SSE lines
        }
      }
    } finally {
      client.close();
    }
  }

  /// Returns dateKey as-is if provided, otherwise today in YYYY-MM-DD format.
  String _isoToday(String? dateKey) {
    if (dateKey != null) return dateKey;
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
