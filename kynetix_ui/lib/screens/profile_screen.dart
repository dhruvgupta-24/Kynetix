import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import '../screens/onboarding_screen.dart';
import '../services/health_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/persistence_service.dart';

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

  // ── AI Integration State ──
  bool _aiIsLoading = true;
  bool _aiIsConnected = false;
  String? _aiErrorMessage;

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    debugPrint('╔══════════════════════════════════════════════════');
    debugPrint('║ [ProfileScreen] initState DIAGNOSTICS');
    debugPrint('║ session null?   : ${session == null}');
    debugPrint('║ user id         : ${user?.id ?? "NULL"}');
    debugPrint('║ token prefix    : ${session?.accessToken.substring(0, session.accessToken.length.clamp(0, 20)) ?? "NULL"}');
    debugPrint('╚══════════════════════════════════════════════════');
    _checkAiStatus();
    _probeEdgeFunctionOnStartup();
    _initDeepLinks();
  }

  // ── TEMPORARY STARTUP PROBE ──────────────────────────────────────────
  // Directly invokes openai-link-status to prove any edge function works at all.
  Future<void> _probeEdgeFunctionOnStartup() async {
    debugPrint('[PROBE] ▶ Starting openai-link-status probe...');
    try {
      final res = await Supabase.instance.client.functions.invoke('openai-link-status');
      debugPrint('[PROBE] ✔ Response received');
      debugPrint('[PROBE]   data        : ${res.data}');
      debugPrint('[PROBE]   status      : ${res.status}');
    } catch (e, st) {
      debugPrint('[PROBE] ✖ EXCEPTION: ${e.runtimeType}');
      debugPrint('[PROBE]   message     : $e');
      debugPrint('[PROBE]   stack trace :');
      debugPrint(st.toString());
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _initDeepLinks() {
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'kynetix' && uri.host == 'openai-auth' && uri.path == '/callback') {
        _finishOpenAiAuth(uri);
      }
    });
  }

  Future<void> _checkAiStatus() async {
    final session = Supabase.instance.client.auth.currentSession;
    debugPrint('[_checkAiStatus] session null? ${session == null} | user: ${session?.user.id ?? "NULL"}');
    if (session == null) {
      if (!mounted) return;
      setState(() => _aiIsLoading = false);
      return;
    }

    try {
      final res = await Supabase.instance.client.functions.invoke('openai-link-status');
      debugPrint('[_checkAiStatus] ✔ data: ${res.data} | status: ${res.status}');
      if (!mounted) return;
      setState(() {
        _aiIsConnected = res.data['isConnected'] == true;
        _aiIsLoading = false;
      });
    } catch (e, st) {
      debugPrint('[_checkAiStatus] ✖ ${e.runtimeType}: $e');
      debugPrint(st.toString());
      if (!mounted) return;
      setState(() {
        _aiIsLoading = false;
      });
    }
  }

  Future<void> _connectAi() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _aiErrorMessage = 'Session expired. Please sign out and sign in again.');
      return;
    }
    setState(() { _aiIsLoading = true; _aiErrorMessage = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke('openai-link-start');
      final data = res.data;
      if (!mounted) return;
      if (data == null || data['authUrl'] == null) {
        setState(() { _aiIsLoading = false; _aiErrorMessage = 'Server returned invalid response'; });
        return;
      }
      final String authUrl = data['authUrl'].toString();
      setState(() { _aiIsLoading = false; });
      
      final uri = Uri.tryParse(authUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
         setState(() { _aiErrorMessage = 'Failed to parse auth URL.'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiIsLoading = false; _aiErrorMessage = 'Failed to start auth flow'; });
    }
  }

  Future<void> _finishOpenAiAuth(Uri uri) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || state == null) {
      if (mounted) setState(() => _aiErrorMessage = 'Invalid callback from OpenAI.');
      return;
    }

    setState(() { _aiIsLoading = true; _aiErrorMessage = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'openai-link-finish',
        body: {'code': code, 'state': state},
      );
      if (!mounted) return;
      if (res.status == 200 && res.data != null && res.data['success'] == true) {
        setState(() { _aiIsConnected = true; _aiIsLoading = false; });
      } else {
        setState(() { _aiIsLoading = false; _aiErrorMessage = 'Server validation failed'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiIsLoading = false; _aiErrorMessage = 'Failed to complete authentication'; });
    }
  }

  Future<void> _disconnectAi() async {
    setState(() { _aiIsLoading = true; });
    try {
      await Supabase.instance.client.functions.invoke('openai-link-disconnect');
      if (!mounted) return;
      setState(() { _aiIsConnected = false; _aiIsLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiIsLoading = false; _aiErrorMessage = 'Failed to disconnect'; });
    }
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
        if (mounted) setState(() { _syncing = false; _syncMessage = 'Permission denied.'; });
        return;
      }
    }

    final result = await HealthService().sync();
    if (!mounted) return;

    if (!result.hasError && result.hasData) {
      currentUserProfile = currentUserProfile!.copyWithHealth(
        averageDailySteps: result.effectiveAverageSteps!.toInt(),
        lastHealthSyncAt:  result.syncedAt,
      );
      PersistenceService.saveProfile(currentUserProfile!).ignore();
      widget.onProfileChanged?.call();
      _syncMessage = 'Synced — ${result.effectiveAverageSteps!.toInt()} steps/day effective';
    } else {
      _syncMessage = result.error ?? 'No step data found.';
    }

    setState(() => _syncing = false);
  }

  void _saveProfile(UserProfile newProfile) {
    currentUserProfile = newProfile;
    PersistenceService.saveProfile(currentUserProfile!).ignore();
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
                  child: Text('Select Goal',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(height: 10),
                ...[kFatLoss, kMaintenance, kLeanBulk, kBulk, kRecomposition].map((g) {
                  final isSel = g == _profile.goal;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(g, style: TextStyle(color: isSel ? const Color(0xFF52B788) : Colors.white, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500)),
                    trailing: isSel ? const Icon(Icons.check_circle_rounded, color: Color(0xFF52B788)) : null,
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

  void _editNumber(String title, String currentVal, String suffix, void Function(double) onSave) {
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Update $title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                   const SizedBox(height: 16),
                   TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
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
          _buildHealthCard(),
          const SizedBox(height: 16),
          _buildAiIntegrationCard(),
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
                Text(_profile.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
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
            onTap: () => _editNumber('Age', _profile.age.toString(), 'years', (v) => _saveProfile(_profile.copyWith(age: v.toInt()))),
          ),
          _InfoRow(
            icon: Icons.height_rounded,
            label: 'Height',
            value: '${_profile.height.toStringAsFixed(1)} cm',
            isEditable: true,
            onTap: () => _editNumber('Height', _profile.height.toString(), 'cm', (v) => _saveProfile(_profile.copyWith(height: v))),
          ),
          _InfoRow(
            icon: Icons.monitor_weight_outlined,
            label: 'Weight',
            value: '${_profile.weight.toStringAsFixed(1)} kg',
            isEditable: true,
            onTap: () => _editNumber('Weight', _profile.weight.toString(), 'kg', (v) => _saveProfile(_profile.copyWith(weight: v))),
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
    final synced  = _profile.healthSyncEnabled;
    final steps   = _profile.averageDailySteps;
    final syncAt  = _profile.lastHealthSyncAt;

    String syncTimeLabel = 'Never synced';
    if (syncAt != null) {
      syncTimeLabel = '${syncAt.day}/${syncAt.month} at '
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
                synced
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 16,
                color: synced
                    ? const Color(0xFF52B788)
                    : const Color(0xFF4B5563),
              ),
              const SizedBox(width: 8),
              Text(
                synced ? 'Connected' : 'Not connected',
                style: TextStyle(
                  color: synced ? const Color(0xFF52B788) : const Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _syncing ? null : _doSync,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                              color: Color(0xFF52B788)),
                        )
                      : Text(
                          synced ? 'Sync Now' : 'Connect',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF52B788)),
                        ),
                ),
              ),
            ],
          ),

          if (_syncMessage != null) ...[
            const SizedBox(height: 8),
            Text(_syncMessage!,
                style: TextStyle(
                    fontSize: 11,
                    color: _syncMessage!.contains('Synced')
                        ? const Color(0xFF52B788)
                        : const Color(0xFFFFB347))),
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

  String _stepOffsetLabel(int steps) {
    if (steps < 3000)  return '−120 kcal (Very low steps)';
    if (steps < 5000)  return '−60 kcal (Low steps)';
    if (steps < 7500)  return '0 kcal (Baseline confirmed)';
    if (steps < 10000) return '+75 kcal (Moderate steps)';
    if (steps < 12000) return '+100 kcal (High steps)';
    return '+120 kcal (Very high steps)';
  }

  ActivityTier _tierFromPersistedSteps(int steps) {
    if (steps < 4000) return ActivityTier.sedentary;
    if (steps < 7000) return ActivityTier.light;
    if (steps < 10000) return ActivityTier.moderate;
    return ActivityTier.high;
  }

  // ── AI Integration ──────────────────────────────────────────────────────────

  Widget _buildAiIntegrationCard() {
    Widget content;

    if (_aiIsLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF52B788)),
          ),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _aiIsConnected ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                size: 16,
                color: _aiIsConnected ? const Color(0xFF52B788) : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 8),
              Text(
                _aiIsConnected ? 'Connected to OpenAI' : 'Not Connected',
                style: TextStyle(
                  color: _aiIsConnected ? const Color(0xFF52B788) : const Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_aiIsConnected)
                GestureDetector(
                  onTap: _disconnectAi,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.4)),
                    ),
                    child: const Text('Disconnect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
                  ),
                )
              else
                GestureDetector(
                  onTap: _connectAi,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF52B788).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.4)),
                    ),
                    child: const Text('Connect OpenAI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF52B788))),
                  ),
                ),
            ],
          ),

          if (_aiErrorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_aiErrorMessage!, style: const TextStyle(fontSize: 12, color: Color(0xFFFF6B35))),
          ],
        ],
      );
    }

    return _Section(
      title: 'AI Integration',
      child: content,
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
  final Widget  child;
  const _Section({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title!.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.8)),
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
  final String   label;
  final String   value;
  final bool     isLast;
  final bool     isEditable;
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
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF9CA3AF))),
              const Spacer(),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
              if (isEditable) ...[
                const SizedBox(width: 4),
                const Icon(Icons.edit_rounded, size: 12, color: Color(0xFF52B788)),
              ],
            ],
          ),
        ),
        if (!isLast)
          const Divider(color: Color(0xFF2E2E3E), height: 1),
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
        kFatLoss       => const Color(0xFFFF6B35),
        kMaintenance   => const Color(0xFF52B788),
        kLeanBulk      => const Color(0xFF60A5FA),
        kBulk          => const Color(0xFF3B82F6),
        kRecomposition => const Color(0xFFA78BFA),
        _              => const Color(0xFF52B788),
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
