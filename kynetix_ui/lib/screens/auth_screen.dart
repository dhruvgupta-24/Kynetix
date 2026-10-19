import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/user_session_coordinator.dart';
import '../services/dev_test_harness.dart';
import '../ui/k_brand_intro.dart';
import '../config/app_theme.dart';
import '../ui/k_segmented.dart';
import 'app_shell.dart';
import 'email_verify_screen.dart';
import 'privacy_policy_screen.dart';
import 'onboarding/password_toggle.dart';
import 'onboarding/scene_backdrop.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = AuthService();

  // Core States
  bool _isSignup = false;
  bool _isLoading = false;
  String? _errorMessage;

  /// True when [_errorMessage] is good news (sign-up confirmation sent), so
  /// the notice gets the calm info treatment instead of the error one.
  bool _noticeIsInfo = false;

  /// The in-flight request is Google sign-in, so the spinner shows on the
  /// Google button rather than on the email action.
  bool _googleLoading = false;

  /// A social sign-in owns the spinner, so the email action stays calm.
  bool get _socialLoading => _googleLoading;

  // Email Controllers
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _resetAuthState() {
    FocusScope.of(context).unfocus();
    _errorMessage = null;
    _noticeIsInfo = false;
    _isLoading = false;
  }

  /// ── EMAIL LOGIC ──────────────────────────────────────────────────────────

  Future<void> _submitEmailAuth() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Add your email and password to continue.');
      return;
    }
    if (_isSignup && password.length < 8) {
      _showError('That password is too short. Use at least 8 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeIsInfo = false;
    });

    try {
      if (_isSignup) {
        final response = await _authService.signUp(email: email, password: password);
        // Email-confirmation projects return a user without a session: the
        // account only signs in (and reaches onboarding through AuthGate)
        // once the link in the email is opened.
        if (response.session == null && response.user != null && mounted) {
          // Supabase answers a sign-up for an address that already has a
          // confirmed account with an empty identity list and no email.
          if ((response.user!.identities ?? const []).isEmpty) {
            _showError('There is already an account with that email. Sign in instead.');
          } else {
            await _openVerify(email, sentNow: true);
          }
        }
      } else {
        await _authService.signIn(email: email, password: password);
        // AuthGate handles the implicit routing.
      }
    } on AuthException catch (e) {
      final m = '${e.code ?? ''} ${e.message}'.toLowerCase();
      if (!_isSignup && (m.contains('email_not_confirmed') || m.contains('not confirmed'))) {
        if (mounted) setState(() => _isLoading = false);
        await _openVerify(email, sentNow: false);
        return;
      }
      _showError(_friendlyAuthError(e));
    } catch (e) {
      _showError(_genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _openVerify(String email, {required bool sentNow}) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EmailVerifyScreen(email: email, sentNow: sentNow)),
    );
  }

  static const _genericError = "That didn't go through. Check your connection and try again.";

  void _showError(String message) {
    if (!mounted) return;
    KHaptics.reject();
    setState(() {
      _errorMessage = message;
      _noticeIsInfo = false;
    });
  }

  /// Maps Supabase auth failures to calm, actionable copy (docs/VOICE.md):
  /// what happened and what to do, never raw exception text.
  static String _friendlyAuthError(AuthException e) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    bool has(String s) => code.contains(s) || msg.contains(s);
    if (has('invalid_credentials') || has('invalid login')) {
      return "That email and password don't match. Try again or reset your password.";
    }
    if (has('email_not_confirmed') || has('not confirmed')) {
      return 'Confirm your email first. The link is in your inbox.';
    }
    if (has('user_already_exists') || has('already registered') || has('already been registered')) {
      return 'There is already an account with that email. Sign in instead.';
    }
    if (has('weak_password') || has('password should be')) {
      return 'That password is too short. Use at least 8 characters.';
    }
    if (has('email_address_invalid') || has('invalid email') || has('unable to validate email')) {
      return "That email doesn't look right. Check it and try again.";
    }
    if (has('otp_expired') || has('token has expired') || has('invalid otp') || has('token is invalid')) {
      return "That code didn't work. Check it, or send a new one.";
    }
    if (has('rate') || has('too many') || has('security purposes')) {
      return 'Too many tries. Give it a minute, then try again.';
    }
    if (has('phone')) {
      return "That number didn't go through. Check it and try again.";
    }
    return _genericError;
  }

  Future<void> _showForgotPasswordSheet() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text);
    bool isSending = false;
    String? sheetError;
    bool isSent = false;

    await showKSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom + KSpacing.xxl,
              ),
              child: SingleChildScrollView(
                child: AnimatedSize(
                  duration: KMotion.of(context, KMotion.standard),
                  curve: KMotion.emphasizedCurve,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: KMotion.of(context, KMotion.standard),
                    child: isSent
                        ? Padding(
                            key: const ValueKey('reset-sent'),
                            padding: const EdgeInsets.fromLTRB(KSpacing.xxl, 0, KSpacing.xxl, KSpacing.lg),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const KDragHandle(),
                                const SizedBox(height: KSpacing.xl),
                                _IconBadge(
                                  icon: Icons.mark_email_read_outlined,
                                  color: KColor.green,
                                  size: 64,
                                ),
                                const SizedBox(height: KSpacing.lg),
                                Semantics(
                                  liveRegion: true,
                                  child: Text('Check your inbox', style: KText.h1, textAlign: TextAlign.center),
                                ),
                                const SizedBox(height: KSpacing.sm),
                                Text(
                                  "If there's an account for that email, a reset link is on its way.",
                                  textAlign: TextAlign.center,
                                  style: KText.body.copyWith(color: KColor.textSecondary),
                                ),
                                const SizedBox(height: KSpacing.xxl),
                              ],
                            ),
                          )
                        : Column(
                            key: const ValueKey('reset-form'),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const KSheetHeader(
                                'Reset your password',
                                subtitle: "Drop your email and we'll send you a reset link.",
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.xl, KSpacing.xl, 0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _InlineNotice(message: sheetError),
                                    _StyledField(
                                      controller: emailCtrl,
                                      hint: 'Email address',
                                      icon: Icons.email_outlined,
                                      keyboardType: TextInputType.emailAddress,
                                    ),
                                    const SizedBox(height: KSpacing.xl),
                                    KButton(
                                      label: 'Send reset link',
                                      width: double.infinity,
                                      loading: isSending,
                                      onTap: isSending
                                          ? null
                                          : () async {
                                              final em = emailCtrl.text.trim();
                                              if (em.isEmpty) {
                                                setSheetState(() => sheetError = 'Add your email first.');
                                                return;
                                              }
                                              setSheetState(() {
                                                isSending = true;
                                                sheetError = null;
                                              });
                                              try {
                                                await Supabase.instance.client.auth.resetPasswordForEmail(
                                                  em,
                                                  redirectTo: 'kynetix://reset-password',
                                                );
                                                setSheetState(() => isSent = true);
                                              } on AuthException catch (e) {
                                                setSheetState(() => sheetError = _friendlyAuthError(e));
                                              } catch (_) {
                                                setSheetState(() => sheetError = _genericError);
                                              } finally {
                                                setSheetState(() => isSending = false);
                                              }
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// ── GOOGLE LOGIC ─────────────────────────────────────────────────────────

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _googleLoading = true;
      _errorMessage = null;
      _noticeIsInfo = false;
    });

    try {
      await _authService.signInWithGoogle();
      // AuthGate handles implicit routing via deep link or local browser redirect.
    } on AuthException catch (e) {
      _showError(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('[AuthScreen] Google sign-in failed: $e');
      _showError("Google sign-in didn't go through. Try again, or use email.");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _googleLoading = false;
        });
      }
    }
  }

  /// ── BUILDERS ─────────────────────────────────────────────────────────────

  // KSegmented fires the selection haptic, so these stay silent.
  void _selectSignIn() {
    FocusScope.of(context).unfocus();
    _resetAuthState();
    setState(() => _isSignup = false);
  }

  void _selectSignUp() {
    _resetAuthState();
    setState(() => _isSignup = true);
  }

  void _openPrivacyPolicy() {
    KHaptics.select();
    Navigator.of(context).push(
      kRiseRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Full-bleed scene: the lifter for sign-in, the rack for sign-up. The
    // photo cross-fades when the mode flips; the form sits where the scrim
    // has settled into the page background.
    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final heroH = (size.height * 0.5).clamp(300.0, 520.0);
    final sections = <Widget>[
      _Hero(height: (heroH * 0.62).clamp(196.0, 320.0)),
      const SizedBox(height: KSpacing.xl),
      _Headline(isSignup: _isSignup),
      const SizedBox(height: KSpacing.xl),
      // The form sits on the page itself (no glass card): the photo, the
      // wordmark and the type do the work.
      _buildForm(context),
      const SizedBox(height: KSpacing.xxl),
      _buildAlternatives(context),
      _LegalLine(onOpenPolicy: _openPrivacyPolicy),
    ];

    return KPage(
      tone: KTone.neutral,
      intensity: 0.35,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH + topInset,
            child: KSceneBackdrop(
              asset: _isSignup ? KScene.rack : KScene.lifter,
              alignment: _isSignup ? const Alignment(0, -0.1) : const Alignment(0.3, -0.35),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.lg, KSpacing.xl, KSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      // One orchestrated entrance on first mount; plays once.
                      children: kStagger(sections, stagger: const Duration(milliseconds: 45)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Segmented control (Sign in / Sign up)
        KSegmented<bool>(
          segments: const [
            KSegment(false, 'Sign in'),
            KSegment(true, 'Sign up'),
          ],
          value: _isSignup,
          onChanged: (signup) => signup ? _selectSignUp() : _selectSignIn(),
        ),
        const SizedBox(height: KSpacing.lg),

        // Error / info message
        _InlineNotice(message: _errorMessage, isInfo: _noticeIsInfo),

        // Email and password; the forgot-password link swaps for space on
        // sign-up, so the height eases rather than jumps.
        AnimatedSize(
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.emphasizedCurve,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _emailFields(context),
          ),
        ),
      ],
    );
  }

  List<Widget> _emailFields(BuildContext context) {
    return [
      _StyledField(
        key: const ValueKey('email_field'),
        controller: _emailCtrl,
        focusNode: _emailFocus,
        hint: 'Email address',
        icon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _passwordFocus.requestFocus(),
      ),
      const SizedBox(height: KSpacing.md),
      _StyledField(
        key: const ValueKey('password_field'),
        controller: _passwordCtrl,
        focusNode: _passwordFocus,
        hint: _isSignup ? 'Password, at least 8 characters' : 'Password',
        icon: Icons.lock_outline,
        isPassword: true,
        textInputAction: TextInputAction.done,
        autofillHints: [_isSignup ? AutofillHints.newPassword : AutofillHints.password],
        onSubmitted: (_) {
          if (!_isLoading) _submitEmailAuth();
        },
      ),
      if (!_isSignup)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: _showForgotPasswordSheet,
            style: TextButton.styleFrom(
              foregroundColor: KColor.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.sm, vertical: KSpacing.md),
              minimumSize: const Size(48, 48),
              shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
            ),
            child: Text(
              'Forgot password?',
              style: KText.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: KColor.textSecondary),
            ),
          ),
        )
      else
        const SizedBox(height: KSpacing.xl),
      KButton(
        label: _isSignup ? 'Create account' : 'Sign in',
        width: double.infinity,
        loading: _isLoading && !_socialLoading,
        onTap: _submitEmailAuth,
      ),
    ];
  }

  Widget _buildAlternatives(BuildContext context) {
    final rule = KColor.fg.withValues(alpha: KColor.isDark ? 0.10 : 0.12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Divider
        Row(
          children: [
            Expanded(child: Container(height: 1, color: rule)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
              child: Text('or', style: KText.caption.copyWith(color: KColor.textMuted)),
            ),
            Expanded(child: Container(height: 1, color: rule)),
          ],
        ),
        const SizedBox(height: KSpacing.xl),

        // Google button
        _GoogleButton(
          onTap: _isLoading ? null : _handleGoogleSignIn,
          loading: _googleLoading,
        ),
        const SizedBox(height: KSpacing.lg),
        if (kDebugMode) ...[
          Center(
            child: TextButton.icon(
              key: const ValueKey('dev_quick_login_button'),
              onPressed: () async {
                const devId = 'dev_tester_pixel7';
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('dev_auto_login_user_id', devId);
                await UserSessionCoordinator.instance.initializeForUser(devId);
                await DevTestHarness.seedDevTesterData(devId);
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const AppShell()),
                  );
                }
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: KColor.textMuted,
                shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
              ),
              icon: Icon(Icons.developer_mode, color: KColor.textMuted, size: 18),
              label: Text(
                'Dev login (test workout)',
                style: KText.caption.copyWith(
                  color: KColor.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Shared field decoration ──────────────────────────────────────────────────
// Carbon: a faint lifted well with a white hairline. Paper: a clean card-white
// well with the warm border. Focus is an ink border (plus the focus ring).

InputDecoration _fieldDecoration({required String hint, IconData? icon}) {
  final dark = KColor.isDark;
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: KRadius.md,
        borderSide: BorderSide(color: c, width: w),
      );
  final rest = dark ? KColor.fg.withValues(alpha: 0.10) : KColor.border;
  return InputDecoration(
    hintText: hint,
    hintStyle: KText.body.copyWith(color: KColor.textMuted, fontSize: 15),
    prefixIcon: icon == null ? null : Icon(icon, color: KColor.textMuted, size: 20),
    filled: true,
    fillColor: dark ? KColor.fg.withValues(alpha: 0.04) : KColor.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.xl, vertical: 17),
    border: border(rest),
    enabledBorder: border(rest),
    focusedBorder: border(KColor.ink, 1.5),
    errorBorder: border(KColor.danger),
    focusedErrorBorder: border(KColor.danger, 1.5),
  );
}

// ─── Kinetic orbit (brand moment) ─────────────────────────────────────────────
// Three thin orbits, one per world (fuel, protein, train), each carrying a
// short comet arc around the Kynetix mark. Moment: ambient brand presence.
// Trigger: screen mounted. Loop: 24 s, runs only while
// `KMotion.ambientAllowed` (never under reduced motion or in tests), and stops
// when the widget leaves the tree. Off: the comets rest at a fixed, composed
// position, so the end state is identical with motion disabled.
// Public so the auth gate's loader can share the same mark.

class KineticOrbit extends StatefulWidget {
  const KineticOrbit({super.key, this.size = 220, this.showMark = true, this.markSize = 52});

  final double size;
  final bool showMark;
  final double markSize;

  @override
  State<KineticOrbit> createState() => _KineticOrbitState();
}

class _KineticOrbitState extends State<KineticOrbit> with SingleTickerProviderStateMixin {
  /// Resting phase: a composed spread of the three comets.
  static const _rest = 0.14;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
    value: _rest,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = KMotion.ambientAllowed(context);
    if (allowed && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!allowed && _spin.isAnimating) {
      _spin.stop();
      _spin.value = _rest;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    final scene = _OrbitScene(
      track: KColor.fg.withValues(alpha: dark ? 0.09 : 0.11),
      // One accent comet; the other two are ink and set-back ink.
      colors: [KColor.ember, KColor.ink, KColor.fat],
      cometAlpha: dark ? 1.0 : 0.9,
    );
    final s = widget.size;
    final m = widget.markSize;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _OrbitPainter(scene: scene, phase: _spin)),
              ),
            ),
            if (widget.showMark)
              DecoratedBox(
                // On Carbon the dark mark gets a hairline so it doesn't sink
                // into the black; Paper gets the soft card shadow instead.
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(m * 0.28),
                  border: dark ? Border.all(color: KColor.fg.withValues(alpha: 0.14)) : null,
                  boxShadow: KShadow.card,
                ),
                // The app icon: the Shear K on graphite.
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(m * 0.28),
                  child: ColoredBox(
                    color: kBrandGraphite,
                    child: SizedBox.square(
                      dimension: m,
                      child: Center(
                        child: KShearWordmark(fontSize: m * 0.62, ink: kBrandBone, ember: kBrandEmber, kOnly: true),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Immutable inputs for one paint of the orbit (resolved from the palette in
/// `build`, so a theme flip repaints with the new values).
class _OrbitScene {
  const _OrbitScene({required this.track, required this.colors, required this.cometAlpha});
  final Color track;
  final List<Color> colors;
  final double cometAlpha;

  @override
  bool operator ==(Object other) =>
      other is _OrbitScene &&
      other.track == track &&
      other.cometAlpha == cometAlpha &&
      other.colors.length == colors.length &&
      List.generate(colors.length, (i) => other.colors[i] == colors[i]).every((e) => e);

  @override
  int get hashCode => Object.hash(track, cometAlpha, Object.hashAll(colors));
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.scene, required this.phase}) : super(repaint: phase);

  final _OrbitScene scene;
  final Animation<double> phase;

  // Radii as a fraction of the half-size, turns per loop (integers keep the
  // loop seamless), start angle and comet length (radians).
  static const _radii = [0.52, 0.74, 0.96];
  static const _turns = [2, -1, 1];
  static const _start = [0.4, 2.6, 4.4];
  static const _sweep = [1.5, 1.2, 1.0];
  static const _segments = 18;
  static const _tau = 6.283185307179586;

  final Paint _track = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.2;
  final Paint _dot = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final half = size.shortestSide / 2 - 4;
    final t = phase.value;
    _track.color = scene.track;
    for (var i = 0; i < _radii.length; i++) {
      final r = half * _radii[i];
      canvas.drawCircle(c, r, _track);

      final color = scene.colors[i % scene.colors.length];
      final head = _start[i] + t * _tau * _turns[i];
      final sweep = _sweep[i];
      final dir = _turns[i] >= 0 ? 1.0 : -1.0;
      final rect = Rect.fromCircle(center: c, radius: r);
      // Comet: the tail fades out behind the head.
      final seg = sweep / _segments;
      for (var k = 0; k < _segments; k++) {
        final f = (k + 1) / _segments; // 0 (tail) → 1 (head)
        _arc.color = color.withValues(alpha: scene.cometAlpha * f * f);
        final from = head - dir * sweep + dir * seg * k;
        canvas.drawArc(rect, from, dir * seg, false, _arc);
      }
      _dot.color = color.withValues(alpha: scene.cometAlpha);
      canvas.drawCircle(c + Offset.fromDirection(head, r), 3.2, _dot);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.scene != scene || old.phase != phase;
}

// ─── Hero ─────────────────────────────────────────────────────────────────────
// The signature moment: the scene photo under its scrim and a heavy, tightly
// tracked Geist wordmark set where the scrim has settled, so it reads in both
// themes. The tagline sits on a short ink rule, like a masthead line.

class _Hero extends StatelessWidget {
  const _Hero({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  label: 'Kynetix',
                  // The Shear wordmark, where the launch intro leaves it.
                  child: const KShearWordmark(fontSize: 54),
                ),
                const SizedBox(height: KSpacing.md),
                Text(
                  'Real food. Real lifts.',
                  style: KText.bodyMedium.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Headline ─────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.isSignup});
  final bool isSignup;

  @override
  Widget build(BuildContext context) {
    final title = isSignup ? 'Make it official.' : 'Welcome back.';
    final body = isSignup
        ? 'Log roti, dal and paneer the way you actually eat them. Track your sets. Get targets that fit your week.'
        : 'Your meals, targets and lifts are right where you left them.';
    return AnimatedSwitcher(
      duration: KMotion.of(context, KMotion.standard),
      switchInCurve: KMotion.decelerate,
      switchOutCurve: KMotion.accelerate,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey(isSignup),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: KText.h1.copyWith(fontSize: 26, height: 1.1)),
          ),
          const SizedBox(height: KSpacing.sm),
          Text(body, style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15, height: 1.5)),
        ],
      ),
    );
  }
}

