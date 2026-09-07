import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/exercises_library.json');
  final list = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  print('Total in json: ${list.length}');

  final faceItems = list.where((e) {
    final n = (e['name'] as String? ?? '').toLowerCase();
    final id = (e['id'] as String? ?? '').toLowerCase();
    final aliases = (e['aliases'] as List? ?? []).map((a) => a.toString().toLowerCase()).toList();
    return n.contains('face') || id.contains('face') || aliases.any((a) => a.contains('face'));
  }).toList();
  for (final e in faceItems) {
    print('FACE: ${e["id"]} | ${e["name"]} | img: ${e["imageRef"]} | gif: ${e["gifRef"]} | aliases: ${e["aliases"]}');
  }

  final triItems = list.where((e) {
    final n = (e['name'] as String? ?? '').toLowerCase();
    final id = (e['id'] as String? ?? '').toLowerCase();
    return n.contains('overhead') && (n.contains('tricep') || n.contains('triceps') || id.contains('tricep') || id.contains('tri'));
  }).toList();
  for (final e in triItems) {
    print('TRI: ${e["id"]} | ${e["name"]} | img: ${e["imageRef"]} | gif: ${e["gifRef"]}');
  }
}
