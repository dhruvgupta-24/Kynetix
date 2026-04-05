import 'package:flutter/foundation.dart';
import 'parser_lexicon.dart';

class ParsedFoodItem {
  final String rawChunk;
  final String normalizedName;
  final double quantity;
  final String unit;

  const ParsedFoodItem({
    required this.rawChunk,
    required this.normalizedName,
    required this.quantity,
    required this.unit,
  });

  @override
  String toString() => 'ParsedFoodItem($normalizedName, qty: $quantity, unit: $unit)';
}

class ItemParser {
  /// Splits raw input deterministically and extracts quantity per chunk.
  static List<ParsedFoodItem> parse(String rawInput) {
    String text = rawInput.toLowerCase().trim();
    if (text.isEmpty) return [];

    debugPrint('[ItemParser] Input: "$rawInput"');

    // 1. Explicit Delimiter Split
    // Replace all explicit delimiters with a unique separator '|'
    for (final delimiter in ParserLexicon.delimiters) {
      text = text.replaceAll(delimiter, '|');
    }

    // 2. Implicit Pairing Split
    // Replace implicit pairs (e.g., 'dal chawal') with 'dal | chawal'
    // To ensure whole word matching, we can match and replace.
    ParserLexicon.implicitPairs.forEach((pairString, parts) {
      if (text.contains(pairString)) {
        text = text.replaceAll(pairString, parts.join('|'));
      }
    });

    // We now split by '|'
    final rawChunks = text.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    debugPrint('[ItemParser] Raw Chunks: $rawChunks');

    // 3. Extract quantity per chunk
    final parsedItems = <ParsedFoodItem>[];
    for (final chunk in rawChunks) {
      final parsed = _extractQuantityAndName(chunk);
      parsedItems.add(parsed);
    }

    return parsedItems;
  }

  static ParsedFoodItem _extractQuantityAndName(String chunk) {
    double qty = 1.0;
    String unit = 'serving';
    String name = chunk;

    // Handle fractional words first (half, quarter, etc.)
    bool handledFractions = false;
    for (final entry in ParserLexicon.fractions.entries) {
      if (chunk.startsWith('${entry.key} ')) {
        qty = entry.value;
        name = chunk.substring(entry.key.length).trim();
        handledFractions = true;
        break;
      }
    }

    // Handle numerical prefixes if fractions didn't match.
    // e.g., "1.5 cup rice", "1 scoop whey"
    if (!handledFractions) {
      final numberMatch = RegExp(r'^([0-9]*\.?[0-9]+)\s+(.*)').firstMatch(chunk);
      if (numberMatch != null) {
        final parsedNum = double.tryParse(numberMatch.group(1) ?? '');
        if (parsedNum != null) {
          qty = parsedNum;
          name = numberMatch.group(2)?.trim() ?? '';
        }
      }
    }

    // Now, if 'name' starts or ends with a known unit, extract it.
    // "scoop whey" -> unit: scoop, name: whey
    // "chapatis 2" -> wait, if "2 chapatis" was handled, number extracted, name "chapatis".
    // We check if the name consists of a unit ONLY or Starts with a unit.
    bool unitFound = false;
    
    // Sort units by length descending so "tablespoon" matches before "tbsp" or "spoon"
    final sortedUnits = ParserLexicon.commonUnits.toList()..sort((a, b) => b.length.compareTo(a.length));
    
    for (final u in sortedUnits) {
      // Unit at start: "scoop whey"
      if (name.startsWith('$u ')) {
        unit = u;
        name = name.substring(u.length).trim();
        unitFound = true;
        break;
      }
      // Unit at the end: "dominos pizza slice"
      if (name.endsWith(' $u')) {
        unit = u;
        name = name.substring(0, name.length - u.length - 1).trim();
        unitFound = true;
        break;
      }
    }

    // Handle things like "150g tofu"
    // If the chunk started with "150g", the previous regex wouldn't catch it because of missing space!
    // Let's refine the number matcher to handle optional space.
    if (!handledFractions && qty == 1.0 && !unitFound) {
      final tightNumberUnitMatch = RegExp(r'^([0-9]*\.?[0-9]+)([a-zA-Z]+)\s*(.*)').firstMatch(chunk);
      if (tightNumberUnitMatch != null) {
        final parsedNum = double.tryParse(tightNumberUnitMatch.group(1) ?? '');
        final matchedUnit = tightNumberUnitMatch.group(2) ?? '';
        final rest = tightNumberUnitMatch.group(3) ?? '';
        
        if (parsedNum != null && ParserLexicon.commonUnits.contains(matchedUnit)) {
          qty = parsedNum;
          unit = matchedUnit;
          name = rest.isEmpty ? matchedUnit : rest; // if it was just "150g", name is "g"? No name should be rawChunk.
          unitFound = true;
        }
      }
    }

    // Handle trailing units? E.g., "pizza slice" -> "slice" is unit?
    // User requested "Unknown Multi-Word Handling". "pizza slice" is protected or left as is.
    // So if name doesn't start with unit, leave it alone.
    
    // Clean up generic leading/trailing hyphens etc just in case
    name = name.replaceAll(RegExp(r'^-+|-+$'), '').trim();
    if (name.isEmpty) {
      name = chunk; // Fallback
    }

    return ParsedFoodItem(
      rawChunk: chunk,
      normalizedName: name,
      quantity: qty,
      unit: unit,
    );
  }
}
