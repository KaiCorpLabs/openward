import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/terminal/paste.dart';
import 'package:openward/ui/themes.dart';

Widget _app(Widget Function(BuildContext) button) => MaterialApp(
  theme: materialTheme(OwThemes.grafito),
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: Builder(builder: button)),
  ),
);

void main() {
  for (final broadcast in [false, true]) {
    testWidgets('complete paste review, broadcast=$broadcast', (tester) async {
      // The former 400/600 UTF-16 cut also split this emoji in half.
      final prefix = List.filled(broadcast ? 599 : 399, 'a').join();
      final text =
          '$prefix😀\n${List.filled(80, 'echo reviewed line').join('\n')}\nTAIL\u001b[201~\u202e';
      bool? answer;
      var completed = false;
      await tester.pumpWidget(
        _app(
          (context) => TextButton(
            onPressed: () async {
              answer = broadcast
                  ? await confirmBroadcastPaste(
                      context,
                      text,
                      here: 'local',
                      names: ['local', 'server'],
                    )
                  : await confirmPaste(context, text);
              completed = true;
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.widget<PastePreview>(find.byType(PastePreview)).text, text);
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(PastePreview),
          matching: find.byType(RichText),
        ),
      );
      final visible = rich.text.toPlainText();
      expect(visible, contains('😀'));
      expect(visible, contains('TAIL␛[201~⟨RLO⟩'));
      expect(visible, isNot(contains(String.fromCharCode(0xfffd))));
      final scroll = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .reduce(
            (a, b) =>
                a.position.maxScrollExtent > b.position.maxScrollExtent ? a : b,
          );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(answer, broadcast ? isNull : isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('broadcast keeps cancel, only here and all choices', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      _app(
        (context) => TextButton(
          onPressed: () async => answer = await confirmBroadcastPaste(
            context,
            'echo one\necho two',
            here: 'local',
            names: ['local', 'server'],
          ),
          child: const Text('open'),
        ),
      ),
    );
    for (final all in [false, true]) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (all) {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(FilledButton),
          ),
        );
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pumpAndSettle();
      expect(answer, all);
    }
  });
}
