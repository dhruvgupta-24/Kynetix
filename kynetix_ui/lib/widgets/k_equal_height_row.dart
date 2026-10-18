import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Equal-width children that all take the height of the tallest one, with
/// an optional hairline rule centred in each gap.
///
/// A replacement for `IntrinsicHeight(child: Row(stretch, [Expanded...]))`
/// without intrinsic passes: each child is laid out once with a loose height
/// to find the tallest, then any shorter one again at that exact height.
/// Children must cope with an unbounded max height in the first pass (no
/// Spacer or Expanded in a vertical Flex; use spaceBetween instead).
class KEqualHeightRow extends MultiChildRenderObjectWidget {
  const KEqualHeightRow({
    super.key,
    required super.children,
    this.gap = 0,
    this.minHeight = 0,
    this.ruleColor,
    this.ruleInset = 0,
  });

  /// Space between children. A rule, when drawn, sits in its middle.
  final double gap;

  /// Every child is at least this tall.
  final double minHeight;

  /// Colour of a 1 px vertical rule between children; none when null.
  final Color? ruleColor;

  /// How far the rule stops short of the top and bottom.
  final double ruleInset;

  @override
  RenderKEqualHeightRow createRenderObject(BuildContext context) => RenderKEqualHeightRow(
        gap: gap,
        minHeight: minHeight,
        ruleColor: ruleColor,
        ruleInset: ruleInset,
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      );

  @override
  void updateRenderObject(BuildContext context, RenderKEqualHeightRow renderObject) {
    renderObject
      ..gap = gap
      ..minHeight = minHeight
      ..ruleColor = ruleColor
      ..ruleInset = ruleInset
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

class _EqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderKEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualRowParentData> {
  RenderKEqualHeightRow({
    required double gap,
    required double minHeight,
    required Color? ruleColor,
    required double ruleInset,
    required TextDirection textDirection,
  })  : _gap = gap,
        _minHeight = minHeight,
        _ruleColor = ruleColor,
        _ruleInset = ruleInset,
        _textDirection = textDirection;

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _minHeight;
  set minHeight(double v) {
    if (v == _minHeight) return;
    _minHeight = v;
    markNeedsLayout();
  }

  Color? _ruleColor;
  set ruleColor(Color? v) {
    if (v == _ruleColor) return;
    _ruleColor = v;
    markNeedsPaint();
  }

  double _ruleInset;
  set ruleInset(double v) {
    if (v == _ruleInset) return;
    _ruleInset = v;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualRowParentData) child.parentData = _EqualRowParentData();
  }

  double _childWidth(double maxWidth) {
    if (childCount == 0 || !maxWidth.isFinite) return 0;
    return math.max(0, (maxWidth - _gap * (childCount - 1)) / childCount);
  }

  Size _sizeFor(BoxConstraints constraints, Size Function(RenderBox, BoxConstraints) measure) {
    final w = _childWidth(constraints.maxWidth);
    var h = _minHeight;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      h = math.max(h, measure(c, BoxConstraints(minWidth: w, maxWidth: w, minHeight: _minHeight)).height);
    }
    return constraints.constrain(Size(constraints.maxWidth.isFinite ? constraints.maxWidth : 0, h));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _sizeFor(constraints, (c, bc) => c.getDryLayout(bc));

  @override
  void performLayout() {
    final w = _childWidth(constraints.maxWidth);
    // Pass 1: natural heights.
    final natural = _sizeFor(constraints, (c, bc) {
      c.layout(bc, parentUsesSize: true);
      return c.size;
    });
    size = natural;
    final h = natural.height;
    // Pass 2: shorter children stretch to the row's height.
    final rtl = _textDirection == TextDirection.rtl;
    var x = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (c.size.height != h) {
        c.layout(BoxConstraints.tightFor(width: w, height: h), parentUsesSize: true);
      }
      final pd = c.parentData! as _EqualRowParentData;
      pd.offset = Offset(rtl ? size.width - x - w : x, 0);
      x += w + _gap;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var w = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      w = math.max(w, c.getMinIntrinsicWidth(height));
    }
    return w * childCount + _gap * math.max(0, childCount - 1);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var w = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      w = math.max(w, c.getMaxIntrinsicWidth(height));
    }
    return w * childCount + _gap * math.max(0, childCount - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final w = _childWidth(width);
    var h = _minHeight;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      h = math.max(h, c.getMinIntrinsicHeight(w));
    }
    return h;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final w = _childWidth(width);
    var h = _minHeight;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      h = math.max(h, c.getMaxIntrinsicHeight(w));
    }
    return h;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    final color = _ruleColor;
    if (color == null || childCount < 2) return;
    final paint = Paint()..color = color;
    final top = offset.dy + _ruleInset;
    final bottom = offset.dy + size.height - _ruleInset;
    if (bottom <= top) return;
    var c = firstChild;
    while (c != null) {
      final next = childAfter(c);
      if (next == null) break;
      final a = (c.parentData! as _EqualRowParentData).offset.dx;
      final b = (next.parentData! as _EqualRowParentData).offset.dx;
      // Centre of the gap between this child and the next.
      final left = math.min(a, b) + c.size.width;
      final x = offset.dx + left + (_gap - 1) / 2;
      context.canvas.drawRect(Rect.fromLTRB(x, top, x + 1, bottom), paint);
      c = next;
    }
  }
}
