import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_result.dart';
import '../models/day_log.dart';
import '../services/nutrition_pipeline.dart';
import '../services/meal_memory.dart';
import '../services/user_nutrition_memory.dart';
import '../services/food_role_classifier.dart';
import '../services/eating_pattern_service.dart';
import '../services/item_parser.dart';
import '../services/persistence_service.dart';
import '../services/cloud_sync_service.dart';

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

  const AddMealScreen({
    super.key,
    required this.section,
    required this.date,
    this.initialEntry,
    this.initialText,
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

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

  final List<_IngredientRow> _rows = [];
  bool _rememberEdits = true;
  double _totalCal = 0;
  double _totalPro = 0;
  double _totalCarb = 0;
  double _totalFat = 0;
  double _totalFib = 0;
  String? _validationWarning;

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      _controller.text = widget.initialEntry!.finalSavedInput;
      _result = widget.initialEntry!.result;
      _initRowsFromResult(_result!);
    } else if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    // Auto-calculate when opened with suggestion text.
    if (widget.initialText != null && widget.initialEntry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _calculate());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _pulseCtrl.dispose();
    _clearRows();
    super.dispose();
  }

  void _clearRows() {
    for (final row in _rows) {
      row.calCtrl.removeListener(_updateTotalsAndValidate);
      row.proCtrl.removeListener(_updateTotalsAndValidate);
      row.carbCtrl.removeListener(_updateTotalsAndValidate);
      row.fatCtrl.removeListener(_updateTotalsAndValidate);
      row.fibCtrl.removeListener(_updateTotalsAndValidate);

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
    for (final item in result.items) {
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
      );

      row.calCtrl.addListener(_updateTotalsAndValidate);
      row.proCtrl.addListener(_updateTotalsAndValidate);
      row.carbCtrl.addListener(_updateTotalsAndValidate);
      row.fatCtrl.addListener(_updateTotalsAndValidate);
      row.fibCtrl.addListener(_updateTotalsAndValidate);

      row.focusNode.addListener(() {
        if (!row.focusNode.hasFocus) {
          _onFocusLost(row);
        }
      });

      _rows.add(row);
    }
    _updateTotalsAndValidate();
  }

  String _constructItemString(ParsedFoodItem parsed) {
    if (parsed.quantity == 1.0 && parsed.unit == 'serving') return parsed.normalizedName;
    if (parsed.quantity == 1.0) return '${parsed.unit} ${parsed.normalizedName}'.trim();
    String formattedQty = parsed.quantity == parsed.quantity.toInt() ? '${parsed.quantity.toInt()}' : '${parsed.quantity}';
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
      } catch (_) {
      } finally {
        setState(() => row.isEstimating = false);
        _updateTotalsAndValidate();
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
      row.parsed = p;
      _updateTotalsAndValidate();
    }
  }

  void _updateTotalsAndValidate() {
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

    if (mounted) {
      setState(() {
        _totalCal = calSum;
        _totalPro = proSum;
        _totalCarb = carbSum;
        _totalFat = fatSum;
        _totalFib = fibSum;

        final impliedCal = proSum * 4 + carbSum * 4 + fatSum * 9;
        if (calSum > 0 && impliedCal > 0) {
          final deviation = ((impliedCal - calSum) / calSum).abs();
          if (deviation > 0.15) {
            _validationWarning = "Please check your calories and macros.";
          } else {
            _validationWarning = null;
          }
        } else {
          _validationWarning = null;
        }
      });
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

    row.calCtrl.addListener(_updateTotalsAndValidate);
    row.proCtrl.addListener(_updateTotalsAndValidate);
    row.carbCtrl.addListener(_updateTotalsAndValidate);
    row.fatCtrl.addListener(_updateTotalsAndValidate);
    row.fibCtrl.addListener(_updateTotalsAndValidate);

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
    row.calCtrl.removeListener(_updateTotalsAndValidate);
    row.proCtrl.removeListener(_updateTotalsAndValidate);
    row.carbCtrl.removeListener(_updateTotalsAndValidate);
    row.fatCtrl.removeListener(_updateTotalsAndValidate);
    row.fibCtrl.removeListener(_updateTotalsAndValidate);

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

    _focusNode.unfocus();
    HapticFeedback.lightImpact();
    setState(() { _loading = true; _result = null; _error = null; });
    try {
      final result = await NutritionPipeline.instance.estimateMeal(text);
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
          _initRowsFromResult(result);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
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
    );
    
    if (isEditing) {
      logFor(widget.date).replace(widget.initialEntry!.section, widget.initialEntry!, entry);
    } else {
      logFor(widget.date).add(widget.section, entry);
    }
    
    await MealMemory.instance.store(
      entry.rawInput,
      entry.result,
      finalSavedInput: entry.finalSavedInput,
      canonicalMeal: entry.result.canonicalMeal,
    );
    
    await PersistenceService.saveDay(widget.date);
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  Future<void> _deleteEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete Entry',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This meal entry will be permanently removed from your log.',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(const DeleteSentinel());
    }
  }

  Widget _buildField(String label, TextEditingController ctrl, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color.withOpacity(0.85),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F0F14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(FoodRole role) {
    final (label, color) = switch (role) {
      FoodRole.primary       => ('Base/Carb', const Color(0xFF60A5FA)),
      FoodRole.protein       => ('Protein', const Color(0xFF52B788)),
      FoodRole.accompaniment => ('Side/Curry', const Color(0xFFFBBF24)),
      FoodRole.addOn         => ('Add-on', const Color(0xFFA78BFA)),
      FoodRole.completeMeal  => ('Single Unit', const Color(0xFF9CA3AF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSourceBadge(OverrideSource source) {
    final (label, color) = switch (source) {
      OverrideSource.userCorrected => ('✏️ Saved', const Color(0xFF60A5FA)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialEntry != null;
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Text(
          !isEditing
              ? 'Add to ${widget.section.displayName}'
              : 'Edit ${widget.section.displayName}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
              ),
              tooltip: 'Delete entry',
              onPressed: _deleteEntry,
            ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final borderColor = _loading
                            ? Color.lerp(
                                const Color(0xFF2E2E3E),
                                const Color(0xFF52B788),
                                _pulse.value,
                              )!
                            : const Color(0xFF2E2E3E);
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2C),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: child,
                        );
                      },
                      child: TextField(
                        controller:      _controller,
                        focusNode:       _focusNode,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15),
                        minLines: 2,
                        maxLines: 5,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _calculate(),
                        decoration: InputDecoration(
                          hintText:
                              '${widget.section.emoji}  Describe your meal…',
                          hintStyle: const TextStyle(
                              color: Color(0xFF4B5563), fontSize: 14),
                          border:        InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled:        false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _calculate,
                        child: _loading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white),
                              )
                            : const Text('Calculate'),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: Color(0xFFFFB347)),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Could not estimate meal. Using local data.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFFFB347)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            if (_result != null) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ingredients',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF52B788).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF52B788).withOpacity(0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bookmark_rounded, size: 10, color: Color(0xFF52B788)),
                                SizedBox(width: 4),
                                Text(
                                  'Saves to Food Library',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF52B788),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final row = _rows[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2C),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF2E2E3E)),
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
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'e.g., 4 bread slices',
                                      hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                      border: InputBorder.none,
                                      suffixIcon: row.isEstimating
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF52B788),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildRoleBadge(row.role),
                                const SizedBox(width: 6),
                                row.isSaved
                                    ? _buildSourceBadge(row.source)
                                    : Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF374151),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          '🤖 AI',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        ),
                                      ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                  onPressed: () => _deleteRow(i),
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            const Divider(color: Color(0xFF2E2E3E), height: 16),
                            Row(
                              children: [
                                Expanded(child: _buildField('Calories (kcal)', row.calCtrl, const Color(0xFFFF6B35))),
                                const SizedBox(width: 10),
                                Expanded(child: _buildField('Protein (g)', row.proCtrl, const Color(0xFF52B788))),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _buildField('Carbs (g)', row.carbCtrl, const Color(0xFF60A5FA))),
                                const SizedBox(width: 10),
                                Expanded(child: _buildField('Fat (g)', row.fatCtrl, const Color(0xFFFBBF24))),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _buildField('Fiber (g)', row.fibCtrl, const Color(0xFFA78BFA))),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => _resetItemToOriginal(i),
                                    icon: const Icon(Icons.undo_rounded, size: 12),
                                    label: const Text('Reset to Estimate', style: TextStyle(fontSize: 11)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF6B7280),
                                      padding: EdgeInsets.zero,
                                      alignment: Alignment.centerLeft,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: _rows.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    children: [
                      TextButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add_rounded, color: Color(0xFF52B788)),
                        label: const Text(
                          'Add Ingredient Row',
                          style: TextStyle(color: Color(0xFF52B788), fontWeight: FontWeight.bold),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: const Color(0xFF52B788).withOpacity(0.3)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
      bottomNavigationBar: _result != null
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F14),
                border: Border(top: BorderSide(color: Color(0xFF1E1E2C))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Remember edits for future logs',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD1D5DB),
                        ),
                      ),
                      Switch(
                        value: _rememberEdits,
                        onChanged: (v) => setState(() => _rememberEdits = v),
                        activeThumbColor: const Color(0xFF52B788),
                        activeTrackColor: const Color(0xFF1E3A2F),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_validationWarning != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB347).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFB347).withOpacity(0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB347), size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _validationWarning!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFFFFB347),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'RUNNING TOTAL',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_totalCal.toStringAsFixed(0)} kcal · ${_totalPro.toStringAsFixed(1)}g P',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ],
                        ),
                        Text(
                          'C: ${_totalCarb.toStringAsFixed(0)}g · F: ${_totalFat.toStringAsFixed(0)}g · Fib: ${_totalFib.toStringAsFixed(0)}g',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveMeal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D6A4F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        widget.initialEntry != null ? 'Save Changes' : 'Add to Log',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
