import 'dart:math';
import 'package:flutter/material.dart';

/// Zero-dependency, high-performance SVG path parser for Flutter.
/// Parses SVG path strings into cached Flutter [Path] objects.
class SvgPathParser {
  static final Map<String, Path> _pathCache = {};

  /// Parse an SVG path data string into a Flutter [Path].
  /// Results are cached in memory for sub-microsecond subsequent lookups.
  static Path parse(String svgPathData) {
    if (_pathCache.containsKey(svgPathData)) {
      return _pathCache[svgPathData]!;
    }

    final path = Path();
    final tokens = _tokenize(svgPathData);
    if (tokens.isEmpty) {
      _pathCache[svgPathData] = path;
      return path;
    }

    double curX = 0;
    double curY = 0;
    double startX = 0;
    double startY = 0;
    double lastCpX = 0;
    double lastCpY = 0;
    String lastCmd = '';

    int i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      if (_isCommand(token)) {
        lastCmd = token;
        i++;
      } else {
        // Repeated coordinates use previous command (except M -> L, m -> l)
        if (lastCmd == 'M') lastCmd = 'L';
        if (lastCmd == 'm') lastCmd = 'l';
      }

      switch (lastCmd) {
        case 'M':
          if (i + 1 < tokens.length) {
            curX = double.tryParse(tokens[i++]) ?? curX;
            curY = double.tryParse(tokens[i++]) ?? curY;
            startX = curX;
            startY = curY;
            path.moveTo(curX, curY);
          }
          break;
        case 'm':
          if (i + 1 < tokens.length) {
            curX += double.tryParse(tokens[i++]) ?? 0;
            curY += double.tryParse(tokens[i++]) ?? 0;
            startX = curX;
            startY = curY;
            path.moveTo(curX, curY);
          }
          break;
        case 'L':
          if (i + 1 < tokens.length) {
            curX = double.tryParse(tokens[i++]) ?? curX;
            curY = double.tryParse(tokens[i++]) ?? curY;
            path.lineTo(curX, curY);
          }
          break;
        case 'l':
          if (i + 1 < tokens.length) {
            curX += double.tryParse(tokens[i++]) ?? 0;
            curY += double.tryParse(tokens[i++]) ?? 0;
            path.lineTo(curX, curY);
          }
          break;
        case 'H':
          if (i < tokens.length) {
            curX = double.tryParse(tokens[i++]) ?? curX;
            path.lineTo(curX, curY);
          }
          break;
        case 'h':
          if (i < tokens.length) {
            curX += double.tryParse(tokens[i++]) ?? 0;
            path.lineTo(curX, curY);
          }
          break;
        case 'V':
          if (i < tokens.length) {
            curY = double.tryParse(tokens[i++]) ?? curY;
            path.lineTo(curX, curY);
          }
          break;
        case 'v':
          if (i < tokens.length) {
            curY += double.tryParse(tokens[i++]) ?? 0;
            path.lineTo(curX, curY);
          }
          break;
        case 'C':
          if (i + 5 < tokens.length) {
            final cp1x = double.tryParse(tokens[i++]) ?? curX;
            final cp1y = double.tryParse(tokens[i++]) ?? curY;
            final cp2x = double.tryParse(tokens[i++]) ?? curX;
            final cp2y = double.tryParse(tokens[i++]) ?? curY;
            curX = double.tryParse(tokens[i++]) ?? curX;
            curY = double.tryParse(tokens[i++]) ?? curY;
            lastCpX = cp2x;
            lastCpY = cp2y;
            path.cubicTo(cp1x, cp1y, cp2x, cp2y, curX, curY);
          }
          break;
        case 'c':
          if (i + 5 < tokens.length) {
            final cp1x = curX + (double.tryParse(tokens[i++]) ?? 0);
            final cp1y = curY + (double.tryParse(tokens[i++]) ?? 0);
            final cp2x = curX + (double.tryParse(tokens[i++]) ?? 0);
            final cp2y = curY + (double.tryParse(tokens[i++]) ?? 0);
            curX += double.tryParse(tokens[i++]) ?? 0;
            curY += double.tryParse(tokens[i++]) ?? 0;
            lastCpX = cp2x;
            lastCpY = cp2y;
            path.cubicTo(cp1x, cp1y, cp2x, cp2y, curX, curY);
          }
          break;
        case 'S':
          if (i + 3 < tokens.length) {
            double cp1x = curX;
            double cp1y = curY;
            if (lastCmd == 'C' || lastCmd == 'c' || lastCmd == 'S' || lastCmd == 's') {
              cp1x = 2 * curX - lastCpX;
              cp1y = 2 * curY - lastCpY;
            }
            final cp2x = double.tryParse(tokens[i++]) ?? curX;
            final cp2y = double.tryParse(tokens[i++]) ?? curY;
            curX = double.tryParse(tokens[i++]) ?? curX;
            curY = double.tryParse(tokens[i++]) ?? curY;
            lastCpX = cp2x;
            lastCpY = cp2y;
            path.cubicTo(cp1x, cp1y, cp2x, cp2y, curX, curY);
          }
          break;
        case 's':
          if (i + 3 < tokens.length) {
            double cp1x = curX;
            double cp1y = curY;
            if (lastCmd == 'C' || lastCmd == 'c' || lastCmd == 'S' || lastCmd == 's') {
              cp1x = 2 * curX - lastCpX;
              cp1y = 2 * curY - lastCpY;
            }
            final cp2x = curX + (double.tryParse(tokens[i++]) ?? 0);
            final cp2y = curY + (double.tryParse(tokens[i++]) ?? 0);
            curX += double.tryParse(tokens[i++]) ?? 0;
            curY += double.tryParse(tokens[i++]) ?? 0;
            lastCpX = cp2x;
            lastCpY = cp2y;
            path.cubicTo(cp1x, cp1y, cp2x, cp2y, curX, curY);
          }
          break;
        case 'Q':
          if (i + 3 < tokens.length) {
            final cpx = double.tryParse(tokens[i++]) ?? curX;
            final cpy = double.tryParse(tokens[i++]) ?? curY;
            curX = double.tryParse(tokens[i++]) ?? curX;
            curY = double.tryParse(tokens[i++]) ?? curY;
            lastCpX = cpx;
            lastCpY = cpy;
            path.quadraticBezierTo(cpx, cpy, curX, curY);
          }
          break;
        case 'q':
          if (i + 3 < tokens.length) {
            final cpx = curX + (double.tryParse(tokens[i++]) ?? 0);
            final cpy = curY + (double.tryParse(tokens[i++]) ?? 0);
            curX += double.tryParse(tokens[i++]) ?? 0;
            curY += double.tryParse(tokens[i++]) ?? 0;
            lastCpX = cpx;
            lastCpY = cpy;
            path.quadraticBezierTo(cpx, cpy, curX, curY);
          }
          break;
        case 'A':
        case 'a':
          if (i + 6 < tokens.length) {
            final rx = (double.tryParse(tokens[i++]) ?? 1).abs();
            final ry = (double.tryParse(tokens[i++]) ?? 1).abs();
            final angle = double.tryParse(tokens[i++]) ?? 0;
            final largeArc = (int.tryParse(tokens[i++]) ?? 0) != 0;
            final sweep = (int.tryParse(tokens[i++]) ?? 0) != 0;
            double endX = double.tryParse(tokens[i++]) ?? curX;
            double endY = double.tryParse(tokens[i++]) ?? curY;
            if (lastCmd == 'a') {
              endX += curX;
              endY += curY;
            }
            _addArc(path, curX, curY, endX, endY, rx, ry, angle, largeArc, sweep);
            curX = endX;
            curY = endY;
          }
          break;
        case 'Z':
        case 'z':
          path.close();
          curX = startX;
          curY = startY;
          break;
        default:
          i++;
      }
    }

