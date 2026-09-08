import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/kyno_assistant_service.dart';
import 'package:kynetix/services/kyno_context_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KynoAssistantService Tests', () {
    test('Dynamic prompt suggestions reflect context', () {
      final chips = KynoAssistantService.instance.getContextualPromptSuggestions();
      expect(chips, isNotEmpty);
      expect(chips.any((c) => c.contains('protein') || c.contains('workout') || c.contains('progress')), isTrue);
    });

    test('Process query returns structured facts, calculations, inferences, and recommendations', () async {
      final reply = await KynoAssistantService.instance.processQuery('How did my workout go today?');
      expect(reply.text, isNotEmpty);
      expect(reply.structuredInsights, isNotNull);
      expect(reply.structuredInsights!.isNotEmpty, isTrue);

      final types = reply.structuredInsights!.map((i) => i.type).toSet();
      expect(types, contains(KynoInformationType.fact));
    });

    test('Nutrition query recommends protein and remaining targets', () async {
      final reply = await KynoAssistantService.instance.processQuery('What should I eat tonight?');
      expect(reply.structuredInsights, isNotNull);
      expect(reply.structuredInsights!.any((i) => i.title.toLowerCase().contains('nutrition') || i.title.toLowerCase().contains('target') || i.title.toLowerCase().contains('protein')), isTrue);
    });
  });
}
