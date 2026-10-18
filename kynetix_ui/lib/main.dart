import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_theme.dart';
import 'ui/k_theme_reveal.dart';
import 'screens/auth_gate.dart';
import 'screens/reset_password_screen.dart';
import 'services/exercise_library_service.dart';
import 'config/supabase_secrets.dart';
import 'services/health_service.dart';
import 'services/persistence_service.dart';
import 'services/global_food_service.dart';
import 'services/error_reporter.dart';

Future<void> main() async {
  final stopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds: silence the app's ~400 debug log lines. They cost real
  // time in hot paths, and may contain personal data.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};

  // Edge-to-edge: content runs under the status and gesture bars. Bar icon
  // brightness follows the active palette (set by KThemeScope).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Bundled font licence (SIL OFL 1.1) — listed on the app's licence page.
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/inter/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter', 'Inter Tight'], ofl);
  });

  // Only what the first frame truly needs blocks runApp:
  //  • the theme preference (System / Light / Dark) so there is no flash, and
  //  • Supabase, because AuthGate routes on its restored session.
  // Both run in parallel.
  final themeLoad = KThemeController.instance.load();
  await Supabase.initialize(
    url: SupabaseSecrets.url,
    anonKey: SupabaseSecrets.anonKey,
  );
  await themeLoad;
  debugPrint('[Startup Profile] Theme + Supabase ready in ${stopwatch.elapsedMilliseconds} ms');

  // Crash/error reporting (privacy-scrubbed, in-house client_errors table).
  ErrorReporter.instance.install();

  // Debug-only dev auto-login: AuthGate recognises it by the cached owner id.
  if (kDebugMode && Supabase.instance.client.auth.currentSession == null) {
    final prefs = await SharedPreferences.getInstance();
    final devUserId = prefs.getString('dev_auto_login_user_id');
    if (devUserId != null && devUserId.isNotEmpty) {
      debugPrint('[main] 🛠️ Restoring debug dev session ($devUserId).');
      await PersistenceService.setCachedOwnerId(devUserId);
    }
  }

  // User data is NOT loaded here: the signed-in gate shows the branded loader
  // and runs UserSessionCoordinator.initializeForUser itself, so a new user
  // still onboards and nobody ever sees another account's (or stale) data.
  runApp(const KynetixApp());
  debugPrint('[Startup Profile] runApp at ${stopwatch.elapsedMilliseconds} ms');

  _warmUpGlobalServices(stopwatch);
}

/// User-independent services that no first screen needs synchronously. They
/// start once the first frame is on screen and run in parallel; each is
/// memoised, so a screen that needs one earlier simply awaits the same load.
void _warmUpGlobalServices(Stopwatch stopwatch) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final start = stopwatch.elapsedMilliseconds;
    Future.wait<void>([
      GlobalFoodService.instance.init(),
      ExerciseLibraryService.instance.initialize(),
      HealthService.ensureConfigured(),
    ]).then((_) {
      debugPrint('[Startup Profile] Global services warmed in '
          '${stopwatch.elapsedMilliseconds - start} ms (after first frame)');
    }, onError: (Object e) {
      debugPrint('[Startup Profile] Global service warm-up failed (non-fatal): $e');
    });
  });
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
          kRiseRoute(builder: (_) => const ResetPasswordScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return KThemeScope(
      builder: (context, palette) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Kynetix',
        debugShowCheckedModeBanner: false,
        theme: buildKynetixTheme(palette),
        themeAnimationDuration: Duration.zero,
        // Light / dark flips are revealed as a circle from the last touch.
        builder: (context, child) => KThemeReveal(child: child ?? const SizedBox.shrink()),
        home: const AuthGate(),
      ),
    );
  }
}

