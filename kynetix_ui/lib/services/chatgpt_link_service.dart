import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_client.dart';

// ─── Data models ──────────────────────────────────────────────────────────────

class DeviceCodeSession {
  final String sessionId;
  final String userCode;
  final String verificationUrl;
  final int intervalSeconds;
  final DateTime expiresAt;

  const DeviceCodeSession({
    required this.sessionId,
    required this.userCode,
    required this.verificationUrl,
    required this.intervalSeconds,
    required this.expiresAt,
  });
}

enum LinkPollStatus { pending, connected, expired, error }

class LinkPollResult {
  final LinkPollStatus status;
  final String? message;
  const LinkPollResult(this.status, {this.message});
}

class ChatGptLinkStatus {
  final bool isConnected;
  final bool tokenExpired;
  final String activeProvider;   // 'user_chatgpt' | 'openrouter'
  final String? activeModel;     // model currently in use
  final String? selectedModel;   // model selected by discovery
  final String? lastProviderUsed;
  final DateTime? lastUsedAt;
  final DateTime? connectedAt;
  final DateTime? expiresAt;
  final bool modelDiscoveryVerified;
  final List<String>? chatCapableModels;
  final DateTime? discoveryTimestamp;

  const ChatGptLinkStatus({
    required this.isConnected,
    this.tokenExpired = false,
    required this.activeProvider,
    this.activeModel,
    this.selectedModel,
    this.lastProviderUsed,
    this.lastUsedAt,
    this.connectedAt,
    this.expiresAt,
    this.modelDiscoveryVerified = false,
    this.chatCapableModels,
    this.discoveryTimestamp,
  });

  static ChatGptLinkStatus get disconnected => const ChatGptLinkStatus(
        isConnected: false,
        activeProvider: 'openrouter',
      );
}

class ModelVerificationResult {
  final bool success;
  final String? selectedModel;
  final String? selectionReason;
  final List<String> chatModelsFound;
  final List<String> allDiscovered;
  final String? testSnippet;
  final String? error;
  final List<Map<String, dynamic>> generationTested;

  const ModelVerificationResult({
    required this.success,
    this.selectedModel,
    this.selectionReason,
    this.chatModelsFound = const [],
    this.allDiscovered = const [],
    this.testSnippet,
    this.error,
    this.generationTested = const [],
  });
}

// ─── Service ──────────────────────────────────────────────────────────────────

class ChatGptLinkService {
  // ── Phase A: Initiate device-code auth flow ────────────────────────────────

  static Future<DeviceCodeSession> startLink() async {
    debugPrint('[ChatGptLinkService] startLink()');
    final res = await supabase.functions.invoke(
      'openai-link-start',
      method: HttpMethod.post,
    );

    if (res.data == null) {
      throw Exception('Empty response from openai-link-start');
    }

    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) {
      final code = data['error'] as String? ?? 'unknown';
      if (code == 'device_code_disabled') {
        throw DeviceCodeDisabledException(
          data['message'] as String? ??
              'Enable device code authorization in ChatGPT settings.',
        );
      }
      throw Exception('openai-link-start error: $code — ${data['message']}');
    }

