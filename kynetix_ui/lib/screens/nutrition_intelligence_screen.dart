import 'package:flutter/material.dart';
import '../services/eating_pattern_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/food_role_classifier.dart';

class NutritionIntelligenceScreen extends StatefulWidget {
  const NutritionIntelligenceScreen({super.key});

  @override
  State<NutritionIntelligenceScreen> createState() => _NutritionIntelligenceScreenState();
}

class _NutritionIntelligenceScreenState extends State<NutritionIntelligenceScreen> {
  Future<void> _resetPattern(LearnedPatternEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Reset Pattern',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to reset the learned behavior pattern for "${entry.key}"?',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      EatingPatternService.instance.resetPattern(
        entry.key.targetRole,
        contextRole: entry.key.contextRole,
      );
      await EatingPatternService.instance.save();
      setState(() {});
    }
  }

  Future<void> _deleteOverride(UserMealOverride override) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete Food Memory',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete the customized override for "${override.canonicalMeal}"? It will revert to AI estimates.',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await UserNutritionMemory.instance.deleteOverride(override.canonicalMeal);
      setState(() {});
    }
  }

  Future<void> _resetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Reset All Patterns & Memory',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will permanently delete all learned eating patterns, customized ingredients, and food memory. This action cannot be undone.',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Reset All', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      EatingPatternService.instance.resetAll();
      await EatingPatternService.instance.save();
      for (final override in UserNutritionMemory.instance.allOverrides.toList()) {
        await UserNutritionMemory.instance.deleteOverride(override.canonicalMeal);
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All personalizations reset successfully.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final patterns = EatingPatternService.instance.allLearned;
    final overrides = UserNutritionMemory.instance.allOverrides;

    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Nutrition Intelligence',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
            tooltip: 'Reset all intelligence',
            onPressed: (patterns.isNotEmpty || overrides.isNotEmpty) ? _resetAll : null,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Section 1: Eating patterns ─────────────────────────────────
            Row(
              children: [
                const Text('🧠', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'LEARNED EATING PATTERNS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B7280),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (patterns.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E2E3E)),
                ),
                child: const Text(
                  'No eating patterns learned yet. Correct ingredient estimates via "Edit Ingredients" 3+ times to train the system.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5, height: 1.4),
                ),
              )
            else
              ...patterns.map((entry) {
                final color = entry.scalar < 1.0 ? const Color(0xFF52B788) : const Color(0xFFFF6B35);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildRoleBadge(entry.key.targetRole),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF6B7280)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _resetPattern(entry),
                            tooltip: 'Reset pattern',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        entry.explanation,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      // Stats row
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('SCALAR', style: TextStyle(fontSize: 8, color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                '${entry.scalar.toStringAsFixed(2)}×',
                                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('CONFIDENCE', style: TextStyle(fontSize: 8, color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                '${(entry.confidence * 100).toInt()}%',
                                style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('UPDATED', style: TextStyle(fontSize: 8, color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                '${DateTime.now().difference(entry.lastUpdated).inDays}d ago',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 28),

            // ── Section 2: Stored Ingredient memory ─────────────────────────────
            Row(
              children: [
                const Text('🥛', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'STORED FOOD MEMORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B7280),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (overrides.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E2E3E)),
                ),
                child: const Text(
                  'No custom ingredient overrides saved yet. Save corrections with "Remember for next time" checked to save them here.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5, height: 1.4),
                ),
              )
            else
              ...overrides.map((override) {
                final carbs = override.carbohydratesPerUnit != null ? (override.carbohydratesPerUnit! * override.referenceQuantity) : null;
                final fat = override.fatPerUnit != null ? (override.fatPerUnit! * override.referenceQuantity) : null;
                final fiber = override.fiberPerUnit != null ? (override.fiberPerUnit! * override.referenceQuantity) : null;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              override.canonicalMeal,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _buildRoleBadge(FoodRoleClassifier.classify(override.canonicalMeal)),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _deleteOverride(override),
                                tooltip: 'Delete food memory',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Portions info
                      Text(
                        '1 unit = ${override.referenceQuantity == override.referenceQuantity.truncate() ? override.referenceQuantity.toInt().toString() : override.referenceQuantity} ${override.referenceUnit}',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      // Macros row
                      Row(
                        children: [
                          _buildMiniMacro('CAL', '${(override.caloriesPerUnit * override.referenceQuantity).toInt()}', const Color(0xFFFF6B35)),
                          const SizedBox(width: 16),
                          _buildMiniMacro('PRO', '${(override.proteinPerUnit * override.referenceQuantity).toStringAsFixed(1)}g', const Color(0xFF52B788)),
                          const SizedBox(width: 16),
                          if (carbs != null) ...[
                            _buildMiniMacro('CARB', '${carbs.toStringAsFixed(0)}g', const Color(0xFF60A5FA)),
                            const SizedBox(width: 16),
                          ],
                          if (fat != null) ...[
                            _buildMiniMacro('FAT', '${fat.toStringAsFixed(0)}g', const Color(0xFFFBBF24)),
                            const SizedBox(width: 16),
                          ],
                          if (fiber != null)
                            _buildMiniMacro('FIB', '${fiber.toStringAsFixed(1)}g', const Color(0xFFA78BFA)),
                        ],
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 28),

            // ── Section 3: Eating Context Stats ─────────────────────────────
            Row(
              children: [
                const Text('📊', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'MEAL CONTEXT INSIGHTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B7280),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E2E3E)),
              ),
              child: Column(
                children: [
                  _buildStatRow('Total meals tracked contextually', '${EatingPatternService.instance.totalMealsTracked}'),
                  const Divider(color: Color(0xFF2E2E3E), height: 24),
                  _buildStatRow('Most common primary carb base', EatingPatternService.instance.dominantPrimaryFood),
                  const Divider(color: Color(0xFF2E2E3E), height: 24),
                  _buildStatRow('Avg primary portion per log', '${EatingPatternService.instance.avgPrimaryPortionPerLog.toStringAsFixed(1)} units'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _buildMiniMacro(String name, String val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
