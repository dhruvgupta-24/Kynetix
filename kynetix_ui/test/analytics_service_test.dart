import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/analytics_service.dart';

void main() {
  group('sanitizeProps', () {
    test('keeps booleans, numbers and short lowercase tokens', () {
      final p = AnalyticsService.sanitizeProps({
        'has_photo': true,
        'sets': 18,
        'duration_min': 52.456,
        'method': 'barcode',
        'size': '2x2',
        'kcal_bucket': '400_599',
      });
      expect(p, {
        'has_photo': true,
        'sets': 18,
        'duration_min': 52.46,
        'method': 'barcode',
        'size': '2x2',
        'kcal_bucket': '400_599',
      });
    });

    test('drops free text, so no meal or message can ride along', () {
      final p = AnalyticsService.sanitizeProps({
        'meal': '2 rotis and dal',
        'message': 'How much protein?',
        'email': 'me@example.com',
        'name': 'Dhruv',
        'long': 'a' * 40,
        'ok': 'fine',
      });
      expect(p, {'ok': 'fine'});
    });

    test('drops nulls, lists, maps, non-finite numbers and bad keys', () {
      final p = AnalyticsService.sanitizeProps({
        'none': null,
        'list': [1, 2],
        'map': {'a': 1},
        'nan': double.nan,
        'inf': double.infinity,
        'Bad Key': 1,
        '9lives': 1,
        'fine_key': 1,
      });
      expect(p, {'fine_key': 1});
      expect(AnalyticsService.sanitizeProps(null), isEmpty);
    });

    test('caps the number of keys', () {
      final p = AnalyticsService.sanitizeProps({for (var i = 0; i < 40; i++) 'k$i': i});
      expect(p.length, 16);
    });

    test('kcal buckets are coarse', () {
      expect(AnalyticsService.kcalBucket(120), 'under_200');
      expect(AnalyticsService.kcalBucket(200), '200_399');
      expect(AnalyticsService.kcalBucket(599.9), '400_599');
      expect(AnalyticsService.kcalBucket(650), '600_899');
      expect(AnalyticsService.kcalBucket(1400), '900_plus');
    });
  });

  group('queue', () {
    late List<List<Map<String, Object?>>> batches;
    late bool signedIn;
    late bool failing;

    AnalyticsService make({int flushAt = 20, Duration flushEvery = const Duration(seconds: 30), int maxQueue = 200}) =>
        AnalyticsService(
          sink: (rows) async {
            if (failing) throw Exception('offline');
            batches.add(rows);
          },
          signedIn: () => signedIn,
          flushAt: flushAt,
          flushEvery: flushEvery,
          maxQueue: maxQueue,
        );

    setUp(() {
      batches = [];
      signedIn = true;
      failing = false;
    });

    test('rows carry name, clean props and the launch session id', () async {
      final a = make();
      a.track('meal_logged', {'method': 'text', 'meal': 'paneer tikka'});
      await a.flush();
      expect(batches, hasLength(1));
      final row = batches.single.single;
      expect(row['name'], 'meal_logged');
      expect(row['props'], {'method': 'text'});
      expect(row['session_id'], a.sessionId);
      expect(row.containsKey('user_id'), isFalse);
      expect(DateTime.tryParse(row['created_at'] as String), isNotNull);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a.sessionId), isTrue);
    });

    test('flushes on its own at the batch size', () async {
      final a = make(flushAt: 3);
      a.track('app_open');
      a.track('screen_view');
      expect(batches, isEmpty);
      a.track('screen_view');
      await Future<void>.delayed(Duration.zero);
      expect(batches.single, hasLength(3));
      expect(a.queued, 0);
    });

    test('flushes on the timer', () async {
      final a = make(flushEvery: const Duration(milliseconds: 20));
      a.track('app_open');
      expect(batches, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches.single, hasLength(1));
    });

    test('signed out: events are dropped', () async {
      signedIn = false;
      final a = make();
      a.track('app_open');
      expect(a.queued, 0);
      await a.flush();
      expect(batches, isEmpty);
    });

    test('bad names are refused', () async {
      final a = make();
      a.track('Bad Name');
      a.track('x');
      expect(a.queued, 0);
    });

    test('a failed flush keeps the events, never throws, and retries', () async {
      final a = make();
      failing = true;
      a.track('app_open');
      a.track('screen_view');
      await a.flush();
      expect(a.queued, 2);
      failing = false;
      await a.flush();
      expect(batches.single.map((r) => r['name']), ['app_open', 'screen_view']);
      expect(a.queued, 0);
    });

    test('the queue is bounded; the oldest go first', () async {
      final a = make(maxQueue: 5);
      failing = true;
      for (var i = 0; i < 8; i++) {
        a.track('set_logged', {'n': i});
      }
      await a.flush();
      expect(a.queued, 5);
      failing = false;
      await a.flush();
      expect(batches.expand((b) => b).map((r) => (r['props'] as Map)['n']), [3, 4, 5, 6, 7]);
    });

    test('concurrent flushes send each event once', () async {
      final a = make();
      for (var i = 0; i < 5; i++) {
        a.track('screen_view');
      }
      await Future.wait([a.flush(), a.flush(), a.flush()]);
      expect(batches.expand((b) => b), hasLength(5));
    });

    test('flushBeforeSignOut sends then empties the queue', () async {
      final a = make();
      a.track('sign_out');
      await a.flushBeforeSignOut();
      expect(batches.single.single['name'], 'sign_out');
      expect(a.queued, 0);
    });
  });
}
