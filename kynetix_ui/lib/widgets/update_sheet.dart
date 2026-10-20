import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../services/analytics_service.dart';
import '../services/update_check_service.dart';

// ─── Update sheet (sideload builds only) ──────────────────────────────────────
// A calm note that a newer build is out. "Get it" opens the download page in
// the browser; the app never downloads or installs anything itself. A
// required update drops "Later" and can't be swiped away, but system back
// still closes it: the app is never locked.

/// Checks for an update and, if there is one, shows the sheet. For app start.
Future<void> maybePromptUpdate(BuildContext context) async {
  final result = await UpdateCheckService.instance.check();
  if (result.kind == UpdateKind.none || !context.mounted) return;
  await showUpdateSheet(context, result);
}

Future<void> showUpdateSheet(BuildContext context, UpdateCheck result) {
  final release = result.release!;
  final required = result.kind == UpdateKind.required;
  AnalyticsService.instance.track('update_prompt_shown', {
    'version_code': release.versionCode,
    'kind': result.kind.name,
  });
  return showKSheet<void>(
    context: context,
    isDismissible: !required,
    enableDrag: !required,
    builder: (_) => UpdateSheet(release: release, kind: result.kind),
  );
}

class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.release, required this.kind, this.open});

  final AppRelease release;
  final UpdateKind kind;

  /// Opens a link. Defaults to the external browser; tests swap it.
  final Future<bool> Function(Uri uri)? open;

  Future<void> _go(BuildContext context, String link) async {
    KHaptics.commit();
    AnalyticsService.instance.track('update_clicked', {'version_code': release.versionCode});
    final navigator = Navigator.of(context);
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      await (open ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {}
    if (kind != UpdateKind.required && navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final play = kind == UpdateKind.play;
    final required = kind == UpdateKind.required;
    final body = KText.body.copyWith(fontSize: 15, height: 1.45, color: KColor.textSecondary);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: KSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KSheetHeader(
              play ? 'Kynetix is on Google Play now' : 'Fresh build ready',
              subtitle: play
                  ? 'Updates come from the Play Store from here on.'
                  : required
                      ? 'Version ${release.versionName}. This one is needed to keep things working.'
                      : 'Version ${release.versionName}.',
            ),
            const SizedBox(height: KSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (play)
                    Text(
                      'Your account and data come with you. Install it from Play, then sign in again.',
                      style: body,
                    )
                  else
                    for (final n in release.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: KSpacing.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, right: KSpacing.md),
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: KColor.ember),
                              ),
                            ),
                            Expanded(child: Text(n, style: body)),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: KSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              child: KButton(
                label: play ? 'Open Google Play' : 'Get it',
                icon: play ? Icons.shop_rounded : Icons.download_rounded,
                onTap: () => _go(context, play ? release.playUrl! : release.page),
              ),
            ),
            if (!required) ...[
              const SizedBox(height: KSpacing.xs),
              Center(
                child: KTextAction(
                  'Later',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
