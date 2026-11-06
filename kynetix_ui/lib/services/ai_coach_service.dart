import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_router_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_secrets.dart';
import 'profile_service.dart';
import '../services/chatgpt_link_service.dart';
import '../services/health_service.dart' show WeightContext;
import 'internal/net_timeouts.dart';

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
  /// Why the server skipped the user's ChatGPT plan for this reply
  /// ('usage_limit', 'not_eligible', 'plan_unavailable', …); null when the
  /// plan answered or isn't in use.
  final String?        planFallbackReason;

  const AiCoachResponse({
    required this.message,
    required this.providerUsed,
    required this.fallbackUsed,
    this.context,
    this.planFallbackReason,
  });

  factory AiCoachResponse.fromJson(Map<String, dynamic> j) => AiCoachResponse(
    message:      j['message']       as String? ?? '',
    providerUsed: j['provider_used'] as String? ?? 'unknown',
    fallbackUsed: j['fallback_used'] as bool?   ?? false,
    context:      j['context'] != null
        ? AiCoachContext.fromJson(j['context'] as Map<String, dynamic>)
        : null,
    planFallbackReason: AiCoachService.cleanFallbackReason(j['plan_fallback_reason']),
  );
}

// ─── AiCoachService ───────────────────────────────────────────────────────────

class AiCoachService {
  AiCoachService._();
  static final AiCoachService instance = AiCoachService._();

  /// Plan fallback reason from the latest successful reply: the
  /// `X-Fallback-Reason` header (streaming) or `plan_fallback_reason` body
  /// field. Null when the ChatGPT plan answered or isn't in use. The UI
  /// listens to this to explain why Kyno is on the standard model.
  final ValueNotifier<String?> planFallbackReason = ValueNotifier<String?>(null);

  /// Normalises a raw fallback reason: trimmed, non-empty, or null.
  static String? cleanFallbackReason(Object? raw) {
    if (raw is! String) return null;
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }

  /// Sends a message (and optional image) to ai-meal-coach.
  /// The backend injects all meal/nutrition context automatically.
  Future<AiCoachResponse> sendMessage({
    required String message,
    List<Uint8List>? imagesBytes,
    String?         dateKey,  // YYYYMMDD, defaults to today on backend if null
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
    if (imagesBytes != null && imagesBytes.isNotEmpty) {
      final base64List = imagesBytes.map((img) => base64Encode(img)).toList();
      body['images_base64'] = base64List;
      debugPrint('[AiCoachService] (4/7) sendMessage payload: attaching ${imagesBytes.length} images. Base64 lengths: ${base64List.map((s) => s.length).toList()}');
    } else {
      debugPrint('[AiCoachService] (4/7) sendMessage payload: no images attached.');
    }

    // Portion anchor (enum name); the server maps it to its own prompt text.
    addPortionAnchor(body);

    final stopwatch = Stopwatch()..start();
    try {
      final FunctionResponse res;
      try {
        res = await Supabase.instance.client.functions.invoke(
          'ai-meal-coach',
          body:    body,
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ).within(NetTimeouts.ai, 'Kyno reply');
      } on FunctionException catch (e) {
        // Router 429 / 413 pass through ai-meal-coach: typed, calm copy.
        throw AiRouterException.from(e);
      }

      final data = res.data as Map<String, dynamic>?;
      if (data == null) {
        ChatGptLinkService.recordAiRequestFailure().ignore();
        throw Exception('ai-meal-coach returned no data');
      }
      if (data['success'] != true) {
        debugPrint('[AiCoachService] ✖ error: ${data['error']}');
        ChatGptLinkService.recordAiRequestFailure().ignore();
        throw AiRouterException.fromResponse(res.status, data);
      }

      stopwatch.stop();
      final response = AiCoachResponse.fromJson(data);
      planFallbackReason.value = response.planFallbackReason;
      ChatGptLinkService.recordAiRequestSuccess(
        response.providerUsed,
        stopwatch.elapsedMilliseconds.toDouble(),
      ).ignore();

      debugPrint('[AiCoachService] (7/7) sendMessage response received: provider=${response.providerUsed} fallback=${response.fallbackUsed} message length=${response.message.length}');
      return response;
    } catch (e) {
      ChatGptLinkService.recordAiRequestFailure().ignore();
      rethrow;
    }
  }

  // ─── Streaming ──────────────────────────────────────────────────────────────

  /// Streams tokens from ai-meal-coach word-by-word via SSE.
  /// Yields each content delta as it arrives from the AI provider.
  Stream<String> streamMessage({
    required String  message,
    List<Uint8List>? imagesBytes,
    String?          dateKey,
    bool?            isGymDay,     // client real-time value, overrides stale DB
    String?          workoutType,  // e.g. 'Push', 'Pull', 'Chest + Triceps'
    double?          targetCaloriesOverride, // active manual override for this day
    List<Map<String, String>>? conversationHistory, // prior turns for multi-turn context
    WeightContext?   weightContext, // compact weight summary for Kyno coaching
    Map<String, dynamic>? appContext, // KynoBriefService brief: targets, trends, food options
  }) async* {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      'message': message,
      'stream':  true,
      'date_key': _isoToday(dateKey),
    };
    if (imagesBytes != null && imagesBytes.isNotEmpty) {
      final base64List = imagesBytes.map((img) => base64Encode(img)).toList();
      body['images_base64'] = base64List;
      debugPrint('[AiCoachService] (4/7) streamMessage payload: attaching ${imagesBytes.length} images. Base64 lengths: ${base64List.map((s) => s.length).toList()}');
    } else {
      debugPrint('[AiCoachService] (4/7) streamMessage payload: no images attached.');
    }
    // Pass client gym state so edge function uses real-time data instead of stale DB
    if (isGymDay != null) {
      body['is_gym_day']   = isGymDay;
      body['workout_type'] = workoutType ?? '';
    }
    // Pass manual calorie override so AI uses the correct effective target for this day.
    // Omit entirely when null so the server falls back to DB-stored override or formula.
    if (targetCaloriesOverride != null) {
      body['target_calories_override'] = targetCaloriesOverride;
    }
    // Pass conversation history so AI has full context from prior messages.
    // Limit to last 10 messages to avoid excessive tokens.
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      final limited = conversationHistory.length > 10
          ? conversationHistory.sublist(conversationHistory.length - 10)
          : conversationHistory;
      body['history'] = limited;
    }
    // Portion anchor (enum name); the server maps it to its own prompt text.
    addPortionAnchor(body);

