import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart' show ExerciseExecutionMode;
import '../ui/k_brand_intro.dart' show KShearWordmark, kBrandBone, kBrandEmber, kBrandGraphite;
import '../ui/k_segmented.dart';
import '../ui/k_shear_text.dart';
import '../services/analytics_service.dart';

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

  String get label => bodyweight
      ? (weight > 0 ? 'BW+${_num(weight)} × $reps' : 'BW × $reps')
      : '${_num(weight)} × $reps';
}

/// One set as the generative templates draw it.
class ShareSet {
  final double load;
  final int reps;
  final bool isPr;
  final bool bodyweight;
  final bool warmUp;
  final bool drop;
  const ShareSet({
    required this.load,
    required this.reps,
    this.isPr = false,
    this.bodyweight = false,
    this.warmUp = false,
    this.drop = false,
  });

  double get volume => load * reps;
}

/// An exercise and its sets, in the order they were done.
class ShareExercise {
  final String name;
  final List<ShareSet> sets;
  const ShareExercise({required this.name, required this.sets});

  /// Volume of the sets that count (warm-ups don't).
  double get volume => sets.where((s) => !s.warmUp).fold(0.0, (a, s) => a + s.volume);
  int get workingSets => sets.where((s) => !s.warmUp && !s.drop).length;
  bool get hasPr => sets.any((s) => s.isPr);

  /// Heaviest working set, as a till prints it: "85 KG", "BW", "BW+10".
  String get topLoad {
    final work = sets.where((s) => !s.warmUp && !s.drop);
    final pool = work.isEmpty ? sets : work;
    if (pool.isEmpty) return '';
    final top = pool.map((s) => s.load).reduce(math.max);
    if (pool.first.bodyweight) return top > 0 ? 'BW+${_num(top)}' : 'BW';
    return top > 0 ? '${_num(top)} KG' : '';
  }
}

/// Everything the share cards print, computed once from a saved session.
class WorkoutShareData {
  final DateTime date;
  final String dayName;
  final int durationMinutes;
  final double totalVolume;
  final int sets;
  final int prs;
  final List<ShareLift> topLifts;
  final List<String> muscles;

  /// Every exercise with its sets; empty when built by hand.
  final List<ShareExercise> exercises;

  const WorkoutShareData({
    required this.date,
    required this.dayName,
    required this.durationMinutes,
    required this.totalVolume,
    required this.sets,
    required this.prs,
    required this.topLifts,
    required this.muscles,
    this.exercises = const [],
  });

  int get totalReps =>
      exercises.fold(0, (a, e) => a + e.sets.where((s) => !s.warmUp).fold(0, (b, s) => b + s.reps));

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
      exercises: exercisesOf(session, isPr: isPr),
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
        // A bodyweight lift's weight is the belt / vest load on top.
        weight: bwLift ? (top.externalLoadKg ?? top.weight) : top.weight,
        reps: top.reps,
        e1rm: top.estimatedOneRepMax,
        isPr: pr,
        bodyweight: bwLift,
      ));
    }
    lifts.sort((a, b) => b.e1rm.compareTo(a.e1rm));
    return lifts.take(limit).toList();
  }

  /// Every rep-based set of the session, grouped by exercise. Timed sets are
  /// left out: they have no load or reps to draw.
  static List<ShareExercise> exercisesOf(
    WorkoutSession session, {
    bool Function(String exerciseId, SetEntry set)? isPr,
  }) {
    final out = <ShareExercise>[];
    for (final e in session.entries) {
      if (e.isSkipped) continue;
      final mode = e.exercise.effectiveExecutionMode;
      final bw = mode == ExerciseExecutionMode.bodyweightReps || mode == ExerciseExecutionMode.weightedBodyweight;
      ShareSet of(SetEntry s, {required bool warm, bool drop = false}) => ShareSet(
            load: bw ? (s.externalLoadKg ?? 0) : s.weight,
            reps: s.reps,
            isPr: !warm && !drop && s.isMainWorkingSet && isPr != null && isPr(e.exercise.id, s),
            bodyweight: bw,
            warmUp: warm,
            drop: drop,
          );
      final sets = <ShareSet>[];
      for (final g in e.logicalSets) {
        if (g.mainSet.durationSeconds != null || g.mainSet.reps <= 0) continue;
        sets.add(of(g.mainSet, warm: g.isWarmUp, drop: g.mainSet.setType == SetType.dropSet));
        for (final d in g.subSets) {
          if (d.reps > 0 && d.durationSeconds == null) sets.add(of(d, warm: false, drop: true));
        }
      }
      if (sets.isNotEmpty) out.add(ShareExercise(name: e.exercise.name, sets: sets));
    }
    return out;
  }
}

// ─── Formatting ───────────────────────────────────────────────────────────────

String _num(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}

