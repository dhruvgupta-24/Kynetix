import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/k_brand_intro.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/persistence_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/nutrition_hydration_guard.dart';
import '../services/eating_pattern_service.dart';
import 'auth_screen.dart';
import 'app_shell.dart';
import 'onboarding_screen.dart';
import 'consent_screen.dart';
import 'privacy_policy_screen.dart';
import '../services/consent_service.dart';
import '../services/insights_report_service.dart';
import '../services/user_session_coordinator.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = const AuthService();

  @override
  void initState() {
    super.initState();
    // Loads prefs early so the consent check below can answer synchronously.
    ConsentService.instance.warmUp().ignore();
    // Health Connect's "privacy policy" link launches the app; show it.
    PrivacyPolicyLaunch.attach(this, () => mounted ? Navigator.maybeOf(context) : null);
  }

  @override
  void dispose() {
    PrivacyPolicyLaunch.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // Routing is resolved first; the result is then cross-faded so the
        // app never hard-cuts between the loader, auth and the signed-in tree.
        final Widget child;
        if (snapshot.connectionState == ConnectionState.waiting) {
          child = const _BrandLoader(
            key: ValueKey('auth-gate-waiting'),
            semanticLabel: 'Loading Kynetix',
            messages: ['Warming up…'],
          );
        } else {
          // SESSION-GATED: require currentSession (live JWT), not just currentUser (stale object).
          final session = Supabase.instance.client.auth.currentSession;
          final hasDevSession = kDebugMode && PersistenceService.cachedOwnerId != null;
          debugPrint('[AuthGate] currentSession: ${session != null ? "VALID (expires ${session.expiresAt})" : (hasDevSession ? "DEV SESSION VALID" : "NULL, routing to AuthScreen")}');

          if (session != null || hasDevSession) {
            debugPrint('[AuthGate] Session valid. Routing to _LoggedInGate.');
            child = const _LoggedInGate(key: ValueKey('auth-gate-signed-in'));
          } else {
            debugPrint('[AuthGate] No session. Routing to AuthScreen.');
            child = const AuthScreen(key: ValueKey('auth-gate-signed-out'));
          }
        }
        return _GateSwitcher(child: child);
      },
    );
  }
}

// ─── Gate cross-fade ──────────────────────────────────────────────────────────
// Moment: context switch. Trigger: auth/profile state resolves. Change: the
// old surface fades out while the new one fades in over the shared ink base.
// Duration: emphasized in, instant out. Haptic: none (no user action).
// Reduced motion: instant swap.

/// True once the gate shows a real destination (sign-in, onboarding, the
/// app) rather than its loader. The launch intro waits for it, so it lifts
/// onto the screen the user came for.
final ValueNotifier<bool> appLanded = ValueNotifier(false);

/// True once the launch intro has started to lift off the app (set by
/// KynetixApp). Anything that wants to greet the user, like the update
/// prompt, waits for it.
final ValueNotifier<bool> introRevealed = ValueNotifier(false);

class _GateSwitcher extends StatelessWidget {
  const _GateSwitcher({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!appLanded.value && child is! _BrandLoader) {
      WidgetsBinding.instance.addPostFrameCallback((_) => appLanded.value = true);
    }
    return ColoredBox(
      color: KColor.bg,
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.emphasized),
        // Outgoing surface is removed at once: after sign-out the old
        // AppShell must not rebuild with a null profile mid-fade.
        reverseDuration: Duration.zero,
        switchInCurve: KMotion.decelerate,
        switchOutCurve: KMotion.accelerate,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, ?current],
        ),
        child: child,
      ),
    );
  }
}

// ─── Brand loader ─────────────────────────────────────────────────────────────
// Calm, branded boot wait: the heavy wordmark from the sign-in masthead with
// quiet loading dots beneath, and honest loader copy that rotates no faster
// than the VOICE.md dwell. The dots loop only while ambient motion is
// allowed. Reads correctly on Carbon and Paper.

class _BrandLoader extends StatelessWidget {
  const _BrandLoader({
    super.key,
    required this.semanticLabel,
    this.messages = const [],
  });

  final String semanticLabel;
  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return KPage(
      tone: KTone.neutral,
      intensity: 0.5,
      body: KLoaderPanel(
        semanticsLabel: semanticLabel,
        messages: messages,
        loader: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KShearWordmark(fontSize: 40),
            const SizedBox(height: KSpacing.lg),
            const KLoadingDots(),
          ],
        ),
      ),
    );
  }
}

