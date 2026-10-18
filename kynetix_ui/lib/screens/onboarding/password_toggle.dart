import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

/// 48dp eye toggle for a password field's suffix.
///
/// Semantics name the action it performs ("Show password" while hidden,
/// "Hide password" while shown); the glyph change and the field's own text
/// carry the state too, so it never relies on the icon alone.
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onToggle,
  });

  final bool obscured;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = obscured ? 'Show password' : 'Hide password';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: IconButton(
        onPressed: () {
          KHaptics.select();
          onToggle();
        },
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: EdgeInsets.zero,
        splashRadius: 22,
        color: KColor.textMuted,
        icon: AnimatedSwitcher(
          duration: KMotion.of(context, KMotion.quick),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1).animate(anim),
              child: child,
            ),
          ),
          child: Icon(
            obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            key: ValueKey(obscured),
            size: 20,
            color: KColor.textMuted,
          ),
        ),
      ),
    );
  }
}
