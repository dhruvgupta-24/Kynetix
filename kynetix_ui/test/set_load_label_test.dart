import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_session.dart';

void main() {
  test('bodyweight sets read BW plus the belt load', () {
    const belt = SetEntry(weight: 0, reps: 8, externalLoadKg: 17.5);
    const bare = SetEntry(weight: 0, reps: 12, externalLoadKg: 0);
    const bar = SetEntry(weight: 62.5, reps: 5);
    expect(belt.loadLabel, 'BW + 17.5 kg');
    expect(bare.loadLabel, 'BW');
    expect(bar.loadLabel, '62.5 kg');
    expect(belt.shortLabel, 'BW+17.5×8');
    expect(bare.shortLabel, 'BW×12');
    expect(bar.shortLabel, '62.5×5');
    // The belt load is what progresses and what counts as volume.
    expect(belt.volume, 140);
    expect(bare.volume, 0);
  });
}