String _thousands(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _dur(int minutes) => minutes < 1 ? '<1M' : minutes >= 60 ? '${minutes ~/ 60}H ${(minutes % 60).toString().padLeft(2, '0')}M' : '${minutes}M';

/// The session's name as the cards set it.
String _title(WorkoutShareData d) => d.dayName.trim().isEmpty ? 'WORKOUT' : d.dayName.trim().toUpperCase();

String _dots(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

// ─── Options ──────────────────────────────────────────────────────────────────

/// Logical size of the post card; captured at 3x for a 1080 × 1350 (4:5)
/// PNG, the size WhatsApp and Instagram show uncropped.
const Size kShareCardSize = Size(360, 450);

/// The story card: 1080 × 1920 at 3x.
const Size kShareStorySize = Size(360, 640);
const double kShareCardPixelRatio = 3.0;

enum ShareFormat {
  story('Story', kShareStorySize),
  post('Post', kShareCardSize);

  const ShareFormat(this.label, this.size);
  final String label;
  final Size size;
}

enum ShareBackdrop { graphite, paper, photo }

enum ShareTemplate {
  poster('Poster'),
  receipt('Receipt'),
  skyline('Skyline'),
  equivalent('In real terms'),
  sticker('Sticker');

  const ShareTemplate(this.label);
  final String label;

  /// Drawn on nothing (or on a photo picked in the sheet), for laying over
  /// the user's own picture.
  bool get transparent => this == ShareTemplate.sticker;
}

/// The three colours a card is painted with, fixed per backdrop so the image
/// never depends on the app's theme.
class _Ink {
  const _Ink(this.bg, this.fg, this.ember, {this.shadow = false});
  final Color bg, fg, ember;

  /// Text over a photo or nothing at all gets a soft shadow to stay legible.
  final bool shadow;

  Color get muted => fg.withValues(alpha: 0.58);
  Color get faint => fg.withValues(alpha: 0.16);

  static const graphite = _Ink(kBrandGraphite, kBrandBone, kBrandEmber);
  static const paper = _Ink(kBrandBone, kBrandGraphite, Color(0xFFE4502A));
  static const photo = _Ink(Color(0xFF000000), kBrandBone, kBrandEmber, shadow: true);
  static const clear = _Ink(Color(0x00000000), Color(0xFFFFFFFF), kBrandEmber, shadow: true);
}

// ─── Canvas ───────────────────────────────────────────────────────────────────

/// One share image: a [template] laid out for a [format] on a [backdrop].
class ShareCanvas extends StatelessWidget {
  const ShareCanvas({
    super.key,
    required this.data,
    required this.template,
    this.format = ShareFormat.story,
    this.backdrop = ShareBackdrop.graphite,
    this.photo,
  });

  final WorkoutShareData data;
  final ShareTemplate template;
  final ShareFormat format;
  final ShareBackdrop backdrop;

  /// The user's picture for [ShareBackdrop.photo].
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    final usePhoto = backdrop == ShareBackdrop.photo && photo != null;
    final ink = template.transparent
        ? _Ink.clear
        : usePhoto
            ? _Ink.photo
            : backdrop == ShareBackdrop.paper
                ? _Ink.paper
                : _Ink.graphite;
    final s = _S(ink, format);
    final Widget body = switch (template) {
      ShareTemplate.poster => _Poster(data, s),
      ShareTemplate.receipt => _Receipt(data, s),
      ShareTemplate.skyline => _Skyline(data, s),
      ShareTemplate.equivalent => _Equivalent(data, s),
      ShareTemplate.sticker => _Sticker(data, s),
    };
    return SizedBox.fromSize(
      size: format.size,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!template.transparent || usePhoto) ...[
              if (usePhoto) ...[
                Image(image: photo!, fit: BoxFit.cover, gaplessPlayback: true),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x8C000000), Color(0x33000000), Color(0x59000000), Color(0xD9000000)],
                      stops: [0, 0.3, 0.55, 1],
                    ),
                  ),
                ),
              ] else
                CustomPaint(painter: _GrainPainter(ink.bg, ink.fg)),
            ],
            Padding(
              padding: format == ShareFormat.story
                  ? const EdgeInsets.fromLTRB(26, 58, 26, 62)
                  : const EdgeInsets.fromLTRB(24, 24, 24, 22),
              child: body,
            ),
          ],
        ),
      ),
    );
  }
}

/// Type and colour for one card.
class _S {
  _S(this.ink, this.format);
  final _Ink ink;
  final ShareFormat format;

  bool get tall => format == ShareFormat.story;

  List<Shadow>? get _shadows => ink.shadow
      ? const [Shadow(color: Color(0x73000000), blurRadius: 14), Shadow(color: Color(0x40000000), blurRadius: 3)]
      : null;

  TextStyle brand(double size, {Color? color, double spacing = -0.02, double height = 0.92}) => TextStyle(
        fontFamily: KText.brandFace,
        fontWeight: FontWeight.w800,
        fontSize: size,
        height: height,
        letterSpacing: size * spacing,
        color: color ?? ink.fg,
        shadows: _shadows,
        decoration: TextDecoration.none,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle text(double size,
          {Color? color, FontWeight weight = FontWeight.w600, double spacing = 0, double height = 1.15}) =>
      TextStyle(
        fontFamily: KText.family,
        fontWeight: weight,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        color: color ?? ink.fg,
        shadows: _shadows,
        decoration: TextDecoration.none,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Small uppercase label: "SETS", "MOVED TODAY".
  TextStyle label({Color? color}) => text(9.5, color: color ?? ink.muted, weight: FontWeight.w700, spacing: 1.6);

  Widget wordmark(double size) => KShearWordmark(fontSize: size, ink: ink.fg, ember: ink.ember);

  Widget rule({double h = 1}) => Container(height: h, color: h > 1 ? ink.fg : ink.faint);
}

/// Wordmark left, a small line of type right.
Widget _masthead(_S s, String right) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        s.wordmark(18),
        const Spacer(),
        Text(right, style: s.label(color: s.ink.muted)),
      ],
    );

