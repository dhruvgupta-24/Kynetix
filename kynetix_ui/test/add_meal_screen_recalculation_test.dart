import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/add_meal_screen.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  testWidgets('AddMealScreen structure changed checking tests', (WidgetTester tester) async {
    final screenKey = GlobalKey<State<AddMealScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        home: AddMealScreen(
          key: screenKey,
          section: MealSection.breakfast,
          date: DateTime.now(),
        ),
      ),
    );

    // pump() once to let initState run. pumpAndSettle() times out on repeating animations.
    await tester.pump();

    final state = screenKey.currentState as dynamic;

    // Test cases for structure change detection
    expect(AddMealScreen.hasParsedMealStructureChanged('1 roti', '1.5 roti'), isTrue);
    expect(AddMealScreen.hasParsedMealStructureChanged('2 roti + channa', '2 roti + rice + channa'), isTrue);
    expect(AddMealScreen.hasParsedMealStructureChanged('100g paneer', '150g paneer'), isTrue);
    expect(AddMealScreen.hasParsedMealStructureChanged('2 eggs', '4 eggs'), isTrue);
    expect(AddMealScreen.hasParsedMealStructureChanged('1 scoop whey', '1 scoop whey + milk'), isTrue);

    // No structure changes
    expect(AddMealScreen.hasParsedMealStructureChanged('1 roti', '1 roti'), isFalse);
    expect(AddMealScreen.hasParsedMealStructureChanged('1 scoop whey', '1 scoop whey'), isFalse);
    expect(AddMealScreen.hasParsedMealStructureChanged('100g paneer', '100g paneer'), isFalse);
  });
}
