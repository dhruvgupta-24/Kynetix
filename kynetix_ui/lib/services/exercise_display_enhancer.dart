import '../models/exercise_definition.dart';
import 'exercise_query_normalizer.dart';

/// Enhances [ExerciseDefinition] instances with human-friendly display names,
/// natural gym aliases, acronyms, and precomputed normalized search tokens.
/// Decoupled and extensible without altering raw JSON catalog integrity.
class ExerciseDisplayEnhancer {
  ExerciseDisplayEnhancer._();

  /// Curated alias expansions for high-frequency exercise patterns.
  static const Map<String, List<String>> _knownPatternAliases = {
    't bar': [
      't-bar row',
      'tbar row',
      't bar',
      'tbar',
      'landmine row',
      'chest supported t bar',
      'machine t bar row',
    ],
    't-bar': [
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
    'skull crusher': [
      'skullcrusher',
      'lying triceps extension',
      'ez bar skull crusher',
    ],
  };

  /// Derives a clean human-friendly display name.
  static String deriveDisplayName(String rawName, String equipment) {
    if (rawName.isEmpty) return '';

    var clean = rawName.trim();

    // Clean Lever prefixes if raw
    if (clean.toLowerCase().startsWith('lever t bar row') ||
        clean.toLowerCase().startsWith('lever t-bar row')) {
      return 'T-Bar Row (Machine)';
    }
    if (clean.toLowerCase().startsWith('lever seated row')) {
      return 'Chest-Supported Machine Row';
    }
    if (clean.toLowerCase().startsWith('lever alternating narrow grip seated row')) {
      return 'Single-Arm Machine Row';
    }

    // Capitalize properly
    final words = clean.split(' ');
    final capitalized = words.map((w) {
      if (w.isEmpty) return '';
      if (w.toLowerCase() == 'db') return 'DB';
      if (w.toLowerCase() == 'bb') return 'BB';
      if (w.toLowerCase() == 'ohp') return 'OHP';
      if (w.toLowerCase() == 'rdl') return 'RDL';
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