    // The app's own numbers (targets with steps and manual targets, 14-day
    // eating, lift trends, food options). The server fences it as data.
    if (appContext != null) body['app_context'] = appContext;

    // Weight context — compact summary only, never raw history.
    // The edge function puts toPromptString() in the fenced user-data block
    // of its system prompt; low_confidence_weight makes it hedge weight claims.
    if (weightContext != null) {
      body['weight_context'] = weightContext.toPromptString();
      if (weightContext.quality.confidenceLabel == 'low') {
        body['low_confidence_weight'] = true;
      }
    }

    final stopwatch = Stopwatch()..start();
    final url     = Uri.parse('${SupabaseSecrets.url}/functions/v1/ai-meal-coach');
    final request = http.Request('POST', url)
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..headers['Content-Type']  = 'application/json'
      ..body = jsonEncode(body);

    final client = http.Client();
    try {
      // Bound only the wait for the response to start; the stream itself
      // may run as long as the reply takes.
      final streamedRes = await client
          .send(request)
          .within(NetTimeouts.aiFirstByte, 'Kyno stream start');

      if (streamedRes.statusCode != 200) {
        final errBody = await streamedRes.stream.bytesToString();
        ChatGptLinkService.recordAiRequestFailure().ignore();
        // Typed and calm (rate limit, too long, …); the raw body is never
        // shown.
        final err = AiRouterException.fromResponse(streamedRes.statusCode, errBody);
        debugPrint('[AiCoachService] ✖ stream rejected: $err');
        throw err;
      }

      stopwatch.stop();
      // http lower-cases header names.
      planFallbackReason.value =
          cleanFallbackReason(streamedRes.headers['x-fallback-reason']);
      ChatGptLinkService.recordAiRequestSuccess(
        'openai',
        stopwatch.elapsedMilliseconds.toDouble(),
      ).ignore();

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

  /// Adds the user's portion anchor as its enum name ('carbAnchored',
  /// 'curryAnchored', 'balanced') when set. ai-meal-coach owns the prompt
  /// text for each anchor.
  @visibleForTesting
  static void addPortionAnchor(Map<String, dynamic> body) {
    final anchor = ProfileService.instance.currentUserProfile?.portionAnchor;
    if (anchor != null) body['portion_anchor'] = anchor.name;
  }
}
