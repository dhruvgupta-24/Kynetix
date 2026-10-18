import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/ui/k_format.dart';

/// The owner's rule: no em dash anywhere in the app. Code comments may keep
/// them; anything that can reach the screen may not.
void main() {
  test('no em dash in app code outside comments', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].trimLeft();
        if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
        // Ignore a trailing line comment (" // 0.0 to 1.0" notes on fields).
        final cut = lines[i].indexOf(' //');
        final code = cut >= 0 && !lines[i].substring(cut).contains("'") ? lines[i].substring(0, cut) : lines[i];
        // The en dash looks the same on screen, so it is banned too.
        if (code.contains('—') || code.contains('–')) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('AI text loses its em dashes', () {
    expect(noEmDash('Dal — 420 kcal'), 'Dal, 420 kcal');
    expect(noEmDash('Good—keep going'), 'Good, keep going');
    expect(noEmDash('No dash here'), 'No dash here');
  });
}
