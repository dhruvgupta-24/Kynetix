class QuickAddItem {
  final String id;
  final String name;
  final double calories;
  final double protein;
  final String emoji;
  final bool builtIn;

  const QuickAddItem({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    this.emoji = '⚡',
    this.builtIn = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        'protein': protein,
        'emoji': emoji,
        'builtIn': builtIn,
      };

  factory QuickAddItem.fromJson(Map<String, dynamic> j) => QuickAddItem(
        id:       (j['id'] as String?) ?? '',
        name:     (j['name'] as String?) ?? '',
        calories: (j['calories'] as num?)?.toDouble() ?? 0.0,
        protein:  (j['protein'] as num?)?.toDouble() ?? 0.0,
        emoji:    (j['emoji'] as String?) ?? '⚡',
        builtIn:  (j['builtIn'] as bool?) ?? false,
      );

  QuickAddItem copyWith({
    String? id,
    String? name,
    double? calories,
    double? protein,
    String? emoji,
    bool? builtIn,
  }) =>
      QuickAddItem(
        id: id ?? this.id,
        name: name ?? this.name,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        emoji: emoji ?? this.emoji,
        builtIn: builtIn ?? this.builtIn,
      );
}
