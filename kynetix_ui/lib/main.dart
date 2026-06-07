import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:health/health.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_theme.dart';
import 'screens/auth_gate.dart';
import 'screens/reset_password_screen.dart';
import 'services/meal_memory.dart';
import 'services/personal_nutrition_memory.dart';
import 'services/persistence_service.dart';
import 'services/workout_service.dart';
import 'services/insights_report_service.dart';
import 'models/day_log.dart';
import 'config/supabase_secrets.dart';

Future<void> main() async {
  final stopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  // Immersive dark status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor:        KColor.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final setupBindingTime = stopwatch.elapsedMilliseconds;
  debugPrint('[Startup Profile] Flutter binding setup took: ${setupBindingTime} ms');

  // Initialize Supabase Auth & Backend Connection
  await Supabase.initialize(
    url: SupabaseSecrets.url,
    anonKey: SupabaseSecrets.anonKey,
  );

  final supabaseInitTime = stopwatch.elapsedMilliseconds - setupBindingTime;
  debugPrint('[Startup Profile] Supabase client initialization took: ${supabaseInitTime} ms');

  final startupSession = Supabase.instance.client.auth.currentSession;
  debugPrint('[main] startup session: ${startupSession != null ? "VALID (user: ${startupSession.user.email ?? startupSession.user.id})" : "NULL — user must sign in"}');

  final serviceStart = stopwatch.elapsedMilliseconds;
  await Future.wait([
    Health().configure(),
    MealMemory.instance.init(),
    PersonalNutritionMemory.instance.init(),
    PersistenceService.load(),
    WorkoutService.instance.init(),
  ]);

  final servicesTime = stopwatch.elapsedMilliseconds - serviceStart;
  debugPrint('[Startup Profile] Concurrently loaded independent services (Health, Memory, Local cache, Workouts) in: ${servicesTime} ms');
  debugPrint('[Startup Profile] Total main initialization took: ${stopwatch.elapsedMilliseconds} ms');



  runApp(const KynetixApp());
}

class KynetixApp extends StatefulWidget {
  const KynetixApp({super.key});

  @override
  State<KynetixApp> createState() => _KynetixAppState();
}

class _KynetixAppState extends State<KynetixApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Kynetix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: KColor.greenDark,
          brightness: Brightness.dark,
          surface: KColor.surface,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: KColor.bg,
        // Consistent slide-up transitions on all MaterialPageRoutes
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _KSlideUpTransitionBuilder(),
            TargetPlatform.iOS:     CupertinoPageTransitionsBuilder(),
          },
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: KColor.green, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: KColor.danger, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: KColor.danger, width: 1.5),
          ),
          hintStyle: const TextStyle(color: KColor.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: KColor.greenDark,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3,
            ),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ─── Slide-up + fade transition ───────────────────────────────────────────────

class _KSlideUpTransitionBuilder extends PageTransitionsBuilder {
  const _KSlideUpTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route, BuildContext context,
    Animation<double> animation, Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: const Interval(0.0, 0.7)),
      child: SlideTransition(position: slide, child: child),
    );
  }
}
