import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../config/app_theme.dart';

// ─── KSegmented ───────────────────────────────────────────────────────────────
// The one segmented control. A quiet track (ink at ~4% with a hairline) holds
// a single ink thumb that slides to the chosen segment on a critically damped
// spring. The motion is interruptible: a new value mid-slide retargets from
// wherever the thumb is, carrying its velocity, so it never jumps.
//
// Moment declaration: segment change
//   trigger: tapping a segment other than the selected one
//   change:  the thumb slides; each label's colour follows the thumb, so a
//            label turns onInk exactly as the thumb passes under it
//   duration role: spring, ~350 ms to settle
//   haptic:  KHaptics.select(), once, on the tap that changes the value
//   reduced motion: the thumb jumps; colours still swap
//
// State is never carried by colour alone: every segment speaks its selected
// state through Semantics, and a segment may swap to a filled [selectedIcon].
// The ticker only runs while the thumb moves.

/// One option in a [KSegmented].
@immutable
class KSegment<T> {
  const KSegment(
    this.value,
    this.label, {
    this.icon,
    this.selectedIcon,
    this.semanticLabel,
  });

  final T value;
  final String label;

  /// Optional leading icon; [selectedIcon] replaces it while selected.
  final IconData? icon;
  final IconData? selectedIcon;

  /// What a screen reader says for the segment. Defaults to [label].
  final String? semanticLabel;
}

class KSegmented<T> extends StatefulWidget {
  const KSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height,
    this.dense = false,
    this.segmentWidth,
    this.position,
  });

  final List<KSegment<T>> segments;
  final T value;

  /// Called with the tapped value when it differs from [value]. The thumb
  /// moves when the parent rebuilds with the new value, so a parent that
  /// refuses a change simply leaves the thumb where it is.
  final ValueChanged<T> onChanged;

  /// Minimum height of each segment (its tap target). Defaults to 48, or 44
  /// when [dense].
  final double? height;

  /// Smaller type for inline toggles that sit beside other content.
  final bool dense;

  /// Fixed width per segment. When set, the control sizes to its content
  /// instead of filling the width it is given.
  final double? segmentWidth;

  /// Optional outside driver for the thumb, in segment-index units (for
  /// example a TabController's animation, so the thumb tracks a swipe).
  /// When null the control animates the thumb itself.
  final Animation<double>? position;

  @override
  State<KSegmented<T>> createState() => _KSegmentedState<T>();
}

class _KSegmentedState<T> extends State<KSegmented<T>>
    with SingleTickerProviderStateMixin {
  // Critically damped: a firm, quick glide that lands without overshooting
  // the track's edge.
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 1);

  static const double _pad = 4;

  late int _index = _indexOf(widget.value);

  // Thumb position in segment-index units (0 = first segment).
  late final AnimationController _thumb = AnimationController.unbounded(
    vsync: this,
    value: _index < 0 ? 0 : _index.toDouble(),
  );

  int _indexOf(T v) => widget.segments.indexWhere((s) => s.value == v);

  @override
  void didUpdateWidget(covariant KSegmented<T> old) {
    super.didUpdateWidget(old);
    final next = _indexOf(widget.value);
    if (next == _index) return;
    _index = next;
    if (next < 0) return;
    // An outside driver moves the thumb; ours only needs to stay in step.
    if (widget.position != null || KMotion.reduced(context)) {
      _thumb.value = next.toDouble();
      return;
    }
    // Retarget from wherever the thumb is, keeping its velocity.
    _thumb.animateWith(
      SpringSimulation(_spring, _thumb.value, next.toDouble(), _thumb.velocity),
    );
  }

  @override
  void dispose() {
    _thumb.dispose();
    super.dispose();
  }

  void _select(T v) {
    if (v == widget.value) return;
    KHaptics.select();
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    final track = DecoratedBox(
      decoration: BoxDecoration(
        color: KColor.fg.withValues(alpha: dark ? 0.04 : 0.035),
        borderRadius: KRadius.md,
        border: Border.all(
          color: KColor.fg.withValues(alpha: dark ? 0.07 : 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_pad - 1),
        child: widget.segmentWidth != null
            ? _body(widget.segmentWidth!)
            : LayoutBuilder(
                builder: (context, box) => _body(
                  box.maxWidth.isFinite
                      ? box.maxWidth / widget.segments.length
                      : 72,
                ),
              ),
      ),
    );
    return RepaintBoundary(child: track);
  }

  Widget _body(double segW) {
    final driver = widget.position ?? _thumb;
    return SizedBox(
      width: segW * widget.segments.length,
      child: AnimatedBuilder(
        animation: driver,
        builder: (context, _) {
          final pos = driver.value;
          return Stack(
            children: [
              if (_index >= 0)
                PositionedDirectional(
                  start: pos * segW,
                  width: segW,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: KColor.ink,
                      borderRadius: KRadius.sm,
                    ),
                  ),
                ),
              // IntrinsicHeight keeps every segment as tall as the tallest
              // label, so the thumb fits whichever one it lands on.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.segments.length; i++)
                      SizedBox(
                        width: segW,
                        child: _segment(
                          context,
                          widget.segments[i],
                          i,
                          // How much of the thumb sits under this segment.
                          _index < 0 ? 0.0 : (1 - (pos - i).abs()).clamp(0.0, 1.0),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _segment(BuildContext context, KSegment<T> s, int i, double cover) {
    final selected = i == _index;
    final fg = Color.lerp(KColor.textSecondary, KColor.onInk, cover)!;
    final bold = MediaQuery.boldTextOf(context);
    final style = (widget.dense
            ? KText.caption.copyWith(fontSize: 13, height: 1.2)
            : KText.bodyMedium.copyWith(fontSize: 14, height: 1.2))
        .copyWith(
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: fg,
        );
    final icon = selected ? (s.selectedIcon ?? s.icon) : s.icon;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: s.semanticLabel ?? s.label,
      // excludeSemantics drops the Pressable's own tap, so re-expose it.
      onTap: () => _select(s.value),
      excludeSemantics: true,
      child: Pressable(
        onTap: () => _select(s.value),
        scale: 0.97,
        borderRadius: KRadius.sm,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: widget.height ?? (widget.dense ? 44 : 48),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? KSpacing.xs + 2 : KSpacing.sm,
              vertical: KSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: widget.dense ? 15 : 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    s.label,
                    textAlign: TextAlign.center,
                    style: style,
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
