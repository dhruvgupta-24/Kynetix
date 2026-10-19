import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../services/feedback_service.dart';
import '../ui/k_segmented.dart';
import '../ui/k_toast.dart';

/// The owner inbox: everything people sent through "Talk to us", and every
/// Kyno reply someone reported. Curators only; the tables' RLS returns
/// nothing to anyone else, so this screen is never a way in.
class FeedbackInboxScreen extends StatefulWidget {
  const FeedbackInboxScreen({super.key});

  @override
  State<FeedbackInboxScreen> createState() => _FeedbackInboxScreenState();
}

class _FeedbackInboxScreenState extends State<FeedbackInboxScreen> {
  InboxSource _tab = InboxSource.feedback;
  List<InboxItem>? _feedback;
  List<InboxItem>? _reports;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final inbox = await FeedbackService.instance.fetchInbox();
      if (!mounted) return;
      setState(() {
        _feedback = inbox.feedback;
        _reports = inbox.reports;
        _failed = false;
      });
    } catch (e) {
      debugPrint('[FEEDBACK_INBOX] load failed: $e');
      // A failed refresh keeps whatever was already on screen.
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _setStatus(InboxItem item, InboxStatus status) async {
    if (item.status == status) return;
    KHaptics.select();
    final toaster = KToaster.of(context);
    _replace(item.withStatus(status));
    try {
      await FeedbackService.instance.setStatus(item, status);
    } catch (e) {
      debugPrint('[FEEDBACK_INBOX] status failed: $e');
      if (!mounted) return;
      _replace(item);
      toaster.show("Couldn't save that. Try again.", kind: KToastKind.error);
    }
  }

  void _replace(InboxItem item) {
    List<InboxItem>? swap(List<InboxItem>? list) =>
        list == null ? null : [for (final i in list) i.id == item.id && i.source == item.source ? item : i];
    setState(() {
      if (item.source == InboxSource.feedback) {
        _feedback = swap(_feedback);
      } else {
        _reports = swap(_reports);
      }
    });
  }

  Future<void> _reply(String email) async {
    final toaster = KToaster.of(context);
    var opened = false;
    try {
      opened = await launchUrl(FeedbackService.mailtoFor(email));
    } catch (_) {}
    if (!opened) toaster.show('No mail app to open. The address is $email.');
  }

  int _fresh(List<InboxItem>? list) => list?.where((i) => i.status == InboxStatus.fresh).length ?? 0;

  @override
  Widget build(BuildContext context) {
    final items = _tab == InboxSource.feedback ? _feedback : _reports;
    final bottom = MediaQuery.paddingOf(context).bottom;
    String tabLabel(String name, List<InboxItem>? list) {
      final n = _fresh(list);
      return n > 0 ? '$name ($n)' : name;
    }

    final Widget body;
    if (items == null && !_failed) {
      body = const Center(child: KSpinner(size: 22));
    } else if (items == null) {
      body = _Message(
        title: "Couldn't load the inbox.",
        line: 'Check your connection, then pull to try again.',
        onRefresh: _load,
      );
    } else if (items.isEmpty) {
      body = _Message(
        title: 'Inbox zero. Suspiciously quiet.',
        line: _tab == InboxSource.feedback ? 'New feedback lands here.' : 'Reported Kyno replies land here.',
        onRefresh: _load,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        color: KColor.ink,
        backgroundColor: KColor.surface,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, KSpacing.xxxl + bottom),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: KSpacing.md),
          itemBuilder: (context, i) {
            final item = items[i];
            return _InboxCard(
              key: ValueKey('${item.source.name}-${item.id}'),
              item: item,
              onStatus: (s) => _setStatus(item, s),
              onReply: item.replyTo == null ? null : () => _reply(item.replyTo!),
            );
          },
        ),
      );
    }

    return KPage(
      tone: KTone.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Feedback inbox', style: KText.h2),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, 0),
            child: KSegmented<InboxSource>(
              dense: true,
              segments: [
                KSegment(InboxSource.feedback, tabLabel('Feedback', _feedback)),
                KSegment(InboxSource.report, tabLabel('Kyno reports', _reports)),
              ],
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          if (_failed && items != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, 0),
              child: Text(
                "Couldn't refresh. Showing what we had.",
                style: KText.caption.copyWith(color: KColor.textMuted),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Empty and error states: one line in voice, one line of help, and still
/// pullable so a refresh is always one gesture away.
class _Message extends StatelessWidget {
  const _Message({required this.title, required this.line, required this.onRefresh});
  final String title;
  final String line;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        color: KColor.ink,
        backgroundColor: KColor.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(KSpacing.p, 96, KSpacing.p, KSpacing.xxxl),
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: KColor.textMuted),
            const SizedBox(height: KSpacing.md),
            Text(title, textAlign: TextAlign.center, style: KText.h3),
            const SizedBox(height: KSpacing.xs),
            Text(line, textAlign: TextAlign.center, style: KText.caption.copyWith(color: KColor.textMuted)),
          ],
        ),
      );
}

