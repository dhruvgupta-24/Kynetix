import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── KColor ───────────────────────────────────────────────────────────────────
// All color tokens for the app. Import this everywhere instead of hardcoding.

abstract class KColor {
  // ── Backgrounds
  static const bg        = Color(0xFF0F0F1A); // page background
  static const surface   = Color(0xFF1A1A28); // cards, bars
  static const card      = Color(0xFF1E1E2E); // elevated cards
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
  static const _base = TextStyle(fontFamily: 'Roboto', color: KColor.textPrimary);

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
