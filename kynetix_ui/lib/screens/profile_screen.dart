import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../ui/k_brand_intro.dart' show KShearWordmark;
import '../ui/k_segmented.dart';
import '../screens/onboarding_screen.dart';
import '../screens/connect_chatgpt_screen.dart';
import '../screens/nutrition_intelligence_screen.dart';
import '../screens/auth_gate.dart';
import '../services/chatgpt_link_service.dart';
import '../services/health_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import '../services/widget_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/insights_report_service.dart';
import 'insights_screen.dart';
import 'privacy_policy_screen.dart';
import 'account_deletion_screen.dart';
import '../ui/k_rolling.dart';
import '../ui/k_shake.dart';
import '../widgets/k_equal_height_row.dart';

enum ProviderHealth { operational, degraded, setupRequired }

// ─── Profile Screen ────────────────────────────────────────────────────────────
//
// "Carbon & Paper" settings: a pushed KPage (neutral tone) with a hero identity
// card (the screen's one signature moment), then monochrome grouped cards with
// inset hairlines. Every row has the same fixed-width trailing slot so values
// line up whether or not they're editable. Colour appears only where it means
// something (fuel, protein, status, danger). Destructive actions live in a
// separate group at the bottom. All logic is unchanged — only presentation.

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileChanged;

  const ProfileScreen({super.key, this.onProfileChanged});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Null-safe for the frame or two after sign-out or account deletion
  // clears the profile while this screen is still mounted.
  UserProfile get _profile => currentUserProfile ?? kFallbackUserProfile;
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
  bool _syncOk = false;

  // ── AI provider state ─────────────────────────────────────────────────────
  ChatGptLinkStatus? _aiStatus;
  bool _aiStatusLoading = true;
  bool _aiDisconnecting = false;

  bool _enableRpeTracking = false;

  // ── App version ─────────────────────────────────────────────────────────────
  // Read from the platform once per app run; null until it lands (or if the
  // lookup fails, in which case the row shows nothing rather than a guess).
  static Future<String?>? _versionLookup;
  String? _version;

  static Future<String?> _lookUpVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final name = info.version.trim();
      final build = info.buildNumber.trim();
      if (name.isEmpty) return null;
      return build.isEmpty ? name : '$name ($build)';
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadVersion() async {
    final v = await (_versionLookup ??= _lookUpVersion());
    if (mounted && v != _version) setState(() => _version = v);
  }

  @override
  void initState() {
    super.initState();
    _loadAiStatus();
    _loadSettings();
    _loadVersion();
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
      if (mounted) {
        setState(() {
          _aiStatus = status;
          _aiStatusLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiStatus = ChatGptLinkStatus.disconnected;
          _aiStatusLoading = false;
        });
      }
    }
  }

  Future<void> _disconnectChatGpt() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _KDialog(
        title: 'Disconnect ChatGPT?',
        icon: Icons.link_off_rounded,
        iconColor: KColor.danger,
        content: Text(
          'Kyno goes back to Kynetix servers. You can connect again any time.',
          style: _dialogBody,
        ),
        actions: [
          _DialogCancel(onPressed: () => Navigator.pop(ctx, false)),
          _DialogConfirm(
            label: 'Disconnect',
            danger: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _aiDisconnecting = true);
    try {
      await ChatGptLinkService.disconnect();
      await _loadAiStatus();
      _showToast('ChatGPT disconnected.', success: true);
    } catch (e) {
      debugPrint('[ProfileScreen] Disconnect failed: $e');
      _showToast('Couldn\'t disconnect. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _aiDisconnecting = false);
    }
  }

  Future<void> _openConnectChatGpt() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConnectChatGptScreen()),
    );
    if (mounted) _loadAiStatus();
  }

  Future<void> _openManageUsage() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(ChatGptLinkService.manageUsageUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[ProfileScreen] Could not open usage settings: $e');
    }
    if (!opened) {
      _showToast('Couldn\'t open ChatGPT settings. Try again in a moment.');
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
      _syncOk = false;
    });

    final hasPerm = await HealthService().hasPermission();
    if (!hasPerm) {
      final granted = await HealthService().requestPermission();
      if (!granted) {
        if (mounted) {
          setState(() {
            _syncing = false;
            _syncMessage =
                'Health Connect access is off. Allow it to sync your steps.';
          });
        }
        return;
      }
    }

    final result = await HealthService().sync();
    if (!mounted) return;

    final profileNow = currentUserProfile;
    if (profileNow == null) {
      // Signed out mid-sync: nothing to update.
      setState(() => _syncing = false);
      return;
    }

    if (!result.hasError && result.hasData) {
      currentUserProfile = profileNow.copyWithHealth(
        averageDailySteps: result.effectiveAverageSteps!.toInt(),
        lastHealthSyncAt: result.syncedAt,
      );
      ProfileService.instance.save(currentUserProfile!).ignore();
      widget.onProfileChanged?.call();
      _syncOk = true;
      final avg14 =
          result.averageDailySteps14d ?? result.effectiveAverageSteps!;
      _syncMessage =
          'Synced. ${avg14.round()} steps a day over your last 14 full days.';
    } else {
      _syncMessage = _friendlySyncError(result.error);
    }

    setState(() => _syncing = false);
  }

  /// Calm copy for a failed Health Connect sync. Never raw exception text.
  static String _friendlySyncError(String? raw) {
    final e = (raw ?? '').toLowerCase();
    if (e.contains('permission')) {
      return 'Health Connect access is off. Tap Connect to allow it.';
    }
    if (raw == null || e.contains('no step data')) {
      return 'No steps in Health Connect yet. Check it\'s tracking, then sync again.';
    }
    return 'Couldn\'t sync with Health Connect. Try again in a moment.';
  }

  /// The screen's toasts. Every message that is not a success here is a
  /// failure ("Couldn't ..."), so it shows as an error.
  void _showToast(String message, {bool success = false}) {
    if (!mounted) return;
    showKToast(
      context,
      message,
      kind: success ? KToastKind.success : KToastKind.error,
      duration: const Duration(seconds: 3),
    );
  }

  void _saveProfile(UserProfile newProfile) {
    currentUserProfile = newProfile;
    // Local write + cloud backup of the whole profile.
    ProfileService.instance.save(currentUserProfile!).ignore();
    widget.onProfileChanged?.call();
    setState(() {});
  }

  // ── Sheets ─────────────────────────────────────────────────────────────────

  void _editGoal() {
    showKSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: KSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KSheetHeader(
                  'Pick your goal',
                  subtitle: 'Your calorie and protein targets follow it.',
                ),
                const SizedBox(height: KSpacing.md),
                ...[
                  kFatLoss,
                  kMaintenance,
                  kLeanBulk,
                  kBulk,
                  kRecomposition,
                ].map((g) {
                  final isSel = g == _profile.goal;
                  return _SheetOption(
                    label: g,
                    selected: isSel,
                    accent: _goalColor(g),
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
    showKSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: KSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KSheetHeader(
                  'Eating style',
                  subtitle: 'How do you eat a meal with roti or rice?',
                ),
                const SizedBox(height: KSpacing.md),
                ...PortionAnchor.values.map((anchor) {
                  final isSel = anchor == _profile.portionAnchor;
                  return _SheetOption(
                    label: anchor.displayLabel,
                    selected: isSel,
                    accent: KColor.textSecondary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _saveProfile(_profile.copyWith(portionAnchor: anchor));
                    },
                  );
                }),
                // Not specified option
                _SheetOption(
                  label: 'Not specified',
                  selected: _profile.portionAnchor == null,
                  accent: KColor.textSecondary,
                  onTap: () {
                    Navigator.pop(ctx);
                    // Only the eating style changes; custom targets, their
                    // history and carry-forward settings are kept.
                    _saveProfile(_profile.copyWith(clearPortionAnchor: true));
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
    final heightCtrl = TextEditingController(
      text: _profile.height.toStringAsFixed(1),
    );
    final weightCtrl = TextEditingController(
      text: _profile.weight.toStringAsFixed(1),
    );
    final formKey = GlobalKey<FormState>();

    showKSheet<void>(
      context: context,
      isScrollControlled: true,
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
                padding: const EdgeInsets.fromLTRB(4, 0, 4, KSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const KSheetHeader(
                      'Body metrics',
                      subtitle: 'Keeps your daily targets honest.',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KSpacing.p - 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: KSpacing.lg),
                          _buildFormInput(
                            controller: ageCtrl,
                            label: 'Age',
                            suffix: 'years',
                            keyboardType: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Add your age';
                              }
                              final numVal = int.tryParse(val);
                              if (numVal == null ||
                                  numVal < 1 ||
                                  numVal > 120) {
                                return 'Age should be between 1 and 120';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: KSpacing.lg),
                          _buildFormInput(
                            controller: heightCtrl,
                            label: 'Height',
                            suffix: 'cm',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            formatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]'),
                              ),
                            ],
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Add your height';
                              }
                              final numVal = double.tryParse(val);
                              if (numVal == null ||
                                  numVal < 50 ||
                                  numVal > 280) {
                                return 'Height should be 50-280 cm';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: KSpacing.lg),
                          _buildFormInput(
                            controller: weightCtrl,
                            label: 'Weight',
                            suffix: 'kg',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            formatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]'),
                              ),
                            ],
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Add your weight';
                              }
                              final numVal = double.tryParse(val);
                              if (numVal == null ||
                                  numVal < 20 ||
                                  numVal > 400) {
                                return 'Weight should be 20-400 kg';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: KSpacing.xxl),
                          KButton(
                            label: 'Save metrics',
                            width: double.infinity,
                            onTap: () {
                              if (formKey.currentState?.validate() ?? false) {
                                final age =
                                    int.tryParse(ageCtrl.text) ?? _profile.age;
                                final height =
                                    double.tryParse(heightCtrl.text) ??
                                    _profile.height;
                                final weight =
                                    double.tryParse(weightCtrl.text) ??
                                    _profile.weight;

                                _saveProfile(
                                  _profile.copyWith(
                                    age: age,
                                    height: height,
                                    weight: weight,
                                  ),
                                );
                                Navigator.pop(ctx);
                                _showToast('Metrics saved.', success: true);
                              } else {
                                KHaptics.reject();
                                KShake.shakeInvalid(formKey.currentContext);
                              }
                            },
                          ),
                        ],
                      ),
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
        Text(label, style: KText.label),
        const SizedBox(height: KSpacing.sm),
        // Shaken by KShake.shakeInvalid when Save rejects the value.
        KShake(
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            validator: validator,
            style: KText.numSmall.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: _inputDecoration(suffix: suffix),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      _buildProfileCard(),
      _buildAppearanceCard(),
      _buildBodyCard(),
      _buildGoalCard(),
      _buildNutritionTargetsCard(),
      _buildLiftingMetricsCard(),
      _buildHealthCard(),
      _buildAiCard(),
      _buildLibraryAndInsightsCard(),
      _buildAboutCard(),
      _buildPrivacyCard(),
      _buildAccountCard(),
    ];

    return KPage(
      tone: KTone.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings', style: KText.h2),
      ),
      // Built eagerly (not lazily) so the one-shot entrance plays once on
      // mount and never replays while scrolling.
      // Rows carry their own 16dp inset, so the page itself runs nearly
      // edge to edge: sections read as one editorial list, not a card stack.
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          KSpacing.xs,
          KSpacing.xs,
          KSpacing.xs,
          MediaQuery.paddingOf(context).bottom + KSpacing.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  top: i == 0
                      ? 0
                      : (i == sections.length - 1
                            ? KSpacing.xxxl + KSpacing.sm
                            : KSpacing.xxxl),
                ),
                child: KReveal(index: i, child: sections[i]),
              ),
            // The sign-off: the mark, quiet, and the line under it.
            Padding(
              padding: const EdgeInsets.only(top: KSpacing.xxxl + KSpacing.lg),
              child: Column(
                children: [
                  KShearWordmark(fontSize: 30, ink: KColor.textMuted, ember: KColor.ember),
                  const SizedBox(height: KSpacing.sm),
                  Text('Real food. Real lifts.', style: KText.caption.copyWith(color: KColor.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Profile Banner (hero identity card) ────────────────────────────────────

  Widget _buildProfileCard() {
    final plan = _plan;

    // The person, set like a masthead: a plain avatar, the name large, the
    // goal as a coloured word, then their numbers in a ruled row. No card,
    // no gradient ring.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KSpacing.sm),
          Row(
            children: [
              Builder(
                builder: (context) {
                  final user = Supabase.instance.client.auth.currentUser;
                  final avatarUrl =
                      user?.userMetadata?['avatar_url'] ??
                      user?.userMetadata?['picture'] as String?;

                  String getInitials(String name) {
                    if (name.isEmpty) return 'K';
                    final parts = name.trim().split(RegExp(r'\s+'));
                    if (parts.length == 1) {
                      return parts.first
                          .substring(0, parts.first.length >= 2 ? 2 : 1)
                          .toUpperCase();
                    }
                    return (parts.first[0] + parts.last[0]).toUpperCase();
                  }

                  final initials = getInitials(_profile.name);
                  final initialsWidget = Center(
                    child: Text(
                      initials,
                      style: KText.h3.copyWith(
                        color: KColor.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  );

                  return ExcludeSemantics(
                    child: Container(
                      width: 56,
                      height: 56,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KColor.cardHigh,
                        border: Border.all(
                          color: KColor.fg.withValues(
                            alpha: KColor.isDark ? 0.12 : 0.1,
                          ),
                        ),
                      ),
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              // Decode at display size, not the full
                              // upload resolution.
                              cacheWidth:
                                  (56 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                              errorBuilder: (context, error, stackTrace) {
                                return initialsWidget;
                              },
                            )
                          : initialsWidget,
                    ),
                  );
                },
              ),
              const SizedBox(width: KSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profile.name,
                      style: KText.h1.copyWith(fontSize: 26, height: 1.1),
                    ),
                    const SizedBox(height: 6),
                    _GoalChip(goal: _profile.goal),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.xl),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: KColor.textPrimary, width: 1.5),
                bottom: BorderSide(
                  color: KColor.fg.withValues(alpha: KColor.isDark ? 0.1 : 0.1),
                ),
              ),
            ),
            // Equal columns with painted hairline rules: the same look as
            // a stretched row, without an intrinsic-height pass.
            child: KEqualHeightRow(
              gap: 1,
              ruleColor: KColor.fg.withValues(alpha: 0.1),
              ruleInset: KSpacing.md,
              children: [
                _StatTile(
                  icon: Icons.height_rounded,
                  label: 'Height',
                  value: _profile.height,
                  decimals: 1,
                  unit: 'cm',
                  tint: KColor.textSecondary,
                  onTap: _editBodyMetrics,
                ),
                _StatTile(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Weight',
                  value: _profile.weight,
                  decimals: 1,
                  unit: 'kg',
                  tint: KColor.textSecondary,
                  onTap: _editBodyMetrics,
                ),
                _StatTile(
                  icon: Icons.local_fire_department_rounded,
                  // A weekly average; training/rest days differ, so say so.
                  label: 'kcal a day',
                  value: plan.avgDailyCalories,
                  unit: 'kcal',
                  tint: KColor.ember,
                ),
                _StatTile(
                  icon: Icons.egg_outlined,
                  label: 'Protein a day',
                  value: plan.avgDailyProtein,
                  unit: 'g',
                  tint: KColor.protein,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Appearance ─────────────────────────────────────────────────────────────
  // System / Light / Dark. A UI preference only (persisted by the controller);
  // KThemeScope repaints the whole tree, so the switch is live.

  Widget _buildAppearanceCard() {
    return _Group(
      title: 'Appearance',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.lg,
            KSpacing.md,
            KSpacing.lg,
            KSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: KThemeController.instance,
                builder: (context, mode, _) =>
                    _ThemeModeSegmented(selected: mode),
              ),
            ],
          ),
        ),
        if (defaultTargetPlatform == TargetPlatform.android)
          _SettingRow(
            icon: Icons.widgets_outlined,
            tint: KColor.textSecondary,
            label: 'Home screen widget',
            subtitle: 'Calories and protein left, without opening the app',
            onTap: () => showKSheet<void>(context: context, builder: (_) => const _WidgetPickerSheet()),
          ),
      ],
    );
  }

  // ── Privacy & legal ────────────────────────────────────────────────────────

  Widget _buildPrivacyCard() {
    return _Group(
      title: 'Privacy & legal',
      children: [
        _SettingRow(
          icon: Icons.privacy_tip_outlined,
          tint: KColor.textSecondary,
          label: 'Privacy policy',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
          ),
        ),
        _SettingRow(
          icon: Icons.description_outlined,
          tint: KColor.textSecondary,
          label: 'Open-source licences',
          onTap: () =>
              showLicensePage(context: context, applicationName: 'Kynetix'),
        ),
      ],
    );
  }

  // ── Body Metrics ───────────────────────────────────────────────────────────

  Widget _buildBodyCard() {
    return _Group(
      title: 'Body metrics',
      children: [
        _SettingRow(
          icon: Icons.person_outline_rounded,
          tint: KColor.textSecondary,
          label: 'Gender',
          value: _profile.gender.isEmpty
              ? _profile.gender
              : _profile.gender[0].toUpperCase() + _profile.gender.substring(1),
        ),
        _SettingRow(
          icon: Icons.cake_outlined,
          tint: KColor.textSecondary,
          label: 'Age',
          value: '${_profile.age} years',
          isEditable: true,
          onTap: _editBodyMetrics,
        ),
        _SettingRow(
          icon: Icons.height_rounded,
          tint: KColor.textSecondary,
          label: 'Height',
          value: '${amount(_profile.height)} cm',
          isEditable: true,
          onTap: _editBodyMetrics,
        ),
        _SettingRow(
          icon: Icons.monitor_weight_outlined,
          tint: KColor.textSecondary,
          label: 'Weight',
          value: '${amount(_profile.weight)} kg',
          isEditable: true,
          onTap: _editBodyMetrics,
        ),
        _SettingRow(
          icon: Icons.calculate_outlined,
          tint: KColor.textSecondary,
          label: 'BMI',
          value: _profile.bmi.toStringAsFixed(1),
        ),
      ],
    );
  }

  // ── Goal & Activity ────────────────────────────────────────────────────────

  Widget _buildGoalCard() {
    final freqLabel = _profile.workoutDaysMin == _profile.workoutDaysMax
        ? '${_profile.workoutDaysMin}×/week'
        : '${_profile.workoutDaysMin}-${_profile.workoutDaysMax}×/week';
    final plan = _plan;

    return _Group(
      title: 'Goal settings',
      children: [
        _SettingRow(
          icon: Icons.flag_rounded,
          tint: _goalColor(_profile.goal),
          label: 'Goal',
          value: _profile.goal,
          isEditable: true,
          onTap: _editGoal,
        ),
        _SettingRow(
          icon: Icons.restaurant_outlined,
          tint: KColor.textSecondary,
          label: 'Eating style',
          value: _profile.portionAnchor?.displayLabel ?? 'Not specified',
          isEditable: true,
          onTap: _editEatingStyle,
        ),
        _SettingRow(
          icon: Icons.fitness_center_rounded,
          tint: KColor.textSecondary,
          label: 'Workouts',
          value: freqLabel,
        ),
        _SettingRow(
          icon: Icons.local_fire_department_rounded,
          tint: KColor.ember,
          label: 'Maintenance',
          value: '${plan.maintenanceCalories.toStringAsFixed(0)} kcal',
        ),
        _SettingRow(
          icon: Icons.bolt_rounded,
          tint: KColor.ember,
          label: 'Base target',
          value: '${plan.avgDailyCalories.toStringAsFixed(0)} kcal',
        ),
        _SettingRow(
          icon: Icons.egg_outlined,
          tint: KColor.protein,
          label: 'Base protein',
          value: '${plan.avgDailyProtein.toStringAsFixed(0)} g',
        ),
      ],
    );
  }

  Widget _buildLiftingMetricsCard() {
    return _Group(
      title: 'Advanced lifting metrics',
      children: [
        _SwitchRow(
          icon: Icons.speed_rounded,
          tint: KColor.textSecondary,
          title: 'RPE tracking',
          subtitle: 'Rate of perceived exertion (1-10) for each set',
          value: _enableRpeTracking,
          onChanged: (val) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('enable_rpe_tracking', val);
            if (!mounted) return;
            setState(() {
              _enableRpeTracking = val;
            });
          },
        ),
      ],
    );
  }

  // ── Health Connect ─────────────────────────────────────────────────────────

  Widget _buildHealthCard() {
    final synced = _profile.healthSyncEnabled;
    final steps = _profile.averageDailySteps;
    final syncAt = _profile.lastHealthSyncAt;

    String syncTimeLabel = 'Not yet';
    if (syncAt != null) {
      syncTimeLabel =
          '${syncAt.day}/${syncAt.month} at '
          '${syncAt.hour.toString().padLeft(2, '0')}:${syncAt.minute.toString().padLeft(2, '0')}';
    }

    final stepOffset = _profile.healthSyncEnabled && steps != null
        ? _stepOffsetLabel(steps)
        : null;

    final syncOk = _syncOk;

    return _Group(
      title: 'Health Connect',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.lg,
            KSpacing.md,
            KSpacing.md,
            KSpacing.md,
          ),
          child: Row(
            children: [
              _IconTile(
                icon: synced
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                tint: synced ? KColor.green : KColor.textMuted,
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      synced ? 'Connected' : 'Not connected',
                      style: KText.bodyMedium.copyWith(
                        color: synced ? KColor.green : KColor.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AnimatedSize(
                      duration: KMotion.of(context, KMotion.standard),
                      curve: KMotion.emphasizedCurve,
                      alignment: AlignmentDirectional.topStart,
                      child: _syncMessage == null
                          ? const SizedBox(width: double.infinity)
                          : Semantics(
                              liveRegion: true,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Icon(
                                        syncOk
                                            ? Icons.check_circle_rounded
                                            : Icons.info_outline_rounded,
                                        size: 13,
                                        color: syncOk
                                            ? KColor.green
                                            : KColor.ember,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _syncMessage!,
                                        style: KText.caption.copyWith(
                                          fontSize: 11,
                                          color: syncOk
                                              ? KColor.green
                                              : KColor.ember,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              _PillAction(
                label: synced ? 'Sync now' : 'Connect',
                busy: _syncing,
                onTap: _syncing ? null : _doSync,
              ),
            ],
          ),
        ),

        if (synced) ...[
          _SettingRow(
            icon: Icons.directions_walk_rounded,
            tint: KColor.textSecondary,
            label: 'Avg steps',
            value: steps != null ? '${steps.toStringAsFixed(0)}/day' : '-',
          ),
          _SettingRow(
            icon: Icons.tune_rounded,
            tint: KColor.ember,
            label: 'Calorie correction',
            value: stepOffset ?? '-',
          ),
          _SettingRow(
            icon: Icons.schedule_rounded,
            tint: KColor.textSecondary,
            label: 'Last sync',
            value: syncTimeLabel,
          ),
        ],
      ],
    );
  }

  /// Shows the actual weight-aware calorie offset for the persisted step count.
  /// Uses the same formula as NutritionTargetEngine._stepCorrectionKcal.
  /// The engine's own step adjustment for the persisted step count.
  String _stepOffsetLabel(int steps) {
    final rawOffset = NutritionTargetEngine.instance.stepCorrectionKcal(
      _profile.copyWith(averageDailySteps: steps),
      null,
    );
    final sign = rawOffset >= 0 ? '+' : '';
    return '$sign$rawOffset kcal vs baseline';
  }

  ActivityTier _tierFromPersistedSteps(int steps) {
    if (steps < 4000) return ActivityTier.sedentary;
    if (steps < 7000) return ActivityTier.light;
    if (steps < 10000) return ActivityTier.moderate;
    if (steps < 13000) return ActivityTier.active;
    return ActivityTier.veryActive;
  }

  // ── AI Engine Info ───────────────────────────────────────────────────────────

  Widget _buildAiCard() {
    return _Group(
      title: 'ChatGPT',
      children: [
        AnimatedSwitcher(
          duration: KMotion.of(context, KMotion.standard),
          switchInCurve: KMotion.decelerate,
          switchOutCurve: KMotion.accelerate,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: _aiStatusLoading
              ? const _AiStatusSkeleton(key: ValueKey('ai-loading'))
              : KeyedSubtree(
                  key: const ValueKey('ai-body'),
                  child: _buildAiStatusBody(),
                ),
        ),
      ],
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
    final viaPlan = isConnected && s.usesChatGptPlan;
    final paused =
        viaPlan && (s.planPausedUntil?.isAfter(DateTime.now()) ?? false);

    // Same states and words as ConnectChatGptScreen. Colour carries meaning
    // only (success / attention) and always pairs with an icon and a label.
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;
    final String body;
    if (!isConnected) {
      statusColor = KColor.textMuted;
      statusLabel = 'Not connected';
      statusIcon = Icons.link_off_rounded;
      body =
          'Kyno runs on Kynetix servers. Connect ChatGPT to run it on your plan instead.';
    } else if (s.tokenExpired) {
      statusColor = KColor.warning;
      statusLabel = 'Sign-in expired';
      statusIcon = Icons.lock_clock_rounded;
      body =
          'Your ChatGPT sign-in expired, so Kyno\'s using the standard model until you reconnect.';
    } else if (paused) {
      statusColor = KColor.warning;
      statusLabel = 'Limit reached';
      statusIcon = Icons.hourglass_bottom_rounded;
      body = s.fallbackReason == 'plan_unavailable'
          ? 'ChatGPT\'s busy right now, so Kyno\'s using the standard model for now.'
          : 'Your ChatGPT limit\'s tapped out, so Kyno\'s using the standard model for now.';
    } else if (viaPlan && s.fallbackReason == 'not_eligible') {
      statusColor = KColor.warning;
      statusLabel = 'Plan not available';
      statusIcon = Icons.block_rounded;
      body =
          'Your ChatGPT plan can\'t be used here, so Kyno\'s using the standard model.';
    } else if (_providerHealth == ProviderHealth.degraded &&
        s.fallbackReason != 'usage_limit' &&
        s.fallbackReason != 'plan_unavailable') {
      statusColor = KColor.warning;
      statusLabel = 'Using backup';
      statusIcon = Icons.warning_amber_rounded;
      body =
          'Couldn\'t reach ChatGPT last time, so Kyno used the standard model. It tries your account again next time.';
    } else if (viaPlan) {
      statusColor = KColor.green;
      statusLabel = 'Using ChatGPT plan';
      statusIcon = Icons.check_circle_rounded;
      body =
          'Kyno\'s AI requests run on your ChatGPT plan and count toward its usage.';
    } else {
      statusColor = KColor.green;
      statusLabel = 'Connected';
      statusIcon = Icons.check_circle_rounded;
      body = 'Kyno runs on your ChatGPT account.';
    }

    final String actionLabel;
    final Color? actionColor;
    final VoidCallback onAction;
    if (!isConnected) {
      actionLabel = 'Connect ChatGPT';
      actionColor = null;
      onAction = _openConnectChatGpt;
    } else if (s.tokenExpired) {
      actionLabel = 'Reconnect';
      actionColor = null;
      onAction = _openConnectChatGpt;
    } else {
      actionLabel = 'Disconnect';
      actionColor = KColor.danger;
      onAction = _disconnectChatGpt;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Status and action row ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.lg,
            KSpacing.md,
            KSpacing.md,
            0,
          ),
          child: Row(
            children: [
              _IconTile(icon: statusIcon, tint: statusColor),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    statusLabel,
                    style: KText.bodyMedium.copyWith(
                      color: statusColor == KColor.textMuted
                          ? KColor.textSecondary
                          : statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              _PillAction(
                label: actionLabel,
                color: actionColor,
                busy: _aiDisconnecting,
                onTap: _aiDisconnecting ? null : onAction,
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.lg,
            KSpacing.md,
            KSpacing.lg,
            0,
          ),
          child: Text(
            body,
            style: KText.caption.copyWith(
              color: KColor.textSecondary,
              height: 1.5,
            ),
          ),
        ),

        if (viaPlan)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.sm,
              KSpacing.xs,
              KSpacing.lg,
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  KHaptics.select();
                  _openManageUsage();
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.sm),
                  foregroundColor: KColor.textPrimary,
                ),
                icon: Icon(
                  Icons.north_east_rounded,
                  size: 16,
                  color: KColor.textPrimary,
                ),
                label: Text(
                  'Manage usage',
                  style: KText.bodyMedium.copyWith(
                    color: KColor.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),

        // Expandable drawer for Advanced Diagnostics (Connection Details)
        Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
            childrenPadding: const EdgeInsets.only(bottom: KSpacing.sm),
            expansionAnimationStyle: AnimationStyle(
              duration: KMotion.of(context, KMotion.standard),
              curve: KMotion.emphasizedCurve,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: KColor.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Connection details',
                    style: KText.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: KColor.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            iconColor: KColor.textSecondary,
            collapsedIconColor: KColor.textMuted,
            children: [
              _DetailRow(
                icon: Icons.cloud_queue_rounded,
                label: 'Running on',
                value: _providerDisplayName(s.activeProvider),
              ),
              _DetailRow(
                icon: Icons.key_rounded,
                label: 'Sign-in',
                value: !isConnected
                    ? '-'
                    : (viaPlan
                          ? 'ChatGPT plan'
                          : (s.authMethod == 'codex_device'
                                ? 'Code'
                                : 'ChatGPT account')),
              ),
              if (paused)
                _DetailRow(
                  icon: Icons.hourglass_bottom_rounded,
                  label: 'Plan resumes',
                  value: _relativeFuture(s.planPausedUntil),
                ),
              _DetailRow(
                icon: Icons.psychology_rounded,
                label: 'Model',
                value:
                    s.selectedModel ??
                    s.activeModel ??
                    (isConnected ? 'Checking…' : '-'),
              ),
              _DetailRow(
                icon: Icons.access_time_rounded,
                label: 'Last used',
                value: _relativeTime(s.lastUsedAt),
              ),
              _DetailRow(
                icon: Icons.sync_rounded,
                label: 'Status',
                value: statusLabel,
              ),
              _DetailRow(
                icon: Icons.check_circle_outline_rounded,
                label: 'Last good reply',
                value: s.lastSuccessfulRequestAt != null
                    ? _relativeTime(s.lastSuccessfulRequestAt)
                    : '-',
              ),
              _DetailRow(
                icon: Icons.error_outline_rounded,
                label: 'Last failed reply',
                value: s.lastFailedRequestAt != null
                    ? _relativeTime(s.lastFailedRequestAt)
                    : '-',
              ),
              _DetailRow(
                icon: Icons.network_check_rounded,
                label: 'Last answered by',
                value: _providerDisplayName(s.lastSuccessfulProvider),
              ),
              _DetailRow(
                icon: Icons.speed_rounded,
                label: 'Average reply time',
                value: s.averageLatencyMs != null
                    ? '${s.averageLatencyMs!.toStringAsFixed(0)} ms'
                    : '-',
              ),
              if (isConnected) ...[
                _DetailRow(
                  icon: Icons.refresh_rounded,
                  label: 'Sign-in refreshed',
                  value: _relativeTime(s.lastRefreshedAt),
                ),
                _DetailRow(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Last test reply',
                  value: s.testGenerationSnippet != null
                      ? '"${s.testGenerationSnippet}"'
                      : '-',
                ),
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  label: 'Connected',
                  value: _relativeTime(s.connectedAt),
                ),
              ],
              if (s.fallbackReason != null) ...[
                _DetailRow(
                  icon: Icons.warning_amber_rounded,
                  label: 'Why the backup',
                  value: _fallbackReasonDisplayName(s.fallbackReason),
                ),
              ],
              _DetailRow(
                icon: Icons.verified_rounded,
                label: 'Model checked',
                value: s.modelDiscoveryVerified
                    ? 'Yes'
                    : (isConnected ? 'Pending' : '-'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _providerDisplayName(String? raw) {
    if (raw == null) return '-';
    return switch (raw) {
      'user_chatgpt' => 'Your ChatGPT',
      'openrouter' || 'gemini' || 'groq' => 'Kynetix servers',
      'openai' => 'Your ChatGPT',
      _ => raw,
    };
  }

  String _fallbackReasonDisplayName(String? reason) {
    if (reason == null) return '-';
    return switch (reason) {
      'account_disconnected' => 'Account disconnected',
      'token_expired' => 'Sign-in expired',
      'refresh_failed' => 'Sign-in refresh failed',
      'model_unavailable' => 'Model unavailable',
      'usage_limit' => 'ChatGPT limit reached',
      'not_eligible' => 'Plan not available here',
      'plan_unavailable' => 'ChatGPT busy',
      'api_error' => 'Couldn\'t reach ChatGPT',
      _ => reason,
    };
  }

  String _relativeFuture(DateTime? dt) {
    if (dt == null) return '-';
    final diff = dt.difference(DateTime.now());
    if (diff.inMinutes < 1) return 'Any moment';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'In ${diff.inHours}h';
    return 'In ${diff.inDays}d';
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Food Library + Insights & Progress ─────────────────────────────────────

  Widget _buildLibraryAndInsightsCard() {
    return _Group(
      title: 'Food library & insights',
      children: [
        _SettingRow(
          icon: Icons.psychology_rounded,
          tint: KColor.textSecondary,
          label: 'Food library',
          value: 'Portion history & custom foods',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NutritionIntelligenceScreen(),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: InsightsReportService.instance,
          builder: (context, _) {
            final newCount = InsightsReportService.instance.newAchievementCount;
            return _SettingRow(
              icon: Icons.insights_rounded,
              tint: KColor.textSecondary,
              label: 'Insights & reports',
              value: newCount > 0 ? '$newCount new' : 'History and badges',
              valueColor: newCount > 0 ? KColor.green : null,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const InsightsScreen())),
            );
          },
        ),
      ],
    );
  }

  // ── About ──────────────────────────────────────────────────────────────────

  Widget _buildAboutCard() {
    return _Group(
      title: 'About Kynetix',
      children: [
        _SettingRow(
          icon: Icons.info_outline_rounded,
          tint: KColor.textSecondary,
          label: 'Version',
          value: _version,
        ),
        _SettingRow(
          icon: Icons.restaurant_menu_rounded,
          tint: KColor.textSecondary,
          label: 'Baseline formula',
          value: 'Kynetix Indian Caloric Baseline',
        ),
      ],
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

    return _Group(
      title: 'Nutrition targets',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.lg,
            KSpacing.lg,
            KSpacing.lg,
            KSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily target source', style: KText.label),
              const SizedBox(height: KSpacing.sm),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: KColor.fg.withValues(
                    alpha: KColor.isDark ? 0.04 : 0.035,
                  ),
                  borderRadius: KRadius.md,
                  border: Border.all(
                    color: KColor.fg.withValues(
                      alpha: KColor.isDark ? 0.07 : 0.08,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _buildSourceChip(
                      label: 'Calculated',
                      selected: !profile.useCustomTargets,
                      onTap: () {
                        if (profile.useCustomTargets) {
                          _changeTargetSource(useCustom: false);
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildSourceChip(
                      label: 'Custom',
                      selected: profile.useCustomTargets,
                      onTap: () {
                        if (!profile.useCustomTargets) {
                          _changeTargetSource(useCustom: true);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (!profile.useCustomTargets) ...[
          _SettingRow(
            icon: Icons.local_fire_department_rounded,
            tint: KColor.ember,
            label: 'Maintenance calories',
            value: '${activePlan.maintenanceCalories.toStringAsFixed(0)} kcal',
          ),
          _SettingRow(
            icon: Icons.bolt_rounded,
            tint: KColor.ember,
            label: 'Training day calories',
            value: '${activePlan.trainingDayCalories.toStringAsFixed(0)} kcal',
          ),
          _SettingRow(
            icon: Icons.nightlight_round,
            tint: KColor.textSecondary,
            label: 'Rest day calories',
            value: '${activePlan.restDayCalories.toStringAsFixed(0)} kcal',
          ),
          _SettingRow(
            icon: Icons.egg_outlined,
            tint: KColor.protein,
            label: 'Daily protein target',
            value: '${activePlan.avgDailyProtein.toStringAsFixed(0)} g',
          ),
        ] else ...[
          _SettingRow(
            icon: Icons.local_fire_department_rounded,
            tint: KColor.ember,
            label: 'Maintenance calories',
            value:
                '${(profile.customMaintenanceCalories ?? enginePlan.maintenanceCalories).toStringAsFixed(0)} kcal',
            isEditable: true,
            onTap: () => _editCustomTargetValue(
              title: 'maintenance calories',
              minValue: 800,
              maxValue: 6000,
              currentValue:
                  profile.customMaintenanceCalories ??
                  enginePlan.maintenanceCalories,
              onSave: (val) {
                final updated = profile.copyWith(
                  customMaintenanceCalories: val,
                );
                _saveProfile(updated);
              },
            ),
          ),
          _SettingRow(
            icon: Icons.bolt_rounded,
            tint: KColor.ember,
            label: 'Training day calories',
            value:
                '${(profile.customTrainingDayCalories ?? enginePlan.trainingDayCalories).toStringAsFixed(0)} kcal',
            isEditable: true,
            onTap: () => _editCustomTargetValue(
              title: 'training day calories',
              minValue: 800,
              maxValue: 6000,
              currentValue:
                  profile.customTrainingDayCalories ??
                  enginePlan.trainingDayCalories,
              onSave: (val) {
                final updated = profile.copyWith(
                  customTrainingDayCalories: val,
                );
                _saveProfile(updated);
              },
            ),
          ),
          _SettingRow(
            icon: Icons.nightlight_round,
            tint: KColor.textSecondary,
            label: 'Rest day calories',
            value:
                '${(profile.customRestDayCalories ?? enginePlan.restDayCalories).toStringAsFixed(0)} kcal',
            isEditable: true,
            onTap: () => _editCustomTargetValue(
              title: 'rest day calories',
              minValue: 800,
              maxValue: 6000,
              currentValue:
                  profile.customRestDayCalories ?? enginePlan.restDayCalories,
              onSave: (val) {
                final updated = profile.copyWith(customRestDayCalories: val);
                _saveProfile(updated);
              },
            ),
          ),
          _SettingRow(
            icon: Icons.egg_outlined,
            tint: KColor.protein,
            label: 'Daily protein target',
            value:
                '${(profile.customProteinTarget ?? enginePlan.avgDailyProtein).toStringAsFixed(0)} g',
            isEditable: true,
            onTap: () => _editCustomTargetValue(
              title: 'daily protein target',
              minValue: 30,
              maxValue: 350,
              currentValue:
                  profile.customProteinTarget ?? enginePlan.avgDailyProtein,
              onSave: (val) {
                final updated = profile.copyWith(customProteinTarget: val);
                _saveProfile(updated);
              },
            ),
          ),
          _SettingRow(
            icon: Icons.refresh_rounded,
            tint: KColor.danger,
            label: 'Reset to recommendations',
            danger: true,
            onTap: _resetToRecommendations,
          ),
        ],

        _SwitchRow(
          icon: Icons.cached_rounded,
          tint: KColor.textSecondary,
          title: 'Calorie carry-forward',
          subtitle: 'Nudges tomorrow\'s target when today runs over or under',
          value: profile.carryForwardEnabled,
          onChanged: (val) {
            _saveProfile(profile.copyWith(carryForwardEnabled: val));
          },
        ),

        if (profile.carryForwardEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.lg,
              KSpacing.md,
              KSpacing.lg,
              KSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Carry-forward threshold', style: KText.label),
                const SizedBox(height: KSpacing.sm),
                Wrap(
                  spacing: KSpacing.sm,
                  runSpacing: KSpacing.sm,
                  children: [
                    _buildThresholdChip(100),
                    _buildThresholdChip(150),
                    _buildThresholdChip(200),
                    _buildThresholdChip(250),
                    _buildCustomThresholdChip(),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSourceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final d = KMotion.of(context, KMotion.standard);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: () {
            KHaptics.select();
            onTap();
          },
          scale: 0.97,
          borderRadius: KRadius.sm,
          child: AnimatedContainer(
            duration: d,
            curve: KMotion.emphasizedCurve,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              vertical: KSpacing.sm,
              horizontal: KSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? KColor.ink : Colors.transparent,
              borderRadius: KRadius.sm,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: d,
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: selected
                      ? Padding(
                          key: ValueKey('on'),
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: KColor.onInk,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('off')),
                ),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: KText.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? KColor.onInk : KColor.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdChip(int kcal) {
    final selected = _profile.carryForwardThreshold == kcal;
    return _ChoicePill(
      label: '$kcal kcal',
      selected: selected,
      onTap: () {
        _saveProfile(_profile.copyWith(carryForwardThreshold: kcal));
      },
    );
  }

  Widget _buildCustomThresholdChip() {
    final currentThreshold = _profile.carryForwardThreshold;
    final isPreset = const [100, 150, 200, 250].contains(currentThreshold);
    final selected = !isPreset;

    final label = selected ? 'Custom ($currentThreshold kcal)' : 'Custom…';

    return _ChoicePill(
      label: label,
      selected: selected,
      trailingIcon: selected ? Icons.edit_rounded : null,
      onTap: _promptCustomThreshold,
    );
  }

  void _changeTargetSource({required bool useCustom}) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _KDialog(
          title: useCustom
              ? 'Switch to custom targets?'
              : 'Switch to calculated targets?',
          content: Text(
            useCustom
                ? 'You set your own calorie and protein numbers. Kynetix stops working them out from your profile.'
                : 'Kynetix works out your targets from your weight, height, age, steps and goal.',
            style: _dialogBody,
          ),
          actions: [
            _DialogCancel(onPressed: () => Navigator.pop(ctx)),
            _DialogConfirm(
              label: useCustom ? 'Use custom' : 'Use calculated',
              onPressed: () {
                Navigator.pop(ctx);
                final updated = _profile.copyWith(useCustomTargets: useCustom);
                _saveProfile(updated);
                _showToast(
                  useCustom
                      ? 'Using custom targets.'
                      : 'Using calculated targets.',
                  success: true,
                );
              },
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
        return _KDialog(
          title: 'Edit $title',
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick a number from ${minValue.round()} to ${maxValue.round()}.',
                  style: KText.caption.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: KSpacing.lg),
                KShake(child: TextFormField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  style: KText.numSmall.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: _inputDecoration(
                    label: title.contains('protein')
                        ? 'Protein (g)'
                        : 'Calories (kcal)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Add a number';
                    }
                    final numVal = double.tryParse(value);
                    if (numVal == null) {
                      return 'That doesn\'t look like a number';
                    }
                    if (numVal < minValue || numVal > maxValue) {
                      return 'Keep it between ${minValue.round()} and ${maxValue.round()}';
                    }
                    return null;
                  },
                )),
              ],
            ),
          ),
          actions: [
            _DialogCancel(onPressed: () => Navigator.pop(ctx)),
            _DialogConfirm(
              label: 'Save',
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final val = double.tryParse(ctrl.text.trim()) ?? currentValue;
                  Navigator.pop(ctx);
                  _confirmValueChange(title, currentValue, val, onSave);
                } else {
                  KHaptics.reject();
                  KShake.shakeInvalid(formKey.currentContext);
                }
              },
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
        return _KDialog(
          title: 'Change $title?',
          content: Text(
            'Going from ${oldVal.round()} to ${newVal.round()}.',
            style: _dialogBody.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          actions: [
            _DialogCancel(onPressed: () => Navigator.pop(ctx)),
            _DialogConfirm(
              label: 'Save',
              onPressed: () {
                Navigator.pop(ctx);
                onSave(newVal);
                _showToast('Target saved.', success: true);
              },
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
        return _KDialog(
          title: 'Reset custom targets?',
          icon: Icons.refresh_rounded,
          iconColor: KColor.danger,
          content: Text(
            'This clears your custom numbers and goes back to calculated targets. Your target history keeps a note of the change.',
            style: _dialogBody,
          ),
          actions: [
            _DialogCancel(onPressed: () => Navigator.pop(ctx)),
            _DialogConfirm(
              label: 'Reset',
              danger: true,
              onPressed: () {
                Navigator.pop(ctx);
                final updated = _profile.copyWith(
                  useCustomTargets: false,
                  customMaintenanceCalories: null,
                  customTrainingDayCalories: null,
                  customRestDayCalories: null,
                  customProteinTarget: null,
                );
                _saveProfile(updated);
                _showToast('Targets reset.', success: true);
              },
            ),
          ],
        );
      },
    );
  }

  void _promptCustomThreshold() {
    final ctrl = TextEditingController(
      text: _profile.carryForwardThreshold.toString(),
    );
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _KDialog(
          title: 'Custom threshold',
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How far off target (in kcal) a day can run before tomorrow adjusts. Pick 50-1,000.',
                  style: KText.caption.copyWith(height: 1.4),
                ),
                const SizedBox(height: KSpacing.lg),
                KShake(child: TextFormField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: KText.numSmall.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: _inputDecoration(label: 'Threshold (kcal)'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Add a number';
                    }
                    final val = int.tryParse(value);
                    if (val == null) return 'Use a whole number';
                    if (val < 50 || val > 1000) {
                      return 'Keep it between 50 and 1,000 kcal';
                    }
                    return null;
                  },
                )),
              ],
            ),
          ),
          actions: [
            _DialogCancel(onPressed: () => Navigator.pop(ctx)),
            _DialogConfirm(
              label: 'Save',
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final val = int.parse(ctrl.text.trim());
                  Navigator.pop(ctx);
                  _saveProfile(_profile.copyWith(carryForwardThreshold: val));
                  _showToast('Threshold saved.', success: true);
                } else {
                  KHaptics.reject();
                  KShake.shakeInvalid(formKey.currentContext);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // ── Account (danger zone) ──────────────────────────────────────────────────

  Widget _buildAccountCard() {
    return _Group(
      title: 'Account',
      danger: true,
      children: [_buildLogoutButton(), _buildDeleteAccountButton()],
    );
  }

  Widget _buildDeleteAccountButton() {
    return _SettingRow(
      icon: Icons.delete_forever_rounded,
      tint: KColor.danger,
      label: 'Delete account',
      subtitle: 'Erase your account and all your data',
      danger: true,
      onTap: () => Navigator.of(
        context,
      ).push(kRiseRoute(builder: (_) => const AccountDeletionScreen())),
    );
  }

  Widget _buildLogoutButton() {
    return _SettingRow(
      icon: Icons.logout_rounded,
      tint: KColor.danger,
      label: 'Log out',
      subtitle: 'Sign out of Kynetix on this device',
      danger: true,
      haptic: false, // _handleLogout fires its own selection tick
      onTap: _handleLogout,
    );
  }

  Future<void> _handleLogout() async {
    kHapticSelect();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _KDialog(
        title: 'Log out?',
        icon: Icons.logout_rounded,
        iconColor: KColor.danger,
        content: Text(
          'Offline data on this device gets cleared, and you\'ll need to sign in again.',
          style: _dialogBody,
        ),
        actions: [
          _DialogCancel(onPressed: () => Navigator.pop(ctx, false)),
          _DialogConfirm(
            label: 'Log out',
            danger: true,
            onPressed: () => Navigator.pop(ctx, true),
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
      builder: (_) => const _SigningOutDialog(),
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

        _showToast('Couldn\'t log out cleanly. Try again in a moment.');
      }
    }
  }
}

// ─── Shared styling helpers ───────────────────────────────────────────────────

// Goals are told apart by their name, not a hue: one neutral dot for all.
Color _goalColor(String goal) => KColor.textSecondary;

TextStyle get _dialogBody =>
    KText.body.copyWith(color: KColor.textSecondary, fontSize: 13, height: 1.5);

InputDecoration _inputDecoration({String? label, String? suffix}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: KRadius.sm,
    borderSide: c == Colors.transparent
        ? BorderSide.none
        : BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    labelStyle: KText.caption.copyWith(color: KColor.textMuted),
    suffixText: suffix,
    suffixStyle: KText.caption.copyWith(color: KColor.textMuted, fontSize: 14),
    filled: true,
    fillColor: KColor.isDark ? KColor.bg : KColor.card,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: KSpacing.lg,
      vertical: 14,
    ),
    border: border(Colors.transparent),
    enabledBorder: border(
      KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.08),
    ),
    errorStyle: KText.caption.copyWith(color: KColor.danger, fontSize: 11),
    focusedBorder: border(KColor.ink, 1.2),
    errorBorder: border(KColor.danger.withValues(alpha: 0.6)),
    focusedErrorBorder: border(KColor.danger, 1.2),
  );
}

// ─── Theme mode segmented control ─────────────────────────────────────────────
// State is carried by the ink thumb, the semantics "selected" flag and a
// filled icon, never colour alone.

class _ThemeModeSegmented extends StatelessWidget {
  const _ThemeModeSegmented({required this.selected});
  final ThemeMode selected;

  @override
  Widget build(BuildContext context) {
    return KSegmented<ThemeMode>(
      value: selected,
      onChanged: (m) => KThemeController.instance.set(m),
      segments: const [
        KSegment(ThemeMode.dark, 'Dark',
            icon: Icons.dark_mode_outlined, selectedIcon: Icons.dark_mode_rounded,
            semanticLabel: 'Dark theme'),
        KSegment(ThemeMode.light, 'Light',
            icon: Icons.light_mode_outlined, selectedIcon: Icons.light_mode_rounded,
            semanticLabel: 'Light theme'),
        KSegment(ThemeMode.system, 'System',
            icon: Icons.brightness_auto_outlined, selectedIcon: Icons.brightness_auto_rounded,
            semanticLabel: 'System theme'),
      ],
    );
  }
}

// ─── Group (editorial section: heading + ruled rows, no card) ────────────────

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool danger;
  const _Group({
    required this.title,
    required this.children,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const _Hairline(indent: 56));
      rows.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.lg,
            0,
            KSpacing.lg,
            KSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: KText.h3.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                color: danger ? KColor.danger : KColor.textMuted,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.emphasizedCurve,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: KSpacing.lg),
      child: Container(
        height: 1,
        color: KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.09),
      ),
    );
  }
}

// ─── Row icon ─────────────────────────────────────────────────────────────────
// A bare outlined glyph in a fixed 24dp slot: no tinted tile behind it.

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.tint});
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Icon(icon, size: KIcons.md, color: tint),
        ),
      ),
    );
  }
}

// ─── Setting row ──────────────────────────────────────────────────────────────

/// Width of every row's trailing affordance slot (pencil / chevron / empty).
const double _kTrailingSlot = 20;

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String? value;
  final String? subtitle;
  final Color? valueColor;
  final bool isEditable;
  final bool danger;
  final bool haptic;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.tint,
    required this.label,
    this.value,
    this.subtitle,
    this.valueColor,
    this.isEditable = false,
    this.danger = false,
    this.haptic = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = danger ? KColor.danger : KColor.textPrimary;
    final tappable = onTap != null;

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KSpacing.lg, 10, KSpacing.lg, 10),
        child: Row(
          children: [
            _IconTile(icon: icon, tint: tint),
            const SizedBox(width: KSpacing.lg),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: KText.bodyMedium.copyWith(
                      color: labelColor,
                      fontSize: 15,
                      fontWeight: danger ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: KText.caption.copyWith(
                        color: KColor.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: KSpacing.md),
              Flexible(
                flex: 4,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    style: KText.bodyMedium.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: valueColor ?? KColor.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
            // Same-width trailing slot on every row (pencil, chevron or
            // empty) so editable and read-only values share one right edge.
            const SizedBox(width: KSpacing.sm),
            SizedBox(
              width: _kTrailingSlot,
              child: tappable
                  ? ExcludeSemantics(
                      child: Icon(
                        isEditable
                            ? Icons.edit_outlined
                            : Icons.chevron_right_rounded,
                        size: isEditable ? 15 : 20,
                        color: danger ? KColor.danger : KColor.textMuted,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );

    if (!tappable) return MergeSemantics(child: row);

    final hint = isEditable ? ', edit' : '';
    return Pressable(
      onTap: () {
        if (haptic) KHaptics.select();
        onTap!();
      },
      scale: 0.985,
      borderRadius: KRadius.md,
      semanticLabel: value == null ? '$label$hint' : '$label, $value$hint',
      child: row,
    );
  }
}

// ─── Compact diagnostic row (inside "Connection Details") ─────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KSpacing.lg, 7, KSpacing.lg, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: ExcludeSemantics(
                child: Icon(icon, size: 14, color: KColor.textMuted),
              ),
            ),
            const SizedBox(width: KSpacing.sm),
            Expanded(
              flex: 5,
              child: Text(
                label,
                style: KText.caption.copyWith(color: KColor.textMuted),
              ),
            ),
            const SizedBox(width: KSpacing.sm),
            Flexible(
              flex: 4,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: KText.caption.copyWith(
                  color: KColor.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Switch row ───────────────────────────────────────────────────────────────

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void toggle(bool v) {
      KHaptics.select();
      onChanged(v);
    }

    return MergeSemantics(
      child: Pressable(
        onTap: () => toggle(!value),
        scale: 0.985,
        borderRadius: KRadius.md,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KSpacing.lg, 10, KSpacing.sm, 10),
          child: Row(
            children: [
              _IconTile(icon: icon, tint: tint),
              const SizedBox(width: KSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: KText.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: KText.caption.copyWith(
                        color: KColor.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Switch(
                value: value,
                activeThumbColor: KColor.onInk,
                activeTrackColor: KColor.ink,
                inactiveThumbColor: KColor.textMuted,
                inactiveTrackColor: KColor.fg.withValues(
                  alpha: KColor.isDark ? 0.08 : 0.07,
                ),
                trackOutlineColor: WidgetStatePropertyAll(
                  KColor.fg.withValues(alpha: KColor.isDark ? 0.09 : 0.1),
                ),
                onChanged: toggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pill action (Sync / Connect / Disconnect) ────────────────────────────────
// In-flight progress shows on the control itself, never over the screen.

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.label,
    required this.busy,
    required this.onTap,
    this.color,
  });

  final String label;

  /// Null = primary ink pill. A semantic colour (e.g. danger) = tinted outline.
  final Color? color;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = KMotion.of(context, KMotion.quick);
    final tone = color;
    final fg = tone ?? KColor.onInk;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: busy ? '$label, working' : label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap == null
            ? null
            : () {
                KHaptics.commit();
                onTap!();
              },
        scale: 0.94,
        borderRadius: KRadius.pill,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: d,
              constraints: const BoxConstraints(minHeight: 36, minWidth: 72),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: tone == null
                    ? KColor.ink.withValues(alpha: busy ? 0.5 : 1)
                    : tone.withValues(alpha: KColor.isDark ? 0.1 : 0.07),
                borderRadius: KRadius.pill,
                border: tone == null
                    ? null
                    : Border.all(color: tone.withValues(alpha: 0.45)),
              ),
              child: AnimatedSwitcher(
                duration: d,
                child: busy
                    ? KSpinner(key: const ValueKey('busy'), size: 16, color: fg)
                    : Text(
                        label,
                        key: ValueKey(label),
                        style: KText.caption.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Choice pill (carry-forward thresholds) ───────────────────────────────────

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final d = KMotion.of(context, KMotion.standard);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          KHaptics.select();
          onTap();
        },
        scale: 0.94,
        borderRadius: KRadius.pill,
        child: AnimatedContainer(
          duration: d,
          curve: KMotion.emphasizedCurve,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? KColor.ink : Colors.transparent,
            borderRadius: KRadius.pill,
            border: Border.all(
              color: selected ? KColor.ink : KColor.fg.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 13, color: KColor.onInk),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  style: KText.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? KColor.onInk : KColor.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 11, color: KColor.onInk),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero stat tile (animated count) ──────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.tint,
    this.decimals = 0,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final double value;
  final String unit;
  final Color tint;
  final int decimals;
  final VoidCallback? onTap;

  String _fmt(double v) => decimals == 0 ? whole(v) : amount(v);

  @override
  Widget build(BuildContext context) {
    final finalText = _fmt(value);
    // One column of the ruled numbers row: the number large, the unit and
    // label small underneath. Meaning colour lives on a dot, not a tile.
    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(2, KSpacing.md, 2, KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Rolls up from 0 when the screen opens, then rolls only the
          // digits that change after an edit.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                KRollingNumber(
                  _fmt(value.isFinite ? value : 0),
                  style: KText.numMedium.copyWith(fontSize: 19),
                  fromZero: true,
                  alignment: Alignment.center,
                ),
                Text(
                  ' $unit',
                  style: KText.caption.copyWith(
                    color: KColor.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tint != KColor.textSecondary) ...[
                KDot(color: tint, size: 5),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  style: KText.caption.copyWith(
                    fontSize: 11.5,
                    color: KColor.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final spoken = '$label $finalText $unit';
    if (onTap == null) {
      return Semantics(label: spoken, excludeSemantics: true, child: tile);
    }
    return Pressable(
      onTap: () {
        KHaptics.select();
        onTap!();
      },
      scale: 0.96,
      borderRadius: KRadius.sm,
      semanticLabel: '$spoken, edit',
      child: tile,
    );
  }
}

// ─── AI status skeleton ───────────────────────────────────────────────────────

class _AiStatusSkeleton extends StatelessWidget {
  const _AiStatusSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Checking ChatGPT status',
      child: const Padding(
        padding: EdgeInsets.fromLTRB(
          KSpacing.lg,
          KSpacing.md,
          KSpacing.lg,
          KSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                KShimmerBox(
                  width: 36,
                  height: 36,
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                ),
                SizedBox(width: KSpacing.md),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: KShimmerBox(
                      width: 110,
                      height: 14,
                      borderRadius: KRadius.sm,
                    ),
                  ),
                ),
                KShimmerBox(width: 84, height: 32, borderRadius: KRadius.pill),
              ],
            ),
            SizedBox(height: KSpacing.md),
            KShimmerBox(
              width: double.infinity,
              height: 10,
              borderRadius: KRadius.sm,
            ),
            SizedBox(height: 6),
            FractionallySizedBox(
              widthFactor: 0.7,
              child: KShimmerBox(
                width: double.infinity,
                height: 10,
                borderRadius: KRadius.sm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet option (goal / eating style) ───────────────────────────────────────

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: 3),
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: () {
            KHaptics.select();
            onTap();
          },
          scale: 0.98,
          borderRadius: KRadius.md,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: KSpacing.lg,
              vertical: KSpacing.md,
            ),
            decoration: BoxDecoration(
              color: KColor.card,
              borderRadius: KRadius.md,
              border: Border.all(
                color: selected
                    ? KColor.ink
                    : KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.08),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: KSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: KText.bodyMedium.copyWith(
                      color: KColor.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: KSpacing.sm),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? KColor.ink : KColor.textDisabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Dialog chrome ────────────────────────────────────────────────────────────

class _KDialog extends StatelessWidget {
  const _KDialog({
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
    Color? iconColor,
  }) : _iconColor = iconColor;

  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final Color? _iconColor;
  Color get iconColor => _iconColor ?? KColor.ink;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColor.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.xl,
        side: BorderSide(
          color: KColor.fg.withValues(alpha: KColor.isDark ? 0.09 : 0.1),
        ),
      ),
      icon: icon == null
          ? null
          : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: KRadius.md,
                border: Border.all(color: iconColor.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
      title: Text(title, style: KText.h2),
      content: content,
      actionsPadding: const EdgeInsets.fromLTRB(
        KSpacing.lg,
        0,
        KSpacing.lg,
        KSpacing.lg,
      ),
      actions: actions,
    );
  }
}

class _DialogCancel extends StatelessWidget {
  const _DialogCancel({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
      child: Text(
        'Cancel',
        style: KText.bodyMedium.copyWith(
          color: KColor.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DialogConfirm extends StatelessWidget {
  const _DialogConfirm({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? KColor.danger : KColor.ink;
    final fg = danger ? KColor.onAccent : KColor.onInk;
    return FilledButton(
      onPressed: () {
        KHaptics.commit();
        onPressed();
      },
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(88, 48),
        shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
      ),
      child: Text(
        label,
        style: KText.bodyMedium.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SigningOutDialog extends StatelessWidget {
  const _SigningOutDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          liveRegion: true,
          label: 'Signing out',
          child: KCard(
            padding: const EdgeInsets.symmetric(
              horizontal: KSpacing.xxl,
              vertical: KSpacing.xl,
            ),
            borderRadius: KRadius.xl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const KSpinner(size: 20),
                const SizedBox(width: KSpacing.lg),
                Flexible(
                  child: Text(
                    'Signing out…',
                    style: KText.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Goal chip ────────────────────────────────────────────────────────────────

class _GoalChip extends StatelessWidget {
  final String goal;
  const _GoalChip({required this.goal});

  @override
  Widget build(BuildContext context) {
    // The goal as a coloured word with a dot: no tinted pill.
    final color = _goalColor(goal);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KDot(color: color, size: 7),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            goal,
            style: KText.bodyMedium.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: KColor.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Home screen widget picker ────────────────────────────────────────────────
// Each size, drawn as its shape on a 4x4 grid, and a tap that asks the
// launcher to place it.

class _WidgetPickerSheet extends StatelessWidget {
  const _WidgetPickerSheet();

  static const _sizes = [
    ('2x2', 'Rings', 'Calories and protein left, on your wallpaper.', 2, 2),
    ('4x2', 'Wide', 'Rings with what is left and what you have eaten.', 4, 2),
    ('2x4', 'Tall', 'Rings, eaten of target, and a Log meal button.', 2, 4),
    ('4x4', 'Large', 'Your whole day, with a Log meal button.', 4, 4),
  ];

  Future<void> _pin(BuildContext context, String size) async {
    final ok = await WidgetService.pinWidget(size);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!ok) {
      showKToast(context, 'Long-press your home screen, tap Widgets, then find Kynetix.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, KSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: KDragHandle()),
            const SizedBox(height: KSpacing.md),
            Text('Add a widget', style: KText.h2),
            const SizedBox(height: 4),
            Text(
              'Pick a size. Your phone asks where to put it.',
              style: KText.body.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: KSpacing.lg),
            for (final (size, name, about, w, h) in _sizes)
              Pressable(
                onTap: () => _pin(context, size),
                haptic: true,
                scale: 0.98,
                borderRadius: KRadius.md,
                semanticLabel: '$name widget, $size. $about',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _SizeGlyph(w: w, h: h),
                      const SizedBox(width: KSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$name, $size', style: KText.h3),
                            const SizedBox(height: 2),
                            Text(about, style: KText.caption.copyWith(fontSize: 13, color: KColor.textMuted)),
                          ],
                        ),
                      ),
                      Icon(Icons.add_rounded, color: KColor.textSecondary),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A widget size as filled cells on a 4x4 grid.
class _SizeGlyph extends StatelessWidget {
  const _SizeGlyph({required this.w, required this.h});
  final int w;
  final int h;

  @override
  Widget build(BuildContext context) {
    const cell = 9.0;
    const gap = 2.0;
    return SizedBox(
      width: cell * 4 + gap * 3,
      height: cell * 4 + gap * 3,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var r = 0; r < 4; r++)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var c = 0; c < 4; c++)
                  Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2.5),
                      color: (c < w && r < h) ? KColor.ink : KColor.cardHigh,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
