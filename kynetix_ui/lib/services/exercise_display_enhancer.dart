import '../models/exercise_definition.dart';
import 'exercise_query_normalizer.dart';

/// Enhances [ExerciseDefinition] instances with human-friendly display names,
/// natural gym aliases, acronyms, and precomputed normalized search tokens.
/// Decoupled and extensible without altering raw JSON catalog integrity.
class ExerciseDisplayEnhancer {
  ExerciseDisplayEnhancer._();

  /// Curated alias expansions for high-frequency exercise patterns.
  static const Map<String, List<String>> _knownPatternAliases = {
    't bar row': [
      't-bar row',
      'tbar row',
      't bar',
      'tbar',
      'landmine row',
      'chest supported t bar',
      'machine t bar row',
    ],
    't-bar row': [
      't-bar row',
      'tbar row',
      't bar',
      'tbar',
      'landmine row',
      'chest supported t bar',
    ],
    'bench press': [
      'flat bench',
      'barbell bench',
      'bb bench',
      'chest press',
      'bench',
    ],
    'incline bench press': [
      'incline bench',
      'incline barbell bench',
      'incline bb press',
      'incline press',
    ],
    'incline dumbbell press': [
      'incline db press',
      'incline db bench',
      'incline dumbbell press',
      'db incline bench',
      'db incline press',
      'incline dumbbell bench press',
    ],
    'incline dumbbell bench press': [
      'incline db press',
      'incline db bench',
      'incline dumbbell press',
      'db incline bench',
      'db incline press',
    ],
    'incline dumbbell curl': [
      'incline db curl',
      'incline dumbbell bicep curl',
      'incline curl',
    ],
    'incline dumbbell fly': [
      'incline db fly',
      'incline dumbbell flyes',
    ],
    'dumbbell bench press': [
      'db bench',
      'flat db press',
      'dumbbell bench',
      'db chest press',
    ],
    'lat pulldown': [
      'lat pull',
      'lat pull down',
      'pulldown',
      'cable pulldown',
      'wide grip pulldown',
    ],
    'overhead press': [
      'ohp',
      'shoulder press',
      'military press',
      'barbell overhead press',
      'bb ohp',
      'standing overhead press',
    ],
    'romanian deadlift': [
      'rdl',
      'romanian dl',
      'barbell rdl',
      'dumbbell rdl',
      'stiff leg deadlift',
    ],
    'deadlift': [
      'conventional deadlift',
      'conventional dl',
      'barbell deadlift',
      'bb deadlift',
    ],
    'squat': [
      'barbell back squat',
      'back squat',
      'bb squat',
      'squats',
    ],
    'front squat': [
      'barbell front squat',
      'bb front squat',
    ],
    'bent over row': [
      'barbell row',
      'bb row',
      'pendlay row',
      'bent over barbell row',
    ],
    'seated cable row': [
      'cable row',
      'seated row',
      'low cable row',
      'horizontal row',
    ],
    'cable seated row': [
      'cable row',
      'seated cable row',
      'seated row',
      'low cable row',
    ],
    'chest dip': [
      'dips',
      'chest dips',
      'bodyweight dips',
      'parallel bar dips',
    ],
    'pull up': [
      'pullup',
      'pull-up',
      'chin up',
      'chinup',
      'pullups',
    ],
    'push up': [
      'pushup',
      'push-up',
      'press up',
      'pushups',
    ],
    'tricep pushdown': [
      'triceps pushdown',
      'cable pushdown',
      'rope pushdown',
      'straight bar pushdown',
    ],
    'bicep curl': [
      'biceps curl',
      'barbell curl',
      'bb curl',
      'dumbbell curl',
      'db curl',
      'arm curl',
    ],
    'biceps curl': [
      'bicep curl',
      'barbell curl',
      'bb curl',
      'dumbbell curl',
      'db curl',
      'arm curl',
    ],
    'dumbbell bicep curl': [
      'dumbbell curl',
      'db curl',
      'db bicep curl',
      'dumbbell biceps curl',
    ],
    'dumbbell biceps curl': [
      'dumbbell curl',
      'db curl',
      'db bicep curl',
      'bicep curl',
    ],
    'lateral raise': [
      'side lateral raise',
      'dumbbell lateral raise',
      'db lateral raise',
      'side raise',
      'delt raise',
    ],
    'face pull': [
      'cable face pull',
      'rope face pull',
      'rear delt face pull',
    ],
    'leg press': [
      'machine leg press',
      'sled leg press',
      '45 degree leg press',
    ],
    'leg extension': [
      'quad extension',
      'machine leg extension',
    ],
    'leg curl': [
      'hamstring curl',
      'seated leg curl',
      'lying leg curl',
    ],
    'calf raise': [
      'standing calf raise',
      'seated calf raise',
      'calves',
    ],
    'preacher curl': [
      'ez bar preacher curl',
      'barbell preacher curl',
      'dumbbell preacher curl',
    ],
    'skull crusher': [
      'skullcrusher',
      'lying triceps extension',
      'ez bar skull crusher',
    ],
    'pec deck': [
      'pec dec',
      'pec deck fly',
      'machine fly',
      'butterfly machine',
      'chest fly machine',
      'seated chest fly',
    ],
    'pec dec': [
      'pec deck',
      'pec deck fly',
      'machine fly',
      'butterfly machine',
      'chest fly machine',
    ],
  };