// ─── Legal line ───────────────────────────────────────────────────────────────
// Informational only: no consent checkbox, no change to the auth flow.

class _LegalLine extends StatelessWidget {
  const _LegalLine({required this.onOpenPolicy});
  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    final style = KText.caption.copyWith(color: KColor.textMuted, fontSize: 12.5);
    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.sm),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('By continuing, you agree to our', style: style),
          TextButton(
            onPressed: onOpenPolicy,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.xs),
              foregroundColor: KColor.textPrimary,
              tapTargetSize: MaterialTapTargetSize.padded,
              shape: const RoundedRectangleBorder(borderRadius: KRadius.sm),
            ),
            child: Text(
              'Privacy policy',
              style: style.copyWith(
                color: KColor.textPrimary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: KColor.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Inline notice (error / info) ─────────────────────────────────────────────

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, this.isInfo = false});
  final String? message;

  /// Good news (the sign-up confirmation) gets the calm success treatment
  /// instead of danger.
  final bool isInfo;

  @override
  Widget build(BuildContext context) {
    final msg = message;
    final color = isInfo ? KColor.green : KColor.danger;
    final dark = KColor.isDark;
    return AnimatedSize(
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.quick),
        child: msg == null
            ? const SizedBox(width: double.infinity, key: ValueKey('no-notice'))
            : Padding(
                key: ValueKey(msg),
                padding: const EdgeInsets.only(bottom: KSpacing.lg),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(KSpacing.md),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: dark ? 0.10 : 0.07),
                      borderRadius: KRadius.sm,
                      border: Border.all(color: color.withValues(alpha: dark ? 0.35 : 0.30)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isInfo ? Icons.mark_email_unread_outlined : Icons.error_outline_rounded,
                          size: 18,
                          color: color,
                          semanticLabel: isInfo ? 'Info' : 'Error',
                        ),
                        const SizedBox(width: KSpacing.sm),
                        Expanded(
                          child: Text(
                            msg,
                            style: KText.caption.copyWith(
                              fontSize: 13,
                              color: isInfo ? KColor.textPrimary : KColor.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── Google button ────────────────────────────────────────────────────────────
// Secondary action: an outlined pill matching KButton(outlined: true).

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onTap, this.loading = false});
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final dark = KColor.isDark;
    return Pressable(
      onTap: onTap == null
          ? null
          : () {
              KHaptics.commit();
              onTap!();
            },
      borderRadius: KRadius.pill,
      semanticLabel: 'Continue with Google',
      child: AnimatedOpacity(
        duration: KMotion.of(context, KMotion.quick),
        opacity: enabled || loading ? 1 : 0.5,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.xl, vertical: KSpacing.md),
          decoration: BoxDecoration(
            color: dark ? KColor.fg.withValues(alpha: 0.03) : KColor.card.withValues(alpha: 0.7),
            borderRadius: KRadius.pill,
            border: Border.all(color: KColor.fg.withValues(alpha: dark ? 0.18 : 0.2), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: KMotion.of(context, KMotion.quick),
                child: loading
                    ? const SizedBox.square(
                        key: ValueKey('google-loading'),
                        dimension: 20,
                        child: Center(child: KSpinner(size: 18)),
                      )
                    : Image.asset(
                        'assets/branding/google_logo.png',
                        key: const ValueKey('google-logo'),
                        width: 20,
                        height: 20,
                        cacheWidth: 64,
                        excludeFromSemantics: true,
                        errorBuilder: (context, error, stackTrace) => Text(
                          'G',
                          style: KText.h2.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              const SizedBox(width: KSpacing.md),
              Flexible(
                child: Text(
                  'Continue with Google',
                  textAlign: TextAlign.center,
                  style: KText.bodyMedium.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Icon badge ───────────────────────────────────────────────────────────────

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color, this.size = 56});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.12 : 0.09),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: dark ? 0.35 : 0.30)),
        ),
        child: Icon(icon, color: color, size: size * 0.46),
      ),
    );
  }
}

