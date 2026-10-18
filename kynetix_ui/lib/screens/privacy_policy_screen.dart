import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException, rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../config/app_theme.dart';

/// Renders the bundled privacy policy (`docs/PRIVACY_POLICY.md`).
///
/// Read-only: no consent is collected here. Opened from the sign-in screen's
/// legal line, Settings, the consent step, and Health Connect's "privacy
/// policy" link (see [PrivacyPolicyLaunch]).
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key, this.healthRationale = false});

  static const assetPath = 'docs/PRIVACY_POLICY.md';

  /// Opened from Health Connect's permission screen: lead with a short note
  /// on which health data Kynetix reads and why.
  final bool healthRationale;

  static const healthRationaleNote =
      '> **Why Kynetix asks for health data.** With your permission, Kynetix '
      '**reads** steps, body weight, sleep sessions and heart-rate variability '
      'from Health Connect to show your activity, weight trend and recovery. '
      'It never writes to Health Connect, never uses this data for ads, and '
      'you can turn access off at any time in Health Connect. Details are in '
      'section 2.2 below.' '\n\n';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late Future<String> _policy = _load();

  Future<String> _load() async {
    final policy = await rootBundle.loadString(PrivacyPolicyScreen.assetPath);
    return widget.healthRationale
        ? '${PrivacyPolicyScreen.healthRationaleNote}$policy'
        : policy;
  }

  void _retry() => setState(() => _policy = _load());

  @override
  Widget build(BuildContext context) {
    return KPage(
      tone: KTone.neutral,
      intensity: 0.5,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Privacy policy', style: KText.h3.copyWith(fontSize: 16)),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<String>(
          future: _policy,
          builder: (context, snap) {
            final Widget child;
            if (snap.hasError) {
              child = _PolicyError(key: const ValueKey('policy-error'), onRetry: _retry);
            } else if (!snap.hasData) {
              child = const _PolicyLoading(key: ValueKey('policy-loading'));
            } else {
              child = _PolicyBody(key: const ValueKey('policy-body'), data: snap.data!);
            }
            return AnimatedSwitcher(
              duration: KMotion.of(context, KMotion.standard),
              switchInCurve: KMotion.decelerate,
              switchOutCurve: KMotion.accelerate,
              child: child,
            );
          },
        ),
      ),
    );
  }
}

// ─── Loading ──────────────────────────────────────────────────────────────────
// Neutral placeholder shaped like the document (a title and paragraphs).

class _PolicyLoading extends StatelessWidget {
  const _PolicyLoading({super.key});

