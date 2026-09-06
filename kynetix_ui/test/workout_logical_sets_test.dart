import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearAll();
    WorkoutService.instance.resetReadyForTesting();
    await WorkoutService.instance.init();
  });

  group('Hierarchical Set Model & Logical Set Semantics', () {
    final lateralRaise = Exercise(
      id: 'cable_lateral_raise',
      name: 'Cable Lateral Raise',
      muscleGroup: 'Shoulders',
      type: ExerciseType.isolation,
      defaultTargetSets: 3,
    );

    test('3 working sets + 1 drop on Set 3 results in 3 logical sets and 4 physical efforts', () {
      final entry = ExerciseEntry(
        exercise: lateralRaise,
        logicalSets: [
          LogicalSetGroup(
            mainSet: const SetEntry(weight: 15, reps: 12, setType: SetType.normal),
          ),
          LogicalSetGroup(
            mainSet: const SetEntry(weight: 15, reps: 13, setType: SetType.normal),
          ),
          LogicalSetGroup(
            mainSet: const SetEntry(weight: 15, reps: 10, setType: SetType.normal),
            subSets: const [
              SetEntry(weight: 10, reps: 4, setType: SetType.dropSet),
            ],
            structure: SetStructure.dropSet,
          ),
        ],
      );

      // Logical Working Sets: exactly 3
      expect(entry.completedWorkingSetsCount, 3);
      expect(entry.totalLogicalSetsCount, 3);
      expect(entry.isCompleted, isTrue);

      // Physical Sets: 4
      expect(entry.totalPhysicalSetsCount, 4);
      expect(entry.sets.length, 4);

      // Volume analytics
      // Set 1: 15 * 12 = 180
      // Set 2: 15 * 13 = 195
      // Set 3: 15 * 10 = 150 -> Primary Working Volume = 525 kg
      // Drop 1: 10 * 4 = 40 kg -> Drop Volume = 40 kg
      // Total Stimulus Volume = 565 kg
      expect(entry.primaryWorkingVolume, 525.0);
      expect(entry.dropSetVolume, 40.0);
      expect(entry.totalVolume, 565.0);
      expect(entry.totalStimulusVolume, 565.0);

      // 1RM / Progression integrity: drop set does NOT skew top working set
      // Set 2 has 15 kg x 13 reps -> e1RM = 15 * (1 + 13/30) = 21.5 kg
      expect(entry.topWorkingSet?.weight, 15.0);
      expect(entry.topWorkingSet?.reps, 13);
      expect(entry.bestOneRepMax, closeTo(21.5, 0.1));
    });

    test('Backward compatibility: legacy flat sets deserialize into hierarchical logical sets', () {
      final legacyJson = {
        'exercise': lateralRaise.toJson(),
        'sets': [
          {'weight': 15.0, 'reps': 12, 'setType': 'normal'},
          {'weight': 15.0, 'reps': 13, 'setType': 'normal'},
          {'weight': 15.0, 'reps': 10, 'setType': 'normal'},
          {'weight': 10.0, 'reps': 4, 'setType': 'dropSet'},
        ],
      };

      final entry = ExerciseEntry.fromJson(legacyJson);

      expect(entry.logicalSets.length, 3);
      expect(entry.completedWorkingSetsCount, 3);
      expect(entry.totalPhysicalSetsCount, 4);
      expect(entry.primaryWorkingVolume, 525.0);
      expect(entry.dropSetVolume, 40.0);
      expect(entry.totalVolume, 565.0);

      // Check hierarchy
      expect(entry.logicalSets[0].subSets, isEmpty);
      expect(entry.logicalSets[1].subSets, isEmpty);
      expect(entry.logicalSets[2].subSets.length, 1);
      expect(entry.logicalSets[2].subSets[0].weight, 10.0);
      expect(entry.logicalSets[2].subSets[0].reps, 4);
      expect(entry.logicalSets[2].structure, SetStructure.dropSet);
    });

    test('Multi-drop set on Set 3: 3 working sets + 2 drops on Set 3', () {
      final legacyJson = {
        'exercise': lateralRaise.toJson(),
        'sets': [
          {'weight': 15.0, 'reps': 12, 'setType': 'normal'},
          {'weight': 15.0, 'reps': 13, 'setType': 'normal'},
          {'weight': 15.0, 'reps': 10, 'setType': 'normal'},
          {'weight': 10.0, 'reps': 4, 'setType': 'dropSet'},
          {'weight': 7.5, 'reps': 6, 'setType': 'dropSet'},
        ],
      };

      final entry = ExerciseEntry.fromJson(legacyJson);

      expect(entry.logicalSets.length, 3);
      expect(entry.completedWorkingSetsCount, 3);
      expect(entry.totalPhysicalSetsCount, 5);
      expect(entry.primaryWorkingVolume, 525.0);
      expect(entry.dropSetVolume, 40.0 + (7.5 * 6)); // 40 + 45 = 85
      expect(entry.totalVolume, 610.0);
      expect(entry.logicalSets[2].subSets.length, 2);
    });

    test('Warmup sets are preserved and excluded from working count and volume', () {
      final legacyJson = {
        'exercise': lateralRaise.toJson(),
        'sets': [
          {'weight': 5.0, 'reps': 15, 'setType': 'warmUp'},
          {'weight': 15.0, 'reps': 12, 'setType': 'normal'},
          {'weight': 15.0, 'reps': 10, 'setType': 'normal'},
          {'weight': 10.0, 'reps': 4, 'setType': 'dropSet'},
        ],
      };

      final entry = ExerciseEntry.fromJson(legacyJson);

      expect(entry.logicalSets.length, 3); // 1 warmup group + 2 working groups
      expect(entry.warmUpSetsCount, 1);
      expect(entry.completedWorkingSetsCount, 2);
      expect(entry.totalPhysicalSetsCount, 4);
      // Warmup 5x15=75kg excluded from total stimulus volume
      expect(entry.primaryWorkingVolume, (15 * 12) + (15 * 10)); // 180 + 150 = 330
      expect(entry.dropSetVolume, 40.0);
      expect(entry.totalVolume, 370.0);
    });

    test('WorkoutSession aggregates logical working sets and total volume correctly', () {
      final session = WorkoutSession(
        id: 'test-session-1',
        date: DateTime.now(),
        splitDayName: 'Shoulder Day',
        entries: [
          ExerciseEntry(
            exercise: lateralRaise,
            logicalSets: [
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 12, setType: SetType.normal),
              ),
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 13, setType: SetType.normal),
              ),
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 10, setType: SetType.normal),
                subSets: const [
                  SetEntry(weight: 10, reps: 4, setType: SetType.dropSet),
                ],
                structure: SetStructure.dropSet,
              ),
            ],
          ),
        ],
      );

      expect(session.totalWorkingSets, 3); // exactly 3 working sets!
      expect(session.totalPhysicalSets, 4);
      expect(session.primaryWorkingVolume, 525.0);
      expect(session.dropSetVolume, 40.0);
      expect(session.totalVolume, 565.0);
    });

    test('Roundtrip serialization of WorkoutSession with hierarchical sets', () {
      final session = WorkoutSession(
        id: 'test-session-1',
        date: DateTime.now(),
        splitDayName: 'Shoulder Day',
        entries: [
          ExerciseEntry(
            exercise: lateralRaise,
            logicalSets: [
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 12, setType: SetType.normal),
              ),
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 10, setType: SetType.normal),
                subSets: const [
                  SetEntry(weight: 10, reps: 4, setType: SetType.dropSet),
                ],
                structure: SetStructure.dropSet,
              ),
            ],
          ),
        ],
      );

      final jsonMap = session.toJson();
      final jsonString = jsonEncode(jsonMap);
      final decodedSession = WorkoutSession.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

      expect(decodedSession.entries.length, 1);
      final decodedEntry = decodedSession.entries[0];
      expect(decodedEntry.logicalSets.length, 2);
      expect(decodedEntry.completedWorkingSetsCount, 2);
      expect(decodedEntry.totalPhysicalSetsCount, 3);
      expect(decodedEntry.totalVolume, (15 * 12) + (15 * 10) + (10 * 4));
      expect(decodedEntry.logicalSets[1].subSets.length, 1);
      expect(decodedEntry.logicalSets[1].subSets[0].weight, 10.0);
    });

    testWidgets('UI Runtime Verification: 3 working sets + 1 drop on Set 3 shows 3 sets with nested drop', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final splitDay = SplitDay(
        name: 'Shoulders',
        weekday: 1,
        exercises: [lateralRaise],
      );

      final draft = WorkoutSession(
        id: 'draft-session',
        date: DateTime.now(),
        splitDayName: 'Shoulders',
        entries: [
          ExerciseEntry(
            exercise: lateralRaise,
            logicalSets: [
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 12, setType: SetType.normal),
              ),
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 13, setType: SetType.normal),
              ),
              LogicalSetGroup(
                mainSet: const SetEntry(weight: 15, reps: 10, setType: SetType.normal),
                subSets: const [
                  SetEntry(weight: 10, reps: 4, setType: SetType.dropSet),
                ],
                structure: SetStructure.dropSet,
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            splitDay: splitDay,
            date: DateTime.now(),
            draftSession: draft,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify UI displays "LOGGED SETS (3)"
      expect(find.text('LOGGED SETS (3)'), findsOneWidget);

      // Verify UI displays Total volume 565 kg and Drop volume 40 kg
      expect(find.textContaining('Vol: 565 kg (Drop: 40 kg)'), findsOneWidget);

      // Verify Main sets 1, 2, 3
      expect(find.text('15 kg  ×  12 reps'), findsOneWidget);
      expect(find.text('15 kg  ×  13 reps'), findsOneWidget);
      expect(find.text('15 kg  ×  10 reps'), findsOneWidget);

      // Verify child drop set nested with DROP indicator
      expect(find.text('DROP'), findsOneWidget);
      expect(find.text('10 kg  ×  4 reps  (40 kg)'), findsOneWidget);
    });
  });
}
