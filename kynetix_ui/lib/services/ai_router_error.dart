import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

/// What went wrong with an AI request, in terms the UI can act on.
enum AiRouterErrorKind {
  /// 429, scope 'minute': short burst limit. Retry in about a minute.
  rateLimitedMinute,

  /// 429, scope 'day': today's AI allowance is used up. Resets tomorrow.
  rateLimitedDay,

  /// 429, scope 'images': today's photo allowance is used up. Text still works.
  rateLimitedImages,

  /// 413: message too long, too many messages, or too many / too large photos.
  tooLarge,

  /// Anything else (400 unknown_purpose, 5xx, network, malformed body).
  generic,
}

/// A calm, typed error for ai-chat-router / ai-meal-coach failures. The raw
/// response body is never shown to the user: [userMessage] is fixed copy per
/// [kind], and [code] / [status] are kept for logs only.
class AiRouterException implements Exception {
  const AiRouterException(
    this.kind, {
    this.status,
    this.code,
    this.retryAfterSeconds,
  });

  final AiRouterErrorKind kind;
  final int? status;

  /// Same as [status]; read by UI code that duck-types `statusCode`.
  int? get statusCode => status;

  /// Server error code (e.g. 'rate_limited', 'too_many_chars'). Logs only.
  final String? code;

  /// Seconds until a retry can succeed, when the server said so.
  final int? retryAfterSeconds;

  static const minuteLimitMessage = "You're going fast. Try again in a minute.";
  static const dayLimitMessage = "That's today's AI limit. It resets tomorrow.";
  static const imageLimitMessage =
      "That's today's photo limit for Kyno. Text questions still work, and photos reset tomorrow.";
  static const tooLargeMessage =
      "That's a bit too long. Try a shorter message or fewer photos.";
  static const genericMessage = "Kyno couldn't answer just now. Try again.";

  /// Copy safe to show as-is.
  String get userMessage => switch (kind) {
        AiRouterErrorKind.rateLimitedMinute => minuteLimitMessage,
        AiRouterErrorKind.rateLimitedDay => dayLimitMessage,
        AiRouterErrorKind.rateLimitedImages => imageLimitMessage,
        AiRouterErrorKind.tooLarge => tooLargeMessage,
        AiRouterErrorKind.generic => genericMessage,
      };

  bool get isRateLimited =>
      kind == AiRouterErrorKind.rateLimitedMinute ||
      kind == AiRouterErrorKind.rateLimitedDay ||
      kind == AiRouterErrorKind.rateLimitedImages;

  /// Maps an HTTP status plus the (already decoded, or raw string) error body.
  factory AiRouterException.fromResponse(int status, Object? body) {
    Map<String, dynamic>? json;
    if (body is Map) {
      json = body.cast<String, dynamic>();
    } else if (body is String && body.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) json = decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    final code = json?['error'] is String ? json!['error'] as String : null;
    final retryRaw = json?['retry_after'];
    final retryAfter = retryRaw is num ? retryRaw.ceil() : null;

    if (status == 429) {
      final scope = json?['scope'];
      return AiRouterException(
        switch (scope) {
          'day' => AiRouterErrorKind.rateLimitedDay,
          'images' => AiRouterErrorKind.rateLimitedImages,
          _ => AiRouterErrorKind.rateLimitedMinute,
        },
        status: status,
        code: code ?? 'rate_limited',
        retryAfterSeconds: retryAfter,
      );
    }
    if (status == 413) {
      return AiRouterException(AiRouterErrorKind.tooLarge,
          status: status, code: code);
    }
    return AiRouterException(AiRouterErrorKind.generic,
        status: status, code: code, retryAfterSeconds: retryAfter);
  }

  /// Maps any error thrown while calling an AI function. Already-typed errors
  /// pass through; [FunctionException]s are mapped by status; everything else
  /// becomes [AiRouterErrorKind.generic].
  factory AiRouterException.from(Object error) {
    if (error is AiRouterException) return error;
    if (error is FunctionException) {
      return AiRouterException.fromResponse(error.status, error.details);
    }
    return const AiRouterException(AiRouterErrorKind.generic);
  }

  @override
  String toString() =>
      'AiRouterException(${kind.name}, status: $status, code: $code)';
}
