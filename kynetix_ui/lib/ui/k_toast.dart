import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../widgets/k_success_check.dart';

// ─── KToast ───────────────────────────────────────────────────────────────────
// The app's one transient message. A rounded card floats above the bottom
// dock (or above the keyboard when it is open), says one thing, and leaves.
// It lives in the root overlay, so it survives the route that raised it
// being popped. Only one shows at a time: a new toast replaces the old one
// with a quick cross-fade.
//
// Moment declaration: toast
//   trigger: showKToast (a save, an undoable delete, a failure)
//   change:  enters with a fade, a 12 px rise and a 0.96 to 1 scale; leaves
//            faster with a fade and a small drop
//   duration role: 260 ms in (KMotion.easeOut), 180 ms out, 140 ms when
//            replaced
//   haptic:  none here; the caller fires one on its commit frame
//   reduced motion: fade only
//
// Stays 4 s, or 8 s when it carries an action. With a screen reader on, a
// toast with an action stays until it is acted on or dismissed. Swipe it
// down or sideways to dismiss.

enum KToastKind { info, success, error }

/// Why a toast went away.
enum KToastClose { timeout, action, swipe, replaced, hidden }

/// Show [message] as a toast. The returned future completes when the toast
/// starts to leave, with the reason it left.
Future<KToastClose> showKToast(
  BuildContext context,
  String message, {
  KToastKind kind = KToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) =>
    KToaster.of(context).show(
      message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );

/// A handle on the root overlay, for code that must resolve it before an
/// `await` (the way a ScaffoldMessenger used to be captured).
class KToaster {
  const KToaster._(this._overlay);
  final OverlayState? _overlay;

  static KToaster of(BuildContext context) =>
      KToaster._(Overlay.maybeOf(context, rootOverlay: true));

  static _KToastHandle? _current;

  /// Dismiss whatever toast is showing.
  static void hide() => _current?.close(KToastClose.hidden);

  Future<KToastClose> show(
    String message, {
    KToastKind kind = KToastKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final overlay = _overlay;
    if (overlay == null || !overlay.mounted) {
      return Future.value(KToastClose.hidden);
    }
    final hasAction = actionLabel != null && onAction != null;
    final handle = _KToastHandle();
    final view = _KToastView(
      key: handle.key,
      handle: handle,
      message: message,
      kind: kind,
      actionLabel: hasAction ? actionLabel : null,
      onAction: hasAction ? onAction : null,
      duration: duration ??
          (hasAction ? const Duration(seconds: 8) : const Duration(seconds: 4)),
    );
    _current?.close(KToastClose.replaced);
    _current = handle;
    handle.entry = OverlayEntry(builder: (_) => view);
    overlay.insert(handle.entry!);
    return handle.done.future;
  }
}

class _KToastHandle {
  final key = GlobalKey<_KToastViewState>();
  final done = Completer<KToastClose>();
  OverlayEntry? entry;

  void close(KToastClose reason) {
    if (done.isCompleted) return;
    done.complete(reason);
    if (identical(KToaster._current, this)) KToaster._current = null;
    final view = key.currentState;
    if (view != null && view.mounted) {
      view._exit(fast: reason == KToastClose.replaced);
    } else {
      remove();
    }
  }

  void remove() {
    final e = entry;
    if (e == null) return;
    entry = null;
    e.remove();
    e.dispose();
  }
}

class _KToastView extends StatefulWidget {
  const _KToastView({
    super.key,
    required this.handle,
    required this.message,
    required this.kind,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });

  final _KToastHandle handle;
  final String message;
  final KToastKind kind;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_KToastView> createState() => _KToastViewState();
}

class _KToastViewState extends State<_KToastView>
    with TickerProviderStateMixin {
  // The bottom of the floating dock's island sits 12 px above the safe area
  // and the island is 64 px tall (see _KDock in app_shell.dart).
  static const double _dockTop = 12 + 64;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: KMotion.easeOut,
    reverseCurve: KMotion.accelerate,
  );

  // Swipe: how far the finger has carried the card, and the spring-back.
  Offset _drag = Offset.zero;
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: KMotion.quick,
  )..addListener(() => setState(() {
        _drag = Offset.lerp(_snapFrom, Offset.zero, KMotion.easeOut.transform(_snap.value))!;
      }));
  Offset _snapFrom = Offset.zero;

  Timer? _timer;
  bool _started = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = KMotion.reduced(context);
    if (_started) return;
    _started = true;
    _ctrl.forward();
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _snap.dispose();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    // A screen reader user needs time to reach the action; keep it up.
    final waitForAction = widget.onAction != null &&
        MediaQuery.accessibleNavigationOf(context);
    if (waitForAction) return;
    _timer = Timer(widget.duration, () => widget.handle.close(KToastClose.timeout));
  }

  void _exit({required bool fast}) {
    _timer?.cancel();
    if (fast) _ctrl.reverseDuration = const Duration(milliseconds: 140);
    _ctrl.reverse().whenCompleteOrCancel(widget.handle.remove);
  }

  bool get _leaving => widget.handle.done.isCompleted;

  void _onPanStart(DragStartDetails _) {
    if (_leaving) return;
    _timer?.cancel();
    _snap.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_leaving) return;
    // Down or sideways only; pulling up meets resistance.
    final dy = _drag.dy + d.delta.dy;
    setState(() => _drag = Offset(_drag.dx + d.delta.dx, dy < 0 ? dy * 0.2 : dy));
  }

  void _onPanEnd(DragEndDetails d) {
    if (_leaving) return;
    final v = d.velocity.pixelsPerSecond;
    final away = _drag.dy > 36 || _drag.dx.abs() > 80 || v.dy > 600 || v.dx.abs() > 700;
    if (away) {
      widget.handle.close(KToastClose.swipe);
      return;
    }
    _snapFrom = _drag;
    _snap.forward(from: 0);
    _arm();
  }

  void _act() {
    if (_leaving) return;
    widget.onAction?.call();
    widget.handle.close(KToastClose.action);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bottom = keyboard > 0
        ? keyboard + KSpacing.md
        : media.padding.bottom + _dockTop + KSpacing.md;

    return Positioned(
      left: KSpacing.lg,
      right: KSpacing.lg,
      bottom: bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, child) {
              final t = _t.value;
              final pulled = _drag.dx.abs() + (_drag.dy > 0 ? _drag.dy : 0.0);
              final opacity = (t * (1 - pulled / 220)).clamp(0.0, 1.0);
              if (_reduced) {
                return Opacity(opacity: opacity, child: child);
              }
              return Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: _drag + Offset(0, (1 - t) * 12),
                  child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
                ),
              );
            },
            child: RepaintBoundary(child: _card()),
          ),
        ),
      ),
    );
  }

  Widget _card() {
    final dark = KColor.isDark;
    final leading = switch (widget.kind) {
      KToastKind.success => KSuccessCheck(size: 18, color: KColor.textPrimary),
      KToastKind.error => Icon(Icons.error_outline_rounded, size: 20, color: KColor.danger),
      KToastKind.info => Icon(Icons.info_outline_rounded, size: 20, color: KColor.textSecondary),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      onDismiss: () => widget.handle.close(KToastClose.hidden),
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: EdgeInsetsDirectional.fromSTEB(
              KSpacing.md + 2,
              KSpacing.sm,
              widget.actionLabel != null ? KSpacing.xs : KSpacing.lg,
              KSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: dark ? KColor.cardHigh : KColor.card,
              borderRadius: KRadius.md,
              border: Border.all(color: KColor.border),
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: Center(child: ExcludeSemantics(child: leading)),
                ),
                const SizedBox(width: KSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: KSpacing.xs),
                    child: Text(
                      widget.message,
                      style: KText.bodyMedium.copyWith(
                        color: KColor.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                if (widget.actionLabel case final label?) ...[
                  const SizedBox(width: KSpacing.xs),
                  Pressable(
                    onTap: _act,
                    borderRadius: KRadius.sm,
                    semanticLabel: label,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: KSpacing.md),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            label,
                            style: KText.bodyMedium.copyWith(
                              color: KColor.ember,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
