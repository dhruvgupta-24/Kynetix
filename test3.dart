void main() {
  String line = '**Total Dinner:**';
  List<String> spans = [];
  final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|' + r'(.+?)');
  int cursor = 0;
  for (final m in re.allMatches(line)) {
    if (m.start > cursor) {
      spans.add('BASE: ' + line.substring(cursor, m.start));
    }
    if (m.group(1) != null) {
      spans.add('BOLD: ' + m.group(1)!);
    } else if (m.group(2) != null) {
      spans.add('ITAL: ' + m.group(2)!);
    } else if (m.group(3) != null) {
      spans.add('CODE: ' + m.group(3)!);
    }
    cursor = m.end;
  }
  if (cursor < line.length) {
    spans.add('BASE: ' + line.substring(cursor));
  }
  if (spans.isEmpty) spans.add('BASE: ' + line);
  for (var s in spans) print(s);
}

