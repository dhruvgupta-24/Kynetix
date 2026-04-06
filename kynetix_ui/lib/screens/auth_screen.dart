import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../services/auth_service.dart';

enum AuthMethod { email, phone }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = AuthService();

  // Core States
  bool _isSignup = false;
  AuthMethod _authMethod = AuthMethod.email;
  bool _isLoading = false;
  String? _errorMessage;

  // Email Controllers
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  // Phone Controllers
  final _phoneCtrl = TextEditingController(); 
  String _fullPhoneNumber = '';
  final _otpCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();
  bool _isOtpSent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _resetAuthState() {
    FocusScope.of(context).unfocus();
    _errorMessage = null;
    _isLoading = false;
    _isOtpSent = false;
    _otpCtrl.clear();
  }

  /// ── EMAIL LOGIC ──────────────────────────────────────────────────────────

  Future<void> _submitEmailAuth() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill out all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isSignup) {
        final response = await _authService.signUp(email: email, password: password);
        if (response.session == null && response.user != null) {
          setState(() {
            _errorMessage = 'Account created! Please check your email to confirm.';
          });
        }
      } else {
        await _authService.signIn(email: email, password: password);
        // AuthGate handles the implicit routing.
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordSheet() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text);
    bool isSending = false;
    String? sheetError;
    bool isSent = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 32,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E2C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: isSent
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.mark_email_read_outlined, color: Color(0xFF52B788), size: 48),
                        const SizedBox(height: 16),
                        const Text('Check your email', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text('We sent a password reset link to your email.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 32),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Reset Password', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        const Text('Enter your email to receive a password reset link.', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                        const SizedBox(height: 24),
                        if (sheetError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(sheetError!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13)),
                          ),
                        _StyledField(
                          controller: emailCtrl,
                          hint: 'Email Address',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSending
                                ? null
                                : () async {
                                    final em = emailCtrl.text.trim();
                                    if (em.isEmpty) {
                                      setSheetState(() => sheetError = 'Please enter an email.');
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
                                      setSheetState(() => sheetError = e.message);
                                    } catch (_) {
                                      setSheetState(() => sheetError = 'An unexpected error occurred.');
                                    } finally {
                                      setSheetState(() => isSending = false);
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF52B788),
                              foregroundColor: const Color(0xFF081C15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: isSending
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF081C15)))
                                : const Text('Send Reset Link', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  /// ── PHONE LOGIC ──────────────────────────────────────────────────────────

  Future<void> _handlePhoneOtpSend() async {
    final phone = _fullPhoneNumber.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _errorMessage = 'Please enter a valid phone number.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendPhoneOtp(phone);
      setState(() => _isOtpSent = true);
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'An unexpected error occurred sending OTP.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePhoneOtpVerify() async {
    final phone = _fullPhoneNumber.trim();
    final token = _otpCtrl.text.trim();

    if (token.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.verifyPhoneOtp(phone, token);
      // AuthGate handles the route naturally.
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Invalid OTP or network error.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ── GOOGLE LOGIC ─────────────────────────────────────────────────────────

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithGoogle();
      // AuthGate handles implicit routing via deep link or local browser redirect.
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ── BUILDERS ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Logo
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2C),
                      borderRadius: BorderRadius.circular(18),
                      image: const DecorationImage(
                        image: AssetImage('assets/branding/kynetix_icon_fg.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  _isSignup ? 'Create Account' : 'Welcome Back',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignup ? 'Sign up to build your custom nutrition engine.' : 'Sign in to access your nutrition engine.',
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Error Message
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E0F0F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3E1E1E)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Segmented Control (Sign In / Sign Up)
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2C),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            _resetAuthState();
                            setState(() => _isSignup = false);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: !_isSignup ? const Color(0xFF2E2E3E) : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text('Sign In', style: TextStyle(color: !_isSignup ? Colors.white : const Color(0xFF6B7280), fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _resetAuthState();
                            setState(() => _isSignup = true);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isSignup ? const Color(0xFF2E2E3E) : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text('Sign Up', style: TextStyle(color: _isSignup ? Colors.white : const Color(0xFF6B7280), fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Segmented Control (Email / Phone)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MethodToggle(
                      title: 'Email',
                      icon: Icons.email_outlined,
                      isSelected: _authMethod == AuthMethod.email,
                      onTap: () {
                        _resetAuthState();
                        setState(() {
                          _authMethod = AuthMethod.email;
                        });
                      },
                    ),
                    const SizedBox(width: 16),
                    _MethodToggle(
                      title: 'Phone',
                      icon: Icons.phone_android_rounded,
                      isSelected: _authMethod == AuthMethod.phone,
                      onTap: () {
                        _resetAuthState();
                        setState(() {
                          _authMethod = AuthMethod.phone;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Dynamic Form Area
                if (_authMethod == AuthMethod.email) ...[
                  _StyledField(
                    key: const ValueKey('email_field'),
                    controller: _emailCtrl,
                    focusNode: _emailFocus,
                    hint: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  _StyledField(
                    key: const ValueKey('password_field'),
                    controller: _passwordCtrl,
                    focusNode: _passwordFocus,
                    hint: 'Password',
                    icon: Icons.lock_outline,
                    isPassword: true,
                  ),
                  if (!_isSignup)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showForgotPasswordSheet,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF9CA3AF),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Forgot Password?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    )
                  else
                    const SizedBox(height: 32),

                  _PrimaryButton(
                    isLoading: _isLoading,
                    label: _isSignup ? 'Create Account' : 'Sign In',
                    onPressed: _submitEmailAuth,
                  ),
                ] else if (_authMethod == AuthMethod.phone) ...[
                  if (!_isOtpSent) ...[
                    IntlPhoneField(
                      key: const ValueKey('phone_field'),
                      controller: _phoneCtrl,
                      focusNode: _phoneFocus,
                      initialCountryCode: 'IN',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      dropdownTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
                      dropdownIconPosition: IconPosition.trailing,
                      dropdownIcon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6B7280)),
                      showCountryFlag: true,
                      decoration: InputDecoration(
                        hintText: 'Mobile Number',
                        hintStyle: const TextStyle(color: Color(0xFF6B7280)),
                        filled: true,
                        fillColor: const Color(0xFF1E1E2C),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2E2E3E), width: 1)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF52B788), width: 1.5)),
                      ),
                      onChanged: (phone) {
                        _fullPhoneNumber = phone.completeNumber;
                      },
                    ),
                    const SizedBox(height: 32),
                    _PrimaryButton(
                      isLoading: _isLoading,
                      label: 'Send OTP',
                      onPressed: _handlePhoneOtpSend,
                    ),
                  ] else ...[
                    _StyledField(
                      key: const ValueKey('otp_field'),
                      controller: _otpCtrl,
                      focusNode: _otpFocus,
                      hint: 'Enter 6-digit OTP',
                      icon: Icons.message_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 32),
                    _PrimaryButton(
                      isLoading: _isLoading,
                      label: 'Verify & ${_isSignup ? "Sign Up" : "Sign In"}',
                      onPressed: _handlePhoneOtpVerify,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _handlePhoneOtpSend,
                          child: const Text('Resend OTP', style: TextStyle(color: Color(0xFF52B788), fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        const Text('•', style: TextStyle(color: Color(0xFF6B7280))),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isOtpSent = false;
                              _otpCtrl.clear();
                            });
                          },
                          child: const Text('Change Number', style: TextStyle(color: Color(0xFF9CA3AF))),
                        ),
                      ],
                    ),
                  ]
                ],

                const SizedBox(height: 40),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: const Color(0xFF2E2E3E), thickness: 1)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    Expanded(child: Divider(color: const Color(0xFF2E2E3E), thickness: 1)),
                  ],
                ),
                const SizedBox(height: 24),

                // Google Button
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    icon: Image.network(
                      'https://mailmeteor.com/logos/assets/PNG/Google_Logo_512px.png',
                      width: 24,
                      height: 24,
                      errorBuilder: (context, error, stackTrace) => const Text(
                        'G',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                    label: const Text('Continue with Google', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2E2E3E)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: const Color(0xFF1E1E2C),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MethodToggle({required this.title, required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2D6A4F).withAlpha(51) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFF52B788) : const Color(0xFF2E2E3E)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? const Color(0xFF52B788) : const Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: isSelected ? const Color(0xFF52B788) : const Color(0xFF6B7280), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final bool isLoading;
  final String label;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.isLoading, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF52B788),
          foregroundColor: const Color(0xFF081C15),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Color(0xFF081C15))))
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final TextInputType? keyboardType;

  const _StyledField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6B7280)),
        prefixIcon: Icon(icon, color: const Color(0xFF52B788), size: 20),
        filled: true,
        fillColor: const Color(0xFF1E1E2C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2E2E3E), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF52B788), width: 1.5)),
      ),
    );
  }
}