/// One item. New ones sit on an ember-tinted card with a "New" pill and
/// heavier text; done ones step back. The status control is the same three-way segment on every card.
class _InboxCard extends StatelessWidget {
  const _InboxCard({super.key, required this.item, required this.onStatus, this.onReply});
  final InboxItem item;
  final ValueChanged<InboxStatus> onStatus;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final fresh = item.status == InboxStatus.fresh;
    final done = item.status == InboxStatus.done;
    final meta = [?item.appVersion, ?item.platform].join('  ·  ');
    final muted = KText.caption.copyWith(fontSize: 12, color: KColor.textMuted);

    final card = KCard(
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.lg, KSpacing.md),
      color: fresh ? KColor.tint(KColor.ember) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Chip(item.label),
              if (fresh) ...[
                const SizedBox(width: KSpacing.sm),
                _Chip('New', ink: true),
              ],
              const Spacer(),
              Text(FeedbackService.relativeTime(item.createdAt), style: muted),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          if (item.prompt != null) ...[
            Text('Asked', style: muted),
            const SizedBox(height: 2),
            SelectableText(item.prompt!, style: KText.body.copyWith(fontSize: 14, color: KColor.textSecondary)),
            const SizedBox(height: KSpacing.sm),
            Text('Kyno said', style: muted),
            const SizedBox(height: 2),
          ],
          SelectableText(
            item.message,
            style: KText.body.copyWith(fontSize: 15, height: 1.4, fontWeight: fresh ? FontWeight.w600 : FontWeight.w400),
          ),
          if (item.note != null) ...[
            const SizedBox(height: KSpacing.sm),
            Text('Note', style: muted),
            const SizedBox(height: 2),
            SelectableText(item.note!, style: KText.body.copyWith(fontSize: 14)),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: KSpacing.sm),
            Text(meta, style: muted),
          ],
          if (onReply != null) ...[
            const SizedBox(height: KSpacing.sm),
            Pressable(
              onTap: onReply,
              scale: 0.98,
              borderRadius: KRadius.sm,
              semanticLabel: 'Reply to ${item.replyTo}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.mail_outline_rounded, size: 16, color: KColor.textSecondary),
                    const SizedBox(width: KSpacing.sm),
                    Flexible(
                      child: Text(
                        item.replyTo!,
                        style: KText.bodyMedium.copyWith(fontSize: 14, decoration: TextDecoration.underline, decorationColor: KColor.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: KSpacing.md),
          KSegmented<InboxStatus>(
            dense: true,
            height: 40,
            segments: [for (final s in InboxStatus.values) KSegment(s, s.label, semanticLabel: 'Mark ${s.label.toLowerCase()}')],
            value: item.status,
            onChanged: onStatus,
          ),
        ],
      ),
    );
    return AnimatedOpacity(
      opacity: done ? 0.6 : 1,
      duration: KMotion.of(context, KMotion.quick),
      child: card,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.ink = false});
  final String text;
  final bool ink;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ink ? KColor.ink : KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.06),
          borderRadius: KRadius.pill,
        ),
        child: Text(
          text,
          style: KText.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: ink ? KColor.onInk : KColor.textPrimary),
        ),
      );
}
