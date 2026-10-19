import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/nutrition_result.dart';
import '../data/micronutrient_library.dart';
import '../models/day_log.dart';
import '../services/nutrition_pipeline.dart';
import '../services/accompaniment_portion_resolver.dart';
import '../services/profile_service.dart';
import '../data/indian_curry_table.dart';
import '../services/hidden_extras.dart';
import '../services/meal_memory.dart';
import '../services/meal_tombstones.dart';
import '../services/user_nutrition_memory.dart';
import '../services/food_role_classifier.dart';
import '../services/eating_pattern_service.dart';
import '../services/item_parser.dart';
import '../services/persistence_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/saved_meal_service.dart';
import '../services/kyno_context_service.dart';
import '../ui/k_rolling.dart';
import '../widgets/k_progress_line.dart';
import '../widgets/k_success_check.dart';
import 'barcode_scanner_screen.dart';

/// Sentinel returned by AddMealScreen when the user explicitly deletes an entry.
class DeleteSentinel {
  const DeleteSentinel();
}

class AddMealScreen extends StatefulWidget {
  final MealSection section;
  final DateTime    date;
  final MealEntry?  initialEntry;
  /// Pre-filled text from a suggestion tap — also triggers auto-calculate.
  final String?     initialText;
  /// Rows to start from, e.g. a scanned product's "Edit before logging".
  /// Loaded as-is (never re-estimated); saving adds a new entry.
  final NutritionResult? initialResult;

  const AddMealScreen({
    super.key,
    required this.section,
    required this.date,
    this.initialEntry,
    this.initialText,
    this.initialResult,
  });

  static bool hasParsedMealStructureChanged(String oldText, String newText) {
    final oldParsed = ItemParser.parse(oldText);
    final newParsed = ItemParser.parse(newText);
    if (oldParsed.length != newParsed.length) return true;
    for (int i = 0; i < oldParsed.length; i++) {
      if (oldParsed[i].normalizedName != newParsed[i].normalizedName) return true;
      if (oldParsed[i].quantity != newParsed[i].quantity) return true;
      if (oldParsed[i].unit != newParsed[i].unit) return true;
    }
    return false;
  }

  @override
  State<AddMealScreen> createState() => _AddMealScreenState();
}

class _IngredientRow {
  final TextEditingController textCtrl;
  final FocusNode focusNode;
  ParsedFoodItem parsed;
  final TextEditingController calCtrl;
  final TextEditingController proCtrl;
  final TextEditingController carbCtrl;
  final TextEditingController fatCtrl;
  final TextEditingController fibCtrl;
  FoodRole role;
  OverrideSource source;
  bool isSaved;
  bool isEstimating = false;
  double originalCalories;
  String lastParsedText;

  /// Micronutrients the row's food carried when estimated or scanned, at
  /// [microsKcal]. Scaled to the saved calories; null means not tracked.
  Micronutrients? micros;
  double microsKcal = 0;

  /// A dal / sabzi / chole whose amount was sized by the roti and rice in
  /// the meal (not typed). It follows the carbs when their count changes.
  bool carbSized = false;

  _IngredientRow({
    required String rawText,
    required this.parsed,
    required double cal,
    required double pro,
    required double carb,
    required double fat,
    required double fib,
    required this.role,
    required this.source,
    required this.isSaved,
    required this.originalCalories,
  }) : textCtrl = TextEditingController(text: rawText),
       focusNode = FocusNode(),
       calCtrl = TextEditingController(text: cal.toStringAsFixed(0)),
       proCtrl = TextEditingController(text: pro.toStringAsFixed(1)),
       carbCtrl = TextEditingController(text: carb.toStringAsFixed(1)),
       fatCtrl = TextEditingController(text: fat.toStringAsFixed(1)),
       fibCtrl = TextEditingController(text: fib.toStringAsFixed(1)),
       lastParsedText = rawText;
}