// ─── Fatal connection error ───────────────────────────────────────────────────

class _GateError extends StatelessWidget {
  const _GateError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return KPage(
      tone: KTone.neutral,
      intensity: 0.7,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KSpacing.xxl),
            child: KCard(
              padding: const EdgeInsets.all(KSpacing.xxl),
              borderRadius: KRadius.xl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: KColor.danger.withValues(alpha: KColor.isDark ? 0.12 : 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: KColor.danger.withValues(alpha: KColor.isDark ? 0.35 : 0.30)),
                    ),
                    child: Icon(Icons.cloud_off_rounded, color: KColor.danger, size: 28, semanticLabel: 'Offline'),
                  ),
                  const SizedBox(height: KSpacing.lg),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: KText.bodyMedium.copyWith(fontSize: 15, height: 1.45),
                    ),
                  ),
                  const SizedBox(height: KSpacing.xxl),
                  KButton(
                    label: 'Try again',
                    icon: Icons.refresh_rounded,
                    width: double.infinity,
                    onTap: onRetry,
                  ),
                  const SizedBox(height: KSpacing.sm),
                  TextButton(
                    onPressed: onSignOut,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(88, 48),
                      foregroundColor: KColor.textSecondary,
                      shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
                    ),
                    child: Text('Sign out', style: KText.bodyMedium.copyWith(color: KColor.textSecondary)),
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

class _LoggedInGate extends StatefulWidget {
  const _LoggedInGate({super.key});

  @override
  State<_LoggedInGate> createState() => _LoggedInGateState();
}

class _LoggedInGateState extends State<_LoggedInGate> {
  late bool? _hasProfile = () {
    if (!PersistenceService.isOnboardingDone || currentUserProfile == null) return null;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? (kDebugMode ? PersistenceService.cachedOwnerId : null);
    if (currentUserId == null) return null;
    if (PersistenceService.cachedOwnerId != currentUserId) return null;
    // The in-memory onboarding flag and profile are only trustworthy once the
    // session coordinator has actually loaded THIS user's scoped data. A
    // stale flag from a previous account (or a half-finished switch) must
    // never let a brand-new signup skip onboarding.
    // currentUserId is set as soon as a load STARTS; only isReadyFor means
    // this user's data has finished loading.
    if (!UserSessionCoordinator.instance.isReadyFor(currentUserId)) return null;
    return true;
  }();
  String? _fatalError;

  /// Agreement to the current privacy policy: true, false, or null while it
  /// is being looked up. Gates both the app and onboarding.
  late bool? _consented = () {
    final uid = _userId;
    // Only a local "yes" is final here; "no" still checks the profile row
    // (reinstall / new phone) before asking again.
    return uid != null && ConsentService.instance.peek(uid) == true ? true : null;
  }();

  String? get _userId =>
      Supabase.instance.client.auth.currentUser?.id ??
      (kDebugMode ? PersistenceService.cachedOwnerId : null);

  /// Local record first; then (signed in, e.g. after a reinstall) the
  /// profile row. Offline with no local record → ask again; it's quick.
  Future<void> _resolveConsent() async {
    final uid = _userId;
    if (uid == null) return;
    var ok = await ConsentService.instance.hasConsented(uid);
    if (!ok && Supabase.instance.client.auth.currentSession != null) {
      ok = await ConsentService.instance.restoreFromCloud(uid);
    }
    if (!mounted) return;
    setState(() => _consented = ok);
    if (ok) ConsentService.instance.syncToCloud(uid).ignore();
  }

  void _onConsented() {
    if (!mounted) return;
    setState(() => _consented = true);
  }

  Future<void> _recordOnboardingConsent({required bool ageConfirmedAdult}) async {
    final uid = _userId;
    if (uid == null) throw StateError('No signed-in user');
    await ConsentService.instance.recordConsent(uid, ageConfirmedAdult: ageConfirmedAdult);
    _consented = true;
  }

  static const _connectionError =
      "Couldn't reach Kynetix. Check your connection and try again.";

  /// Onboarding finished (questions saved, optional ChatGPT step done or
  /// skipped, welcome moment played): cross-fade into the app.
  void _onOnboardingFinished() {
    if (!mounted || _hasProfile == true) return;
    setState(() => _hasProfile = true);
  }

