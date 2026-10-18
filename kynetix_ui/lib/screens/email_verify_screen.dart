import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../services/auth_service.dart';

/// Confirms a new email account before it can be used. Sign-up sends a
/// 6-digit code (and a link that does the same job) to the address; typing
/// the code here signs the account in, and AuthGate takes it from there.
class EmailVerifyScreen extends StatefulWidget {
  const EmailVerifyScreen({
    super.key,
    required this.email,
    this.sentNow = true,
    this.authService = const AuthService(),
  });

  final String email;

  /// False when the person arrived from sign-in with an unconfirmed address:
  /// no code has gone out in this visit, so the screen offers to send one.
  final bool sentNow;
  final AuthService authService;

  static const codeLength = 6;

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _verifying = false;
  bool _sending = false;
  String? _error;
  String? _info;
  int _cooldown = 0;
  Timer? _timer;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    if (widget.sentNow) _startCooldown();
    _ctrl.addListener(_onChanged);
    // Opening the link in the email signs the account in too.
    _authSub = widget.authService.authStateChanges.listen((s) {
      if (s.session != null && mounted) _done();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSub?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  void _onChanged() {
    setState(() => _error = null);
    if (_ctrl.text.length == EmailVerifyScreen.codeLength && !_verifying) _verify();
  }

  void _done() {
    KHaptics.commit();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _verify() async {
    final code = _ctrl.text.trim();
    if (code.length != EmailVerifyScreen.codeLength) {
      setState(() => _error = 'Enter all ${EmailVerifyScreen.codeLength} digits from the email.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final res = await widget.authService.verifyEmailCode(email: widget.email, code: code);
      if (!mounted) return;
      if (res.session != null) {
        _done();
      } else {
        setState(() => _error = "That code didn't work. Check it, or send a new one.");
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      KHaptics.reject();
      final m = '${e.code ?? ''} ${e.message}'.toLowerCase();
      setState(() => _error = m.contains('expired')
          ? 'That code has expired. Send a new one.'
          : "That code didn't work. Check it, or send a new one.");
    } catch (_) {
      if (!mounted) return;
      KHaptics.reject();
      setState(() => _error = "That didn't go through. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_sending || _cooldown > 0) return;
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.authService.resendSignupEmail(widget.email);
      if (!mounted) return;
      _ctrl.clear();
      setState(() => _info = 'New code sent. It replaces the old one.');
      _startCooldown();
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = '${e.code ?? ''} ${e.message}'.toLowerCase();
      setState(() => _error = (m.contains('rate') || m.contains('security purposes') || m.contains('too many'))
          ? 'Too many emails for now. Wait a few minutes, then send again.'
          : "Couldn't send a new code. Try again in a moment.");
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't send a new code. Check your connection.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _ctrl.text;
    return Scaffold(
      backgroundColor: KColor.bg,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.sm, KSpacing.xl, KSpacing.xxl),
          children: [
            Semantics(header: true, child: Text('Check your email', style: KText.display)),
            const SizedBox(height: KSpacing.md),
            Text.rich(
              TextSpan(
                style: KText.body.copyWith(fontSize: 15, color: KColor.textSecondary),
                children: [
                  TextSpan(
                    text: widget.sentNow
                        ? 'We sent a ${EmailVerifyScreen.codeLength}-digit code to '
                        : 'This account is waiting to be confirmed. The code goes to ',
                  ),
                  TextSpan(text: widget.email, style: KText.bodyMedium.copyWith(fontSize: 15)),
                  const TextSpan(text: '. Enter it to finish, or tap the link in the same email.'),
                ],
              ),
            ),
            const SizedBox(height: KSpacing.xxl),
            _CodeBoxes(
              controller: _ctrl,
              focusNode: _focus,
              length: EmailVerifyScreen.codeLength,
              error: _error != null,
            ),
            const SizedBox(height: KSpacing.md),
            AnimatedSwitcher(
              duration: KMotion.of(context, KMotion.quick),
              child: _error != null
                  ? Text(_error!, key: ValueKey(_error), style: KText.caption.copyWith(fontSize: 13, color: KColor.danger))
                  : _info != null
                      ? Text(_info!, key: ValueKey(_info), style: KText.caption.copyWith(fontSize: 13, color: KColor.green))
                      : const SizedBox(height: 18),
            ),
            const SizedBox(height: KSpacing.xl),
            KButton(
              label: 'Confirm email',
              width: double.infinity,
              loading: _verifying,
              onTap: code.length == EmailVerifyScreen.codeLength ? _verify : null,
            ),
            const SizedBox(height: KSpacing.md),
            Center(
              child: TextButton(
                onPressed: (_sending || _cooldown > 0) ? null : _resend,
                child: Text(
                  _sending
                      ? 'Sending...'
                      : _cooldown > 0
                          ? 'Send a new code in ${_cooldown}s'
                          : (widget.sentNow ? 'Send a new code' : 'Send me a code'),
                  style: KText.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: (_sending || _cooldown > 0) ? KColor.textMuted : KColor.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: KSpacing.lg),
            Text(
              "Can't find it? Check spam or promotions. The code works for an hour.",
              textAlign: TextAlign.center,
              style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Six boxes over one hidden field, so paste, autofill and the number pad
/// all work like a normal text field.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.error,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      child: Stack(
        children: [
          // The real input: invisible, but focusable and readable.
          Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: length,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(counterText: '', border: InputBorder.none, filled: false),
              showCursor: false,
              enableInteractiveSelection: false,
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final text = controller.text;
              return Semantics(
                label: 'Confirmation code, ${text.length} of $length digits',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var i = 0; i < length; i++) ...[
                        if (i > 0) const SizedBox(width: KSpacing.sm),
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 0.82,
                            child: AnimatedContainer(
                              duration: KMotion.of(context, KMotion.quick),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: KColor.card,
                                borderRadius: KRadius.md,
                                border: Border.all(
                                  width: (focusNode.hasFocus && i == text.length.clamp(0, length - 1)) ? 1.6 : 1,
                                  color: error
                                      ? KColor.danger
                                      : (focusNode.hasFocus && i == text.length.clamp(0, length - 1))
                                          ? KColor.textPrimary
                                          : KColor.border,
                                ),
                              ),
                              child: Text(
                                i < text.length ? text[i] : '',
                                style: KText.numMedium.copyWith(fontSize: 26),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
