import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── KynoReportService ────────────────────────────────────────────────────────
// "Report this reply": a user flags a Kyno answer as harmful, wrong or unsafe
// (Google Play generative AI policy). One row in `kyno_reports`; the table's
// RLS lets an authenticated user insert their own rows and nothing else, and
// user_id defaults to auth.uid() on the server.

/// Why a reply was reported. [code] is what the table's check constraint
/// accepts.
enum KynoReportReason {
  harmful('harmful', 'Harmful or offensive'),
  unsafe('unsafe', 'Wrong or unsafe advice'),
  other('other', 'Other');

  const KynoReportReason(this.code, this.label);
  final String code;
  final String label;
}

class KynoReportService {
  KynoReportService._();
  static final KynoReportService instance = KynoReportService._();

  static const maxNoteLength    = 500;
  static const maxMessageLength = 4000;
  static const maxPromptLength  = 2000;

  /// The row to insert. Pure, so it can be tested without a client.
  /// Throws [ArgumentError] when there is no reply text to report.
  @visibleForTesting
  static Map<String, Object?> buildRow({
    required KynoReportReason reason,
    required String message,
    String? prompt,
    String? note,
  }) {
    final reply = message.trim();
    if (reply.isEmpty) {
      throw ArgumentError.value(message, 'message', 'nothing to report');
    }
    final n = note?.trim() ?? '';
    final p = prompt?.trim() ?? '';
    return {
      'reason':  reason.code,
      'message': _clip(reply, maxMessageLength),
      'prompt':  p.isEmpty ? null : _clip(p, maxPromptLength),
      'note':    n.isEmpty ? null : _clip(n, maxNoteLength),
    };
  }

  /// Cut to at most [max] UTF-16 units without splitting a surrogate pair.
  @visibleForTesting
  static String clip(String s, int max) => _clip(s, max);

  static String _clip(String s, int max) {
    if (s.length <= max) return s;
    var end = max;
    final unit = s.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--; // lone high surrogate
    return s.substring(0, end);
  }

  /// Sends the report. Throws on no session, no connection or a server error;
  /// the caller shows a calm toast.
  Future<void> report({
    required KynoReportReason reason,
    required String message,
    String? prompt,
    String? note,
  }) async {
    final row = buildRow(reason: reason, message: message, prompt: prompt, note: note);
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      throw StateError('not authenticated');
    }
    await client
        .from('kyno_reports')
        .insert(row)
        .timeout(const Duration(seconds: 12));
  }
}