  @override
  void initState() {
    super.initState();
    if (_consented == true) {
      // Known locally; push it to the profile row if it isn't there yet.
      final uid = _userId;
      if (uid != null) ConsentService.instance.syncToCloud(uid).ignore();
    } else {
      _resolveConsent();
    }
    if (_hasProfile == true) {
      _startBackgroundSync();
    } else {
      _checkProfile();
    }
  }

  Future<void> _checkProfile() async {
    // ── Session guard ──────────────────────────────────────────────────────────
    // Verify we actually have a live JWT before doing any remote work.
    final session = Supabase.instance.client.auth.currentSession;
    final currentUserId = session?.user.id ?? (kDebugMode ? PersistenceService.cachedOwnerId : null);
    debugPrint('[_LoggedInGate] currentSession: ${session != null ? "VALID" : "NULL"} (currentUserId: $currentUserId)');
    if (currentUserId == null) {
      // No live session — send back to auth screen immediately.
      debugPrint('[_LoggedInGate] No session, forcing re-authentication.');
      if (mounted) setState(() => _hasProfile = null);
      // Sign out cleanly to reset the auth stream and trigger AuthGate to show AuthScreen.
      await Supabase.instance.client.auth.signOut();
      return;
    }

    // Initialize or switch user session via UserSessionCoordinator
    if (!UserSessionCoordinator.instance.isReadyFor(currentUserId)) {
      debugPrint('[_LoggedInGate] Initializing user session for: $currentUserId');
      try {
        await UserSessionCoordinator.instance.initializeForUser(currentUserId);
      } catch (e) {
        debugPrint('[_LoggedInGate] Session initialization failed: $e');
        if (mounted) setState(() => _fatalError = _connectionError);
        return;
      }
    }

    if (session == null && kDebugMode) {
      // Debug dev session: there is no JWT to reach the cloud with, so local
      // state decides. A dev account without a saved profile still onboards
      // instead of landing in AppShell with nothing.
      final onboarded = PersistenceService.isOnboardingDone && currentUserProfile != null;
      if (mounted) setState(() => _hasProfile = onboarded);
      return;
    }

    // Quick-pass check: if onboarding is done and local profile exists, show AppShell immediately
    if (PersistenceService.isOnboardingDone && currentUserProfile != null) {
      debugPrint('[_LoggedInGate] Quick-pass active. Showing AppShell immediately, running background sync.');
      NutritionHydrationGuard.instance.markComplete(session?.user.id ?? currentUserId);
      if (mounted) {
        setState(() {
          _hasProfile = true;
        });
      }
      _startBackgroundSync();
      return;
    }

    _doFullSync();
  }

  /// True while this gate is mounted and [uid]'s session (as of [epoch]) is
  /// still the loaded one. Checked after every await and before any write, so
  /// a sign-out or account switch mid-sync never saves this user's profile
  /// (or anything else) under the next account.
  bool _stillOwns(String uid, int epoch) =>
      mounted && CloudSyncService.isSessionCurrent(uid, epoch);

  Future<void> _startBackgroundSync() async {
    final uid = _userId;
    final epoch = PersistenceService.sessionEpoch;
    if (uid == null || !_stillOwns(uid, epoch)) return;
    try {
      final remoteProfile = await ProfileService.instance.fetchRemoteProfile();
      if (!_stillOwns(uid, epoch)) return;
      await CloudSyncService.instance.hydrateFromCloud();
      if (!_stillOwns(uid, epoch)) return;
      if (remoteProfile != null) {
        // Full cloud backup (profile_json) when present; older rows only
        // hold basic columns, the rest then comes from this device.
        final mergedProfile = ProfileService.mergeRemoteWithLocal(
            remoteProfile, currentUserProfile);
        final resolvedAnchor = mergedProfile.portionAnchor;
        // Saved through the one path that also backs it up (this
        // backfills profile_json for rows written by older versions).
        final savedProfile = await ProfileService.instance.save(mergedProfile);
        if (!_stillOwns(uid, epoch)) return;
        currentUserProfile = savedProfile;
        // Seed eating pattern scalars from the declared style.
        if (resolvedAnchor != null) {
          EatingPatternService.instance.seedFromPortionAnchor(resolvedAnchor);
          await EatingPatternService.instance.save();
          if (!_stillOwns(uid, epoch)) return;
        }
        if (mounted) {
          setState(() {}); // refresh visual state
        }
      }
      if (!_stillOwns(uid, epoch)) return;
      if (currentUserProfile != null) {
        InsightsReportService.instance.maybeRecompute(currentUserProfile!).ignore();
      }
    } catch (e) {
      debugPrint('[_LoggedInGate] Background sync failed (non-blocking): $e');
    }
  }

