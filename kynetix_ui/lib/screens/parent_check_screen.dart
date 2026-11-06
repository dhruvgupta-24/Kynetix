import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/guardian_service.dart';
import '../ui/k_toast.dart';
import 'account_deletion_screen.dart';
import 'onboarding_screen.dart' show OnboardingTextField;

/// Teen mode's one extra step: a parent or guardian says yes.
///
/// The teen shares a link (WhatsApp or anything else); the parent opens it in
/// a browser, reads what Kynetix keeps and taps yes. This screen checks every
/// few seconds and moves on by itself the moment they do. Nothing else about
/// the teen is processed until then.
class ParentCheckPanel extends StatefulWidget {
  const ParentCheckPanel({
    super.key,
    required this.userId,
    required this.dateOfBirth,
    required this.onApproved,
    this.initialFirstName = '',
    this.onSignOut,
    this.padding = const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
    this.service,
    this.pollEvery = const Duration(seconds: 6),
    this.share,
  });

  final String userId;
  final DateTime dateOfBirth;
  final VoidCallback onApproved;
  final String initialFirstName;
  final Future<void> Function()? onSignOut;
  final EdgeInsetsGeometry padding;
  final GuardianService? service;
  final Duration pollEvery;

  /// Test hook for the share sheet.
  final Future<void> Function(String text)? share;

  @override
  State<ParentCheckPanel> createState() => _ParentCheckPanelState();
}

class _ParentCheckPanelState extends State<ParentCheckPanel> {
  GuardianService get _svc => widget.service ?? GuardianService.instance;

  late final _nameCtrl = TextEditingController(text: widget.initialFirstName.trim().split(' ').first);
  GuardianStatus? _status;
  String? _link;
  bool _busy = false;
  bool _checking = true;
  String? _error;
  Timer? _poll;
  AppLifecycleListener? _life;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _status = _svc.peek(widget.userId);
    _life = AppLifecycleListener(onResume: _check);
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _life?.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_status == GuardianStatus.pending && !_done) {
      _poll = Timer(widget.pollEvery, _check);
    }
  }

  Future<void> _check() async {
    final s = await _svc.refresh(widget.userId);
    if (!mounted || _done) return;
    setState(() {
      _checking = false;
      if (s != null) _status = s;
    });
    if (s == GuardianStatus.approved) {
      _done = true;
      KHaptics.success();
      widget.onApproved();
      return;
    }
    _schedulePoll();
  }

  String _shareText(String link) =>
      "Hey! I want to use Kynetix, a gym and food tracker. I'm under 18, "
      "so it needs a parent's OK first. Takes a minute: $link";

  Future<void> _share(String link) async {
    final custom = widget.share;
    if (custom != null) return custom(_shareText(link));
    await SharePlus.instance.share(ShareParams(text: _shareText(link), subject: 'Kynetix: a quick OK for me'));
  }

  Future<void> _makeLink() async {
    if (_busy) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      KHaptics.reject();
      setState(() => _error = 'Add your first name so your parent knows it is you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _svc.requestLink(userId: widget.userId, dateOfBirth: widget.dateOfBirth, firstName: name);
      if (!mounted) return;
      setState(() {
        _status = res.status;
        _link = res.link;
      });
      if (res.status == GuardianStatus.approved) {
        _done = true;
        widget.onApproved();
        return;
      }
      if (res.link != null) await _share(res.link!);
      _schedulePoll();
    } on GuardianException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't make the link. Try again in a moment.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final link = _link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    KHaptics.select();
    if (mounted) showKToast(context, 'Link copied');
  }

  Future<void> _signOut() async {
    final f = widget.onSignOut ?? () => const AuthService().signOut();
    try {
      await f();
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't sign out. Try again in a moment.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _status == GuardianStatus.pending;
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!waiting) ...[
            const _Perk(
              icon: Icons.restaurant_rounded,
              title: 'Fuel, not starve',
              body: 'Food targets sized for a body that is still growing. No crash diets, '
                  'even if you pick fat loss. Training does that job.',
            ),
            const _Perk(
              icon: Icons.auto_awesome_outlined,
              title: 'Kyno sits this one out',
              body: 'Our AI unlocks on your 18th. Logging, workouts, PRs, streaks, '
                  'all of that is yours right now.',
            ),
            const _Perk(
              icon: Icons.visibility_off_outlined,
              title: 'Zero tracking',
              body: 'No ads, no analytics on you. Not now, not ever.',
              last: true,
            ),
            const SizedBox(height: KSpacing.lg),
            if (_statusNote() case final note?) ...[
              _Note(text: note, tone: _status == GuardianStatus.expired ? KColor.textSecondary : KColor.danger),
              const SizedBox(height: KSpacing.md),
            ],
            Text('Your first name', style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: KSpacing.sm),
            OnboardingTextField(
              controller: _nameCtrl,
              hint: 'So they know it is you',
              capitalization: TextCapitalization.words,
            ),
          ] else
            _WaitingCard(link: _link, checking: _checking),
          if (_error != null) ...[
            const SizedBox(height: KSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: KText.caption.copyWith(color: KColor.danger, fontSize: 13)),
            ),
          ],
          const SizedBox(height: KSpacing.lg),
          if (!waiting)
            KButton(
              key: const ValueKey('parent-send-link'),
              label: _status == GuardianStatus.none || _status == null ? 'Send the link to a parent' : 'Send a new link',
              icon: Icons.send_rounded,
              width: double.infinity,
              loading: _busy,
              onTap: _makeLink,
            )
          else ...[
            KButton(
              key: const ValueKey('parent-share-again'),
              label: _link != null ? 'Send it again' : 'Send a fresh link',
              icon: Icons.send_rounded,
              width: double.infinity,
              loading: _busy,
              onTap: _link != null ? () => _share(_link!) : _makeLink,
            ),
            if (_link != null) ...[
              const SizedBox(height: KSpacing.md),
              KButton(
                label: 'Copy the link',
                icon: Icons.link_rounded,
                outlined: true,
                width: double.infinity,
                onTap: _copy,
              ),
            ],
          ],
          const SizedBox(height: KSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (waiting) _TextLink(label: 'Check now', onTap: () {
                setState(() => _checking = true);
                _check();
              }),
              if (_status == GuardianStatus.revoked || _status == GuardianStatus.declined)
                _TextLink(
                  label: 'Delete my account',
                  onTap: () => Navigator.of(context).push(kRiseRoute(builder: (_) => const AccountDeletionScreen())),
                ),
              _TextLink(label: 'Sign out', onTap: _signOut),
            ],
          ),
          const SizedBox(height: KSpacing.xl),
        ],
      ),
    );
  }

  String? _statusNote() => switch (_status) {
        GuardianStatus.declined =>
          'Your parent said not yet. Totally their call. If they change their mind, send a new link.',
        GuardianStatus.revoked =>
          'Your parent switched Kynetix off for now. Your data stays put until you decide: '
              'send a new link, or delete everything.',
        GuardianStatus.expired => 'That link timed out (they last 7 days). Send a fresh one.',
        _ => null,
      };
}

