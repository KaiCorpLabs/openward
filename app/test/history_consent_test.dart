import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/history/history.dart';
import 'package:openward/history/line_tracker.dart';
import 'package:openward/history/replay.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/controller.dart';
import 'package:openward/terminal/send_target.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/ui/themes.dart';

import 'fakes.dart';

String shown(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .join('\n');

Future<BuildContext> window(WidgetTester tester, ProviderContainer ref) async {
  late BuildContext context;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ref,
      child: MaterialApp(
        theme: materialTheme(OwThemes.grafito),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

TerminalController open(ProviderContainer ref) {
  ref.read(tabsProvider.notifier).openLocal();
  return ref.read(tabsProvider).currentSession!..phase = Phase.running;
}

HistoryEntry saved(
  ProviderContainer ref,
  TerminalController c,
  String text, {
  CommandOrigin origin = CommandOrigin.unknown,
}) {
  ref.read(historyProvider.notifier).add(text, c, origin: origin);
  ref.read(historyProvider.notifier).flush();
  return ref.read(historyProvider).first;
}

void main() {
  testWidgets('replay respects an existing private-line opt-out', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final ref = fakeContainer(app);
    final c = open(ref);
    final context = await window(tester, ref);
    final entry = saved(ref, c, 'echo own', origin: CommandOrigin.own);
    c.line.text(' private', _Screen());
    expect(await replayHistory(context, ref, entry), 1);
    expect(ref.read(historyProvider).single.count, 1);
    expect(app.sessions.single.sentTexts, ['echo own\n']);
  });
  testWidgets('legacy output stays inert until the full snapshot is approved', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final ref = fakeContainer(app);
    final c = open(ref);
    c.customTitle = 'original destination';
    final context = await window(tester, ref);
    final text = '${'x' * 700}😀\nTAIL\x1b\u202e';
    final entry = saved(ref, c, text);
    final pending = replayHistory(context, ref, entry);
    await tester.pumpAndSettle();
    expect(app.sessions.first.sentTexts, isEmpty);
    expect(shown(tester), contains('x' * 700));
    expect(shown(tester), contains('😀␊TAIL␛⟨RLO⟩␊'));
    expect(
      shown(tester),
      contains('origin of this older history entry is unknown'),
    );
    expect(shown(tester), contains('original destination'));
    // Changing tabs and title cannot change the approved recipient/text.
    open(ref);
    c.customTitle = 'renamed after review';
    await tester.tap(find.byKey(const ValueKey('history.review.send')));
    await tester.pumpAndSettle();
    expect(await pending, 1);
    ref.read(historyProvider.notifier).flush();
    expect(app.sessions.first.sentTexts, ['$text\n']);
    expect(app.sessions.last.sentTexts, isEmpty);
    expect(ref.read(historyProvider).first.origin, CommandOrigin.unknown);
    expect(ref.read(historyProvider).first.count, 2);
  });

  testWidgets('Enter cancels review and never increments history', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final ref = fakeContainer(app);
    final c = open(ref);
    final context = await window(tester, ref);
    final entry = saved(ref, c, 'echo screen', origin: CommandOrigin.screen);
    final pending = replayHistory(context, ref, entry);
    await tester.pumpAndSettle();
    expect(shown(tester), contains('Reconstructed from terminal output'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await pending, 0);
    expect(app.sessions.single.sentTexts, isEmpty);
    expect(ref.read(historyProvider).single.count, 1);
  });

  testWidgets('own plain command in the same context preserves the fast path', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final ref = fakeContainer(app);
    final c = open(ref);
    final context = await window(tester, ref);
    final entry = saved(ref, c, 'echo own', origin: CommandOrigin.own);
    expect(await replayHistory(context, ref, entry), 1);
    ref.read(historyProvider.notifier).flush();
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.sessions.single.sentTexts, ['echo own\n']);
    expect(ref.read(historyProvider).single.origin, CommandOrigin.own);
    expect(ref.read(historyProvider).single.count, 2);
  });

  testWidgets('own cross-host or hidden text requires review, also type-only', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final ref = fakeContainer(app);
    open(ref);
    final context = await window(tester, ref);
    for (final entry in [
      const HistoryEntry(
        command: 'echo remote',
        where: 'host:remote',
        label: 'Remote',
        at: 1,
        origin: CommandOrigin.own,
        binding: 'remote',
      ),
      const HistoryEntry(
        command: 'echo hidden\t\x1b',
        where: 'local',
        label: 'Local',
        at: 1,
        origin: CommandOrigin.own,
        binding: 'local',
      ),
    ]) {
      final pending = replayHistory(context, ref, entry, typeOnly: true);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(app.sessions.single.pastedTexts, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await pending, 0);
    }
  });

  testWidgets(
    'type-only preserves bytes and does not promote screen provenance',
    (tester) async {
      final app = FakeOpenWard();
      final ref = fakeContainer(app);
      final c = open(ref);
      final context = await window(tester, ref);
      final entry = saved(ref, c, 'echo screen', origin: CommandOrigin.screen);
      final pending = replayHistory(context, ref, entry, typeOnly: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history.review.send')));
      await tester.pumpAndSettle();
      expect(await pending, 1);
      ref.read(historyProvider.notifier).flush();
      expect(app.sessions.single.pastedTexts, ['echo screen']);
      expect(app.sessions.single.sentTexts, isEmpty);
      expect(ref.read(historyProvider).single.count, 1);
      expect(c.line.plainTyped, isNull);
    },
  );

  testWidgets(
    'replacement shell invalidates consent without delivery or count',
    (tester) async {
      final app = FakeOpenWard();
      final ref = fakeContainer(app);
      final c = open(ref);
      final context = await window(tester, ref);
      final entry = saved(ref, c, 'echo old');
      final pending = replayHistory(context, ref, entry);
      await tester.pumpAndSettle();
      c.onEvent(event(SessionEventKind.closed));
      c.phase = Phase.running;
      await tester.tap(find.byKey(const ValueKey('history.review.send')));
      await tester.pumpAndSettle();
      expect(await pending, 0);
      expect(app.sessions.single.sentTexts, isEmpty);
      expect(ref.read(historyProvider).single.count, 1);
    },
  );

  testWidgets('broadcast approves only the frozen recipient set', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final ref = fakeContainer(app);
    final a = open(ref)..customTitle = 'first';
    final tab = ref.read(tabsProvider).current as SessionTab;
    final b = TerminalController(app: app, label: 'second')
      ..phase = Phase.running;
    tab.panes.insertBeside(tab.panes.active, Pane(b), DropSide.right);
    tab.panes.active = tab.panes.leaves.first;
    tab.panes.setBroadcast(true);
    final context = await window(tester, ref);
    final entry = saved(ref, a, 'echo broadcast', origin: CommandOrigin.own);
    final pending = replayHistory(context, ref, entry);
    await tester.pumpAndSettle();
    expect(shown(tester), contains('first'));
    expect(shown(tester), contains('second'));
    final other = TerminalController(app: app, label: 'not approved')
      ..phase = Phase.running;
    tab.panes.insertBeside(tab.panes.active, Pane(other), DropSide.right);
    tab.panes.setBroadcast(true);
    await tester.tap(find.byKey(const ValueKey('history.review.send')));
    await tester.pumpAndSettle();
    expect(await pending, 2);
    ref.read(historyProvider.notifier).flush();
    expect(app.sessions[0].sentTexts, ['echo broadcast\n']);
    expect(app.sessions[1].sentTexts, ['echo broadcast\n']);
    expect(app.sessions[2].sentTexts, isEmpty);
  });

  test('captured delivery refuses closed, replaced and disposed shells', () {
    final app = FakeOpenWard();
    final c = TerminalController(app: app, label: 'here')
      ..phase = Phase.running;
    final first = TerminalSendTarget(c);
    expect(first.paste('text', allowUnsafe: true), isTrue);
    c.onEvent(event(SessionEventKind.closed));
    c.phase = Phase.running;
    expect(first.execute('stale'), isFalse);
    expect(first.paste('stale', allowUnsafe: true), isFalse);
    final next = TerminalSendTarget(c);
    c.dispose();
    expect(next.execute('closed'), isFalse);
    expect(app.sessions.single.sentTexts, isEmpty);
    expect(app.sessions.single.pastedTexts, ['text']);
  });
}

class _Screen implements LineScreen {
  @override
  int get cursorRow => 0;
  @override
  ({String text, String after}) typedFrom(int row) => (text: '\$ ', after: '');
}
