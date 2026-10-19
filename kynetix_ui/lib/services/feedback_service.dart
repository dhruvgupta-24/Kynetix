import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'kyno_report_service.dart';

// ─── FeedbackService ──────────────────────────────────────────────────────────
// "Talk to us": a user sends an idea, a bug, some love or anything else. One
// row in `feedback`; RLS lets any signed-in user insert their own rows, and
// user_id defaults to auth.uid() on the server.
//
// Curators (rows in `app_curators`, the owner among them) also get an inbox:
// they can read every feedback row and every Kyno report, and move each one
// from new to read to done. Everyone else reads nothing back.

/// What kind of feedback it is. [code] is what the table's check constraint
/// accepts; [hint] is the text field's placeholder for that kind.
enum FeedbackKind {
  idea('idea', 'Idea', 'What should Kynetix do next?'),
  bug('bug', 'Bug', 'What broke, and what were you doing?'),
  love('love', 'Love it', 'Go on. We can take it.'),
  other('other', 'Other', "Whatever's on your mind.");

  const FeedbackKind(this.code, this.label, this.hint);
  final String code;
  final String label;
  final String hint;

  static FeedbackKind? fromCode(String? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Where an inbox item sits. [code] matches the tables' status column.
enum InboxStatus {
  fresh('new', 'New'),
  read('read', 'Read'),
  done('done', 'Done');

  const InboxStatus(this.code, this.label);
  final String code;
  final String label;

  /// Unknown or missing codes read as new, so nothing hides by accident.
  static InboxStatus fromCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return InboxStatus.fresh;
  }
}

/// Which table an inbox item came from.
enum InboxSource { feedback, report }

/// One row in the owner inbox, from either table.
@immutable
class InboxItem {
  const InboxItem({
    required this.id,
    required this.source,
    required this.createdAt,
    required this.label,
    required this.message,
    required this.status,
    this.replyTo,
    this.appVersion,
    this.platform,
    this.note,
    this.prompt,
  });

  final String id;
  final InboxSource source;
  final DateTime createdAt;

  /// The kind (feedback) or reason (report), as people read it.
  final String label;
  final String message;
  final InboxStatus status;
  final String? replyTo;
  final String? appVersion;
  final String? platform;

  /// Kyno reports only: the reporter's note and the question asked.
  final String? note;
  final String? prompt;

  InboxItem withStatus(InboxStatus s) => InboxItem(
        id: id,
        source: source,
        createdAt: createdAt,
        label: label,
        message: message,
        status: s,
        replyTo: replyTo,
        appVersion: appVersion,
        platform: platform,
        note: note,
        prompt: prompt,
      );

  /// A `feedback` row. Pure, for tests.
  static InboxItem fromFeedbackRow(Map<String, dynamic> row) => InboxItem(
        id: '${row['id']}',
        source: InboxSource.feedback,
        createdAt: _time(row['created_at']),
        label: FeedbackKind.fromCode(row['kind'] as String?)?.label ?? 'Other',
        message: (row['message'] as String?) ?? '',
        status: InboxStatus.fromCode(row['status'] as String?),
        replyTo: _blankToNull(row['reply_to']),
        appVersion: _blankToNull(row['app_version']),
        platform: _blankToNull(row['platform']),
      );

  /// A `kyno_reports` row. Pure, for tests.
  static InboxItem fromReportRow(Map<String, dynamic> row) {
    final code = row['reason'] as String?;
    var label = 'Other';
    for (final r in KynoReportReason.values) {
      if (r.code == code) label = r.label;
    }
    return InboxItem(
      id: '${row['id']}',
      source: InboxSource.report,
      createdAt: _time(row['created_at']),
      label: label,
      message: (row['message'] as String?) ?? '',
      status: InboxStatus.fromCode(row['status'] as String?),
      note: _blankToNull(row['note']),
      prompt: _blankToNull(row['prompt']),
    );
  }

  static DateTime _time(Object? v) =>
      (v is String ? DateTime.tryParse(v)?.toLocal() : null) ?? DateTime.fromMillisecondsSinceEpoch(0);

  static String? _blankToNull(Object? v) {
    final s = v is String ? v.trim() : '';
    return s.isEmpty ? null : s;
  }
}

class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  static const maxMessageLength    = 2000;
  static const maxReplyToLength    = 320;
  static const maxAppVersionLength = 40;
  static const maxPlatformLength   = 60;

  /// Newest rows the inbox loads per table.
  static const inboxLimit = 200;

  static const _timeout = Duration(seconds: 12);

  /// Unread items across both tables, for the badge on the Settings row.
  /// Only ever set for curators.
  final ValueNotifier<int> newCount = ValueNotifier(0);

  /// The row to insert. Pure, so it can be tested without a client. Never
  /// carries user_id; the server fills it in. Throws [ArgumentError] when
  /// there is nothing to send.
  @visibleForTesting
  static Map<String, Object?> buildRow({
    required FeedbackKind kind,
    required String message,
    String? replyTo,
    String? appVersion,
    String? platform,
  }) {
    final text = message.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(message, 'message', 'nothing to send');
    }
    String? opt(String? s, int max) {
      final t = s?.trim() ?? '';
      return t.isEmpty ? null : _clip(t, max);
    }

