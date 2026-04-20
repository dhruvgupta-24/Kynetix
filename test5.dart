void main() {
  final re = RegExp(r'\*\*(.+?)\*\*');
  final text = '**Total Dinner:**';
  print(re.hasMatch(text));
}

