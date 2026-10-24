import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/hosts/editors.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/ui/themes.dart';

/// An editor in its panel: one field, saved or not.
class _Editor extends StatefulWidget {
  const _Editor();

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _name = TextEditingController(text: 'web');

  /// The port is set here, in a field of its own; ↺ inherits it again.
  bool _port = true;

  @override
  Widget build(BuildContext context) => EditorFrame(
    title: 'Host',
    subtitle: null,
    error: null,
    onSave: () => Navigator.pop(context, true),
    snapshot: () => '${_name.text} $_port',
    children: [
      TextField(key: const ValueKey('name'), controller: _name),
      if (_port) const TextField(key: ValueKey('port')),
      TextButton(
        key: const ValueKey('reset'),
        onPressed: () => setState(() => _port = false),
        child: const Text('↺'),
      ),
    ],
  );
}

void main() {
  Future<Future<bool>> open(WidgetTester tester) async {
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.grafito),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              root = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final closed = showSidePanel(root, (_) => const _Editor());
    await tester.pumpAndSettle();
    return closed;
  }

  testWidgets('an editor without changes closes at once', (tester) async {
    final closed = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsNothing);
    expect(await closed, isFalse);
  });

  /// The focused field goes (the setting inherits again): the focus
  /// comes back to the panel, and Esc still reaches it.
  testWidgets('a field that goes with the focus leaves Esc working', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('port')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('port')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
  });

  testWidgets('with changes, Esc, Cancel and a click outside ask first', (
    tester,
  ) async {
    final closed = await open(tester);
    await tester.enterText(find.byKey(const ValueKey('name')), 'db');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('name')), findsOneWidget);

    // A click on the scrim, left of the panel.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('name')), findsNothing);
    expect(await closed, isFalse);
  });

  testWidgets('opened from a menu, with no field focused, Esc still asks', (
    tester,
  ) async {
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.grafito),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              root = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final action = showMenu<VoidCallback>(
      context: root,
      position: const RelativeRect.fromLTRB(10, 10, 10, 10),
      items: [
        PopupMenuItem(
          value: () => showSidePanel(root, (_) => const _Editor()),
          child: const Text('Editar…'),
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar…'));
    await tester.pumpAndSettle();
    (await action)?.call();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('name')), 'db');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
  });
}
