import 'package:flutter/material.dart';

import '../models/workout_split.dart';
import '../services/workout_service.dart';

class WorkoutSetupScreen extends StatefulWidget {
  final bool editMode;

  const WorkoutSetupScreen({super.key, this.editMode = false});

  @override
  State<WorkoutSetupScreen> createState() => _WorkoutSetupScreenState();
}

class _WorkoutSetupScreenState extends State<WorkoutSetupScreen> {
  int _step = 0;

  final Map<int, bool> _selectedDays = {
    1: true,
    2: true,
    3: true,
    4: true,
    5: true,
    6: true,
    7: false,
  };

  final Map<int, TextEditingController> _nameControllers = {};
  final Map<int, List<Exercise>> _dayExercises = {};

  static const _defaultNames = {
    1: 'Chest + Triceps',
    2: 'Back + Biceps',
    3: 'Shoulders',
    4: 'Legs',
    5: 'Push',
    6: 'Pull',
    7: 'Rest Day',
  };

  static const _shortDays = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  @override
  void initState() {
    super.initState();
    final existing = WorkoutService.instance.split;
    for (int wd = 1; wd <= 7; wd++) {
      final existingDay = existing.dayFor(wd);
      final name = existingDay?.name ?? _defaultNames[wd] ?? 'Day $wd';
      _nameControllers[wd] = TextEditingController(text: name);
      _dayExercises[wd] = List.of(
        existingDay?.exercises ??
            exerciseLibraryByDay[_defaultNames[wd] ?? ''] ??
            const [],
      );
      if (widget.editMode) {
        _selectedDays[wd] = existingDay != null && !existingDay.isRestDay;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _trainingDayCount => _selectedDays.values.where((v) => v).length;

  void _next() {
    if (_trainingDayCount == 0) {
      _showSnack('Select at least one training day.');
      return;
    }
    setState(() => _step = 1);
  }

  Future<void> _finish() async {
    final days = <SplitDay>[];
    for (int wd = 1; wd <= 7; wd++) {
      final isTraining = _selectedDays[wd] == true;
      final name = _nameControllers[wd]!.text.trim().isEmpty
          ? (_defaultNames[wd] ?? 'Day $wd')
          : _nameControllers[wd]!.text.trim();
      days.add(
        SplitDay(
          weekday: wd,
          name: isTraining ? name : 'Rest Day',
          exercises: isTraining ? (_dayExercises[wd] ?? []) : [],
        ),
      );
    }

    final newSplit = WorkoutSplit(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'My Split',
      days: days,
    );
    await WorkoutService.instance.saveSplit(newSplit);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1E1E2C)),
    );
  }

  void _removeExercise(int weekday, Exercise ex) {
    setState(() => _dayExercises[weekday]!.remove(ex));
  }

