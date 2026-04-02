/// Centralized personal mess calibration constants.
///
/// These override standard nutrition-database serving references inside
/// every AI prompt.  Future: load/save via UserProfile settings.
///
/// CRITICAL MILK CORRECTION:
///   Indian TONED milk (Amul Toned, most packet milks) = 58 kcal/100ml.
///   Do NOT use 46 kcal/100ml — that is DOUBLE-TONED (low-fat) milk.
///   Default always = toned milk unless user explicitly says double-toned.
///
/// CONSUMED PORTION PRINCIPLE (hostel/mess context):
///   Estimate WHAT WAS EATEN, not what was served.
///   Dal/sabzi alongside roti/rice = only enough to finish carbs, rarely a full bowl.
///   Paneer = pieces fully eaten, but ~30–40% of gravy/oil typically left on plate.
class MessCalibration {
  MessCalibration._();

  // ── Volume / weight references ─────────────────────────────────────────────
  static const int milkGlassMl          = 200;  // user's hostel glass
  static const int milkKcalPer100ml     = 58;   // TONED milk (NOT double-toned 46)
  static const int milkProteinPer100ml  = 3;    // ~3.0–3.4 g/100ml for toned

  // Rice: calibrated to 130 kcal per ladle (user-stated measurement)
  static const int riceLadleKcal        = 130;  // ≈85–90g cooked rice per ladle
  static const int riceLadleProtein     = 3;    // ~2.5–3g protein per ladle
  static const int riceLadleGMin        = 85;   // cooked g per ladle (lower)
  static const int riceLadleGMax        = 95;   // cooked g per ladle (upper)

  // Dal
  static const int dalLadleMlMin        = 60;
  static const int dalLadleMlMax        = 85;
  static const int dalFullServingMlMin  = 120;
  static const int dalFullServingMlMax  = 170;

  // Sabzi
  static const int sabziFullGMin        = 80;
  static const int sabziFullGMax        = 130;

  // Paneer — mess eating defaults
  //   Mess serving: ~90–150g dish (40–65g actual paneer + gravy)
  //   User eats paneer pieces fully, leaves ~35% gravy/oil on plate
  static const int paneerMessServingKcalMin = 220;
  static const int paneerMessServingKcalMax = 300;
  static const int paneerServingGMin    = 90;
  static const int paneerServingGMax    = 150;
  static const int paneerCubeGMin       = 18;
  static const int paneerCubeGMax       = 28;

  // Roti
  static const int messRotiKcalMin      = 95;
  static const int messRotiKcalMax      = 110;

  // Thali compartment sizes (IMPORTANT: N compartments ≠ N full servings)
  static const int smallCompartmentGMin = 60;   // small/round compartment
  static const int smallCompartmentGMax = 80;
  static const int largeCompartmentGMin = 120;  // large/rectangular compartment
  static const int largeCompartmentGMax = 155;

  // ── Prompt context string ─────────────────────────────────────────────────

  /// Injected into every AI nutrition request.
  static String toPromptContext() => '''
PERSONAL MESS CALIBRATION — use these values, not generic references:
- 1 milk glass = $milkGlassMl ml of Indian TONED milk ($milkKcalPer100ml kcal/100ml, NOT 46)
- 1 roti (mess) = $messRotiKcalMin–$messRotiKcalMax kcal, ~3g protein
- 1 rice ladle  = $riceLadleGMin–$riceLadleGMax g cooked = ~$riceLadleKcal kcal, ~$riceLadleProtein g protein
  (1.5 ladles = 195 kcal | 2 ladles = 260 kcal)
- 1 full dal serving = $dalFullServingMlMin–$dalFullServingMlMax ml
- 1 sabzi serving = $sabziFullGMin–$sabziFullGMax g (CONSUMED, not served)
- Mess paneer serving = $paneerServingGMin–$paneerServingGMax g dish, $paneerMessServingKcalMin–$paneerMessServingKcalMax kcal consumed

MESS COMPARTMENT SIZES (critical for thali/tray meals):
- Small / round / circular compartment  = $smallCompartmentGMin–$smallCompartmentGMax g per compartment
- Large / rectangular compartment       = $largeCompartmentGMin–$largeCompartmentGMax g per compartment
- WHEN "N compartments" has NO size qualifier → default to SMALL compartments
  → 3 small compartments paneer = ~180–240 g dish total consumed (not 3 full bowls)

CONSUMED PORTION RULES (hostel/mess context — estimate EATEN, not SERVED):
- Dal/sabzi alongside roti/rice: estimate what was used to finish carbs (~60–80% of one katori)
- Rajma/chole alongside roti/rice: ~70–90g cooked (one ladle-sized portion, ~160–200 kcal)
- Dal alongside roti: ~70–85 ml per 2 roti (~100–130 kcal from dal portion)
- Paneer: eat ALL paneer pieces, leave ~35% of gravy/oil → net ~220–290 kcal per mess serving
- Full thali (roti + rice + curry): estimate TOTAL consumed, not all compartments at full value''';
}
