import 'package:flutter/material.dart';

import '../config/app_theme.dart';

enum KMedalState { earned, progress, locked }

/// The glyph for a badge id, from the shared icon language (never emoji).
IconData badgeIcon(String id) => switch (id) {
      'logged_first_day' => KIcons.baseline,
      'logged_7_days' || 'logged_30_days' || 'logged_100_days' => KIcons.calendar,
      'protein_target_3_row' || 'protein_target_7_row' || 'pb_protein_day' => KIcons.protein,
      'cal_adherence_week' => KIcons.target,
      'perfect_week' => Icons.check_circle_outline,
      'gym_3_row' || 'gym_30_total' => KIcons.train,
      'gym_100_total' => KIcons.record,
      'quality_score_80_week' => KIcons.plate,
      'first_monthly_report' => Icons.insert_chart_outlined,
      'improvement_month' => Icons.trending_up,
      _ => KIcons.record,
    };

/// Achievement medallion: one outlined glyph in a ring. Earned is a solid ink
/// disc, in progress a hairline ring, locked a faint ring with a muted glyph.
/// [progress] (0 to 1) draws an ember arc round the ring of an in-progress
/// medal, the same lap language as the fuel rings.
class KBadgeMedal extends StatelessWidget {
  const KBadgeMedal({super.key, required this.id, required this.size, required this.state, this.progress});
  final String id;
  final double size;
  final KMedalState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final earned = state == KMedalState.earned;
    final locked = state == KMedalState.locked;
    final medal = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: earned ? KShade.convex(KColor.ink) : null,
        boxShadow: earned ? KShadow.lifted : null,
        border: earned
            ? null
            : Border.all(
                color: KColor.fg.withValues(alpha: locked ? 0.12 : 0.28),
                width: 1.2,
              ),
      ),
      alignment: Alignment.center,
      child: Icon(
        badgeIcon(id),
        size: size * 0.46,
        color: earned ? KColor.onInk : (locked ? KColor.textMuted : KColor.textPrimary),
      ),
    );
    final p = progress;
    return ExcludeSemantics(
      child: p == null || earned
          ? medal
          : CustomPaint(
              foregroundPainter: _MedalArc(p.clamp(0.0, 1.0), KColor.ember),
              child: medal,
            ),
    );
  }
}

class _MedalArc extends CustomPainter {
  _MedalArc(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (value <= 0) return;
    final r = Rect.fromLTWH(0.6, 0.6, size.width - 1.2, size.height - 1.2);
    canvas.drawArc(
      r,
      -1.5708,
      6.28318 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_MedalArc old) => old.value != value || old.color != color;
}
