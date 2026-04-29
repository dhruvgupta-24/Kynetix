import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/onboarding_screen.dart';
import '../services/health_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../services/profile_service.dart';

// ─── Profile Screen ────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileChanged;

  const ProfileScreen({super.key, this.onProfileChanged});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile get _profile => currentUserProfile!;
  WeeklyTargetPlan get _plan => NutritionTargetEngine().weeklyPlan(
    _profile,
    health: _profile.healthSyncEnabled && _profile.averageDailySteps != null
        ? HealthSyncResult(
            effectiveAverageSteps: _profile.averageDailySteps!.toDouble(),
            averageDailySteps14d: _profile.averageDailySteps!.toDouble(),
            averageDailySteps30d: _profile.averageDailySteps!.toDouble(),
            syncedAt: _profile.lastHealthSyncAt ?? DateTime.now(),
            activityTier: _tierFromPersistedSteps(_profile.averageDailySteps!),
          )
        : null,
  );

  bool _syncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _doSync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });

    final hasPerm = await HealthService().hasPermission();
    if (!hasPerm) {
      final granted = await HealthService().requestPermission();
      if (!granted) {
        if (mounted) {
          setState(() {
            _syncing = false;
            _syncMessage = 'Permission denied.';
          });
        }
        return;
      }
    }

    final result = await HealthService().sync();
    if (!mounted) return;

    if (!result.hasError && result.hasData) {
      currentUserProfile = currentUserProfile!.copyWithHealth(
        averageDailySteps: result.effectiveAverageSteps!.toInt(),
        lastHealthSyncAt: result.syncedAt,
      );
      PersistenceService.saveProfile(currentUserProfile!).ignore();
      widget.onProfileChanged?.call();
      _syncMessage =
          'Synced — ${result.effectiveAverageSteps!.toInt()} steps/day effective';
    } else {
      _syncMessage = result.error ?? 'No step data found.';
    }

    setState(() => _syncing = false);
  }

  void _saveProfile(UserProfile newProfile) {
    currentUserProfile = newProfile;
    PersistenceService.saveProfile(currentUserProfile!).ignore();
    ProfileService.instance.upsertProfile(currentUserProfile!).ignore(); // Upload to cloud
    widget.onProfileChanged?.call();
    setState(() {});
  }

  // ── Sheets ─────────────────────────────────────────────────────────────────

  void _editGoal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Select Goal',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ...[
                  kFatLoss,
                  kMaintenance,
                  kLeanBulk,
                  kBulk,
                  kRecomposition,
                ].map((g) {
                  final isSel = g == _profile.goal;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      g,
                      style: TextStyle(
                        color: isSel ? const Color(0xFF52B788) : Colors.white,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: isSel
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF52B788),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _saveProfile(_profile.copyWith(goal: g));
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editNumber(
    String title,
    String currentVal,
    String suffix,
    void Function(double) onSave,
  ) {
    final ctrl = TextEditingController(text: currentVal);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update $title',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      suffixText: suffix,
                      suffixStyle: const TextStyle(color: Color(0xFF6B7280)),
                      hintText: title,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final val = double.tryParse(ctrl.text.trim());
                        if (val != null) {
                          onSave(val);
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          _buildProfileCard(),
          const SizedBox(height: 16),
          _buildBodyCard(),
          const SizedBox(height: 16),
          _buildGoalCard(),
          const SizedBox(height: 16),
          _buildHealthCard(),
          const SizedBox(height: 16),
          _buildAiCard(),
          const SizedBox(height: 16),
          _buildAboutCard(),
        ],
      ),
    );
  }

  // ── Profile Banner ─────────────────────────────────────────────────────────

  Widget _buildProfileCard() {
    return _Section(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                _profile.gender == 'Male' ? '👨' : '👩',
                style: const TextStyle(fontSize: 34),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profile.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                _GoalChip(goal: _profile.goal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Body Metrics ───────────────────────────────────────────────────────────

  Widget _buildBodyCard() {
    return _Section(
      title: 'Body Metrics',
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Gender',
            value: _profile.gender,
          ),
          _InfoRow(
            icon: Icons.cake_outlined,
            label: 'Age',
            value: '${_profile.age} years',
            isEditable: true,
            onTap: () => _editNumber(
              'Age',
              _profile.age.toString(),
              'years',
              (v) => _saveProfile(_profile.copyWith(age: v.toInt())),
            ),
          ),
          _InfoRow(
            icon: Icons.height_rounded,
            label: 'Height',
            value: '${_profile.height.toStringAsFixed(1)} cm',
            isEditable: true,
            onTap: () => _editNumber(
              'Height',
              _profile.height.toString(),
              'cm',
              (v) => _saveProfile(_profile.copyWith(height: v)),
            ),
          ),
          _InfoRow(
            icon: Icons.monitor_weight_outlined,
            label: 'Weight',
            value: '${_profile.weight.toStringAsFixed(1)} kg',
            isEditable: true,
            onTap: () => _editNumber(
              'Weight',
              _profile.weight.toString(),
              'kg',
              (v) => _saveProfile(_profile.copyWith(weight: v)),
            ),
          ),
          _InfoRow(
            icon: Icons.calculate_outlined,
            label: 'BMI',
            value: _profile.bmi.toStringAsFixed(1),
            isLast: true,
          ),
        ],
      ),
    );
  }

  // ── Goal & Activity ────────────────────────────────────────────────────────

  Widget _buildGoalCard() {
    final freqLabel = _profile.workoutDaysMin == _profile.workoutDaysMax
        ? '${_profile.workoutDaysMin}×/week'
        : '${_profile.workoutDaysMin}–${_profile.workoutDaysMax}×/week';
    final plan = _plan;

    return _Section(
      title: 'Goal Settings',
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.flag_rounded,
            label: 'Goal',
            value: _profile.goal,
            isEditable: true,
            onTap: _editGoal,
          ),
          _InfoRow(
            icon: Icons.fitness_center_rounded,
            label: 'Workouts',
            value: freqLabel,
          ),
          _InfoRow(
            icon: Icons.local_fire_department_rounded,
            label: 'Maintenance',
            value: '${plan.maintenanceCalories.toStringAsFixed(0)} kcal',
          ),
          _InfoRow(
            icon: Icons.bolt_rounded,
            label: 'Base Target',
            value: '${plan.avgDailyCalories.toStringAsFixed(0)} kcal',
          ),
          _InfoRow(
            icon: Icons.egg_outlined,
            label: 'Base Protein',
            value: '${plan.avgDailyProtein.toStringAsFixed(0)} g',
            isLast: true,
          ),
        ],
      ),
    );
  }

  // ── Health Connect ─────────────────────────────────────────────────────────

  Widget _buildHealthCard() {
    final synced = _profile.healthSyncEnabled;
    final steps = _profile.averageDailySteps;
    final syncAt = _profile.lastHealthSyncAt;

    String syncTimeLabel = 'Never synced';
    if (syncAt != null) {
      syncTimeLabel =
          '${syncAt.day}/${syncAt.month} at '
          '${syncAt.hour.toString().padLeft(2, '0')}:${syncAt.minute.toString().padLeft(2, '0')}';
    }

    final stepOffset = _profile.healthSyncEnabled && steps != null
        ? _stepOffsetLabel(steps)
        : null;

    return _Section(
      title: 'Health Connect',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                synced ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 16,
                color: synced
                    ? const Color(0xFF52B788)
                    : const Color(0xFF4B5563),
              ),
              const SizedBox(width: 8),
              Text(
                synced ? 'Connected' : 'Not connected',
                style: TextStyle(
                  color: synced
                      ? const Color(0xFF52B788)
                      : const Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _syncing ? null : _doSync,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF52B788).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF52B788).withValues(alpha: 0.4),
                    ),
                  ),
                  child: _syncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF52B788),
                          ),
                        )
                      : Text(
                          synced ? 'Sync Now' : 'Connect',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF52B788),
                          ),
                        ),
                ),
              ),
            ],
          ),

          if (_syncMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _syncMessage!,
              style: TextStyle(
                fontSize: 11,
                color: _syncMessage!.contains('Synced')
                    ? const Color(0xFF52B788)
                    : const Color(0xFFFFB347),
              ),
            ),
          ],

          if (synced) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2E2E3E), height: 1),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.directions_walk_rounded,
              label: 'Avg Steps',
              value: steps != null ? '${steps.toStringAsFixed(0)}/day' : '—',
            ),
            _InfoRow(
              icon: Icons.tune_rounded,
              label: 'Calorie Correction',
              value: stepOffset ?? '—',
            ),
            _InfoRow(
              icon: Icons.schedule_rounded,
              label: 'Last Sync',
              value: syncTimeLabel,
              isLast: true,
            ),
          ],
        ],
      ),
    );
  }

  /// Shows the actual weight-aware calorie offset for the persisted step count.
  /// Uses the same formula as NutritionTargetEngine._stepCorrectionKcal.
  String _stepOffsetLabel(int steps) {
    final weight = _profile.weight;
    const baseline = 7000.0;
    const strideKm = 0.00075;
    const metFactor = 0.55;
    final kcalPerStep = weight * strideKm * metFactor;
    final rawOffset = ((steps - baseline) * kcalPerStep).clamp(-400.0, 400.0).round();
    final sign = rawOffset >= 0 ? '+' : '';
    return '$sign$rawOffset kcal vs baseline';
  }

  ActivityTier _tierFromPersistedSteps(int steps) {
    if (steps < 4000)  return ActivityTier.sedentary;
    if (steps < 7000)  return ActivityTier.light;
    if (steps < 10000) return ActivityTier.moderate;
    if (steps < 13000) return ActivityTier.active;
    return ActivityTier.veryActive;
  }

  // ── AI Engine Info ───────────────────────────────────────────────────────────

  Widget _buildAiCard() {
    return _Section(
      title: 'AI Engine',
      child: Column(
        children: const [
          _InfoRow(
            icon: Icons.auto_awesome_rounded,
            label: 'Provider',
            value: 'OpenAI (gpt-4o-mini)',
          ),
          _InfoRow(
            icon: Icons.swap_horiz_rounded,
            label: 'Fallback',
            value: 'OpenRouter (auto)',
            isLast: true,
          ),
        ],
      ),
    );
  }

  // ── About ──────────────────────────────────────────────────────────────────

  Widget _buildAboutCard() {
    return _Section(
      title: 'About Kynetix',
      child: Column(
        children: const [
          _InfoRow(
            icon: Icons.info_outline_rounded,
            label: 'Version',
            value: '1.0.0',
          ),
          _InfoRow(
            icon: Icons.restaurant_menu_rounded,
            label: 'Engine',
            value: 'Kynetix Indian Caloric Baseline',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

// ─── Section wrapper ──────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Section({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title!.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ],
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;
  final bool isEditable;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
    this.isEditable = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF4B5563)),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isEditable) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.edit_rounded,
                  size: 12,
                  color: Color(0xFF52B788),
                ),
              ],
            ],
          ),
        ),
        if (!isLast) const Divider(color: Color(0xFF2E2E3E), height: 1),
      ],
    );

    if (isEditable && onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}

// ─── Goal chip ────────────────────────────────────────────────────────────────

class _GoalChip extends StatelessWidget {
  final String goal;
  const _GoalChip({required this.goal});

  Color get _color => switch (goal) {
    kFatLoss => const Color(0xFFFF6B35),
    kMaintenance => const Color(0xFF52B788),
    kLeanBulk => const Color(0xFF60A5FA),
    kBulk => const Color(0xFF3B82F6),
    kRecomposition => const Color(0xFFA78BFA),
    _ => const Color(0xFF52B788),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        goal,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}