// ─── 1. Poster ────────────────────────────────────────────────────────────────

/// The session name cut like the logo, the volume huge, the best lifts.
class _Poster extends StatelessWidget {
  const _Poster(this.d, this.s);
  final WorkoutShareData d;
  final _S s;

  @override
  Widget build(BuildContext context) {
    final ink = s.ink;
    final title = _title(d);
    return LayoutBuilder(builder: (context, c) {
      final size = KShearText.fit(title, s.brand(10), c.maxWidth,
          maxLines: 2, min: 26, max: s.tall ? 86 : 54, ember: true);
      Widget stat(String v, String l, {bool hot = false}) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(v, style: s.brand(s.tall ? 26 : 22, color: hot ? ink.ember : ink.fg, height: 1)),
              const SizedBox(height: 4),
              Text(l, style: s.label()),
            ],
          );
      final lifts = d.topLifts.take(s.tall ? 3 : 2).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _masthead(s, _dots(d.date)),
          const Spacer(flex: 3),
          Text('SESSION LOG', style: s.label(color: ink.ember)),
          SizedBox(height: s.tall ? 12 : 8),
          KShearText(title, style: s.brand(size), ember: ink.ember, maxLines: 2),
          SizedBox(height: s.tall ? 26 : 14),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: _thousands(d.totalVolume), style: s.brand(s.tall ? 58 : 40, height: 1)),
              TextSpan(text: ' KG', style: s.brand(s.tall ? 20 : 15, color: ink.muted, height: 1)),
            ]),
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          Text('MOVED TODAY', style: s.label()),
          SizedBox(height: s.tall ? 22 : 12),
          s.rule(h: 1.5),
          SizedBox(height: s.tall ? 14 : 10),
          Row(
            children: [
              Expanded(child: stat('${d.sets}', d.sets == 1 ? 'SET' : 'SETS')),
              Expanded(child: stat(_dur(d.durationMinutes), 'TIME')),
              Expanded(child: stat('${d.prs}', d.prs == 1 ? 'RECORD' : 'RECORDS', hot: d.prs > 0)),
            ],
          ),
          SizedBox(height: s.tall ? 14 : 10),
          s.rule(),
          if (lifts.isNotEmpty) ...[
            SizedBox(height: s.tall ? 12 : 8),
            for (final l in lifts)
              Padding(
                padding: EdgeInsets.symmetric(vertical: s.tall ? 4 : 2.5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false,
                          style: s.text(s.tall ? 13.5 : 12.5, weight: FontWeight.w600)),
                    ),
                    if (l.isPr) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: ink.ember, borderRadius: BorderRadius.circular(3)),
                        child: Text('PR',
                            style: s.text(8.5, color: kBrandGraphite, weight: FontWeight.w800, spacing: 0.8)
                                .copyWith(shadows: const [])),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(l.label, style: s.text(s.tall ? 14 : 13, weight: FontWeight.w800, spacing: -0.2)),
                  ],
                ),
              ),
          ],
          const Spacer(flex: 2),
          if (d.muscles.isNotEmpty)
            Text(d.muscles.map((m) => m.toUpperCase()).join('  /  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: s.label()),
        ],
      );
    });
  }
}

// ─── 2. Receipt ───────────────────────────────────────────────────────────────

/// A thermal till receipt for the session, itemised by exercise.
class _Receipt extends StatelessWidget {
  const _Receipt(this.d, this.s);
  final WorkoutShareData d;
  final _S s;

  static const _paper = Color(0xFFFBFAF6);
  static const _ink = Color(0xFF1A1A1B);
  static const _quips = [
    'PAID IN SWEAT. NO REFUNDS.',
    'ALL SALES FINAL. SO ARE THOSE REPS.',
    'KEEP THIS FOR YOUR RECORDS. KYNO DID.',
    'NO EXCHANGES ON SORENESS.',
    'GRAVITY HAS BEEN BILLED.',
  ];

