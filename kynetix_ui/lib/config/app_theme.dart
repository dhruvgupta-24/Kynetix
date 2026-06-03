import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── KColor ───────────────────────────────────────────────────────────────────
// All color tokens for the app. Import this everywhere instead of hardcoding.

abstract class KColor {
  // ── Backgrounds
  static const bg        = Color(0xFF0F0F1A); // page background
  static const surface   = Color(0xFF1A1A28); // cards, bars
  static const card      = Color(0xFF1E1E2C); // elevated cards
  static const cardHigh  = Color(0xFF252535); // hovered / pressed cards

  // ── Borders
  static const border    = Color(0xFF2A2A3C);
  static const divider   = Color(0xFF252535);

  // ── Brand
  static const green     = Color(0xFF52B788); // primary accent
  static const greenDark = Color(0xFF2D6A4F); // dark green
  static const greenGlow = Color(0xFF52B788); // glow accent (same, used explicitly)

  // ── Semantic
  static const calorie   = Color(0xFFFF6B35); // orange
  static const protein   = Color(0xFF52B788); // green
  static const amber     = Color(0xFFFFB347);
  static const blue      = Color(0xFF60A5FA);
  static const danger    = Color(0xFFEF4444);
  static const warning   = Color(0xFFF59E0B);
  static const success   = Color(0xFF10B981);

  // ── Text
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB0B7C3);
  static const textMuted     = Color(0xFF6B7280);
  static const textDisabled  = Color(0xFF4B5563);
}

// ─── KText ────────────────────────────────────────────────────────────────────
// Typography scale. Use these consistently.

abstract class KText {
  static final _base = GoogleFonts.inter(color: KColor.textPrimary);

  static final display = _base.copyWith(
    fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2,
  );
  static final h1 = _base.copyWith(
    fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.25,
  );
  static final h2 = _base.copyWith(
    fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.3,
  );
  static final h3 = _base.copyWith(
    fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.1, height: 1.35,
  );
  static final body = _base.copyWith(
    fontSize: 14, fontWeight: FontWeight.w400, height: 1.6,
  );
  static final bodyMedium = _base.copyWith(
    fontSize: 14, fontWeight: FontWeight.w500, height: 1.5,
  );
  static final caption = _base.copyWith(
    fontSize: 12, fontWeight: FontWeight.w500, color: KColor.textSecondary, height: 1.4,
  );
  static final label = _base.copyWith(
    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: KColor.textMuted,
  );
  static final numDisplay = _base.copyWith(
    fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.0, height: 1.0,
  );
}

// ─── KSpacing ─────────────────────────────────────────────────────────────────

abstract class KSpacing {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 24;
  static const double p   = 20; // standard horizontal page padding
}

// ─── KRadius ──────────────────────────────────────────────────────────────────

abstract class KRadius {
  static const sm  = BorderRadius.all(Radius.circular(10));
  static const md  = BorderRadius.all(Radius.circular(14));
  static const lg  = BorderRadius.all(Radius.circular(18));
  static const xl  = BorderRadius.all(Radius.circular(22));
  static const pill= BorderRadius.all(Radius.circular(100));
}

// ─── KShadow ──────────────────────────────────────────────────────────────────

abstract class KShadow {
  static final card = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 20, offset: const Offset(0, 6),
    ),
  ];
  static List<BoxShadow> glow(Color c) => [
    BoxShadow(
      color: c.withValues(alpha: 0.25),
      blurRadius: 16, spreadRadius: 0, offset: const Offset(0, 4),
    ),
  ];
}

// ─── Pressable ────────────────────────────────────────────────────────────────
// A card that physically responds to press with scale + haptic.

