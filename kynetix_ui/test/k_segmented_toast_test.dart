import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/ui/k_segmented.dart';
import 'package:kynetix/ui/k_toast.dart';

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int value = 0;
  @override
  Widget build(BuildContext context) => KSegmented<int>(
        segments: const [KSegment(0, 'Week'), KSegment(1, 'Month'), KSegment(2, 'Year')],
        value: value,
        onChanged: (v) => setState(() => value = v),
      );
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))));

void main() {
  testWidgets('KSegmented selects on tap, speaks selection, and goes idle', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Host()));
    expect(tester.getSemantics(find.bySemanticsLabel('Week')), containsSemantics(isSelected: true, isButton: true, isInMutuallyExclusiveGroup: true));

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(tester.state<_HostState>(find.byType(_Host)).value, 2);
    expect(tester.getSemantics(find.bySemanticsLabel('Year')), containsSemantics(isSelected: true, isButton: true, isInMutuallyExclusiveGroup: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Week')), containsSemantics(isSelected: false));
    // No ticker left running once the thumb has landed.
    expect(tester.binding.hasScheduledFrame, isFalse);
    semantics.dispose();
  });

  testWidgets('KToast shows, runs its action once, and reports why it closed', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));

    var undone = 0;
    final closed = showKToast(ctx, 'Deleted dal.', actionLabel: 'Undo', onAction: () => undone++);
    await tester.pumpAndSettle();
    expect(find.text('Deleted dal.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(await closed, KToastClose.action);
    expect(find.text('Deleted dal.'), findsNothing);
  });

  testWidgets('KToast: one at a time, and it times out', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));

    final first = showKToast(ctx, 'First');
    await tester.pump(const Duration(milliseconds: 300));
    showKToast(ctx, 'Second', kind: KToastKind.error);
    await tester.pumpAndSettle();
    expect(await first, KToastClose.replaced);
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });
}