  TextStyle _m(double size, {Color color = _ink, FontWeight w = FontWeight.w500, double spacing = 0}) => TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['RobotoMono', 'Courier'],
        fontSize: size,
        fontWeight: w,
        color: color,
        letterSpacing: spacing,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  @override
  Widget build(BuildContext context) {
    final items = d.exercises.isNotEmpty
        ? d.exercises
        : [
            for (final l in d.topLifts)
              ShareExercise(name: l.name, sets: [ShareSet(load: l.weight, reps: l.reps, isPr: l.isPr, bodyweight: l.bodyweight)]),
          ];
    final cap = s.tall ? 7 : 3;
    final shown = items.take(cap).toList();
    final more = items.length - shown.length;
    final order = ((d.date.year * 372 + d.date.month * 31 + d.date.day) * 7919) % 100000;
    final quip = _quips[(d.date.day + d.date.month) % _quips.length];
    final hh = d.date.hour.toString().padLeft(2, '0');
    final mm = d.date.minute.toString().padLeft(2, '0');
    final small = s.tall ? 10.5 : 9.5;
    final dash = Text('-' * 40, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: _m(small, color: const Color(0x991A1A1B)));
    Widget line(String l, String r, {bool bold = false, Color color = _ink, double? size}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false,
                  style: _m(size ?? small, w: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
            ),
            const SizedBox(width: 8),
            Text(r, style: _m(size ?? small, w: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
          ],
        );

    return Center(
      child: Transform.rotate(
        angle: -0.018,
        child: CustomPaint(
          painter: _ReceiptPainter(_paper, shadow: s.ink.bg != _Ink.paper.bg || s.ink.shadow),
          child: SizedBox(
            width: s.tall ? 278 : 252,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, s.tall ? 26 : 18, 18, s.tall ? 26 : 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: KShearWordmark(fontSize: s.tall ? 24 : 19, ink: _ink, ember: kBrandEmber)),
                  const SizedBox(height: 6),
                  Text('IRON GOODS · EST. TODAY', textAlign: TextAlign.center, style: _m(small - 1, spacing: 1.2)),
                  Text('CASHIER: KYNO   TILL 01', textAlign: TextAlign.center, style: _m(small - 1, spacing: 1.2)),
                  const SizedBox(height: 6),
                  line('${d.date.day} ${_months[d.date.month - 1]} ${d.date.year}  $hh:$mm', 'NO. ${order.toString().padLeft(5, '0')}'),
                  dash,
                  Text(d.dayName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: _m(small + 1.5, w: FontWeight.w800, spacing: 0.6)),
                  const SizedBox(height: 4),
                  for (final e in shown) ...[
                    line(e.name.toUpperCase(), '${_thousands(e.volume)} KG', bold: true),
                    line(
                      '  ${e.workingSets} × ${e.sets.where((x) => !x.warmUp && !x.drop).map((x) => x.reps).toSet().join('/')}'
                          '${e.hasPr ? '   * PR' : ''}',
                      e.topLoad.isEmpty ? '' : '@ ${e.topLoad}',
                      color: e.hasPr ? const Color(0xFFD9481F) : const Color(0x991A1A1B),
                    ),
                  ],
                  if (more > 0) line('  + $more MORE', ''),
                  dash,
                  line('SETS', '${d.sets}'),
                  line('TIME', _dur(d.durationMinutes)),
                  line('RECORDS', '${d.prs}'),
                  const SizedBox(height: 4),
                  line('TOTAL', '${_thousands(d.totalVolume)} KG', bold: true, size: small + 3),
                  dash,
                  const SizedBox(height: 6),
                  SizedBox(height: s.tall ? 38 : 28, child: CustomPaint(painter: _BarcodePainter(d, _ink))),
                  const SizedBox(height: 8),
                  Text(quip, textAlign: TextAlign.center, style: _m(small - 0.5, w: FontWeight.w700, spacing: 0.4)),
                  Text('THANK YOU FOR LIFTING', textAlign: TextAlign.center, style: _m(small - 1.5, spacing: 1.4, color: const Color(0x991A1A1B))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paper with torn zigzag ends and a soft drop shadow.
class _ReceiptPainter extends CustomPainter {
  _ReceiptPainter(this.paper, {required this.shadow});
  final Color paper;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    const t = 6.0;
    final p = Path()..moveTo(0, t);
    final n = (size.width / (t * 2)).ceil();
    final step = size.width / n;
    for (var i = 0; i < n; i++) {
      p.lineTo(step * i + step / 2, 0);
      p.lineTo(step * (i + 1), t);
    }
    p.lineTo(size.width, size.height - t);
    for (var i = n; i > 0; i--) {
      p.lineTo(step * i - step / 2, size.height);
      p.lineTo(step * (i - 1), size.height - t);
    }
    p.close();
    if (shadow) canvas.drawShadow(p, const Color(0xFF000000), 10, false);
    canvas.drawPath(p, Paint()..color = paper);
  }

  @override
  bool shouldRepaint(_ReceiptPainter old) => old.paper != paper || old.shadow != shadow;
}

/// A barcode spelled from the session: each set's reps set a bar's width.
class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.d, this.ink);
  final WorkoutShareData d;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final seq = <int>[
      for (final e in d.exercises)
        for (final s in e.sets) s.reps,
      d.sets,
      d.durationMinutes,
      d.totalVolume.round(),
    ];
    final rnd = math.Random(d.date.millisecondsSinceEpoch ~/ 86400000);
    final widths = <double>[];
    var i = 0;
    var total = 0.0;
    while (total < size.width) {
      final v = seq.isEmpty ? rnd.nextInt(9) : seq[i % seq.length] + rnd.nextInt(3);
      final w = 0.8 + (v % 4) * 0.75;
      widths.add(w);
      total += w * 1.9;
      i++;
    }
    final paint = Paint()..color = ink;
    var x = 0.0;
    for (var k = 0; k < widths.length; k++) {
      if (x + widths[k] > size.width) break;
      if (k.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, widths[k], size.height), paint);
      x += widths[k] * (k.isEven ? 1 : 1.8) + 0.9;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.d != d;
}

// ─── 3. Skyline ───────────────────────────────────────────────────────────────

/// Generative: every set a bar, its height the set's volume. Records burn
/// ember, warm-ups sit faint. No two sessions draw the same skyline.
class _Skyline extends StatelessWidget {
  const _Skyline(this.d, this.s);
  final WorkoutShareData d;
  final _S s;

  @override
  Widget build(BuildContext context) {
    final ink = s.ink;
    final ex = d.exercises.isNotEmpty
        ? d.exercises
        : [
            for (final l in d.topLifts)
              ShareExercise(name: l.name, sets: [
                for (var i = 0; i < 3; i++) ShareSet(load: l.weight, reps: l.reps, isPr: l.isPr && i == 2),
              ]),
          ];
    final key = ex.take(s.tall ? 8 : 4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _masthead(s, _dots(d.date)),
        SizedBox(height: s.tall ? 30 : 16),
        LayoutBuilder(
          builder: (context, c) => KShearText(_title(d),
              style: s.brand(KShearText.fit(_title(d), s.brand(10), c.maxWidth,
                  maxLines: 1, min: 14, max: s.tall ? 30 : 22, ember: true)),
              ember: ink.ember,
              maxLines: 1),
        ),
        const SizedBox(height: 6),
        Text('EVERY SET, TO SCALE', style: s.label()),
        SizedBox(height: s.tall ? 22 : 12),
        Expanded(child: CustomPaint(size: Size.infinite, painter: _SkylinePainter(ex, ink))),
        const SizedBox(height: 8),
        s.rule(h: 1.5),
        SizedBox(height: s.tall ? 14 : 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < key.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${(i + 1).toString().padLeft(2, '0')}  ', style: s.text(10, color: key[i].hasPr ? ink.ember : ink.muted, weight: FontWeight.w700)),
                          TextSpan(text: key[i].name.toUpperCase(), style: s.text(10, weight: FontWeight.w600, spacing: 0.4)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (ex.length > key.length) Text('+ ${ex.length - key.length} MORE', style: s.label()),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_thousands(d.totalVolume), style: s.brand(s.tall ? 40 : 30, height: 1)),
                const SizedBox(height: 4),
                Text('KG  ·  ${d.sets} SETS  ·  ${_dur(d.durationMinutes)}', style: s.label()),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _SkylinePainter extends CustomPainter {
  _SkylinePainter(this.ex, this.ink);
  final List<ShareExercise> ex;
  final _Ink ink;

  /// A set's height: its volume, or its reps for unloaded bodyweight work,
  /// scaled to sit with loaded sets.
  static double _h(ShareSet s, double perRep) => s.volume > 0 ? s.volume : s.reps * perRep;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ex.fold<int>(0, (a, e) => a + e.sets.length);
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    final loaded = [for (final e in ex) for (final s in e.sets) if (s.volume > 0) s.volume / s.reps];
    final perRep = loaded.isEmpty ? 20.0 : loaded.reduce((a, b) => a + b) / loaded.length;
    final top = ex.expand((e) => e.sets).map((s) => _h(s, perRep)).fold<double>(0, math.max);
    final groupGap = 3.0;
    final slots = n * 1.0 + (ex.length - 1) * groupGap;
    final unit = size.width / slots;
    final barW = (unit * 0.72).clamp(1.5, 16.0);
    final base = size.height - 16;
    final avail = base - 10;
    // Ground line.
    canvas.drawRect(Rect.fromLTWH(0, base, size.width, 1), Paint()..color = ink.faint);
    var x = 0.0;
    for (var g = 0; g < ex.length; g++) {
      final e = ex[g];
      final gx = x;
      for (final s in e.sets) {
        final h = math.max(3.0, avail * (top <= 0 ? 0.1 : _h(s, perRep) / top));
        final r = Rect.fromLTWH(x + (unit - barW) / 2, base - h, barW, h);
        final color = s.isPr
            ? ink.ember
            : s.warmUp
                ? ink.fg.withValues(alpha: 0.18)
                : s.drop
                    ? ink.fg.withValues(alpha: 0.5)
                    : ink.fg;
        canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: Radius.circular(barW * 0.25), topRight: Radius.circular(barW * 0.25)),
            Paint()..color = color);
        if (s.isPr) {
          canvas.drawRect(Rect.fromLTWH(r.left, r.top - 6, barW, 2), Paint()..color = ink.ember);
        }
        x += unit;
      }
      // Group number under its bars.
      final tp = TextPainter(
        text: TextSpan(
          text: (g + 1).toString().padLeft(2, '0'),
          style: TextStyle(fontFamily: KText.family, fontSize: 8.5, fontWeight: FontWeight.w700, color: ink.muted, letterSpacing: 0.6),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = (gx + x) / 2 - tp.width / 2;
      tp.paint(canvas, Offset(cx.clamp(0, size.width - tp.width), base + 5));
      tp.dispose();
      x += unit * groupGap;
    }
  }

  @override
  bool shouldRepaint(_SkylinePainter old) => old.ex != ex || old.ink != ink;
}

// ─── 4. In real terms ─────────────────────────────────────────────────────────

/// What the volume weighs in things people know.
class ShareEquivalent {
  const ShareEquivalent(this.one, this.many, this.kg, this.quip);
  final String one, many;
  final double kg;
  final String quip;

  static const all = [
    ShareEquivalent('LPG CYLINDER', 'LPG CYLINDERS', 29.5, 'Dinner for a year, lifted.'),
    ShareEquivalent('BAJAJ CHETAK', 'BAJAJ CHETAKS', 105, 'Kick start not required.'),
    ShareEquivalent('ROYAL ENFIELD', 'ROYAL ENFIELDS', 195, 'Thump thump thump.'),
    ShareEquivalent('AUTO RICKSHAW', 'AUTO RICKSHAWS', 360, 'Meter down. No haggling.'),
    ShareEquivalent('GRAND PIANO', 'GRAND PIANOS', 400, 'Moved without a single scratch.'),
    ShareEquivalent('DESI COW', 'DESI COWS', 450, 'Gently. They are sacred.'),
    ShareEquivalent('MARUTI 800', 'MARUTI 800 CARS', 650, 'The whole family fits in there.'),
    ShareEquivalent('ELEPHANT', 'ELEPHANTS', 4000, 'Gravity filed a complaint.'),
  ];

  /// A thing whose count comes out between 3 and 40, chosen by the date so a
  /// session always prints the same one. Null under 88 kg.
  static (ShareEquivalent, int)? pick(double volume, DateTime date) {
    final fit = [
      for (final e in all)
        if (volume / e.kg >= 3 && volume / e.kg <= 40) e,
    ];
    if (fit.isEmpty) {
      if (volume < all.first.kg * 3) return null;
      final e = all.last;
      return (e, (volume / e.kg).round());
    }
    final e = fit[(date.year + date.month * 7 + date.day * 13) % fit.length];
    return (e, (volume / e.kg).round());
  }
}

class _Equivalent extends StatelessWidget {
  const _Equivalent(this.d, this.s);
  final WorkoutShareData d;
  final _S s;

  @override
  Widget build(BuildContext context) {
    final ink = s.ink;
    final pick = ShareEquivalent.pick(d.totalVolume, d.date);
    final reps = d.totalReps;
    final count = pick?.$2 ?? reps;
    final noun = pick == null ? (count == 1 ? 'REP' : 'REPS') : (count == 1 ? pick.$1.one : pick.$1.many);
    final quip = pick?.$1.quip ?? 'Bodyweight only. Gravity still lost.';
    return LayoutBuilder(builder: (context, c) {
      final nounSize = KShearText.fit(noun, s.brand(10), c.maxWidth, maxLines: 2, min: 22, max: s.tall ? 52 : 36, ember: true);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _masthead(s, _dots(d.date)),
          const Spacer(flex: 2),
          Text(pick == null ? 'YOU DID' : 'YOU MOVED', style: s.label()),
          const SizedBox(height: 6),
          Text(pick == null ? '${d.sets} SETS' : '${_thousands(d.totalVolume)} KG',
              style: s.brand(s.tall ? 40 : 30, color: ink.muted, height: 1)),
          SizedBox(height: s.tall ? 26 : 14),
          Text(pick == null ? 'FOR A TOTAL OF' : "THAT'S ABOUT", style: s.label()),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('$count', style: s.brand(s.tall ? 150 : 96, height: 0.98, spacing: -0.045)),
          ),
          KShearText(noun, style: s.brand(nounSize), ember: ink.ember, maxLines: 2),
          SizedBox(height: s.tall ? 24 : 12),
          if (pick != null) _Tally(count: count, ink: ink, cell: s.tall ? 11 : 8),
          const Spacer(flex: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text.rich(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  TextSpan(children: [
                    TextSpan(text: 'KYNO  ', style: s.text(10, color: ink.ember, weight: FontWeight.w800, spacing: 1.4)),
                    TextSpan(text: quip, style: s.text(s.tall ? 13 : 11.5, weight: FontWeight.w500)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.36),
                child: Text(d.dayName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: s.label()),
              ),
            ],
          ),
        ],
      );
    });
  }
}

/// A tally of [count] small blocks, the last one ember.
class _Tally extends StatelessWidget {
  const _Tally({required this.count, required this.ink, required this.cell});
  final int count;
  final _Ink ink;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final n = count.clamp(1, 40);
    return Wrap(
      spacing: cell * 0.45,
      runSpacing: cell * 0.45,
      children: [
        for (var i = 0; i < n; i++)
          Container(
            width: cell,
            height: cell,
            decoration: BoxDecoration(
              color: i == n - 1 ? ink.ember : ink.fg,
              borderRadius: BorderRadius.circular(cell * 0.18),
            ),
          ),
      ],
    );
  }
}

// ─── 5. Sticker ───────────────────────────────────────────────────────────────

/// Transparent: the stats alone, for laying over your own story photo.
class _Sticker extends StatelessWidget {
  const _Sticker(this.d, this.s);
  final WorkoutShareData d;
  final _S s;

  /// One big line when the name allows it; two lines rather than tiny type.
  double _stickerTitleSize(String title, double width) {
    final max = s.tall ? 46.0 : 34.0;
    final one = KShearText.fit(title, s.brand(10), width, maxLines: 1, min: 12, max: max, ember: true);
    if (one >= max * 0.7) return one;
    return KShearText.fit(title, s.brand(10), width, maxLines: 2, min: 20, max: max, ember: true);
  }

  @override
  Widget build(BuildContext context) {
    final ink = s.ink;
    final top = d.topLifts.isEmpty ? null : d.topLifts.first;
    Widget stat(String v, String l) => Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v, style: s.brand(s.tall ? 30 : 24, height: 1)),
                const SizedBox(height: 4),
                Text(l, style: s.label(color: ink.fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
        );
    return LayoutBuilder(builder: (context, c) => Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: c.maxWidth,
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KShearWordmark(fontSize: s.tall ? 30 : 24, ink: ink.fg, ember: ink.ember),
          SizedBox(height: s.tall ? 18 : 12),
          KShearText(_title(d),
              style: s.brand(_stickerTitleSize(_title(d), c.maxWidth - 8)),
              ember: ink.ember,
              textAlign: TextAlign.center,
              maxLines: 2),
          SizedBox(height: s.tall ? 22 : 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              stat(_thousands(d.totalVolume), 'KG'),
              stat('${d.sets}', 'SETS'),
              stat(_dur(d.durationMinutes), 'TIME'),
            ],
          ),
          if (top != null) ...[
            SizedBox(height: s.tall ? 20 : 14),
            Text.rich(
              TextSpan(children: [
                if (top.isPr) TextSpan(text: 'PR  ', style: s.text(11, color: ink.ember, weight: FontWeight.w800, spacing: 1.2)),
                TextSpan(text: '${top.name.toUpperCase()}  ', style: s.text(11, weight: FontWeight.w700, spacing: 0.8)),
                TextSpan(text: top.label, style: s.text(13, weight: FontWeight.w800)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: s.tall ? 16 : 10),
          Text(_dots(d.date), style: s.label(color: ink.fg.withValues(alpha: 0.75))),
        ],
          ),
        ),
      ),
    ));
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

/// Flat ground with a fixed film grain. Seeded, so the same card always
/// exports identically.
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.base, this.grain);
  final Color base, grain;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final rnd = math.Random(7);
    final dark = base.computeLuminance() < 0.5;
    final pts = <Offset>[
      for (var i = 0; i < (size.width * size.height / 60).round(); i++)
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = grain.withValues(alpha: dark ? 0.06 : 0.05)
        ..strokeWidth = 0.6,
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.base != base || old.grain != grain;
}

// ─── Legacy card ──────────────────────────────────────────────────────────────

/// The post-sized poster on Graphite or Paper, picked by [palette].
class WorkoutShareCard extends StatelessWidget {
  final WorkoutShareData data;
  final KPalette palette;
  const WorkoutShareCard({super.key, required this.data, required this.palette});

  @override
  Widget build(BuildContext context) => ShareCanvas(
        data: data,
        template: ShareTemplate.poster,
        format: ShareFormat.post,
        backdrop: palette.isDark ? ShareBackdrop.graphite : ShareBackdrop.paper,
      );
}

// ─── Share sheet ──────────────────────────────────────────────────────────────

/// Swipe through the templates, pick a format and a backdrop, share a PNG.
Future<void> showWorkoutShareSheet(BuildContext context, WorkoutShareData data) {
  AnalyticsService.instance.track('share_opened');
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
  final _keys = {for (final t in ShareTemplate.values) t: GlobalKey()};
  final _pages = PageController(viewportFraction: 0.78);
  ShareTemplate _template = ShareTemplate.poster;
  ShareFormat _format = ShareFormat.story;
  late ShareBackdrop _backdrop = KColor.isDark ? ShareBackdrop.graphite : ShareBackdrop.paper;
  Uint8List? _photoBytes;
  ImageProvider? _photo;

  /// The sticker's own backdrop choice: clear, or the picked photo.
  bool _stickerOnPhoto = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showKSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: KSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const KSheetHeader('Backdrop photo', subtitle: 'Your gym, your mirror, your view'),
              _SourceOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take photo',
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              _SourceOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from gallery',
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final f = await ImagePicker().pickImage(source: source, imageQuality: 88, maxWidth: 1440);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _error = null;
        _photoBytes = bytes;
        _photo = MemoryImage(bytes);
        if (_template.transparent) {
          _stickerOnPhoto = true;
        } else {
          _backdrop = ShareBackdrop.photo;
        }
      });
    } catch (e) {
      debugPrint('[WORKOUT_SHARE] photo failed: $e');
      if (mounted) setState(() => _error = 'Couldn\'t open that photo.');
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    KHaptics.commit();
    try {
      final boundary = _keys[_template]!.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('card not painted');
      final image = await boundary.toImage(pixelRatio: kShareCardPixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('encode failed');
      final d = widget.data.date;
      final name = 'kynetix-workout-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.png';
      final shared = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        fileNameOverrides: [name],
        text: '${widget.data.dayName} done. Logged on Kynetix.',
      ));
      if (shared.status != ShareResultStatus.dismissed) {
        AnalyticsService.instance.track('share_exported', {'template': _template.name.toLowerCase(), 'format': _format.name.toLowerCase(), 'backdrop': _backdrop.name.toLowerCase()});
      }
    } catch (e) {
      debugPrint('[WORKOUT_SHARE] failed: $e');
      if (mounted) setState(() => _error = 'Couldn\'t make the image. Try again in a moment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Screen reader tap on a neighbouring preview: bring it to the centre.
  void _showTemplate(int i) {
    final d = KMotion.of(context, KMotion.standard);
    if (d == Duration.zero) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i, duration: d, curve: KMotion.easeOut);
    }
  }