    return DeviceCodeSession(
      sessionId:       data['session_id'] as String,
      userCode:        data['user_code'] as String,
      verificationUrl: data['verification_url'] as String,
      intervalSeconds: data['interval_seconds'] as int? ?? 5,
      expiresAt:       DateTime.parse(data['expires_at'] as String),
    );
  }

  // ── Phase B: Poll for auth completion ─────────────────────────────────────

  static Future<LinkPollResult> pollLink(String sessionId) async {
    try {
      final res = await supabase.functions.invoke(
        'openai-link-poll',
        method: HttpMethod.post,
        body: {'session_id': sessionId},
      );

      if (res.data == null) return const LinkPollResult(LinkPollStatus.error, message: 'Empty response');

      final data = Map<String, dynamic>.from(res.data as Map);
      final status = data['status'] as String? ?? 'error';

      return switch (status) {
        'connected' => const LinkPollResult(LinkPollStatus.connected),
        'expired'   => LinkPollResult(LinkPollStatus.expired, message: data['reason'] as String?),
        'pending'   => const LinkPollResult(LinkPollStatus.pending),
        _           => LinkPollResult(LinkPollStatus.error, message: data['message'] as String?),
      };
    } catch (e) {
      debugPrint('[ChatGptLinkService] pollLink error: $e');
      return LinkPollResult(LinkPollStatus.error, message: e.toString());
    }
  }

  // ── Phase D/E: Run model discovery + generation verification ───────────────

  static Future<ModelVerificationResult> verifyAndSelectModel() async {
    debugPrint('[ChatGptLinkService] verifyAndSelectModel()');
    try {
      final res = await supabase.functions.invoke(
        'openai-link-verify',
        method: HttpMethod.post,
      );

      if (res.data == null) {
        return const ModelVerificationResult(
          success: false,
          error: 'Empty response from openai-link-verify',
        );
      }

      final data = Map<String, dynamic>.from(res.data as Map);
      final success = data['success'] as bool? ?? false;

      final chatModels = (data['chat_models_found'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      final allDiscovered = (data['all_discovered'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      final tested = (data['generation_tested'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [];

      return ModelVerificationResult(
        success:          success,
        selectedModel:    data['selected_model'] as String?,
        selectionReason:  data['selection_reason'] as String?,
        chatModelsFound:  chatModels,
        allDiscovered:    allDiscovered,
        testSnippet:      data['test_snippet'] as String?,
        error:            data['error'] as String?,
        generationTested: tested,
      );
    } catch (e) {
      debugPrint('[ChatGptLinkService] verifyAndSelectModel error: $e');
      return ModelVerificationResult(success: false, error: e.toString());
    }
  }

  // ── Phase G: Get current connection status ─────────────────────────────────

  static Future<ChatGptLinkStatus> getStatus() async {
    try {
      final res = await supabase.functions.invoke(
        'openai-link-status',
        method: HttpMethod.post,
      );

      if (res.data == null) return ChatGptLinkStatus.disconnected;

      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['error'] != null) return ChatGptLinkStatus.disconnected;

      final discoveredRaw = data['discovered_models'];
      List<String>? chatModels;
      if (discoveredRaw is Map) {
        chatModels = (discoveredRaw['chat_capable'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList();
      }

      return ChatGptLinkStatus(
        isConnected:             data['is_connected'] as bool? ?? false,
        tokenExpired:            data['token_expired'] as bool? ?? false,
        activeProvider:          data['active_provider'] as String? ?? 'openrouter',
        activeModel:             data['active_model'] as String?,
        selectedModel:           data['selected_model'] as String?,
        lastProviderUsed:        data['last_provider_used'] as String?,
        lastUsedAt:              _parseDate(data['last_used_at']),
        connectedAt:             _parseDate(data['connected_at']),
        expiresAt:               _parseDate(data['expires_at']),
        modelDiscoveryVerified:  data['model_discovery_verified'] as bool? ?? false,
        chatCapableModels:       chatModels,
        discoveryTimestamp:      _parseDate(data['discovery_timestamp']),
      );
    } catch (e) {
      debugPrint('[ChatGptLinkService] getStatus error: $e');
      return ChatGptLinkStatus.disconnected;
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  static Future<void> disconnect() async {
    debugPrint('[ChatGptLinkService] disconnect()');
    await supabase.functions.invoke(
      'openai-link-disconnect',
      method: HttpMethod.post,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try { return DateTime.parse(raw as String); } catch (_) { return null; }
  }
}

// ─── Custom exceptions ────────────────────────────────────────────────────────

class DeviceCodeDisabledException implements Exception {
  final String message;
  const DeviceCodeDisabledException(this.message);
  @override
  String toString() => 'DeviceCodeDisabledException: $message';
}
