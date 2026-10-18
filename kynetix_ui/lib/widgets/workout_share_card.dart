import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart' show ExerciseExecutionMode;

// ─── Data ─────────────────────────────────────────────────────────────────────

/// One lift on the card: "Bench Press  80 × 5".
class ShareLift {
  final String name;
  final double weight;
  final int reps;
  final double e1rm;
  final bool isPr;
  const ShareLift({
    required this.name,
    required this.weight,
    required this.reps,
    required this.e1rm,
    this.isPr = false,
    this.bodyweight = false,
  });

  /// A pull-up or dip with no added load: printed as "BW × reps".
  final bool bodyweight;
}

/// Everything the share card prints, computed once from a saved session.
class WorkoutShareData {
  final DateTime date;
  final String dayName;
  final int durationMinutes;
  final double totalVolume;
  final int sets;
  final int prs;
  final List<ShareLift> topLifts;
  final List<String> muscles;

  const WorkoutShareData({
    required this.date,
    required this.dayName,
    required this.durationMinutes,
    required this.totalVolume,
    required this.sets,
    required this.prs,
    required this.topLifts,
    required this.muscles,
  });

  /// [isPr] says whether a set (of an exercise id) was a record; the screen
  /// passes the same rule it uses for its own PR count.
  factory WorkoutShareData.fromSession(
    WorkoutSession session, {
    required Duration duration,
    required int prCount,
    bool Function(String exerciseId, SetEntry set)? isPr,
  }) {
    return WorkoutShareData(
      date: session.date,
      dayName: session.splitDayName,
      durationMinutes: session.durationMinutes ?? duration.inMinutes,
      totalVolume: session.totalVolume,
      sets: session.totalSets,
      prs: prCount,
      topLifts: topLiftsOf(session, isPr: isPr),
      muscles: session.entries
          .where((e) => !e.isSkipped && e.sets.isNotEmpty)
          .map((e) => e.exercise.muscleGroup)
          .toSet()
          .take(4)
          .toList(),
    );
  }