/// Full-screen version for the app gate (existing teens, a revoked OK).
class ParentCheckScreen extends StatelessWidget {
  const ParentCheckScreen({
    super.key,
    required this.userId,
    required this.dateOfBirth,
    required this.onApproved,
    this.initialFirstName = '',
  });

  final String userId;
  final DateTime dateOfBirth;
  final VoidCallback onApproved;
  final String initialFirstName;

  @override
  Widget build(BuildContext context) {
    return KPage(
      tone: KTone.neutral,
      intensity: 0.5,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ParentCheckHeader(dateOfBirth: dateOfBirth),
                Expanded(
                  child: ParentCheckPanel(
                    userId: userId,
                    dateOfBirth: dateOfBirth,
                    onApproved: onApproved,
                    initialFirstName: initialFirstName,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "TEEN MODE / You're 15. One quick yes and you're in."
class ParentCheckHeader extends StatelessWidget {
  const ParentCheckHeader({super.key, required this.dateOfBirth, this.padding});
  final DateTime dateOfBirth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final age = UserProfile.ageOn(dateOfBirth, DateTime.now());
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(KSpacing.xxl, KSpacing.xxl, KSpacing.xxl, KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.md, vertical: KSpacing.xs),
            decoration: BoxDecoration(
              color: KColor.ember.withValues(alpha: 0.14),
              borderRadius: KRadius.pill,
            ),
            child: Text(
              'TEEN MODE',
              style: KText.label.copyWith(color: KColor.ember, fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
          ),
          const SizedBox(height: KSpacing.md),
          Semantics(
            header: true,
            child: Text("You're $age. One quick yes and you're in.", style: KText.display),
          ),
          const SizedBox(height: KSpacing.xs),
          Text(
            "Starting early is a flex. Same Kynetix, tuned for you, and the law asks a "
            'parent or guardian to OK it first. Send them a link, they tap yes, done.',
            style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.title, required this.body, this.last = false});
  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: KColor.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: KShade.sunken(KColor.card),
                borderRadius: KRadius.md,
                border: Border.all(color: KColor.hairline),
              ),
              child: Icon(icon, size: 20, color: KColor.ember),
            ),
          ),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: KColor.textPrimary)),
                const SizedBox(height: 2),
                Text(body, style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.link, required this.checking});
  final String? link;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KSpacing.xl),
      decoration: KShade.surface(KRadius.lg, border: Border.all(color: KColor.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: KColor.ember),
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text('Waiting on the yes', style: KText.h3),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          Text(
            link != null
                ? 'Link sent. Once they tap yes, this screen moves on by itself. '
                    'The link works for 7 days.'
                : 'A link is out with your parent. Lost it? Send a fresh one; '
                    'the old one stops working.',
            style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 14, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.tone});
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(KSpacing.md),
        decoration: BoxDecoration(
          gradient: KShade.sunken(KColor.card),
          borderRadius: KRadius.md,
          border: Border.all(color: tone.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: KText.body.copyWith(color: KColor.textPrimary, fontSize: 14, height: 1.45)),
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: KColor.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.md),
      ),
      child: Text(
        label,
        style: KText.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: KColor.textMuted,
        ),
      ),
    );
  }
}
