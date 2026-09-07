import '../models/exercise_definition.dart';
import '../models/workout_split.dart' show Exercise;
import 'exercise_library_service.dart';

/// Service managing exercise visual assets (thumbnails, animated GIFs),
/// official GymVisual attribution, canonical exercise identity resolution,
/// and CDN URL resolution.
class ExerciseMediaService {
  ExerciseMediaService._();
  static final ExerciseMediaService instance = ExerciseMediaService._();

  static const String cdnBaseImages =
      'https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@main/images';
  static const String cdnBaseVideos =
      'https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@main/videos';

  static const String rawBaseImages =
      'https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/images';
  static const String rawBaseVideos =
      'https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/videos';

  /// Mandatory GymVisual copyright attribution notice per dataset license.
  static const String attribution = '© Gym visual — gymvisual.com';

  /// Deterministic media mappings for the foundational exercises.
  /// Verified against GymVisual / openGym CDN repository.
  static const Map<String, ({String image, String gif})> _foundationalMediaMap = {
    'bench_press': (image: '0025-EIeI8Vf.jpg', gif: '0025-EIeI8Vf.gif'),
    'incline_db_press': (image: '0314-ns0SIbU.jpg', gif: '0314-ns0SIbU.gif'),
    'close_grip_bench': (image: '0025-EIeI8Vf.jpg', gif: '0025-EIeI8Vf.gif'),
    'pec_dec': (image: '0596-v3xmPAR.jpg', gif: '0596-v3xmPAR.gif'),
    'cable_chest_fly': (image: '0188-xLYSdtg.jpg', gif: '0188-xLYSdtg.gif'),
    'chest_dip': (image: '0251-9WTm7dq.jpg', gif: '0251-9WTm7dq.gif'),
    'dips': (image: '3287-LkoAWAE.jpg', gif: '3287-LkoAWAE.gif'),
    'deadlift': (image: '0032-ila4NZS.jpg', gif: '0032-ila4NZS.gif'),
    'rdl': (image: '0085-wQ2c4XD.jpg', gif: '0085-wQ2c4XD.gif'),
    'squat': (image: '0043-sA9xX0W.jpg', gif: '0043-sA9xX0W.gif'),
    'hack_squat': (image: '0046-5VCj6iH.jpg', gif: '0046-5VCj6iH.gif'),
    'leg_press': (image: '2287-V07qpXy.jpg', gif: '2287-V07qpXy.gif'),
    'leg_extension': (image: '0585-my33uHU.jpg', gif: '0585-my33uHU.gif'),
    'leg_curl': (image: '0586-17lJ1kr.jpg', gif: '0586-17lJ1kr.gif'),
    'standing_calf': (image: '1372-8ozhUIZ.jpg', gif: '1372-8ozhUIZ.gif'),
    'calf_raise': (image: '0088-ktsFQAZ.jpg', gif: '0088-ktsFQAZ.gif'),
    'adductor_machine': (image: '1712-hC6oYY5.jpg', gif: '1712-hC6oYY5.gif'),
    'bb_row': (image: '0027-eZyBC3j.jpg', gif: '0027-eZyBC3j.gif'),
    'db_row': (image: '0293-BJ0Hz5L.jpg', gif: '0293-BJ0Hz5L.gif'),
    'tbar_row': (image: '1349-BgljGjd.jpg', gif: '1349-BgljGjd.gif'),
    'seated_cable_row': (image: '0861-fUBheHs.jpg', gif: '0861-fUBheHs.gif'),
    'lat_pulldown': (image: '2330-LEprlgG.jpg', gif: '2330-LEprlgG.gif'),
    'pullups': (image: '3019-mExgrF9.jpg', gif: '3019-mExgrF9.gif'),
    'cable_pullover': (image: '1316-cA9FuWG.jpg', gif: '1316-cA9FuWG.gif'),
    'ohp': (image: '0091-gAeez7P.jpg', gif: '0091-gAeez7P.gif'),
    'arnold_press': (image: '2137-Xy4jlWA.jpg', gif: '2137-Xy4jlWA.gif'),
    'db_shoulder_press': (image: '0426-A6wtbuL.jpg', gif: '0426-A6wtbuL.gif'),
    'lateral_raise': (image: '0334-DsgkuIt.jpg', gif: '0334-DsgkuIt.gif'),
    'cable_lateral_raise': (image: '0178-goJ6ezq.jpg', gif: '0178-goJ6ezq.gif'),
    'face_pull': (image: '0233-ZfyAGhK.jpg', gif: '0233-ZfyAGhK.gif'), // Cable Standing Rear Delt Row (with Rope)
    'rear_delt_fly': (image: '1022-tc5dYrf.jpg', gif: '1022-tc5dYrf.gif'),
    'shrugs': (image: '0406-NJzBsGJ.jpg', gif: '0406-NJzBsGJ.gif'),
    'bb_curl': (image: '2407-aee2Fcj.jpg', gif: '2407-aee2Fcj.gif'),
    'db_curl': (image: '0294-G7dY8zE.jpg', gif: '0294-G7dY8zE.gif'),
    'hammer_curl': (image: '0313-slDvUAU.jpg', gif: '0313-slDvUAU.gif'),
    'incline_db_curl': (image: '0315-G09xWwN.jpg', gif: '0315-G09xWwN.gif'),
    'cable_curl': (image: '0868-G08RZcQ.jpg', gif: '0868-G08RZcQ.gif'),
    'tri_pushdown': (image: '1723-qRZ5S1N.jpg', gif: '1723-qRZ5S1N.gif'),
    'overhead_tri_ext': (image: '1722-1xHyxys.jpg', gif: '1722-1xHyxys.gif'),
    'skullcrusher': (image: '0061-iZop9xO.jpg', gif: '0061-iZop9xO.gif'),
  };

