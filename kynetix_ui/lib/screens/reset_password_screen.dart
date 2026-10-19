import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import 'onboarding/password_toggle.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'Fill in both fields to continue.');
      return;
    }

    if (password != confirm) {
      setState(() => _errorMessage = "Those passwords don't match. Try again.");
      return;
    }

    if (password.length < 8) {
      setState(() => _errorMessage = 'Use at least 8 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      
      if (mounted) {
        setState(() {
          _isSuccess = true;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendly(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Couldn't reach the server. Check your connection and try again.";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Calm, actionable copy for update failures (docs/VOICE.md).
  static String _friendly(AuthException e) {
    final m = '${e.code ?? ''} ${e.message}'.toLowerCase();
    if (m.contains('same_password') || m.contains('different from the old')) {
      return "That's your current password. Pick a new one.";
    }
    if (m.contains('weak_password') || m.contains('should be')) {
      return 'That password is too short. Use at least 8 characters.';
    }
    if (m.contains('session') || m.contains('expired') || m.contains('jwt')) {
      return 'This reset link has expired. Request a new one from the sign-in screen.';
    }
    return "That didn't go through. Try again in a moment.";
  }

  @override
  Widget build(BuildContext context) {
    return KPage(
      tone: KTone.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _isSuccess
          ? null
          : IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.sm, KSpacing.xl, KSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              // Moment: success. The form gives way to the confirmation with
              // a soft fade-scale; reduced motion swaps instantly.
              child: AnimatedSwitcher(
                duration: KMotion.of(context, KMotion.emphasized),
                switchInCurve: KMotion.decelerate,
                switchOutCurve: KMotion.accelerate,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1).animate(anim),
                    child: child,
                  ),
                ),
                child: _isSuccess
                    ? KeyedSubtree(key: const ValueKey('reset-success'), child: _buildSuccess())
                    : KeyedSubtree(key: const ValueKey('reset-form'), child: _buildForm()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: KColor.green.withValues(alpha: KColor.isDark ? 0.12 : 0.09),
              shape: BoxShape.circle,
              border: Border.all(color: KColor.green.withValues(alpha: KColor.isDark ? 0.4 : 0.32)),
            ),
            child: Icon(Icons.check_rounded, color: KColor.green, size: 38),
          ),
        ),
        const SizedBox(height: KSpacing.xxl),
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(
            'Password updated.',
            textAlign: TextAlign.center,
            style: KText.display,
          ),
        ),
        const SizedBox(height: KSpacing.md),
        Text(
          "You're good to go. Use it next time you sign in.",
          textAlign: TextAlign.center,
          style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: KSpacing.xxxl + KSpacing.lg),
        KButton(
          label: 'Continue',
          width: double.infinity,
          onTap: () {
            // Pop back to root (AuthGate)
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: kStagger([
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('New password', style: KText.display.copyWith(fontSize: 34)),
            ),
            const SizedBox(height: KSpacing.sm),
            Text(
              "At least 8 characters. You'll sign in with it from now on.",
              style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: KSpacing.xxxl),
        // The form sits on the page, as on sign-in: no card.
        Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ErrorNotice(message: _errorMessage),
              _PasswordField(
                key: const ValueKey('reset_new_password_field'),
                controller: _passwordCtrl,
                hint: 'New password',
                icon: Icons.lock_outline,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: KSpacing.md),
              _PasswordField(
                key: const ValueKey('reset_confirm_password_field'),
                controller: _confirmCtrl,
                hint: 'Confirm new password',
                icon: Icons.lock_reset_rounded,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isLoading) _updatePassword();
                },
              ),
              const SizedBox(height: KSpacing.xl),
              KButton(
                label: 'Update password',
                width: double.infinity,
                loading: _isLoading,
                onTap: _updatePassword,
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Error notice ─────────────────────────────────────────────────────────────

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    final msg = message;
    return AnimatedSize(
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: msg == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: KSpacing.lg),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(KSpacing.md),
                  decoration: BoxDecoration(
                    color: KColor.danger.withValues(alpha: KColor.isDark ? 0.10 : 0.07),
                    borderRadius: KRadius.sm,
                    border: Border.all(color: KColor.danger.withValues(alpha: KColor.isDark ? 0.35 : 0.30)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 18, color: KColor.danger, semanticLabel: 'Error'),
                      const SizedBox(width: KSpacing.sm),
                      Expanded(
                        child: Text(msg, style: KText.caption.copyWith(fontSize: 13, color: KColor.danger)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ─── Password field with focus glow ───────────────────────────────────────────

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  final _focus = FocusNode();
  bool _focused = false;

  /// Hidden by default; the eye toggle flips it.
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted && _focus.hasFocus != _focused) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: KRadius.md,
          borderSide: BorderSide(color: c, width: w),
        );
    final rest = dark ? KColor.fg.withValues(alpha: 0.10) : KColor.border;
    final ring = KColor.fg.withValues(alpha: dark ? 0.10 : 0.07);
    return AnimatedContainer(
      duration: KMotion.of(context, KMotion.quick),
      curve: KMotion.emphasizedCurve,
      decoration: BoxDecoration(
        borderRadius: KRadius.md,
        boxShadow: [
          BoxShadow(
            color: _focused ? ring : ring.withValues(alpha: 0),
            blurRadius: 0,
            spreadRadius: 4,
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: _obscured,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: _obscured ? null : TextInputType.visiblePassword,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        style: KText.bodyMedium.copyWith(fontSize: 15),
        cursorColor: KColor.ink,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: KText.body.copyWith(color: KColor.textMuted, fontSize: 15),
          prefixIcon: Icon(widget.icon, color: KColor.textMuted, size: 20),
          suffixIcon: Padding(
            padding: const EdgeInsetsDirectional.only(end: KSpacing.xs),
            child: PasswordVisibilityToggle(
              obscured: _obscured,
              onToggle: () => setState(() => _obscured = !_obscured),
            ),
          ),
          filled: true,
          fillColor: dark ? KColor.fg.withValues(alpha: 0.04) : KColor.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.xl, vertical: 17),
          border: border(rest),
          enabledBorder: border(rest),
          focusedBorder: border(KColor.ink, 1.5),
        ),
      ),
    );
  }
}