    _pathCache[svgPathData] = path;
    return path;
  }

  static bool _isCommand(String token) {
    if (token.length != 1) return false;
    const cmds = 'MmLlHhVvCcSsQqTtAaZz';
    return cmds.contains(token);
  }

  static List<String> _tokenize(String d) {
    final tokens = <String>[];
    final regex = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?');
    for (final match in regex.allMatches(d)) {
      tokens.add(match.group(0)!);
    }
    return tokens;
  }

  static void _addArc(
    Path path,
    double x1,
    double y1,
    double x2,
    double y2,
    double rx,
    double ry,
    double angle,
    bool largeArc,
    bool sweep,
  ) {
    if (x1 == x2 && y1 == y2) return;
    if (rx == 0 || ry == 0) {
      path.lineTo(x2, y2);
      return;
    }

    final phi = angle * pi / 180.0;
    final cosPhi = cos(phi);
    final sinPhi = sin(phi);

    final dx = (x1 - x2) / 2.0;
    final dy = (y1 - y2) / 2.0;

    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;

    var rxSq = rx * rx;
    var rySq = ry * ry;
    final x1pSq = x1p * x1p;
    final y1pSq = y1p * y1p;

    final lambda = x1pSq / rxSq + y1pSq / rySq;
    if (lambda > 1.0) {
      rx *= sqrt(lambda);
      ry *= sqrt(lambda);
      rxSq = rx * rx;
      rySq = ry * ry;
    }

    final sign = (largeArc == sweep) ? -1.0 : 1.0;
    final num = max(0.0, (rxSq * rySq - rxSq * y1pSq - rySq * x1pSq));
    final den = rxSq * y1pSq + rySq * x1pSq;
    final sq = den == 0 ? 0.0 : sign * sqrt(num / den);

    final cxp = sq * (rx * y1p / ry);
    final cyp = sq * -(ry * x1p / rx);

    final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2.0;
    final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2.0;

    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );

    path.arcTo(rect, 0, pi, false);
    path.lineTo(x2, y2);
  }
}
