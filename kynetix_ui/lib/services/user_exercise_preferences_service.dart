import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a local user's historical interaction with a specific exercise.
class ExerciseUsageRecord {
  final String exerciseId;
  int selectionCount;
  DateTime lastUsedAt;
  int completedWorkoutCount;

  ExerciseUsageRecord({
    required this.exerciseId,
    this.selectionCount = 1,
    DateTime? lastUsedAt,
    this.completedWorkoutCount = 0,
  }) : lastUsedAt = lastUsedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'selectionCount': selectionCount,
        'lastUsedAt': lastUsedAt.toIso8601String(),
        'completedWorkoutCount': completedWorkoutCount,
      };

  factory ExerciseUsageRecord.fromJson(Map<String, dynamic> json) {
    return ExerciseUsageRecord(
      exerciseId: json['exerciseId'] as String? ?? '',
      selectionCount: (json['selectionCount'] as num?)?.toInt() ?? 1,
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.tryParse(json['lastUsedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      completedWorkoutCount: (json['completedWorkoutCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Offline-first service managing user exercise history and favorites locally.
/// Strictly decoupled from the master exercise catalog. Never mutates built-in definitions.
class UserExercisePreferencesService extends ChangeNotifier {
  UserExercisePreferencesService._();
  static final UserExercisePreferencesService instance =
      UserExercisePreferencesService._();

  static const String _kFavoritesKey = 'kynetix_user_exercise_favorites_v1';
  static const String _kHistoryKey = 'kynetix_user_exercise_history_v1';

  bool _initialized = false;
  final Set<String> _favorites = {};
  final Map<String, ExerciseUsageRecord> _usageHistory = {};

  Set<String> get favorites => Set.unmodifiable(_favorites);
  Map<String, ExerciseUsageRecord> get usageHistory =>
      Map.unmodifiable(_usageHistory);

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load favorites
      final favList = prefs.getStringList(_kFavoritesKey) ?? [];
      _favorites.clear();
      _favorites.addAll(favList);

      // Load usage history
      final historyJson = prefs.getString(_kHistoryKey);
      _usageHistory.clear();
      if (historyJson != null && historyJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(historyJson);
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            _usageHistory[entry.key] =
                ExerciseUsageRecord.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      }
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('UserExercisePreferencesService init error: $e');
      _initialized = true;
    }
  }

  /// Synchronously seed favorites/history for unit tests.
  void seedForTesting({
    Set<String>? favorites,
    Map<String, ExerciseUsageRecord>? history,
  }) {
    if (favorites != null) {
      _favorites.clear();
      _favorites.addAll(favorites);
    }
    if (history != null) {
      _usageHistory.clear();
      _usageHistory.addAll(history);
    }
    _initialized = true;
    notifyListeners();
  }

  /// Records an exercise selection or workout completion.
  Future<void> recordSelection(String exerciseId, {bool fromCompletedWorkout = false}) async {
    if (exerciseId.isEmpty) return;
    final existing = _usageHistory[exerciseId];
    if (existing != null) {
      existing.selectionCount++;
      existing.lastUsedAt = DateTime.now();
      if (fromCompletedWorkout) existing.completedWorkoutCount++;
    } else {
      _usageHistory[exerciseId] = ExerciseUsageRecord(
        exerciseId: exerciseId,
        selectionCount: 1,
        lastUsedAt: DateTime.now(),
        completedWorkoutCount: fromCompletedWorkout ? 1 : 0,
      );
    }
    notifyListeners();
    await _persistHistory();
  }

  /// Toggles favorite status for an exercise.
  Future<bool> toggleFavorite(String exerciseId) async {
    if (exerciseId.isEmpty) return false;
    final isFav = _favorites.contains(exerciseId);
    if (isFav) {
      _favorites.remove(exerciseId);
    } else {
      _favorites.add(exerciseId);
    }
    notifyListeners();
    await _persistFavorites();
    return !isFav;
  }

  bool isFavorite(String exerciseId) => _favorites.contains(exerciseId);

  /// Returns recent exercise IDs ordered by last used timestamp.
  List<String> getRecentExerciseIds({int limit = 10}) {
    final list = _usageHistory.values.toList()
      ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return list.take(limit).map((r) => r.exerciseId).toList();
  }

  /// Returns favorite exercise IDs.
  List<String> getFavoriteExerciseIds() => _favorites.toList();

  /// Calculates a personalized relevance score boost (0 to 350 pts).
  /// Gives preference to frequently & recently performed movements
  /// without ever overriding strong exact search matches.
  int getPersonalBoost(String exerciseId) {
    int boost = 0;
    if (_favorites.contains(exerciseId)) {
      boost += 150;
    }
    final record = _usageHistory[exerciseId];
    if (record != null) {
      // Frequency boost: +25 per use, capped at +150
      boost += (record.selectionCount * 25).clamp(0, 150);
      
      // Recency boost: +50 if used within last 7 days
      final daysSince = DateTime.now().difference(record.lastUsedAt).inDays;
      if (daysSince <= 7) {
        boost += 50;
      } else if (daysSince <= 30) {
        boost += 20;
      }
    }
    return boost.clamp(0, 350);
  }

  Future<void> _persistFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kFavoritesKey, _favorites.toList());
    } catch (e) {
      debugPrint('Error saving exercise favorites: $e');
    }
  }

  Future<void> _persistHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final e in _usageHistory.entries) {
        map[e.key] = e.value.toJson();
      }
      await prefs.setString(_kHistoryKey, jsonEncode(map));
    } catch (e) {
      debugPrint('Error saving exercise history: $e');
    }
  }
}