  /// Centralized canonical alias dictionary mapping gym aliases, alternate namings,
  /// and legacy workout IDs directly to their canonical foundational identity.
  static const Map<String, String> _canonicalAliasMap = {
    // Face Pull aliases
    'face_pull': 'face_pull',
    'face pull': 'face_pull',
    'face pulls': 'face_pull',
    'cable face pull': 'face_pull',
    'cable face pulls': 'face_pull',
    'rope face pull': 'face_pull',
    'rope face pulls': 'face_pull',
    'facepull': 'face_pull',
    'facepulls': 'face_pull',
    'face-pull': 'face_pull',
    'face-pulls': 'face_pull',
    'cable rope face pull': 'face_pull',
    'cable rope face pulls': 'face_pull',
    'cable standing rear delt row with rope': 'face_pull',
    'cable rear delt row with rope': 'face_pull',
    'standing face pull': 'face_pull',
    'standing face pulls': 'face_pull',

    // Overhead Tricep Extension aliases
    'overhead_tri_ext': 'overhead_tri_ext',
    'overhead tricep extension': 'overhead_tri_ext',
    'overhead triceps extension': 'overhead_tri_ext',
    'cable high pulley overhead tricep extension': 'overhead_tri_ext',
    'cable overhead tricep extension': 'overhead_tri_ext',
    'cable overhead triceps extension': 'overhead_tri_ext',
    'cable rope high pulley overhead tricep extension': 'overhead_tri_ext',
    'db overhead tricep extension': 'overhead_tri_ext',
    'dumbbell overhead tricep extension': 'overhead_tri_ext',
    'dumbbell seated reverse grip one arm overhead tricep extension': 'overhead_tri_ext',
    'barbell seated overhead triceps extension': 'overhead_tri_ext',
    'barbell standing overhead triceps extension': 'overhead_tri_ext',
    'overhead tricep ext': 'overhead_tri_ext',
    'tricep overhead extension': 'overhead_tri_ext',

    // Bench Press aliases
    'bench_press': 'bench_press',
    'bench press': 'bench_press',
    'barbell bench press': 'bench_press',
    'bb bench press': 'bench_press',
    'flat bench press': 'bench_press',
    'barbell flat bench press': 'bench_press',
    'barbell bench': 'bench_press',
    'flat bench': 'bench_press',

    // Incline DB Press aliases
    'incline_db_press': 'incline_db_press',
    'incline db press': 'incline_db_press',
    'incline dumbbell press': 'incline_db_press',
    'incline dumbbell bench press': 'incline_db_press',
    'dumbbell incline bench press': 'incline_db_press',
    'db incline press': 'incline_db_press',

    // Close Grip Bench aliases
    'close_grip_bench': 'close_grip_bench',
    'close grip bench': 'close_grip_bench',
    'close-grip bench press': 'close_grip_bench',
    'close grip bench press': 'close_grip_bench',
    'cgbp': 'close_grip_bench',

    // Lat Pulldown aliases
    'lat_pulldown': 'lat_pulldown',
    'lat pulldown': 'lat_pulldown',
    'lat pull down': 'lat_pulldown',
    'cable lat pulldown': 'lat_pulldown',
    'wide grip lat pulldown': 'lat_pulldown',

    // T-Bar Row aliases
    'tbar_row': 'tbar_row',
    't-bar row': 'tbar_row',
    't bar row': 'tbar_row',
    'tbar row': 'tbar_row',
    't-bar row with handle': 'tbar_row',

    // Barbell Bent Over Row aliases
    'bb_row': 'bb_row',
    'barbell row': 'bb_row',
    'barbell bent over row': 'bb_row',
    'bent over row': 'bb_row',
    'bb row': 'bb_row',

    // Dumbbell Row aliases
    'db_row': 'db_row',
    'dumbbell row': 'db_row',
    'dumbbell bent over row': 'db_row',
    'single arm db row': 'db_row',
    'one arm dumbbell row': 'db_row',

    // Seated Cable Row aliases
    'seated_cable_row': 'seated_cable_row',
    'seated cable row': 'seated_cable_row',
    'cable seated row': 'seated_cable_row',
    'cable row': 'seated_cable_row',

    // Overhead Press aliases
    'ohp': 'ohp',
    'overhead press': 'ohp',
    'standing overhead press': 'ohp',
    'standing military press': 'ohp',
    'military press': 'ohp',
    'barbell overhead press': 'ohp',

    // Lateral Raise aliases
    'lateral_raise': 'lateral_raise',
    'lateral raise': 'lateral_raise',
    'dumbbell lateral raise': 'lateral_raise',
    'db lateral raise': 'lateral_raise',
    'side lateral raise': 'lateral_raise',

    // Cable Lateral Raise aliases
    'cable_lateral_raise': 'cable_lateral_raise',
    'cable lateral raise': 'cable_lateral_raise',

    // Tricep Pushdown aliases
    'tri_pushdown': 'tri_pushdown',
    'tricep pushdown': 'tri_pushdown',
    'triceps pushdown': 'tri_pushdown',
    'cable pushdown': 'tri_pushdown',
    'cable tricep pushdown': 'tri_pushdown',
    'rope pushdown': 'tri_pushdown',

    // Skullcrusher aliases
    'skullcrusher': 'skullcrusher',
    'skull crusher': 'skullcrusher',
    'skull crushers': 'skullcrusher',
    'skullcrushers': 'skullcrusher',
    'lying triceps extension': 'skullcrusher',

    // Barbell Curl aliases
    'bb_curl': 'bb_curl',
    'barbell curl': 'bb_curl',
    'bb curl': 'bb_curl',
    'bicep curl': 'bb_curl',

    // Dumbbell Curl aliases
    'db_curl': 'db_curl',
    'dumbbell curl': 'db_curl',
    'db curl': 'db_curl',

    // Hammer Curl aliases
    'hammer_curl': 'hammer_curl',
    'hammer curl': 'hammer_curl',
    'dumbbell hammer curl': 'hammer_curl',

    // Incline DB Curl aliases
    'incline_db_curl': 'incline_db_curl',
    'incline db curl': 'incline_db_curl',
    'incline dumbbell curl': 'incline_db_curl',

    // Cable Curl aliases
    'cable_curl': 'cable_curl',
    'cable curl': 'cable_curl',

    // Squat aliases
    'squat': 'squat',
    'barbell squat': 'squat',
    'barbell back squat': 'squat',
    'back squat': 'squat',

    // Deadlift aliases
    'deadlift': 'deadlift',
    'barbell deadlift': 'deadlift',
    'conventional deadlift': 'deadlift',

    // Romanian Deadlift aliases
    'rdl': 'rdl',
    'romanian deadlift': 'rdl',
    'barbell romanian deadlift': 'rdl',
    'stiff leg deadlift': 'rdl',
    'sldl': 'rdl',

    // Pec Dec aliases
    'pec_dec': 'pec_dec',
    'pec dec': 'pec_dec',
    'pec deck': 'pec_dec',
    'seated machine fly': 'pec_dec',

    // Cable Chest Fly aliases
    'cable_chest_fly': 'cable_chest_fly',
    'cable chest fly': 'cable_chest_fly',
    'cable fly': 'cable_chest_fly',

    // Dips aliases
    'dips': 'dips',
    'dip': 'dips',
    'chest dip': 'chest_dip',
    'chest_dip': 'chest_dip',

    // Pullups aliases
    'pullups': 'pullups',
    'pull up': 'pullups',
    'pull-up': 'pullups',
    'pull ups': 'pullups',
    'chin up': 'pullups',
    'chin-up': 'pullups',

    // Cable Pullover aliases
    'cable_pullover': 'cable_pullover',
    'cable pullover': 'cable_pullover',
    'pullover': 'cable_pullover',

    // Leg Extension aliases
    'leg_extension': 'leg_extension',
    'leg extension': 'leg_extension',

    // Leg Curl aliases
    'leg_curl': 'leg_curl',
    'leg curl': 'leg_curl',
    'lying leg curl': 'leg_curl',

    // Leg Press aliases
    'leg_press': 'leg_press',
    'leg press': 'leg_press',

    // Hack Squat aliases
    'hack_squat': 'hack_squat',
    'hack squat': 'hack_squat',

    // Calf Raise aliases
    'calf_raise': 'calf_raise',
    'calf raise': 'calf_raise',
    'standing calf': 'standing_calf',
    'standing_calf': 'standing_calf',
    'standing calf raise': 'standing_calf',

    // Rear Delt Fly aliases
    'rear_delt_fly': 'rear_delt_fly',
    'rear delt fly': 'rear_delt_fly',
    'reverse fly': 'rear_delt_fly',
    'dumbbell rear delt fly': 'rear_delt_fly',

    // Shrugs aliases
    'shrugs': 'shrugs',
    'shrug': 'shrugs',
    'dumbbell shrug': 'shrugs',
    'barbell shrug': 'shrugs',

    // Adductor Machine aliases
    'adductor_machine': 'adductor_machine',
    'adductor': 'adductor_machine',
    'adductor machine': 'adductor_machine',

    // Arnold Press aliases
    'arnold_press': 'arnold_press',
    'arnold press': 'arnold_press',
  };

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Resolves the canonical media filenames for any exercise input.
  /// Resolution priority:
  /// 1. Explicit openGym media on [definition] or catalog item
  /// 2. Canonical exercise ID in [_foundationalMediaMap]
  /// 3. Normalized alias / synonym dictionary match
  /// 4. Normalized exercise name match against catalog definitions
  /// 5. Graceful fallback (null)
  ({String? image, String? gif, String? canonicalId}) resolveMedia({
    ExerciseDefinition? definition,
    Exercise? exercise,
    String? id,
    String? name,
  }) {
    // 1. Explicit openGym media on definition
    if (definition != null) {
      final img = definition.imageRef;
      final gf = definition.gifRef;
      if (img != null && img.isNotEmpty && gf != null && gf.isNotEmpty) {
        return (image: img, gif: gf, canonicalId: definition.id);
      }
    }

    final effectiveId = id ?? exercise?.id ?? definition?.id ?? '';
    final effectiveName = name ?? exercise?.name ?? definition?.name ?? '';

    // Check catalog definition for explicit openGym media by ID
    if (effectiveId.isNotEmpty) {
      final catDef = ExerciseLibraryService.instance.getById(effectiveId);
      if (catDef != null &&
          catDef.imageRef != null &&
          catDef.imageRef!.isNotEmpty &&
          catDef.gifRef != null &&
          catDef.gifRef!.isNotEmpty) {
        return (image: catDef.imageRef, gif: catDef.gifRef, canonicalId: catDef.id);
      }
    }

    // 2. Canonical exercise ID in foundational map
    if (effectiveId.isNotEmpty && _foundationalMediaMap.containsKey(effectiveId)) {
      final mapped = _foundationalMediaMap[effectiveId]!;
      return (image: mapped.image, gif: mapped.gif, canonicalId: effectiveId);
    }

    // 3. Normalized alias / synonym dictionary match
    final normId = _normalize(effectiveId);
    final normName = _normalize(effectiveName);

    final mappedId = _canonicalAliasMap[effectiveId.toLowerCase()] ??
        _canonicalAliasMap[normId] ??
        _canonicalAliasMap[normName];

    if (mappedId != null && _foundationalMediaMap.containsKey(mappedId)) {
      final mapped = _foundationalMediaMap[mappedId]!;
      return (image: mapped.image, gif: mapped.gif, canonicalId: mappedId);
    }

    // 4. Normalized exercise name matching against catalog definitions
    if (normName.isNotEmpty) {
      for (final def in ExerciseLibraryService.instance.allDefinitions) {
        if (_normalize(def.canonicalName) == normName ||
            _normalize(def.displayName) == normName ||
            def.aliases.any((a) => _normalize(a) == normName)) {
          if (def.imageRef != null &&
              def.imageRef!.isNotEmpty &&
              def.gifRef != null &&
              def.gifRef!.isNotEmpty) {
            return (image: def.imageRef, gif: def.gifRef, canonicalId: def.id);
          }
          if (_foundationalMediaMap.containsKey(def.id)) {
            final mapped = _foundationalMediaMap[def.id]!;
            return (image: mapped.image, gif: mapped.gif, canonicalId: def.id);
          }
        }
      }
    }

    // 5. Fallback: Check if definition had only an image or only a gif
    if (definition != null) {
      return (image: definition.imageRef, gif: definition.gifRef, canonicalId: definition.id);
    }

    return (image: null, gif: null, canonicalId: null);
  }

