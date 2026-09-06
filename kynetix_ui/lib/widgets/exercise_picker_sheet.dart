import 'package:flutter/material.dart';
import '../models/exercise_definition.dart';
import '../models/workout_split.dart';
import '../services/exercise_library_service.dart';
import '../services/workout_service.dart';
import '../screens/exercise_detail_sheet.dart';
import '../screens/workout_setup_screen.dart' show showCreateCustomExerciseSheet;
import '../config/app_theme.dart';

/// Shows the premium Kynetix Exercise Picker with 1,300+ exercises,
/// multi-token fuzzy search, dynamic categorical & equipment filters,
/// and instant detail inspection.
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final splitIds = WorkoutService.instance.split.days
        .expand((d) => d.exercises)
        .map((e) => e.id)
        .toSet();
    final recentIds = WorkoutService.instance
        .recentSessions(limit: 10)
        .expand((s) => s.entries)
        .map((e) => e.exercise.id)
        .toSet();

    final results = ExerciseLibraryService.instance.search(
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
                    'EXERCISE LIBRARY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
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

            // 2. Multi-Token Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search 1,300+ exercises (e.g. "incline db", "pullup")...',
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: KColor.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KColor.green.withValues(alpha: 0.25), width: 0.8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add_circle_outline_rounded, color: KColor.green, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '+ Create Custom Exercise',
                        style: TextStyle(
                          color: KColor.green,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      Icon(Icons.arrow_forward_ios_rounded, color: KColor.green, size: 12),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),
            const Divider(height: 1, color: Color(0xFF1E1E2F)),

            // 6. Filtered Exercise List View
            Flexible(
              child: results.isEmpty
                  ? Center(
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
                              'Try a broader query or create a custom exercise above.',
                              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final def = results[i];
                        final isSplit = splitIds.contains(def.id);
                        final isRecent = recentIds.contains(def.id);

                        String badge = '';
                        Color badgeColor = Colors.transparent;
                        if (isSplit && isRecent) {
                          badge = 'SPLIT • RECENT';
                          badgeColor = KColor.green;
                        } else if (isSplit) {
                          badge = 'SPLIT';
                          badgeColor = KColor.blue;
                        } else if (isRecent) {
                          badge = 'RECENT';
                          badgeColor = KColor.amber;
                        }

                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop(def.toExercise());
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFF161622), width: 0.8)),
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
                                              def.name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (badge.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.5),
                                              ),
                                              child: Text(
                                                badge,
                                                style: TextStyle(
                                                  color: badgeColor,
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
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
                                          Text(
                                            def.equipment,
                                            style: const TextStyle(
                                              color: Color(0xFF9CA3AF),
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Info button
                                IconButton(
                                  icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF6B7280), size: 20),
                                  tooltip: 'View instructions & PR',
                                  onPressed: () async {
                                    final navigator = Navigator.of(context);
                                    final picked = await showExerciseDetailSheet(
                                      context,
                                      definition: def,
                                    );
                                    if (picked != null) {
                                      navigator.pop(picked);
                                    }
                                  },
                                ),

                                // Quick Add button
                                IconButton(
                                  icon: const Icon(Icons.add_circle_rounded, color: KColor.green, size: 24),
                                  onPressed: () {
                                    Navigator.of(context).pop(def.toExercise());
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
