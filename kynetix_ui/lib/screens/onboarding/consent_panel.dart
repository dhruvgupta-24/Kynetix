import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../privacy_policy_screen.dart';

/// The privacy notice and consent controls, shared by onboarding's first step
/// (new users) and [ConsentScreen] (existing users who haven't agreed yet).
///
/// Two required controls: "I agree to the Privacy Policy" and "I'm 18 or
/// older". The primary action stays disabled until both are on. "I don't
/// agree" switches to a plain explanation with Read policy and Sign out;
/// nothing is recorded in that case.
class ConsentPanel extends StatefulWidget {
  const ConsentPanel({
    super.key,
    required this.onAgree,
    required this.onSignOut,
    this.agreeLabel = 'Agree and continue',
    this.padding = const EdgeInsets.symmetric(horizontal: KSpacing.xxl),
  });

  /// Records consent. The panel shows a loader until it completes; if it
  /// throws, the panel shows a calm error and stays put.
  final Future<void> Function({required bool ageConfirmedAdult}) onAgree;

  final Future<void> Function() onSignOut;
  final String agreeLabel;
  final EdgeInsetsGeometry padding;

  @override
  State<ConsentPanel> createState() => _ConsentPanelState();
}

class _ConsentPanelState extends State<ConsentPanel> {
  bool _agreed = false;
  bool _adult = false;
  bool _saving = false;
  bool _declined = false;
  bool _signingOut = false;
  String? _error;

  bool get _ready => _agreed && _adult && !_saving;

  void _openPolicy() {
    Navigator.of(context).push(
      kRiseRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  Future<void> _agree() async {
    if (!_ready) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onAgree(ageConfirmedAdult: _adult);
      KHaptics.success();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "That didn't save. Try again in a moment.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't sign out. Try again in a moment.");
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _declined ? _buildDeclined() : _buildNotice();
    return AnimatedSwitcher(
      duration: KMotion.of(context, KMotion.standard),
      switchInCurve: KMotion.decelerate,
      switchOutCurve: KMotion.accelerate,
      child: KeyedSubtree(
        key: ValueKey(_declined),
        child: child,
      ),
    );
  }

  Widget _buildNotice() {
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The terms, set like a short printed notice: numbered clauses
          // between rules, no card and no decorative icons.
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: KColor.textPrimary, width: 1.5),
                bottom: BorderSide(color: _rule()),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _NoticeLine(
                  number: 1,
                  text: 'Your profile, meals and workouts are stored on this '
                      'phone and on our servers so they sync.',
                ),
                _NoticeLine(
                  number: 2,
                  text: 'If you allow it, we read steps, weight, sleep and '
                      'HRV from Health Connect or Apple Health. We never '
                      'write to them.',
                ),
                _NoticeLine(
                  number: 3,
                  text: 'When you use AI features, the details needed to '
                      'answer go to our AI providers, some outside India.',
                ),
                _NoticeLine(
                  number: 4,
                  text: "We don't sell your data or use it for ads.",
                ),
                _NoticeLine(
                  number: 5,
                  text: 'You can delete your account and data any time in '
                      'Settings.',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: KSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _LinkButton(
              label: 'Read the privacy policy',
              icon: Icons.open_in_new_rounded,
              onTap: _openPolicy,
            ),
          ),
          const SizedBox(height: KSpacing.sm),
          _ConsentCheck(
            key: const ValueKey('consent-agree-policy'),
            value: _agreed,
            label: 'I agree to the Privacy Policy',
            onChanged: _saving ? null : (v) => setState(() => _agreed = v),
          ),
          _ConsentCheck(
            key: const ValueKey('consent-age-18'),
            value: _adult,
            label: "I'm 18 or older",
            onChanged: _saving ? null : (v) => setState(() => _adult = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: KSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: KText.caption.copyWith(color: KColor.danger, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: KSpacing.lg),
          KButton(
            label: widget.agreeLabel,
            width: double.infinity,
            loading: _saving,
            onTap: _ready ? _agree : null,
          ),
          const SizedBox(height: KSpacing.xs),
          Center(
            child: _LinkButton(
              label: "I don't agree",
              onTap: _saving ? null : () => setState(() => _declined = true),
            ),
          ),
          const SizedBox(height: KSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildDeclined() {
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(top: KSpacing.lg),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: KColor.textPrimary, width: 1.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text("You can't use Kynetix without this", style: KText.h2),
                ),
                const SizedBox(height: KSpacing.sm),
                Text(
                  'Kynetix needs your agreement to the Privacy Policy to store '
                  'and sync your data, and Kynetix is for adults 18 and over. '
                  "Nothing was saved. You can read the policy, change your "
                  'mind, or sign out.',
                  style: KText.body.copyWith(color: KColor.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: KSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: KText.caption.copyWith(color: KColor.danger, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: KSpacing.xl),
          KButton(
            label: 'Review again',
            width: double.infinity,
            onTap: () => setState(() {
              _declined = false;
              _error = null;
            }),
          ),
          const SizedBox(height: KSpacing.md),
          KButton(
            label: 'Read the privacy policy',
            icon: Icons.privacy_tip_outlined,
            outlined: true,
            width: double.infinity,
            onTap: _openPolicy,
          ),
          const SizedBox(height: KSpacing.md),
          KButton(
            label: 'Sign out',
            icon: Icons.logout_rounded,
            outlined: true,
            width: double.infinity,
            loading: _signingOut,
            onTap: _signOut,
          ),
          const SizedBox(height: KSpacing.xl),
        ],
      ),
    );
  }
}

Color _rule() => KColor.fg.withValues(alpha: KColor.isDark ? 0.1 : 0.1);

/// One numbered clause of the notice, with a hairline under it.
class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.number, required this.text, this.last = false});
  final int number;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: _rule())),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 28,
              child: Text(
                '$number',
                style: KText.numSmall.copyWith(
                  fontSize: 14,
                  height: 1.45,
                  color: KColor.textMuted,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: KText.body.copyWith(
                color: KColor.textPrimary,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width, 48dp+ checkbox row. The whole row toggles.
class _ConsentCheck extends StatelessWidget {
  const _ConsentCheck({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return MergeSemantics(
      child: InkWell(
        borderRadius: KRadius.sm,
        onTap: enabled
            ? () {
                KHaptics.select();
                onChanged!(!value);
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: enabled
                    ? (v) {
                        KHaptics.select();
                        onChanged!(v ?? false);
                      }
                    : null,
                activeColor: KColor.ink,
                checkColor: KColor.onInk,
                side: BorderSide(color: KColor.textSecondary, width: 1.5),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              const SizedBox(width: KSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: KText.bodyMedium.copyWith(
                    color: KColor.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: KColor.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.md),
        shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: KText.bodyMedium.copyWith(
                color: KColor.textPrimary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: KColor.textMuted,
              ),
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: KSpacing.xs),
            ExcludeSemantics(child: Icon(icon, size: 16, color: KColor.textSecondary)),
          ],
        ],
      ),
    );
  }
}
