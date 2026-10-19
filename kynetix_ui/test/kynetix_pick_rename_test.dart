import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:kynetix/models/workout_split.dart';

void main() {
  test('the default split is shown as Kynetix Pick, id unchanged', () {
    expect(developersChoiceName, 'Kynetix Pick');
    expect(defaultWorkoutSplit.id, 'developers_choice');
    expect(defaultWorkoutSplit.name, 'Kynetix Pick');
  });

  test('a split saved under the old name loads with the new one', () {
    final json = _json()..['name'] = "Developer's Choice";
    final loaded = WorkoutSplit.fromJson(json);
    expect(loaded.id, developersChoiceId);
    expect(loaded.name, 'Kynetix Pick');
    expect(isUnchangedDevelopersChoice(loaded), isTrue);
  });

  test('a renamed or custom split keeps its own name', () {
    final custom = _json()..['name'] = 'My Split';
    expect(WorkoutSplit.fromJson(custom).name, 'My Split');

    final other = _json()
      ..['id'] = 'custom_1'
      ..['name'] = "Developer's Choice";
    expect(WorkoutSplit.fromJson(other).name, "Developer's Choice");
  });
}

Map<String, dynamic> _json() =>
    jsonDecode(developersChoiceSplit.encode()) as Map<String, dynamic>;
