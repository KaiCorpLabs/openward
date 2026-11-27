import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/platform.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/palette/command_palette.dart';
import 'package:openward/src/rust/api/security.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/tabs/pane_header.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/ui/themes.dart';
import 'package:openward/window/menu_bar.dart';

import 'fakes.dart';

List<PlatformMenuItem> _flatten(List<PlatformMenuItem> items) => [
  for (final item in items) ...[
    item,
    if (item is PlatformMenu) ..._flatten(item.menus),
    if (item is PlatformMenuItemGroup) ..._flatten(item.members),
  ],
];

HostView _host(String id, String label) => HostView(
  id: id,
  label: label,
  address: '$label.example.com',
  tags: const [],
  user: 'deploy',
  port: 22,
  protocol: ProtocolKind.ssh,
  terminalScheme: '',
  startupSnippet: '',
);

class _SecurityCore extends FakeOpenWard {
  _SecurityCore(VaultPhase initial) {
    security = SecurityView(
      phase: initial,
      autoLockSeconds: BigInt.from(900),
      nativeEnabled: false,
      recoveryAvailable: false,
    );
  }

  void setPhase(VaultPhase phase) {
    security = SecurityView(
      phase: phase,
      autoLockSeconds: security.autoLockSeconds,
      nativeEnabled: security.nativeEnabled,
      recoveryAvailable: security.recoveryAvailable,
    );
    securityEvents.add(security);
  }
}

