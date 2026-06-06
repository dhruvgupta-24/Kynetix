import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import '../models/quick_add_item.dart';
import '../services/nutrition_pipeline.dart';
import '../services/persistence_service.dart';
import '../services/quick_add_service.dart';
import '../services/meal_memory.dart';

// ─── HomeScreen (Redesigned as Quick Macro Estimator Sheet) ─────────────────
//
// Popup utility card / sheet that allows the user to log a meal directly
// with manual calories and macros or estimate them via plain text description using AI.
//
// Accessible via:
//   • Dashboard Card
//   • Floating Action Button
//   • Bottom Sheet from Add Meal flow
//
// Visual layout:
//   • Description / Name TextField
//   • Calorie and Macro fields of IDENTICAL HEIGHT (52px)
//   • Log to Journal action (with section dropdown)
//   • Save as Quick Add action

class HomeScreen extends StatefulWidget {
  final MealSection? initialSection;
  const HomeScreen({super.key, this.initialSection});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _descriptionController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();

  MealSection _selectedSection = MealSection.breakfast;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection ?? _getSectionForTime();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    super.dispose();
  }

  MealSection _getSectionForTime() {
    final now = DateTime.now();
    final h = now.hour;
    if (h < 11) return MealSection.breakfast;
    if (h < 16) return MealSection.lunch;
    if (h < 19) return MealSection.eveningSnack;
    if (h < 23) return MealSection.dinner;
    return MealSection.lateNight;
  }

  Future<void> _estimateWithAi() async {
    final desc = _descriptionController.text.trim();
    if (desc.isEmpty) return;

    setState(() => _loading = true);
    kHaptic();
    try {
      final result = await NutritionPipeline.instance.estimateMeal(desc);
      if (mounted) {
        _caloriesController.text = result.primaryCaloriesEstimate.round().toString();
        _proteinController.text = result.primaryProteinEstimate.round().toString();
        if (result.carbohydrates != null) {
          _carbsController.text = result.carbohydrates!.mid.round().toString();
        }
        if (result.fat != null) {
          _fatController.text = result.fat!.mid.round().toString();
        }
        if (result.fiber != null) {
          _fiberController.text = result.fiber!.mid.round().toString();
        }
        setState(() => _loading = false);
        kHapticMedium();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI Estimation failed: $e'), backgroundColor: KColor.danger),
        );
      }
    }
  }

  Future<void> _logToJournal() async {
    final name = _descriptionController.text.trim().isNotEmpty
        ? _descriptionController.text.trim()
        : 'Quick Meal';
    final calories = double.tryParse(_caloriesController.text) ?? 0.0;
    final protein = double.tryParse(_proteinController.text) ?? 0.0;
    final carbs = double.tryParse(_carbsController.text);
    final fat = double.tryParse(_fatController.text);
    final fiber = double.tryParse(_fiberController.text);

    final today = DateTime.now();
    final todayLog = logFor(today);
    final entry = MealEntry(
      rawInput: name,
      finalSavedInput: name,
      section: _selectedSection,
      addedAt: DateTime.now(),
      dayOfWeek: today.weekday,
      parsedFoods: [name],
      userCorrected: true,
      result: NutritionResult.createCustom(
        canonicalMeal: name,
        calories: calories,
        protein: protein,
        carbohydrates: carbs,
        fat: fat,
        fiber: fiber,
        source: 'quick_macro_estimator',
        userCorrected: true,
      ),
    );
    todayLog.add(_selectedSection, entry);

    MealMemory.instance.store(
      name,
      entry.result,
      finalSavedInput: name,
      canonicalMeal: name,
    ).ignore();

    await PersistenceService.saveDay(today);

    if (mounted) {
      kHapticMedium();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged "$name" to ${entry.section.displayName}'),
          backgroundColor: KColor.greenDark,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _saveAsQuickAdd() async {
    final name = _descriptionController.text.trim().isNotEmpty
        ? _descriptionController.text.trim()
        : 'Quick Meal';
    final calories = double.tryParse(_caloriesController.text) ?? 0.0;
    final protein = double.tryParse(_proteinController.text) ?? 0.0;

    final item = QuickAddItem(
      id: QuickAddService.instance.generateUuid(),
      name: name,
      calories: calories,
      protein: protein,
      emoji: '⚡',
      builtIn: false,
    );
    await QuickAddService.instance.saveItem(item);

    if (mounted) {
      kHapticMedium();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "$name" to Quick Add!'),
          backgroundColor: KColor.greenDark,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required Color color,
  }) {
    return Container(
      height: 52, // Identical heights for all calorie and macro inputs!
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E3E), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 8),
                border: InputBorder.none,
                hintText: '0',
                hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                labelText: label.toUpperCase(),
                labelStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
          ),
          Text(
            suffix,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMealSectionDropdown() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E3E), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MealSection>(
          value: _selectedSection,
          dropdownColor: const Color(0xFF1E1E2C),
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white),
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          onChanged: (val) {
            if (val != null) setState(() => _selectedSection = val);
          },
          items: MealSection.values
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.displayName),
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13131F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF2A2A3C), width: 0.5)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KDragHandle(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Quick Macro Estimator',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Input macros manually or estimate with AI',
                      style: TextStyle(fontSize: 12, color: KColor.textMuted),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: KColor.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description textfield
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Meal Description / Name',
                labelStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                hintText: 'e.g. 2 eggs and a banana',
                hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                filled: true,
                fillColor: const Color(0xFF1E1E2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2E2E3E), width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2E2E3E), width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: KColor.green, width: 1),
                ),
                suffixIcon: _descriptionController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: KColor.textMuted, size: 18),
                        onPressed: () {
                          _descriptionController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: KColor.green),
                      )
                    : TextButton.icon(
                        onPressed: _descriptionController.text.trim().isEmpty ? null : _estimateWithAi,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                        label: const Text('Estimate with AI'),
                        style: TextButton.styleFrom(
                          foregroundColor: KColor.green,
                          disabledForegroundColor: KColor.textDisabled,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 8),

            // Calories & Protein Row (Identical 52px heights)
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    controller: _caloriesController,
                    label: 'Calories',
                    suffix: 'kcal',
                    color: KColor.calorie,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildField(
                    controller: _proteinController,
                    label: 'Protein',
                    suffix: 'g',
                    color: KColor.protein,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Carbs, Fat, and Fiber Row (Identical 52px heights)
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    controller: _carbsController,
                    label: 'Carbs',
                    suffix: 'g',
                    color: KColor.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildField(
                    controller: _fatController,
                    label: 'Fat',
                    suffix: 'g',
                    color: const Color(0xFFE9D502),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildField(
                    controller: _fiberController,
                    label: 'Fiber',
                    suffix: 'g',
                    color: const Color(0xFFA78BFA),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Divider(color: KColor.divider, height: 1),
            const SizedBox(height: 16),

            // Dropdown selection
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LOGGING SECTION',
                  style: TextStyle(
                    color: KColor.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                _buildMealSectionDropdown(),
              ],
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: _saveAsQuickAdd,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: KColor.green, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Save as Quick Add',
                        style: TextStyle(color: KColor.green, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Pressable(
                    onTap: _logToJournal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [KColor.greenDark, KColor.green],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: KColor.greenDark.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Log to Journal',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
