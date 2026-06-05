import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../screens/onboarding_screen.dart';
import '../screens/connect_chatgpt_screen.dart';
import '../screens/nutrition_intelligence_screen.dart';
import '../screens/auth_gate.dart';
import '../services/chatgpt_link_service.dart';
import '../services/health_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/insights_report_service.dart';
import 'insights_screen.dart';

enum ProviderHealth { operational, degraded, setupRequired }

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

  // ── AI provider state ─────────────────────────────────────────────────────
  ChatGptLinkStatus? _aiStatus;
  bool _aiStatusLoading = true;
  bool _aiDisconnecting = false;

  bool _enableRpeTracking = false;

  @override
  void initState() {
    super.initState();
    _loadAiStatus();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _enableRpeTracking = prefs.getBool('enable_rpe_tracking') ?? false;
      });
    }
  }

  Future<void> _loadAiStatus() async {
    setState(() => _aiStatusLoading = true);
    try {
      final status = await ChatGptLinkService.getStatus();
      if (mounted) setState(() { _aiStatus = status; _aiStatusLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _aiStatus = ChatGptLinkStatus.disconnected; _aiStatusLoading = false; });
    }
  }

  Future<void> _disconnectChatGpt() async {
    setState(() => _aiDisconnecting = true);
    try {
      await ChatGptLinkService.disconnect();
      await _loadAiStatus();
    } finally {
      if (mounted) setState(() => _aiDisconnecting = false);
    }
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
      backgroundColor: KColor.card,
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
                const KSheetHeader('Select Goal'),
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
                        color: isSel ? KColor.green : Colors.white,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: isSel
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: KColor.green,
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

  void _editEatingStyle() {
    showModalBottomSheet(
      context: context,
      backgroundColor: KColor.card,
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
                const KSheetHeader('Eating Style', subtitle: 'How do you eat a meal with roti or rice?'),
                const SizedBox(height: 10),
                ...PortionAnchor.values.map((anchor) {
                  final isSel = anchor == _profile.portionAnchor;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      anchor.displayLabel,
                      style: TextStyle(
                        color: isSel ? KColor.green : Colors.white,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: isSel
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: KColor.green,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _saveProfile(_profile.copyWith(portionAnchor: anchor));
                    },
                  );
                }),
                // Not specified option
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(
                    'Not specified',
                    style: TextStyle(
                      color: _profile.portionAnchor == null
                          ? KColor.green
                          : Colors.white,
                      fontWeight: _profile.portionAnchor == null
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: _profile.portionAnchor == null
                      ? const Icon(Icons.check_circle_rounded,
                          color: KColor.green)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    // Save with portionAnchor explicitly null by rebuilding profile
                    currentUserProfile = UserProfile(
                      name:              _profile.name,
                      age:               _profile.age,
                      gender:            _profile.gender,
                      height:            _profile.height,
                      weight:            _profile.weight,
                      workoutDaysMin:    _profile.workoutDaysMin,
                      workoutDaysMax:    _profile.workoutDaysMax,
                      goal:              _profile.goal,
                      portionAnchor:     null,
                      averageDailySteps: _profile.averageDailySteps,
                      healthSyncEnabled: _profile.healthSyncEnabled,
                      lastHealthSyncAt:  _profile.lastHealthSyncAt,
                    );
                    PersistenceService.saveProfile(currentUserProfile!).ignore();
                    ProfileService.instance.upsertProfile(currentUserProfile!).ignore();
                    widget.onProfileChanged?.call();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editBodyMetrics() {
    final ageCtrl = TextEditingController(text: _profile.age.toString());
    final heightCtrl = TextEditingController(text: _profile.height.toStringAsFixed(1));
    final weightCtrl = TextEditingController(text: _profile.weight.toStringAsFixed(1));
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      backgroundColor: KColor.card,
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
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KSheetHeader('Body Metrics', subtitle: 'Update metrics for accurate daily calculations'),
                    const SizedBox(height: 16),
                    _buildFormInput(
                      controller: ageCtrl,
                      label: 'Age',
                      suffix: 'years',
                      keyboardType: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Age is required';
                        final numVal = int.tryParse(val);
                        if (numVal == null || numVal < 1 || numVal > 120) return 'Enter a valid age (1-120)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildFormInput(
                      controller: heightCtrl,
                      label: 'Height',
                      suffix: 'cm',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      formatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Height is required';
                        final numVal = double.tryParse(val);
                        if (numVal == null || numVal < 50 || numVal > 280) return 'Enter a valid height (50-280 cm)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildFormInput(
                      controller: weightCtrl,
                      label: 'Weight',
                      suffix: 'kg',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      formatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Weight is required';
                        final numVal = double.tryParse(val);
                        if (numVal == null || numVal < 20 || numVal > 400) return 'Enter a valid weight (20-400 kg)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    KButton(
                      label: 'Save Metrics',
                      onTap: () {
                        if (formKey.currentState?.validate() ?? false) {
                          final age = int.tryParse(ageCtrl.text) ?? _profile.age;
                          final height = double.tryParse(heightCtrl.text) ?? _profile.height;
                          final weight = double.tryParse(weightCtrl.text) ?? _profile.weight;
                          
                          _saveProfile(_profile.copyWith(
                            age: age,
                            height: height,
                            weight: weight,
                          ));
                          Navigator.pop(ctx);
                        } else {
                          kHapticMedium();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormInput({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required TextInputType keyboardType,
    required List<TextInputFormatter> formatters,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: KColor.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            suffixText: suffix,
            suffixStyle: const TextStyle(color: KColor.textMuted, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF13131F),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            errorStyle: const TextStyle(color: KColor.danger, fontSize: 11),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: KColor.green, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: KColor.danger, width: 1),
            ),
          ),
        ),
      ],
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
          _buildLiftingMetricsCard(),
          const SizedBox(height: 16),
          _buildNutritionTargetsCard(),
          const SizedBox(height: 16),
          _buildHealthCard(),
          const SizedBox(height: 16),
          _buildNutritionIntelligenceCard(),
          const SizedBox(height: 16),
          _buildAiCard(),
          const SizedBox(height: 16),
          _buildInsightsCard(),
          const SizedBox(height: 16),
          _buildAboutCard(),
          const SizedBox(height: 24),
          _buildLogoutButton(),
        ],
      ),
    );
  }

  // ── Profile Banner ─────────────────────────────────────────────────────────

  Widget _buildProfileCard() {
    return _Section(
      child: Row(
        children: [
          Builder(
            builder: (context) {
              final user = Supabase.instance.client.auth.currentUser;
              final avatarUrl = user?.userMetadata?['avatar_url'] ?? user?.userMetadata?['picture'] as String?;

              String getInitials(String name) {
                if (name.isEmpty) return 'K';
                final parts = name.trim().split(RegExp(r'\s+'));
                if (parts.length == 1) {
                  return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
                }
                return (parts.first[0] + parts.last[0]).toUpperCase();
              }

              final initials = getInitials(_profile.name);

              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 64,
                  height: 64,
                  color: const Color(0xFF2D6A4F),
                  child: avatarUrl != null && avatarUrl.isNotEmpty
                      ? Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              );
            },
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
            onTap: _editBodyMetrics,
          ),
          _InfoRow(
            icon: Icons.height_rounded,
            label: 'Height',
            value: '${_profile.height.toStringAsFixed(1)} cm',
            isEditable: true,
            onTap: _editBodyMetrics,
          ),
          _InfoRow(
            icon: Icons.monitor_weight_outlined,
            label: 'Weight',
            value: '${_profile.weight.toStringAsFixed(1)} kg',
            isEditable: true,
            onTap: _editBodyMetrics,
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
            icon: Icons.restaurant_outlined,
            label: 'Eating Style',
            value: _profile.portionAnchor?.displayLabel ?? 'Not specified',
            isEditable: true,
            onTap: _editEatingStyle,
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

  Widget _buildLiftingMetricsCard() {
    return _Section(
      title: 'Advanced Lifting Metrics',
      child: SwitchListTile(
        title: const Text(
          'Enable RPE Tracking',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: const Text(
          'Rate of Perceived Exertion (1-10 scale) for sets',
          style: TextStyle(
            color: KColor.textMuted,
            fontSize: 12,
          ),
        ),
        value: _enableRpeTracking,
        activeColor: KColor.green,
        activeTrackColor: KColor.green.withValues(alpha: 0.2),
        inactiveTrackColor: const Color(0xFF1F1F2F),
        contentPadding: EdgeInsets.zero,
        onChanged: (val) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('enable_rpe_tracking', val);
          setState(() {
            _enableRpeTracking = val;
          });
        },
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
      title: 'Connected AI',
      child: _aiStatusLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF52B788),
                  ),
                ),
              ),
            )
          : _buildAiStatusBody(),
    );
  }

  ProviderHealth get _providerHealth {
    final s = _aiStatus ?? ChatGptLinkStatus.disconnected;
    if (!s.isConnected) {
      return ProviderHealth.setupRequired;
    }
    if (s.fallbackReason != null) {
      return ProviderHealth.degraded;
    }
    return ProviderHealth.operational;
  }

  Widget _buildAiStatusBody() {
    final s = _aiStatus ?? ChatGptLinkStatus.disconnected;
    final isConnected = s.isConnected;
    final health = _providerHealth;
    
    Color statusColor;
    String statusLabel;
    switch (health) {
      case ProviderHealth.operational:
        statusColor = const Color(0xFF52B788); // Green
        statusLabel = 'Operational';
        break;
      case ProviderHealth.degraded:
        statusColor = const Color(0xFFFFB347); // Amber
        statusLabel = 'Degraded (Backup Server)';
        break;
      case ProviderHealth.setupRequired:
        statusColor = const Color(0xFF9CA3AF); // Gray
        statusLabel = 'Setup Required';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Status and Connect Row ──────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            // Connect / Disconnect button
            GestureDetector(
              onTap: _aiDisconnecting
                  ? null
                  : isConnected
                      ? _disconnectChatGpt
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ConnectChatGptScreen(),
                            ),
                          );
                          _loadAiStatus();
                        },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isConnected ? const Color(0xFFEF4444).withValues(alpha: 0.12) : const Color(0xFF52B788).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isConnected ? const Color(0xFFEF4444).withValues(alpha: 0.4) : const Color(0xFF52B788).withValues(alpha: 0.4)
                  ),
                ),
                child: _aiDisconnecting
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF52B788),
                        ),
                      )
                    : Text(
                        isConnected ? 'Disconnect' : 'Connect',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isConnected ? const Color(0xFFEF4444) : const Color(0xFF52B788),
                        ),
                      ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2E2E3E), height: 1),
        const SizedBox(height: 8),

        // Descriptive prompt / subtitle
        Text(
          isConnected
              ? (health == ProviderHealth.operational
                  ? 'Your personal AI connection is active. Meals are analyzed using your account credits.'
                  : 'Your personal AI connection is active but fell back to our backup server due to a connection error.')
              : 'Meals are analyzed using our shared servers. Connect your account to use your own premium credits.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
            height: 1.5,
          ),
        ),

        const SizedBox(height: 8),
        
        // Expandable drawer for Advanced Diagnostics (Connection Details)
        Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: KColor.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Connection Details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            iconColor: Colors.white.withValues(alpha: 0.6),
            collapsedIconColor: Colors.white.withValues(alpha: 0.4),
            children: [
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.cloud_queue_rounded,
                label: 'Connected Service',
                value: _providerDisplayName(s.activeProvider),
              ),
              _InfoRow(
                icon: Icons.psychology_rounded,
                label: 'Analysis Service',
                value: s.selectedModel ?? (isConnected ? 'Discovering…' : '—'),
              ),
              _InfoRow(
                icon: Icons.access_time_rounded,
                label: 'Last Used',
                value: _relativeTime(s.lastUsedAt),
              ),
              _InfoRow(
                icon: Icons.sync_rounded,
                label: 'Connection Status',
                value: isConnected ? 'Connected' : 'Disconnected',
              ),
              if (isConnected) ...[
                _InfoRow(
                  icon: Icons.refresh_rounded,
                  label: 'Last Token Refresh',
                  value: _relativeTime(s.lastRefreshedAt),
                ),
                _InfoRow(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Last Connection Test',
                  value: s.testGenerationSnippet != null ? '"${s.testGenerationSnippet}"' : '—',
                ),
                _InfoRow(
                  icon: Icons.schedule_rounded,
                  label: 'Connected',
                  value: _relativeTime(s.connectedAt),
                ),
              ],
              if (s.fallbackReason != null) ...[
                _InfoRow(
                  icon: Icons.warning_amber_rounded,
                  label: 'Backup Reason',
                  value: _fallbackReasonDisplayName(s.fallbackReason),
                ),
              ],
              _InfoRow(
                icon: Icons.verified_rounded,
                label: 'Service Verified',
                value: s.modelDiscoveryVerified ? 'Yes' : (isConnected ? 'Pending' : '—'),
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _providerDisplayName(String? raw) {
    if (raw == null) return '—';
    return switch (raw) {
      'user_chatgpt' => 'Direct Connection',
      'openrouter'   => 'Shared Server',
      'openai'       => 'Direct Connection',
      _              => raw,
    };
  }

  String _fallbackReasonDisplayName(String? reason) {
    if (reason == null) return '—';
    return switch (reason) {
      'account_disconnected' => 'Account Disconnected',
      'token_expired'        => 'Token Expired',
      'refresh_failed'       => 'Refresh Failed',
      'model_unavailable'    => 'Service Unavailable',
      'api_error'            => 'Connection Error (analysis failed)',
      _                      => reason,
    };
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Nutrition Intelligence ─────────────────────────────────────────────────

  Widget _buildNutritionIntelligenceCard() {
    return _Section(
      title: 'Food Library',
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.psychology_rounded,
            label: 'Food Library',
            value: 'Portion history & custom foods',
            isEditable: true,
            isLast: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NutritionIntelligenceScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ── Insights & Progress ────────────────────────────────────────────────────

  Widget _buildInsightsCard() {
    return ListenableBuilder(
      listenable: InsightsReportService.instance,
      builder: (context, _) {
        final newCount = InsightsReportService.instance.newAchievementCount;
        return _Section(
          title: 'Insights & Progress',
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.insights_rounded,
                label: 'Insights & Reports',
                value: newCount > 0 ? '$newCount new' : 'View history & achievements',
                isEditable: true,
                isLast: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InsightsScreen()),
                ),
              ),
            ],
          ),
        );
      },
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
            label: 'Baseline Formula',
            value: 'Kynetix Indian Caloric Baseline',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionTargetsCard() {
    final profile = _profile;
    final enginePlan = NutritionTargetEngine().weeklyPlan(
      profile.copyWith(useCustomTargets: false),
      health: profile.healthSyncEnabled && profile.averageDailySteps != null
          ? HealthSyncResult(
              effectiveAverageSteps: profile.averageDailySteps!.toDouble(),
              averageDailySteps14d: profile.averageDailySteps!.toDouble(),
              averageDailySteps30d: profile.averageDailySteps!.toDouble(),
              syncedAt: profile.lastHealthSyncAt ?? DateTime.now(),
              activityTier: _tierFromPersistedSteps(profile.averageDailySteps!),
            )
          : null,
    );
    final activePlan = _plan;

    return _Section(
      title: 'Nutrition Targets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Target Setting',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSourceChip(
                label: 'System Calculated',
                selected: !profile.useCustomTargets,
                onTap: () {
                  if (profile.useCustomTargets) {
                    _changeTargetSource(useCustom: false);
                  }
                },
              ),
              const SizedBox(width: 8),
              _buildSourceChip(
                label: 'Custom Targets',
                selected: profile.useCustomTargets,
                onTap: () {
                  if (!profile.useCustomTargets) {
                    _changeTargetSource(useCustom: true);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2E2E3E), height: 1),
          const SizedBox(height: 12),

          if (!profile.useCustomTargets) ...[
            _InfoRow(
              icon: Icons.local_fire_department_rounded,
              label: 'Maintenance Calories',
              value: '${activePlan.maintenanceCalories.toStringAsFixed(0)} kcal',
            ),
            _InfoRow(
              icon: Icons.bolt_rounded,
              label: 'Training Day Calories',
              value: '${activePlan.trainingDayCalories.toStringAsFixed(0)} kcal',
            ),
            _InfoRow(
              icon: Icons.nightlight_round,
              label: 'Rest Day Calories',
              value: '${activePlan.restDayCalories.toStringAsFixed(0)} kcal',
            ),
            _InfoRow(
              icon: Icons.egg_outlined,
              label: 'Daily Protein Target',
              value: '${activePlan.avgDailyProtein.toStringAsFixed(0)} g',
              isLast: true,
            ),
          ] else ...[
            _InfoRow(
              icon: Icons.local_fire_department_rounded,
              label: 'Maintenance Calories',
              value: '${(profile.customMaintenanceCalories ?? enginePlan.maintenanceCalories).toStringAsFixed(0)} kcal',
              isEditable: true,
              onTap: () => _editCustomTargetValue(
                title: 'Maintenance Calories',
                minValue: 800,
                maxValue: 6000,
                currentValue: profile.customMaintenanceCalories ?? enginePlan.maintenanceCalories,
                onSave: (val) {
                  final prev = {
                    'useCustomTargets': profile.useCustomTargets,
                    'customMaintenanceCalories': profile.customMaintenanceCalories,
                    'customTrainingDayCalories': profile.customTrainingDayCalories,
                    'customRestDayCalories': profile.customRestDayCalories,
                    'customProteinTarget': profile.customProteinTarget,
                  };
                  final updated = profile.copyWith(
                    customMaintenanceCalories: val,
                    targetChangeHistory: [
                      ...profile.targetChangeHistory,
                      TargetChangeRecord(
                        timestamp: DateTime.now(),
                        sourceType: 'Custom Targets',
                        maintenanceCalories: val,
                        trainingDayCalories: profile.customTrainingDayCalories,
                        restDayCalories: profile.customRestDayCalories,
                        proteinTarget: profile.customProteinTarget,
                        previousValues: prev,
                      ),
                    ],
                  );
                  _saveProfile(updated);
                },
              ),
            ),
            _InfoRow(
              icon: Icons.bolt_rounded,
              label: 'Training Day Calories',
              value: '${(profile.customTrainingDayCalories ?? enginePlan.trainingDayCalories).toStringAsFixed(0)} kcal',
              isEditable: true,
              onTap: () => _editCustomTargetValue(
                title: 'Training Day Calories',
                minValue: 800,
                maxValue: 6000,
                currentValue: profile.customTrainingDayCalories ?? enginePlan.trainingDayCalories,
                onSave: (val) {
                  final prev = {
                    'useCustomTargets': profile.useCustomTargets,
                    'customMaintenanceCalories': profile.customMaintenanceCalories,
                    'customTrainingDayCalories': profile.customTrainingDayCalories,
                    'customRestDayCalories': profile.customRestDayCalories,
                    'customProteinTarget': profile.customProteinTarget,
                  };
                  final updated = profile.copyWith(
                    customTrainingDayCalories: val,
                    targetChangeHistory: [
                      ...profile.targetChangeHistory,
                      TargetChangeRecord(
                        timestamp: DateTime.now(),
                        sourceType: 'Custom Targets',
                        maintenanceCalories: profile.customMaintenanceCalories,
                        trainingDayCalories: val,
                        restDayCalories: profile.customRestDayCalories,
                        proteinTarget: profile.customProteinTarget,
                        previousValues: prev,
                      ),
                    ],
                  );
                  _saveProfile(updated);
                },
              ),
            ),
            _InfoRow(
              icon: Icons.nightlight_round,
              label: 'Rest Day Calories',
              value: '${(profile.customRestDayCalories ?? enginePlan.restDayCalories).toStringAsFixed(0)} kcal',
              isEditable: true,
              onTap: () => _editCustomTargetValue(
                title: 'Rest Day Calories',
                minValue: 800,
                maxValue: 6000,
                currentValue: profile.customRestDayCalories ?? enginePlan.restDayCalories,
                onSave: (val) {
                  final prev = {
                    'useCustomTargets': profile.useCustomTargets,
                    'customMaintenanceCalories': profile.customMaintenanceCalories,
                    'customTrainingDayCalories': profile.customTrainingDayCalories,
                    'customRestDayCalories': profile.customRestDayCalories,
                    'customProteinTarget': profile.customProteinTarget,
                  };
                  final updated = profile.copyWith(
                    customRestDayCalories: val,
                    targetChangeHistory: [
                      ...profile.targetChangeHistory,
                      TargetChangeRecord(
                        timestamp: DateTime.now(),
                        sourceType: 'Custom Targets',
                        maintenanceCalories: profile.customMaintenanceCalories,
                        trainingDayCalories: profile.customTrainingDayCalories,
                        restDayCalories: val,
                        proteinTarget: profile.customProteinTarget,
                        previousValues: prev,
                      ),
                    ],
                  );
                  _saveProfile(updated);
                },
              ),
            ),
            _InfoRow(
              icon: Icons.egg_outlined,
              label: 'Daily Protein Target',
              value: '${(profile.customProteinTarget ?? enginePlan.avgDailyProtein).toStringAsFixed(0)} g',
              isEditable: true,
              onTap: () => _editCustomTargetValue(
                title: 'Daily Protein Target',
                minValue: 30,
                maxValue: 350,
                currentValue: profile.customProteinTarget ?? enginePlan.avgDailyProtein,
                onSave: (val) {
                  final prev = {
                    'useCustomTargets': profile.useCustomTargets,
                    'customMaintenanceCalories': profile.customMaintenanceCalories,
                    'customTrainingDayCalories': profile.customTrainingDayCalories,
                    'customRestDayCalories': profile.customRestDayCalories,
                    'customProteinTarget': profile.customProteinTarget,
                  };
                  final updated = profile.copyWith(
                    customProteinTarget: val,
                    targetChangeHistory: [
                      ...profile.targetChangeHistory,
                      TargetChangeRecord(
                        timestamp: DateTime.now(),
                        sourceType: 'Custom Targets',
                        maintenanceCalories: profile.customMaintenanceCalories,
                        trainingDayCalories: profile.customTrainingDayCalories,
                        restDayCalories: profile.customRestDayCalories,
                        proteinTarget: val,
                        previousValues: prev,
                      ),
                    ],
                  );
                  _saveProfile(updated);
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _resetToRecommendations,
                icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF52B788)),
                label: const Text(
                  'Reset to Recommendations',
                  style: TextStyle(color: Color(0xFF52B788), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: const Color(0xFF52B788).withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2E2E3E), height: 1),
          const SizedBox(height: 16),

          Row(
            children: [
              const Icon(Icons.cached_rounded, size: 18, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Calorie Carry-Forward',
                      style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Adjust next day\'s target for yesterday\'s deviations',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: profile.carryForwardEnabled,
                activeThumbColor: const Color(0xFF52B788),
                activeTrackColor: const Color(0xFF52B788).withValues(alpha: 0.2),
                inactiveThumbColor: const Color(0xFF4B5563),
                inactiveTrackColor: const Color(0xFF1E1E2C),
                onChanged: (val) {
                  _saveProfile(profile.copyWith(carryForwardEnabled: val));
                },
              ),
            ],
          ),

          if (profile.carryForwardEnabled) ...[
            const SizedBox(height: 16),
            const Text(
              'Carry-forward threshold',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildThresholdChip(100),
                _buildThresholdChip(150),
                _buildThresholdChip(200),
                _buildThresholdChip(250),
                _buildCustomThresholdChip(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF52B788).withValues(alpha: 0.12)
                : const Color(0xFF13131F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF52B788)
                  : const Color(0xFF2E2E3E),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: selected ? const Color(0xFF52B788) : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdChip(int kcal) {
    final selected = _profile.carryForwardThreshold == kcal;
    return GestureDetector(
      onTap: () {
        _saveProfile(_profile.copyWith(carryForwardThreshold: kcal));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF52B788).withValues(alpha: 0.12)
              : const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF52B788) : const Color(0xFF2E2E3E),
          ),
        ),
        child: Text(
          '$kcal kcal',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? const Color(0xFF52B788) : const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomThresholdChip() {
    final currentThreshold = _profile.carryForwardThreshold;
    final isPreset = const [100, 150, 200, 250].contains(currentThreshold);
    final selected = !isPreset;

    final label = selected ? 'Custom ($currentThreshold kcal)' : 'Custom...';

    return GestureDetector(
      onTap: _promptCustomThreshold,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF52B788).withValues(alpha: 0.12)
              : const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF52B788) : const Color(0xFF2E2E3E),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected ? const Color(0xFF52B788) : const Color(0xFF9CA3AF),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, size: 10, color: Color(0xFF52B788)),
            ],
          ],
        ),
      ),
    );
  }

  void _changeTargetSource({required bool useCustom}) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          title: Text(
            useCustom ? 'Switch to Custom Targets?' : 'Switch to Calculated Targets?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            useCustom
                ? 'Your nutrition targets will be determined by values you manually set instead of automatically calculating them from your profile settings.'
                : 'Your nutrition targets will revert to automatically calculated recommendations matching your weight, height, age, steps, and goal.',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final prev = {
                  'useCustomTargets': _profile.useCustomTargets,
                  'customMaintenanceCalories': _profile.customMaintenanceCalories,
                  'customTrainingDayCalories': _profile.customTrainingDayCalories,
                  'customRestDayCalories': _profile.customRestDayCalories,
                  'customProteinTarget': _profile.customProteinTarget,
                };
                final updated = _profile.copyWith(
                  useCustomTargets: useCustom,
                  targetChangeHistory: [
                    ..._profile.targetChangeHistory,
                    TargetChangeRecord(
                      timestamp: DateTime.now(),
                      sourceType: useCustom ? 'Custom Targets' : 'System Calculated',
                      maintenanceCalories: _profile.customMaintenanceCalories,
                      trainingDayCalories: _profile.customTrainingDayCalories,
                      restDayCalories: _profile.customRestDayCalories,
                      proteinTarget: _profile.customProteinTarget,
                      previousValues: prev,
                    ),
                  ],
                );
                _saveProfile(updated);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF52B788),
                foregroundColor: const Color(0xFF0F0F14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _editCustomTargetValue({
    required String title,
    required double minValue,
    required double maxValue,
    required double currentValue,
    required void Function(double) onSave,
  }) {
    final ctrl = TextEditingController(text: currentValue.toStringAsFixed(0));
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: KColor.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: KColor.border, width: 0.5),
          ),
          title: Text(
            'Edit $title',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter a value between ${minValue.toInt()} and ${maxValue.toInt()}.',
                  style: const TextStyle(color: KColor.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: title.contains('Protein') ? 'Protein (g)' : 'Calories (kcal)',
                    labelStyle: const TextStyle(color: KColor.textMuted),
                    filled: true,
                    fillColor: const Color(0xFF13131F),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: KColor.green, width: 1),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Value required';
                    final numVal = double.tryParse(value);
                    if (numVal == null) return 'Invalid number';
                    if (numVal < minValue || numVal > maxValue) {
                      return 'Must be within ${minValue.toInt()}–${maxValue.toInt()}';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: KColor.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final val = double.tryParse(ctrl.text.trim()) ?? currentValue;
                  Navigator.pop(ctx);
                  _confirmValueChange(title, currentValue, val, onSave);
                } else {
                  kHapticMedium();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: KColor.greenDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _confirmValueChange(
    String title,
    double oldVal,
    double newVal,
    void Function(double) onSave,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          title: Text(
            'Confirm $title Change',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            'Are you sure you want to change $title from ${oldVal.toInt()} to ${newVal.toInt()}?',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onSave(newVal);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF52B788),
                foregroundColor: const Color(0xFF0F0F14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _resetToRecommendations() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          title: const Text(
            'Reset Custom Targets?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: const Text(
            'This will clear all manual targets and switch you back to System Calculated Recommendations. Your custom target history will keep a log of this change.',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final prev = {
                  'useCustomTargets': _profile.useCustomTargets,
                  'customMaintenanceCalories': _profile.customMaintenanceCalories,
                  'customTrainingDayCalories': _profile.customTrainingDayCalories,
                  'customRestDayCalories': _profile.customRestDayCalories,
                  'customProteinTarget': _profile.customProteinTarget,
                };
                final updated = _profile.copyWith(
                  useCustomTargets: false,
                  customMaintenanceCalories: null,
                  customTrainingDayCalories: null,
                  customRestDayCalories: null,
                  customProteinTarget: null,
                  targetChangeHistory: [
                    ..._profile.targetChangeHistory,
                    TargetChangeRecord(
                      timestamp: DateTime.now(),
                      sourceType: 'System Calculated',
                      maintenanceCalories: null,
                      trainingDayCalories: null,
                      restDayCalories: null,
                      proteinTarget: null,
                      previousValues: prev,
                    ),
                  ],
                );
                _saveProfile(updated);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF52B788),
                foregroundColor: const Color(0xFF0F0F14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _promptCustomThreshold() {
    final ctrl = TextEditingController(text: _profile.carryForwardThreshold.toString());
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E3E)),
          ),
          title: const Text(
            'Custom Threshold',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter carry-forward deviation threshold (kcal). Range: 50–1,000 kcal.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Threshold (kcal)',
                    labelStyle: const TextStyle(color: Color(0xFF4B5563)),
                    filled: true,
                    fillColor: const Color(0xFF0F0F14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Value required';
                    final val = int.tryParse(value);
                    if (val == null) return 'Invalid integer';
                    if (val < 50 || val > 1000) return 'Must be within 50–1,000 kcal';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final val = int.parse(ctrl.text.trim());
                  Navigator.pop(ctx);
                  _saveProfile(_profile.copyWith(carryForwardThreshold: val));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF52B788),
                foregroundColor: const Color(0xFF0F0F14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        onPressed: _handleLogout,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
          backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
            SizedBox(width: 8),
            Text(
              'Logout',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    kHapticSelect();
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Logout',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to log out? Offline data will be cleared, and you will need to sign in again.',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show a loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFEF4444)),
      ),
    );

    try {
      // Sign out using the canonical AuthService signOut sequence
      await const AuthService().signOut();
      
      // 3. Navigate back to AuthGate
      if (!mounted) return;
      // Dismiss loading dialog first
      Navigator.of(context).pop();
      
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('[ProfileScreen] Error during logout: $e');
      if (mounted) {
        // Dismiss loading dialog
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to logout cleanly: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
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
              style: KText.label,
            ),
          ),
        ],
        KCard(
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: KColor.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: KColor.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
              if (isEditable) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.edit_rounded,
                  size: 12,
                  color: KColor.green,
                ),
              ],
            ],
          ),
        ),
        if (!isLast) const Divider(color: KColor.divider, height: 1),
      ],
    );

    if (isEditable && onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          kHapticSelect();
          onTap!();
        },
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