  /// The three strongest lifts of the day, by each exercise's best working
  /// set (estimated 1RM). Warm-ups and drops never count; bodyweight lifts
  /// with no load print as "BW × 12"; other unloaded sets are left out.
  static List<ShareLift> topLiftsOf(
    WorkoutSession session, {
    int limit = 3,
    bool Function(String exerciseId, SetEntry set)? isPr,
  }) {
    final lifts = <ShareLift>[];
    for (final e in session.entries) {
      if (e.isSkipped) continue;
      final mode = e.exercise.effectiveExecutionMode;
      final bwLift = mode == ExerciseExecutionMode.bodyweightReps ||
          mode == ExerciseExecutionMode.weightedBodyweight;
      SetEntry? top;
      for (final s in e.sets) {
        if (!s.isMainWorkingSet || s.durationSeconds != null) continue;
        if (s.weight <= 0 && !bwLift) continue;
        final better = top == null ||
            s.estimatedOneRepMax > top.estimatedOneRepMax ||
            (s.estimatedOneRepMax == top.estimatedOneRepMax && s.reps > top.reps);
        if (better) top = s;
      }
      if (top == null) continue;
      final pr = isPr != null && e.sets.any((s) => s.isMainWorkingSet && isPr(e.exercise.id, s));
      lifts.add(ShareLift(
        name: e.exercise.name,
        weight: top.weight,
        reps: top.reps,
        e1rm: top.estimatedOneRepMax,
        isPr: pr,
        bodyweight: bwLift && top.weight <= 0,
      ));
    }
    lifts.sort((a, b) => b.e1rm.compareTo(a.e1rm));
    return lifts.take(limit).toList();
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

/// Logical size of the card; captured at 3x for a 1080 × 1350 (4:5) PNG,
/// the size WhatsApp and Instagram show uncropped.
const Size kShareCardSize = Size(360, 450);
const double kShareCardPixelRatio = 3.0;

/// The branded summary card. Takes an explicit [palette] (Carbon or Paper),
/// so the exported image doesn't depend on the app's current theme.
class WorkoutShareCard extends StatelessWidget {
  final WorkoutShareData data;
  final KPalette palette;
  const WorkoutShareCard({super.key, required this.data, required this.palette});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String get _dateLabel => '${data.date.day} ${_months[data.date.month - 1]} ${data.date.year}';

  static String _num(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
  }

  static String _thousands(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  TextStyle _t(double size, FontWeight w, Color c,
          {double spacing = 0, double height = 1.1, bool tabular = false, bool display = false}) =>
      TextStyle(
        fontFamily: display ? KText.displayFace : KText.family,
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: spacing,
        height: height,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        decoration: TextDecoration.none,
      );

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final dark = p.isDark;
    final hairline = p.fg.withValues(alpha: dark ? 0.12 : 0.14);

    Widget stat(String value, String unit, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: value, style: _t(30, FontWeight.w800, p.textPrimary, spacing: -1.2, tabular: true, display: true)),
                if (unit.isNotEmpty)
                  TextSpan(text: ' $unit', style: _t(12, FontWeight.w600, p.textSecondary, tabular: true)),
              ]),
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(label, style: _t(11, FontWeight.w500, p.textMuted)),
          ],
        );

    return SizedBox.fromSize(
      size: kShareCardSize,
      child: ClipRect(
        child: CustomPaint(
          painter: _LampGrainPainter(base: p.bg, lamp: p.violet, grain: p.fg, isDark: dark),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wordmark and date.
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: p.violet, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text('kynetix', style: _t(15, FontWeight.w800, p.textPrimary, spacing: -0.4)),
                    const Spacer(),
                    Text(_dateLabel, style: _t(11, FontWeight.w600, p.textSecondary, tabular: true)),
                  ],
                ),
                const SizedBox(height: 30),
                Text('Workout done', style: _t(12, FontWeight.w600, p.violet)),
                const SizedBox(height: 4),
                Text(
                  data.dayName,
                  maxLines: 2,
                  overflow: TextOverflow.fade,
                  style: _t(34, FontWeight.w800, p.textPrimary, spacing: -1.4, height: 1.02, display: true),
                ),
                const SizedBox(height: 22),
                Container(height: 2, color: p.textPrimary),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: stat(_thousands(data.totalVolume), 'kg', 'Volume')),
                    Expanded(child: stat('${data.sets}', '', data.sets == 1 ? 'Set' : 'Sets')),
                    Expanded(child: stat('${data.durationMinutes}', 'min', 'Time')),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: hairline),
                const SizedBox(height: 12),
                if (data.topLifts.isNotEmpty) ...[
                  Text('Top lifts', style: _t(11, FontWeight.w600, p.textMuted)),
                  const SizedBox(height: 8),
                  for (final l in data.topLifts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.name,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: _t(14, FontWeight.w600, p.textPrimary),
                            ),
                          ),
                          if (l.isPr) ...[
                            Text('PR', style: _t(10, FontWeight.w800, p.saffron, spacing: 0.4)),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            l.bodyweight ? 'BW × ${l.reps}' : '${_num(l.weight)} × ${l.reps}',
                            style: _t(15, FontWeight.w800, p.textPrimary, tabular: true, spacing: -0.3),
                          ),
                        ],
                      ),
                    ),
                ],
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final m in data.muscles)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: KRadius.xs,
                                border: Border.all(color: p.violet.withValues(alpha: 0.55)),
                                color: p.violet.withValues(alpha: dark ? 0.10 : 0.07),
                              ),
                              child: Text(m, style: _t(10, FontWeight.w600, p.textPrimary)),
                            ),
                        ],
                      ),
                    ),
                    if (data.prs > 0) ...[
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${data.prs}', style: _t(26, FontWeight.w800, p.saffron, tabular: true, spacing: -1)),
                          Text(data.prs == 1 ? 'Record' : 'Records', style: _t(10, FontWeight.w600, p.textMuted)),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lamp-light from the top corner plus a fixed film grain. Seeded, so the
/// same card always exports identically.
class _LampGrainPainter extends CustomPainter {
  _LampGrainPainter({required this.base, required this.lamp, required this.grain, required this.isDark});
  final Color base, lamp, grain;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final center = Offset(size.width * 0.92, -size.height * 0.08);
    final r = size.width * 1.15;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [
          lamp.withValues(alpha: isDark ? 0.30 : 0.16),
          lamp.withValues(alpha: isDark ? 0.08 : 0.04),
          lamp.withValues(alpha: 0),
        ], const [0.0, 0.45, 1.0]),
    );
    final rnd = math.Random(7);
    final dot = Paint()..color = grain.withValues(alpha: isDark ? 0.05 : 0.045);
    final pts = <Offset>[];
    for (var i = 0; i < 2600; i++) {
      pts.add(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height));
    }
    canvas.drawPoints(ui.PointMode.points, pts, dot..strokeWidth = 0.6);
  }

  @override
  bool shouldRepaint(covariant _LampGrainPainter old) =>
      old.base != base || old.lamp != lamp || old.grain != grain || old.isDark != isDark;
}

