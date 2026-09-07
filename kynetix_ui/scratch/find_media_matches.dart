import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/exercises_library.json');
  final list = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();

  final noMedia = list.where((e) => e['imageRef'] == null || (e['imageRef'] as String).isEmpty).toList();
  final withMedia = list.where((e) => e['imageRef'] != null && (e['imageRef'] as String).isNotEmpty).toList();

  final manualKeywords = {
    'db_row': 'dumbbell bent over row',
    'skullcrusher': 'lying triceps extension',
    'cable_curl': 'cable curl',
    'squat': 'barbell squat',
    'ohp': 'standing overhead press',
    'adductor_machine': 'adductor',
    'rdl': 'romanian deadlift',
    'rear_delt_fly': 'rear delt',
    'face_pull': 'face pull',
    'db_shoulder_press': 'dumbbell shoulder press',
    'incline_db_curl': 'incline dumbbell curl',
    'cable_pullover': 'pullover',
    'bb_row': 'barbell bent over row',
    'seated_cable_row': 'cable seated row',
    'pec_dec': 'seated fly',
    'cable_chest_fly': 'cable middle fly',
    'incline_db_press': 'dumbbell incline bench press',
  };

  for (final nm in noMedia) {
    final id = nm['id'] as String;
    final name = (nm['name'] as String).toLowerCase();
    final kw = manualKeywords[id] ?? name;

    Map<String, dynamic>? best;
    for (final wm in withMedia) {
      final wmName = (wm['name'] as String).toLowerCase();
      if (wmName.contains(kw) || kw.contains(wmName)) {
        best = wm;
        break;
      }
    }
    if (best == null) {
      // fallback partial
      final firstWord = kw.split(' ').first;
      for (final wm in withMedia) {
        final wmName = (wm['name'] as String).toLowerCase();
        if (wmName.contains(firstWord)) {
          best = wm;
          break;
        }
      }
    }
    print("  '$id': (image: '${best?['imageRef'] ?? ''}', gif: '${best?['gifRef'] ?? ''}'), // ${nm['name']} -> ${best?['name']}");
  }
}
