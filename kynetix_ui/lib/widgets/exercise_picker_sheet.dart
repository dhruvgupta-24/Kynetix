import 'package:flutter/material.dart';
import '../models/workout_split.dart';
import '../models/exercise_definition.dart';
import '../services/exercise_library_service.dart';
import '../services/exercise_search_engine.dart';
import '../services/user_exercise_preferences_service.dart';
import '../services/workout_service.dart';
import '../screens/exercise_detail_sheet.dart';
import '../screens/workout_setup_screen.dart' show showCreateCustomExerciseSheet;
import '../config/app_theme.dart';
import 'exercise_media_widget.dart';

/// Shows the relevance-ranked Kynetix Exercise Discovery Picker.
/// Features intelligent multi-signal ranking, alias resolution, instant favorites,
/// recents prioritization, and clean display names across the 1,363+ catalog.
Future<Exercise?> showExercisePickerSheet(
  BuildContext context, {
  List<Exercise>? initialAvailableExercises,
  Set<String>? excludeIds,
}) {
  return showKSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => ExercisePickerSheet(excludeIds: excludeIds),
  );
}

class ExercisePickerSheet extends StatefulWidget {
  final Set<String>? excludeIds;

  const ExercisePickerSheet({super.key, this.excludeIds});

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

// ─── Flat list entries (lazy ListView.builder) ────────────────────────────────

sealed class _Entry {
  const _Entry();
}

final class _HeaderEntry extends _Entry {
  const _HeaderEntry(this.title, this.accent, this.icon);
  final String title;
  final Color accent;
  final IconData icon;
}

final class _DidYouMeanEntry extends _Entry {
  const _DidYouMeanEntry(this.definition);
  final ExerciseDefinition definition;
}

final class _RowEntry extends _Entry {
  const _RowEntry(this.result, {required this.isBest});
  final ExerciseSearchResult result;
  final bool isBest;
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  String _query = '';
  String _selectedCategory = 'ALL';
  String _selectedEquipment = 'ALL';

  List<ExerciseSearchResult> _cachedResults = [];
  Map<String, int> _cachedCatCounts = {};
  Map<String, int> _cachedEqCounts = {};
  Set<String> _splitIds = const {};
  Set<String> _recentIds = const {};

  static const List<String> _categories = [
    'ALL',
    'Chest',
    'Back',
    'Shoulders',
    'Arms',
    'Legs',
    'Core',
    'Cardio',
  ];

