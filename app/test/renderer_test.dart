import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/frame.dart';
import 'package:openward/terminal/palette.dart';
import 'package:openward/terminal/renderer.dart';

Span _span(int col, String text, {int width = 0, int attrs = 0}) => Span(
  col: col,
  width: width == 0 ? text.length : width,
  fg: 0,
  bg: 0,
  attrs: attrs,
  text: text,
);

TermFrame _frame(
  List<RowUpdate> lines, {
  int row = 0,
  int col = 0,
  bool full = true,
}) => TermFrame(
  full: full,
  cols: 20,
  rows: 3,
  cursor: TermCursor(
    row: row,
    col: col,
    shape: CursorShape.block,
    visible: true,
  ),
  displayOffset: 0,
  lines: lines,
);

void main() {
  TerminalRenderer renderer() => TerminalRenderer(
    metrics: CellMetrics.measure(),
    palette: TermPalette.grafito,
    devicePixelRatio: 1,
  );

  test('each row keeps its text; only the rows a frame repaints change', () {
    final r = renderer();
    r.apply(
      _frame([
        RowUpdate(0, [_span(0, 'ana@web:~\$'), _span(11, 'ls')]),
        RowUpdate(1, [_span(0, 'notes.txt')]),
      ]),
    );
    expect(r.rowText(0), r'ana@web:~$ ls');
    expect(r.rowText(1), 'notes.txt');
    expect(r.rowText(2), '');
    final told = r.screen.value;
    // The same text again: nothing to tell a screen reader.
    r.apply(
      _frame([
        RowUpdate(1, [_span(0, 'notes.txt')]),
      ], full: false),
    );
    expect(r.screen.value, told);
    r.apply(
      _frame(
        [
          RowUpdate(2, [_span(0, 'done')]),
        ],
        full: false,
        row: 2,
      ),
    );
    expect(r.rowText(0), r'ana@web:~$ ls', reason: 'not repainted, kept');
    expect(r.rowText(2), 'done');
    expect(r.screen.value, greaterThan(told));
    r.dispose();
  });

  testWidgets('a screen reader reads the screen by rows, the cursor\'s as a '
      'text field', (tester) async {
    final r = renderer();
    addTearDown(r.dispose);
    r.apply(
      _frame([
        RowUpdate(0, [_span(0, 'uptime')]),
        RowUpdate(1, [_span(0, 'up 3 days')]),
      ], row: 2),
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: TerminalGrid(
            renderer: r,
            cols: 20,
            rows: 3,
            cursorLabel: 'Línea del cursor',
          ),
        ),
      ),
    );
    expect(find.semantics.byLabel('uptime'), findsOne);
    expect(find.semantics.byLabel('up 3 days'), findsOne);
    final cursor = find.semantics.byLabel('Línea del cursor').evaluate().single;
    expect(cursor.flagsCollection.isTextField, isTrue);
    expect(cursor.value, '');
    // Typed on the cursor's row: its value follows.
    r.apply(
      _frame(
        [
          RowUpdate(2, [_span(0, r'$ whoami')]),
        ],
        full: false,
        row: 2,
        col: 8,
      ),
    );
    await tester.pump();
    expect(
      find.semantics.byLabel('Línea del cursor').evaluate().single.value,
      r'$ whoami',
    );
    semantics.dispose();
  });

  test('the block cursor takes a wide character whole', () {
    final r = renderer();
    r.apply(
      _frame([
        RowUpdate(0, [_span(0, 'a'), _span(1, '漢', width: 2)]),
      ], col: 1),
    );
    expect(r.cellAt(0, 1), (text: '漢', col: 1, cells: 2, attrs: 0));
    expect(r.cellAt(0, 2)?.col, 1, reason: 'its second half too');
    expect(r.cellAt(0, 0)?.cells, 1);
    expect(r.cellAt(0, 5), isNull, reason: 'an empty cell');
    // Painting, focused (solid) or not (hollow).
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    r.paint(canvas, const Size(200, 60));
    r.setFocused(false);
    r.paint(canvas, const Size(200, 60));
    recorder.endRecording().dispose();
    expect(r.rowText(0), 'a漢');
    r.dispose();
  });
}
