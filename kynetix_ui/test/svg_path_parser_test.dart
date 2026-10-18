import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/utils/svg_path_parser.dart';

/// The body map was drawn garbled: compact arc flags ("0 01-.19") were read
/// as one number, and every arc was drawn as a fixed half-ellipse. Every
/// muscle path must now stay inside its view.
void main() {
  test('every body-map path stays inside its viewBox', () {
    final d = jsonDecode(File('assets/data/body_paths.json').readAsStringSync()) as Map<String, dynamic>;
    final bad = <String>[];
    for (final side in ['front', 'back']) {
      final vb = (d[side]['viewBox'] as String).split(' ').map(double.parse).toList();
      final paths = d[side]['paths'] as Map<String, dynamic>;
      paths.forEach((k, v) {
        final list = v is List ? v : [v];
        for (var j = 0; j < list.length; j++) {
          final b = SvgPathParser.parse(list[j] as String).getBounds();
          if (b.left < vb[0] - 20 || b.right > vb[0] + vb[2] + 20 || b.top < vb[1] - 20 || b.bottom > vb[1] + vb[3] + 20) {
            bad.add('$side $k $j $b');
          }
        }
      });
    }
    expect(bad, isEmpty);
  });

  test('compact arc flags parse as two flags then the end point', () {
    final p = SvgPathParser.parse('M10 10a5 5 0 0110 0');
    final b = p.getBounds();
    expect(b.left, closeTo(10, 0.01));
    expect(b.right, closeTo(20, 0.01));
    expect(b.top, closeTo(5, 0.01));
  });
}
