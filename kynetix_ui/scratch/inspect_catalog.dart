import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/exercises_library.json');
  final list = jsonDecode(file.readAsStringSync()) as List;
  int withImage = 0;
  int withGif = 0;
  int total = list.length;

  for (final item in list) {
    if (item['imageRef'] != null && (item['imageRef'] as String).isNotEmpty) withImage++;
    if (item['gifRef'] != null && (item['gifRef'] as String).isNotEmpty) withGif++;
  }

  print('Total exercises: $total');
  print('With imageRef: $withImage');
  print('With gifRef: $withGif');
}