  Future<void> _doFullSync() async {
    debugPrint('[_LoggedInGate] Validating Supabase Profile...');
    final uid = _userId;
    final epoch = PersistenceService.sessionEpoch;
    if (uid == null || !_stillOwns(uid, epoch)) return;
    try {
      // 1. ALWAYS Treat Supabase as the source of truth for identity
      final remoteProfile = await ProfileService.instance.fetchRemoteProfile();
      if (!_stillOwns(uid, epoch)) return;

      // Hydrate all meals, workouts, and nutrition memories from the cloud
      await CloudSyncService.instance.hydrateFromCloud();
      if (!_stillOwns(uid, epoch)) return;

      if (remoteProfile != null) {
        debugPrint('[_LoggedInGate] Supabase Profile Found. Triggering localized AppShell hydration.');
        
        // Full cloud backup (profile_json) when present; older rows only
        // hold basic columns, the rest then comes from this device.
        final mergedProfile = ProfileService.mergeRemoteWithLocal(
            remoteProfile, currentUserProfile);
        final resolvedAnchor = mergedProfile.portionAnchor;

        // Hydrate local cache
        // Saved through the one path that also backs it up (this
        // backfills profile_json for rows written by older versions).
        final savedProfile = await ProfileService.instance.save(mergedProfile);
        if (!_stillOwns(uid, epoch)) return;
        await PersistenceService.setOnboardingDone();
        if (!_stillOwns(uid, epoch)) return;
        currentUserProfile = savedProfile;
        // Seed eating pattern scalars from the declared style.
        if (resolvedAnchor != null) {
          EatingPatternService.instance.seedFromPortionAnchor(resolvedAnchor);
          await EatingPatternService.instance.save();
          if (!_stillOwns(uid, epoch)) return;
        }

        InsightsReportService.instance.maybeRecompute(currentUserProfile!).ignore();

        if (mounted) setState(() => _hasProfile = true);
        return;
      }
    } catch (e) {
      debugPrint('[_LoggedInGate] Network/Fetch Exception triggering locally-cached execution failover: $e');
      // 2. Network offline fallback
      if (!_stillOwns(uid, epoch)) return;
      if (PersistenceService.isOnboardingDone && currentUserProfile != null) {
        debugPrint('[_LoggedInGate] Falling back to local cache. Session is live, just offline.');
        final userId = Supabase.instance.client.auth.currentUser?.id;
        NutritionHydrationGuard.instance.markComplete(userId);
        
        InsightsReportService.instance.maybeRecompute(currentUserProfile!).ignore();

        if (mounted) setState(() => _hasProfile = true);
        return;
      }
      
      // If we reach here, we have a network/internal error AND no local profile to fall back to.
      if (mounted) {
        setState(() {
          _fatalError = _connectionError;
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
    // Same routing as before; the result is cross-faded instead of hard-cut.
    final Widget child;
    if (_fatalError != null) {
      child = _GateError(
        key: const ValueKey('gate-error'),
        message: _fatalError!,
        onRetry: () {
          setState(() {
            _fatalError = null;
            _hasProfile = null;
          });
          _checkProfile();
        },
        onSignOut: () => AuthService().signOut(),
      );
    } else if (_hasProfile == null || _consented == null) {
      child = const _BrandLoader(
        key: ValueKey('gate-loading'),
        semanticLabel: 'Loading your profile',
        messages: ['Getting your plan ready…', 'Pulling your history…'],
      );
    } else if (_hasProfile!) {
      final uid = _userId;
      child = (_consented == true || uid == null)
          ? const AppShell(key: ValueKey('gate-app'))
          // Existing user who hasn't agreed to the current policy: once,
          // before the app. Declining keeps them here.
          : ConsentScreen(
              key: const ValueKey('gate-consent'),
              userId: uid,
              onConsented: _onConsented,
            );
    } else {
      child = OnboardingScreen(
        key: const ValueKey('gate-onboarding'),
        onFinished: _onOnboardingFinished,
        showPrologue: true,
        // New users agree on onboarding's first step.
        onConsent: _consented == true ? null : _recordOnboardingConsent,
      );
    }
    return _GateSwitcher(child: child);
  }
}