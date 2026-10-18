import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import 'onboarding/consent_panel.dart';

/// One-time privacy consent for signed-in users who haven't agreed to the
/// current policy yet. Shown by AuthGate after sign-in, before the app.
/// Declining keeps the user here (with Read policy and Sign out).
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({
    super.key,
    required this.userId,
    required this.onConsented,
    this.onSignOut,
  });

  final String userId;
  final VoidCallback onConsented;

  /// Defaults to the canonical [AuthService.signOut].
  final Future<void> Function()? onSignOut;

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      KSpacing.xxl, KSpacing.xxl, KSpacing.xxl, KSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Before you continue', style: KText.display),
                      ),
                      const SizedBox(height: KSpacing.xs),
                      Text(
                        'Here is how Kynetix handles your data. Agree to keep '
                        'using the app.',
                        style: KText.body.copyWith(
                          color: KColor.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ConsentPanel(
                    onAgree: ({required bool ageConfirmedAdult}) async {
                      await ConsentService.instance.recordConsent(
                        userId,
                        ageConfirmedAdult: ageConfirmedAdult,
                      );
                      onConsented();
                    },
                    onSignOut: onSignOut ?? () => const AuthService().signOut(),
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