    return {
      'kind':        kind.code,
      'message':     _clip(text, maxMessageLength),
      'reply_to':    opt(replyTo, maxReplyToLength),
      'app_version': opt(appVersion, maxAppVersionLength),
      'platform':    opt(platform, maxPlatformLength),
    };
  }

  /// Cut to at most [max] UTF-16 units without splitting a surrogate pair.
  static String _clip(String s, int max) {
    if (s.length <= max) return s;
    var end = max;
    final unit = s.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--; // lone high surrogate
    return s.substring(0, end);
  }

  /// "android 16", "ios 18.1": the OS name and its version, whitespace
  /// collapsed. Pure, for tests.
  @visibleForTesting
  static String platformLabel(String os, String version) {
    final v = version.replaceAll(RegExp(r'\s+'), ' ').trim();
    return v.isEmpty ? os : '$os $v';
  }

  /// A mail link to [email] with the reply subject filled in. Spaces are
  /// encoded as %20 (not +), which every mail app reads right.
  static Uri mailtoFor(String email) => Uri(
        scheme: 'mailto',
        path: email.trim(),
        query: 'subject=${Uri.encodeComponent('About your Kynetix feedback')}',
      );

  /// "just now", "5m ago", "3h ago", "2d ago", then the date. Pure.
  static String relativeTime(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final sameYear = t.year == (now ?? DateTime.now()).year;
    return sameYear ? '${t.day} ${months[t.month - 1]}' : '${t.day} ${months[t.month - 1]} ${t.year}';
  }

  /// The signed-in user's email, if the account has one.
  String? get accountEmail {
    try {
      final e = Supabase.instance.client.auth.currentUser?.email?.trim();
      return (e == null || e.isEmpty) ? null : e;
    } catch (_) {
      return null;
    }
  }

  static Future<String?>? _versionLookup;

  static Future<String?> _lookUpVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final name = info.version.trim();
      final build = info.buildNumber.trim();
      if (name.isEmpty) return null;
      return build.isEmpty ? name : '$name+$build';
    } catch (_) {
      return null;
    }
  }

  static String? _platform() {
    if (kIsWeb) return 'web';
    try {
      return platformLabel(Platform.operatingSystem, Platform.operatingSystemVersion);
    } catch (_) {
      return defaultTargetPlatform.name;
    }
  }

  /// Sends the feedback. Throws on no session, no connection or a server
  /// error; the sheet stays open and says so calmly.
  Future<void> submit({
    required FeedbackKind kind,
    required String message,
    String? replyTo,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      throw StateError('not authenticated');
    }
    final row = buildRow(
      kind: kind,
      message: message,
      replyTo: replyTo,
      appVersion: await (_versionLookup ??= _lookUpVersion()),
      platform: _platform(),
    );
    await client.from('feedback').insert(row).timeout(_timeout);
  }

  // ── Curator inbox ──────────────────────────────────────────────────────────

  String? _curatorFor;
  Future<bool>? _curator;

  /// True when the signed-in user is a curator. Asked once per user; a
  /// failed lookup is not cached, so the next call tries again.
  Future<bool> isCurator() {
    String? uid;
    try {
      uid = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}
    if (uid == null) return Future.value(false);
    if (_curatorFor != uid || _curator == null) {
      _curatorFor = uid;
      _curator = _lookUpCurator(uid);
    }
    return _curator!;
  }

  Future<bool> _lookUpCurator(String uid) async {
    try {
      final rows = await Supabase.instance.client
          .from('app_curators')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1)
          .timeout(_timeout);
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('[FEEDBACK] curator lookup failed: $e');
      if (_curatorFor == uid) _curator = null;
      return false;
    }
  }

  Future<List<InboxItem>> fetchFeedback() async {
    final rows = await Supabase.instance.client
        .from('feedback')
        .select('id, created_at, kind, message, reply_to, app_version, platform, status')
        .order('created_at', ascending: false)
        .limit(inboxLimit)
        .timeout(_timeout);
    return [for (final r in rows) InboxItem.fromFeedbackRow(r)];
  }

  Future<List<InboxItem>> fetchReports() async {
    final rows = await Supabase.instance.client
        .from('kyno_reports')
        .select('id, created_at, reason, note, message, prompt, status')
        .order('created_at', ascending: false)
        .limit(inboxLimit)
        .timeout(_timeout);
    return [for (final r in rows) InboxItem.fromReportRow(r)];
  }

  /// Both inbox lists, newest first. Also refreshes [newCount].
  Future<({List<InboxItem> feedback, List<InboxItem> reports})> fetchInbox() async {
    final results = await Future.wait([fetchFeedback(), fetchReports()]);
    final inbox = (feedback: results[0], reports: results[1]);
    newCount.value = [...inbox.feedback, ...inbox.reports].where((i) => i.status == InboxStatus.fresh).length;
    return inbox;
  }

  /// Counts unread items for the badge without loading them. Quiet on
  /// failure: the badge just keeps its last value.
  Future<void> refreshNewCount() async {
    if (!await isCurator()) return;
    try {
      final client = Supabase.instance.client;
      final counts = await Future.wait([
        for (final table in const ['feedback', 'kyno_reports'])
          client.from(table).select('id').eq('status', InboxStatus.fresh.code).count(CountOption.exact).timeout(_timeout),
      ]);
      newCount.value = counts.fold<int>(0, (s, r) => s + r.count);
    } catch (e) {
      debugPrint('[FEEDBACK] new count failed: $e');
    }
  }

  /// Moves one item to [status]. Throws on failure; the caller puts the old
  /// status back.
  Future<void> setStatus(InboxItem item, InboxStatus status) async {
    final table = item.source == InboxSource.feedback ? 'feedback' : 'kyno_reports';
    await Supabase.instance.client
        .from(table)
        .update({'status': status.code})
        .eq('id', item.id)
        .timeout(_timeout);
    if (item.status != status) {
      if (item.status == InboxStatus.fresh) newCount.value = (newCount.value - 1).clamp(0, 1 << 30);
      if (status == InboxStatus.fresh) newCount.value += 1;
    }
  }
}