class _AddMealScreenState extends State<AddMealScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();

  NutritionResult? _result;
  bool _loading = false;
  String? _error;

  /// Kyno "thinking" pulse on the composer. Runs ONLY while estimating and
  /// only when ambient motion is allowed — see [_syncPulse].
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

  bool _composerFocused = false;
  bool _saving = false;

  /// Presentation only: the estimate has landed and the progress line is
  /// closing its last stretch before the result cross-fades in. Every piece
  /// of logic reads [_loading] / [_result], never this.
  bool _finishingEstimate = false;

  /// Presentation only: the meal is saved and the button is showing its
  /// drawn check; the screen closes when that moment ends.
  bool _logged = false;
  Completer<void>? _loggedMoment;

  final List<_IngredientRow> _rows = [];
  bool _rememberEdits = true;
  double _totalCal = 0;
  double _totalPro = 0;
  double _totalCarb = 0;
  double _totalFat = 0;
  double _totalFib = 0;
  String? _validationWarning;

  /// Bumped when only the live totals / warning changed (macro typing), so
  /// just the widgets that show them rebuild instead of the whole screen.
  final ValueNotifier<int> _totalsTick = ValueNotifier<int>(0);

  List<SavedMealMatch> _savedMealMatches = const [];
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    if (widget.initialEntry != null) {
      _controller.text = widget.initialEntry!.finalSavedInput;
      _result = widget.initialEntry!.result;
      _initRowsFromResult(_result!);
    } else if (widget.initialResult != null) {
      _controller.text = widget.initialResult!.canonicalMeal;
      _result = widget.initialResult;
      _initRowsFromResult(_result!);
    } else if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    _focusNode.addListener(_onComposerFocusChanged);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: KMotion.slow,
    );
    _pulse = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: KMotion.emphasizedCurve),
    );
    // Auto-calculate when opened with suggestion text.
    if (widget.initialText != null && widget.initialEntry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _calculate());
    }
  }

  void _onComposerFocusChanged() {
    if (!mounted) return;
    final focused = _focusNode.hasFocus;
    if (focused != _composerFocused) setState(() => _composerFocused = focused);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion can flip at runtime; re-resolve the pulse.
    _syncPulse();
  }

  /// Starts the Kyno pulse only while estimating and only when ambient motion
  /// is allowed; otherwise parks it (static glow while estimating, hidden
  /// otherwise). Never leaves a repeat() running after estimation ends.
  void _syncPulse() {
    if (!mounted) return;
    // The wait is shown by the calm progress line under the button, so the
    // composer border just holds still while estimating: no pulsing loop.
    if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
    _pulseCtrl.value = _loading ? 1.0 : 0.0;
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    if (text.length < 2) {
      _searchDebounceTimer?.cancel();
      if (_savedMealMatches.isNotEmpty) {
        setState(() {
          _savedMealMatches = const [];
        });
      }
      return;
    }

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final currentText = _controller.text.trim();
      if (currentText.length >= 2) {
        final matches = SavedMealService.instance.search(currentText, limit: 3);
        if (!_areMatchListsEqual(_savedMealMatches, matches)) {
          setState(() {
            _savedMealMatches = matches;
          });
        }
      } else if (_savedMealMatches.isNotEmpty) {
        setState(() {
          _savedMealMatches = const [];
        });
      }
    });
  }

  bool _areMatchListsEqual(List<SavedMealMatch> a, List<SavedMealMatch> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title || a[i].matchScore != b[i].matchScore) return false;
    }
    return true;
  }

  void _useSavedMeal(SavedMealMatch match) {
    KHaptics.commit();
    setState(() {
      _controller.text = match.rawInput;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _savedMealMatches = const [];
      _result = match.result;
      _initRowsFromResult(match.result);
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.removeListener(_onComposerFocusChanged);
    _focusNode.dispose();
    _pulseCtrl.stop();
    _pulseCtrl.dispose();
    _clearRows();
    _totalsTick.dispose();
    super.dispose();
  }

  void _clearRows() {
    for (final row in _rows) {
      row.calCtrl.removeListener(_onMacroFieldChanged);
      row.proCtrl.removeListener(_onMacroFieldChanged);
      row.carbCtrl.removeListener(_onMacroFieldChanged);
      row.fatCtrl.removeListener(_onMacroFieldChanged);
      row.fibCtrl.removeListener(_onMacroFieldChanged);

      row.calCtrl.dispose();
      row.proCtrl.dispose();
      row.carbCtrl.dispose();
      row.fatCtrl.dispose();
      row.fibCtrl.dispose();
      row.textCtrl.dispose();
      row.focusNode.dispose();
    }
    _rows.clear();
  }

  void _initRowsFromResult(NutritionResult result) {
    _clearRows();
    final effectiveItems = result.items.isNotEmpty
        ? result.items
        : [
            NutritionItem(
              name: result.canonicalMeal.isNotEmpty
                  ? result.canonicalMeal
                  : (_controller.text.trim().isNotEmpty ? _controller.text.trim() : 'Meal'),
              quantity: 1.0,
              unit: 'serving',
              estimated: false,
              mode: EstimationMode.directQuantity,
              calories: result.calories,
              protein: result.protein,
              carbohydrates: result.carbohydrates,
              fat: result.fat,
              fiber: result.fiber,
            ),
          ];

    for (final item in effectiveItems) {
      final rawText = _constructItemString(ParsedFoodItem(
        rawChunk: item.name,
        normalizedName: item.name,
        quantity: item.quantity,
        unit: item.unit,
      ));
      final parsedItem = ParsedFoodItem(
        rawChunk: item.name,
        normalizedName: item.name,
        quantity: item.quantity,
        unit: item.unit,
      );

      final cal = (item.calories.min + item.calories.max) / 2;
      final pro = (item.protein.min + item.protein.max) / 2;
      final carb = item.carbohydrates != null ? (item.carbohydrates!.min + item.carbohydrates!.max) / 2 : 0.0;
      final fat = item.fat != null ? (item.fat!.min + item.fat!.max) / 2 : 0.0;
      final fib = item.fiber != null ? (item.fiber!.min + item.fiber!.max) / 2 : 0.0;

      final role = FoodRoleClassifier.classify(item.name);
      final (stored, source) = UserNutritionMemory.instance.lookupWithSource(item.name);

      final row = _IngredientRow(
        rawText: rawText,
        parsed: parsedItem,
        cal: cal,
        pro: pro,
        carb: carb,
        fat: fat,
        fib: fib,
        role: role,
        source: source,
        isSaved: stored != null,
        originalCalories: cal,
      )
        ..micros = item.micros
        ..microsKcal = cal
        ..carbSized = item.unit == 'g' &&
            item.mode == EstimationMode.contextualIntake &&
            IndianCurryTable.match(item.name) != null;

      row.calCtrl.addListener(_onMacroFieldChanged);
      row.proCtrl.addListener(_onMacroFieldChanged);
      row.carbCtrl.addListener(_onMacroFieldChanged);
      row.fatCtrl.addListener(_onMacroFieldChanged);
      row.fibCtrl.addListener(_onMacroFieldChanged);

      row.focusNode.addListener(() {
        if (!row.focusNode.hasFocus) {
          _onFocusLost(row);
        }
      });

      _rows.add(row);
    }
    _updateTotalsAndValidate();
    debugPrint('''
=================== REAL APP RUNTIME AUDIT TRACE (EDIT SCREEN INITIALIZED) ===================
  7. Detail sheet values          : Calories=${result.calories.mid}, Pro=${result.protein.mid}, Carbs=${result.carbohydrates?.mid}, Fat=${result.fat?.mid}, Fiber=${result.fiber?.mid}, Score=${result.mealQualityScore}
  8. Edit screen values before Calc: Calories=$_totalCal, Pro=$_totalPro, Carbs=$_totalCarb, Fat=$_totalFat, Fiber=$_totalFib
=============================================================================================
''');
  }

  String _constructItemString(ParsedFoodItem parsed) {
    if (parsed.quantity == 1.0 && parsed.unit == 'serving') return parsed.normalizedName;
    if (parsed.quantity == 1.0) return '${parsed.unit} ${parsed.normalizedName}'.trim();
    String formattedQty = parsed.quantity == parsed.quantity.toInt() ? '${parsed.quantity.round()}' : '${parsed.quantity}';
    return '$formattedQty ${parsed.unit} ${parsed.normalizedName}'.trim();
  }

  Future<void> _onFocusLost(_IngredientRow row) async {
    final text = row.textCtrl.text.trim();
    if (text.isEmpty || text == row.lastParsedText) return;
    row.lastParsedText = text;

    final parsedList = ItemParser.parse(text);
    if (parsedList.isEmpty) return;
    final p = parsedList.first;

    if (p.normalizedName != row.parsed.normalizedName) {
      setState(() => row.isEstimating = true);
      try {
        final result = await NutritionPipeline.instance.estimateMeal(text);
        // The screen may have closed, or the row been removed (its
        // controllers disposed), while the estimate was in flight.
        if (!mounted || !_rows.contains(row)) return;
        final cal = result.calories.mid;
        final pro = result.protein.mid;
        final carb = result.carbohydrates?.mid ?? 0.0;
        final fat = result.fat?.mid ?? 0.0;
        final fib = result.fiber?.mid ?? 0.0;

        row.calCtrl.text = cal.toStringAsFixed(0);
        row.proCtrl.text = pro.toStringAsFixed(1);
        row.carbCtrl.text = carb.toStringAsFixed(1);
        row.fatCtrl.text = fat.toStringAsFixed(1);
        row.fibCtrl.text = fib.toStringAsFixed(1);

        row.role = FoodRoleClassifier.classify(p.normalizedName);
        final (stored, source) = UserNutritionMemory.instance.lookupWithSource(p.normalizedName);
        row.source = source;
        row.isSaved = stored != null;
        row.parsed = p;
        row.originalCalories = cal;
        row.micros = result.items.isNotEmpty && result.items.every((i) => i.micros != null)
            ? result.items.fold<Micronutrients>(Micronutrients.empty, (a, i) => a + i.micros!)
            : null;
        row.microsKcal = cal;
      } catch (_) {
      } finally {
        if (mounted && _rows.contains(row)) {
          setState(() => row.isEstimating = false);
          _updateTotalsAndValidate();
        }
      }
    } else if (p.quantity != row.parsed.quantity && row.parsed.quantity > 0) {
      final scale = p.quantity / row.parsed.quantity;
      final oldCal = double.tryParse(row.calCtrl.text) ?? 0.0;
      final oldPro = double.tryParse(row.proCtrl.text) ?? 0.0;
      final oldCarb = double.tryParse(row.carbCtrl.text) ?? 0.0;
      final oldFat = double.tryParse(row.fatCtrl.text) ?? 0.0;
      final oldFib = double.tryParse(row.fibCtrl.text) ?? 0.0;

      row.calCtrl.text = (oldCal * scale).toStringAsFixed(0);
      row.proCtrl.text = (oldPro * scale).toStringAsFixed(1);
      row.carbCtrl.text = (oldCarb * scale).toStringAsFixed(1);
      row.fatCtrl.text = (oldFat * scale).toStringAsFixed(1);
      row.fibCtrl.text = (oldFib * scale).toStringAsFixed(1);

      row.originalCalories = row.originalCalories * scale;
      row.micros = row.micros?.scaled(scale);
      row.microsKcal = row.microsKcal * scale;
      row.parsed = p;
      if (row.carbSized) {
        // The person set this curry's amount themselves now.
        row.carbSized = false;
      } else {
        _resizeCarbSizedCurries();
      }
      _updateTotalsAndValidate();
    }
  }

  /// After a roti or rice count changes, the dal / sabzi / chole that was
  /// sized by the carbs is sized again: 3 roti take more chole than 2.
  /// Rows whose macros were edited by hand, or that hold the person's own
  /// saved values, are left alone.
  void _resizeCarbSizedCurries() {
    bool untouched(_IngredientRow r) =>
        ((double.tryParse(r.calCtrl.text) ?? 0) - r.originalCalories).abs() < 1;
    final follow = {
      for (final r in _rows)
        if (r.carbSized && !r.isSaved && untouched(r)) r,
    };
    if (follow.isEmpty) return;

    NutrientRange at(TextEditingController c) {
      final v = double.tryParse(c.text) ?? 0;
      return NutrientRange(min: v, max: v);
    }

    final items = [
      for (final r in _rows)
        NutritionItem(
          name: r.parsed.normalizedName,
          quantity: follow.contains(r) ? 1 : r.parsed.quantity,
          unit: follow.contains(r) ? 'serving' : r.parsed.unit,
          estimated: true,
          mode: EstimationMode.contextualIntake,
          calories: at(r.calCtrl),
          protein: at(r.proCtrl),
        ),
    ];
    final sized = AccompanimentPortionResolver.resolve(
      items,
      anchor: ProfileService.instance.activePortionAnchor,
    );
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (!follow.contains(row)) continue;
      final it = sized[i];
      final cal = it.calories.mid;
      row.parsed = ParsedFoodItem(
        rawChunk: row.parsed.rawChunk,
        normalizedName: row.parsed.normalizedName,
        quantity: it.quantity,
        unit: it.unit,
      );
      final text = _constructItemString(row.parsed);
      row.textCtrl.text = text;
      row.lastParsedText = text;
      row.calCtrl.text = cal.toStringAsFixed(0);
      row.proCtrl.text = it.protein.mid.toStringAsFixed(1);
      row.carbCtrl.text = (it.carbohydrates?.mid ?? 0).toStringAsFixed(1);
      row.fatCtrl.text = (it.fat?.mid ?? 0).toStringAsFixed(1);
      row.fibCtrl.text = (it.fiber?.mid ?? 0).toStringAsFixed(1);
      if (row.microsKcal > 0) row.micros = row.micros?.scaled(cal / row.microsKcal);
      row.microsKcal = cal;
      row.originalCalories = cal;
    }
  }

  /// Macro field listener. Controllers also notify on cursor / focus moves,
  /// so this only rebuilds when a total or the warning actually changed.
  void _onMacroFieldChanged() => _updateTotalsAndValidate(skipIfUnchanged: true);

  void _updateTotalsAndValidate({bool skipIfUnchanged = false}) {
    double calSum = 0;
    double proSum = 0;
    double carbSum = 0;
    double fatSum = 0;
    double fibSum = 0;

    for (int i = 0; i < _rows.length; i++) {
      calSum  += double.tryParse(_rows[i].calCtrl.text) ?? 0;
      proSum  += double.tryParse(_rows[i].proCtrl.text) ?? 0;
      carbSum += double.tryParse(_rows[i].carbCtrl.text) ?? 0;
      fatSum  += double.tryParse(_rows[i].fatCtrl.text) ?? 0;
      fibSum  += double.tryParse(_rows[i].fibCtrl.text) ?? 0;
    }

    final impliedCalories = proSum * 4 + carbSum * 4 + fatSum * 9;
    final String? warning;
    if (calSum > 0 && impliedCalories > 0 &&
        ((impliedCalories - calSum) / calSum).abs() > 0.15) {
      warning = "The macros don't quite add up to the calories. Worth a quick look.";
    } else {
      warning = null;
    }
    if (skipIfUnchanged &&
        calSum == _totalCal &&
        proSum == _totalPro &&
        carbSum == _totalCarb &&
        fatSum == _totalFat &&
        fibSum == _totalFib &&
        warning == _validationWarning) {
      return;
    }

    if (!mounted) return;
    void apply() {
      _totalCal = calSum;
      _totalPro = proSum;
      _totalCarb = carbSum;
      _totalFat = fatSum;
      _totalFib = fibSum;
      _validationWarning = warning;
    }
    if (skipIfUnchanged) {
      // Typing in a macro field: only the totals and warning changed.
      apply();
      _totalsTick.value++;
    } else {
      setState(apply);
    }
  }

  void _resetItemToOriginal(int index) {
    final row = _rows[index];
    row.calCtrl.text = row.originalCalories.toStringAsFixed(0);
    _updateTotalsAndValidate();
  }

  void _addRow() {
    final parsed = ParsedFoodItem(
      rawChunk: '1 serving food',
      normalizedName: 'food',
      quantity: 1.0,
      unit: 'serving',
    );
    final row = _IngredientRow(
      rawText: '1 serving food',
      parsed: parsed,
      cal: 100,
      pro: 5,
      carb: 10,
      fat: 2,
      fib: 0,
      role: FoodRole.completeMeal,
      source: OverrideSource.userCorrected,
      isSaved: false,
      originalCalories: 100,
    );

    row.calCtrl.addListener(_onMacroFieldChanged);
    row.proCtrl.addListener(_onMacroFieldChanged);
    row.carbCtrl.addListener(_onMacroFieldChanged);
    row.fatCtrl.addListener(_onMacroFieldChanged);
    row.fibCtrl.addListener(_onMacroFieldChanged);

    row.focusNode.addListener(() {
      if (!row.focusNode.hasFocus) {
        _onFocusLost(row);
      }
    });

    setState(() {
      _rows.add(row);
    });
    _updateTotalsAndValidate();
  }

  void _deleteRow(int index) {
    final row = _rows[index];
    row.calCtrl.removeListener(_onMacroFieldChanged);
    row.proCtrl.removeListener(_onMacroFieldChanged);
    row.carbCtrl.removeListener(_onMacroFieldChanged);
    row.fatCtrl.removeListener(_onMacroFieldChanged);
    row.fibCtrl.removeListener(_onMacroFieldChanged);

    row.calCtrl.dispose();
    row.proCtrl.dispose();
    row.carbCtrl.dispose();
    row.fatCtrl.dispose();
    row.fibCtrl.dispose();
    row.textCtrl.dispose();
    row.focusNode.dispose();

    setState(() {
      _rows.removeAt(index);
    });
    _updateTotalsAndValidate();
  }

  Future<void> _calculate() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    // Just a number ("3") isn't a meal: say what's missing instead of
    // returning a confident 0 kcal.
    if (!RegExp(r'[A-Za-zऀ-ॿ]').hasMatch(text)) {
      setState(() {
        _result = null;
        _error = 'Add what you ate too, like "3 roti" or "1 katori dal".';
      });
      return;
    }

    _focusNode.unfocus();
    // Haptic for the commit is fired by the tap surface (KButton / keyboard
    // submit), so this method stays silent and fires exactly once per action.
    setState(() { _loading = true; _result = null; _error = null; _finishingEstimate = false; });
    _syncPulse();
    try {
      final result = await NutritionPipeline.instance.estimateMeal(text);
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
          // Let the progress line close out before the result fades in.
          _finishingEstimate = !KMotion.reduced(context);
          _initRowsFromResult(result);
        });
        _syncPulse();
      }
    } catch (e) {
      if (mounted) {
        debugPrint('[AddMeal] estimate failed: $e');
        setState(() {
          _loading = false;
          _error = "Couldn't estimate that just now. Check your connection and try again.";
        });
        _syncPulse();
      }
    }
  }

  /// Scan a packaged product into this meal. The scanner returns the exact
  /// portion (e.g. 40 g) as label figures; they land in the editable rows and
  /// save through the normal path. An empty editor takes the product as the
  /// meal; an existing meal gets it as one more row.
  Future<void> _scanBarcode() async {
    if (_loading || _saving) return;
    _focusNode.unfocus();
    final outcome = await openBarcodeFlow(
      context,
      date: widget.date,
      section: widget.section,
      mode: BarcodeFlowMode.fill,
    );
    if (outcome == null || !mounted) return;
    final scanned = outcome.result;
    final scannedText = scanned.canonicalMeal;

    if (_result == null || _rows.isEmpty) {
      setState(() {
        _finishingEstimate = false;
        _result = scanned;
        _controller.text = scannedText;
        _controller.selection = TextSelection.collapsed(offset: scannedText.length);
        _savedMealMatches = const [];
        _error = null;
        _initRowsFromResult(scanned);
      });
      return;
    }

    final existing = _rows.toList(growable: false);
    final carried = <NutritionItem>[
      for (final row in existing)
        NutritionItem(
          name: row.parsed.normalizedName,
          quantity: row.parsed.quantity,
          unit: row.parsed.unit,
          estimated: false,
          mode: EstimationMode.directQuantity,
          calories: _exact(row.calCtrl.text),
          protein: _exact(row.proCtrl.text),
          carbohydrates: _exact(row.carbCtrl.text),
          fat: _exact(row.fatCtrl.text),
          fiber: _exact(row.fibCtrl.text),
          micros: _microsForRow(row, double.tryParse(row.calCtrl.text) ?? 0),
        ),
      ...scanned.items,
    ];
    final current = _controller.text.trim();
    final text = current.isEmpty ? scannedText : '$current + $scannedText';
    NutrientRange sum(NutrientRange? Function(NutritionItem) f) {
      var v = 0.0;
      for (final i in carried) {
        v += f(i)?.mid ?? 0;
      }
      return NutrientRange(min: v, max: v);
    }

    final merged = NutritionResult(
      canonicalMeal: text,
      items: carried,
      calories: sum((i) => i.calories),
      protein: sum((i) => i.protein),
      carbohydrates: sum((i) => i.carbohydrates),
      fat: sum((i) => i.fat),
      fiber: sum((i) => i.fiber),
      sugar: sum((i) => i.sugar),
      confidence: _result!.confidence,
      warnings: const [],
      source: _result!.source,
      createdAt: _result!.createdAt,
    );
    setState(() {
      _result = merged;
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      _savedMealMatches = const [];
      _initRowsFromResult(_result!);
    });
  }

  /// Adds a forgotten extra (ghee, oil, sugar) as one more row, keeping any
  /// numbers already edited in the rows above.
  void _addExtra(HiddenExtra extra) {
    final base = _result;
    if (base == null) return;
    KHaptics.commit();
    NutrientRange n(double v) => NutrientRange(min: v, max: v);
    final carried = <NutritionItem>[
      for (final row in _rows)
        NutritionItem(
          name: row.parsed.normalizedName,
          quantity: row.parsed.quantity,
          unit: row.parsed.unit,
          estimated: false,
          mode: EstimationMode.directQuantity,
          calories: _exact(row.calCtrl.text),
          protein: _exact(row.proCtrl.text),
          carbohydrates: _exact(row.carbCtrl.text),
          fat: _exact(row.fatCtrl.text),
          fiber: _exact(row.fibCtrl.text),
        ),
      NutritionItem(
        name: extra.label.replaceFirst(RegExp(r'^[\d.]+\s*(tsp|tbsp)\s*'), ''),
        quantity: 1,
        unit: extra.label.contains('tbsp') ? 'tbsp' : 'tsp',
        estimated: false,
        mode: EstimationMode.directQuantity,
        calories: n(extra.kcal),
        protein: n(extra.protein),
        carbohydrates: n(extra.carbs),
        fat: n(extra.fat),
        fiber: n(0),
      ),
    ];
    NutrientRange sum(NutrientRange? Function(NutritionItem) f) {
      var v = 0.0;
      for (final i in carried) {
        v += f(i)?.mid ?? 0;
      }
      return NutrientRange(min: v, max: v);
    }

    final text = '${_controller.text.trim()}, ${extra.label}';
    setState(() {
      _result = NutritionResult(
        canonicalMeal: text,
        items: carried,
        calories: sum((i) => i.calories),
        protein: sum((i) => i.protein),
        carbohydrates: sum((i) => i.carbohydrates),
        fat: sum((i) => i.fat),
        fiber: sum((i) => i.fiber),
        confidence: base.confidence,
        warnings: const [],
        source: base.source,
        createdAt: base.createdAt,
      );
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      _savedMealMatches = const [];
      _initRowsFromResult(_result!);
    });
  }

  static NutrientRange _exact(String text) {
    final v = double.tryParse(text.trim()) ?? 0;
    return NutrientRange(min: v, max: v);
  }

  Future<void> _onSavePressed() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _saveMeal();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The row's micros at [kcal]: what it carried (pack label or estimate),
  /// scaled to the saved calories, with the food library filling any gaps.
  Micronutrients? _microsForRow(_IngredientRow row, double kcal) {
    var own = row.micros;
    if (own != null && row.microsKcal > 0 && kcal >= 0) own = own.scaled(kcal / row.microsKcal);
    return MicronutrientLibrary.instance.enrich(row.parsed.normalizedName, kcal, own, preferExisting: true);
  }

  Future<void> _saveMeal() async {
    if (_result == null) return;
    
    final text = _controller.text.trim();
    final updatedItems = <NutritionItem>[];
    double totalCal = 0;
    double totalPro = 0;
    double totalCarb = 0;
    double totalFat = 0;
    double totalFib = 0;
    
    for (final row in _rows) {
      final cVal = double.tryParse(row.calCtrl.text) ?? 0;
      final pVal = double.tryParse(row.proCtrl.text) ?? 0;
      final carbVal = double.tryParse(row.carbCtrl.text) ?? 0;
      final fatVal = double.tryParse(row.fatCtrl.text) ?? 0;
      final fibVal = double.tryParse(row.fibCtrl.text) ?? 0;
      
      updatedItems.add(NutritionItem(
        name: row.parsed.normalizedName,
        quantity: row.parsed.quantity,
        unit: row.parsed.unit,
        estimated: false,
        mode: row.role == FoodRole.completeMeal ? EstimationMode.packagedKnown : EstimationMode.directQuantity,
        calories: NutrientRange(min: cVal, max: cVal),
        protein: NutrientRange(min: pVal, max: pVal),
        carbohydrates: NutrientRange(min: carbVal, max: carbVal),
        fat: NutrientRange(min: fatVal, max: fatVal),
        fiber: NutrientRange(min: fibVal, max: fibVal),
        micros: _microsForRow(row, cVal),
      ));
      
      totalCal += cVal;
      totalPro += pVal;
      totalCarb += carbVal;
      totalFat += fatVal;
      totalFib += fibVal;
      
      final qty = row.parsed.quantity > 0.0 ? row.parsed.quantity : 1.0;
      
      if (_rememberEdits) {
        await UserNutritionMemory.instance.saveOverride(
          row.parsed.normalizedName,
          cVal / qty,
          pVal / qty,
          carbohydratesPerUnit: carbVal / qty,
          fatPerUnit: fatVal / qty,
          fiberPerUnit: fibVal / qty,
          referenceQuantity: qty,
          referenceUnit: row.parsed.unit,
        );
      }
      
      final origCal = row.originalCalories;
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: row.role,
        mealHasPrimary: _rows.any((r) => r.role == FoodRole.primary),
        pipelineCalEstimate: origCal,
        userCorrectedCal: cVal,
      );
    }
    
    await EatingPatternService.instance.save();
    CloudSyncService.instance.syncEatingPatternsBackground().ignore();
    
    final score = NutritionResult.calculateLocalQualityScore(
      totalCal,
      totalPro,
      text.isNotEmpty ? text : _result!.canonicalMeal,
      carbs: totalCarb,
      fat: totalFat,
      fiber: totalFib,
    );
    
    final finalResult = NutritionResult(
      canonicalMeal: text.isNotEmpty ? text : _result!.canonicalMeal,
      items: updatedItems,
      calories: NutrientRange(min: totalCal, max: totalCal),
      protein: NutrientRange(min: totalPro, max: totalPro),
      confidence: 1.0,
      warnings: const [],
      source: 'user_override',
      createdAt: _result!.createdAt,
      carbohydrates: NutrientRange(min: totalCarb, max: totalCarb),
      fat: NutrientRange(min: totalFat, max: totalFat),
      fiber: NutrientRange(min: totalFib, max: totalFib),
      mealQualityScore: score,
      mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, text.isNotEmpty ? text : _result!.canonicalMeal),
      mealQualityPositive: NutritionResult.getLocalQualityPositive(score, text.isNotEmpty ? text : _result!.canonicalMeal),
      mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, text.isNotEmpty ? text : _result!.canonicalMeal),
      macrosLockedByUser: true,
      userCorrected: true,
    );
    
    if (kDebugMode) {
      debugPrint('''
=================== REAL APP RUNTIME AUDIT TRACE (AFTER CALCULATE / SAVE) ===================
  9. Detail sheet values after Calc: Calories=${finalResult.calories.mid}, Pro=${finalResult.protein.mid}, Carbs=${finalResult.carbohydrates?.mid}, Fat=${finalResult.fat?.mid}, Fiber=${finalResult.fiber?.mid}, Score=${finalResult.mealQualityScore}
=============================================================================================
''');
    }
    
    final isEditing = widget.initialEntry != null;
    final entry = MealEntry(
      rawInput: widget.initialEntry?.rawInput ?? text,
      result: finalResult,
      addedAt: widget.initialEntry?.addedAt ?? DateTime.now(),
      section: widget.section,
      dayOfWeek: widget.date.weekday,
      parsedFoods: updatedItems.map((i) => i.name).toList(),
      edited: isEditing || true,
      editCount: (widget.initialEntry?.editCount ?? 0) + (isEditing ? 1 : 0),
      finalSavedInput: text,
      userCorrected: true,
      // An edit keeps the entry's identity and is stamped so it wins the
      // cross-device merge over older copies.
      id: widget.initialEntry?.id,
      updatedAt: isEditing ? DateTime.now().toUtc() : null,
    );

    if (isEditing) {
      logFor(widget.date).replace(widget.initialEntry!.section, widget.initialEntry!, entry);
      MealTombstones.instance.recordReplace(dateKey(widget.date), widget.initialEntry!, entry);
    } else {
      logFor(widget.date).add(widget.section, entry);
    }
    
    // The in-memory log above is the source of truth, so the screen closes
    // right away. Both writes below update memory synchronously and then
    // persist through coalesced writers that are flushed on app pause/logout.
    MealMemory.instance.store(
      entry.rawInput,
      entry.result,
      finalSavedInput: entry.finalSavedInput,
      canonicalMeal: entry.result.canonicalMeal,
    ).ignore();

    PersistenceService.saveDay(widget.date).ignore();
    // Tell everything that reads the logs (heatmap, avatar rings, Kyno).
    PersistenceService.notifyLogsChanged();
    KynoContextService.instance.invalidate();
    if (!mounted) return;
    // Everything above is already written. The button now shows its drawn
    // check for a beat (instant under reduced motion), then the screen
    // closes with the entry exactly as before.
    await _playLoggedMoment();
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  /// Swaps the save button for its "Logged" face and completes when that
  /// moment has played. The commit haptic already fired once on the tap
  /// (KButton), the same frame the save landed, so none is added here.
  Future<void> _playLoggedMoment() {
    final moment = Completer<void>();
    _loggedMoment = moment;
    setState(() => _logged = true);
    return moment.future;
  }

  void _onLoggedMomentFinished() {
    final moment = _loggedMoment;
    _loggedMoment = null;
    if (moment != null && !moment.isCompleted) moment.complete();
  }


  Future<void> _deleteEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColor.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: KRadius.xl,
          side: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
        ),
        title: Text('Delete this meal?', style: KText.h2),
        content: Text(
          "It'll be removed from your log for good. This can't be undone.",
          style: KText.body.copyWith(color: KColor.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: KColor.textSecondary,
              minimumSize: const Size(64, 48),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: KColor.danger,
              minimumSize: const Size(64, 48),
              textStyle: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      KHaptics.commit();
      KynoContextService.instance.invalidate();
      Navigator.of(context).pop(const DeleteSentinel());
    }
  }

  // ─── Small building blocks ──────────────────────────────────────────────────

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    Color color, {
    bool isProminent = false,
  }) {
    final radius = KRadius.sm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: KText.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isProminent ? KColor.textSecondary : KColor.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          cursorColor: KColor.ink,
          style: KText.numSmall.copyWith(
            color: KColor.textPrimary,
            fontSize: isProminent ? 17 : 15,
            fontWeight: isProminent ? FontWeight.w700 : FontWeight.w600,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.035),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: isProminent
                    ? color.withValues(alpha: KColor.isDark ? 0.32 : 0.36)
                    : (KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: KColor.ink,
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(FoodRole role) {
    final (label, color) = switch (role) {
      FoodRole.primary => ('Base / carb', KColor.textSecondary),
      FoodRole.protein => ('Protein', KColor.protein),
      FoodRole.accompaniment => ('Side / curry', KColor.textSecondary),
      FoodRole.addOn => ('Add-on', KColor.textSecondary),
      FoodRole.completeMeal => ('Single unit', KColor.textMuted),
    };
    return _Tag(label: label, color: color);
  }

  Widget _buildSourceBadge(OverrideSource source) {
    final (label, color) = switch (source) {
      OverrideSource.userCorrected => ('Your numbers', KColor.textSecondary),
    };
    return _Tag(label: label, color: color);
  }

  Widget _buildMealTypeBadge(SavedMealType type) {
    final (label, col) = switch (type) {
      SavedMealType.recurringMeal => ('Recurring', KColor.textSecondary),
      SavedMealType.savedMeal => ('Saved', KColor.textSecondary),
      SavedMealType.rememberedFood => ('Remembered', KColor.textSecondary),
      SavedMealType.globalDefault => ('Default', KColor.textMuted),
      SavedMealType.oneOffMeal => ('Recent', KColor.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.06),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        label,
        style: KText.label.copyWith(
          color: col,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _buildSavedMealsAutocompleteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KIcon(Icons.bookmark_border, size: 16, color: KColor.textMuted),
            const SizedBox(width: 6),
            Text('Saved meals', style: KText.h3.copyWith(fontSize: 14, color: KColor.textSecondary)),
          ],
        ),
        const SizedBox(height: KSpacing.sm),
        ..._savedMealMatches.map((match) {
          final calStr = match.calories.toStringAsFixed(0);
          final proVal = match.protein;
          final proStr = proVal == proVal.truncateToDouble()
              ? proVal.toStringAsFixed(0)
              : proVal.toStringAsFixed(1);
          final carbVal = match.carbohydrates;
          final carbStr = carbVal > 0
              ? ' • ${carbVal.toStringAsFixed(carbVal == carbVal.truncateToDouble() ? 0 : 1)}g C'
              : '';

          return Container(
            margin: const EdgeInsets.only(bottom: KSpacing.sm),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: KColor.card,
              borderRadius: KRadius.md,
              border: Border.all(
                color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                KIcon(KIcons.food(match.title), size: KIcons.lg),
                const SizedBox(width: KSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match.title,
                        style: KText.h3.copyWith(
                          fontSize: 15,
                          color: KColor.textPrimary,
                        ),
                        softWrap: true,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildMealTypeBadge(match.mealType),
                          KDotStat(calStr, 'kcal', color: KColor.ember),
                          KDotStat(proStr, 'g protein', color: KColor.protein),
                          if (carbStr.isNotEmpty)
                            KDotStat(amount(match.carbohydrates), 'g carbs', color: KColor.carbs),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Pressable(
                  onTap: () => _useSavedMeal(match),
                  semanticLabel: 'Use saved meal ${match.title}',
                  borderRadius: KRadius.pill,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: KColor.ink,
                          borderRadius: KRadius.pill,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Use',
                              style: KText.label.copyWith(
                                color: KColor.onInk,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: KColor.onInk,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─── Composer ───────────────────────────────────────────────────────────────

  Widget _buildComposer() {
    final focused = _composerFocused;
    return Stack(
      children: [
        AnimatedContainer(
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.emphasizedCurve,
          decoration: BoxDecoration(
            color: focused ? KColor.cardHigh : KColor.card,
            borderRadius: KRadius.lg,
            border: Border.all(
              color: focused
                  ? KColor.ink
                  : (KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
              width: focused ? 1.5 : 1,
            ),
            boxShadow: KShadow.card,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: KSpacing.lg,
            vertical: 4,
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: KText.body.copyWith(fontSize: 17, color: KColor.textPrimary),
            cursorColor: KColor.ink,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_controller.text.trim().isNotEmpty && !_loading) {
                KHaptics.commit();
              }
              _calculate();
            },
            decoration: InputDecoration(
              hintText: 'e.g. 2 roti, a katori of dal, some salad',
              hintStyle: KText.body.copyWith(color: KColor.textDisabled),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        // Kyno pulse — only visible while estimating. The controller repeats
        // only when ambient motion is allowed (see _syncPulse).
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedOpacity(
                opacity: _loading ? 1 : 0,
                duration: KMotion.of(context, KMotion.quick),
                child: FadeTransition(
                  opacity: _pulse,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: KRadius.lg,
                      border: Border.all(
                        color: KColor.ember.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Estimate states ────────────────────────────────────────────────────────

  Widget _buildStateArea() {
    final Widget child;
    if (_loading || (_finishingEstimate && _result != null)) {
      // Same key while loading and while finishing, so the progress line is
      // the same widget that eases to 100% when the estimate lands.
      child = _EstimateSkeleton(
        key: const ValueKey('loading'),
        done: !_loading,
        onCompleted: () {
          if (mounted && _finishingEstimate) setState(() => _finishingEstimate = false);
        },
      );
    } else if (_result != null) {
      child = KeyedSubtree(
        key: const ValueKey('result'),
        // Live totals repaint on their own while macro fields are typed in.
        child: ValueListenableBuilder<int>(
          valueListenable: _totalsTick,
          builder: (context, tick, child) => _buildEstimateSummary(),
        ),
      );
    } else if (_error != null) {
      child = Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(bottom: KSpacing.xxl),
        child: KErrorCard(
          title: "Couldn't estimate that",
          message: 'Check your connection and try again, or reword the meal a little.',
          onRetry: _calculate,
        ),
      );
    } else {
      child = const _ComposerHint(key: ValueKey('idle'));
    }
    // The height eases between states (the skeleton is taller than the
    // result), so the ingredients below glide up instead of jumping.
    return AnimatedSize(
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.standard),
        switchInCurve: KMotion.decelerate,
        switchOutCurve: KMotion.accelerate,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: child,
      ),
    );
  }

  /// The estimate preview: calories → protein → confidence & macro split,
  /// revealed in one stagger. Values are the live totals (single numbers —
  /// no fabricated ranges).
  Widget _buildEstimateSummary() {
    final r = _result!;
    final confirmed = r.userCorrected || r.macrosLockedByUser;
    final confColor = confirmed
        ? KColor.textSecondary
        : (r.confidence >= 0.86
              ? KColor.ink
              : (r.confidence >= 0.62 ? KColor.textSecondary : KColor.ember));
    final confLabel = confirmed ? 'Your confirmed macros' : r.confidenceLabel;
    final confIcon = confirmed
        ? Icons.lock_rounded
        : (r.confidence >= 0.86 ? Icons.verified_rounded : Icons.tune_rounded);

    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KReveal(
                  index: 0,
                  child: _HeroStat(
                    label: 'Calories',
                    icon: KIcons.calories,
                    value: _totalCal,
                    decimals: 0,
                    unit: 'kcal',
                    colors: KGradient.fuel,
                  ),
                ),
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: KReveal(
                  index: 1,
                  child: _HeroStat(
                    label: 'Protein',
                    icon: KIcons.protein,
                    value: _totalPro,
                    decimals: 1,
                    unit: 'g',
                    colors: KGradient.protein,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          KReveal(
            index: 2,
            child: Wrap(
              spacing: KSpacing.sm,
              runSpacing: KSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                KChip(confLabel, color: confColor, icon: confIcon),
                _MiniMacro(
                  label: 'Carbs',
                  value: _totalCarb,
                  color: KColor.carbs,
                ),
                _MiniMacro(
                  label: 'Fat',
                  value: _totalFat,
                  color: KColor.fat,
                ),
                _MiniMacro(
                  label: 'Fiber',
                  value: _totalFib,
                  color: KColor.fiber,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Anything on top?": one-tap extras people forget (ghee on roti, sugar
  /// in chai), shown under the ingredients.
  Widget _buildExtras() {
    final extras = HiddenExtras.suggest(_controller.text);
    if (extras.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Anything on top?',
            style: KText.caption.copyWith(color: KColor.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: KSpacing.xs),
          Wrap(
            spacing: KSpacing.sm,
            runSpacing: KSpacing.sm,
            children: [
              for (final e in extras)
                ActionChip(
                  avatar: Icon(Icons.add_rounded, size: 16, color: KColor.fuel),
                  label: Text('${e.label} · ${e.kcal.round()} kcal', style: KText.caption.copyWith(color: KColor.textPrimary)),
                  side: BorderSide(color: KColor.fuel.withValues(alpha: 0.3)),
                  backgroundColor: KColor.tint(KColor.fuel, dark: 0.06, light: 0.04),
                  onPressed: () => _addExtra(e),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRememberToggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, 6, 6, 6),
      decoration: BoxDecoration(
        color: KColor.card.withValues(alpha: KColor.isDark ? 0.7 : 1),
        borderRadius: KRadius.md,
        border: Border.all(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.psychology_alt_rounded,
            size: 16,
            color: KColor.textSecondary,
          ),
          const SizedBox(width: KSpacing.sm),
          Expanded(
            child: Text(
              'Remember my numbers for next time',
              style: KText.bodyMedium.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KColor.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: KSpacing.sm),
          Switch(
            value: _rememberEdits,
            onChanged: (v) {
              KHaptics.select();
              setState(() => _rememberEdits = v);
            },
            activeThumbColor: KColor.onInk,
            activeTrackColor: KColor.ink,
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsHeader() {
    return KReveal(
      index: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Ingredients', style: KText.h2),
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.05),
                    borderRadius: KRadius.pill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: KColor.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Tap any number to adjust',
                          style: KText.label.copyWith(
                            fontSize: 12,
                            letterSpacing: 0,
                            color: KColor.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
        ],
      ),
    );
  }

  Widget _buildIngredientCard(int i) {
    final row = _rows[i];
    return KReveal(
      key: ObjectKey(row),
      index: 4 + i,
      child: Container(
        margin: const EdgeInsets.only(bottom: KSpacing.lg),
        padding: const EdgeInsets.fromLTRB(KSpacing.lg, 10, 6, 10),
        decoration: BoxDecoration(
          color: KColor.card,
          borderRadius: KRadius.lg,
          border: Border.all(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
          boxShadow: KShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.textCtrl,
                    focusNode: row.focusNode,
                    cursorColor: KColor.ink,
                    style: KText.h3.copyWith(
                      fontSize: 15,
                      color: KColor.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. 2 roti',
                      hintStyle: KText.body.copyWith(
                        color: KColor.textDisabled,
                      ),
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      suffixIcon: row.isEstimating
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: KSpinner(
                                size: 14,
                                color: KColor.textSecondary,
                                semanticsLabel: 'Re-estimating this one',
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: KColor.danger,
                    size: 20,
                  ),
                  tooltip: 'Remove ingredient',
                  onPressed: () => _deleteRow(i),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildRoleBadge(row.role),
                  row.isSaved
                      ? _buildSourceBadge(row.source)
                      : _Tag(
                          label: "Kyno's estimate",
                          color: KColor.textMuted,
                          filled: true,
                        ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Divider(
                color: KColor.isDark ? KColor.fg.withValues(alpha: 0.07) : KColor.divider,
                height: 22,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildField(
                          'Calories (kcal)',
                          row.calCtrl,
                          KColor.calorie,
                          isProminent: true,
                        ),
                      ),
                      const SizedBox(width: KSpacing.md),
                      Expanded(
                        child: _buildField(
                          'Protein (g)',
                          row.proCtrl,
                          KColor.protein,
                          isProminent: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildField(
                          'Carbs (g)',
                          row.carbCtrl,
                          KColor.carbs,
                        ),
                      ),
                      const SizedBox(width: KSpacing.sm),
                      Expanded(
                        child: _buildField(
                          'Fat (g)',
                          row.fatCtrl,
                          KColor.fat,
                        ),
                      ),
                      const SizedBox(width: KSpacing.sm),
                      Expanded(
                        child: _buildField(
                          'Fiber (g)',
                          row.fibCtrl,
                          KColor.fiber,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => _resetItemToOriginal(i),
                icon: const Icon(Icons.undo_rounded, size: 14),
                label: const Text('Reset to estimate'),
                style: TextButton.styleFrom(
                  foregroundColor: KColor.textSecondary,
                  textStyle: KText.caption.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssumptions() {
    final warnings = _result?.userFacingWarnings ?? const <String>[];
    if (warnings.isEmpty) return const SizedBox.shrink();
    return KReveal(
      index: 4 + _rows.length,
      child: Container(
        margin: const EdgeInsets.only(bottom: KSpacing.lg),
        padding: const EdgeInsets.all(KSpacing.lg),
        decoration: BoxDecoration(
          color: KColor.ember.withValues(alpha: KColor.isDark ? 0.06 : 0.07),
          borderRadius: KRadius.lg,
          border: Border.all(color: KColor.ember.withValues(alpha: KColor.isDark ? 0.22 : 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How Kyno estimated this',
              style: KText.h3.copyWith(fontSize: 14, color: KColor.ember),
            ),
            const SizedBox(height: KSpacing.sm),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: KColor.ember,
                        size: 13,
                      ),
                    ),
                    const SizedBox(width: KSpacing.sm),
                    Expanded(
                      child: Text(
                        w,
                        style: KText.caption.copyWith(
                          fontSize: 13,
                          color: KColor.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isEditing = widget.initialEntry != null;
    return KReveal(
      rise: 24,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          KSpacing.p,
          KSpacing.md,
          KSpacing.p,
          KSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: KColor.surface.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Warning + running total repaint on their own while macro
            // fields are typed in; the rest of the bar stays as built.
            ValueListenableBuilder<int>(
              valueListenable: _totalsTick,
              builder: (context, tick, child) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    AnimatedSize(
                      duration: KMotion.of(context, KMotion.standard),
                      curve: KMotion.emphasizedCurve,
                      alignment: Alignment.topCenter,
                      child: _validationWarning == null
                          ? const SizedBox(width: double.infinity)
                          : Semantics(
                              liveRegion: true,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: KSpacing.md),
                                decoration: BoxDecoration(
                                  color: KColor.warning.withValues(alpha: 0.1),
                                  borderRadius: KRadius.sm,
                                  border: Border.all(
                                    color: KColor.warning.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: KColor.warning,
                                      size: 16,
                                    ),
                                    const SizedBox(width: KSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        _validationWarning!,
                                        style: KText.caption.copyWith(
                                          fontSize: 13,
                                          color: KColor.warning,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    // Running total — compact, tabular, always visible while editing rows.
                    Padding(
                      padding: const EdgeInsets.only(bottom: KSpacing.md),
                      child: Wrap(
                        spacing: KSpacing.lg,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Total',
                            style: KText.caption.copyWith(fontSize: 13, color: KColor.textMuted),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(color: KColor.calorie, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              // Totals roll digit by digit as rows are edited.
                              Flexible(
                                child: _RollingTotal(
                                  value: _totalCal.toStringAsFixed(0),
                                  unit: ' kcal',
                                  style: KText.numSmall.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(color: KColor.protein, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: _RollingTotal(
                                  value: _totalPro.toStringAsFixed(1),
                                  unit: 'g protein',
                                  style: KText.numSmall.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Idle / saving is the normal button; a successful save turns it
            // into the drawn-check "Logged" face, then the screen closes.
            AnimatedSwitcher(
              duration: KMotion.of(context, KMotion.quick),
              switchInCurve: KMotion.decelerate,
              switchOutCurve: KMotion.accelerate,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.passthrough,
                alignment: Alignment.center,
                children: [...previous, ?current],
              ),
              child: _logged
                  ? SizedBox(
                      key: const ValueKey('logged'),
                      width: double.infinity,
                      child: KSuccessPill(
                        label: isEditing ? 'Saved' : 'Logged',
                        onFinished: _onLoggedMomentFinished,
                      ),
                    )
                  : KButton(
                      key: const ValueKey('save'),
                      label: isEditing ? 'Save changes' : 'Log meal',
                      icon: isEditing ? Icons.check_rounded : Icons.add_task_rounded,
                      loading: _saving,
                      onTap: _onSavePressed,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialEntry != null;
    // While the "Logged" moment plays the meal is already saved; hold the
    // route so the caller still receives the entry when it closes.
    return PopScope(
      canPop: !_logged,
      child: KPage(
      tone: KTone.fuel,
      intensity: 0.8,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: KColor.textPrimary),
          tooltip: 'Close',
          onPressed: _logged ? null : () => Navigator.of(context).pop(null),
        ),
        title: Text(
          !isEditing
              ? 'Add to ${widget.section.displayName}'
              : 'Edit ${widget.section.displayName}',
          style: KText.h2,
        ),
        centerTitle: false,
        actions: [
          if (isEditing)
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                color: KColor.danger,
              ),
              tooltip: 'Delete meal',
              onPressed: _deleteEntry,
            ),
        ],
      ),
      body: SafeArea(
        bottom: _result == null,
        child: CustomScrollView(
          // Keep the (few) ingredient editors mounted when scrolled away so
          // focus-loss re-estimation and live totals never lose a row.
          cacheExtent: 1600,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KSpacing.p,
                  4,
                  KSpacing.p,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Wraps under the label when large text leaves no room.
                    // Label and scan pill share a line; under large text the
                    // pill drops below, left-aligned.
                    Row(
                      children: [
                        Expanded(
                          child: Text('What did you eat?', style: KText.h3.copyWith(color: KColor.textSecondary)),
                        ),
                        const SizedBox(width: KSpacing.sm),
                        // Large text shrinks the pill instead of overflowing.
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: _ScanPill(onTap: _scanBarcode),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: KSpacing.md),
                    _buildComposer(),
                    // Layout lands instantly (matches are tappable on the very
                    // next frame); only opacity/offset animate.
                    AnimatedSwitcher(
                      duration: KMotion.of(context, KMotion.standard),
                      switchInCurve: KMotion.decelerate,
                      switchOutCurve: KMotion.accelerate,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          for (final p in previous) IgnorePointer(child: p),
                          ?current,
                        ],
                      ),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, -0.04), end: Offset.zero)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: _savedMealMatches.isNotEmpty
                          ? Padding(
                              key: const ValueKey('saved-matches'),
                              padding: const EdgeInsets.only(top: KSpacing.md),
                              child: _buildSavedMealsAutocompleteSection(),
                            )
                          : const SizedBox(key: ValueKey('no-matches'), width: double.infinity),
                    ),
                    const SizedBox(height: KSpacing.md),
                    KButton(
                      label: _result == null ? 'Estimate macros' : 'Re-estimate',
                      loading: _loading,
                      // Once a preview exists, re-calculating is secondary to saving.
                      outlined: _result != null,
                      onTap: _loading ? null : _calculate,
                    ),
                    const SizedBox(height: KSpacing.xl),
                    _buildStateArea(),
                  ],
                ),
              ),
            ),

            if (_result != null) ...[
              // A meal has a handful of ingredients: build them eagerly so every
              // row's controllers/fields stay mounted while the user edits.
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildIngredientsHeader(),
                      for (var i = 0; i < _rows.length; i++)
                        _buildIngredientCard(i),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpacing.p,
                    vertical: KSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildExtras(),
                      _buildAssumptions(),
                      _buildRememberToggle(),
                      const SizedBox(height: KSpacing.lg),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            KHaptics.select();
                            _addRow();
                          },
                          icon: Icon(
                            Icons.add_rounded,
                            color: KColor.textPrimary,
                          ),
                          label: const Text('Add ingredient'),
                          style: TextButton.styleFrom(
                            foregroundColor: KColor.textPrimary,
                            textStyle: KText.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: KRadius.pill,
                              side: BorderSide(
                                color: KColor.fg.withValues(alpha: KColor.isDark ? 0.18 : 0.2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _result != null ? _buildBottomBar() : null,
      ),
    );
  }
}

// ─── Private presentational widgets ───────────────────────────────────────────

/// Small rounded tag used for ingredient role / source.
/// Inline "Scan a barcode" affordance beside the composer label: a quiet
/// outlined pill, 48dp tall, that reads as a second way in, not chrome.
class _ScanPill extends StatelessWidget {
  const _ScanPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Scan barcode',
      excludeFromSemantics: true,
      child: Pressable(
        onTap: () {
          KHaptics.select();
          onTap();
        },
        semanticLabel: 'Scan a barcode',
        borderRadius: KRadius.pill,
        scale: 0.96,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: KColor.card,
              borderRadius: KRadius.pill,
              border: Border.all(
                color: KColor.isDark ? KColor.fg.withValues(alpha: 0.12) : KColor.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KIcon(KIcons.scan, size: 16, color: KColor.textPrimary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Scan a barcode',
                    style: KText.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KColor.textPrimary,
                    ),
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

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.filled = false});
  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.06) : null,
        borderRadius: KRadius.xs,
        border: filled
            ? null
            : Border.all(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.16 : 0.14)),
      ),
      child: Text(
        label,
        style: KText.label.copyWith(
          fontSize: 12,
          letterSpacing: 0,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// One hero number of the estimate preview (calories / protein). The number
/// counts to its live value; the unit is a separate label.
class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.icon,
    required this.value,
    required this.decimals,
    required this.unit,
    required this.colors,
  });

  final String label;
  final IconData icon;
  final double value;
  final int decimals;
  final String unit;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final accent = colors.first;
    final shown = value.toStringAsFixed(decimals);
    return Semantics(
      container: true,
      label: '$label $shown $unit',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            // Printed, not boxed: an ink rule on top, the number below.
            border: Border(top: BorderSide(color: accent, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  KIcon(icon, size: 15, color: accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: KText.caption.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KColor.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KSpacing.sm),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 4,
                children: [
                  // Rolls up from zero on reveal, then digit by digit as
                  // ingredient numbers change. Tabular, so it never reflows.
                  KRollingNumber(
                    shown,
                    fromZero: true,
                    duration: KMotion.slow,
                    style: KText.numDisplay.copyWith(
                      fontSize: 34,
                      color: KColor.textPrimary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      unit,
                      style: KText.caption.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMacro extends StatelessWidget {
  const _MiniMacro({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        _RollingTotal(
          prefix: '$label ',
          value: value.toStringAsFixed(0),
          unit: 'g',
          style: KText.caption.copyWith(
            fontSize: 13,
            color: KColor.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Idle / empty state below the composer: how to talk to Kyno.
class _ComposerHint extends StatelessWidget {
  const _ComposerHint({super.key});

  static const _examples = [
    '2 roti + dal',
    'rice thoda, rajma',
    '1 scoop whey in milk',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.xxl),
      child: KReveal(
        child: Container(
          padding: const EdgeInsets.only(top: KSpacing.lg),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.10 : 0.09))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const KynoMark(size: 20),
                  const SizedBox(width: KSpacing.sm),
                  Expanded(
                    child: Text('Type it like you’d say it', style: KText.h3),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Katori, roti, thoda, scoop. Kyno gets everyday portions.',
                style: KText.caption.copyWith(fontSize: 13),
              ),
              const SizedBox(height: KSpacing.md),
              Wrap(
                spacing: KSpacing.lg,
                runSpacing: KSpacing.xs,
                children: [
                  for (final e in _examples)
                    Text(
                      '“$e”',
                      style: KText.body.copyWith(
                        fontSize: 14,
                        color: KColor.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number with its words around it ("Carbs 42g", "512 kcal") where only the
/// digits roll when the value changes. Read by screen readers as one phrase.
class _RollingTotal extends StatelessWidget {
  const _RollingTotal({
    required this.value,
    required this.style,
    this.prefix = '',
    this.unit = '',
  });

  final String value;
  final String prefix;
  final String unit;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final st = style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      label: '$prefix$value$unit',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (prefix.isNotEmpty) Text(prefix, style: st),
          KRollingNumber(value, style: st, duration: KMotion.standard),
          if (unit.isNotEmpty) Flexible(child: Text(unit, style: st, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// Estimating state: a still skeleton shaped like the estimate preview, under
/// a calm ticked progress line that eases toward ~90% over the usual wait
/// (3 to 8 s) and closes out when the estimate lands. No shimmer, no glow.
class _EstimateSkeleton extends StatelessWidget {
  const _EstimateSkeleton({super.key, this.done = false, this.onCompleted});

  /// The estimate has arrived: finish the line, then call [onCompleted].
  final bool done;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    final fill = KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.05);
    Widget box(double h, {double? w, BorderRadius? r}) => Container(
      width: w ?? double.infinity,
      height: h,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: r ?? KRadius.sm,
      ),
    );

    return Semantics(
      liveRegion: true,
      label: 'Crunching your macros',
      child: Padding(
        padding: const EdgeInsets.only(bottom: KSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  const KMacroLoader(size: 32, semanticsLabel: null),
                  const SizedBox(width: KSpacing.md),
                  Expanded(
                    child: KLoadingLabel(
                      textAlign: TextAlign.start,
                      style: KText.bodyMedium.copyWith(color: KColor.textSecondary),
                      messages: const [
                        'Crunching your macros…',
                        'Reading the portions…',
                        'Adding it all up…',
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KSpacing.sm),
            KProgressLine(done: done, onCompleted: onCompleted),
            const SizedBox(height: KSpacing.md),
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: box(104, r: KRadius.lg)),
                      const SizedBox(width: KSpacing.md),
                      Expanded(child: box(104, r: KRadius.lg)),
                    ],
                  ),
                  const SizedBox(height: KSpacing.md),
                  Row(
                    children: [
                      box(24, w: 110, r: KRadius.pill),
                      const SizedBox(width: KSpacing.sm),
                      Expanded(child: box(12)),
                    ],
                  ),
                  const SizedBox(height: KSpacing.xl),
                  box(132, r: KRadius.lg),
                  const SizedBox(height: KSpacing.md),
                  box(132, r: KRadius.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
