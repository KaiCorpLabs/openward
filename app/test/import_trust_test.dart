import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/hosts/editors.dart' show EditorFrame;
import 'package:openward/import/program_preview.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/src/rust/api/programs.dart';
import 'package:openward/ui/themes.dart';

void main() {
  testWidgets('trust is unchecked, complete, visible and selected per entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longLine = '@cert-authority * ssh-ed25519 ${'A' * 450} end-of-entry';
    final preview = ProgramPreview(
      program: ProgramKind.termius,
      items: const [],
      identities: 0,
      newIdentities: 0,
      newTunnels: 0,
      newSnippets: 0,
      newKnownHosts: 2,
      knownHosts: [
        ProgramKnownHost(id: '0', line: longLine, fingerprint: 'SHA256:first'),
        const ProgramKnownHost(
          id: '1',
          line: 'host\u202E ssh-ed25519 AAAA',
          fingerprint: 'SHA256:second',
        ),
      ],
      keys: const [],
      warnings: const [],
      passwords: 0,
      passphrases: 0,
    );
    ProgramChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.grafito),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('es'),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async =>
                  choice = await showProgramPreview(context, preview),
              child: const Text('open preview'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open preview'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditorFrame>(find.byType(EditorFrame)).saveEnabled,
      isFalse,
    );
    for (final tile in tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    )) {
      expect(tile.value, isFalse);
    }
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .join('\n');
    expect(shown, contains(longLine), reason: 'the end must not be cut');
    expect(shown, contains('⟨RLO⟩'));
    expect(shown, isNot(contains('\u202E')));
    expect(shown, contains('SHA256:first'));

    final selected = find.descendant(
      of: find.byKey(const ValueKey('import.known.0')),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(selected);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    final editor = tester.widget<EditorFrame>(find.byType(EditorFrame));
    expect(editor.saveEnabled, isTrue);
    editor.onSave();
    await tester.pumpAndSettle();
    expect(choice?.knownHosts, ['0']);
    expect(choice?.hosts, isEmpty);
  });
}
