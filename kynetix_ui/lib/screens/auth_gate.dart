import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/persistence_service.dart';
import '../services/cloud_sync_service.dart';
import 'auth_screen.dart';
import 'app_shell.dart';
import 'onboarding_screen.dart';

class AuthGate extends StatelessWidget {
  AuthGate({super.key});

  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // Fallback or waiting state can just return a sleek dark screen.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(backgroundColor: Color(0xFF0F0F14));
        }

        // SESSION-GATED: require currentSession (live JWT), not just currentUser (stale object).
        final session = Supabase.instance.client.auth.currentSession;
        debugPrint('[AuthGate] currentSession: ${session != null ? "VALID (expires ${session.expiresAt})" : "NULL — routing to AuthScreen"}');

        if (session != null) {
          debugPrint('[AuthGate] Session valid. Routing to _LoggedInGate.');
          return const _LoggedInGate();
        }

        debugPrint('[AuthGate] No session. Routing to AuthScreen.');
        return const AuthScreen();
      },
    );
  }
}

class _LoggedInGate extends StatefulWidget {
  const _LoggedInGate();

  @override
  State<_LoggedInGate> createState() => _LoggedInGateState();
}

class _LoggedInGateState extends State<_LoggedInGate> {
  bool? _hasProfile;
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    // ── Session guard ──────────────────────────────────────────────────────────
    // Verify we actually have a live JWT before doing any remote work.
    final session = Supabase.instance.client.auth.currentSession;
    debugPrint('[_LoggedInGate] currentSession: ${session != null ? "VALID" : "NULL"}');
    if (session == null) {
      // No live session — send back to auth screen immediately.
      debugPrint('[_LoggedInGate] No session — forcing re-authentication.');
      if (mounted) setState(() => _hasProfile = null);
      // Sign out cleanly to reset the auth stream and trigger AuthGate to show AuthScreen.
      await Supabase.instance.client.auth.signOut();
      return;
    }

    debugPrint('[_LoggedInGate] Validating Supabase Profile...');
    try {
      // 1. ALWAYS Treat Supabase as the source of truth for identity
      final remoteProfile = await ProfileService.instance.fetchProfile();
      
      // Hydrate all meals, workouts, and nutrition memories from the cloud
      await CloudSyncService.instance.hydrateFromCloud();
      
      if (remoteProfile != null) {
        debugPrint('[_LoggedInGate] Supabase Profile Found. Triggering localized AppShell hydration.');
        // Hydrate local cache
        await PersistenceService.saveProfile(remoteProfile);
        await PersistenceService.setOnboardingDone();
        currentUserProfile = remoteProfile;
        
        if (mounted) setState(() => _hasProfile = true);
        return;
      }
    } catch (e) {
      debugPrint('[_LoggedInGate] Network/Fetch Exception triggering locally-cached execution failover: $e');
      // 2. Network offline fallback
      // ONLY if there is existing clean local state AND we verified a session above.
      // Session was already confirmed valid above, so this is safe to allow.
      if (PersistenceService.isOnboardingDone && currentUserProfile != null) {
        debugPrint('[_LoggedInGate] Falling back to local cache. Session is live, just offline.');
        if (mounted) setState(() => _hasProfile = true);
        return;
      }
      
      // If we reach here, we have a network/internal error AND no local profile to fall back to.
      if (mounted) {
        setState(() {
          _fatalError = 'Unable to connect to Kynetix Servers.\nPlease check your connection and try again.';
        });
      }
      return;
    }

    // 3. True fresh account OR no cloud line exists -> must onboard
    debugPrint('[_LoggedInGate] No profile found on cloud network mapping. Transferring to OnboardingScreen natively.');
    if (mounted) setState(() => _hasProfile = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_fatalError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F14),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF6B6B), size: 48),
                const SizedBox(height: 16),
                Text(
                  _fatalError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _fatalError = null;
                      _hasProfile = null;
                    });
                    _checkProfile();
                  },
                  child: const Text('Retry Connection'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => AuthService().signOut(),
                  child: const Text('Sign Out', style: TextStyle(color: Color(0xFF6B7280))),
                )
              ],
            ),
          ),
        ),
      );
    }

    if (_hasProfile == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F14),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF52B788)),
        ),
      );
    }

    if (_hasProfile!) {
      return const AppShell();
    }

    return const OnboardingScreen();
  }
}