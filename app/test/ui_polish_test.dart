import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/local_documents.dart';
import 'package:openward/core/platform.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/hosts/rail.dart';
import 'package:openward/hosts/sidebar.dart';
import 'package:openward/keys/key_dialogs.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/settings/settings_page.dart';
import 'package:openward/src/rust/api/identities.dart';
import 'package:openward/src/rust/api/keychain.dart';
import 'package:openward/src/rust/api/logs.dart';
import 'package:openward/src/rust/api/security.dart';
import 'package:openward/src/rust/api/tunnels.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tab_strip.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/palette.dart';
import 'package:openward/ui/environment.dart';
import 'package:openward/ui/themes.dart';
import 'package:openward/ui/tokens.dart';
import 'package:openward/ui/widgets.dart';

import 'fakes.dart';

class _MockRustApi extends Fake implements RustLibApi {
  @override
  String crateApiAppCoreVersion() => '0.1.0-test';
}

class _UiPolishCore extends FakeOpenWard {
  _UiPolishCore({bool unlocked = false}) {
    if (unlocked) {
      security = SecurityView(
        phase: VaultPhase.unlocked,
        autoLockSeconds: BigInt.from(900),
        nativeEnabled: false,
        recoveryAvailable: true,
      );
    }
  }

  final Map<LocalDocument, String> _docs = {};

  @override
  Future<List<SshKey>> keys() async => const [];

  @override
  String keyComment() => 'test@openward';

  @override
  Future<List<IdentityView>> identities() async => const [];

  @override
  List<TunnelView> tunnels() => const [];

  @override
  Stream<bool> watchTunnels() => const Stream.empty();

  @override
  Future<int> knownHostCount() async => 0;

  @override
  List<LogEntry> logs() => const [];

  @override
  Stream<bool> watchLogs() => const Stream.empty();

  @override
  LogsConfig logsConfig() => LogsConfig(
    recordLocal: false,
    keepDays: 30,
    maxBytes: BigInt.from(1024 * 1024 * 1024),
  );

  @override
  LogsUsage logsUsage() =>
      LogsUsage(entries: 0, recorded: 0, saved: 0, bytes: BigInt.zero);

  @override
  List<LogSetIn> logsSetIn() => const [];

  @override
  String logsDir() => '/tmp/openward-logs';

  @override
  int unreadableItems() => 0;

  @override
  String? readLocalDocument({required LocalDocument kind}) => _docs[kind];

  @override
  void writeLocalDocument({required LocalDocument kind, required String json}) {
    _docs[kind] = json;
  }

  @override
  void eraseLocalDocument({required LocalDocument kind}) => _docs.remove(kind);
}

Widget _app({
  required ProviderContainer container,
  required Widget child,
  OwTheme? theme,
  Locale locale = const Locale('es'),
  TargetPlatform? platform,
  double textScale = 1.0,
}) {
  final effectiveTheme = theme ?? OwThemes.grafito;
  var themeData = materialTheme(effectiveTheme);
  if (platform != null) {
    themeData = themeData.copyWith(platform: platform);
  }
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: themeData,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, body) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: body!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

HostView _host({
  required String id,
  required String label,
  int? favorite,
  EnvironmentView? environment,
  SystemView? system,
}) => HostView(
  id: id,
  label: label,
  address: '10.0.0.1',
  tags: const [],
  user: 'deploy',
  port: 22,
  favorite: favorite,
  environment: environment,
  system: system,
  protocol: ProtocolKind.ssh,
  terminalScheme: '',
  startupSnippet: '',
);

