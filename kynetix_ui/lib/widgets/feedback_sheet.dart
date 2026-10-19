import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/feedback_service.dart';
import '../ui/k_segmented.dart';
import '../ui/k_toast.dart';
import '../services/analytics_service.dart';

// ─── Feedback sheet ───────────────────────────────────────────────────────────
// "Talk to us": pick a kind, say it, send. On success the sheet closes with a
// toast and a success haptic. On failure it stays open, keeps the text, and
// says what happened under the field.

/// Opens the feedback sheet over [context].
Future<void> showFeedbackSheet(BuildContext context) {
  KHaptics.select();
  return showKSheet<void>(
    context: context,
    builder: (_) => FeedbackSheet(email: FeedbackService.instance.accountEmail),
  );
}

class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, this.email, this.send});

  /// The account's email, offered as the reply address. No email, no offer.
  final String? email;

  /// Sends the feedback. Defaults to [FeedbackService.submit]; tests swap it.
  final Future<void> Function({required FeedbackKind kind, required String message, String? replyTo})? send;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _text = TextEditingController();
  FeedbackKind _kind = FeedbackKind.idea;
  bool _replyOk = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (_text.text.trim().isEmpty) {
      KHaptics.reject();
      setState(() => _error = 'Say something first. Even one line.');
      return;
    }
    final toaster = KToaster.of(context);
    final navigator = Navigator.of(context);
    final send = widget.send ?? FeedbackService.instance.submit;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await send(
        kind: _kind,
        message: _text.text,
        replyTo: _replyOk ? widget.email : null,
      );
      AnalyticsService.instance.track('feedback_sent', {'kind': _kind.code});
      KHaptics.success();
      if (navigator.mounted) navigator.pop();
      toaster.show('Got it. Straight to the team.', kind: KToastKind.success);
    } catch (e) {
      debugPrint('[FEEDBACK] send failed: $e');
      if (!mounted) return;
      final signedOut = e.toString().contains('not authenticated');
      setState(() {
        _sending = false;
        _error = signedOut
            ? 'Sign in again, then send it.'
            : "Didn't go through. Check your connection and try again.";
      });
    }
  }

  OutlineInputBorder _border(Color c) =>
      OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: c));

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final email = widget.email;
    final edge = KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetHeader(
                'Say it straight',
                subtitle: 'Ideas, bugs, love letters. We read every one.',
              ),
              const SizedBox(height: KSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: KSegmented<FeedbackKind>(
                  dense: true,
                  segments: [for (final k in FeedbackKind.values) KSegment(k, k.label)],
                  value: _kind,
                  onChanged: (k) {
                    if (_sending) return;
                    setState(() => _kind = k);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
                child: TextField(
                  controller: _text,
                  enabled: !_sending,
                  maxLength: FeedbackService.maxMessageLength,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: KText.body.copyWith(fontSize: 15, height: 1.4),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    hintText: _kind.hint,
                    hintStyle: KText.body.copyWith(color: KColor.textMuted),
                    filled: true,
                    fillColor: KColor.card,
                    contentPadding: const EdgeInsets.all(KSpacing.md),
                    border: _border(edge),
                    enabledBorder: _border(edge),
                    focusedBorder: _border(KColor.textSecondary),
                    disabledBorder: _border(edge),
                  ),
                ),
              ),
              if (email != null)
                MergeSemantics(
                  child: InkWell(
                    onTap: _sending
                        ? null
                        : () {
                            KHaptics.select();
                            setState(() => _replyOk = !_replyOk);
                          },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.md, KSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'You can reply to me at ',
                                children: [
                                  TextSpan(text: email, style: TextStyle(color: KColor.textPrimary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                            ),
                          ),
                          const SizedBox(width: KSpacing.sm),
                          Switch(
                            value: _replyOk,
                            activeThumbColor: KColor.onInk,
                            activeTrackColor: KColor.ink,
                            inactiveThumbColor: KColor.textMuted,
                            inactiveTrackColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.07),
                            trackOutlineColor: WidgetStatePropertyAll(KColor.fg.withValues(alpha: KColor.isDark ? 0.09 : 0.1)),
                            onChanged: _sending
                                ? null
                                : (v) {
                                    KHaptics.select();
                                    setState(() => _replyOk = v);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedSize(
                duration: KMotion.of(context, KMotion.quick),
                alignment: Alignment.topCenter,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, 0),
                        child: Semantics(
                          liveRegion: true,
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: KColor.danger),
                              const SizedBox(width: KSpacing.sm),
                              Expanded(
                                child: Text(_error!, style: KText.caption.copyWith(fontSize: 13, color: KColor.danger)),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: KSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: KButton(
                  label: 'Send',
                  icon: Icons.arrow_upward_rounded,
                  loading: _sending,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
