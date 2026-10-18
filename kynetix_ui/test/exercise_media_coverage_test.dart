import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/exercise_media_service.dart';

/// Every exercise the app can show must resolve to a demo that really exists
/// in the dataset, and the app's own ids must point at the right movement.
///
/// test/fixtures/exercise_media_verified_ids.json is the dataset's media
/// index (file stem to dataset exercise name). Each stem was checked to
/// return HTTP 200 for both videos/<stem>.gif and images/<stem>.jpg on
/// jsDelivr, so this test catches broken or invented ids without network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> verified;
  final service = ExerciseMediaService.instance;

  String stem(String file) => file.substring(0, file.lastIndexOf('.'));

  setUpAll(() async {
    final raw = jsonDecode(
      File('test/fixtures/exercise_media_verified_ids.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    verified = (raw['media'] as Map<String, dynamic>).cast<String, String>();
    await ExerciseLibraryService.instance.initialize();
  });

  void expectVerified(
    ({String? image, String? gif, String? canonicalId}) r,
    String label,
  ) {
    expect(r.gif, isNotNull, reason: '$label has no demo');
    expect(r.image, isNotNull, reason: '$label has no thumbnail');
    expect(verified.containsKey(stem(r.gif!)), isTrue,
        reason: '$label points at unknown gif ${r.gif}');
    expect(stem(r.image!), stem(r.gif!),
        reason: '$label thumbnail and demo disagree');
  }

  test('fixture covers the whole dataset', () {
    expect(verified.length, greaterThanOrEqualTo(1324));
  });

  test('every library exercise resolves to a verified demo of itself', () {
    final defs = ExerciseLibraryService.instance.allDefinitions;
    expect(defs.length, greaterThan(1300));
    for (final def in defs) {
      final r = service.resolveMedia(definition: def);
      expectVerified(r, '${def.id} ${def.name}');
      // Dataset-backed entries must show their own dataset id, never a
      // neighbour's.
      if (RegExp(r'^\d{4}$').hasMatch(def.id)) {
        expect(r.gif!.startsWith('${def.id}-'), isTrue,
            reason: '${def.id} ${def.name} shows ${r.gif}');
      }
    }
  });

  test('every built-in and default split exercise resolves to a verified demo', () {
    final all = <Exercise>[
      ...deduplicatedLibrary,
      ...exerciseLibraryByDay.values.expand((e) => e),
      for (final day in developersChoiceSplit.days) ...day.exercises,
    ];
    expect(all, isNotEmpty);
    for (final ex in all) {
      expectVerified(service.resolveMedia(exercise: ex), '${ex.id} ${ex.name}');
      // The session screen and picker go through the url helpers.
      expect(service.getAnimationUrl(ex), isNotNull, reason: ex.id);
    }
  });

  test('every explicit override is a verified dataset id', () {
    ExerciseMediaService.mediaOverrides.forEach((id, media) {
      expect(verified.containsKey(stem(media.gif)), isTrue, reason: id);
      expect(stem(media.image), stem(media.gif), reason: id);
    });
  });

  // The movement each app id must show, by the dataset's own name. Guards
  // against equipment, grip and bench angle mix-ups.
  const expectedMovement = <String, String>{
    'bench_press': 'barbell bench press',
    'flat_bench_press': 'barbell bench press',
    'incline_bench_press': 'barbell incline bench press',
    'incline_db_press': 'dumbbell incline bench press',
    'close_grip_bench': 'barbell close-grip bench press',
    'pec_dec': 'lever seated fly',
    'cable_chest_fly': 'cable middle fly',
    'chest_dip': 'chest dip',
    'dips': 'triceps dip',
    'deadlift': 'barbell deadlift',
    'rdl': 'barbell romanian deadlift',
    'squat': 'barbell full squat',
    'hack_squat': 'sled hack squat',
    'leg_press': 'sled 45° leg press',
    'leg_extension': 'lever leg extension',
    'leg_curl': 'lever lying leg curl',
    'standing_calf': 'lever standing calf raise',
    'calf_raise': 'lever seated calf raise',
    'adductor_machine': 'lever seated hip adduction',
    'bb_row': 'barbell bent over row',
    'db_row': 'dumbbell one arm bent-over row',
    'tbar_row': 'lever t bar row',
    'seated_cable_row': 'cable seated row',
    'close_grip_cable_row': 'cable seated row',
    'wide_grip_seated_row': 'cable seated wide-grip row',
    'lat_pulldown': 'cable pulldown',
    'pullups': 'pull-up',
    'cable_pullover': 'cable straight arm pulldown',
    'shrugs': 'dumbbell shrug',
    'ohp': 'barbell standing close grip military press',
    'arnold_press': 'dumbbell arnold press',
    'db_shoulder_press': 'dumbbell seated shoulder press',
    'machine_shoulder_press': 'lever shoulder press v. 2',
    'lateral_raise': 'dumbbell lateral raise',
    'cable_lateral_raise': 'cable lateral raise',
    'face_pull': 'cable standing rear delt row (with rope)',
    'rear_delt_fly': 'lever seated reverse fly',
    'bb_curl': 'barbell curl',
    'db_curl': 'dumbbell biceps curl',
    'hammer_curl': 'dumbbell hammer curl',
    'incline_db_curl': 'dumbbell incline biceps curl',
    'cable_curl': 'cable curl',
    'machine_preacher_curl': 'lever preacher curl',
    'tri_pushdown': 'cable pushdown (with rope attachment)',
    'rod_tricep_pushdown': 'cable pushdown',
    'overhead_tri_ext': 'cable high pulley overhead tricep extension',
    'skullcrusher': 'barbell lying triceps extension skull crusher',
  };

  test('app exercise ids show the matching movement', () {
    expect(ExerciseMediaService.mediaOverrides.keys.toSet(),
        expectedMovement.keys.toSet());
    expectedMovement.forEach((id, movement) {
      final r = service.resolveMedia(id: id);
      expect(verified[stem(r.gif!)], movement, reason: id);
    });
  });

  test('aliases never cross equipment', () {
    String? shown(String name) {
      final r = service.resolveMedia(id: 'custom_x', name: name);
      return r.gif == null ? null : verified[stem(r.gif!)];
    }

    expect(shown('Chin-up'), 'chin-up');
    expect(shown('Barbell Shrug'), 'barbell shrug');
    expect(shown('Dumbbell Shrug'), 'dumbbell shrug');
    expect(shown('Dumbbell Bent Over Row'), 'dumbbell bent over row');
    expect(shown('Stiff Leg Deadlift'), 'barbell straight leg deadlift');
    expect(shown('Cable Pushdown'), 'cable pushdown');
    expect(shown('Rope Pushdown'), 'cable pushdown (with rope attachment)');
    expect(shown('Barbell Standing Overhead Triceps Extension'),
        'barbell standing overhead triceps extension');
    expect(shown('Incline Dumbbell Press'), 'dumbbell incline bench press');
    expect(shown('Face Pull'), 'cable standing rear delt row (with rope)');
  });

  test('cdn urls have a raw GitHub mirror for the single retry', () {
    final url = service.getAnimationUrl('lat_pulldown')!;
    expect(url, startsWith(ExerciseMediaService.cdnBaseVideos));
    expect(ExerciseMediaService.mirrorUrlFor(url),
        '${ExerciseMediaService.rawBaseVideos}/0198-RVwzP10.gif');
    expect(ExerciseMediaService.mirrorUrlFor('https://example.com/x.gif'), isNull);
  });
}
