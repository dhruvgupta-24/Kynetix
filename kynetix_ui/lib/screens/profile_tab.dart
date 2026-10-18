import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';
import '../services/avatar_service.dart';
import '../services/body_metrics_service.dart';
import '../services/insights_report_service.dart';
import '../services/nutrition_target_engine.dart';
import '../services/profile_service.dart';
import '../services/workout_service.dart';
import '../widgets/k_avatar.dart';
import 'connect_chatgpt_screen.dart';
import 'insights_screen.dart';
import 'nutrition_intelligence_screen.dart';
import 'profile_screen.dart';
import 'workout_history_screen.dart';

/// The Profile tab: who you are in Kynetix, your record so far, and the way
/// into everything personal. Settings sit behind the gear, top right.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _picker = ImagePicker();

  Future<void> _push(Widget page) async {
    KHaptics.select();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return;
      await AvatarService.instance.setPhoto(await file.readAsBytes());
      KHaptics.commit();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open that photo. Try another one."), persist: false),
      );
    }
  }

  void _changePhoto() {
    KHaptics.select();
    final hasPhoto = AvatarService.instance.photo.value != null;
    showKSheet<void>(
      context: context,
      builder: (ctx) {
        Widget option(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              leading: Icon(icon, color: danger ? KColor.danger : KColor.textPrimary),
              title: Text(label, style: KText.bodyMedium.copyWith(fontSize: 15, color: danger ? KColor.danger : KColor.textPrimary)),
              onTap: () {
                Navigator.of(ctx).pop();
                onTap();
              },
            );
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: KSpacing.sm, bottom: KSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: KDragHandle()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, KSpacing.sm),
                  child: Text('Profile photo', style: KText.h2),
                ),
                option(Icons.photo_library_outlined, 'Choose from gallery', () => _pick(ImageSource.gallery)),
                option(Icons.photo_camera_outlined, 'Take a photo', () => _pick(ImageSource.camera)),
                if (hasPhoto)
                  option(Icons.delete_outline_rounded, 'Remove photo', () => AvatarService.instance.removePhoto(), danger: true),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService.instance.currentUserProfile;
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (profile == null) return const SizedBox.shrink();
    final plan = NutritionTargetEngine().weeklyPlan(profile);
    final daysLogged = dayLogStore.values.where((d) => !d.isEmpty).length;
    final meals = dayLogStore.values.fold<int>(0, (s, d) => s + d.allEntries.length);
    final workouts = WorkoutService.instance.sessions.length;
    final weight = BodyMetricsService.instance.trend().latest?.trendKg ?? profile.weight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, KSpacing.dockClearance + bottom),
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(header: true, child: Text('Profile', style: KText.display.copyWith(fontSize: 28))),
                ),
                _RoundIcon(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => _push(const ProfileScreen()),
                ),
              ],
            ),
            const SizedBox(height: KSpacing.xl),
            Center(
              child: Pressable(
                onTap: _changePhoto,
                semanticLabel: 'Change profile photo',
                borderRadius: BorderRadius.circular(60),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const KAvatar(size: 104),
                    Positioned(
                      right: 0,
                      bottom: 2,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KColor.ink,
                          border: Border.all(color: KColor.bg, width: 3),
                        ),
                        child: Icon(Icons.photo_camera_rounded, size: 15, color: KColor.onInk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KSpacing.lg),
            Text(
              profile.name.trim().isEmpty ? 'You' : profile.name.trim(),
              textAlign: TextAlign.center,
              style: KText.h1,
            ),
            const SizedBox(height: 4),
            Text(
              '${profile.goal}, ${thousands(plan.avgDailyCalories)} kcal and ${plan.avgDailyProtein.round()} g protein a day',
              textAlign: TextAlign.center,
              style: KText.body.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: KSpacing.xl),
            KCard(
              padding: const EdgeInsets.symmetric(vertical: KSpacing.lg),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _Stat(value: thousands(daysLogged), label: daysLogged == 1 ? 'day logged' : 'days logged'),
                    VerticalDivider(color: KColor.divider, width: 1),
                    _Stat(value: thousands(meals), label: meals == 1 ? 'meal' : 'meals'),
                    VerticalDivider(color: KColor.divider, width: 1),
                    _Stat(value: thousands(workouts), label: workouts == 1 ? 'workout' : 'workouts'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KSpacing.md),
            Row(
              children: [
                Expanded(child: _BodyTile(label: 'Weight', value: weight.toStringAsFixed(1), unit: 'kg')),
                const SizedBox(width: KSpacing.md),
                Expanded(child: _BodyTile(label: 'Height', value: profile.height.round().toString(), unit: 'cm')),
                const SizedBox(width: KSpacing.md),
                Expanded(child: _BodyTile(label: 'BMI', value: profile.bmi.toStringAsFixed(1))),
              ],
            ),
            const SizedBox(height: KSpacing.xl),
            KCard(
              padding: const EdgeInsets.symmetric(vertical: KSpacing.xs),
              child: ListenableBuilder(
                listenable: InsightsReportService.instance,
                builder: (context, _) {
                  final fresh = InsightsReportService.instance.newAchievementCount;
                  return Column(
                    children: [
                      _MenuRow(
                        icon: Icons.insights_rounded,
                        label: 'Insights and reports',
                        trailing: fresh > 0 ? '$fresh new' : null,
                        onTap: () => _push(const InsightsScreen()),
                      ),
                      const KHairline(indent: 56),
                      _MenuRow(
                        icon: KIcons.train,
                        label: 'Workout history',
                        onTap: () => _push(const WorkoutHistoryScreen()),
                      ),
                      const KHairline(indent: 56),
                      _MenuRow(
                        icon: Icons.menu_book_outlined,
                        label: 'Food library',
                        onTap: () => _push(const NutritionIntelligenceScreen()),
                      ),
                      const KHairline(indent: 56),
                      _MenuRow(
                        icon: Icons.bolt_outlined,
                        label: 'Run Kyno on ChatGPT',
                        onTap: () => _push(const ConnectChatGptScreen()),
                      ),
                      const KHairline(indent: 56),
                      _MenuRow(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: () => _push(const ProfileScreen()),
                      ),
                    ],
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

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KColor.card,
            border: Border.all(color: KColor.hairline),
          ),
          child: Icon(icon, size: 21, color: KColor.textPrimary),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: KText.numMedium.copyWith(fontSize: 24)),
            const SizedBox(height: 2),
            Text(label, style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textMuted)),
          ],
        ),
      );
}

class _BodyTile extends StatelessWidget {
  const _BodyTile({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) => KCard(
        padding: const EdgeInsets.fromLTRB(KSpacing.md, KSpacing.md, KSpacing.sm, KSpacing.md),
        borderRadius: KRadius.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: value, style: KText.numMedium.copyWith(fontSize: 20)),
                  if (unit != null)
                    TextSpan(text: ' $unit', style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
                ]),
              ),
            ),
          ],
        ),
      );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.onTap, this.trailing});
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.98,
        semanticLabel: trailing == null ? label : '$label, $trailing',
        borderRadius: KRadius.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 20, color: KColor.textSecondary),
              const SizedBox(width: KSpacing.lg),
              Expanded(child: Text(label, style: KText.bodyMedium.copyWith(fontSize: 15))),
              if (trailing != null) ...[
                Text(trailing!, style: KText.caption.copyWith(fontSize: 12.5, color: KColor.green)),
                const SizedBox(width: KSpacing.sm),
              ],
              Icon(Icons.chevron_right_rounded, size: 20, color: KColor.textMuted),
            ],
          ),
        ),
      );
}