// ─── Share sheet ──────────────────────────────────────────────────────────────

/// Preview the card, pick Carbon or Paper, then share a 1080 × 1350 PNG.
Future<void> showWorkoutShareSheet(BuildContext context, WorkoutShareData data) {
  return showKSheet<void>(
    context: context,
    builder: (_) => _ShareSheet(data: data),
  );
}

class _ShareSheet extends StatefulWidget {
  final WorkoutShareData data;
  const _ShareSheet({required this.data});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  late bool _dark = KColor.isDark;
  bool _busy = false;
  String? _error;

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    KHaptics.commit();
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('card not painted');
      final image = await boundary.toImage(pixelRatio: kShareCardPixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('encode failed');
      final d = widget.data.date;
      final name = 'kynetix-workout-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.png';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        fileNameOverrides: [name],
        text: '${widget.data.dayName} done. Logged on Kynetix.',
      ));
    } catch (e) {
      debugPrint('[WORKOUT_SHARE] failed: $e');
      if (mounted) setState(() => _error = 'Couldn\'t make the image. Try again in a moment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _dark ? KPalette.dark : KPalette.light;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KSheetHeader('Share your workout', subtitle: 'A clean card for your story or the group chat.'),
            const SizedBox(height: 12),
            Center(
              child: Semantics(
                image: true,
                label: 'Workout card preview: ${widget.data.dayName}, ${widget.data.sets} sets, '
                    '${widget.data.totalVolume.round()} kilograms volume, ${widget.data.durationMinutes} minutes',
                excludeSemantics: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                  child: AspectRatio(
                    aspectRatio: kShareCardSize.width / kShareCardSize.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: KRadius.lg,
                        border: Border.all(color: KColor.fg.withValues(alpha: 0.12)),
                      ),
                      child: ClipRRect(
                        borderRadius: KRadius.lg,
                        child: FittedBox(
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: WorkoutShareCard(data: widget.data, palette: palette),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Carbon')),
                  ButtonSegment(value: false, label: Text('Paper')),
                ],
                selected: {_dark},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  KHaptics.select();
                  setState(() => _dark = s.first);
                },
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(96, 44)),
                  textStyle: WidgetStatePropertyAll(KText.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? KColor.onInk : KColor.textPrimary,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? KColor.ink : Colors.transparent,
                  ),
                  side: WidgetStatePropertyAll(BorderSide(color: KColor.fg.withValues(alpha: 0.18))),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(_error!, textAlign: TextAlign.center, style: KText.caption.copyWith(color: KColor.danger)),
              ),
            ],
            const SizedBox(height: 14),
            KButton(
              label: 'Share',
              icon: Icons.ios_share_rounded,
              loading: _busy,
              onTap: _busy ? null : _share,
            ),
          ],
        ),
      ),
    );
  }
}
