import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/match.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/palette/command_palette.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/ui/themes.dart';

import 'fakes.dart';

HostView _host(String id, String label, {int? favorite}) => HostView(
  id: id,
  label: label,
  address: '$label.example.com',
  tags: const [],
  user: 'deploy',
  port: 22,
  favorite: favorite,
);

void main() {
  test('the start, a word, anywhere, then the letters in order', () {
    expect(matchScore('web-1', ''), 0);
    expect(matchScore('Web-1', 'web'), 0);
    expect(matchScore('prod-web', 'web'), 1);
    expect(matchScore('db.example.com', 'example'), 1);
    expect(matchScore('cobweb', 'web'), 2);
    expect(matchScore('bastion', 'btn'), 3);
    expect(matchScore('bastion', 'b'), 0);
    expect(matchScore('bastion', 'x'), isNull);
    expect(matchScore('bastion', 'nb'), isNull, reason: 'out of order');
  });

  testWidgets('typed: matching hosts and tabs; `>` only actions; a pick '
      'runs once the palette is gone', (tester) async {
    final app = FakeOpenWard()
      ..hostList = [
        _host('h1', 'web-1'),
        _host('h2', 'db-main', favorite: 0),
        _host('h3', 'prod-web'),
      ];
    final container = fakeContainer(app);
    container.read(tabsProvider.notifier).openPage(PageKind.settings);
    late WidgetRef ref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: materialTheme(OwThemes.grafito),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    final done = showCommandPalette(context, ref);
    await tester.pumpAndSettle();
    final query = find.byKey(const ValueKey('palette.query'));
    expect(query, findsOneWidget);
    // Before typing: the favorite, not every host.
    expect(find.byKey(const ValueKey('palette.host.db-main')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette.host.web-1')), findsNothing);

    await tester.enterText(query, 'web');
    await tester.pumpAndSettle();
    final web1 = tester.getTopLeft(
      find.byKey(const ValueKey('palette.host.web-1')),
    );
    final prod = tester.getTopLeft(
      find.byKey(const ValueKey('palette.host.prod-web')),
    );
    expect(web1.dy, lessThan(prod.dy), reason: 'the start before a word');
    expect(find.byKey(const ValueKey('palette.host.db-main')), findsNothing);

    await tester.enterText(query, '>');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('palette.host.web-1')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('palette.action.'),
      ),
      findsWidgets,
    );

    // A host picked: its tab opens, connecting, once the palette closed.
    await tester.enterText(query, 'prod');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await done;
    expect(query, findsNothing);
    expect(app.calls, contains('connect h3'));
    expect(container.read(tabsProvider).current, isA<SessionTab>());
  });
}