// ─── Focus ring ───────────────────────────────────────────────────────────────
// A soft monochrome halo while the wrapped field has focus. Decoration only —
// the ink focused border on the field itself carries the state too.

class _FocusRing extends StatefulWidget {
  const _FocusRing({required this.focusNode, required this.child});
  final FocusNode focusNode;
  final Widget child;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  late bool _focused = widget.focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _FocusRing old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
      _focused = widget.focusNode.hasFocus;
    }
  }

  void _onFocus() {
    if (!mounted) return;
    final f = widget.focusNode.hasFocus;
    if (f != _focused) setState(() => _focused = f);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = KColor.fg.withValues(alpha: KColor.isDark ? 0.10 : 0.07);
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
      child: widget.child,
    );
  }
}

// ─── Styled field ─────────────────────────────────────────────────────────────

class _StyledField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  const _StyledField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });

  @override
  State<_StyledField> createState() => _StyledFieldState();
}

class _StyledFieldState extends State<_StyledField> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  /// Password fields start hidden; the eye toggle flips this.
  bool _obscured = true;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = KText.bodyMedium;
    return _FocusRing(
      focusNode: _node,
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        obscureText: widget.isPassword && _obscured,
        enableSuggestions: !widget.isPassword,
        autocorrect: !widget.isPassword,
        keyboardType: widget.isPassword && !_obscured
            ? TextInputType.visiblePassword
            : widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        autofillHints: widget.autofillHints,
        style: base.copyWith(fontSize: 15, color: KColor.textPrimary),
        cursorColor: KColor.ink,
        decoration: _fieldDecoration(hint: widget.hint, icon: widget.icon).copyWith(
          suffixIcon: widget.isPassword
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(end: KSpacing.xs),
                  child: PasswordVisibilityToggle(
                    key: const ValueKey('password_visibility_toggle'),
                    obscured: _obscured,
                    onToggle: () => setState(() => _obscured = !_obscured),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
