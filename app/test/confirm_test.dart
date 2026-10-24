import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/ui/confirm.dart';
import 'package:openward/ui/focus_ring.dart';
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
  /// Enter does what the focused button says: going ahead when nothing is
  /// lost, staying when something would be.
  testWidgets('a confirmation: Enter and Esc, by what it risks', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      _app(
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () async => answer = await confirmAction(
                context,
                title: 'Abrir las tres',
                action: 'Abrir',
              ),
              child: const Text('safe'),
            ),
            TextButton(
              onPressed: () async => answer = await confirmDestructive(
                context,
                title: 'Borrar web',
                action: 'Borrar',
              ),
              child: const Text('danger'),
            ),
          ],
        ),
      ),
    );
    for (final (button, key, expected) in [
      ('safe', LogicalKeyboardKey.enter, true),
      ('safe', LogicalKeyboardKey.escape, false),
      ('danger', LogicalKeyboardKey.enter, false),
      ('danger', LogicalKeyboardKey.escape, false),
    ]) {
      answer = null;
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(answer, expected, reason: '$button, $key');
    }
  });

  /// The ring shows where the keyboard is, and not after a click.
  testWidgets('the focus ring: with the keyboard only', (tester) async {
    KeyboardMode.watch();
    await tester.pumpWidget(
      _app(
        (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(onPressed: () {}, child: const Text('uno')),
            FilledButton(onPressed: () {}, child: const Text('dos')),
          ],
        ),
      ),
    );
    BorderSide? side(String text) {
      final material = tester.widget<Material>(
        find
            .ancestor(of: find.text(text), matching: find.byType(Material))
            .first,
      );
      return (material.shape as OutlinedBorder?)?.side;
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(side('uno')!.width, 2, reason: 'reached with Tab');
    expect(side('uno')!.strokeAlign, BorderSide.strokeAlignOutside);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(side('dos')!.width, 2);
    // Grafito's main button is in the accent: its ring is not.
    final c = OwThemes.grafito.colors;
    expect(side('dos')!.color, c.text);
    await tester.tap(find.text('dos'));
    await tester.pump();
    expect(side('dos')!.width, isNot(2), reason: 'a click');
  });
}
