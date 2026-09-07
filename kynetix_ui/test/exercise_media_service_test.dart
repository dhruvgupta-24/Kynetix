import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/exercise_media_service.dart';

void main() {
  group('ExerciseMediaService Canonical Resolution Tests', () {
    final service = ExerciseMediaService.instance;

    test('Direct foundational ID resolution works for bench press', () {
      final gif = service.getAnimationUrl('bench_press');
      expect(gif, contains('0025-EIeI8Vf.gif'));
    });

    test('Overhead Tricep Extension resolves from Exercise model', () {
      const ex = Exercise(
        id: 'overhead_tri_ext',
        name: 'Overhead Tricep Extension',
        muscleGroup: 'Triceps',
        type: ExerciseType.cableMachine,
      );
      final gif = service.getAnimationUrl(ex);
      expect(gif, isNotNull);
      expect(gif, contains('1722-1xHyxys.gif'));
    });

    test('Face Pull resolves from legacy/alternate aliases without exact ID match', () {
      // Alternate alias 1: "Face Pull"
      const ex1 = Exercise(
        id: 'custom_saved_1',
        name: 'Face Pull',
        muscleGroup: 'Rear Delts',
        type: ExerciseType.cableMachine,
      );
      final gif1 = service.getAnimationUrl(ex1);
      expect(gif1, isNotNull);
      expect(gif1, contains('0233-ZfyAGhK.gif')); // Verified authentic rope face pull

      // Alternate alias 2: "Cable Face Pull"
      final gif2 = service.getAnimationUrl('Cable Face Pull');
      expect(gif2, isNotNull);
      expect(gif2, contains('0233-ZfyAGhK.gif'));

      // Alternate alias 3: "Rope Face Pull"
      final gif3 = service.getAnimationUrl('Rope Face Pull');
      expect(gif3, isNotNull);
      expect(gif3, contains('0233-ZfyAGhK.gif'));
    });

    test('Incline DB Press resolves from colloquial abbreviations', () {
      final gif1 = service.getAnimationUrl('Incline DB Press');
      expect(gif1, contains('0314-ns0SIbU.gif'));

      final gif2 = service.getAnimationUrl('incline dumbbell bench press');
      expect(gif2, contains('0314-ns0SIbU.gif'));
    });

    test('T-Bar Row resolves from hyphenated and unhyphenated names', () {
      expect(service.getAnimationUrl('T-Bar Row'), contains('1349-BgljGjd.gif'));
      expect(service.getAnimationUrl('t bar row'), contains('1349-BgljGjd.gif'));
      expect(service.getAnimationUrl('tbar row'), contains('1349-BgljGjd.gif'));
    });

    test('Standing Military Press / OHP resolves cleanly', () {
      expect(service.getAnimationUrl('ohp'), contains('0091-gAeez7P.gif'));
      expect(service.getAnimationUrl('standing overhead press'), contains('0091-gAeez7P.gif'));
      expect(service.getAnimationUrl('military press'), contains('0091-gAeez7P.gif'));
    });

    test('Exercise with genuine absence of media returns null for graceful fallback', () {
      const customEx = Exercise(
        id: 'unmapped_bizarre_exercise_999',
        name: 'Unmapped Bizarre Movement 999',
        muscleGroup: 'Core',
        type: ExerciseType.isolation,
      );
      expect(service.hasMedia(customEx), isFalse);
      expect(service.getAnimationUrl(customEx), isNull);
    });

    test('Attribution string is strictly present and unmodified', () {
      expect(ExerciseMediaService.attribution, equals('© Gym visual — gymvisual.com'));
    });
  });
}
