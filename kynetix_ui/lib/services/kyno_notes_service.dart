import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Things the user wants Kyno to keep in mind in every answer: "vegetarian on
/// Tuesdays", "left knee hurts on squats", "no whey". Per user, on this
/// device; sent with each question inside the app brief.
class KynoNotesService {
  KynoNotesService._();
  static final KynoNotesService instance = KynoNotesService._();

  static const _kNotes = 'kyno_standing_notes_v1';
  static const maxNotes = 12;
  static const maxLength = 80;

  final ValueNotifier<List<String>> notes = ValueNotifier(const []);
  String? _userId;
  SharedPreferences? _prefs;

  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _userId = userId;
    _prefs = prefsOverride ?? await SharedPreferences.getInstance();
    final raw = _prefs!.getString('${_kNotes}_$userId');
    var list = const <String>[];
    if (raw != null) {
      try {
        list = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    notes.value = List.unmodifiable(list);
  }

  void clearMemory() {
    _userId = null;
    notes.value = const [];
  }

  /// Cleans a note for storage: one line, trimmed, capped.
  static String clean(String raw) {
    final one = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= maxLength ? one : one.substring(0, maxLength).trimRight();
  }

  Future<bool> add(String raw) async {
    final n = clean(raw);
    if (n.isEmpty || notes.value.length >= maxNotes) return false;
    if (notes.value.any((e) => e.toLowerCase() == n.toLowerCase())) return false;
    await _save([...notes.value, n]);
    return true;
  }

  Future<void> remove(String note) => _save([...notes.value]..remove(note));

  Future<void> _save(List<String> list) async {
    final owner = _userId;
    if (owner == null) return;
    notes.value = List.unmodifiable(list);
    await (_prefs ?? await SharedPreferences.getInstance()).setString('${_kNotes}_$owner', jsonEncode(list));
  }
}