  /// Derives a clean human-friendly display name.
  static String deriveDisplayName(String rawName, String equipment) {
    if (rawName.isEmpty) return '';

    var clean = rawName.trim();

    // Specific cleanups for common verbose catalog entries
    final lower = clean.toLowerCase();
    if (lower == 't-bar row' || lower == 't bar row') {
      return 'T-Bar Row';
    }
    if (lower.startsWith('lever t bar row') || lower.startsWith('lever t-bar row') || lower.startsWith('lever reverse t-bar row')) {
      if (lower.contains('reverse')) {
        return 'Machine Reverse T-Bar Row';
      }
      return 'T-Bar Row (Machine)';
    }
    if (lower.startsWith('lever seated row')) {
      return 'Chest-Supported Machine Row';
    }
    if (lower.startsWith('lever alternating narrow grip seated row')) {
      return 'Single-Arm Machine Row';
    }
    if (lower == 'cable lat pulldown full range of motion') {
      return 'Cable Lat Pulldown';
    }
    if (lower == 'cable seated row') {
      return 'Seated Cable Row';
    }
    if (lower == 'dumbbell side lateral raise' || lower == 'side lateral raise') {
      return 'Dumbbell Lateral Raise';
    }
    if (lower == 'barbell standing overhead press') {
      return 'Standing Overhead Press';
    }
    if (lower == 'barbell bent over row reverse grip') {
      return 'Reverse Grip Barbell Row';
    }
    if (lower == 'dumbbell incline bench press') {
      return 'Incline Dumbbell Press';
    }
    if (lower == 'dumbbell biceps curl') {
      return 'Dumbbell Bicep Curl';
    }
    if (lower == 'barbell biceps curl') {
      return 'Barbell Bicep Curl';
    }
    if (lower.contains('bench press - medium grip') || lower.contains('bench press medium grip')) {
      return 'Barbell Bench Press (Medium Grip)';
    }
    if (lower.contains('bench press - wide grip') || lower.contains('bench press wide grip')) {
      return 'Barbell Bench Press (Wide Grip)';
    }
    if (lower.contains('twin handle parallel grip lat pulldown')) {
      return 'Twin-Handle Lat Pulldown (Parallel Grip)';
    }
    if (lower == 'lever seated fly' || lower == 'lever seated fly (pec deck)' || lower == 'pec dec machine' || lower == 'pec deck fly') {
      return 'Pec Deck Fly (Machine)';
    }

    // Capitalize properly
    final words = clean.split(' ');
    final capitalized = words.map((w) {
      if (w.isEmpty) return '';
      if (w.toLowerCase() == 'db') return 'DB';
      if (w.toLowerCase() == 'bb') return 'BB';
      if (w.toLowerCase() == 'ohp') return 'OHP';
      if (w.toLowerCase() == 'rdl') return 'RDL';
      if (w.toLowerCase() == 't-bar' || w.toLowerCase() == 't-bar,') return 'T-Bar';
      if (w.startsWith('(') && w.endsWith(')')) {
        return '(${w.substring(1, 2).toUpperCase()}${w.substring(2, w.length - 1).toLowerCase()})';
      }
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');

    return capitalized;
  }

  /// Builds a comprehensive alias set for an exercise.
  static List<String> buildEnhancedAliases(ExerciseDefinition def) {
    final aliasSet = <String>{};

    // 1. Existing aliases from definition
    for (final a in def.aliases) {
      final norm = ExerciseQueryNormalizer.normalize(a);
      if (norm.isNotEmpty) aliasSet.add(norm);
    }

    // 2. Normalized name and display name
    final normName = ExerciseQueryNormalizer.normalize(def.name);
    final normDisplay = ExerciseQueryNormalizer.normalize(def.displayName);
    if (normName.isNotEmpty) aliasSet.add(normName);
    if (normDisplay.isNotEmpty) aliasSet.add(normDisplay);

    // 3. Match against known gym pattern dictionary with strict word boundaries
    final nameJoined = ' $normName $normDisplay ';
    
    for (final entry in _knownPatternAliases.entries) {
      final key = entry.key;
      if (nameJoined.contains(' $key ') ||
          normName == key ||
          normDisplay == key ||
          normName.startsWith('$key ') ||
          normDisplay.startsWith('$key ') ||
          normName.endsWith(' $key') ||
          normDisplay.endsWith(' $key')) {
        for (final alias in entry.value) {
          final normAlias = ExerciseQueryNormalizer.normalize(alias);
          if (normAlias.isNotEmpty) aliasSet.add(normAlias);
        }
      }
    }

    // 4. Handle "T-Bar" / "T Bar" / "Tbar" variations specifically
    if (nameJoined.contains(' t bar ') ||
        nameJoined.contains(' t-bar ') ||
        nameJoined.contains(' tbar ') ||
        def.id.contains('tbar') ||
        def.id.contains('t_bar') ||
        normName.startsWith('t bar') ||
        normName.startsWith('t-bar') ||
        normDisplay.startsWith('t bar') ||
        normDisplay.startsWith('t-bar')) {
      aliasSet.add('t-bar');
      aliasSet.add('t bar');
      aliasSet.add('tbar');
      aliasSet.add('t-bar row');
      aliasSet.add('t bar row');
      aliasSet.add('tbar row');
    }

    // 5. Equipment shorthand combinations
    if (def.equipment.toLowerCase().contains('dumbbell') || def.name.toLowerCase().contains('dumbbell')) {
      final nameWithDb = def.name.toLowerCase().replaceAll('dumbbell', 'db');
      aliasSet.add(ExerciseQueryNormalizer.normalize(nameWithDb));
    }
    if (def.equipment.toLowerCase().contains('barbell') || def.name.toLowerCase().contains('barbell')) {
      final nameWithBb = def.name.toLowerCase().replaceAll('barbell', 'bb');
      aliasSet.add(ExerciseQueryNormalizer.normalize(nameWithBb));
    }

    return aliasSet.toList();
  }
}
