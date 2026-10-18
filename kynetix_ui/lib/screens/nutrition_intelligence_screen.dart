import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../ui/k_segmented.dart';
import '../services/eating_pattern_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/food_role_classifier.dart';
import '../services/food_link_service.dart';
import 'app_shell.dart';

class NutritionIntelligenceScreen extends StatefulWidget {
  const NutritionIntelligenceScreen({super.key});

  @override
  State<NutritionIntelligenceScreen> createState() => _NutritionIntelligenceScreenState();
}

class _SectionHeader {
  final String title;
  final IconData icon;
  final String? count;
  const _SectionHeader({required this.title, required this.icon, this.count});
}

class _EmptyState {
  final String title;
  final String message;

  /// "Nothing matches this search" — offers to clear the query rather than
  /// pretending the library is empty.
  final bool isFiltered;
  const _EmptyState({required this.title, required this.message, this.isFiltered = false});
}

class _InsightsCard {
  const _InsightsCard();
}

const _kTabular = [FontFeature.tabularFigures()];

class _NutritionIntelligenceScreenState extends State<NutritionIntelligenceScreen> {
  int _selectedTab = 0; // 0 = All, 1 = Customized, 2 = Learned
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// The first list paints with one staggered entrance; later rebuilds (search,
  /// tab switches, scrolling) mount items already at rest.
  bool _revealDone = false;