class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;
  final BorderRadius borderRadius;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.duration = const Duration(milliseconds: 100),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scaleAnim;
  bool _isDown = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: widget.scale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _down() {
    if (!_isDown) {
      _isDown = true;
      _ctrl.forward();
    }
  }

  void _up() {
    if (_isDown) {
      _isDown = false;
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:    (_) => _down(),
      onTapUp:      (_) { _up(); widget.onTap?.call(); },
      onTapCancel:  ()  => _up(),
      onLongPress:  widget.onLongPress,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: widget.child,
      ),
    );
  }
}

// ─── KCard ────────────────────────────────────────────────────────────────────
// Standard app card. Replaces every hand-rolled `Container + BoxDecoration`.

class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final Border? border;

  const KCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderRadius,
    this.boxShadow,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(KSpacing.lg),
      decoration: BoxDecoration(
        color: color ?? KColor.card,
        borderRadius: borderRadius ?? KRadius.lg,
        border: border ?? Border.all(color: KColor.border, width: 0.5),
        boxShadow: boxShadow ?? KShadow.card,
      ),
      child: child,
    );
  }
}

// ─── KSectionTitle ────────────────────────────────────────────────────────────

class KSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  const KSectionTitle(this.text, {super.key, this.trailing, this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.xxl, KSpacing.xl, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: KText.label,
            ),
          ),
          if (trailing case final t?) t,
        ],
      ),
    );
  }
}

// ─── KButton ──────────────────────────────────────────────────────────────────
// Branded primary button with built-in loading state.

class KButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool outlined;
  final IconData? icon;
  final Color? color;
  final double? width;

  const KButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.outlined = false,
    this.icon,
    this.color,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? KColor.greenDark;
    return SizedBox(
      width: width,
      child: Pressable(
        onTap: (loading || onTap == null) ? null : onTap,
        borderRadius: KRadius.md,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : (loading ? bg.withValues(alpha: 0.5) : bg),
            borderRadius: KRadius.md,
            border: outlined ? Border.all(color: KColor.green, width: 1.5) : null,
            boxShadow: outlined ? null : [
              BoxShadow(
                color: bg.withValues(alpha: 0.4),
                blurRadius: 12, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
              ] else if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── KChip ────────────────────────────────────────────────────────────────────

class KChip extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  const KChip(this.label, {super.key, this.color, this.textColor, this.icon});

  @override
  Widget build(BuildContext context) {
    final bg = (color ?? KColor.green).withValues(alpha: 0.15);
    final fg = textColor ?? color ?? KColor.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: KRadius.pill,
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

// ─── KDragHandle ──────────────────────────────────────────────────────────────

class KDragHandle extends StatelessWidget {
  const KDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 36, height: 4,
        decoration: BoxDecoration(
          color: KColor.border, borderRadius: KRadius.pill,
        ),
      ),
    );
  }
}

// ─── KSheetHeader ─────────────────────────────────────────────────────────────

class KSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const KSheetHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KDragHandle(),
          const SizedBox(height: 8),
          Text(title, style: KText.h2),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: KText.caption),
          ],
        ],
      ),
    );
  }
}

// ─── Navigation helpers ───────────────────────────────────────────────────────

/// Slide-up + fade route — used for detail screens (DayDetail, AddMeal, etc.)
PageRoute<T> slideUpRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    pageBuilder: (ctx, anim, sec) => builder(ctx),
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (ctx, anim, sec, child) {
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.06),
        end:   Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// Haptic tap convenience
void kHaptic() => HapticFeedback.lightImpact();
void kHapticMedium() => HapticFeedback.mediumImpact();
void kHapticSelect() => HapticFeedback.selectionClick();

// ─── KGradientCircularProgress ───────────────────────────────────────────────

class KGradientCircularProgress extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final double strokeWidth;
  final List<Color> colors;
  final Color? trackColor;
  final Widget? child;

  const KGradientCircularProgress({
    super.key,
    required this.progress,
    this.strokeWidth = 10,
    required this.colors,
    this.trackColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GradientCircularProgressPainter(
        progress: progress,
        strokeWidth: strokeWidth,
        colors: colors,
        trackColor: trackColor ?? KColor.border,
      ),
      child: child != null ? Center(child: child) : null,
    );
  }
}