/// The app-wide Material theme, derived from the KColor / KText tokens so every
/// stock widget (sheets, dialogs, snackbars, switches, inputs…) already looks
/// like Kynetix before a screen styles anything. Primary actions are monochrome
/// ink; colour is kept for meaning (calories, protein, training, errors).
ThemeData buildKynetixTheme([KPalette? palette]) {
  final p = palette ?? KColor.palette;
  final dark = p.isDark;
  final hair = p.fg.withValues(alpha: dark ? 0.08 : 0.09);

  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.ink,
    onPrimary: p.onInk,
    primaryContainer: Color.alphaBlend(p.green.withValues(alpha: 0.18), p.card),
    onPrimaryContainer: p.textPrimary,
    secondary: p.green,
    onSecondary: p.onInk,
    secondaryContainer: Color.alphaBlend(p.ember.withValues(alpha: 0.14), p.card),
    onSecondaryContainer: p.textPrimary,
    tertiary: p.ember,
    onTertiary: p.onAccent,
    error: p.danger,
    onError: p.onAccent,
    surface: p.surface,
    onSurface: p.textPrimary,
    onSurfaceVariant: p.textSecondary,
    surfaceContainerLowest: p.bg,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.cardHigh,
    surfaceContainerHighest: p.border,
    outline: p.border,
    outlineVariant: p.divider,
    shadow: p.shadow,
    scrim: Colors.black,
    inverseSurface: p.textPrimary,
    onInverseSurface: p.bg,
    inversePrimary: p.onInk,
  );

  final base = (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
        fontFamily: KText.family,
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      );
  TextStyle? tight(TextStyle? s, double ls) =>
      s?.copyWith(fontWeight: FontWeight.w700, letterSpacing: ls);
  final textTheme = base.copyWith(
    displayLarge: tight(base.displayLarge, -2),
    displayMedium: tight(base.displayMedium, -1.6),
    displaySmall: tight(base.displaySmall, -1.2),
    headlineLarge: tight(base.headlineLarge, -1),
    headlineMedium: tight(base.headlineMedium, -0.8),
    headlineSmall: tight(base.headlineSmall, -0.6),
  );

  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: KRadius.md,
        borderSide: BorderSide(color: c, width: w),
      );
  const buttonText = TextStyle(
    fontFamily: KText.family,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    fontFamily: KText.family,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.surface,
    // InkRipple, not InkSparkle: no fragment shader to load and compile on
    // the first tap (a one-off hitch on some devices), and a calmer ripple.
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: kPageTransitions,
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: p.textPrimary,
      titleTextStyle: KText.h2,
      // A transparent app bar can't infer the status-bar icon colour (it
      // reads as dark and picks white icons, which then stick on light
      // screens), so say it per theme.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.lg,
        side: BorderSide(color: hair),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        side: BorderSide(color: hair),
      ),
      modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.32),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.xl,
        side: BorderSide(color: hair),
      ),
      titleTextStyle: KText.h2,
      contentTextStyle: KText.body.copyWith(color: p.textSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: KText.bodyMedium.copyWith(fontSize: 13.5, color: p.onInk),
      // Ember on ink fails contrast in both themes, so the action is base
      // colour and set apart by its weight and position.
      actionTextColor: p.onInk,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      shape: const RoundedRectangleBorder(borderRadius: KRadius.md),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: KRadius.sm),
      textStyle: KText.caption.copyWith(color: p.onInk),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.textPrimary,
      linearTrackColor: hair,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onInk : p.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.ink : p.cardHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : p.border,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.textPrimary,
      inactiveTrackColor: hair,
      thumbColor: p.textPrimary,
      overlayColor: p.textPrimary.withValues(alpha: 0.1),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.ink,
      secondarySelectedColor: p.ink,
      side: BorderSide(color: hair),
      shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
      labelStyle: KText.caption.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600),
      secondaryLabelStyle: KText.caption.copyWith(color: p.onInk, fontWeight: FontWeight.w600),
      checkmarkColor: p.onInk,
    ),
    listTileTheme: ListTileThemeData(iconColor: p.textSecondary),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.ink,
      foregroundColor: p.onInk,
      elevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.textPrimary,
      selectionColor: p.green.withValues(alpha: 0.3),
      selectionHandleColor: p.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      border: field(Colors.transparent),
      enabledBorder: field(dark ? hair : p.border),
      focusedBorder: field(p.textPrimary, 1.4),
      errorBorder: field(p.danger),
      focusedErrorBorder: field(p.danger, 1.6),
      hintStyle: TextStyle(color: p.textMuted),
      labelStyle: TextStyle(color: p.textSecondary),
      floatingLabelStyle: TextStyle(color: p.textPrimary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.onInk,
        disabledBackgroundColor: p.cardHigh,
        disabledForegroundColor: p.textDisabled,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
        textStyle: buttonText,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.onInk,
        minimumSize: const Size(48, 52),
        shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        minimumSize: const Size(48, 52),
        side: BorderSide(color: p.fg.withValues(alpha: dark ? 0.16 : 0.18)),
        shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.textPrimary,
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
        textStyle: buttonText.copyWith(fontSize: 14.5),
      ),
    ),
  );
}
