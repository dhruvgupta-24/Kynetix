import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_result.dart';
import '../models/day_log.dart';
import '../services/nutrition_pipeline.dart';
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

class _FixValues {
  final List<NutritionItem> items;
  final double cal;
  final double pro;
  final double carbs;
  final double fat;
  final double fiber;
  _FixValues(this.items, this.cal, this.pro, this.carbs, this.fat, this.fiber);
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

class _AddMealScreenState extends State<AddMealScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();

  NutritionResult? _result;
  bool _loading = false;
  String? _error;
  String? _lastLockedText;

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      _controller.text = widget.initialEntry!.finalSavedInput;
      _result = widget.initialEntry!.result;
      if (_result?.macrosLockedByUser ?? false) {
        _lastLockedText = widget.initialEntry!.finalSavedInput;
      }
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
    super.dispose();
  }

  Future<void> _calculate() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    // Never overwrite a manually-locked result via AI re-estimation.
    // The user must explicitly tap "Fix Estimate" to change macros.
    if (_result != null && _result!.macrosLockedByUser) {
      final changed = text != _lastLockedText || AddMealScreen.hasParsedMealStructureChanged(_lastLockedText ?? '', text);
      if (changed) {
        setState(() {
          _result = null;
          _lastLockedText = null;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.lock_rounded, color: Color(0xFF60A5FA), size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Macros are manually edited. Tap "Fix Estimate" to update them.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E1E2C),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return;
      }
    }

    _focusNode.unfocus();
    HapticFeedback.lightImpact();
    setState(() { _loading = true; _result = null; _error = null; });
    try {
      final result = await NutritionPipeline.instance.estimateMeal(text);
      if (mounted) setState(() { _result = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }  Future<void> _fixEstimate() async {
    if (_result == null) return;

    final mode = await showModalBottomSheet<_CorrectionMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CorrectionModeSheet(),
    );
    if (!mounted || mode == null) return;

    final mealName = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : _result!.canonicalMeal;

    if (mode == _CorrectionMode.applyCorrections) {
      // 1. Apply Corrections (Whole-meal)
      final initCal = _result!.primaryCaloriesEstimate;
      final initPro = _result!.primaryProteinEstimate;
      final initCarbs = ((_result!.carbohydrates?.min ?? 0) + (_result!.carbohydrates?.max ?? 0)) / 2;
      final initFat = ((_result!.fat?.min ?? 0) + (_result!.fat?.max ?? 0)) / 2;
      final initFiber = ((_result!.fiber?.min ?? 0) + (_result!.fiber?.max ?? 0)) / 2;

      final vals = await showModalBottomSheet<_FixValues>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _FixEstimateSheet(
          items: const [], // Empty items force a single overall meal correction form
          canonicalMeal: mealName,
          initialCal: initCal,
          initialPro: initPro,
          initialCarbs: initCarbs > 0 ? initCarbs : null,
          initialFat: initFat > 0 ? initFat : null,
          initialFiber: initFiber > 0 ? initFiber : null,
        ),
      );
      if (!mounted || vals == null) return;

      final score = NutritionResult.calculateLocalQualityScore(vals.cal, vals.pro, mealName);

      setState(() {
        _result = NutritionResult(
          canonicalMeal: mealName,
          items: const [], // whole meal only has no sub-items
          calories: NutrientRange(min: vals.cal, max: vals.cal),
          protein: NutrientRange(min: vals.pro, max: vals.pro),
          carbohydrates: NutrientRange(min: vals.carbs, max: vals.carbs),
          fat: NutrientRange(min: vals.fat, max: vals.fat),
          fiber: NutrientRange(min: vals.fiber, max: vals.fiber),
          sugar: _result?.sugar,
          saturatedFat: _result?.saturatedFat,
          sodium: _result?.sodium,
          mealQualityScore: score,
          mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, mealName),
          mealQualityPositive: NutritionResult.getLocalQualityPositive(score, mealName),
          mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, mealName),
          confidence: 0.99,
          warnings: const [],
          source: 'user_override',
          createdAt: DateTime.now(),
          macrosLockedByUser: true,
        );
        _lastLockedText = mealName;
      });
    } else {
      // 2. Edit Ingredients
      final res = await showModalBottomSheet<_IngredientEditResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _IngredientEditSheet(
          items: _result!.items,
          canonicalMeal: mealName,
        ),
      );
      if (!mounted || res == null) return;

      final vals = res.items;
      final originalItems = res.originalItems;
      final remember = res.rememberEdits;

      double totalCal = 0;
      double totalPro = 0;
      double totalCarb = 0;
      double totalFat = 0;
      double totalFib = 0;

      for (int i = 0; i < vals.length; i++) {
        final item = vals[i];
        final origItem = originalItems[i];
        final cVal = item.calories.max;
        final pVal = item.protein.max;
        final carbVal = item.carbohydrates?.max ?? 0;
        final fatVal = item.fat?.max ?? 0;
        final fibVal = item.fiber?.max ?? 0;

        totalCal += cVal;
        totalPro += pVal;
        totalCarb += carbVal;
        totalFat += fatVal;
        totalFib += fibVal;

        final qty = item.quantity.clamp(1.0, double.infinity);
        final origCal = (origItem.calories.min + origItem.calories.max) / 2;

        // Save override if "Remember edits" is checked
        if (remember) {
          await UserNutritionMemory.instance.saveOverride(
            item.name,
            cVal / qty,
            pVal / qty,
            carbohydratesPerUnit: carbVal / qty,
            fatPerUnit: fatVal / qty,
            fiberPerUnit: fibVal / qty,
            referenceQuantity: qty,
            referenceUnit: item.unit,
          );
        }

        // Record ingredient ratio correction to EatingPatternService (always learned)
        final rolledItems = FoodRoleClassifier.classifyAll(
          vals.map((v) => ParsedFoodItem(
            rawChunk: v.name,
            normalizedName: v.name,
            quantity: v.quantity,
            unit: v.unit,
          )).toList()
        );
        final hasPrimary = rolledItems.any((r) => r.role == FoodRole.primary);
        final itemRole = FoodRoleClassifier.classify(item.name);

        EatingPatternService.instance.recordIngredientCorrection(
          correctedItemRole: itemRole,
          mealHasPrimary: hasPrimary,
          pipelineCalEstimate: origCal,
          userCorrectedCal: cVal,
        );
      }

      await EatingPatternService.instance.save();
      // Fire-and-forget: sync new correction records to cloud
      CloudSyncService.instance.syncEatingPatternsBackground().ignore();

      final score = NutritionResult.calculateLocalQualityScore(totalCal, totalPro, mealName);

      setState(() {
        _result = NutritionResult(
          canonicalMeal: mealName,
          items: vals,
          calories: NutrientRange(min: totalCal, max: totalCal),
          protein: NutrientRange(min: totalPro, max: totalPro),
          carbohydrates: NutrientRange(min: totalCarb, max: totalCarb),
          fat: NutrientRange(min: totalFat, max: totalFat),
          fiber: NutrientRange(min: totalFib, max: totalFib),
          sugar: _result?.sugar,
          saturatedFat: _result?.saturatedFat,
          sodium: _result?.sodium,
          mealQualityScore: score,
          mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, mealName),
          mealQualityPositive: NutritionResult.getLocalQualityPositive(score, mealName),
          mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, mealName),
          confidence: 0.99,
          warnings: const [],
          source: 'user_override',
          createdAt: DateTime.now(),
          macrosLockedByUser: true,
        );
        _lastLockedText = mealName;
      });
    }

    if (widget.initialEntry != null && _result != null) {
      final text = _controller.text.trim();
      final parsedFoods = _result!.items.map((i) => i.name).toList(growable: false);
      final entry = MealEntry(
        rawInput: widget.initialEntry!.rawInput,
        result: _result!,
        addedAt: widget.initialEntry!.addedAt,
        section: widget.initialEntry!.section,
        dayOfWeek: widget.initialEntry!.dayOfWeek,
        parsedFoods: parsedFoods,
        edited: true,
        editCount: widget.initialEntry!.editCount + 1,
        finalSavedInput: text.isNotEmpty ? text : widget.initialEntry!.finalSavedInput,
      );
      logFor(widget.date).replace(widget.initialEntry!.section, widget.initialEntry!, entry);
      await PersistenceService.saveDayLogs();
      if (mounted) {
        Navigator.of(context).pop(entry);
      }
    }
  }

  Future<void> _confirm() async {
    if (_result == null || _result!.calories.max == 0) return;
    
    final text = _controller.text.trim();
    if (_result!.macrosLockedByUser) {
      final changed = text != _lastLockedText || AddMealScreen.hasParsedMealStructureChanged(_lastLockedText ?? '', text);
      if (changed) {
        final action = await showDialog<_LockedTextChangeAction>(
          context: context,
          builder: (_) => const _LockedTextChangeDialog(),
        );
        if (action == null) return;

        if (action == _LockedTextChangeAction.recalculate) {
          setState(() {
            _result = null;
            _lastLockedText = null;
          });
          _calculate();
          return;
        } else {
          setState(() {
            _lastLockedText = text;
          });
        }
      }
    }

    HapticFeedback.mediumImpact();
    final parsedFoods = _result!.items.map((i) => i.name).toList(growable: false);
    // edited=true when: (a) re-editing an existing entry, OR (b) user fixed macros on this new entry.
    final isEdited = widget.initialEntry != null || (_result?.macrosLockedByUser ?? false);
    final entry = MealEntry(
      rawInput: widget.initialEntry?.rawInput ?? text,
      result:   _result!,
      addedAt:  widget.initialEntry?.addedAt ?? DateTime.now(),
      section: widget.section,
      dayOfWeek: widget.date.weekday,
      parsedFoods: parsedFoods,
      edited: isEdited,
      editCount: (widget.initialEntry?.editCount ?? 0) + (widget.initialEntry != null ? 1 : 0),
      finalSavedInput: text,
    );
    if (widget.initialEntry != null) {
      logFor(widget.date).replace(widget.initialEntry!.section, widget.initialEntry!, entry);
    } else {
      logFor(widget.date).add(widget.section, entry);
    }
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  /// Shows a confirmation dialog then pops with [_DeleteSentinel] so the
  /// caller can remove the entry from the log and trigger a sync.
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
                    // ── Input field ──────────────────────────────
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

                    // ── Calculate button ─────────────────────────
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

            // ── Result card ──────────────────────────────────────
            if (_result != null)
              SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0, 0.06),
                              end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: Padding(
                    key: ValueKey(_result.hashCode),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _ResultPreview(
                      result:    _result!,
                      source:    _result!.source,
                      isEditing: widget.initialEntry != null,
                      onConfirm: _confirm,
                      onFix:     _fixEstimate,
                      onDelete:  widget.initialEntry != null ? _deleteEntry : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Result preview ───────────────────────────────────────────────────────────

class _ResultPreview extends StatelessWidget {
  final NutritionResult result;
  final String           source;
  final bool             isEditing;
  final VoidCallback     onConfirm;
  final VoidCallback     onFix;
  final VoidCallback?    onDelete;

  const _ResultPreview({
    required this.result,
    required this.source,
    required this.isEditing,
    required this.onConfirm,
    required this.onFix,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasFood = result.calories.max > 0;
    final userWarnings = result.userFacingWarnings;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasFood
              ? const Color(0xFF52B788).withValues(alpha: 0.35)
              : const Color(0xFF2E2E3E),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasFood)
            const _EmptyResultTile()
          else ...[
            // ── Source pill (clean, no debug text) ────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SourcePill(source: source),
                TextButton.icon(
                  onPressed: onFix,
                  icon: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF6B7280)),
                  label: const Text(
                    'Fix Estimate',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _PrimaryEstimateRow(result: result),
            const SizedBox(height: 14),

            // ── Per-item breakdown ───────────────────────────
            if (result.items.isNotEmpty) ...[
              const _SectionLabel('Breakdown'),
              const SizedBox(height: 10),
              ...result.items.map((item) => _ItemRow(item: item)),
              const Divider(color: Color(0xFF2E2E3E), height: 20),
            ],

            // ── Total macro chips ─────────────────────────────
            if (result.shouldShowRange) ...[
              const _SectionLabel('Likely range'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _MacroChip(
                    icon:  Icons.local_fire_department_rounded,
                    color: const Color(0xFFFF6B35),
                    label: _rangeLabel(
                        result.calories.min, result.calories.max, 'kcal'),
                  ),
                  const SizedBox(width: 10),
                  _MacroChip(
                    icon:  Icons.fitness_center_rounded,
                    color: const Color(0xFF52B788),
                    label: _rangeLabel(
                        result.protein.min, result.protein.max, 'g protein'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            _ConfidenceBar(confidence: result.confidence),
            if ((result.coachSummary ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                result.coachSummary!,
                style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 12.5, height: 1.45),
              ),
            ],
            if (userWarnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...userWarnings.map((w) => _WarningRow(text: w)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConfirm,
                icon: Icon(
                  isEditing ? Icons.save_rounded : Icons.add_rounded,
                  size: 18,
                ),
                label: Text(isEditing ? 'Save Changes' : 'Add to Log'),
              ),
            ),
            if (isEditing && onDelete != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                  label: const Text(
                    'Delete Entry',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFFEF4444),
                      width: 1.2,
                    ),
                    backgroundColor:
                        const Color(0xFFEF4444).withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Returns "235 kcal" when min == max, else "230–240 kcal".
String _rangeLabel(double min, double max, String unit) {
  final minI = min.toInt();
  final maxI = max.toInt();
  return minI == maxI ? '$minI $unit' : '$minI–$maxI $unit';
}

// ─── Source pill — minimal, clean ────────────────────────────────────────────

class _SourcePill extends StatelessWidget {
  final String source;
  const _SourcePill({required this.source});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (source) {
      'memory_exact' => (Icons.bookmark_rounded, const Color(0xFF60A5FA)),
      'cache' || 'memory_recurring' => (Icons.history_rounded, const Color(0xFF52B788)),
      'ai' || 'gemini' => (Icons.auto_awesome_rounded, const Color(0xFFA78BFA)),
      _ => (Icons.restaurant_menu_rounded, const Color(0xFF6B7280)),
    };

    final label = switch (source) {
      'memory_exact' => 'Using saved food memory',
      'cache' || 'memory_recurring' => 'Based on your usual foods',
      'ai' || 'gemini' => 'AI-assisted estimate',
      _ => 'Estimated from common foods',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _PrimaryEstimateRow extends StatelessWidget {
  final NutritionResult result;
  const _PrimaryEstimateRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final cal = result.primaryCaloriesEstimate.toInt();
    final pro = result.primaryProteinEstimate.toInt();
    final calHasRange = result.calories.min.toInt() != result.calories.max.toInt();
    final proHasRange = result.protein.min.toInt() != result.protein.max.toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Primary estimate'),
        const SizedBox(height: 8),
        Text(
          '$cal kcal • $pro g protein',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (result.shouldShowRange && (calHasRange || proHasRange))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${result.estimateLabel} • likely ${_rangeLabel(result.calories.min, result.calories.max, 'kcal')} • ${_rangeLabel(result.protein.min, result.protein.max, 'g protein')}',
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Item breakdown row ───────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  final NutritionItem item;
  const _ItemRow({required this.item});

  /// Formats quantity cleanly: drops ".0" suffix for whole numbers.
  /// Examples: 1.0 -> "1", 150.0 -> "150", 1.5 -> "1.5"
  static String _fmtQty(double qty) {
    if (qty == qty.truncateToDouble()) return qty.toInt().toString();
    return qty.toString();
  }

  /// Builds the display label: "150 g tofu", "1 scoop whey", "2 roti"
  /// Falls back to just the name when quantity is 0 or unit is empty.
  String get _displayLabel {
    final qty = item.quantity;
    final unit = item.unit.trim();
    final name = item.name.trim();
    if (qty <= 0 || unit.isEmpty) return name;
    return '${_fmtQty(qty)} $unit $name';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 5, color: Color(0xFF4B5563)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _displayLabel,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            ),
          ),
          Text(
            _rangeLabel(item.calories.min, item.calories.max, 'kcal'),
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFFF6B35),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            _rangeLabel(item.protein.min, item.protein.max, 'g'),
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF52B788),
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Shared mini-widgets ──────────────────────────────────────────────────────

class _EmptyResultTile extends StatelessWidget {
  const _EmptyResultTile();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.warning_amber_rounded,
            color: Color(0xFFFFB347), size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'No food recognised — try rephrasing.',
            style: TextStyle(color: Color(0xFFFFB347), fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _MacroChip extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   label;
  const _MacroChip(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              )),
        ],
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});

  Color _color() {
    if (confidence >= 0.75) return const Color(0xFF52B788);
    if (confidence >= 0.55) return const Color(0xFFFFB347);
    return const Color(0xFFFF6B6B);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Accuracy',
                style: TextStyle(
                    fontSize: 11,
                    color: _color(),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
            Text('${(confidence * 100).toInt()}%',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: confidence),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 5,
              backgroundColor: const Color(0xFF2E2E3E),
              valueColor: AlwaysStoppedAnimation(_color()),
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningRow extends StatelessWidget {
  final String text;
  const _WarningRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded,
                size: 13, color: Color(0xFFFFB347)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFFB347),
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: 1.1,
        ));
  }
}

// ─── Fix Estimate Sheet (bottom sheet for manual adjustments) ─────────────────

class _FixEstimateSheet extends StatefulWidget {
  final List<NutritionItem> items;
  final String canonicalMeal;
  final double initialCal;
  final double initialPro;
  final double? initialCarbs;
  final double? initialFat;
  final double? initialFiber;

  const _FixEstimateSheet({
    required this.items,
    required this.canonicalMeal,
    required this.initialCal,
    required this.initialPro,
    this.initialCarbs,
    this.initialFat,
    this.initialFiber,
  });

  @override
  State<_FixEstimateSheet> createState() => _FixEstimateSheetState();
}

class _FixEstimateSheetState extends State<_FixEstimateSheet> {
  late final List<NutritionItem> _displayItems;
  final List<TextEditingController> _calCtrls   = [];
  final List<TextEditingController> _proCtrls   = [];
  final List<TextEditingController> _carbCtrls  = [];
  final List<TextEditingController> _fatCtrls   = [];
  final List<TextEditingController> _fibCtrls   = [];
  String? _validationWarning;

  @override
  void initState() {
    super.initState();
    if (widget.items.isEmpty) {
      _displayItems = [
        NutritionItem(
          name: widget.canonicalMeal,
          quantity: 1.0,
          unit: 'serving',
          estimated: true,
          mode: EstimationMode.contextualIntake,
          calories: NutrientRange(min: widget.initialCal, max: widget.initialCal),
          protein:  NutrientRange(min: widget.initialPro, max: widget.initialPro),
        )
      ];
    } else {
      _displayItems = List.from(widget.items);
    }

    // Distribute initial totals proportionally across items if multi-item.
    final totalCalFromItems = _displayItems.fold<double>(0, (s, it) => s + (it.calories.min + it.calories.max) / 2);

    for (int i = 0; i < _displayItems.length; i++) {
      final item = _displayItems[i];
      final calMid  = (item.calories.min + item.calories.max) / 2;
      final proMid  = (item.protein.min  + item.protein.max)  / 2;
      final carbMid = (item.carbohydrates != null)
          ? (item.carbohydrates!.min + item.carbohydrates!.max) / 2
          : (widget.initialCarbs != null
              ? widget.initialCarbs! * (totalCalFromItems > 0 ? calMid / totalCalFromItems : 1)
              : NutritionResult.estimateCarbsLocally(calMid, proMid, item.name).min);
      final fatMid  = (item.fat != null)
          ? (item.fat!.min + item.fat!.max) / 2
          : (widget.initialFat != null
              ? widget.initialFat! * (totalCalFromItems > 0 ? calMid / totalCalFromItems : 1)
              : NutritionResult.estimateFatLocally(calMid, proMid, item.name).min);
      final fibMid  = (item.fiber != null)
          ? (item.fiber!.min + item.fiber!.max) / 2
          : (widget.initialFiber != null
              ? widget.initialFiber! * (totalCalFromItems > 0 ? calMid / totalCalFromItems : 1)
              : NutritionResult.estimateFiberLocally(calMid, item.name).min);

      _calCtrls.add(TextEditingController(text: calMid.toStringAsFixed(0)));
      _proCtrls.add(TextEditingController(text: proMid.toStringAsFixed(1)));
      _carbCtrls.add(TextEditingController(text: carbMid.toStringAsFixed(1)));
      _fatCtrls.add(TextEditingController(text: fatMid.toStringAsFixed(1)));
      _fibCtrls.add(TextEditingController(text: fibMid.toStringAsFixed(1)));
    }

    // Listen to any field change to re-validate.
    for (final ctrl in [..._calCtrls, ..._proCtrls, ..._carbCtrls, ..._fatCtrls, ..._fibCtrls]) {
      ctrl.addListener(_validate);
    }
  }

  @override
  void dispose() {
    for (final c in [..._calCtrls, ..._proCtrls, ..._carbCtrls, ..._fatCtrls, ..._fibCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Warns when macro-derived calories diverge from entered calories by > 15%.
  void _validate() {
    double totalCal = 0, totalPro = 0, totalCarb = 0, totalFat = 0;
    for (int i = 0; i < _displayItems.length; i++) {
      totalCal  += double.tryParse(_calCtrls[i].text)  ?? 0;
      totalPro  += double.tryParse(_proCtrls[i].text)  ?? 0;
      totalCarb += double.tryParse(_carbCtrls[i].text) ?? 0;
      totalFat  += double.tryParse(_fatCtrls[i].text)  ?? 0;
    }
    final impliedCal = totalPro * 4 + totalCarb * 4 + totalFat * 9;
    String? warning;
    if (totalCal > 0 && impliedCal > 0) {
      final deviation = ((impliedCal - totalCal) / totalCal).abs();
      if (deviation > 0.15) {
        warning = 'Macro totals imply ~${impliedCal.toStringAsFixed(0)} kcal but '
            'you entered ${totalCal.toStringAsFixed(0)} kcal. '
            'Check your values — protein×4 + carbs×4 + fat×9 should equal calories.';
      }
    }
    if (warning != _validationWarning) setState(() => _validationWarning = warning);
  }

  void _submit() {
    double totalCal = 0, totalPro = 0, totalCarb = 0, totalFat = 0, totalFib = 0;
    final updatedItems = <NutritionItem>[];

    for (int i = 0; i < _displayItems.length; i++) {
      final item = _displayItems[i];
      final calMid  = (item.calories.min + item.calories.max) / 2;

      // Use user-entered values exactly — no ratio scaling.
      final cVal  = double.tryParse(_calCtrls[i].text)  ?? calMid;
      final pVal  = double.tryParse(_proCtrls[i].text)  ?? ((item.protein.min + item.protein.max) / 2);
      final carbVal = double.tryParse(_carbCtrls[i].text) ?? 0;
      final fatVal  = double.tryParse(_fatCtrls[i].text)  ?? 0;
      final fibVal  = double.tryParse(_fibCtrls[i].text)  ?? 0;

      totalCal  += cVal;
      totalPro  += pVal;
      totalCarb += carbVal;
      totalFat  += fatVal;
      totalFib  += fibVal;

      // Preserve sugar / sat-fat / sodium via proportional scale on original cal.
      final scale = calMid > 0 ? cVal / calMid : 1.0;
      final sugar = item.sugar != null
          ? NutrientRange(min: double.parse((item.sugar!.min * scale).toStringAsFixed(1)),
                          max: double.parse((item.sugar!.max * scale).toStringAsFixed(1)))
          : null;
      final saturatedFat = item.saturatedFat != null
          ? NutrientRange(min: double.parse((item.saturatedFat!.min * scale).toStringAsFixed(1)),
                          max: double.parse((item.saturatedFat!.max * scale).toStringAsFixed(1)))
          : null;
      final sodium = item.sodium != null
          ? NutrientRange(min: double.parse((item.sodium!.min * scale).toStringAsFixed(1)),
                          max: double.parse((item.sodium!.max * scale).toStringAsFixed(1)))
          : null;

      updatedItems.add(NutritionItem(
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        estimated: true,
        mode: item.mode,
        calories: NutrientRange(min: cVal,    max: cVal),
        protein:  NutrientRange(min: pVal,    max: pVal),
        carbohydrates: NutrientRange(min: carbVal, max: carbVal),
        fat:   NutrientRange(min: fatVal,  max: fatVal),
        fiber: NutrientRange(min: fibVal,  max: fibVal),
        sugar: sugar,
        saturatedFat: saturatedFat,
        sodium: sodium,
      ));
    }
    Navigator.of(context).pop(
        _FixValues(updatedItems, totalCal, totalPro, totalCarb, totalFat, totalFib));
  }

  Widget _buildField(String label, TextEditingController ctrl, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1E1E2C),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F14),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Correct Macros',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 10, color: Color(0xFF60A5FA)),
                        SizedBox(width: 4),
                        Text(
                          'Becomes source of truth',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF60A5FA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'All five fields are editable. Values you enter will never be overwritten by AI.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7280), height: 1.4),
              ),
              const SizedBox(height: 20),
              // ── Per-item fields ─────────────────────────────────────
              ...List.generate(_displayItems.length, (i) {
                final item = _displayItems[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_displayItems.length > 1) ...[
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD1D5DB),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      // Row 1: Calories + Protein
                      Row(
                        children: [
                          Expanded(child: _buildField('Calories (kcal)', _calCtrls[i], const Color(0xFFFF6B35))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildField('Protein (g)', _proCtrls[i], const Color(0xFF52B788))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Row 2: Carbs + Fat
                      Row(
                        children: [
                          Expanded(child: _buildField('Carbs (g)', _carbCtrls[i], const Color(0xFF60A5FA))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildField('Fat (g)', _fatCtrls[i], const Color(0xFFFBBF24))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Row 3: Fiber (half-width)
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 50) / 2,
                        child: _buildField('Fiber (g)', _fibCtrls[i], const Color(0xFFA78BFA)),
                      ),
                    ],
                  ),
                );
              }),
              // ── Validation warning ──────────────────────────────────
              if (_validationWarning != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB347).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFFFB347), size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationWarning!,
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFFFB347),
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ── Apply button ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Apply Corrections',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


enum _CorrectionMode { applyCorrections, editIngredients }

class _CorrectionModeSheet extends StatelessWidget {
  const _CorrectionModeSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How would you like to correct this meal?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () => Navigator.pop(context, _CorrectionMode.applyCorrections),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E2E3E)),
                ),
                child: Row(
                  children: [
                    const Text('✏️', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Apply Corrections (Whole-meal)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enter total meal macros. Affects this entry only. Saves to no memory.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: const Color(0xFF9CA3AF),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF6B7280)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => Navigator.pop(context, _CorrectionMode.editIngredients),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E2E3E)),
                ),
                child: Row(
                  children: [
                    const Text('🔬', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Edit Ingredients',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Edit each ingredient separately. Saves to ingredient memory and updates eating patterns.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: const Color(0xFF9CA3AF),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF6B7280)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngredientEditResult {
  final List<NutritionItem> items;
  final List<NutritionItem> originalItems;
  final bool rememberEdits;
  _IngredientEditResult({
    required this.items,
    required this.originalItems,
    required this.rememberEdits,
  });
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

class _IngredientEditSheet extends StatefulWidget {
  final List<NutritionItem> items;
  final String canonicalMeal;

  const _IngredientEditSheet({
    required this.items,
    required this.canonicalMeal,
  });

  @override
  State<_IngredientEditSheet> createState() => _IngredientEditSheetState();
}

class _IngredientEditSheetState extends State<_IngredientEditSheet> {
  final List<_IngredientRow> _rows = [];
  bool _loading = true;
  bool _rememberEdits = true;
  String? _validationWarning;

  double _totalCal = 0;
  double _totalPro = 0;
  double _totalCarb = 0;
  double _totalFat = 0;
  double _totalFib = 0;

  @override
  void initState() {
    super.initState();
    _initRows();
  }

  bool _namesMatch(String nameA, String nameB) {
    final a = nameA.toLowerCase().trim();
    final b = nameB.toLowerCase().trim();
    if (a == b) return true;
    if (ItemParser.parse(a).length > 1 || ItemParser.parse(b).length > 1) {
      return false;
    }
    if (a.contains(b) || b.contains(a)) return true;
    final wordsA = a.split(' ');
    final wordsB = b.split(' ');
    for (final w in wordsA) {
      if (w.length > 3 && wordsB.contains(w)) return true;
    }
    return false;
  }

  Future<void> _initRows() async {
    setState(() => _loading = true);
    try {
      final initialItems = <NutritionItem>[];
      
      // Always parse the canonical meal to get the list of atomic ingredients
      final parsed = ItemParser.parse(widget.canonicalMeal);
      
      if (parsed.isNotEmpty) {
        for (final p in parsed) {
          // Check if we have a matching item in widget.items (by name match)
          NutritionItem? matchedItem;
          
          for (final item in widget.items) {
            if (_namesMatch(item.name, p.normalizedName)) {
              matchedItem = item;
              break;
            }
          }
          
          if (matchedItem != null) {
            initialItems.add(matchedItem);
          } else {
            // Estimate this item individually
            final itemStr = _constructItemString(p);
            final result = await NutritionPipeline.instance.estimateMeal(itemStr);
            
            // Extract the estimated item from result if available, or build a new one
            NutritionItem estItem;
            if (result.items.isNotEmpty) {
              final firstItem = result.items.first;
              estItem = NutritionItem(
                name: p.normalizedName,
                quantity: p.quantity,
                unit: p.unit,
                estimated: true,
                mode: firstItem.mode,
                calories: firstItem.calories,
                protein: firstItem.protein,
                carbohydrates: firstItem.carbohydrates,
                fat: firstItem.fat,
                fiber: firstItem.fiber,
                sugar: firstItem.sugar,
                saturatedFat: firstItem.saturatedFat,
                sodium: firstItem.sodium,
              );
            } else {
              estItem = NutritionItem(
                name: p.normalizedName,
                quantity: p.quantity,
                unit: p.unit,
                estimated: true,
                mode: EstimationMode.directQuantity,
                calories: result.calories,
                protein: result.protein,
                carbohydrates: result.carbohydrates,
                fat: result.fat,
                fiber: result.fiber,
                sugar: result.sugar,
                saturatedFat: result.saturatedFat,
                sodium: result.sodium,
              );
            }
            initialItems.add(estItem);
          }
        }
      } else {
        // Fallback: if parsed is empty, just use widget.items
        initialItems.addAll(widget.items);
      }
      
      // If still empty (e.g. canonicalMeal and items are both empty), add a default row
      if (initialItems.isEmpty) {
        final parsed = ParsedFoodItem(
          rawChunk: '1 serving food',
          normalizedName: 'food',
          quantity: 1.0,
          unit: 'serving',
        );
        final result = await NutritionPipeline.instance.estimateMeal(widget.canonicalMeal.isNotEmpty ? widget.canonicalMeal : 'food');
        initialItems.add(NutritionItem(
          name: parsed.normalizedName,
          quantity: parsed.quantity,
          unit: parsed.unit,
          estimated: true,
          mode: result.items.isNotEmpty ? result.items.first.mode : EstimationMode.directQuantity,
          calories: result.calories,
          protein: result.protein,
          carbohydrates: result.carbohydrates,
          fat: result.fat,
          fiber: result.fiber,
        ));
      }

      for (final item in initialItems) {
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
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _updateTotalsAndValidate();
      }
    }
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
            _validationWarning = 'Macro totals imply ~${impliedCal.toStringAsFixed(0)} kcal but '
                'running total is ${calSum.toStringAsFixed(0)} kcal. '
                'protein×4 + carbs×4 + fat×9 should equal calories.';
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

  void _submit() {
    final updatedItems = <NutritionItem>[];
    final originalItems = <NutritionItem>[];

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final cVal = double.tryParse(row.calCtrl.text) ?? 0;
      final pVal = double.tryParse(row.proCtrl.text) ?? 0;
      final carbVal = double.tryParse(row.carbCtrl.text) ?? 0;
      final fatVal = double.tryParse(row.fatCtrl.text) ?? 0;
      final fibVal = double.tryParse(row.fibCtrl.text) ?? 0;

      updatedItems.add(NutritionItem(
        name: row.parsed.normalizedName,
        quantity: row.parsed.quantity,
        unit: row.parsed.unit,
        estimated: true,
        mode: EstimationMode.directQuantity,
        calories: NutrientRange(min: cVal, max: cVal),
        protein: NutrientRange(min: pVal, max: pVal),
        carbohydrates: NutrientRange(min: carbVal, max: carbVal),
        fat: NutrientRange(min: fatVal, max: fatVal),
        fiber: NutrientRange(min: fibVal, max: fibVal),
      ));

      originalItems.add(NutritionItem(
        name: row.parsed.normalizedName,
        quantity: row.parsed.quantity,
        unit: row.parsed.unit,
        estimated: true,
        mode: EstimationMode.directQuantity,
        calories: NutrientRange(min: row.originalCalories, max: row.originalCalories),
        protein: NutrientRange(min: pVal, max: pVal),
      ));
    }

    Navigator.of(context).pop(_IngredientEditResult(
      items: updatedItems,
      originalItems: originalItems,
      rememberEdits: _rememberEdits,
    ));
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
            color: color.withValues(alpha: 0.85),
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
              borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
    return Container(
      color: const Color(0xFF0F0F14),
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF374151),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit Ingredients',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF52B788).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.memory_rounded, size: 10, color: Color(0xFF52B788)),
                        SizedBox(width: 4),
                        Text(
                          'Saves to Ingredient Memory',
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
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Correct individual ingredients or adjust split names below. Edits update memory & behavior scalars.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7280), height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF52B788),
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      ...List.generate(_rows.length, (i) {
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
                      }),
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
                            side: BorderSide(color: const Color(0xFF52B788).withValues(alpha: 0.3)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            if (!_loading)
              Container(
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
                          color: const Color(0xFFFFB347).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.4)),
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
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Apply Ingredient Corrections',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
}

enum _LockedTextChangeAction { recalculate, keep }

class _LockedTextChangeDialog extends StatelessWidget {
  const _LockedTextChangeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Meal Text Changed',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: const Text(
        'Meal text changed since manual corrections were applied. Recalculate before saving?',
        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_LockedTextChangeAction.keep),
          child: const Text(
            'Keep Manual Macros',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_LockedTextChangeAction.recalculate),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF52B788)),
          child: const Text(
            'Recalculate',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