class _GradientCircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final List<Color> colors;
  final Color trackColor;

  _GradientCircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.colors,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    // Sweep gradient progress
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepGradient = SweepGradient(
      colors: colors,
      stops: List.generate(colors.length, (index) => index / (colors.length - 1)),
      transform: const GradientRotation(-3.14159 / 2),
    );

    final progressPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      rect,
      -3.14159 / 2,
      2 * 3.14159 * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientCircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.colors != colors ||
        oldDelegate.trackColor != trackColor;
  }
}

// ─── KShimmer ─────────────────────────────────────────────────────────────────

class KShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const KShimmer({super.key, required this.child, this.enabled = true});

  @override
  State<KShimmer> createState() => _KShimmerState();
}

class _KShimmerState extends State<KShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final double slide = _controller.value;
            return LinearGradient(
              begin: const Offset(-1.0, -0.3) as Alignment,
              end: const Offset(1.0, 0.3) as Alignment,
              colors: const [
                Color(0xFF1E1E2C),
                Color(0xFF2E2E3C),
                Color(0xFF1E1E2C),
              ],
              stops: const [0.3, 0.5, 0.7],
              transform: _ShimmerGradientTransform(slide),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

class _ShimmerGradientTransform extends GradientTransform {
  final double percent;

  const _ShimmerGradientTransform(this.percent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (percent * 2 - 1), 0.0, 0.0);
  }
}

class KShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const KShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return KShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? KRadius.md,
        ),
      ),
    );
  }
}

// ─── KAnimatedCount ──────────────────────────────────────────────────────────

class KAnimatedCount extends StatefulWidget {
  final num value;
  final TextStyle style;
  final String suffix;
  final String prefix;
  final int decimalPlaces;

  const KAnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.suffix = '',
    this.prefix = '',
    this.decimalPlaces = 0,
  });

  @override
  State<KAnimatedCount> createState() => _KAnimatedCountState();
}

class _KAnimatedCountState extends State<KAnimatedCount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _oldValue = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(begin: 0.0, end: widget.value.toDouble()).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    _oldValue = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant KAnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _oldValue = oldWidget.value.toDouble();
      _animation = Tween<double>(begin: _oldValue, end: widget.value.toDouble()).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final current = _animation.value;
        final text = widget.decimalPlaces == 0
            ? current.round().toString()
            : current.toStringAsFixed(widget.decimalPlaces);
        return Text(
          '${widget.prefix}$text${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}

// ─── KPulseLoader ────────────────────────────────────────────────────────────

class KPulseLoader extends StatefulWidget {
  final double size;
  final Color color;

  const KPulseLoader({
    super.key,
    this.size = 40.0,
    this.color = KColor.green,
  });

  @override
  State<KPulseLoader> createState() => _KPulseLoaderState();
}

class _KPulseLoaderState extends State<KPulseLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size * (1.0 + _controller.value * 0.5),
              height: widget.size * (1.0 + _controller.value * 0.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.4 * (1.0 - _controller.value)),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: KShadow.glow(widget.color),
              ),
              child: const Center(
                child: Icon(
                  Icons.bolt,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── KLoadingDots ────────────────────────────────────────────────────────────

class KLoadingDots extends StatefulWidget {
  final double size;
  final Color color;

  const KLoadingDots({
    super.key,
    this.size = 6.0,
    this.color = KColor.textSecondary,
  });

  @override
  State<KLoadingDots> createState() => _KLoadingDotsState();
}

class _KLoadingDotsState extends State<KLoadingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.0, end: -8.0).animate(
        CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        ),
      );
    }).toList();

    _startAnimations();
  }

  void _startAnimations() async {
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      _controllers[i].repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _animations[index].value),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