void main() {
  setUpAll(() => RustLib.initMock(api: _MockRustApi()));

  testWidgets(
    'TabStyle.pill active StatusDot uses high-contrast onPrimary color',
    (tester) async {
      final core = _UiPolishCore();
      final container = fakeContainer(core);
      final tabs = container.read(tabsProvider.notifier);
      tabs.openLocal();
      tabs.openLocal();
      tabs.select(0);

      await tester.pumpWidget(
        _app(
          container: container,
          theme: OwThemes.catppuccinMocha,
          child: const TabStrip(),
        ),
      );
      await tester.pump();

      final dots = tester
          .widgetList<StatusDot>(find.byType(StatusDot))
          .toList();
      expect(dots, hasLength(2));
      final activeDot = dots[0];
      final inactiveDot = dots[1];
      expect(
        activeDot.onAccent,
        OwThemes.catppuccinMocha.colors.onPrimary,
        reason: 'active pill dot must contrast with primary == accent',
      );
      expect(
        TermPalette.contrast(
          activeDot.onAccent!,
          OwThemes.catppuccinMocha.colors.primary,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(inactiveDot.onAccent, isNull);
    },
  );

  group('Secure Enclave and Security Keys platform gating', () {
    tearDown(() {
      Device.debugMobile = null;
      Device.debugSecureEnclave = null;
    });

    test('Device platform capabilities gate mobile and Secure Enclave', () {
      Device.debugMobile = true;
      expect(Device.securityKeys, isFalse);
      expect(Device.supportsSecureEnclaveFor(TargetPlatform.iOS), isTrue);
      expect(Device.supportsSecureEnclaveFor(TargetPlatform.android), isFalse);
      expect(Device.supportsSecureEnclaveFor(TargetPlatform.linux), isFalse);

      Device.debugMobile = false;
      expect(Device.securityKeys, isTrue);
      expect(Device.supportsSecureEnclaveFor(TargetPlatform.macOS), isTrue);
      expect(Device.supportsSecureEnclaveFor(TargetPlatform.windows), isFalse);
    });

    testWidgets(
      'iOS shows Secure Enclave without security key option; Android hides both',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        Future<void> openFor(
          TargetPlatform platform, {
          required bool mobile,
        }) async {
          Device.debugMobile = mobile;
          final core = _UiPolishCore(unlocked: true);
          final container = fakeContainer(core);
          await tester.pumpWidget(
            _app(
              container: container,
              platform: platform,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showNewKeyDialog(context),
                  child: const Text('open-dialog'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open-dialog'));
          await tester.pumpAndSettle();
        }

        // iOS: Secure Enclave visible, FIDO2 security key hidden.
        await openFor(TargetPlatform.iOS, mobile: true);
        expect(find.byKey(const ValueKey('newKey.enclave')), findsOneWidget);
        expect(find.byKey(const ValueKey('newKey.onKey')), findsNothing);
        expect(find.byKey(const ValueKey('newKey.make')), findsOneWidget);

        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();

        // Android: both Secure Enclave and FIDO2 security key hidden.
        await openFor(TargetPlatform.android, mobile: true);
        expect(find.byKey(const ValueKey('newKey.enclave')), findsNothing);
        expect(find.byKey(const ValueKey('newKey.onKey')), findsNothing);
        expect(find.byKey(const ValueKey('newKey.make')), findsOneWidget);

        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();

        // macOS desktop: both Secure Enclave and FIDO2 security key visible.
        await openFor(TargetPlatform.macOS, mobile: false);
        expect(find.byKey(const ValueKey('newKey.enclave')), findsOneWidget);
        expect(find.byKey(const ValueKey('newKey.onKey')), findsOneWidget);
        expect(find.byKey(const ValueKey('newKey.make')), findsOneWidget);
      },
    );
  });

  group('Settings polish', () {
    test('formatOperatingSystem formats platform names cleanly', () {
      expect(formatOperatingSystem('macos'), 'macOS');
      expect(formatOperatingSystem('ios'), 'iOS');
      expect(formatOperatingSystem('linux'), 'Linux');
      expect(formatOperatingSystem('windows'), 'Windows');
      expect(formatOperatingSystem('android'), 'Android');
    });

    testWidgets(
      'General styling, OS display name, and Terminal section spacing',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final core = _UiPolishCore();
        final container = fakeContainer(core);
        await tester.pumpWidget(
          _app(
            container: container,
            locale: const Locale('es'),
            child: const SettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        // Preserved keys in General.
        expect(
          find.byKey(const ValueKey('settings.terminalPadding')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('settings.sidebar')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('settings.sidebarOnSession')),
          findsOneWidget,
        );

        // Formatted OS name in About card.
        expect(
          find.textContaining('${formatOperatingSystem()} · '),
          findsOneWidget,
        );

        // Option as Alt styling matches surrounding DropdownButtons.
        final optionDropdownFinder = find.byKey(
          const ValueKey('settings.optionAsAlt'),
        );
        if (optionDropdownFinder.evaluate().isNotEmpty) {
          final dropdown = tester.widget<DropdownButton<OptionAltChoice>>(
            optionDropdownFinder,
          );
          expect(dropdown.style?.fontSize, 13);
          expect(dropdown.underline, isNot(isA<SizedBox>()));
        }

        // Terminal section spacing before RATÓN, RESALTADO, ATAJOS.
        await tester.tap(
          find.byKey(const ValueKey('settings.section.terminal')),
        );
        await tester.pumpAndSettle();

        final column = tester.widget<Column>(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Column &&
                  w.children.any((c) => c is SectionLabel && c.text == 'Ratón'),
            ),
          ),
        );
        for (final label in ['Ratón', 'Resaltado', 'Atajos']) {
          final index = column.children.indexWhere(
            (w) => w is SectionLabel && w.text == label,
          );
          expect(index, greaterThan(0));
          final prev = column.children[index - 1];
          expect(prev, isA<SizedBox>());
          expect((prev as SizedBox).height, 24);
        }
      },
    );
  });

  group('Appearance layout', () {
    testWidgets(
      'En claro and En oscuro align together and preview stays sticky while scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 620);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final core = _UiPolishCore();
        final container = fakeContainer(core);
        container
            .read(settingsSectionProvider.notifier)
            .show(SettingsSection.appearance);

        await tester.pumpWidget(
          _app(
            container: container,
            locale: const Locale('es'),
            child: const SettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Claro'), findsAtLeastNWidgets(1));
        expect(find.text('13 px'), findsOneWidget);
        final sampleFinder = find.byKey(
          const ValueKey('appearance.terminalSample'),
        );
        expect(sampleFinder, findsOneWidget);

        // En claro and En oscuro sit together below the SegmentedButton on the same row.
        final lightLabel = tester.getTopLeft(find.text('En claro').first);
        final darkLabel = tester.getTopLeft(find.text('En oscuro').first);
        final segmentedBottom = tester
            .getBottomLeft(find.byType(SegmentedButton<ThemeChoice>))
            .dy;
        expect(lightLabel.dy, greaterThan(segmentedBottom));
        expect((lightLabel.dy - darkLabel.dy).abs(), lessThan(4));

        // Scrolling the appearance form keeps preview sticky on screen.
        final beforeRect = tester.getRect(sampleFinder);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        final afterRect = tester.getRect(sampleFinder);
        expect(afterRect.top, closeTo(beforeRect.top, 1.0));
        expect(afterRect.top, greaterThanOrEqualTo(0));
      },
    );

    testWidgets(
      'Narrow mobile viewport shows sticky preview above controls without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final core = _UiPolishCore();
        final container = fakeContainer(core);
        container
            .read(settingsSectionProvider.notifier)
            .show(SettingsSection.appearance);

        await tester.pumpWidget(
          _app(
            container: container,
            locale: const Locale('es'),
            textScale: 1.3,
            child: const SettingsPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final sampleFinder = find.byKey(
          const ValueKey('appearance.terminalSample'),
        );
        expect(sampleFinder, findsOneWidget);
        final before = tester.getRect(sampleFinder);
        final segmentedTop = tester
            .getTopLeft(find.byType(SegmentedButton<ThemeChoice>))
            .dy;
        expect(before.bottom, lessThan(segmentedTop));

        await tester.drag(
          find
              .byWidgetPredicate(
                (w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.vertical,
              )
              .last,
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(sampleFinder).top, closeTo(before.top, 1.0));
      },
    );
  });

  group('Sidebar and Rail polish', () {
    testWidgets(
      'Sidebar library switches to full-width rows without truncation in Spanish Fósforo at 130% text scale and keeps Nuevo host single-line',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final core = _UiPolishCore()
          ..hostList = [_host(id: 'h1', label: 'prod-web')];
        final container = fakeContainer(core);
        final focus = FocusNode();
        addTearDown(focus.dispose);

        await tester.pumpWidget(
          _app(
            container: container,
            theme: OwThemes.fosforo,
            locale: const Locale('es'),
            textScale: 1.3,
            child: SizedBox(
              width: 260,
              height: 820,
              child: Sidebar(searchFocus: focus),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.byKey(const ValueKey('sidebar.hosts')), findsOneWidget);
        expect(find.byKey(const ValueKey('sidebar.fold')), findsOneWidget);

        // Library entries occupy full width (stacked 1-column) and meet >= 28px touch target.
        final workspacesRect = tester.getRect(
          find.byKey(const ValueKey('library.workspaces')),
        );
        final knownRect = tester.getRect(
          find.byKey(const ValueKey('library.knownHosts')),
        );
        expect(workspacesRect.height, greaterThanOrEqualTo(28));
        expect(knownRect.height, greaterThanOrEqualTo(28));
        expect(workspacesRect.width, greaterThan(180));
        expect(knownRect.top, greaterThanOrEqualTo(workspacesRect.bottom));

        // Nuevo host button text stays on a single line.
        final newHostText = tester.widget<Text>(find.text('Nuevo host'));
        expect(newHostText.maxLines, 1);
      },
    );

    testWidgets('Empty sidebar footer has no empty Expanded spacer gap', (
      tester,
    ) async {
      final core = _UiPolishCore();
      final container = fakeContainer(core);
      final focus = FocusNode();
      addTearDown(focus.dispose);

      await tester.pumpWidget(
        _app(
          container: container,
          locale: const Locale('es'),
          child: SizedBox(
            width: 260,
            height: 800,
            child: Sidebar(searchFocus: focus),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar.fold')), findsOneWidget);
      final foldFinder = find.byKey(const ValueKey('sidebar.fold'));
      final footerRow = find
          .ancestor(of: foldFinder, matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: footerRow, matching: find.byType(Expanded)),
        findsNothing,
      );
    });

    testWidgets(
      'SidebarRail does not render clipped EnvTag pill in 52px rail while keeping tooltip and keys',
      (tester) async {
        final core = _UiPolishCore()
          ..hostList = [
            _host(
              id: 'h1',
              label: 'api',
              favorite: 0,
              environment: const EnvironmentView(
                name: 'Producción',
                short: 'prod',
                color: 'red',
              ),
            ),
          ];
        final container = fakeContainer(core);

        await tester.pumpWidget(
          _app(
            container: container,
            locale: const Locale('es'),
            child: SizedBox(
              width: 52,
              height: 600,
              child: SidebarRail(onSearch: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.byKey(const ValueKey('rail.library')), findsOneWidget);
        final favFinder = find.byKey(const ValueKey('rail.favorite.api'));
        expect(favFinder, findsOneWidget);

        final badge = tester.widget<SystemBadge>(
          find.descendant(of: favFinder, matching: find.byType(SystemBadge)),
        );
        expect(badge.tagged, isFalse);
        expect(
          find.descendant(of: favFinder, matching: find.byType(EnvTag)),
          findsNothing,
        );
        final tooltip = tester.widget<Tooltip>(
          find.descendant(of: favFinder, matching: find.byType(Tooltip)),
        );
        expect(tooltip.message, contains('prod'));
        expect(tester.getSize(favFinder).width, greaterThanOrEqualTo(28));
        expect(tester.getSize(favFinder).height, greaterThanOrEqualTo(28));
      },
    );
  });
}
