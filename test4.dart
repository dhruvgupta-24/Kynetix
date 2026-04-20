void main() {
  String text = '**Total Dinner:**\n- Calories: 553 + 220';
  final lines = text.split('\n');
  for (int i=0; i<lines.length; i++) {
    final raw = lines[i];
    final trimmed = raw.trim();
    if (trimmed.startsWith('**') && trimmed.endsWith(':**') && trimmed.length > 5) {
      final inner = trimmed.substring(2, trimmed.length - 3).trim();
      if (inner.isNotEmpty && !inner.contains('**')) {
        print('WHOLE LINE RULE 2: ' + inner);
        continue;
      }
    }
    if (trimmed.startsWith('**') && trimmed.endsWith('**') && trimmed.length > 4) {
      final inner = trimmed.substring(2, trimmed.length - 2).trim();
      if (inner.isNotEmpty && !inner.contains('**')) {
        final label = inner.endsWith(':') ? inner.substring(0, inner.length - 1) : inner;
        print('WHOLE LINE RULE 1: ' + label);
        continue;
      }
    }
    print('_parseInline: ' + trimmed);
  }
}