  void _reorderExercise(int weekday, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex--;
      }
      final item = _dayExercises[weekday]!.removeAt(oldIndex);
      _dayExercises[weekday]!.insert(newIndex, item);
    });
  }

  Future<void> _addExercise(int weekday) async {
    final current = _dayExercises[weekday] ?? [];
    final available = WorkoutService.instance.allExercises
        .where((e) => !current.any((c) => c.id == e.id))
        .toList();

    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExercisePickerSheet(exercises: available),
    );

    if (picked != null) {
      setState(() => _dayExercises[weekday] = [...current, picked]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => setState(() => _step = 0),
              )
            : (widget.editMode
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null),
        title: Text(
          widget.editMode ? 'Edit Training Split' : 'Set Up Training',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _step == 0 ? _buildDaySelection() : _buildDayNames(),
    );
  }

  Widget _buildDaySelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Training days',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_trainingDayCount day${_trainingDayCount == 1 ? '' : 's'} selected',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 6,
                childAspectRatio: 0.72,
              ),
              itemCount: 7,
              itemBuilder: (_, i) {
                final wd = i + 1;
                final selected = _selectedDays[wd] == true;
                return _DayToggleTile(
                  dayLabel: _shortDays[wd]!,
                  selected: selected,
                  onTap: () => setState(() => _selectedDays[wd] = !selected),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Next →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayNames() {
    final trainingDays = [
      for (int wd = 1; wd <= 7; wd++)
        if (_selectedDays[wd] == true) wd,
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              const Text(
                'Name your days',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add, reorder, or remove exercises for each day.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(height: 20),
              for (final wd in trainingDays) _buildDayCard(wd),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                widget.editMode ? 'Save Split' : 'Start Training →',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayCard(int weekday) {
    final exercises = _dayExercises[weekday] ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      _shortDays[weekday]!,
                      style: const TextStyle(
                        color: Color(0xFF52B788),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _nameControllers[weekday],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Day name',
                      hintStyle: TextStyle(color: Color(0xFF4B5563)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2E2E3E), height: 1),
          if (exercises.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: const [
                  Icon(
                    Icons.drag_indicator_rounded,
                    color: Color(0xFF4B5563),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Drag to change the order used in future workouts',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 11.5),
                  ),
                ],
              ),
            ),
          if (exercises.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIdx, newIdx) =>
                  _reorderExercise(weekday, oldIdx, newIdx),
              itemCount: exercises.length,
              itemBuilder: (_, index) {
                final ex = exercises[index];
                final subtitle = ex.notes?.trim().isNotEmpty == true
                    ? '${ex.muscleGroup} • ${ex.repRangeLabel} • ${ex.notes!.trim()}'
                    : '${ex.muscleGroup} • ${ex.repRangeLabel}';
                return ListTile(
                  key: ValueKey('${weekday}_${ex.id}'),
                  contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  leading: const Icon(
                    Icons.fitness_center_rounded,
                    color: Color(0xFF4B5563),
                    size: 18,
                  ),
                  title: Text(
                    ex.name,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _removeExercise(weekday, ex),
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          color: Color(0xFF4B5563),
                          size: 18,
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: Color(0xFF6B7280),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          InkWell(
            onTap: () => _addExercise(weekday),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    color: Color(0xFF52B788),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Add exercise',
                    style: TextStyle(
                      color: Color(0xFF52B788),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayToggleTile extends StatelessWidget {
  final String dayLabel;
  final bool selected;
  final VoidCallback onTap;

  const _DayToggleTile({
    required this.dayLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2D6A4F) : const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF52B788) : const Color(0xFF2E2E3E),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected)
              const Icon(
                Icons.check_rounded,
                color: Color(0xFF52B788),
                size: 16,
              ),
            const SizedBox(height: 2),
            Text(
              dayLabel,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF6B7280),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ExercisePickerSheet extends StatefulWidget {
  final List<Exercise> exercises;

  const _ExercisePickerSheet({required this.exercises});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.exercises
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query.toLowerCase()) ||
              e.muscleGroup.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF4B5563),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF6B7280),
                ),
                fillColor: const Color(0xFF2E2E3E),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          _CreateCustomTile(onCreated: (ex) => Navigator.of(context).pop(ex)),
          const Divider(height: 1, color: Color(0xFF2E2E3E)),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final ex = filtered[i];
                final isCustom = ex.id.startsWith('custom_');
                return ListTile(
                  title: Text(
                    ex.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${ex.muscleGroup}${isCustom ? ' (custom)' : ''}',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.add_rounded,
                    color: Color(0xFF52B788),
                  ),
                  onTap: () => Navigator.of(context).pop(ex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateCustomTile extends StatelessWidget {
  final ValueChanged<Exercise> onCreated;

  const _CreateCustomTile({required this.onCreated});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final ex = await showModalBottomSheet<Exercise>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1A1A28),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const _CreateCustomExerciseSheet(),
      );
      if (ex != null) {
        onCreated(ex);
      }
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Color(0xFF52B788),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '+ Add Custom Exercise',
                style: TextStyle(
                  color: Color(0xFF52B788),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Save your own exercise and use it everywhere',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<Exercise?> showCreateCustomExerciseSheet(BuildContext context) =>
    showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CreateCustomExerciseSheet(),
    );

class _CreateCustomExerciseSheet extends StatefulWidget {
  const _CreateCustomExerciseSheet();

  @override
  State<_CreateCustomExerciseSheet> createState() =>
      _CreateCustomExerciseSheetState();
}

class _CreateCustomExerciseSheetState
    extends State<_CreateCustomExerciseSheet> {
  final _nameCtrl = TextEditingController();
  final _repMinCtrl = TextEditingController();
  final _repMaxCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _muscleGroup = 'Other';
  ExerciseType _type = ExerciseType.barbellCompound;
  bool _saving = false;

  static const _muscleGroups = [
    'Chest',
    'Back',
    'Lats',
    'Shoulders',
    'Rear Delts',
    'Traps',
    'Biceps',
    'Triceps',
    'Quads',
    'Hamstrings',
    'Glutes',
    'Calves',
    'Core',
    'Other',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _repMinCtrl.dispose();
    _repMaxCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final repMin = int.tryParse(_repMinCtrl.text.trim());
    final repMax = int.tryParse(_repMaxCtrl.text.trim());
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a name for the exercise.'),
          backgroundColor: Color(0xFF1E1E2C),
        ),
      );
      return;
    }
    if ((repMin != null || repMax != null) &&
        (repMin == null || repMax == null || repMin <= 0 || repMax < repMin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid rep range.'),
          backgroundColor: Color(0xFF1E1E2C),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final ex = Exercise(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      muscleGroup: _muscleGroup,
      type: _type,
      defaultRepMin: repMin,
      defaultRepMax: repMax,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await WorkoutService.instance.addCustomExercise(ex);
    if (mounted) {
      Navigator.of(context).pop(ex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF4B5563),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Custom Exercise',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Saved permanently and available in split setup, logging, and history.',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Exercise name (e.g. Preacher Curl)',
                labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                filled: true,
                fillColor: const Color(0xFF1E1E2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF52B788),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'DEFAULT REP RANGE (OPTIONAL)',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _repMinCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Min reps',
                      labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E2C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _repMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Max reps',
                      labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E2C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes or cue (optional)',
                hintText: 'Example: chest-supported, use 10 to 15 reps',
                labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                filled: true,
                fillColor: const Color(0xFF1E1E2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'MUSCLE GROUP',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _muscleGroups.map((g) {
                final selected = _muscleGroup == g;
                return GestureDetector(
                  onTap: () => setState(() => _muscleGroup = g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2D6A4F).withValues(alpha: 0.2)
                          : const Color(0xFF1E1E2C),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF52B788)
                            : const Color(0xFF2E2E3E),
                      ),
                    ),
                    child: Text(
                      g,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF52B788)
                            : const Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'EXERCISE TYPE',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            for (final opt in _typeOptions)
              GestureDetector(
                onTap: () => setState(() => _type = opt.type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _type == opt.type
                        ? const Color(0xFF2D6A4F).withValues(alpha: 0.18)
                        : const Color(0xFF1E1E2C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _type == opt.type
                          ? const Color(0xFF52B788)
                          : const Color(0xFF2E2E3E),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(opt.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.label,
                              style: TextStyle(
                                color: _type == opt.type
                                    ? Colors.white
                                    : const Color(0xFF9CA3AF),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              opt.hint,
                              style: const TextStyle(
                                color: Color(0xFF4B5563),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_type == opt.type)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF52B788),
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Exercise',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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

class _TypeOption {
  final ExerciseType type;
  final String label;
  final String emoji;
  final String hint;

  const _TypeOption({
    required this.type,
    required this.label,
    required this.emoji,
    required this.hint,
  });
}

const _typeOptions = [
  _TypeOption(
    type: ExerciseType.barbellCompound,
    label: 'Barbell Compound',
    emoji: '🏋️',
    hint: '+2.5 kg jumps when rep range is earned',
  ),
  _TypeOption(
    type: ExerciseType.dumbbell,
    label: 'Dumbbell',
    emoji: '💪',
    hint: '+2 kg jumps (nearest DB increment)',
  ),
  _TypeOption(
    type: ExerciseType.cableMachine,
    label: 'Cable / Machine',
    emoji: '⚙️',
    hint: '+5 kg stack increments',
  ),
  _TypeOption(
    type: ExerciseType.isolation,
    label: 'Isolation',
    emoji: '🎯',
    hint: 'Beat reps twice before adding weight',
  ),
  _TypeOption(
    type: ExerciseType.bodyweight,
    label: 'Bodyweight',
    emoji: '🧘',
    hint: 'Rep-first progression, then add load',
  ),
];
