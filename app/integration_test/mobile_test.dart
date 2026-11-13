// The phone's layout and the phone's own parts, against the real core:
//
//   fvm flutter test integration_test/mobile_test.dart -d <simulator or emulator>
//   fvm flutter test integration_test/mobile_test.dart -d macos   # the layout only
//
// The SSH case needs the S2 test servers (spikes/s2-ssh/servers/up.sh) and
// their key where the app can read it: the iOS simulator reads the Mac's
// files, so `--dart-define=S2_FIXTURES=$HOME/Library/Caches/openward/s2-fixtures`
// is enough; the Android emulator reaches the Mac at 10.0.2.2
// (`--dart-define=S2_HOST=10.0.2.2`) but not its files, so that case skips
// there unless the key is pushed (docs/plan/movil.md).

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openward/app.dart';
import 'package:openward/core/platform.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/security.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tab_strip.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/key_bar.dart';
import 'package:openward/terminal/keys.dart';
import 'package:openward/welcome/whats_new.dart';

/// pumpAndSettle with a short limit, as in ui_test.dart.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 20),
);

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what, {
  Duration within = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(within);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A host on the Hosts page: a row, or a card on a wide screen.
Finder _hostRow(String label) => find.byWidgetPredicate(
  (w) =>
      w.key == ValueKey('hosts.row.$label') ||
      w.key == ValueKey('hosts.card.$label'),
);

const _fixturesDefine = String.fromEnvironment('S2_FIXTURES');
const _host = String.fromEnvironment('S2_HOST', defaultValue: '127.0.0.1');

/// The S2 fixtures if the servers answer and the key is readable here.
Future<String?> _servers() async {
  final fixtures = _fixturesDefine.isNotEmpty
      ? _fixturesDefine
      : '${Platform.environment['HOME']}/Library/Caches/openward/s2-fixtures';
  final up = await Socket.connect(
    _host,
    22100,
    timeout: const Duration(milliseconds: 500),
  ).then((s) => (s..destroy()) == s).catchError((_) => false);
  if (up && File('$fixtures/id_ed25519').existsSync()) return fixtures;
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  late Directory dir;
  late OpenWard app;

  setUp(() async {
    // Tried on the desktop too: its layout and limits as a phone's.
    Device.debugMobile = true;
    dir = await Directory.systemTemp.createTemp('openward-mobile-');
    app = await OpenWard.open(
      dataDir: '${dir.path}/data',
      requireOnboarding: false,
    );
  });
  tearDown(() async {
    Device.debugMobile = null;
    await dir.delete(recursive: true);
  });

  /// The app at a phone's size (an iPhone 17 Pro's points).
  Future<ProviderContainer> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final settings = File('${dir.path}/data/settings.json');
    if (!settings.existsSync()) {
      settings.writeAsStringSync(
        '{"language": "es", "welcomed": true, "seen_news": "$newsVersion"}',
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openWardProvider.overrideWithValue(app),
          settingsFileProvider.overrideWithValue(settings),
          sshConfigFileProvider.overrideWithValue('${dir.path}/no-ssh-config'),
        ],
        child: const OpenWardApp(),
      ),
    );
    await _settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(OpenWardApp)));
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('the phone: a drawer, a tap connects, tabs in a list, a key '
      'bar', (tester) async {
    await app.createHost(
      spec: const HostSpec(
        label: 'nowhere',
        // Nothing listens there: the tab opens and says so.
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: 'demo',
          port: 9,
          agent: AgentKind.off,
          connectTimeoutSecs: 2,
        ),
      ),
    );
    final container = await launch(tester);

    // A top bar instead of the tab strip; nothing of this device's own.
    expect(key('mobile.topBar'), findsOneWidget);
    expect(find.byType(TabStrip), findsNothing);
    expect(key('start.local'), findsNothing);
    expect(key('start.serial'), findsNothing);

    // The library is in the drawer; what it opens goes in front, and the
    // drawer goes. A tap on a host connects (a double click on the desktop).
    await tester.tap(key('mobile.menu'));
    await _settle(tester);
    expect(key('mobile.drawer'), findsOneWidget);
    await tester.tap(key('sidebar.hosts'));
    await _settle(tester);
    expect(key('mobile.drawer'), findsNothing);
    await tester.tap(_hostRow('nowhere'));
    await _settle(tester);
    final tabs = container.read(tabsProvider);
    expect(tabs.current, isA<SessionTab>());
    // Under a session, the keys a phone's keyboard lacks.
    expect(key('keyBar'), findsOneWidget);

    // The title lists the tabs; the start page is one of them.
    await tester.tap(key('mobile.title'));
    await _settle(tester);
    expect(key('mobile.switcher'), findsOneWidget);
    // The Hosts page and the session.
    expect(key('mobile.switcher.0'), findsOneWidget);
    expect(key('mobile.switcher.1'), findsOneWidget);
    await tester.tap(find.text('Inicio'));
    await _settle(tester);
    expect(container.read(tabsProvider).current, isNull);
    expect(key('keyBar'), findsNothing);
    expect(container.read(tabsProvider).tabs, hasLength(2));

    // A long press is the right click: the host's menu, on the Hosts page.
    container.read(tabsProvider.notifier).select(0);
    await _settle(tester);
    final g = await tester.startGesture(
      tester.getCenter(_hostRow('nowhere')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.up();
    await _settle(tester);
    expect(find.byType(PopupMenuItem<VoidCallback>), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);

    container.read(tabsProvider.notifier)
      ..close(1)
      ..close(0);
    await _settle(tester);
  });

  testWidgets('ssh from the phone, typed with the key bar', (tester) async {
    final fixtures = await _servers();
    if (fixtures == null) {
      markTestSkipped('S2 servers or their key not reachable from here');
      return;
    }
    await app.createHost(
      spec: HostSpec(
        label: 'tenzero',
        address: _host,
        settings: SettingsSpec(
          user: 'demo',
          port: 22100,
          identityFiles: ['$fixtures/id_ed25519'],
          agent: AgentKind.off,
          hostKeyPolicy: KeyPolicy.acceptNew,
        ),
      ),
    );
    final container = await launch(tester);
    await tester.tap(key('mobile.menu'));
    await _settle(tester);
    await tester.tap(key('sidebar.hosts'));
    await _settle(tester);
    await tester.tap(_hostRow('tenzero'));
    await _settle(tester);
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.keyBar != null, 'the pane');
    await _until(
      tester,
      () => c.session.screenText().contains(r'$'),
      'the prompt',
    );

    // Text and Enter from the bar, as the phone's keyboard sends them.
    c.keyBar!.barText(r'echo mobile-$((6*7))');
    c.keyBar!.barKey(Hid.enter, 0);
    await _until(
      tester,
      () => c.session.screenText().contains('mobile-42'),
      'the echo',
    );

    // Ctrl held on the bar, then «c» from the keyboard: an interrupt.
    c.keyBar!.barText('sleep 30');
    c.keyBar!.barKey(Hid.enter, 0);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(of: key('keyBar'), matching: find.text('Ctrl')),
    );
    await tester.pump();
    expect(stickyMods.held(Mods.ctrl), isTrue);
    c.keyBar!.barText('c');
    expect(stickyMods.held(Mods.ctrl), isFalse);
    c.keyBar!.barText(r'echo after-$((6*7))');
    c.keyBar!.barKey(Hid.enter, 0);
    await _until(
      tester,
      () => c.session.screenText().contains('after-42'),
      'the prompt after Ctrl+C',
      within: const Duration(seconds: 8),
    );

    container.read(tabsProvider.notifier)
      ..close(1)
      ..close(0);
    await _settle(tester);
  });

  testWidgets('the vault protected by this device («Later»), locked and '
      'opened again', (tester) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      markTestSkipped("the phone's keychain: iOS or Android only");
      return;
    }
    final fresh = await Directory.systemTemp.createTemp('openward-vault-');
    addTearDown(() => fresh.delete(recursive: true));
    final vault = await OpenWard.open(
      dataDir: '${fresh.path}/data',
      requireOnboarding: true,
    );
    expect(vault.vaultOnboardingRequired(), isTrue);
    // Keychain on iOS; the Keystore, through VaultKeystore.kt, on Android.
    await vault.deferVaultSetup(linuxAck: false);
    expect(vault.securityState().phase, VaultPhase.unlocked);
    await vault.lockVault();
    expect(vault.securityState().phase, isNot(VaultPhase.unlocked));
    await vault.unlockDeviceVault();
    expect(vault.securityState().phase, VaultPhase.unlocked);
    expect(vault.nativeProtection(), NativeProtection.biometric);
  });
}
