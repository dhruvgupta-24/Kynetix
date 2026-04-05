import 'package:flutter/material.dart';
import '../models/coach_insight.dart';
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../screens/onboarding_screen.dart';
import '../services/coach_service.dart';
import '../services/health_service.dart';
import '../services/meal_suggestion_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../services/workout_service.dart';
import 'add_meal_screen.dart';

class DayDetailScreen extends StatefulWidget {
  final DateTime date;
  final HealthSyncResult? health; // passed from dashboard for engine

  const DayDetailScreen({super.key, required this.date, this.health});

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  late DayLog _log;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _log = logFor(widget.date);
  }

  void _refresh() {
    setState(() {
      _log = logFor(widget.date);
    });
    PersistenceService.saveDayLogs().ignore();
  }

  Future<void> _openAddMeal(MealSection section) async {
    final entry = await Navigator.of(context).push<dynamic>(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) =>
            AddMealScreen(section: section, date: widget.date),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
    if (entry != null) _refresh();
  }

  /// Opens AddMealScreen with [prefilledText] for the time-appropriate section.
  Future<void> _openAddMealWithText(String prefilledText) async {
    final entry = await Navigator.of(context).push<dynamic>(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) => AddMealScreen(
          section: _currentSection,
          date: widget.date,
          initialText: prefilledText,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
    if (entry != null) _refresh();
  }

  /// The most time-appropriate meal section right now.
  MealSection get _currentSection {
    final h = DateTime.now().hour;
    if (h < 11) return MealSection.breakfast;
    if (h < 16) return MealSection.lunch;
    if (h < 19) return MealSection.eveningSnack;
    if (h < 23) return MealSection.dinner;
    return MealSection.lateNight;
  }

  Future<void> _openEditMeal(MealEntry entry) async {
    final updated = await Navigator.of(context).push<dynamic>(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) => AddMealScreen(
          section: entry.section,
          date: widget.date,
          initialEntry: entry,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
    if (!mounted) return;
    if (updated is DeleteSentinel) {
      // User confirmed deletion inside the edit flow — remove from log and sync.
      _log.remove(entry.section, entry);
      _refresh();
    } else if (updated != null) {
      _refresh();
    }
  }

  String get _dateLabel {
    final d = widget.date;
    final wd = _weekdays[d.weekday - 1];
    return '$wd, ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  bool get _isToday {
    final now = DateTime.now();
    return widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
  }

  /// Engine-computed target for this day.
  /// Recomputes on every rebuild so gym toggle takes effect instantly.
  /// Priority: actual logged session > gymDay workoutType > plain toggle.
  DayTarget? get _dayTarget {
    final profile = currentUserProfile;
    if (profile == null) return null;
    final session = WorkoutService.instance.sessionFor(widget.date);
    final gymDay  = _log.gymDay;
    return NutritionTargetEngine().dayTarget(
      profile,
      isGymDay:        gymDay?.didGym ?? false,
      health:          widget.health,
      session:         session,
      workoutTypeName: gymDay?.workoutType?.displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = currentUserProfile;
    final target = _dayTarget;
    final todayWorkout = WorkoutService.instance.sessionFor(widget.date);
    final insights = target != null
        ? CoachService.instance.insightsForDay(
            _log,
            target,
            profile: profile,
            todayWorkout: todayWorkout,
          )
        : const <CoachInsight>[];
    final suggestions = (target != null && profile != null)
        ? MealSuggestionService.instance.suggestionsForDay(
            date: widget.date,
            log: _log,
            target: target,
            profile: profile,
          )
        : const <MealSuggestion>[];
    final dayStatus = target != null
        ? DayStatusEngine.classify(_log, target)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isToday ? 'Today' : _dateLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (!_isToday)
              Text(
                _dateLabel,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _DaySummaryBanner(log: _log, target: target, dayStatus: dayStatus),
          const SizedBox(height: 12),

          // ── Coach insights ────────────────────────────────────
          if (insights.isNotEmpty) ...[
            _CoachInsightCard(insights: insights),
            const SizedBox(height: 12),
          ],

          // ── What to eat next ──────────────────────────────────
          if (suggestions.isNotEmpty) ...[
            _SuggestionCard(
              suggestions: suggestions,
              onSuggestionTap: _openAddMealWithText,
            ),
            const SizedBox(height: 12),
          ],

          // ── Gym tracking ──────────────────────────────────────
          _GymCard(log: _log, onChanged: _refresh),
          const SizedBox(height: 4),
          ...MealSection.values.map(
            (section) => _MealSectionCard(
              section: section,
              log: _log,
              onAdd: () => _openAddMeal(section),
              onEdit: _openEditMeal,
              onDelete: (entry) {
                _log.remove(section, entry);
                _refresh();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Gym tracking card ────────────────────────────────────────────────────────

class _GymCard extends StatelessWidget {
  final DayLog log;
  final VoidCallback onChanged;
  const _GymCard({required this.log, required this.onChanged});

  void _toggleGym(bool didGym) {
    log.gymDay = didGym
        ? const GymDay(didGym: true)
        : const GymDay(didGym: false);
    onChanged();
  }

  void _selectType(WorkoutType t) {
    log.gymDay = GymDay(didGym: true, workoutType: t);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final gym = log.gymDay;
    final didGym = gym?.didGym ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: didGym
              ? const Color(0xFF52B788).withValues(alpha: 0.40)
              : const Color(0xFF2E2E3E),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with toggle
          Row(
            children: [
              Text(didGym ? '🏋️' : '💤', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Gym / Workout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Yes / No toggle
              _GymToggleButton(
                label: 'Yes',
                active: didGym,
                activeColor: const Color(0xFF52B788),
                onTap: () => _toggleGym(true),
              ),
              const SizedBox(width: 8),
              _GymToggleButton(
                label: 'No',
                active: !didGym,
                activeColor: const Color(0xFF4B5563),
                onTap: () => _toggleGym(false),
              ),
            ],
          ),

          // Workout type chips (only shown when gym = yes)
          if (didGym) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2E2E3E), height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: WorkoutType.values.map((t) {
                final selected = gym?.workoutType == t;
                return GestureDetector(
                  onTap: () => _selectType(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF52B788).withValues(alpha: 0.18)
                          : const Color(0xFF13131F),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF52B788).withValues(alpha: 0.6)
                            : const Color(0xFF2E2E3E),
                      ),
                    ),
                    child: Text(
                      '${t.emoji} ${t.displayName}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFF52B788)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _GymToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _GymToggleButton({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? activeColor : const Color(0xFF2E2E3E),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? activeColor : const Color(0xFF4B5563),
          ),
        ),
      ),
    );
  }
}

// ─── Day summary banner ───────────────────────────────────────────────────────

class _DaySummaryBanner extends StatelessWidget {
  final DayLog log;
  final DayTarget? target;
  final DayOutcomeResult? dayStatus;
  const _DaySummaryBanner({required this.log, this.target, this.dayStatus});

  @override
  Widget build(BuildContext context) {
    final t = target;

    // ── Empty log — show target only ──────────────────────────────────────
    if (log.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E2E3E)),
        ),
        child: t == null
            ? const Row(
                children: [
                  Icon(
                    Icons.restaurant_menu_rounded,
                    color: Color(0xFF4B5563),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No meals logged yet — add a meal below.',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DayTypeChip(isGymDay: t.isTrainingDay, label: t.label),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _TargetPill(
                        icon: Icons.local_fire_department_rounded,
                        color: const Color(0xFFFF6B35),
                        label: 'Target',
                        value: '${t.calories.toInt()} kcal',
                      ),
                      const SizedBox(width: 10),
                      _TargetPill(
                        icon: Icons.fitness_center_rounded,
                        color: const Color(0xFF52B788),
                        label: 'Protein',
                        value: '${t.protein.toInt()} g',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No meals logged yet — start tracking',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 11),
                  ),
                ],
              ),
      );
    }

    // ── Has food — show progress vs target ────────────────────────────────
    final consumedCal = log.totalCaloriesMid;
    final consumedProt = log.totalProteinMid;
    final targetCal = t?.calories;
    final targetProt = t?.protein;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A2A), Color(0xFF1E1E2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF52B788).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t != null) ...[
            _DayTypeChip(isGymDay: t.isTrainingDay, label: t.label),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _MacroProgress(
                  label: 'Calories',
                  consumed: consumedCal,
                  target: targetCal,
                  unit: 'kcal',
                  color: const Color(0xFFFF6B35),
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: const Color(0xFF2E2E3E),
                margin: const EdgeInsets.symmetric(horizontal: 14),
              ),
              Expanded(
                child: _MacroProgress(
                  label: 'Protein',
                  consumed: consumedProt,
                  target: targetProt,
                  unit: 'g',
                  color: const Color(0xFF52B788),
                ),
              ),
            ],
          ),
          // Day status chip — only for meaningful outcomes
          if (dayStatus != null &&
              dayStatus!.outcome != DayOutcome.incomplete &&
              dayStatus!.outcome != DayOutcome.unlogged) ...[
            const SizedBox(height: 10),
            // Constrain width so Flexible inside the chip's Row can ellipsize
            // long notes on small screens instead of overflowing.
            SizedBox(
              width: double.infinity,
              child: _DayStatusChip(status: dayStatus!),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Day status chip ──────────────────────────────────────────────────────────

class _DayStatusChip extends StatelessWidget {
  final DayOutcomeResult status;
  const _DayStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status.color.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      // Use an intrinsic-width row but let the note shrink to available space.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: status.isPositive ? 1.0 : 0.97),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Text(status.emoji, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 5),
          // Label is fixed — always visible.
          Flexible(
            flex: 0,
            child: Text(
              status.label,
              style: TextStyle(
                color: status.color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          // Note is secondary — shrinks / ellipses on small screens.
          if (status.note.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '· ${status.note}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Day type chip ────────────────────────────────────────────────────────────

class _DayTypeChip extends StatelessWidget {
  final bool isGymDay;
  final String label;
  const _DayTypeChip({required this.isGymDay, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = isGymDay ? const Color(0xFF52B788) : const Color(0xFF6B7280);
    final emoji = isGymDay ? '⚡' : '😴';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─── Macro progress col ───────────────────────────────────────────────────────

class _MacroProgress extends StatelessWidget {
  final String label;
  final double consumed;
  final double? target;
  final String unit;
  final Color color;
  const _MacroProgress({
    required this.label,
    required this.consumed,
    required this.target,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasTarget = target != null && target! > 0;
    final ratio = hasTarget ? (consumed / target!).clamp(0.0, 1.0) : 0.0;
    final pct = (ratio * 100).toInt();
    final overGoal = hasTarget && consumed > target!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF6B7280),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        // Consumed / Target
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${consumed.toInt()}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: overGoal ? const Color(0xFFFFB347) : color,
                ),
              ),
              if (hasTarget)
                TextSpan(
                  text: ' / ${target!.toInt()} $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                )
              else
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
            ],
          ),
        ),
        if (hasTarget) ...[
          const SizedBox(height: 5),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 4,
                backgroundColor: const Color(0xFF2E2E3E),
                valueColor: AlwaysStoppedAnimation(
                  overGoal ? const Color(0xFFFFB347) : color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$pct%${overGoal ? ' — over goal' : ''}',
            style: TextStyle(
              fontSize: 9,
              color: overGoal
                  ? const Color(0xFFFFB347)
                  : const Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Target pill (empty state only) ──────────────────────────────────────────

class _TargetPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _TargetPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Meal section card ────────────────────────────────────────────────────────

class _MealSectionCard extends StatelessWidget {
  final MealSection section;
  final DayLog log;
  final VoidCallback onAdd;
  final ValueChanged<MealEntry>? onEdit;
  final ValueChanged<MealEntry> onDelete;

  const _MealSectionCard({
    required this.section,
    required this.log,
    required this.onAdd,
    this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final entries = log.entriesFor(section);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Text(section.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (entries.isNotEmpty) ...[
                  Text(
                    _macroLabel(
                      entries.fold<double>(
                        0,
                        (s, e) => s + e.result.calories.min,
                      ),
                      entries.fold<double>(
                        0,
                        (s, e) => s + e.result.calories.max,
                      ),
                      'kcal',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFF6B35),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF52B788).withValues(alpha: 0.40),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 14,
                          color: Color(0xFF52B788),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF52B788),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Empty slot ────────────────────────────────────
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Nothing logged — tap Add',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
              ),
            )
          else ...[
            const Divider(color: Color(0xFF2E2E3E), height: 1),
            ...entries.map(
              (entry) => _EntryTile(
                entry: entry,
                onTap: onEdit != null ? () => onEdit!(entry) : null,
                onDelete: () => onDelete(entry),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Entry tile ───────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  final MealEntry entry;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ObjectKey(entry),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(0),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFEF4444),
          size: 20,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.fastfood_rounded,
                  size: 14,
                  color: Color(0xFF4B5563),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.finalSavedInput,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _MacroBadge(
                          _macroLabel(
                            entry.result.calories.min,
                            entry.result.calories.max,
                            'kcal',
                          ),
                          const Color(0xFFFF6B35),
                        ),
                        const SizedBox(width: 6),
                        _MacroBadge(
                          _macroLabel(
                            entry.result.protein.min,
                            entry.result.protein.max,
                            'g',
                          ),
                          const Color(0xFF52B788),
                        ),
                        if (entry.edited) ...[
                          const SizedBox(width: 6),
                          const _MacroBadge('Edited', Color(0xFF60A5FA)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.addedAt.hour.toString().padLeft(2, '0')}:'
                    '${entry.addedAt.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  if (onTap != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: Color(0xFF6B7280),
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
}

class _MacroBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _MacroBadge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _macroLabel(double min, double max, String unit) {
  final minI = min.toInt();
  final maxI = max.toInt();
  return minI == maxI ? '$minI $unit' : '$minI–$maxI $unit';
}

// ─── Coach insight card ───────────────────────────────────────────────────────

class _CoachInsightCard extends StatelessWidget {
  final List<CoachInsight> insights;
  const _CoachInsightCard({required this.insights});

  static (IconData, Color) _iconColor(CoachInsightType type) => switch (type) {
    CoachInsightType.protein => (
      Icons.fitness_center_rounded,
      const Color(0xFF52B788),
    ),
    CoachInsightType.overGoal => (
      Icons.warning_amber_rounded,
      const Color(0xFFFFB347),
    ),
    CoachInsightType.underEaten => (
      Icons.restaurant_menu_rounded,
      const Color(0xFF60A5FA),
    ),
    CoachInsightType.balance => (
      Icons.balance_rounded,
      const Color(0xFFA78BFA),
    ),
    CoachInsightType.info => (
      Icons.info_outline_rounded,
      const Color(0xFF9CA3AF),
    ),
  };

  @override
  Widget build(BuildContext context) {
    // Show only the top 2 most relevant insights.
    final top = insights.take(2).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E3550)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(color: Color(0xFF1E2438), height: 1),
            _CoachInsightRow(
              insight: top[i],
              iconColor: _iconColor(top[i].type),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachInsightRow extends StatelessWidget {
  final CoachInsight insight;
  final (IconData, Color) iconColor;
  const _CoachInsightRow({required this.insight, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = iconColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (insight.actionHint != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    insight.actionHint!,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Suggestion card ──────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  final List<MealSuggestion> suggestions;
  final void Function(String text) onSuggestionTap;
  const _SuggestionCard({
    required this.suggestions,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 14,
                  color: Color(0xFFFFB347),
                ),
                SizedBox(width: 6),
                Text(
                  'What to eat next',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF2A2A3A), height: 1),
          // Suggestions
          for (int i = 0; i < suggestions.length; i++) ...[
            if (i > 0)
              const Divider(
                color: Color(0xFF252535),
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
            _SuggestionRow(
              suggestion: suggestions[i],
              onTap: suggestions[i].prefilledText != null
                  ? () => onSuggestionTap(suggestions[i].prefilledText!)
                  : null,
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final MealSuggestion suggestion;
  final VoidCallback? onTap;
  const _SuggestionRow({required this.suggestion, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${suggestion.title}  •  ${suggestion.quantity}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    suggestion.reason,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 10),
              const Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: Color(0xFF52B788),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
