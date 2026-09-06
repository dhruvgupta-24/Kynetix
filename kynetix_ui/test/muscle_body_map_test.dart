import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/widgets/muscle_body_map.dart';
import 'package:kynetix/utils/svg_path_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SvgPathParser Tests', () {
    test('parses simple rectangle SVG path commands correctly', () {
      const svgPath = 'M 0 0 L 100 0 L 100 100 L 0 100 Z';
      final path = SvgPathParser.parse(svgPath);
      expect(path, isNotNull);
      final bounds = path.getBounds();
      expect(bounds.width, closeTo(100.0, 0.1));
      expect(bounds.height, closeTo(100.0, 0.1));
    });

    test('parses cubic bezier curve commands (C, c)', () {
      const svgPath = 'M 10 10 C 20 20, 40 20, 50 10';
      final path = SvgPathParser.parse(svgPath);
      expect(path, isNotNull);
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(10.0, 0.1));
    });

    test('caches parsed SVG paths for high performance', () {
      const svgPath = 'M 0 0 L 50 50 Z';
      final path1 = SvgPathParser.parse(svgPath);
      final path2 = SvgPathParser.parse(svgPath);
      expect(identical(path1, path2), isTrue);
    });
  });

  setUpAll(() {
    MuscleBodyMap.setCachedGeometryForTesting({
      'front': {
        'viewBox': '0 0 100 100',
        'paths': {
          'chest': 'M 10 10 L 50 10 L 50 50 L 10 50 Z',
          'deltoids': 'M 50 10 L 90 10 L 90 50 L 50 50 Z',
        }
      },
      'back': {
        'viewBox': '0 0 100 100',
        'paths': {
          'lats': 'M 10 10 L 50 10 L 50 50 L 10 50 Z',
          'trapezius': 'M 50 10 L 90 10 L 90 50 L 50 50 Z',
        }
      }
    });
  });

  group('MuscleBodyMap Widget Tests', () {
    testWidgets('renders MuscleBodyMap widget with front view', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MuscleBodyMap(
              view: BodyView.front,
              highlightedMuscles: {'chest', 'deltoids'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MuscleBodyMap), findsOneWidget);
    });

    testWidgets('renders MuscleBodyMap with sideBySide view', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MuscleBodyMap(
              view: BodyView.sideBySide,
              highlightedMuscles: {'chest', 'quadriceps'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MuscleBodyMap), findsOneWidget);
    });
  });
}
