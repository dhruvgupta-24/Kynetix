import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/eating_pattern_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/food_role_classifier.dart';

class NutritionIntelligenceScreen extends StatefulWidget {
  const NutritionIntelligenceScreen({super.key});

  @override
  State<NutritionIntelligenceScreen> createState() => _NutritionIntelligenceScreenState();
}

class _SectionHeader {
  final String title;
  final String emoji;
  const _SectionHeader({required this.title, required this.emoji});
}

class _EmptyState {
  final String message;
  const _EmptyState({required this.message});
}

class _InsightsCard {
  const _InsightsCard();
}

class _NutritionIntelligenceScreenState extends State<NutritionIntelligenceScreen> {
  int _selectedTab = 0; // 0 = All, 1 = Customized, 2 = Learned
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text;
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetPattern(LearnedPatternEntry entry) async {
    kHapticMedium();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KColor.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Reset Portion Pattern',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to reset the learned portion adjustment pattern for "${entry.key}"?',
          style: const TextStyle(color: KColor.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: KColor.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: KColor.danger),
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
    kHapticMedium();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KColor.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Remove Custom Food',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to remove the custom ingredients for "${override.canonicalMeal}"? It will revert to standard estimates.',
          style: const TextStyle(color: KColor.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: KColor.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: KColor.danger),
            child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
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
    kHapticMedium();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KColor.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Clear Food Library & Portions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will permanently clear all portion history and custom foods in your Food Library. This cannot be undone.',
          style: TextStyle(color: KColor.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: KColor.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: KColor.danger),
            child: const Text('Clear All', style: TextStyle(fontWeight: FontWeight.bold)),
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
            content: Text('All Food Library customizations have been cleared.'),
            backgroundColor: KColor.danger,
          ),
        );
      }
    }
  }

  Widget _buildRoleBadge(FoodRole role) {
    final (label, color) = switch (role) {
      FoodRole.primary       => ('Base/Carb', KColor.blue),
      FoodRole.protein       => ('Protein', KColor.protein),
      FoodRole.accompaniment => ('Side/Curry', KColor.amber),
      FoodRole.addOn         => ('Add-on', const Color(0xFFA78BFA)),
      FoodRole.completeMeal  => ('Single Unit', KColor.textSecondary),
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

  Widget _buildSectionHeader(_SectionHeader item) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            item.title,
            style: KText.label,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(_EmptyState item) {
    return KCard(
      padding: const EdgeInsets.all(16),
      child: Text(
        item.message,
        style: const TextStyle(color: KColor.textSecondary, fontSize: 13, height: 1.4),
      ),
    );
  }

  Widget _buildPatternCard(LearnedPatternEntry entry) {
    final color = entry.scalar < 1.0 ? KColor.protein : KColor.calorie;
    return Dismissible(
      key: Key('pattern_${entry.key.targetRole?.name ?? "none"}_${entry.key.contextRole?.name ?? "none"}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: KColor.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.refresh_rounded, color: KColor.danger),
      ),
      confirmDismiss: (_) async {
        await _resetPattern(entry);
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: KCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildRoleBadge(entry.key.targetRole),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 16, color: KColor.textMuted),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _resetPattern(entry),
                    tooltip: 'Reset Portion Pattern',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                entry.explanation,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Portion Scale', style: TextStyle(fontSize: 8, color: KColor.textMuted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${entry.scalar.toStringAsFixed(2)}×',
                              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: (entry.scalar / 2.0).clamp(0.0, 1.0),
                                  backgroundColor: KColor.border,
                                  valueColor: AlwaysStoppedAnimation<Color>(color),
                                  minHeight: 4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Reliability', style: TextStyle(fontSize: 8, color: KColor.textMuted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${(entry.confidence * 100).toInt()}%',
                              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: entry.confidence.clamp(0.0, 1.0),
                                  backgroundColor: KColor.border,
                                  valueColor: const AlwaysStoppedAnimation<Color>(KColor.protein),
                                  minHeight: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildOverrideCard(UserMealOverride override) {
    final carbs = override.carbohydratesPerUnit != null ? (override.carbohydratesPerUnit! * override.referenceQuantity) : null;
    final fat = override.fatPerUnit != null ? (override.fatPerUnit! * override.referenceQuantity) : null;
    final fiber = override.fiberPerUnit != null ? (override.fiberPerUnit! * override.referenceQuantity) : null;

    return Dismissible(
      key: Key('override_${override.canonicalMeal}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: KColor.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: KColor.danger),
      ),
      confirmDismiss: (_) async {
        await _deleteOverride(override);
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: KCard(
          padding: const EdgeInsets.all(16),
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
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: KColor.danger),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _deleteOverride(override),
                        tooltip: 'Remove Custom Food',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '1 unit = ${override.referenceQuantity == override.referenceQuantity.truncate() ? override.referenceQuantity.toInt().toString() : override.referenceQuantity} ${override.referenceUnit}',
                style: const TextStyle(color: KColor.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  _buildMiniMacro('CAL', '${(override.caloriesPerUnit * override.referenceQuantity).toInt()}', KColor.calorie),
                  _buildMiniMacro('PRO', '${(override.proteinPerUnit * override.referenceQuantity).toStringAsFixed(1)}g', KColor.protein),
                  if (carbs != null)
                    _buildMiniMacro('CARB', '${carbs.toStringAsFixed(0)}g', KColor.blue),
                  if (fat != null)
                    _buildMiniMacro('FAT', '${fat.toStringAsFixed(0)}g', KColor.amber),
                  if (fiber != null)
                    _buildMiniMacro('FIB', '${fiber.toStringAsFixed(1)}g', const Color(0xFFA78BFA)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: KCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatRow('Total meals tracked', '${EatingPatternService.instance.totalMealsTracked}'),
            const Divider(color: KColor.divider, height: 24),
            _buildStatRow('Common meal base', EatingPatternService.instance.dominantPrimaryFood),
            const Divider(color: KColor.divider, height: 24),
            _buildStatRow('Average portion size', '${EatingPatternService.instance.avgPrimaryPortionPerLog.toStringAsFixed(1)} units'),
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
            style: const TextStyle(fontSize: 12.5, color: KColor.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
          ),
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

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = (constraints.maxWidth) / 3;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: _selectedTab * tabWidth,
                width: tabWidth,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: KColor.cardHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildTabButton(0, 'All'),
                  _buildTabButton(1, 'Custom Foods'),
                  _buildTabButton(2, 'Portion History'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          kHapticSelect();
          setState(() {
            _selectedTab = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: isSelected ? Colors.white : KColor.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
              fontFamily: 'Inter',
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patterns = EatingPatternService.instance.allLearned;
    final overrides = UserNutritionMemory.instance.allOverrides;

    // Filter overrides
    final filteredOverrides = overrides.where((o) {
      if (_searchQuery.isEmpty) return true;
      return o.canonicalMeal.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Construct flat items list for the ListView.builder recycler
    final items = <Object>[];

    if (_selectedTab == 0) {
      // ALL
      items.add(const _SectionHeader(title: 'PORTION HISTORY', emoji: '🧠'));
      if (patterns.isEmpty) {
        items.add(const _EmptyState(message: 'No portion patterns learned yet. Edit ingredient estimates on logged meals to build portion history.'));
      } else {
        items.addAll(patterns);
      }

      items.add(const _SectionHeader(title: 'CUSTOM FOODS', emoji: '🥛'));
      if (filteredOverrides.isEmpty) {
        items.add(_EmptyState(
          message: _searchQuery.isEmpty 
              ? 'No custom foods found. Check "Remember for next time" when saving a meal.' 
              : 'No matching custom foods found.'
        ));
      } else {
        items.addAll(filteredOverrides);
      }

      items.add(const _SectionHeader(title: 'PORTION INSIGHTS', emoji: '📊'));
      items.add(const _InsightsCard());
    } else if (_selectedTab == 1) {
      // CUSTOMIZED
      if (filteredOverrides.isEmpty) {
        items.add(_EmptyState(
          message: _searchQuery.isEmpty 
              ? 'No custom foods found. Check "Remember for next time" when saving a meal.' 
              : 'No matching custom foods found.'
        ));
      } else {
        items.addAll(filteredOverrides);
      }
    } else if (_selectedTab == 2) {
      // LEARNED PATTERNS
      items.add(const _SectionHeader(title: 'PORTION HISTORY', emoji: '🧠'));
      if (patterns.isEmpty) {
        items.add(const _EmptyState(message: 'No portion patterns learned yet. Edit ingredient estimates on logged meals to build portion history.'));
      } else {
        items.addAll(patterns);
      }

      items.add(const _SectionHeader(title: 'PORTION INSIGHTS', emoji: '📊'));
      items.add(const _InsightsCard());
    }

    final showSearch = _selectedTab == 0 || _selectedTab == 1;

    return Scaffold(
      backgroundColor: KColor.bg,
      appBar: AppBar(
        backgroundColor: KColor.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Food Library',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: KColor.danger),
            tooltip: 'Reset Food Library',
            onPressed: (patterns.isNotEmpty || overrides.isNotEmpty) ? _resetAll : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _buildTabs(),
            ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: KColor.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KColor.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      icon: const Icon(Icons.search_rounded, color: KColor.textMuted, size: 18),
                      hintText: 'Search custom foods...',
                      hintStyle: const TextStyle(color: KColor.textMuted, fontSize: 13.5),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: KColor.textMuted, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                _searchCtrl.clear();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item is _SectionHeader) {
                    return _buildSectionHeader(item);
                  } else if (item is _EmptyState) {
                    return _buildEmptyState(item);
                  } else if (item is LearnedPatternEntry) {
                    return _buildPatternCard(item);
                  } else if (item is UserMealOverride) {
                    return _buildOverrideCard(item);
                  } else if (item is _InsightsCard) {
                    return _buildInsightsCard();
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