  Widget _page(ShareTemplate t) {
    final size = _format.size;
    final card = RepaintBoundary(
      key: _keys[t],
      child: ShareCanvas(
        data: widget.data,
        template: t,
        format: _format,
        backdrop: t.transparent
            ? (_stickerOnPhoto && _photo != null ? ShareBackdrop.photo : ShareBackdrop.graphite)
            : _photo == null && _backdrop == ShareBackdrop.photo
                ? ShareBackdrop.graphite
                : _backdrop,
        photo: _photo,
      ),
    );
    return Center(
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: KRadius.lg,
            border: Border.all(color: KColor.fg.withValues(alpha: 0.12)),
          ),
          child: ClipRRect(
            borderRadius: KRadius.lg,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (t.transparent && !(_stickerOnPhoto && _photo != null))
                  CustomPaint(painter: _CheckerPainter(KColor.isDark)),
                FittedBox(child: SizedBox.fromSize(size: size, child: card)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _changePhoto() => Align(
        child: Semantics(
          button: true,
          label: 'Change backdrop photo',
          onTap: _pickPhoto,
          excludeSemantics: true,
          child: TextButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Change photo'),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final previewH = (h * 0.5).clamp(300.0, 520.0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KSheetHeader('Share your session', subtitle: 'Swipe for a style. Made for your story.'),
            const SizedBox(height: 12),
            Semantics(
              label: 'Share card preview. '
                  '${widget.data.dayName}, ${widget.data.sets} sets, ${widget.data.totalVolume.round()} kilograms.',
              child: SizedBox(
                height: previewH,
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) {
                    KHaptics.select();
                    setState(() => _template = ShareTemplate.values[i]);
                  },
                  children: [
                    for (final (i, t) in ShareTemplate.values.indexed)
                      // Each preview speaks as one node ("Style 2 of 5,
                      // Receipt"); the card's own text would read as noise.
                      Semantics(
                        container: true,
                        selected: t == _template,
                        label: 'Style ${i + 1} of ${ShareTemplate.values.length}, '
                            '${t.transparent ? '${t.label}, transparent' : t.label}',
                        onTap: t == _template ? null : () => _showTemplate(i),
                        child: ExcludeSemantics(
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: _page(t)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Style ${_template.index + 1} of ${ShareTemplate.values.length}',
              excludeSemantics: true,
              child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final t in ShareTemplate.values)
                  AnimatedContainer(
                    duration: KMotion.quick,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: t == _template ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: t == _template ? KColor.ember : KColor.fg.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _template.transparent
                  ? (_stickerOnPhoto && _photo != null
                      ? 'Sticker on your photo'
                      : 'Sticker · clear. Chats like WhatsApp show clear as black, so add a photo')
                  : _template.label,
              textAlign: TextAlign.center,
              style: KText.caption.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KSegmented<ShareFormat>(
                    dense: true,
                    segments: [
                      for (final f in ShareFormat.values)
                        KSegment(f, f.label, semanticLabel: switch (f) {
                          ShareFormat.story => 'Story size, tall',
                          ShareFormat.post => 'Post size, 4 by 5',
                        }),
                    ],
                    value: _format,
                    onChanged: (f) => setState(() => _format = f),
                  ),
                  if (_template.transparent) ...[
                    const SizedBox(height: 10),
                    KSegmented<bool>(
                      dense: true,
                      segments: [
                        const KSegment(false, 'Clear', semanticLabel: 'Clear backdrop'),
                        KSegment(
                          true,
                          'Photo',
                          icon: Icons.photo_outlined,
                          semanticLabel: _photoBytes == null ? 'Photo backdrop, choose a photo' : 'Photo backdrop',
                        ),
                      ],
                      value: _stickerOnPhoto && _photo != null,
                      onChanged: (v) {
                        if (v && _photoBytes == null) {
                          _pickPhoto();
                          return;
                        }
                        setState(() => _stickerOnPhoto = v);
                      },
                    ),
                    if (_stickerOnPhoto && _photo != null) _changePhoto(),
                  ],
                  if (!_template.transparent) ...[
                    const SizedBox(height: 10),
                    KSegmented<ShareBackdrop>(
                      dense: true,
                      segments: [
                        const KSegment(ShareBackdrop.graphite, 'Graphite', semanticLabel: 'Graphite backdrop'),
                        const KSegment(ShareBackdrop.paper, 'Paper', semanticLabel: 'Paper backdrop'),
                        KSegment(
                          ShareBackdrop.photo,
                          'Photo',
                          icon: Icons.photo_outlined,
                          semanticLabel: _photoBytes == null ? 'Photo backdrop, choose a photo' : 'Photo backdrop',
                        ),
                      ],
                      value: _photo == null && _backdrop == ShareBackdrop.photo ? ShareBackdrop.graphite : _backdrop,
                      onChanged: (b) {
                        if (b == ShareBackdrop.photo && _photoBytes == null) {
                          _pickPhoto();
                          return;
                        }
                        setState(() => _backdrop = b);
                      },
                    ),
                    if (_backdrop == ShareBackdrop.photo && _photo != null) _changePhoto(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: Text(_error!, textAlign: TextAlign.center, style: KText.caption.copyWith(color: KColor.danger)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Semantics(
                    container: true,
                    button: true,
                    enabled: !_busy,
                    label: _busy
                        ? 'Making your image'
                        : 'Share the ${_template.label} card as an image',
                    onTap: _busy ? null : _share,
                    excludeSemantics: true,
                    child: KButton(
                      label: 'Share',
                      icon: Icons.ios_share_rounded,
                      loading: _busy,
                      onTap: _busy ? null : _share,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the photo source picker.
class _SourceOption extends StatelessWidget {
  const _SourceOption({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.p, vertical: KSpacing.md),
            child: Row(
              children: [
                Icon(icon, size: 22, color: KColor.textPrimary),
                const SizedBox(width: KSpacing.lg),
                Expanded(child: Text(label, style: KText.bodyMedium.copyWith(color: KColor.textPrimary))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The transparency grid behind the sticker preview (not in the export).
class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF2A2A2C) : const Color(0xFFB9B8B2));
    final p = Paint()..color = dark ? const Color(0xFF353538) : const Color(0xFFA9A8A2);
    const c = 12.0;
    for (var y = 0; y * c < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * c < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * c, y * c, c, c), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.dark != dark;
}
