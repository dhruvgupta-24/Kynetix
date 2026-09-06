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
    ExerciseLibraryService.instance.initialize();
    UserExercisePreferencesService.instance.initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _selectExercise(ExerciseDefinition def) {
    UserExercisePreferencesService.instance.recordSelection(def.id);
    Navigator.of(context).pop(def.toExercise());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final splitIds = WorkoutService.instance.split.days
        .expand((d) => d.exercises)
        .map((e) => e.id)
        .toSet();
    final recentIds = UserExercisePreferencesService.instance.getRecentExerciseIds().toSet();

    final results = ExerciseLibraryService.instance.searchDetailed(
      query: _query,
      category: _selectedCategory,
      equipmentGroup: _selectedEquipment,
      excludeIds: widget.excludeIds,
      splitExerciseIds: splitIds,
      recentExerciseIds: recentIds,
      limit: 120,
    );

    final catCounts = ExerciseLibraryService.instance.getCategoryCounts(
      query: _query,
      equipmentGroup: _selectedEquipment,
      excludeIds: widget.excludeIds,
    );

    final eqCounts = ExerciseLibraryService.instance.getEquipmentCounts(
      query: _query,
      category: _selectedCategory,
      excludeIds: widget.excludeIds,
    );

    final isSearching = _query.trim().isNotEmpty;
    final bestMatches = isSearching ? results.where((r) => r.isBestMatch).toList() : <ExerciseSearchResult>[];
    final otherMatches = isSearching ? results.where((r) => !r.isBestMatch).toList() : results;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        decoration: const BoxDecoration(
          color: Color(0xFF0C0C14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Drag handle & Header
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2E2E3E),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'EXERCISE DISCOVERY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF), size: 22),
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
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search 1,363+ exercises (e.g. "t bar", "db bench", "ohp")...',
                  hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: KColor.green, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Color(0xFF9CA3AF), size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
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
                  final count = catCounts[cat] ?? 0;

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
                  final count = eqCounts[eq] ?? 0;

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
                        });
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

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
                      Text(
                        '+ Create Custom Exercise',
                        style: TextStyle(
                          color: KColor.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
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
              child: results.isEmpty
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
          Text(
            title,
            style: TextStyle(
              color: accentColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isBest ? KColor.green.withValues(alpha: 0.04) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: Color(0xFF161622), width: 0.8)),
        ),
        child: Row(
          children: [
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
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: KColor.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: KColor.blue.withValues(alpha: 0.4), width: 0.5),
                          ),
                          child: const Text(
                            'SPLIT',
                            style: TextStyle(
                              color: KColor.blue,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        def.targetMuscle,
                        style: const TextStyle(
                          color: KColor.green,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        ' • ',
                        style: TextStyle(color: Color(0xFF4B5563), fontSize: 11),
                      ),
                      Flexible(
                        child: Text(
                          def.equipment,
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (result.matchReason.label.isNotEmpty &&
                          result.matchReason.type != MatchReasonType.tokenMatch &&
                          _query.isNotEmpty) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(color: Color(0xFF4B5563), fontSize: 11),
                        ),
                        Flexible(
                          child: Text(
                            result.matchReason.label,
                            style: const TextStyle(
                              color: KColor.amber,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Favorite Toggle
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? Colors.redAccent : const Color(0xFF4B5563),
                size: 18,
              ),
              tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
              onPressed: () async {
                await UserExercisePreferencesService.instance.toggleFavorite(def.id);
                if (mounted) setState(() {});
              },
            ),

            // Info button
            IconButton(
              icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF6B7280), size: 19),
              tooltip: 'View instructions & PR',
              onPressed: () async {
                final navigator = Navigator.of(context);
                final picked = await showExerciseDetailSheet(
                  context,
                  definition: def,
                );
                if (picked != null) {
                  UserExercisePreferencesService.instance.recordSelection(def.id);
                  navigator.pop(picked);
                }
              },
            ),

            // Quick Select / Add button
            IconButton(
              icon: const Icon(Icons.add_circle_rounded, color: KColor.green, size: 24),
              onPressed: () => _selectExercise(def),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZeroResultsView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, color: Color(0xFF4B5563), size: 48),
            const SizedBox(height: 12),
            Text(
              'No exercises match "$_query"',
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try a shorthand like "db", "bb", or "ohp", or create a custom exercise.',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
