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
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF0C0C14),
    barrierColor: Colors.black.withValues(alpha: 0.75),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => ExercisePickerSheet(excludeIds: excludeIds),
  );
}

class ExercisePickerSheet extends StatefulWidget {
  final Set<String>? excludeIds;

  const ExercisePickerSheet({super.key, this.excludeIds});

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
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

    _cachedResults = ExerciseLibraryService.instance.searchDetailed(
      query: _query,
      category: _selectedCategory,
      equipmentGroup: _selectedEquipment,
      excludeIds: widget.excludeIds,
      splitExerciseIds: splitIds,
      recentExerciseIds: recentIds,
      limit: 150,
    );

    _cachedCatCounts = ExerciseLibraryService.instance.getCategoryCounts(
      query: _query,
      equipmentGroup: _selectedEquipment,
      excludeIds: widget.excludeIds,
    );

    _cachedEqCounts = ExerciseLibraryService.instance.getEquipmentCounts(
      query: _query,
      category: _selectedCategory,
      excludeIds: widget.excludeIds,
    );
  }

  void _selectExercise(ExerciseDefinition def) {
    UserExercisePreferencesService.instance.recordSelection(def.id);
    Navigator.of(context).pop(def.toExercise());
  }

  void _toggleFavorite(String exerciseId) {
    setState(() {
      UserExercisePreferencesService.instance.toggleFavorite(exerciseId);
      _recomputeData();
    });
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
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C14),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag handle & Header
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E2E3E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'EXERCISE DISCOVERY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF), size: 22),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),

              // 2. Multi-Token Relevance Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search 1,363+ exercises (e.g. "bench", "t bar", "ohp")...',
                    hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: KColor.green, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Color(0xFF9CA3AF), size: 18),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF13131F),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF1E1E2F)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF1E1E2F)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: KColor.green, width: 1.2),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // 3. Dynamic Category Chips Carousel
              SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _categories.length,
                  itemBuilder: (context, i) {
                    final cat = _categories[i];
                    final isSelected = _selectedCategory.toUpperCase() == cat.toUpperCase();
                    final count = _cachedCatCounts[cat] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '$cat ($count)',
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: KColor.green,
                        backgroundColor: const Color(0xFF13131F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? KColor.green : const Color(0xFF2E2E3E),
                            width: 0.8,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (selected) {
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

              const SizedBox(height: 6),

              // 4. Dynamic Equipment Chips Carousel
              SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _equipmentGroups.length,
                  itemBuilder: (context, i) {
                    final eq = _equipmentGroups[i];
                    final isSelected = _selectedEquipment.toUpperCase() == eq.toUpperCase();
                    final count = _cachedEqCounts[eq] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '$eq ($count)',
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFF2A2A3E),
                        backgroundColor: const Color(0xFF13131F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? KColor.blue : const Color(0xFF222233),
                            width: 0.8,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (selected) {
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

              const SizedBox(height: 6),

              // 5. Add Custom Exercise Quick Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final ex = await showCreateCustomExerciseSheet(context);
                    if (!mounted || ex == null) return;
                    ExerciseLibraryService.instance.registerCustomExercises(
                      WorkoutService.instance.customExercises,
                    );
                    navigator.pop(ex);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: KColor.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KColor.green.withValues(alpha: 0.25), width: 0.8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: KColor.green, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '+ Create Custom Exercise',
                            style: TextStyle(
                              color: KColor.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: KColor.green, size: 11),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),
              const Divider(height: 1, color: Color(0xFF1E1E2F)),

              // 6. Ranked Exercise List View
              Flexible(
                child: _cachedResults.isEmpty
                    ? _buildZeroResultsView(context)
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          // BEST MATCHES SECTION (when searching)
                          if (isSearching && bestMatches.isNotEmpty) ...[
                            _buildSectionHeader(
                              'BEST MATCH${bestMatches.length > 1 ? 'ES' : ''}',
                              KColor.green,
                              Icons.verified_rounded,
                            ),
                            ...bestMatches.map((r) => _buildExerciseRow(r, isBest: true)),
                            if (otherMatches.isNotEmpty)
                              _buildSectionHeader(
                                'OTHER MATCHES (${otherMatches.length})',
                                const Color(0xFF9CA3AF),
                                Icons.search_rounded,
                              ),
                          ],

                          // OTHER MATCHES / ALL RESULTS
                          ...otherMatches.map((r) => _buildExerciseRow(r, isBest: false)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color accentColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      color: const Color(0xFF0F0F1A),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: accentColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseRow(ExerciseSearchResult result, {required bool isBest}) {
    final def = result.definition;
    final isFav = UserExercisePreferencesService.instance.isFavorite(def.id);
    final splitIds = WorkoutService.instance.split.days
        .expand((d) => d.exercises)
        .map((e) => e.id)
        .toSet();
    final isSplit = splitIds.contains(def.id);

    return InkWell(
      onTap: () => _selectExercise(def),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isBest ? KColor.green.withValues(alpha: 0.04) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: Color(0xFF161622), width: 0.8)),
        ),
        child: Row(
          children: [
            // Exercise Thumbnail Preview
            ExerciseMediaWidget(
              definition: def,
              height: 42,
              width: 42,
              borderRadius: BorderRadius.circular(8),
              showMuscleMapFallback: false,
              interactiveZoom: false,
              preferAnimation: false,
              showAttribution: false,
              fit: BoxFit.cover,
            ),
            const SizedBox(width: 12),

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
                          style: TextStyle(
                            color: isBest ? Colors.white : const Color(0xFFE5E7EB),
                            fontSize: 14,
                            fontWeight: isBest ? FontWeight.w900 : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isFav) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 14),
                      ],
                      if (isSplit) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: KColor.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'IN SPLIT',
                            style: TextStyle(color: KColor.blue, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: Text(
                          def.equipment,
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(width: 3, height: 3, decoration: const BoxDecoration(color: Color(0xFF4B5563), shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Flexible(
                        flex: 3,
                        child: Text(
                          def.targetMuscle,
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (result.matchReason.label.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          flex: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: _getReasonColor(result.matchReason.type).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              result.matchReason.label,
                              style: TextStyle(
                                color: _getReasonColor(result.matchReason.type),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Favorite Quick Toggle
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? Colors.redAccent : const Color(0xFF6B7280),
                size: 18,
              ),
              onPressed: () => _toggleFavorite(def.id),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),

            // Detail Info Button
            IconButton(
              icon: const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF9CA3AF),
                size: 18,
              ),
              onPressed: () {
                showExerciseDetailSheet(context, definition: def);
              },
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZeroResultsView(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF13131F),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2E2E3E)),
            ),
            child: const Icon(Icons.search_off_rounded, size: 36, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          Text(
            'No catalog exercises match "$_query"',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Try checking your spelling, removing equipment filters, or create a custom exercise below.',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final ex = await showCreateCustomExerciseSheet(context);
              if (!mounted || ex == null) return;
              ExerciseLibraryService.instance.registerCustomExercises(
                WorkoutService.instance.customExercises,
              );
              navigator.pop(ex);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create Custom Exercise'),
            style: ElevatedButton.styleFrom(
              backgroundColor: KColor.green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _getReasonColor(MatchReasonType type) {
    switch (type) {
      case MatchReasonType.exactMatch:
        return const Color(0xFF10B981);
      case MatchReasonType.phraseMatch:
        return const Color(0xFF6366F1);
      case MatchReasonType.aliasMatch:
        return const Color(0xFF3B82F6);
      case MatchReasonType.synonymMatch:
        return const Color(0xFF8B5CF6);
      case MatchReasonType.typoCorrection:
        return const Color(0xFFF59E0B);
      case MatchReasonType.categoryMatch:
      case MatchReasonType.equipmentMatch:
      case MatchReasonType.tokenMatch:
        return const Color(0xFF9CA3AF);
    }
  }
}
