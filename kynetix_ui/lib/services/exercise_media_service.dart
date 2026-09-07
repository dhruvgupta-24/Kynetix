import '../models/exercise_definition.dart';

/// Service managing exercise visual assets (thumbnails, animated GIFs),
/// official GymVisual attribution, and CDN URL resolution.
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

  /// Deterministic media mappings for the 39 foundational exercises.
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
    'face_pull': (image: '0247-uD6gQeR.jpg', gif: '0247-uD6gQeR.gif'),
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

  /// Resolves the static image/thumbnail URL for [definition].
  String? getThumbnailUrl(ExerciseDefinition? definition) {
    if (definition == null) return null;

    if (definition.imageRef != null && definition.imageRef!.isNotEmpty) {
      return '$cdnBaseImages/${definition.imageRef}';
    }

    final mapped = _foundationalMediaMap[definition.id];
    if (mapped != null && mapped.image.isNotEmpty) {
      return '$cdnBaseImages/${mapped.image}';
    }

    return null;
  }

  /// Resolves the animated GIF demonstration URL for [definition].
  String? getAnimationUrl(ExerciseDefinition? definition) {
    if (definition == null) return null;

    if (definition.gifRef != null && definition.gifRef!.isNotEmpty) {
      return '$cdnBaseVideos/${definition.gifRef}';
    }

    final mapped = _foundationalMediaMap[definition.id];
    if (mapped != null && mapped.gif.isNotEmpty) {
      return '$cdnBaseVideos/${mapped.gif}';
    }

    return null;
  }

  /// Returns true if the definition has visual media available.
  bool hasMedia(ExerciseDefinition? definition) {
    if (definition == null) return false;
    if (definition.gifRef != null && definition.gifRef!.isNotEmpty) return true;
    if (definition.imageRef != null && definition.imageRef!.isNotEmpty) return true;
    return _foundationalMediaMap.containsKey(definition.id);
  }
}
