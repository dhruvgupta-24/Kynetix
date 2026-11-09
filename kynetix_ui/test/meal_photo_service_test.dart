import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/services/meal_photo_service.dart';

/// The photo contract on the app side: what Kyno's canonical answer turns
/// into, how it is typed into the meal, what is sent, and how failures map
/// to calm copy. The server half lives in
/// supabase/functions/shared/meal_photo_test.ts.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => MealPhotoService.instance.invokeOverride = null);

  Map<String, dynamic> food(String name, {double? count, String unit = 'g', double grams = 150, double kcal = 160}) => {
        'name': name,
        'count': count,
        'unit': unit,
        'grams': grams,
        'kcal': kcal,
        'protein_g': 8,
        'carbs_g': 20,
        'fat_g': 5,
        'fiber_g': 4,
        'confidence': 0.8,
      };

  String answer(List<Map<String, dynamic>> items, {String? title}) =>
      jsonEncode({'is_food': true, 'title': title, 'items': items});

  group('reading', () {
    test('foods become lines a person would type', () {
      final r = MealPhotoReading.tryParse(answer([
        food('roti', count: 3, unit: 'piece', grams: 105, kcal: 300),
        food('dal tadka'),
        food('lassi', unit: 'ml', grams: 250),
        food('paratha', count: 1.5, unit: 'piece', grams: 120, kcal: 360),
      ], title: 'dal roti'))!;
      expect(r.mealText, '3 roti, 150 g dal tadka, 250 ml lassi, 1.5 paratha');
      expect(r.title, 'dal roti');
      expect(r.foods.first.amountLabel, '3 pcs');
      expect(r.foods[1].amountLabel, '150 g');
    });

    test('the parsed form keeps amount and unit', () {
      final f = MealPhotoReading.tryParse(answer([food('dal tadka', grams: 180)]))!.foods.single;
      final p = f.parsed;
      expect(p.normalizedName, 'dal tadka');
      expect(p.quantity, 180);
      expect(p.unit, 'g');
    });

    test('a name the parser would split stays one food', () {
      final f = MealPhotoReading.tryParse(answer([food('bread and butter', grams: 60, kcal: 200)]))!.foods.single;
      expect(f.parsed.normalizedName, 'bread and butter');
    });

    test('junk items are dropped; nothing usable is null', () {
      final r = MealPhotoReading.tryParse(answer([
        food('dal tadka'),
        {...food('<script>'), 'name': '<script>'},
        {...food('x'), 'grams': -4},
        {...food('dal tadka'), 'kcal': 999},
      ]))!;
      expect(r.foods.map((f) => f.name), ['dal tadka']);
      expect(MealPhotoReading.tryParse('{"is_food": false, "items": []}'), isNull);
      expect(MealPhotoReading.tryParse('not json'), isNull);
    });

    test('low confidence is flagged for a second look', () {
      final r = MealPhotoReading.tryParse(answer([
        {...food('chutney', grams: 20, kcal: 30), 'protein_g': 0.5, 'carbs_g': 5, 'fat_g': 1, 'fiber_g': 1, 'confidence': 0.3},
      ]))!;
      expect(r.foods.single.unsure, isTrue);
    });
  });

  group('request', () {
    test('one photo, a fixed instruction, the note clipped', () {
      final body = MealPhotoService.buildRequestBody(Uint8List.fromList([1, 2, 3]), note: '  mutton,\nnot chicken ${'x' * 400}');
      expect(body['purpose'], 'meal_photo');
      final content = (body['messages'] as List).single['content'] as List;
      final text = content.first['text'] as String;
      expect(text, startsWith('Log this meal. Note from me: mutton, not chicken'));
      expect(text.length, lessThanOrEqualTo('Log this meal. Note from me: '.length + MealPhotoService.maxNote));
      expect((content.last['image_url'] as Map)['url'], startsWith('data:image/jpeg;base64,'));
    });

    test('no note, no note text', () {
      final body = MealPhotoService.buildRequestBody(Uint8List(3));
      final content = (body['messages'] as List).single['content'] as List;
      expect(content.first['text'], MealPhotoService.userText);
    });
  });

  group('failures map to calm copy', () {
    Future<MealPhotoException> failWith(Object? response) async {
      MealPhotoService.instance.invokeOverride = (_) async => response;
      try {
        await MealPhotoService.instance.read(Uint8List(4));
      } on MealPhotoException catch (e) {
        return e;
      }
      throw TestFailure('expected an exception');
    }

    test('not food', () async {
      final e = await failWith({'success': false, 'error': 'not_food'});
      expect(e.kind, MealPhotoFailure.notFood);
      expect(e.retakeHelps, isTrue);
    });

    test('unreadable answer', () async {
      final e = await failWith({'success': true, 'response': 'I see a plate!'});
      expect(e.kind, MealPhotoFailure.unreadable);
    });

    test('offline on a thrown error', () async {
      MealPhotoService.instance.invokeOverride = (_) async => throw Exception('socket');
      await expectLater(
        MealPhotoService.instance.read(Uint8List(4)),
        throwsA(isA<MealPhotoException>().having((e) => e.kind, 'kind', MealPhotoFailure.offline)),
      );
    });

    test('copy has no em or en dashes and no exclamation marks', () {
      for (final k in MealPhotoFailure.values) {
        final m = MealPhotoException(k).userMessage;
        expect(m.contains('—') || m.contains('–'), isFalse, reason: m);
        expect(m.contains('!'), isFalse, reason: m);
      }
    });

    test('a good answer reads', () async {
      MealPhotoService.instance.invokeOverride = (_) async => {
            'success': true,
            'response': answer([food('dal tadka')]),
          };
      final r = await MealPhotoService.instance.read(Uint8List(4));
      expect(r.foods.single.name, 'dal tadka');
    });
  });

  group('pricing goes through the app pipeline', () {
    test('a food the app does not know uses Kyno\'s photo numbers, no second AI call', () async {
      final r = MealPhotoReading.tryParse(answer([
        {...food('zqx bhaji special', grams: 140, kcal: 210), 'protein_g': 6, 'carbs_g': 22, 'fat_g': 11, 'fiber_g': 3},
      ]))!;
      final result = await r.estimate();
      expect(result.items, hasLength(1));
      expect(result.calories.mid, closeTo(210, 0.01));
      expect(result.protein.mid, closeTo(6, 0.01));
      expect(result.estimationAudit?.memoryMatchUsed, contains('photo_estimate'));
    });

    test('a curry the app knows uses the curry table at the photo\'s grams', () async {
      // Kyno says 150 g of dal tadka is 600 kcal (wrong); the curry table wins.
      final r = MealPhotoReading.tryParse(answer([
        {...food('dal tadka', grams: 150, kcal: 600), 'protein_g': 20, 'carbs_g': 60, 'fat_g': 31, 'fiber_g': 5},
      ]))!;
      final result = await r.estimate();
      expect(result.calories.mid, lessThan(300));
      expect(result.estimationAudit?.memoryMatchUsed, contains('curry_table'));
    });
  });
}