  @override
  Widget build(BuildContext context) {
    Widget line(double w, [double h = 12]) => Padding(
          padding: const EdgeInsets.only(bottom: KSpacing.md),
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: w,
            child: Container(
              height: h,
              decoration: BoxDecoration(
                color: KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.06),
                borderRadius: KRadius.pill,
              ),
            ),
          ),
        );
    return Semantics(
      label: 'Loading privacy policy',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.lg, KSpacing.xl, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(0.7, 26),
              const SizedBox(height: KSpacing.lg),
              line(1),
              line(0.94),
              line(0.82),
              const SizedBox(height: KSpacing.lg),
              line(0.45, 18),
              line(1),
              line(0.9),
              line(0.6),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Error ────────────────────────────────────────────────────────────────────

class _PolicyError extends StatelessWidget {
  const _PolicyError({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 36, color: KColor.textMuted),
              const SizedBox(height: KSpacing.lg),
              Semantics(
                liveRegion: true,
                child: Text(
                  'We couldn\'t open the privacy policy',
                  textAlign: TextAlign.center,
                  style: KText.h2,
                ),
              ),
              const SizedBox(height: KSpacing.sm),
              Text(
                'The document didn\'t load on this device. Try again, or reopen the app.',
                textAlign: TextAlign.center,
                style: KText.body.copyWith(color: KColor.textSecondary),
              ),
              const SizedBox(height: KSpacing.xxl),
              KButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                outlined: true,
                onTap: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _PolicyBody extends StatelessWidget {
  const _PolicyBody({super.key, required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    final hairline = dark ? KColor.fg.withValues(alpha: 0.10) : KColor.border;
    final body = KText.body.copyWith(fontSize: 15, height: 1.6, color: KColor.textSecondary);

    final sheet = MarkdownStyleSheet(
      a: body.copyWith(
        color: KColor.textPrimary,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
        decorationColor: KColor.textMuted,
      ),
      p: body,
      pPadding: EdgeInsets.zero,
      h1: KText.display.copyWith(fontSize: 32, height: 1.1),
      h1Padding: const EdgeInsets.only(top: KSpacing.sm, bottom: KSpacing.xs),
      h2: KText.h1.copyWith(fontSize: 21),
      h2Padding: const EdgeInsets.only(top: KSpacing.xl),
      h3: KText.h2.copyWith(fontSize: 16.5),
      h3Padding: const EdgeInsets.only(top: KSpacing.md),
      h4: KText.h3,
      h5: KText.h3,
      h6: KText.h3.copyWith(color: KColor.textSecondary),
      em: body.copyWith(fontStyle: FontStyle.italic),
      strong: body.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w600),
      del: body.copyWith(decoration: TextDecoration.lineThrough),
      code: KText.numSmall.copyWith(
        fontSize: 13,
        color: KColor.textPrimary,
        backgroundColor: KColor.fg.withValues(alpha: dark ? 0.08 : 0.06),
      ),
      blockquote: body,
      blockquotePadding: const EdgeInsets.all(KSpacing.lg),
      blockquoteDecoration: BoxDecoration(
        color: KColor.saffron.withValues(alpha: dark ? 0.08 : 0.07),
        borderRadius: KRadius.md,
        border: Border.all(color: KColor.saffron.withValues(alpha: dark ? 0.30 : 0.35)),
      ),
      listBullet: body.copyWith(color: KColor.textMuted),
      listIndent: KSpacing.xxl,
      blockSpacing: KSpacing.md,
      tableHead: KText.caption.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w700, fontSize: 12.5),
      tableBody: KText.caption.copyWith(color: KColor.textSecondary, fontSize: 12.5, height: 1.45),
      tableHeadAlign: TextAlign.start,
      tableBorder: TableBorder.all(color: hairline, width: 1, borderRadius: KRadius.sm),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: KSpacing.sm, vertical: KSpacing.sm),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: hairline, width: 1)),
      ),
      codeblockDecoration: BoxDecoration(
        color: KColor.fg.withValues(alpha: dark ? 0.05 : 0.04),
        borderRadius: KRadius.sm,
      ),
      codeblockPadding: const EdgeInsets.all(KSpacing.md),
    );

    return Scrollbar(
      child: Markdown(
        data: data,
        styleSheet: sheet,
        selectable: false,
        padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.sm, KSpacing.xl, KSpacing.xxxl * 2),
      ),
    );
  }
}

// ─── Launch from Health Connect ───────────────────────────────────────────────
// Health Connect opens the app with ACTION_SHOW_PERMISSIONS_RATIONALE (Android
// 13 and lower) or VIEW_PERMISSION_USAGE (Android 14+, via the activity
// alias). MainActivity turns either into the launch action "privacy_policy"
// on the `com.kynetix.app/launch` channel; this shows the policy on top of
// whatever is on screen (sign-in or the app).

class PrivacyPolicyLaunch {
  PrivacyPolicyLaunch._();

  static const channel = MethodChannel('com.kynetix.app/launch');
  static const actionPrivacyPolicy = 'privacy_policy';

  static Object? _owner;
  static NavigatorState? Function()? _navigator;
  static bool _showing = false;

  /// Starts listening (and handles a cold-start launch). The latest owner
  /// wins; [detach] only clears the handler if [owner] still owns it.
  static void attach(Object owner, NavigatorState? Function() navigator) {
    _owner = owner;
    _navigator = navigator;
    try {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'onLaunchAction') handle(call.arguments as String?);
        return null;
      });
      channel
          .invokeMethod<String>('getLaunchAction')
          .then(handle)
          .catchError((Object e) {
        if (e is! MissingPluginException && kDebugMode) {
          debugPrint('[PrivacyPolicyLaunch] getLaunchAction failed: $e');
        }
        return null;
      }).ignore();
    } catch (_) {}
  }

  static void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _navigator = null;
    try {
      channel.setMethodCallHandler(null);
    } catch (_) {}
  }

  /// Shows the policy for [action] == [actionPrivacyPolicy]; ignores anything else.
  static void handle(String? action) {
    if (action != actionPrivacyPolicy || _showing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _navigator?.call();
      if (nav == null || _showing) return;
      _showing = true;
      nav
          .push(kRiseRoute(
            builder: (_) => const PrivacyPolicyScreen(healthRationale: true),
          ))
          .whenComplete(() => _showing = false)
          .ignore();
    });
  }
}
