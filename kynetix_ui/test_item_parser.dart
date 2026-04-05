import 'dart:io';
import 'lib/services/item_parser.dart';

void main() {
  final out = StringBuffer();
  
  final testCases = [
    "1 scoop whey with 150g tofu",
    "2 roti with 1 ladle rice with chana dal",
    "1 dominos pizza slice with 450ml mango shake",
    "paneer with rice",
    "dal chawal",
    "2 roti", // To test if name is empty
    "veg fried rice",
    "bread omelette",
    "1/2 plate chicken biryani",
  ];

  for (final raw in testCases) {
    out.writeln('\n=======================================');
    out.writeln('Testing Input: "$raw"');
    final parsed = ItemParser.parse(raw);
    for (final p in parsed) {
      out.writeln('  - $p');
    }
  }

  File('output_parse_utf8.txt').writeAsStringSync(out.toString());
}