void main() {
  Widget wrap(
    ProviderContainer container,
    Widget child, {
    Locale locale = const Locale('es'),
    ThemeData? theme,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: theme ?? materialTheme(OwThemes.grafito),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  testWidgets(
    'OwMenuBar exposes localized macOS menus and platform items',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final app = _SecurityCore(VaultPhase.legacy);
      final container = fakeContainer(app);

      await tester.pumpWidget(
        wrap(container, const OwMenuBar(child: Scaffold(body: Text('body')))),
      );

      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final topLabels = [for (final m in bar.menus) m.label];
      expect(topLabels, ['OpenWard', 'Archivo', 'Ver', 'Ventana', 'Ayuda']);

      final all = _flatten(bar.menus);
      final provided = all
          .whereType<PlatformProvidedMenuItem>()
          .map((m) => m.type)
          .toSet();
      expect(
        provided,
        containsAll({
          PlatformProvidedMenuItemType.about,
          PlatformProvidedMenuItemType.hide,
          PlatformProvidedMenuItemType.hideOtherApplications,
          PlatformProvidedMenuItemType.showAllApplications,
          PlatformProvidedMenuItemType.quit,
          PlatformProvidedMenuItemType.toggleFullScreen,
          PlatformProvidedMenuItemType.minimizeWindow,
          PlatformProvidedMenuItemType.zoomWindow,
          PlatformProvidedMenuItemType.arrangeWindowsInFront,
        }),
      );

      final labels = {for (final m in all) m.label};
      expect(
        labels,
        containsAll([
          'Ajustes…',
          'Nueva pestaña',
          'Cerrar la pestaña',
          'Dividir a la derecha',
          'Dividir abajo',
          'Paleta de comandos',
          'Plegar o abrir la barra lateral',
          'Atajos de teclado',
        ]),
      );
      // Legacy vault has no encryption configured: no Lock vault entry.
      expect(labels, isNot(contains('Bloquear vault')));
    },
  );

  testWidgets('OwMenuBar omits PlatformMenuBar on mobile', (tester) async {
    Device.debugMobile = true;
    addTearDown(() => Device.debugMobile = null);
    final app = _SecurityCore(VaultPhase.legacy);
    final container = fakeContainer(app);

    await tester.pumpWidget(
      wrap(container, const OwMenuBar(child: Scaffold(body: Text('mobile')))),
    );

    expect(find.byType(PlatformMenuBar), findsNothing);
    expect(find.text('mobile'), findsOneWidget);
  });

  testWidgets(
    'Preferences opens Settings and Lock vault locks unlocked vault',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final app = _SecurityCore(VaultPhase.unlocked);
      final container = fakeContainer(app);

      await tester.pumpWidget(
        wrap(container, const OwMenuBar(child: Scaffold(body: Text('body')))),
      );

      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final all = _flatten(bar.menus);

      final prefs = all.firstWhere((m) => m.label == 'Ajustes…');
      expect(
        prefs.shortcut,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true),
      );
      prefs.onSelected!();
      expect(
        container.read(tabsProvider).current,
        isA<PageTab>().having((t) => t.page, 'page', PageKind.settings),
      );

      final lockItem = all.firstWhere((m) => m.label == 'Bloquear vault');
      expect(
        lockItem.shortcut,
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true),
      );
      lockItem.onSelected!();
      await tester.pump();
      expect(app.security.phase, VaultPhase.locked);
    },
  );

  testWidgets(
    'OwMenuBar never binds ⌘C, ⌘V, ⌘X, ⌘A or ⌘Z shortcuts',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final app = _SecurityCore(VaultPhase.unlocked);
      final container = fakeContainer(app);

      await tester.pumpWidget(
        wrap(container, const OwMenuBar(child: Scaffold(body: TextField()))),
      );

      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final all = _flatten(bar.menus);
      final reserved = {
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyZ,
      };

      for (final item in all) {
        final s = item.shortcut;
        if (s is SingleActivator) {
          expect(
            reserved.contains(s.trigger),
            isFalse,
            reason: '${item.label} must not bind ${s.trigger.keyLabel}',
          );
        } else if (s is CharacterActivator) {
          expect(
            const {'c', 'v', 'x', 'a', 'z'}.contains(s.character.toLowerCase()),
            isFalse,
            reason: '${item.label} must not bind ${s.character}',
          );
        }
      }
    },
  );

  testWidgets('Command palette exposes vault lock only when unlocked and uses '
      'translucent barrier scrim', (tester) async {
    final app = _SecurityCore(VaultPhase.legacy);
    final container = fakeContainer(app);
    late WidgetRef ref;

    await tester.pumpWidget(
      wrap(
        container,
        Consumer(
          builder: (context, r, _) {
            ref = r;
            return const Scaffold();
          },
        ),
      ),
    );

    final context = tester.element(find.byType(Scaffold));
    final first = showCommandPalette(context, ref);
    await tester.pumpAndSettle();

    // Scrim barrier is visible and not fully transparent.
    final barrier = tester.widget<ModalBarrier>(find.byType(ModalBarrier).last);
    expect(barrier.color, isNotNull);
    expect(barrier.color, isNot(Colors.transparent));
    expect(barrier.color!.a, greaterThan(0));
    expect(barrier.color!.a, lessThan(1));

    // Legacy vault does not offer Lock vault.
    await tester.enterText(
      find.byKey(const ValueKey('palette.query')),
      'bloquear',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('palette.action.Bloquear vault')),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await first;

    // Unlocked encrypted vault offers Lock vault and locks on selection.
    app.setPhase(VaultPhase.unlocked);
    await tester.pump();

    final second = showCommandPalette(context, ref);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('palette.query')),
      'bloquear',
    );
    await tester.pumpAndSettle();
    final lockAction = find.byKey(
      const ValueKey('palette.action.Bloquear vault'),
    );
    expect(lockAction, findsOneWidget);
    await tester.tap(lockAction);
    await tester.pumpAndSettle();
    await second;

    expect(app.security.phase, VaultPhase.locked);
  });

  testWidgets('PanePicker deduplicates local terminal when splitting local', (
    tester,
  ) async {
    final app = FakeOpenWard()..hostList = [_host('h1', 'web-1')];
    final container = fakeContainer(app);
    final tabs = container.read(tabsProvider.notifier);

    tabs.openLocal();
    final localTab = container.read(tabsProvider).current! as SessionTab;
    tabs.split(Axis.horizontal);
    final freshPane = localTab.panes.active;

    await tester.pumpWidget(
      wrap(
        container,
        Scaffold(
          body: PanePicker(tab: localTab, pane: freshPane),
        ),
      ),
    );

    // Local appears once under ESTE EQUIPO, never duplicated as "Local · el mismo host".
    expect(find.textContaining('el mismo host'), findsNothing);
    expect(find.byKey(const ValueKey('pane.choice.Local')), findsNothing);
    expect(
      find.byKey(const ValueKey('pane.choice.Terminal local')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pane.choice.web-1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('PanePicker shows same-host once when splitting a saved host', (
    tester,
  ) async {
    final web1 = _host('h1', 'web-1');
    final app = FakeOpenWard()..hostList = [web1, _host('h2', 'db-1')];
    final container = fakeContainer(app);
    final tabs = container.read(tabsProvider.notifier);

    tabs.openHost(web1);
    final hostTab = container.read(tabsProvider).current! as SessionTab;
    tabs.split(Axis.horizontal);
    final freshPane = hostTab.panes.active;

    await tester.pumpWidget(
      wrap(
        container,
        Scaffold(
          body: PanePicker(tab: hostTab, pane: freshPane),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pane.choice.web-1')), findsOneWidget);
    expect(find.textContaining('el mismo host'), findsOneWidget);
    expect(find.byKey(const ValueKey('pane.choice.db-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pane.choice.Terminal local')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
