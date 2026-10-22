import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/ui/move_draggable.dart';

void main() {
  // A row with nothing else that wants the press, as in the SFTP listings,
  // over a place to drop it.
  Future<List<String>> pump(WidgetTester tester) async {
    final dropped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const MoveDraggable<String>(
              data: 'a.txt',
              feedback: Text('badge'),
              child: SizedBox(width: 200, height: 30, child: Text('a.txt')),
            ),
            DragTarget<String>(
              onAcceptWithDetails: (d) => dropped.add(d.data),
              builder: (_, _, _) =>
                  const SizedBox(width: 200, height: 200, child: Text('here')),
            ),
          ],
        ),
      ),
    );
    return dropped;
  }

  Future<TestGesture> press(WidgetTester tester) => tester.startGesture(
    tester.getCenter(find.text('a.txt')),
    kind: PointerDeviceKind.mouse,
  );

  testWidgets('a click does not start a drag', (tester) async {
    await pump(tester);
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('badge'), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(find.text('badge'), findsNothing);
  });

  testWidgets('nor does a click that wobbles', (tester) async {
    await pump(tester);
    final gesture = await press(tester);
    await gesture.moveBy(const Offset(2, 1));
    await tester.pump();
    await gesture.moveBy(const Offset(1, -1));
    await tester.pump();
    expect(find.text('badge'), findsNothing);
    await gesture.up();
  });

  testWidgets('moving past the slop drags, and drops', (tester) async {
    final dropped = await pump(tester);
    final gesture = await press(tester);
    await gesture.moveBy(const Offset(dragSlop + 2, 0));
    await tester.pump();
    expect(find.text('badge'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.text('here')));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('badge'), findsNothing);
    expect(dropped, ['a.txt']);
  });
}
