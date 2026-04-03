import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'screens/onboarding_screen.dart';
import 'screens/app_shell.dart';
import 'services/meal_memory.dart';
import 'services/personal_nutrition_memory.dart';
import 'services/persistence_service.dart';
import 'services/workout_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Health().configure();
  await MealMemory.instance.init();
  await PersonalNutritionMemory.instance.init();
  await PersistenceService.load();   // restores profile + day logs
  await WorkoutService.instance.init(); // restores split + sessions

  const apiKey = String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: '');
  if (apiKey.isEmpty) {
    debugPrint('[main] ⚠️  OPENROUTER_API_KEY is EMPTY — AI will fall back locally');
  } else {
    final preview = apiKey.length <= 8
        ? 'provided'
        : '${apiKey.substring(0, 4)}…${apiKey.substring(apiKey.length - 4)}';
    debugPrint('[main] ✅ OPENROUTER_API_KEY detected ($preview) — AI enabled');
  }

  runApp(const KynetixApp());
}

class KynetixApp extends StatelessWidget {
  const KynetixApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Route: skip onboarding if profile already exists and flag is set.
    final home = PersistenceService.isOnboardingDone && currentUserProfile != null
        ? const AppShell()
        : const OnboardingScreen();

    return MaterialApp(
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
      home: home,
    );
  }
}
