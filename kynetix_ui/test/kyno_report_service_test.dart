import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/ai_coach_screen.dart' show recentHistory, maxHistoryMessages;
import 'package:kynetix/services/kyno_report_service.dart';

void main() {
  group('KynoReportService.buildRow', () {
    test('maps reason codes to what the table accepts', () {
      expect(KynoReportReason.values.map((r) => r.code), ['harmful', 'unsafe', 'other']);
      final row = KynoReportService.buildRow(reason: KynoReportReason.unsafe, message: 'Eat 5000 kcal');
      expect(row['reason'], 'unsafe');
      expect(row['message'], 'Eat 5000 kcal');
    });

    test('never sends user_id; the server fills it from auth.uid()', () {
      final row = KynoReportService.buildRow(reason: KynoReportReason.other, message: 'x');
      expect(row.containsKey('user_id'), isFalse);
      expect(row.keys.toSet(), {'reason', 'message', 'prompt', 'note'});
    });

    test('truncates message, prompt and note to their column limits', () {
      final row = KynoReportService.buildRow(
        reason: KynoReportReason.harmful,
        message: 'm' * 5000,
        prompt: 'p' * 3000,
        note: 'n' * 900,
      );
      expect((row['message'] as String).length, KynoReportService.maxMessageLength);
      expect((row['prompt'] as String).length, KynoReportService.maxPromptLength);
      expect((row['note'] as String).length, KynoReportService.maxNoteLength);
      expect(KynoReportService.maxMessageLength, 4000);
      expect(KynoReportService.maxPromptLength, 2000);
      expect(KynoReportService.maxNoteLength, 500);
    });

    test('blank note and prompt are sent as null, text is trimmed', () {
      final row = KynoReportService.buildRow(
        reason: KynoReportReason.other,
        message: '  reply  ',
        prompt: '   ',
        note: '\n',
      );
      expect(row['message'], 'reply');
      expect(row['prompt'], isNull);
      expect(row['note'], isNull);
    });

    test('rejects an empty reply', () {
      expect(
        () => KynoReportService.buildRow(reason: KynoReportReason.other, message: '   '),
        throwsArgumentError,
      );
    });

    test('clip never leaves half an emoji', () {
      final s = '${'a' * 3}\u{1F600}';
      expect(s.length, 5);
      expect(KynoReportService.clip(s, 4), 'aaa');
      expect(KynoReportService.clip(s, 5), s);
    });
  });

  group('recentHistory', () {
    test('keeps the latest 20 in order', () {
      final thread = List.generate(35, (i) => i);
      final out = recentHistory(thread);
      expect(maxHistoryMessages, 20);
      expect(out, List.generate(20, (i) => i + 15));
    });

    test('a short thread goes as is', () {
      final thread = [1, 2, 3];
      expect(recentHistory(thread), [1, 2, 3]);
    });
  });
}
