void main() {
  final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|' + r'(.+?)');
  final txt = '**Total Dinner:**';
  for (final m in re.allMatches(txt)) {
    print('Match found! group1: ' + (m.group(1) ?? 'null'));
  }
}

