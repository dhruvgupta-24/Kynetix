void main() {
  final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
  final txt = '**Total Dinner:**';
  print('Matches:');
  for (final m in re.allMatches(txt)) {
    print(m.group(0));
    print('  1: ' + (m.group(1) ?? 'null'));
    print('  2: ' + (m.group(2) ?? 'null'));
  }
}
