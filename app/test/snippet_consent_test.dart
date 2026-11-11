import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/snippets/run_on_hosts.dart';
import 'package:openward/snippets/snippets.dart';
import 'package:openward/src/rust/api/snippets.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/controller.dart';
import 'package:openward/ui/themes.dart';

import 'fakes.dart';

// The renderer is native and tested there. These tests exercise consent and
// delivery with opaque output, including output that changes after review.
class _Renderer extends Fake implements RustLibApi {
  String output = '';
  @override
  String crateApiSnippetsRenderSnippet({
    required String script,
    required List<SnippetValue> values,
  }) => output;
}

SnippetView _snippet({
  bool imported = true,
  List<String> builtins = const [],
  List<String> asked = const [],
  bool typeOnly = false,
}) => SnippetView(
  id: 's1',
  rev: BigInt.one,
  spec: SnippetSpec(
    label: 'Status',
    script: 'opaque template',
    typeOnly: typeOnly,
  ),
  variables: SnippetVariables(asked: asked, builtins: builtins),
  requiresReview: imported,
);

HostView _host(String id) => HostView(
  id: id,
  label: id,
  tags: const [],
  address: '$id.example.com',
  user: 'demo',
  port: 22,
  protocol: ProtocolKind.ssh,
  terminalScheme: '',
  startupSnippet: 's1',
);

String _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  final renderer = _Renderer();
  setUpAll(() => RustLib.initMock(api: renderer));

  Future<BuildContext> window(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: materialTheme(OwThemes.grafito),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold(body: Text('terminal'));
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets(
    'imported command is complete and inert until exact text is approved',
    (tester) async {
      final app = FakeOpenWard();
      final container = fakeContainer(app);
      container.read(tabsProvider.notifier).openLocal();
      final context = await window(tester, container);
      final text = 'echo ${'x' * 500}\nsecond-command\u202E\x1b';
      renderer.output = text;
      final running = runSnippet(context, container, _snippet());
      await tester.pumpAndSettle();
      expect(app.sessions.single.sentTexts, isEmpty);
      expect(_shown(tester), contains('x' * 500));
      expect(_shown(tester), contains('second-command'));
      expect(_shown(tester), contains('⟨RLO⟩'));
      expect(_shown(tester), isNot(contains('\u202E')));
      renderer.output = 'changed-after-preview';
      await tester.tap(find.byKey(const ValueKey('snippet.review.run')));
      await tester.pumpAndSettle();
      await running;
      expect(app.sessions.single.sentTexts, ['$text\n']);
    },
  );

  testWidgets('cancelling imported commands and builtins sends nothing', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final container = fakeContainer(app);
    container.read(tabsProvider.notifier).openLocal();
    final context = await window(tester, container);
    for (final snippet in [
      _snippet(),
      _snippet(imported: false, builtins: ['host']),
    ]) {
      renderer.output = 'echo benign; unexpected-command';
      final running = runSnippet(context, container, snippet);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await running;
      expect(app.sessions.single.sentTexts, isEmpty);
      expect(app.sessions.single.pastedTexts, isEmpty);
    }
    renderer.output = 'echo own-literal';
    await runSnippet(context, container, _snippet(imported: false));
    expect(app.sessions.single.sentTexts, ['echo own-literal\n']);
  });

  testWidgets(
    'asked values send the displayed snapshot and preserve type-only',
    (tester) async {
      final app = FakeOpenWard();
      final container = fakeContainer(app);
      container.read(tabsProvider.notifier).openLocal();
      final context = await window(tester, container);
      renderer.output = 'reviewed-value';
      final running = runSnippet(
        context,
        container,
        _snippet(asked: ['value'], typeOnly: true),
      );
      await tester.pumpAndSettle();
      expect(_shown(tester), contains('reviewed-value'));
      renderer.output = 'never-reviewed';
      await tester.tap(find.byKey(const ValueKey('snippet.send')));
      await tester.pumpAndSettle();
      await running;
      expect(app.sessions.single.sentTexts, isEmpty);
      expect(app.sessions.single.pastedTexts, ['reviewed-value']);
    },
  );

  testWidgets(
    'multiple hosts are not opened before review and use approved snapshots',
    (tester) async {
      final app = FakeOpenWard()..hostList = [_host('a'), _host('b')];
      final container = fakeContainer(app);
      final context = await window(tester, container);
      renderer.output = 'echo selected-host; second-command';
      final running = showRunOnHosts(
        context,
        container,
        _snippet(builtins: ['host']),
      );
      await tester.pumpAndSettle();
      for (final id in ['a', 'b']) {
        await tester.tap(find.byKey(ValueKey('runOnHosts.host.$id')));
        await tester.pumpAndSettle();
      }
      expect(app.sessions, isEmpty);
      expect(_shown(tester), contains(renderer.output));
      renderer.output = 'changed-after-review';
      await tester.tap(find.byKey(const ValueKey('runOnHosts.run')));
      await tester.pumpAndSettle();
      await running;
      final tab = container.read(tabsProvider).current as SessionTab;
      expect(tab.panes.controllers.map((c) => c.sendWhenUp?.text), [
        'echo selected-host; second-command',
        'echo selected-host; second-command',
      ]);
    },
  );

  test(
    'startup needs review for imported commands and substituted metadata',
    () async {
      final app = FakeOpenWard();
      final c = TerminalController(app: app, label: 'a', hostId: 'a');
      addTearDown(c.dispose);
      final library = Library(hosts: [_host('a')], groups: []);
      renderer.output = 'echo original';
      for (final snippet in [
        _snippet(),
        _snippet(imported: false, builtins: ['address']),
      ]) {
        expect(await prepareStartupSnippet(library, [snippet], c), (
          text: null,
          cancelled: true,
        ));
        final review = Completer<bool>();
        final pending = prepareStartupSnippet(
          library,
          [snippet],
          c,
          review: (s, text) {
            expect(text, 'echo original');
            return review.future;
          },
        );
        renderer.output = 'changed-after-review';
        review.complete(true);
        expect(await pending, (text: 'echo original', cancelled: false));
        renderer.output = 'echo original';
      }
      expect(
        await prepareStartupSnippet(library, [_snippet(imported: false)], c),
        (text: 'echo original', cancelled: false),
      );
    },
  );
}