  /// Resolves the static image/thumbnail URL.
  String? getThumbnailUrl([dynamic target, String? name]) {
    ExerciseDefinition? def;
    Exercise? ex;
    String? id;
    String? n = name;

    if (target is ExerciseDefinition) {
      def = target;
    } else if (target is Exercise) {
      ex = target;
    } else if (target is String) {
      if (target.contains('_') || _foundationalMediaMap.containsKey(target) || RegExp(r'^\d{4}$').hasMatch(target)) {
        id = target;
      } else {
        n ??= target;
        id = target;
      }
    }

    final res = resolveMedia(definition: def, exercise: ex, id: id, name: n);
    if (res.image != null && res.image!.isNotEmpty) {
      return '$cdnBaseImages/${res.image}';
    }
    return null;
  }

  /// Resolves the animated GIF demonstration URL.
  String? getAnimationUrl([dynamic target, String? name]) {
    ExerciseDefinition? def;
    Exercise? ex;
    String? id;
    String? n = name;

    if (target is ExerciseDefinition) {
      def = target;
    } else if (target is Exercise) {
      ex = target;
    } else if (target is String) {
      if (target.contains('_') || _foundationalMediaMap.containsKey(target) || RegExp(r'^\d{4}$').hasMatch(target)) {
        id = target;
      } else {
        n ??= target;
        id = target;
      }
    }

    final res = resolveMedia(definition: def, exercise: ex, id: id, name: n);
    if (res.gif != null && res.gif!.isNotEmpty) {
      return '$cdnBaseVideos/${res.gif}';
    }
    return null;
  }

  /// Returns true if the exercise has visual media available.
  bool hasMedia([dynamic target, String? name]) {
    ExerciseDefinition? def;
    Exercise? ex;
    String? id;
    String? n = name;

    if (target is ExerciseDefinition) {
      def = target;
    } else if (target is Exercise) {
      ex = target;
    } else if (target is String) {
      if (target.contains('_') || _foundationalMediaMap.containsKey(target) || RegExp(r'^\d{4}$').hasMatch(target)) {
        id = target;
      } else {
        n ??= target;
        id = target;
      }
    }

    final res = resolveMedia(definition: def, exercise: ex, id: id, name: n);
    return (res.gif != null && res.gif!.isNotEmpty) ||
        (res.image != null && res.image!.isNotEmpty);
  }
}
