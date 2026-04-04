import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_gate.dart';
import 'screens/reset_password_screen.dart';
import 'services/meal_memory.dart';
import 'services/personal_nutrition_memory.dart';
import 'services/persistence_service.dart';
import 'services/workout_service.dart';
import 'config/secrets.dart';
import 'config/supabase_secrets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Auth & Backend Connection
  await Supabase.initialize(
    url: SupabaseSecrets.url,
    anonKey: SupabaseSecrets.anonKey,
  );

  await Health().configure();
  await MealMemory.instance.init();
  await PersonalNutritionMemory.instance.init();
  
  // Local-first load
  await PersistenceService.load();   
  await WorkoutService.instance.init(); 

  const apiKey = AppSecrets.openRouterApiKey;
  if (apiKey.isEmpty || apiKey == 'YOUR_OPENROUTER_API_KEY_HERE') {
    debugPrint('[main] ⚠️  OPENROUTER_API_KEY is EMPTY — AI will fall back locally');
  } else {
    final preview = apiKey.length <= 8
        ? 'provided'
        : '${apiKey.substring(0, 4)}…${apiKey.substring(apiKey.length - 4)}';
    debugPrint('[main] ✅ OPENROUTER_API_KEY detected ($preview) — AI enabled');
  }

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
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E2C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF52B788), width: 2),
          ),
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D6A4F),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      home: AuthGate(),
    );
  }
}
