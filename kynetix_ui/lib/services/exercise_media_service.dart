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

  /// The raw GitHub copy of a jsDelivr media url, used as a single retry
  /// when the CDN fails. Returns null for urls that are not dataset media.
  static String? mirrorUrlFor(String url) {
    if (url.startsWith('$cdnBaseVideos/')) {
      return '$rawBaseVideos/${url.substring(cdnBaseVideos.length + 1)}';
    }
    if (url.startsWith('$cdnBaseImages/')) {
      return '$rawBaseImages/${url.substring(cdnBaseImages.length + 1)}';
    }
    return null;
  }

  /// Mandatory GymVisual copyright attribution notice per dataset license.
  static const String attribution = '© Gym visual, gymvisual.com';

  /// Explicit media for the app's own (non-numeric) exercise ids: the
  /// foundational library, the day library and the Developer's Choice split.
  ///
  /// Every entry was checked against the dataset index
  /// (data/exercises.json in hasaneyldrm/exercises-dataset) and by eye
  /// against the GIF frames, so the equipment, grip and bench angle match
  /// the exercise name. These win over any media refs on a definition.
  /// The trailing comment is the dataset's own exercise name.
  static const Map<String, ({String image, String gif})> _foundationalMediaMap = {
    // Chest
    'bench_press': (image: '0025-EIeI8Vf.jpg', gif: '0025-EIeI8Vf.gif'), // barbell bench press
    'flat_bench_press': (image: '0025-EIeI8Vf.jpg', gif: '0025-EIeI8Vf.gif'), // barbell bench press
    'incline_bench_press': (image: '0047-3TZduzM.jpg', gif: '0047-3TZduzM.gif'), // barbell incline bench press
    'incline_db_press': (image: '0314-ns0SIbU.jpg', gif: '0314-ns0SIbU.gif'), // dumbbell incline bench press
    'close_grip_bench': (image: '0030-J6Dx1Mu.jpg', gif: '0030-J6Dx1Mu.gif'), // barbell close-grip bench press
    'pec_dec': (image: '0596-v3xmPAR.jpg', gif: '0596-v3xmPAR.gif'), // lever seated fly
    'cable_chest_fly': (image: '0188-xLYSdtg.jpg', gif: '0188-xLYSdtg.gif'), // cable middle fly
    'chest_dip': (image: '0251-9WTm7dq.jpg', gif: '0251-9WTm7dq.gif'), // chest dip
    'dips': (image: '0814-X6C6i5Y.jpg', gif: '0814-X6C6i5Y.gif'), // triceps dip
    // Legs
    'deadlift': (image: '0032-ila4NZS.jpg', gif: '0032-ila4NZS.gif'), // barbell deadlift
    'rdl': (image: '0085-wQ2c4XD.jpg', gif: '0085-wQ2c4XD.gif'), // barbell romanian deadlift
    'squat': (image: '0043-qXTaZnJ.jpg', gif: '0043-qXTaZnJ.gif'), // barbell full squat
    'hack_squat': (image: '0743-Qa55kX1.jpg', gif: '0743-Qa55kX1.gif'), // sled hack squat
    'leg_press': (image: '0739-10Z2DXU.jpg', gif: '0739-10Z2DXU.gif'), // sled 45 degree leg press
    'leg_extension': (image: '0585-my33uHU.jpg', gif: '0585-my33uHU.gif'), // lever leg extension
    'leg_curl': (image: '0586-17lJ1kr.jpg', gif: '0586-17lJ1kr.gif'), // lever lying leg curl
    'standing_calf': (image: '0605-ykUOVze.jpg', gif: '0605-ykUOVze.gif'), // lever standing calf raise
    'calf_raise': (image: '0594-bOOdeyc.jpg', gif: '0594-bOOdeyc.gif'), // lever seated calf raise
    'adductor_machine': (image: '0598-oHsrypV.jpg', gif: '0598-oHsrypV.gif'), // lever seated hip adduction
    // Back
    'bb_row': (image: '0027-eZyBC3j.jpg', gif: '0027-eZyBC3j.gif'), // barbell bent over row
    'db_row': (image: '0292-C0MA9bC.jpg', gif: '0292-C0MA9bC.gif'), // dumbbell one arm bent-over row
    'tbar_row': (image: '0606-aaXr7ld.jpg', gif: '0606-aaXr7ld.gif'), // lever t bar row
    'seated_cable_row': (image: '0861-fUBheHs.jpg', gif: '0861-fUBheHs.gif'), // cable seated row
    'close_grip_cable_row': (image: '0861-fUBheHs.jpg', gif: '0861-fUBheHs.gif'), // cable seated row (close handle)
    'wide_grip_seated_row': (image: '0218-qcY50ZD.jpg', gif: '0218-qcY50ZD.gif'), // cable seated wide-grip row
    'lat_pulldown': (image: '0198-RVwzP10.jpg', gif: '0198-RVwzP10.gif'), // cable pulldown
    'pullups': (image: '0652-lBDjFxJ.jpg', gif: '0652-lBDjFxJ.gif'), // pull-up
    'cable_pullover': (image: '0238-x69MAlq.jpg', gif: '0238-x69MAlq.gif'), // cable straight arm pulldown
    'shrugs': (image: '0406-NJzBsGJ.jpg', gif: '0406-NJzBsGJ.gif'), // dumbbell shrug
    // Shoulders
    'ohp': (image: '1456-wdRZISl.jpg', gif: '1456-wdRZISl.gif'), // barbell standing close grip military press
    'arnold_press': (image: '2137-Xy4jlWA.jpg', gif: '2137-Xy4jlWA.gif'), // dumbbell arnold press
    'db_shoulder_press': (image: '0405-znQUdHY.jpg', gif: '0405-znQUdHY.gif'), // dumbbell seated shoulder press
    'machine_shoulder_press': (image: '0869-vqsbmL0.jpg', gif: '0869-vqsbmL0.gif'), // lever shoulder press v. 2
    'lateral_raise': (image: '0334-DsgkuIt.jpg', gif: '0334-DsgkuIt.gif'), // dumbbell lateral raise
    'cable_lateral_raise': (image: '0178-goJ6ezq.jpg', gif: '0178-goJ6ezq.gif'), // cable lateral raise
    'face_pull': (image: '0233-ZfyAGhK.jpg', gif: '0233-ZfyAGhK.gif'), // cable standing rear delt row (with rope)
    'rear_delt_fly': (image: '0602-myfUsKf.jpg', gif: '0602-myfUsKf.gif'), // lever seated reverse fly
    // Arms
    'bb_curl': (image: '0031-25GPyDY.jpg', gif: '0031-25GPyDY.gif'), // barbell curl
    'db_curl': (image: '0294-NbVPDMW.jpg', gif: '0294-NbVPDMW.gif'), // dumbbell biceps curl
    'hammer_curl': (image: '0313-slDvUAU.jpg', gif: '0313-slDvUAU.gif'), // dumbbell hammer curl
    'incline_db_curl': (image: '0315-F3xgbjF.jpg', gif: '0315-F3xgbjF.gif'), // dumbbell incline biceps curl
    'cable_curl': (image: '0868-G08RZcQ.jpg', gif: '0868-G08RZcQ.gif'), // cable curl
    'machine_preacher_curl': (image: '0592-b6hQYMb.jpg', gif: '0592-b6hQYMb.gif'), // lever preacher curl
    'tri_pushdown': (image: '0200-dU605di.jpg', gif: '0200-dU605di.gif'), // cable pushdown (with rope attachment)
    'rod_tricep_pushdown': (image: '0201-3ZflifB.jpg', gif: '0201-3ZflifB.gif'), // cable pushdown
    'overhead_tri_ext': (image: '1722-1xHyxys.jpg', gif: '1722-1xHyxys.gif'), // cable high pulley overhead tricep extension
    'skullcrusher': (image: '0060-h8LFzo9.jpg', gif: '0060-h8LFzo9.gif'), // barbell lying triceps extension skull crusher
  };

  /// Read-only view of the explicit media overrides, for audits and tests.
  static Map<String, ({String image, String gif})> get mediaOverrides =>
      _foundationalMediaMap;

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
    // 'cable rear delt row (with rope)' is its own dataset entry (0203).
    'cable rear delt row with rope': '0203',
    'standing face pull': 'face_pull',
    'standing face pulls': 'face_pull',

    // Overhead Tricep Extension aliases
    'overhead_tri_ext': 'overhead_tri_ext',
    'overhead tricep extension': 'overhead_tri_ext',
    'overhead triceps extension': 'overhead_tri_ext',
    'cable high pulley overhead tricep extension': 'overhead_tri_ext',
    'cable overhead tricep extension': 'overhead_tri_ext',
    'cable overhead triceps extension': 'overhead_tri_ext',
    'cable rope high pulley overhead tricep extension': '1724',
    // Dumbbell and barbell variants are deliberately not aliased here: the
    // cable demo would show the wrong equipment. Barbell ones resolve to
    // their own dataset entries.
    'barbell seated overhead triceps extension': '0092',
    'barbell standing overhead triceps extension': '0109',
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
    // Two-arm dumbbell row is its own dataset entry.
    'dumbbell bent over row': '0293',
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
    // Plain 'cable pushdown' in the dataset is the straight bar version.
    'cable pushdown': '0201',
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
    // Stiff-leg is a distinct dataset lift (barbell straight leg deadlift).
    'stiff leg deadlift': '0116',
    'sldl': '0116',

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
    // Chin-ups (supinated grip) have their own demo.
    'chin up': '1326',
    'chin-up': '1326',
    'chin ups': '1326',

    // Cable Pullover aliases
    'cable_pullover': 'cable_pullover',
    'cable pullover': 'cable_pullover',

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
    'dumbbell rear delt fly': '0378',

    // Shrugs aliases
    'shrugs': 'shrugs',
    'shrug': 'shrugs',
    'dumbbell shrug': 'shrugs',
    'barbell shrug': '0095',

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

  /// Resolves the canonical ID for any exercise name, ID, or alias.
  String getCanonicalId(String nameOrId) {
    final res = resolveMedia(id: nameOrId, name: nameOrId);
    if (res.canonicalId != null && res.canonicalId!.isNotEmpty) {
      return res.canonicalId!;
    }
    final norm = _normalize(nameOrId);
    final mapped = _canonicalAliasMap[nameOrId.toLowerCase()] ??
        _canonicalAliasMap[norm];
    if (mapped != null) return mapped;
    return nameOrId;
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
    final effectiveId = id ?? exercise?.id ?? definition?.id ?? '';
    final effectiveName = name ?? exercise?.name ?? definition?.name ?? '';

    // 1. Explicit, verified override for the app's own exercise ids. These
    // win over refs carried on a definition so a stale ref can't show the
    // wrong demo.
    if (effectiveId.isNotEmpty && _foundationalMediaMap.containsKey(effectiveId)) {
      final mapped = _foundationalMediaMap[effectiveId]!;
      return (image: mapped.image, gif: mapped.gif, canonicalId: effectiveId);
    }

    // 1a. Media refs on the definition (dataset-backed library entries)
    if (definition != null) {
      final img = definition.imageRef;
      final gf = definition.gifRef;
      if (img != null && img.isNotEmpty && gf != null && gf.isNotEmpty) {
        return (image: img, gif: gf, canonicalId: definition.id);
      }
    }

    // 1b. Explicit canonical ID in catalog definitions
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

    // 2. Strict verified 1:1 alias in _canonicalAliasMap -> foundational or catalog ID
    final normId = _normalize(effectiveId);
    final normName = _normalize(effectiveName);

    final mappedId = _canonicalAliasMap[effectiveId.toLowerCase()] ??
        _canonicalAliasMap[normId] ??
        _canonicalAliasMap[normName];

    if (mappedId != null) {
      if (_foundationalMediaMap.containsKey(mappedId)) {
        final mapped = _foundationalMediaMap[mappedId]!;
        return (image: mapped.image, gif: mapped.gif, canonicalId: mappedId);
      }
      final catDef = ExerciseLibraryService.instance.getById(mappedId);
      if (catDef != null &&
          catDef.imageRef != null &&
          catDef.imageRef!.isNotEmpty &&
          catDef.gifRef != null &&
          catDef.gifRef!.isNotEmpty) {
        return (image: catDef.imageRef, gif: catDef.gifRef, canonicalId: catDef.id);
      }
    }

    // 3. Strict 1:1 exact name match against catalog definitions
    // (Only if exactly 1 definition matches on canonicalName or displayName; NEVER match against ambiguous aliases)
    if (normName.isNotEmpty) {
      final matches = ExerciseLibraryService.instance.allDefinitions.where((def) =>
          _normalize(def.canonicalName) == normName ||
          _normalize(def.displayName) == normName).toList();

      // The dataset repeats a few names (two angles of the same lift). Those
      // are the same exercise, so the first one with media is safe to use.
      final sameExercise = matches.length > 1 &&
          matches.every((d) =>
              _normalize(d.canonicalName) == _normalize(matches.first.canonicalName) &&
              d.equipment.toLowerCase() == matches.first.equipment.toLowerCase());
      if (matches.length == 1 || sameExercise) {
        final def = matches.firstWhere(
          (d) =>
              (d.gifRef?.isNotEmpty ?? false) ||
              _foundationalMediaMap.containsKey(d.id),
          orElse: () => matches.first,
        );
        if (_foundationalMediaMap.containsKey(def.id)) {
          final mapped = _foundationalMediaMap[def.id]!;
          return (image: mapped.image, gif: mapped.gif, canonicalId: def.id);
        }
        if (def.imageRef != null &&
            def.imageRef!.isNotEmpty &&
            def.gifRef != null &&
            def.gifRef!.isNotEmpty) {
          return (image: def.imageRef, gif: def.gifRef, canonicalId: def.id);
        }
      }
    }

    // 4. Otherwise: Fail closed. If identity is not sufficiently certain, return no media.
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