  static const List<String> _equipmentGroups = [
    'ALL',
    'Barbell',
    'Dumbbell',
    'Cable',
    'Machine',
    'Bodyweight',
    'Band',
    'Kettlebell',
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();

    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
    ExerciseLibraryService.instance.addListener(_onLibraryUpdated);
    UserExercisePreferencesService.instance.initialize();

    _recomputeData();

    // Ensure async initialization finishes and updates data deterministically
    ExerciseLibraryService.instance.initialize().then((_) {
      if (mounted) {
        _recomputeData();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onFocusChanged);
    ExerciseLibraryService.instance.removeListener(_onLibraryUpdated);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onSearchChanged() {
    final text = _searchController.text;
    if (_query != text) {
      setState(() {
        _query = text;
        _recomputeData();
      });
    }
  }

  void _onLibraryUpdated() {
    if (mounted) {
      setState(() {
        _recomputeData();
      });
    }
  }

  void _recomputeData() {
    final splitIds = WorkoutService.instance.split.days
        .expand((d) => d.exercises)
        .map((e) => e.id)
        .toSet();
    final recentIds = UserExercisePreferencesService.instance.getRecentExerciseIds().toSet();
    _splitIds = splitIds;
    _recentIds = recentIds;

    final lib = ExerciseLibraryService.instance;
    if (_query.trim().isEmpty) {
      _cachedResults = lib.searchDetailed(
        query: _query,
        category: _selectedCategory,
        equipmentGroup: _selectedEquipment,
        excludeIds: widget.excludeIds,
        splitExerciseIds: splitIds,
        recentExerciseIds: recentIds,
        limit: 150,
      );
      _cachedCatCounts = lib.getCategoryCounts(
        query: _query,
        equipmentGroup: _selectedEquipment,
        excludeIds: widget.excludeIds,
      );
      _cachedEqCounts = lib.getEquipmentCounts(
        query: _query,
        category: _selectedCategory,
        excludeIds: widget.excludeIds,
      );
      return;
    }

    // Typing: the list and both chip counts each needed a full scored search
    // of the ~1,400-movement catalog (three per keystroke). The counts only
    // need the matches under the *other* filter, so memoise by filter pair:
    // with no filters (the common case while typing) all three share one
    // search, and with one filter set they share two.
    final memo = <String, List<ExerciseSearchResult>>{};
    List<ExerciseSearchResult> run(String cat, String eq) => memo['$cat|$eq'] ??= lib.searchDetailed(
          query: _query,
          category: cat,
          equipmentGroup: eq,
          excludeIds: widget.excludeIds,
          splitExerciseIds: splitIds,
          recentExerciseIds: recentIds,
          limit: 1500,
        );

    final both = run(_selectedCategory, _selectedEquipment);
    _cachedResults = both.length > 150 ? both.sublist(0, 150) : both;

    final catCounts = <String, int>{'ALL': 0};
    for (final r in run('ALL', _selectedEquipment)) {
      catCounts['ALL'] = catCounts['ALL']! + 1;
      final c = r.definition.category;
      catCounts[c] = (catCounts[c] ?? 0) + 1;
    }
    _cachedCatCounts = catCounts;

    final eqCounts = <String, int>{'ALL': 0};
    for (final r in run(_selectedCategory, 'ALL')) {
      eqCounts['ALL'] = eqCounts['ALL']! + 1;
      final g = r.definition.equipmentGroup;
      eqCounts[g] = (eqCounts[g] ?? 0) + 1;
    }
    _cachedEqCounts = eqCounts;
  }

  void _selectExercise(ExerciseDefinition def) {
    KHaptics.commit();
    UserExercisePreferencesService.instance.recordSelection(def.id);
    Navigator.of(context).pop(def.toExercise());
  }

  void _toggleFavorite(String exerciseId) {
    KHaptics.select();
    setState(() {
      UserExercisePreferencesService.instance.toggleFavorite(exerciseId);
      _recomputeData();
    });
  }

  Future<void> _createCustomExercise() async {
    final navigator = Navigator.of(context);
    final ex = await showCreateCustomExerciseSheet(context);
    if (!mounted || ex == null) return;
    ExerciseLibraryService.instance.registerCustomExercises(
      WorkoutService.instance.customExercises,
    );
    navigator.pop(ex);
  }

  void _applySuggestion(String name) {
    KHaptics.select();
    _searchController.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  List<_Entry> _buildEntries({
    required bool isSearching,
    required List<ExerciseSearchResult> bestMatches,
    required List<ExerciseSearchResult> otherMatches,
  }) {
    final entries = <_Entry>[];
    if (isSearching) {
      // BEST MATCHES SECTION (when searching)
      if (bestMatches.isNotEmpty) {
        entries.add(_HeaderEntry(
          bestMatches.length > 1 ? 'Best matches' : 'Best match',
          KColor.textPrimary,
          Icons.verified_rounded,
        ));
        entries.addAll(bestMatches.map((r) => _RowEntry(r, isBest: true)));
        if (otherMatches.isNotEmpty) {
          entries.add(_HeaderEntry(
            'Other matches (${otherMatches.length})',
            KColor.textMuted,
            Icons.search_rounded,
          ));
        }
      } else if (otherMatches.isNotEmpty &&
          otherMatches.first.matchReason.type == MatchReasonType.typoCorrection) {
        // Only fuzzy hits: offer the closest name as a one-tap correction.
        entries.add(_DidYouMeanEntry(otherMatches.first.definition));
      }
      // OTHER MATCHES / ALL RESULTS
      entries.addAll(otherMatches.map((r) => _RowEntry(r, isBest: false)));
      return entries;
    }

    // Empty query: favourites → recent → everything else (popular first).
    final prefs = UserExercisePreferencesService.instance;
    final favs = <ExerciseSearchResult>[];
    final recents = <ExerciseSearchResult>[];
    final rest = <ExerciseSearchResult>[];
    for (final r in otherMatches) {
      if (prefs.isFavorite(r.definition.id)) {
        favs.add(r);
      } else if (_recentIds.contains(r.definition.id)) {
        recents.add(r);
      } else {
        rest.add(r);
      }
    }
    if (favs.isEmpty && recents.isEmpty) {
      entries.addAll(rest.map((r) => _RowEntry(r, isBest: false)));
      return entries;
    }
    if (favs.isNotEmpty) {
      entries.add(_HeaderEntry('Favourites', KColor.ember, Icons.favorite_rounded));
      entries.addAll(favs.map((r) => _RowEntry(r, isBest: false)));
    }
    if (recents.isNotEmpty) {
      entries.add(_HeaderEntry('Recent', KColor.textSecondary, Icons.history_rounded));
      entries.addAll(recents.map((r) => _RowEntry(r, isBest: false)));
    }
    if (rest.isNotEmpty) {
      entries.add(_HeaderEntry('All movements', KColor.textMuted, Icons.grid_view_rounded));
      entries.addAll(rest.map((r) => _RowEntry(r, isBest: false)));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;

    final isSearching = _query.trim().isNotEmpty;
    final bestMatches = isSearching
        ? _cachedResults.where((r) => r.isBestMatch).toList()
        : <ExerciseSearchResult>[];
    final otherMatches = isSearching
        ? _cachedResults.where((r) => !r.isBestMatch).toList()
        : _cachedResults;

    final isEmpty = _cachedResults.isEmpty;
    // Result-group key: the list crossfades when the group changes (mode,
    // filters or the top hit) — never a per-row stagger on each keystroke.
    final groupKey = isEmpty
        ? 'zero|$_selectedCategory|$_selectedEquipment'
        : '${isSearching ? 'search' : 'browse'}|$_selectedCategory|$_selectedEquipment|'
            '${_cachedResults.first.definition.id}';

    // 48dp rows so every filter chip is a full-size touch target.
    final chipRowHeight = media.textScaler.scale(48).clamp(48.0, 80.0);

    return PopScope(
      canPop: !_searchFocusNode.hasFocus,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.90),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: KColor.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: KColor.isDark
                ? Border(top: BorderSide(color: KColor.fg.withValues(alpha: 0.10)))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag handle & Header
              const KDragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpacing.lg, 0, KSpacing.xs, KSpacing.xs),
                child: Row(
                  children: [
                    const _TrainBadge(icon: Icons.fitness_center_rounded),
                    const SizedBox(width: KSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              'Add an exercise',
                              style: KText.h3.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: KColor.textSecondary, size: 22),
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),

              // 2. Multi-Token Relevance Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.xs),
                child: AnimatedContainer(
                  duration: KMotion.of(context, KMotion.standard),
                  curve: KMotion.emphasizedCurve,
                  decoration: BoxDecoration(
                    borderRadius: KRadius.md,
                    boxShadow: KColor.isDark ? const [] : KShadow.card,
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: KText.body.copyWith(color: KColor.textPrimary, height: 1.3),
                    cursorColor: KColor.textPrimary,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search 1,363+ moves, like "bench" or "t bar"',
                      hintStyle: KText.body.copyWith(color: KColor.textMuted, fontSize: 14, height: 1.3),
                      prefixIcon: AnimatedSwitcher(
                        duration: KMotion.of(context, KMotion.quick),
                        child: Icon(
                          Icons.search_rounded,
                          key: ValueKey(_searchFocusNode.hasFocus),
                          color: _searchFocusNode.hasFocus ? KColor.textPrimary : KColor.textMuted,
                          size: 20,
                        ),
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear search',
                              icon: Icon(Icons.clear_rounded, color: KColor.textSecondary, size: 18),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: KColor.isDark ? KColor.card : KColor.cardHigh,
                      contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.md),
                      border: OutlineInputBorder(
                        borderRadius: KRadius.md,
                        borderSide: BorderSide(color: _hairline()),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: KRadius.md,
                        borderSide: BorderSide(color: _hairline()),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: KRadius.md,
                        borderSide: BorderSide(color: KColor.textPrimary, width: 1.4),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: KSpacing.xs),

              // 3. Dynamic Category Chips Carousel
              SizedBox(
                height: chipRowHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
                  itemCount: _categories.length,
                  itemBuilder: (context, i) {
                    final cat = _categories[i];
                    final isSelected = _selectedCategory.toUpperCase() == cat.toUpperCase();
                    final count = _cachedCatCounts[cat] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(right: KSpacing.sm),
                      child: _filterChip(
                        label: '${cat == 'ALL' ? 'All' : cat} ($count)',
                        isSelected: isSelected,
                        accent: KColor.ink,
                        onSelected: (selected) {
                          KHaptics.select();
                          setState(() {
                            _selectedCategory = selected ? cat : 'ALL';
                            _recomputeData();
                          });
                        },
                      ),
                    );
                  },
                ),
              ),

              // 4. Dynamic Equipment Chips Carousel
              SizedBox(
                height: chipRowHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
                  itemCount: _equipmentGroups.length,
                  itemBuilder: (context, i) {
                    final eq = _equipmentGroups[i];
                    final isSelected = _selectedEquipment.toUpperCase() == eq.toUpperCase();
                    final count = _cachedEqCounts[eq] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(right: KSpacing.sm),
                      child: _filterChip(
                        label: '${eq == 'ALL' ? 'All' : eq} ($count)',
                        isSelected: isSelected,
                        accent: KColor.ink,
                        onSelected: (selected) {
                          KHaptics.select();
                          setState(() {
                            _selectedEquipment = selected ? eq : 'ALL';
                            _recomputeData();
                          });
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: KSpacing.xs),

              // 5. Add Custom Exercise Quick Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
                child: Semantics(
                  button: true,
                  label: 'Create custom exercise',
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: _createCustomExercise,
                      borderRadius: KRadius.md,
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: KSpacing.md, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: KRadius.md,
                          border: Border.all(
                            color: KColor.fg.withValues(alpha: KColor.isDark ? 0.16 : 0.18),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: KColor.ink,
                              ),
                              child: Icon(Icons.add_rounded, color: KColor.onInk, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '+ Create Custom Exercise',
                                style: KText.bodyMedium.copyWith(
                                  color: KColor.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded, color: KColor.textMuted, size: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: KSpacing.sm),
              Divider(height: 1, color: _hairline()),

              // 6. Ranked Exercise List View
              Flexible(
                child: AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  switchInCurve: KMotion.decelerate,
                  switchOutCurve: KMotion.accelerate,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.012),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(groupKey),
                    child: isEmpty
                        ? _buildZeroResultsView(context)
                        : _buildResultsList(
                            _buildEntries(
                              isSearching: isSearching,
                              bestMatches: bestMatches,
                              otherMatches: otherMatches,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    required Color accent,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: KText.caption.copyWith(
          color: isSelected ? KColor.onInk : KColor.textSecondary,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      selected: isSelected,
      showCheckmark: false,
      selectedColor: accent,
      backgroundColor: KColor.isDark ? KColor.card : KColor.cardHigh,
      side: BorderSide(
        color: isSelected ? accent : _hairline(),
        width: 1,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected ? accent : _hairline(),
          width: 1,
        ),
      ),
      // Padded = 48dp hit area around the compact visual chip.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      onSelected: onSelected,
    );
  }

  Widget _buildResultsList(List<_Entry> entries) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        top: KSpacing.xs,
        bottom: KSpacing.lg + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => switch (entries[i]) {
        _HeaderEntry(:final title, :final accent, :final icon) =>
          _buildSectionHeader(title, accent, icon),
        _DidYouMeanEntry(:final definition) => _buildDidYouMean(definition),
        _RowEntry(:final result, :final isBest) => _buildExerciseRow(result, isBest: isBest),
      },
    );
  }

  Widget _buildSectionHeader(String title, Color accentColor, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, 14, KSpacing.lg, 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: KSpacing.sm),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: KText.label.copyWith(
                  color: accentColor == KColor.textMuted ? KColor.textSecondary : accentColor,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDidYouMean(ExerciseDefinition def) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, 10, KSpacing.lg, KSpacing.xs),
      child: Semantics(
        button: true,
        label: 'Did you mean ${def.displayName}?',
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _applySuggestion(def.displayName),
            borderRadius: KRadius.md,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.md, vertical: 14),
              decoration: BoxDecoration(
                color: KColor.isDark ? KColor.card : KColor.cardHigh,
                borderRadius: KRadius.md,
                border: Border.all(color: _hairline(), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.spellcheck_rounded, size: 16, color: KColor.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 14, height: 1.35),
                        children: [
                          const TextSpan(text: 'Did you mean? '),
                          TextSpan(
                            text: def.displayName,
                            style: TextStyle(
                              color: KColor.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Icon(Icons.north_west_rounded, size: 14, color: KColor.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseRow(ExerciseSearchResult result, {required bool isBest}) {
    final def = result.definition;
    final isFav = UserExercisePreferencesService.instance.isFavorite(def.id);
    final isSplit = _splitIds.contains(def.id);
    final reasonLabel = result.matchReason.label;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _selectExercise(def),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(KSpacing.lg, 10, KSpacing.xs, 10),
          decoration: BoxDecoration(
            color: isBest ? KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.03) : null,
            border: Border(
              bottom: BorderSide(
                color: KColor.isDark ? KColor.fg.withValues(alpha: 0.06) : KColor.divider,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Best matches carry an ink spine (shape cue, not just tint).
              if (isBest) ...[
                Container(
                  width: 3,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: KRadius.pill,
                    color: KColor.ink,
                  ),
                ),
                const SizedBox(width: KSpacing.sm),
              ],
              // Exercise Thumbnail Preview
              ExerciseMediaWidget(
                definition: def,
                height: 46,
                width: 46,
                borderRadius: KRadius.sm,
                showMuscleMapFallback: false,
                interactiveZoom: false,
                preferAnimation: false,
                showAttribution: false,
                fit: BoxFit.cover,
              ),
              const SizedBox(width: KSpacing.md),

              // Exercise info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            def.displayName,
                            style: KText.bodyMedium.copyWith(
                              color: KColor.textPrimary,
                              fontSize: 15,
                              fontWeight: isBest ? FontWeight.w700 : FontWeight.w600,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isFav) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.favorite_rounded, color: KColor.ember, size: 14),
                        ],
                        if (isSplit) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: KColor.violet.withValues(alpha: KColor.isDark ? 0.16 : 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'In split',
                              style: KText.caption.copyWith(
                                color: KColor.violet,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          flex: 3,
                          child: Text(
                            def.equipment,
                            style: KText.caption.copyWith(color: KColor.textSecondary, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(color: KColor.textDisabled, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          flex: 3,
                          child: Text(
                            def.targetMuscle,
                            style: KText.caption.copyWith(color: KColor.textSecondary, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (reasonLabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            flex: 4,
                            child: _ReasonPill(reason: result.matchReason),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Favorite Quick Toggle
              IconButton(
                tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
                icon: AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.standard),
                  switchInCurve: KMotion.overshoot,
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    key: ValueKey(isFav),
                    color: isFav ? KColor.ember : KColor.textMuted,
                    size: 19,
                  ),
                ),
                onPressed: () => _toggleFavorite(def.id),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
              ),

              // Detail Info Button
              IconButton(
                tooltip: 'Exercise details',
                icon: Icon(
                  Icons.info_outline_rounded,
                  color: KColor.textSecondary,
                  size: 19,
                ),
                onPressed: () {
                  showExerciseDetailSheet(context, definition: def);
                },
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZeroResultsView(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: KSpacing.lg),
          // Quiet hairline ring around the "nothing found" glyph.
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KColor.isDark ? KColor.card : KColor.cardHigh,
              border: Border.all(color: _hairline(), width: 1),
            ),
            child: Icon(Icons.search_off_rounded, size: 32, color: KColor.textSecondary),
          ),
          const SizedBox(height: KSpacing.lg),
          Text(
            'No catalog exercises match "$_query"',
            style: KText.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Check the spelling or loosen the filters. Or make your own below.',
            style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KSpacing.xl),
          KButton(
            label: 'Create Custom Exercise',
            icon: Icons.add_rounded,
            onTap: _createCustomExercise,
          ),
        ],
      ),
    );
  }
}

// ─── Private pieces ───────────────────────────────────────────────────────────

/// Theme hairline: a whisper of white on Carbon, the warm paper border on Paper.
Color _hairline() => KColor.isDark ? KColor.fg.withValues(alpha: 0.09) : KColor.border;

class _TrainBadge extends StatelessWidget {
  const _TrainBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: KRadius.sm,
          color: KColor.violet.withValues(alpha: KColor.isDark ? 0.16 : 0.10),
          border: Border.all(color: KColor.violet.withValues(alpha: 0.28), width: 1),
        ),
        child: Icon(icon, color: KColor.violet, size: 20),
      ),
    );
  }
}

/// Match-reason pill: colour + a distinct glyph per reason so the signal
/// survives without hue.
class _ReasonPill extends StatelessWidget {
  const _ReasonPill({required this.reason});
  final MatchReason reason;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _style(reason);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: KColor.isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              reason.label,
              style: KText.caption.copyWith(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  static (Color, IconData) _style(MatchReason r) {
    // Empty-query personal labels reuse the exact-match type.
    if (r.label == 'Favorite') return (KColor.ember, Icons.favorite_rounded);
    if (r.label == 'Recent') return (KColor.cyan, Icons.history_rounded);
    switch (r.type) {
      case MatchReasonType.exactMatch:
        return (KColor.green, Icons.check_rounded);
      case MatchReasonType.phraseMatch:
        return (KColor.violet, Icons.format_quote_rounded);
      case MatchReasonType.aliasMatch:
        return (KColor.cyan, Icons.alternate_email_rounded);
      case MatchReasonType.synonymMatch:
        return (KColor.blue, Icons.short_text_rounded);
      case MatchReasonType.typoCorrection:
        return (KColor.saffron, Icons.spellcheck_rounded);
      case MatchReasonType.categoryMatch:
      case MatchReasonType.equipmentMatch:
      case MatchReasonType.tokenMatch:
        return (KColor.textMuted, Icons.search_rounded);
    }
  }
}
