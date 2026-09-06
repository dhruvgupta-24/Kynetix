import 'package:flutter/material.dart';
import '../models/exercise_definition.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import '../config/app_theme.dart';
import '../widgets/exercise_media_widget.dart';

/// Shows the detailed anatomical information, step-by-step cues, equipment info,
/// and personal historical PR stats for an exercise.
Future<Exercise?> showExerciseDetailSheet(
  BuildContext context, {
  required ExerciseDefinition definition,
  bool showAddButton = true,
}) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0C0C14),
    barrierColor: Colors.black.withValues(alpha: 0.75),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => ExerciseDetailSheet(
      definition: definition,
      showAddButton: showAddButton,
    ),
  );
}

class ExerciseDetailSheet extends StatelessWidget {
  final ExerciseDefinition definition;
  final bool showAddButton;

  const ExerciseDetailSheet({
    super.key,
    required this.definition,
    this.showAddButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final history = WorkoutService.instance.historyFor(definition.id);

    double maxWeight = 0.0;
    int maxReps = 0;
    double bestE1rm = 0.0;
    bool hasLogs = false;

    for (final h in history) {
      for (final s in h.entry.sets) {
        if (!s.isMainWorkingSet) continue;
        hasLogs = true;
        if (s.weight > maxWeight) maxWeight = s.weight;
        if (s.reps > maxReps) maxReps = s.reps;
        final e1rm = s.estimatedOneRepMax;
        if (e1rm > bestE1rm) bestE1rm = e1rm;
      }
    }

    final lastSession = history.isNotEmpty ? history.first : null;
    final lastTopSet = lastSession?.entry.topWorkingSet;

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2E2E3E),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badges row
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildPill(
                            label: definition.category.toUpperCase(),
                            color: KColor.green,
                            bgColor: KColor.green.withValues(alpha: 0.15),
                          ),
                          _buildPill(
                            label: definition.equipment.toUpperCase(),
                            color: KColor.blue,
                            bgColor: KColor.blue.withValues(alpha: 0.15),
                          ),
                          _buildPill(
                            label: definition.targetMuscle.toUpperCase(),
                            color: KColor.amber,
                            bgColor: KColor.amber.withValues(alpha: 0.15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        definition.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF), size: 24),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF1E1E2F)),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              physics: const BouncingScrollPhysics(),
              children: [
                // 0. Visual Demonstration & Media Card
                ExerciseMediaWidget(
                  definition: definition,
                  height: 190,
                ),
                const SizedBox(height: 16),

                // 1. Muscle Anatomy Section
                _buildSectionHeader('ANATOMICAL TARGETS', Icons.accessibility_new_rounded),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13131F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1E1E2F)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Primary Agonist:',
                            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            definition.targetMuscle,
                            style: const TextStyle(color: KColor.green, fontSize: 14, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      if (definition.secondaryMuscles.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Synergists:',
                              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                definition.secondaryMuscles.join(', '),
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text(
                            'Progression Style:',
                            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            definition.exerciseType.name,
                            style: const TextStyle(color: KColor.blue, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Personal Historical Performance & PR Card
                _buildSectionHeader('YOUR PERFORMANCE', Icons.emoji_events_rounded),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13131F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: hasLogs ? KColor.amber.withValues(alpha: 0.3) : const Color(0xFF1E1E2F)),
                  ),
                  child: hasLogs
                      ? Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatColumn('BEST WEIGHT', '${maxWeight.toStringAsFixed(1)} kg', KColor.amber),
                                _buildStatColumn('BEST REPS', '$maxReps reps', Colors.white),
                                _buildStatColumn('ESTIMATED 1RM', '${bestE1rm.toStringAsFixed(1)} kg', KColor.green),
                              ],
                            ),
                            if (lastTopSet != null) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Color(0xFF222233)),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Recent Output:',
                                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                                  ),
                                  Text(
                                    '${lastTopSet.weight.toStringAsFixed(1)} kg × ${lastTopSet.reps} reps',
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        )
                      : const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No historical logs yet. Log your first set today!',
                              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 20),

                // 3. Step-by-Step Instructions & Cues
                if (definition.instructions.isNotEmpty) ...[
                  _buildSectionHeader('EXECUTION & CUES', Icons.format_list_numbered_rounded),
                  const SizedBox(height: 10),
                  ...definition.instructions.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final text = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: KColor.green.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: KColor.green.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              '$index',
                              style: const TextStyle(
                                color: KColor.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),

          // Bottom CTA
          if (showAddButton)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: const BoxDecoration(
                color: Color(0xFF0C0C14),
                border: Border(top: BorderSide(color: Color(0xFF1E1E2F))),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(definition.toExercise());
                    },
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                    label: const Text(
                      'ADD TO WORKOUT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KColor.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPill({required String label, required Color color, required Color bgColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: KColor.green, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildStatColumn(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: valueColor, fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ],
    );
  }
}