  @override
  void initState() {
    super.initState();
    // The controller also notifies on cursor / selection moves; only a real
    // text change re-filters the list.
    _searchCtrl.addListener(() {
      if (!mounted || _searchCtrl.text == _searchQuery) return;
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

  // ─── Dialogs ────────────────────────────────────────────────────────────────

  Widget _confirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return AlertDialog(
      backgroundColor: KColor.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.xl,
        side: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
      ),
      icon: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: KColor.danger.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.restart_alt_rounded, color: KColor.danger, size: 22),
      ),
      title: Text(title, style: KText.h2, textAlign: TextAlign.center),
      content: Text(
        message,
        style: KText.body.copyWith(color: KColor.textSecondary, height: 1.45),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          child: Text('Cancel', style: KText.bodyMedium.copyWith(color: KColor.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: KColor.danger, minimumSize: const Size(64, 48)),
          child: Text(confirmLabel, style: KText.bodyMedium.copyWith(color: KColor.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Future<void> _resetPattern(LearnedPatternEntry entry) async {
    kHapticMedium();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _confirmDialog(
        context: context,
        title: 'Reset this pattern?',
        message: 'Kyno forgets what it learned for "${entry.key}" and goes back to standard portions.',
        confirmLabel: 'Reset',
      ),
    );

    if (confirmed == true) {
      EatingPatternService.instance.resetPattern(
        entry.key.targetRole,
        contextRole: entry.key.contextRole,
      );
      // Optimistic: the in-memory store is already updated, so the row goes
      // away this frame; the disk write follows.
      if (mounted) setState(() {});
      await EatingPatternService.instance.save();
    }
  }

  Future<void> _deleteOverride(UserMealOverride override) async {
    kHapticMedium();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _confirmDialog(
        context: context,
        title: 'Remove custom food?',
        message: 'Your numbers for "${override.canonicalMeal}" will be removed, and Kyno goes back to its own estimate.',
        confirmLabel: 'Remove',
      ),
    );

    if (confirmed == true) {
      // deleteOverride drops the in-memory entry synchronously; rebuild this
      // frame and let the disk write finish after.
      final done = UserNutritionMemory.instance.deleteOverride(override.canonicalMeal);
      if (mounted) setState(() {});
      await done;
    }
  }

  /// Unlink every older name from a scanned pack. The hidden entries come
  /// back as they were; Undo links them again.
  Future<void> _unlink(FoodLink link) async {
    kHapticSelect();
    final toaster = KToaster.of(context);
    final done = FoodLinkService.instance.unlink(link.barcode);
    if (mounted) setState(() {});
    await done;
    if (mounted) setState(() {});
    toaster.show(
      'Unlinked. Both names are separate again.',
      actionLabel: 'Undo',
      onAction: () async {
        for (final a in link.aliases) {
          await FoodLinkService.instance.link(link.product, a);
        }
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildLinkCard(FoodLink link) {
    final result = link.product.resultForAmount(link.portionGrams);
    final aliases = link.aliases.join(', ');
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.10 : 0.09))),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: KSpacing.xs, bottom: KSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 16, color: KColor.textMuted),
                const SizedBox(width: KSpacing.sm),
                Expanded(
                  child: Text(link.name, style: KText.h3.copyWith(fontSize: 15.5)),
                ),
                IconButton(
                  icon: Icon(Icons.link_off_rounded, size: 18, color: KColor.textSecondary),
                  onPressed: () => _unlink(link),
                  tooltip: 'Unlink',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: KSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Also logged as: $aliases',
                    style: KText.caption.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Per ${link.product.amountLabel(link.portionGrams)}, from the pack label',
                    style: KText.caption.copyWith(fontSize: 13, fontFeatures: _kTabular),
                  ),
                  const SizedBox(height: KSpacing.sm),
                  KDotStats([
                    KDotStat(whole(result.calories.mid), 'kcal', color: KColor.calorie),
                    KDotStat(amount(result.protein.mid), 'g protein', color: KColor.protein),
                    if (result.carbohydrates != null) KDotStat(whole(result.carbohydrates!.mid), 'g carbs', color: KColor.carbs),
                    if (result.fat != null) KDotStat(whole(result.fat!.mid), 'g fat', color: KColor.fat),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetAll() async {
    kHapticMedium();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _confirmDialog(
        context: context,
        title: 'Clear your food library?',
        message: 'This clears all portion history and custom foods for good. This can\'t be undone.',
        confirmLabel: 'Clear all',
      ),
    );

    if (confirmed == true) {
      EatingPatternService.instance.resetAll();
      // One write for every custom food instead of one write per food.
      final cleared = UserNutritionMemory.instance.deleteOverrides(
        UserNutritionMemory.instance.allOverrides
            .map((o) => o.canonicalMeal)
            .toList(),
      );
      if (mounted) setState(() {});
      await Future.wait([EatingPatternService.instance.save(), cleared]);
      if (mounted) {
        setState(() {});
        showKToast(context, 'Food library cleared. Fresh start.', kind: KToastKind.success);
      }
    }
  }

  // ─── Building blocks ────────────────────────────────────────────────────────

  Widget _buildRoleBadge(FoodRole role) {
    final (label, color) = switch (role) {
      FoodRole.primary       => ('Base or carb', KColor.carbs),
      FoodRole.protein       => ('Protein', KColor.protein),
      FoodRole.accompaniment => ('Side or curry', KColor.textSecondary),
      FoodRole.addOn         => ('Add-on', KColor.textMuted),
      FoodRole.completeMeal  => ('Single unit', KColor.textMuted),
    };
    // A quiet label keyed by a dot, not a tinted badge.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KDot(color: color, size: 6),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(_SectionHeader item) {
    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.xxl, bottom: KSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                item.title,
                style: KText.h2.copyWith(fontSize: 18),
              ),
            ),
          ),
          if (item.count != null)
            Text(item.count!, style: KText.numSmall.copyWith(color: KColor.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(_EmptyState item) {
    final action = item.isFiltered
        ? KTextAction('Clear search', onTap: () => _searchCtrl.clear())
        : (AppShell.addMealAction.value != null
            ? KTextAction('Log a meal', onTap: _logMealFromEmpty)
            : null);
    // Inline and left-aligned: an empty list is a sentence, not a poster.
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KHairline(),
          const SizedBox(height: KSpacing.md),
          Text(item.title, style: KText.h3.copyWith(fontSize: 16)),
          const SizedBox(height: 4),
          Text(item.message, style: KText.body.copyWith(fontSize: 14, color: KColor.textSecondary)),
          if (action != null) ...[
            const SizedBox(height: KSpacing.xs),
            Transform.translate(offset: const Offset(-4, 0), child: action),
          ],
        ],
      ),
    );
  }

  /// Empty-state action: back to the home tab, then open the same "Log a meal"
  /// flow the dock's + button uses.
  void _logMealFromEmpty() {
    final addMeal = AppShell.addMealAction.value;
    if (addMeal == null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    addMeal();
  }

  Widget _dismissBackground(IconData icon, String label) {
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: KSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [KColor.danger.withValues(alpha: 0), KColor.danger.withValues(alpha: KColor.isDark ? 0.2 : 0.14)],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: KText.bodyMedium.copyWith(color: KColor.danger, fontWeight: FontWeight.w600)),
          const SizedBox(width: KSpacing.sm),
          Icon(icon, color: KColor.danger),
        ],
      ),
    );
  }

  String _confidenceWord(double c) {
    if (c >= 0.75) return 'High';
    if (c >= 0.45) return 'Medium';
    return 'Low';
  }

  Widget _buildPatternCard(LearnedPatternEntry entry) {
    final color = KColor.textPrimary;
    final gradient = KGradient.primary;
    final direction = entry.scalar < 1.0
        ? 'Smaller portions'
        : (entry.scalar > 1.0 ? 'Larger portions' : 'Standard portions');
    final confidencePct = (entry.confidence * 100).toInt();

    return Dismissible(
      key: Key('pattern_${entry.key.targetRole.name}_${entry.key.contextRole?.name ?? "none"}'),
      direction: DismissDirection.endToStart,
      background: _dismissBackground(Icons.refresh_rounded, 'Reset'),
      confirmDismiss: (_) async {
        await _resetPattern(entry);
        return false;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.10 : 0.09))),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: KSpacing.xs, bottom: KSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: _buildRoleBadge(entry.key.targetRole)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh, size: 18, color: KColor.textMuted),
                    onPressed: () => _resetPattern(entry),
                    tooltip: 'Reset this pattern',
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: KSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.explanation,
                      style: KText.body.copyWith(color: KColor.textPrimary, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: KSpacing.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _MetricBlock(
                            label: 'Portion scale',
                            value: '${entry.scalar.toStringAsFixed(2)}×',
                            valueColor: color,
                            caption: direction,
                            progress: (entry.scalar / 2.0).clamp(0.0, 1.0),
                            colors: gradient,
                            semantics: 'Portion scale ${entry.scalar.toStringAsFixed(2)} times. $direction',
                          ),
                        ),
                        const SizedBox(width: KSpacing.lg),
                        Expanded(
                          child: _MetricBlock(
                            label: 'Reliability',
                            value: '$confidencePct%',
                            valueColor: KColor.textPrimary,
                            caption: '${_confidenceWord(entry.confidence)}, from ${plural(entry.sampleCount, 'meal')}',
                            progress: entry.confidence.clamp(0.0, 1.0),
                            colors: [KColor.textSecondary],
                            semantics: 'Reliability $confidencePct percent, ${_confidenceWord(entry.confidence)} confidence',
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
      background: _dismissBackground(Icons.delete_outline_rounded, 'Remove'),
      confirmDismiss: (_) async {
        await _deleteOverride(override);
        return false;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.10 : 0.09))),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: KSpacing.xs, bottom: KSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      override.canonicalMeal,
                      style: KText.h3.copyWith(fontSize: 15.5),
                    ),
                  ),
                  const SizedBox(width: KSpacing.sm),
                  _buildRoleBadge(FoodRoleClassifier.classify(override.canonicalMeal)),
                  IconButton(
                    icon: Icon(KIcons.delete, size: 18, color: KColor.danger),
                    onPressed: () => _deleteOverride(override),
                    tooltip: 'Remove custom food',
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: KSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Per ${amount(override.referenceQuantity)} ${override.referenceUnit}',
                      style: KText.caption.copyWith(fontSize: 13, fontFeatures: _kTabular),
                    ),
                    const SizedBox(height: KSpacing.sm),
                    KDotStats([
                      KDotStat(whole(override.caloriesPerUnit * override.referenceQuantity), 'kcal', color: KColor.calorie),
                      KDotStat(amount(override.proteinPerUnit * override.referenceQuantity), 'g protein', color: KColor.protein),
                      if (carbs != null) KDotStat(whole(carbs), 'g carbs', color: KColor.carbs),
                      if (fat != null) KDotStat(whole(fat), 'g fat', color: KColor.fat),
                      if (fiber != null) KDotStat(amount(fiber), 'g fiber', color: KColor.fiber),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.md),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _buildStatRow(Icons.receipt_long_outlined, KColor.textSecondary, 'Total meals tracked', '${EatingPatternService.instance.totalMealsTracked}'),
            const _Hairline(),
            _buildStatRow(Icons.rice_bowl_outlined, KColor.textSecondary, 'Common meal base', EatingPatternService.instance.dominantPrimaryFood),
            const _Hairline(),
            _buildStatRow(Icons.straighten_outlined, KColor.textSecondary, 'Average portion size', '${EatingPatternService.instance.avgPrimaryPortionPerLog.toStringAsFixed(1)} units'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
      child: Row(
        children: [
          KIcon(icon, size: 18),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Text(label, style: KText.bodyMedium.copyWith(fontSize: 14, color: KColor.textSecondary)),
          ),
          const SizedBox(width: KSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: KText.numSmall.copyWith(fontSize: 15, color: KColor.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return KSegmented<int>(
      segments: const [
        KSegment(0, 'All'),
        KSegment(1, 'Custom foods'),
        KSegment(2, 'Portion history'),
      ],
      value: _selectedTab,
      onChanged: (index) {
        setState(() {
          _selectedTab = index;
        });
      },
    );
  }

  Widget _buildSummary(int patternCount, int overrideCount) {
    Widget stat(IconData icon, Color color, String value, String label) {
      return Expanded(
        child: Semantics(
          label: '$value $label',
          excludeSemantics: true,
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: KSpacing.sm),
              Text(value, style: KText.numMedium.copyWith(fontSize: 24)),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: KText.caption.copyWith(fontSize: 13))),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        stat(Icons.tune_rounded, KColor.textMuted, '$patternCount', patternCount == 1 ? 'pattern learned' : 'patterns learned'),
        const SizedBox(width: KSpacing.md),
        stat(Icons.restaurant_menu_rounded, KColor.textMuted, '$overrideCount', overrideCount == 1 ? 'custom food' : 'custom foods'),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      style: KText.body.copyWith(color: KColor.textPrimary, fontSize: 14),
      cursorColor: KColor.ink,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        filled: true,
        fillColor: KColor.isDark ? KColor.surface.withValues(alpha: 0.85) : KColor.card,
        prefixIcon: Icon(Icons.search_rounded, color: KColor.textMuted, size: 20),
        hintText: 'Search custom foods',
        hintStyle: KText.body.copyWith(color: KColor.textMuted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: KSpacing.lg),
        border: OutlineInputBorder(
          borderRadius: KRadius.md,
          borderSide: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: KRadius.md,
          borderSide: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: KRadius.md,
          borderSide: BorderSide(color: KColor.ink, width: 1.4),
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: Icon(Icons.clear_rounded, color: KColor.textMuted, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                },
              )
            : null,
      ),
    );
  }

  Widget _buildItem(Object item) {
    if (item is _SectionHeader) {
      return _buildSectionHeader(item);
    } else if (item is _EmptyState) {
      return _buildEmptyState(item);
    } else if (item is LearnedPatternEntry) {
      return _buildPatternCard(item);
    } else if (item is UserMealOverride) {
      return _buildOverrideCard(item);
    } else if (item is FoodLink) {
      return _buildLinkCard(item);
    } else if (item is _InsightsCard) {
      return _buildInsightsCard();
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final patterns = EatingPatternService.instance.allLearned;
    // Older names linked to a scanned pack show under that pack instead
    // (hidden here, never deleted).
    final overrides = UserNutritionMemory.instance.allOverrides
        .where((o) => !FoodLinkService.instance.isHidden(o.canonicalMeal))
        .toList();
    final links = FoodLinkService.instance.links;

    // Filter overrides
    final query = _searchQuery.toLowerCase();
    final filteredOverrides = query.isEmpty
        ? overrides.toList()
        : overrides
            .where((o) => o.canonicalMeal.toLowerCase().contains(query))
            .toList();
    final filteredLinks = query.isEmpty
        ? links
        : links
            .where((l) => [l.name, ...l.aliases].any((n) => n.toLowerCase().contains(query)))
            .toList();

    const patternsEmpty = _EmptyState(
      title: 'No patterns yet',
      message: 'Tweak the numbers on a meal you log and Kyno picks up your usual portions.',
    );
    final overridesEmpty = _searchQuery.isEmpty
        ? const _EmptyState(
            title: 'No custom foods yet',
            message: 'Turn on "Remember my numbers for next time" when you log a meal, and it lands here.',
          )
        : const _EmptyState(
            title: 'Nothing matches',
            message: 'No custom foods match that. Try another word.',
            isFiltered: true,
          );

    // Construct flat items list for the ListView.builder recycler
    final items = <Object>[];

    if (_selectedTab == 0) {
      // ALL
      items.add(_SectionHeader(title: 'Portion history', icon: Icons.psychology_rounded, count: patterns.isEmpty ? null : '${patterns.length}'));
      if (patterns.isEmpty) {
        items.add(patternsEmpty);
      } else {
        items.addAll(patterns);
      }

      items.add(_SectionHeader(title: 'Custom foods', icon: Icons.restaurant_menu_rounded, count: filteredOverrides.isEmpty ? null : '${filteredOverrides.length}'));
      if (filteredOverrides.isEmpty) {
        items.add(overridesEmpty);
      } else {
        items.addAll(filteredOverrides);
      }

      if (filteredLinks.isNotEmpty) {
        items.add(_SectionHeader(title: 'Linked foods', icon: Icons.link_rounded, count: '${filteredLinks.length}'));
        items.addAll(filteredLinks);
      }

      items.add(const _SectionHeader(title: 'Portion insights', icon: Icons.insights_rounded));
      items.add(const _InsightsCard());
    } else if (_selectedTab == 1) {
      // CUSTOMIZED
      if (filteredOverrides.isEmpty) {
        items.add(overridesEmpty);
      } else {
        items.addAll(filteredOverrides);
      }
      if (filteredLinks.isNotEmpty) {
        items.add(_SectionHeader(title: 'Linked foods', icon: Icons.link_rounded, count: '${filteredLinks.length}'));
        items.addAll(filteredLinks);
      }
    } else if (_selectedTab == 2) {
      // LEARNED PATTERNS
      items.add(_SectionHeader(title: 'Portion history', icon: Icons.psychology_rounded, count: patterns.isEmpty ? null : '${patterns.length}'));
      if (patterns.isEmpty) {
        items.add(patternsEmpty);
      } else {
        items.addAll(patterns);
      }

      items.add(const _SectionHeader(title: 'Portion insights', icon: Icons.insights_rounded));
      items.add(const _InsightsCard());
    }

    final showSearch = _selectedTab == 0 || _selectedTab == 1;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final playReveal = !_revealDone;
    if (playReveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealDone = true);
    }

    return KPage(
      tone: KTone.fuel,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: KColor.textPrimary,
        title: Text('Food library', style: KText.h2),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            color: KColor.danger,
            disabledColor: KColor.textDisabled,
            tooltip: 'Reset food library',
            onPressed: (patterns.isNotEmpty || overrides.isNotEmpty) ? _resetAll : null,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, KSpacing.md),
              child: KReveal(
                duration: playReveal ? KMotion.emphasized : Duration.zero,
                child: _buildSummary(patterns.length, overrides.length),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              child: KReveal(
                index: 1,
                duration: playReveal ? KMotion.emphasized : Duration.zero,
                child: _buildTabs(),
              ),
            ),
            AnimatedSize(
              duration: KMotion.of(context, KMotion.standard),
              curve: KMotion.emphasizedCurve,
              alignment: Alignment.topCenter,
              child: showSearch
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
                      child: _buildSearchField(),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: KMotion.of(context, KMotion.standard),
                reverseDuration: KMotion.of(context, KMotion.quick),
                switchInCurve: KMotion.decelerate,
                switchOutCurve: KMotion.accelerate,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: ListView.builder(
                  key: ValueKey('food_library_tab_$_selectedTab'),
                  padding: EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, bottomInset + KSpacing.xxl),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final play = playReveal && index < 8;
                    return KReveal(
                      index: index + 2,
                      duration: play ? KMotion.emphasized : Duration.zero,
                      stagger: play ? KMotion.stagger : Duration.zero,
                      child: _buildItem(items[index]),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Private building blocks ──────────────────────────────────────────────────

/// A labelled number with a confidence/scale bar beneath it.
class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.caption,
    required this.progress,
    required this.colors,
    required this.semantics,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String caption;
  final double progress;
  final List<Color> colors;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: KText.numMedium.copyWith(fontSize: 24, color: valueColor)),
          const SizedBox(height: KSpacing.sm),
          KBar(progress: progress, colors: colors, height: 4),
          const SizedBox(height: 6),
          Text(caption, style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary)),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: KColor.isDark ? KColor.fg.withValues(alpha: 0.07) : KColor.divider);
  }
}

