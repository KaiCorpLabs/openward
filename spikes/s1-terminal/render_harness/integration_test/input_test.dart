// Spike S1.5: input routing end to end, on the real engine and pty.
//
//   fvm flutter test integration_test/input_test.dart -d macos
//
// Keys go through the framework as on a hardware keyboard; IME input is
// delivered the way the platform does it, through updateEditingValue.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:render_harness/shell/shell_page.dart';
import 'package:render_harness/src/rust/frb_generated.dart';
import 'package:render_harness/term/renderer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  Future<ShellPageState> open(WidgetTester tester, String program) async {
    await tester.pumpWidget(MaterialApp(home: ShellPage(program: program)));
    final state = tester.state<ShellPageState>(find.byType(ShellPage));
    await until(tester, () => state.session != null);
    await tester.pump();
    return state;
  }

  String screen(ShellPageState s) => s.session!.screenText();

  /// Lines the key log printed, without the banner.
  List<String> logged(ShellPageState s) => screen(s)
      .split('\n')
      .where((l) => l.startsWith('→ '))
      .map((l) => l.substring(2).replaceFirst(RegExp(r'\s+\(\d+ B\)\s*$'), ''))
      .toList();

  TextEditingValue typed(String text, {TextRange? composing}) {
    final full = '  $text';
    return TextEditingValue(
      text: full,
      selection: TextSelection.collapsed(offset: full.length),
      composing: composing ?? TextRange.empty,
    );
  }

  testWidgets('functional keys and chords go through the encoder', (
    tester,
  ) async {
    final s = await open(tester, keyLog);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    // A plain printable key is left to the input method: nothing here.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(logged(s), ['␛[A', '␛[15~', '␛', '␛[Z', '^C']);
  });

  testWidgets('modes the program sets change the encoding', (tester) async {
    final s = await open(tester, keyLog);
    s.session!.inject(bytes: '\x1b[?1h'.codeUnits); // DECCKM
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    s.session!.inject(bytes: '\x1b[=1;1u'.codeUnits); // kitty: disambiguate
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(logged(s), ['␛OA', '␛[27u']);
  });

  testWidgets('IME: composition stays local until committed', (tester) async {
    final s = await open(tester, keyLog);
    s.updateEditingValue(typed('a'));
    s.updateEditingValue(
      typed('にほ', composing: const TextRange(start: 2, end: 4)),
    );
    await tester.pump();
    expect(find.text('にほ'), findsOneWidget, reason: 'drawn at the cursor');
    expect(logged(s), ['a']);
    s.updateEditingValue(typed('日本'));
    await tester.pump();
    expect(find.text('にほ'), findsNothing);
    // Soft keyboard: deleting into the placeholder is Backspace, a newline
    // is Enter.
    s.updateEditingValue(const TextEditingValue(text: ' '));
    s.updateEditingValue(typed('ls\n'));
    await tester.pump();
    expect(logged(s), ['a', '日本', '^?', 'ls^M']);
  });

  testWidgets('key bar: sticky Ctrl applies to the next character', (
    tester,
  ) async {
    final s = await open(tester, keyLog);
    final bar = find.byIcon(Icons.keyboard_alt_outlined);
    if (find.text('ctrl').evaluate().isEmpty) await tester.tap(bar);
    await settle(tester);
    await tester.tap(find.text('esc'));
    await tester.tap(find.text('ctrl'));
    await tester.pump();
    s.updateEditingValue(typed('c'));
    await tester.tap(find.text('↑'));
    await tester.pump();
    expect(logged(s), ['␛', '^C', '␛[A']);
  });

  testWidgets('mouse is reported only when the program tracks it', (
    tester,
  ) async {
    final s = await open(tester, keyLog);
    final grid = tester.getTopLeft(find.byType(TerminalView));
    Future<void> click(Offset at) async {
      final g = await tester.startGesture(
        grid + at,
        kind: PointerDeviceKind.mouse,
      );
      await g.up();
      await tester.pump();
    }

    await click(const Offset(3, 3));
    expect(logged(s), isEmpty);
    s.session!.inject(bytes: '\x1b[?1000h\x1b[?1006h'.codeUnits);
    await tester.pump(); // the next frame tells the UI tracking is on
    await tester.pump();
    await click(const Offset(3, 3));
    expect(logged(s), ['␛[<0;1;1M', '␛[<0;1;1m']);
  });

  testWidgets('multi-line paste asks first', (tester) async {
    final s = await open(tester, keyLog);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'echo uno\necho dos'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byIcon(Icons.content_paste));
    await settle(tester);
    expect(find.text('¿Pegar varias líneas?'), findsOneWidget);
    expect(logged(s), isEmpty);
    await tester.tap(find.text('Pegar'));
    await settle(tester);
    expect(logged(s), ['echo uno^Mecho dos']);

    // Bracketed: no question, framed.
    s.session!.inject(bytes: '\x1b[?2004h'.codeUnits);
    await tester.tap(find.byIcon(Icons.content_paste));
    await settle(tester);
    expect(find.text('¿Pegar varias líneas?'), findsNothing);
    expect(logged(s).last, '␛[200~echo uno^Jecho dos␛[201~');
  });

  testWidgets('a real shell runs what is typed', (tester) async {
    final s = await open(tester, '/bin/sh');
    s.updateEditingValue(
      typed(
        r'echo s1-$((6*7))'
        '\n',
      ),
    );
    await until(tester, () => screen(s).contains('s1-42'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await until(
      tester,
      () => find.textContaining('proceso terminado').evaluate().isNotEmpty,
    );
  });
}

Future<void> until(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for a condition');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The terminal polls the engine on every frame, so pumpAndSettle would
/// never return: pump long enough for dialogs and their animations.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
