// The whole window against the real core:
//
//   fvm flutter test integration_test/ui_test.dart -d macos
//
// Screenshots (rendered by the app itself) go to $TMPDIR/openward-shots.
// The SSH part needs the S2 test servers (spikes/s2-ssh/servers/up.sh).

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        kDoubleTapMinTime,
        kPrimaryMouseButton,
        kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openward/app.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/controller.dart';
import 'package:openward/terminal/keys.dart';
import 'package:openward/terminal/renderer.dart';
import 'package:openward/settings/settings_page.dart';
import 'package:openward/ui/tokens.dart';

final _shots = Directory('${Directory.systemTemp.path}/openward-shots');
final _frame = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  _shots.createSync(recursive: true);
  File('${_shots.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

/// pumpAndSettle with a short limit: an animation that never ends (a
/// spinner, say) fails here at once instead of after ten minutes.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 20),
);

/// Pumps frames until `done`, like a user waiting.
Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The S2 fixtures directory if the test servers are up, else null.
Future<String?> _servers() async {
  final cache = Platform.isMacOS ? 'Library/Caches' : '.cache';
  final fixtures =
      Platform.environment['S2_FIXTURES'] ??
      '${Platform.environment['HOME']}/$cache/openward/s2-fixtures';
  final up = await Socket.connect(
    '127.0.0.1',
    22100,
    timeout: const Duration(milliseconds: 300),
  ).then((s) => (s..destroy()) == s).catchError((_) => false);
  return up && File('$fixtures/id_ed25519').existsSync() ? fixtures : null;
}

/// A segment of the light / dark / system choice (cards say «Claro» too).
Finder _segment(String text) => find.descendant(
  of: find.byType(SegmentedButton<ThemeChoice>),
  matching: find.text(text),
);

/// ⌘ and a key, or Ctrl (and Shift, for letters) off Apple platforms.
Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool letter = false,
}) async {
  final mods = isApple
      ? [LogicalKeyboardKey.metaLeft]
      : [
          LogicalKeyboardKey.controlLeft,
          if (letter) LogicalKeyboardKey.shiftLeft,
        ];
  for (final k in mods) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(key);
  for (final k in mods.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
}

Future<void> _doubleTap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(find.text(text));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  late Directory dir;
  late OpenWard app;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('openward-ui-');
    app = await OpenWard.open(dataDir: '${dir.path}/data');
  });
  tearDown(() => dir.delete(recursive: true));

  /// The window, in Spanish whatever the machine's language, past the
  /// first-run guide unless `welcomed` is false.
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    bool welcomed = true,
    String? sshConfig,
  }) async {
    tester.view.physicalSize = const Size(1280, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final settings = File('${dir.path}/data/settings.json');
    if (!settings.existsSync()) {
      settings.writeAsStringSync('{"language": "es", "welcomed": $welcomed}');
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        child: ProviderScope(
          overrides: [
            openWardProvider.overrideWithValue(app),
            settingsFileProvider.overrideWithValue(settings),
            sshConfigFileProvider.overrideWithValue(
              sshConfig ?? '${dir.path}/no-ssh-config',
            ),
          ],
          child: const OpenWardApp(),
        ),
      ),
    );
    await _settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(OpenWardApp)));
  }

  testWidgets('hosts in the sidebar, search, and a local terminal', (
    tester,
  ) async {
    final config = File('${dir.path}/config')
      ..writeAsStringSync('''
Host bastion
    HostName bastion.example.com
    User ops
Host web-1 web-2
    HostName %h.example.com
    ProxyJump bastion
''');
    await app.importSshConfig(file: config.path);
    await app.createHost(
      spec: const HostSpec(
        label: 'db',
        address: '10.0.0.5',
        tags: ['postgres'],
        settings: SettingsSpec(user: 'admin'),
      ),
    );
    final container = await launch(tester);

    // Group names are section labels, in capitals.
    expect(find.text('~/.SSH/CONFIG'), findsOneWidget);
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('admin@10.0.0.5'), findsOneWidget);
    expect(find.text('postgres'), findsOneWidget);
    await _shot(tester, '1-hosts');

    await tester.enterText(find.byType(TextField).first, 'web');
    await _settle(tester);
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('db'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await _settle(tester);

    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final tabs = container.read(tabsProvider);
    expect(tabs.tabs, hasLength(1));
    final c = tabs.currentSession!;
    await _until(tester, () => c.phase == Phase.running, 'the shell');
    c.session.text(text: 'echo ui-\$((6*7))\n');
    await _until(
      tester,
      () => c.session.screenText().contains('ui-42'),
      'the echo',
    );
    await _shot(tester, '2-local-terminal');

    // Select with the mouse and copy with ⌘C (to a stand-in clipboard: the
    // real one is the tester's).
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final grid = tester.getTopLeft(find.byType(TerminalGrid));
    final m = c.currentRenderer!.metrics;
    final lines = c.session.screenText().split('\n');
    final row = lines.indexWhere((l) => l == 'ui-42');
    expect(row, isNonNegative, reason: lines.join('\n'));
    Offset cell(int col) =>
        grid + Offset(col * m.width + 1, row * m.height + m.height / 2);
    final drag = await tester.startGesture(
      cell(0),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await drag.moveTo(cell(4) + Offset(m.width - 2, 0));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.session.selectionText(), 'ui-42');
    expect(c.currentRenderer!.selection, hasLength(1));
    await _shot(tester, '9-selection');
    // ⌘C, or Ctrl+Shift+C off Apple platforms.
    final copyMods = isApple
        ? [LogicalKeyboardKey.metaLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
    for (final k in copyMods) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    for (final k in copyMods.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pump();
    expect(copied, 'ui-42');

    // A double click takes the word.
    Future<void> click() async {
      final g = await tester.startGesture(
        cell(1),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await g.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await click();
    await click();
    expect(c.session.selectionText(), 'ui-42');

    // A program that follows the mouse gets the drags; Shift still selects.
    // cat swallows the mouse reports, which a shell would take as typing.
    c.session.text(
      text:
          r"printf '\033[?1000h'; cat > /dev/null"
          '\n',
    );
    await _until(tester, () => c.mouseTracking, 'mouse tracking');
    expect(c.session.selectionText(), isNull, reason: 'typing clears it');
    Future<void> dragAcross() async {
      final g = await tester.startGesture(
        cell(0),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await g.moveTo(cell(4) + Offset(m.width - 2, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await dragAcross();
    expect(c.session.selectionText(), isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await dragAcross();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(c.session.selectionText(), 'ui-42');
    // Ctrl+C ends cat; then tracking off.
    for (final kind in [KeyKind.down, KeyKind.up]) {
      c.session.key(
        hidUsage: 0x00070006,
        kind: kind,
        mods: Mods.ctrl,
        text: kind == KeyKind.down ? 'c' : '',
        unshifted: 0x63,
      );
    }
    // Until cat is gone the line may go to it instead of the shell: send
    // it again until the terminal reports tracking off.
    for (var i = 0; i < 20 && c.mouseTracking; i++) {
      c.session.text(
        text:
            r"printf '\033[?1000l'"
            '\n',
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(c.mouseTracking, isFalse);

    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
    expect(container.read(tabsProvider).tabs, isEmpty);
  });

  testWidgets('settings in a tab: light theme, a bigger font, the language', (
    tester,
  ) async {
    final container = await launch(tester);
    await tester.tap(find.byTooltip('Ajustes'));
    await _settle(tester);
    await tester.tap(find.text('Apariencia'));
    await _settle(tester);
    await tester.tap(_segment('Claro'));
    await _settle(tester);
    await _shot(tester, '10-settings');
    await tester.ensureVisible(find.text('13 px'));
    await tester.tap(find.text('13 px'));
    await _settle(tester);
    await tester.tap(find.text('16 px').last);
    await _settle(tester);
    // ⌘, on the open page brings it to the front instead of a second one.
    container.read(tabsProvider.notifier).openPage(PageKind.settings);
    expect(container.read(tabsProvider).tabs, hasLength(1));

    await tester.tap(find.text('General'));
    await _settle(tester);
    await tester.tap(find.text('Español'));
    await _settle(tester);
    await tester.tap(find.text('English').last);
    await _settle(tester);
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('English'));
    await _settle(tester);
    await tester.tap(find.text('Español').last);
    await _settle(tester);
    expect(container.read(settingsProvider).theme, ThemeChoice.light);
    final saved = File('${dir.path}/data/settings.json').readAsStringSync();
    expect(saved, contains('"theme": "light"'));
    expect(saved, contains('"font_size": 16.0'));
    expect(saved, contains('"language": "es"'));
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);

    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.running, 'the shell');
    c.session.text(text: 'printf "\\033[31mrojo\\033[0m normal\\n"\n');
    await _until(
      tester,
      () => c.session.screenText().contains('rojo normal'),
      'the output',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.currentRenderer!.metrics.fontSize, 16);
    expect(c.currentRenderer!.palette.dark, isFalse);
    await _shot(tester, '11-light-terminal');
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('a group and a host from the editors, with inheritance', (
    tester,
  ) async {
    await launch(tester);
    Finder field(String key) => find.byKey(ValueKey(key));

    await tester.tap(find.byTooltip('Más acciones'));
    await _settle(tester);
    await tester.tap(find.text('Nuevo grupo'));
    await _settle(tester);
    await tester.enterText(field('group.name'), 'prod');
    // Inherited until changed here: the user is the first setting.
    await tester.tap(find.text('Cambiar').first);
    await _settle(tester);
    await tester.enterText(field('settings.user'), 'deploy');
    await tester.tap(find.text('Guardar'));
    await _settle(tester);
    expect(find.text('PROD'), findsOneWidget);

    await tester.tap(find.text('Nuevo host'));
    await _settle(tester);
    await tester.enterText(field('host.label'), 'web');
    await tester.enterText(field('host.address'), 'web.example.com');
    await tester.tap(find.text('Cambiar').at(1));
    await _settle(tester);
    await tester.enterText(field('settings.port'), '2222');
    await tester.tap(field('host.group'));
    await _settle(tester);
    await tester.tap(find.text('prod').last);
    await _settle(tester);
    // The group's user shows in the host, with where it comes from.
    expect(find.text('Del grupo prod'), findsWidgets);
    await tester.tap(find.text('Guardar'));
    await _settle(tester);
    // The user comes from the group.
    expect(find.text('deploy@web.example.com:2222'), findsOneWidget);

    final detail = app.host(id: app.hosts().single.id);
    expect(detail.spec.settings.user, isNull);
    expect(detail.effective.user, 'deploy');

    // The editor says where inherited values come from.
    await tester.tap(find.text('web'), buttons: kSecondaryButton);
    await _settle(tester);
    await tester.tap(find.text('Editar…'));
    await _settle(tester);
    expect(find.text('deploy'), findsOneWidget);
    expect(find.text('Del grupo prod'), findsWidgets);
    expect(find.text('Cambiado aquí; heredaría 22'), findsOneWidget);
    await _shot(tester, '5-host-editor');
    await tester.tap(find.text('Cancelar'));
    await _settle(tester);
  });

  testWidgets('ssh: a changed host key is shown and trusted on purpose', (
    tester,
  ) async {
    final fixtures = await _servers();
    if (fixtures == null) return markTestSkipped('S2 servers not running');
    // Trusted before: a key the server does not have.
    await app.trustHostKey(
      host: '127.0.0.1',
      port: 22092,
      key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f',
    );
    await app.createHost(
      spec: HostSpec(
        label: 'ninetwo',
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: 'demo',
          port: 22092,
          identityFiles: ['$fixtures/id_ed25519'],
          agent: AgentKind.off,
          hostKeyPolicy: KeyPolicy.acceptNew,
        ),
      ),
    );
    final container = await launch(tester);
    await _doubleTap(tester, 'ninetwo');
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.closed, 'the refusal');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('La clave de ninetwo ha cambiado'), findsOneWidget);
    await tester.tap(find.text('Revisar la clave…').first);
    await tester.pump(const Duration(milliseconds: 400));
    // In the dialog, and in the card behind it.
    expect(
      find.text('SHA256:OcXwgqVGP3Hoo1XR2bnfs1DJan7drTyBcfSdQo6EdIE'),
      findsWidgets,
    );
    expect(find.text('guardada en OpenWard'), findsOneWidget);
    await _shot(tester, '6-host-key-changed');

    // Not without saying the fingerprint was checked.
    final trust = find.widgetWithText(
      FilledButton,
      'Confiar en la clave nueva',
    );
    expect(tester.widget<FilledButton>(trust).onPressed, isNull);
    await tester.tap(find.text('He comprobado la huella nueva'));
    await tester.pump();
    await tester.tap(trust);
    await _until(tester, () => c.phase == Phase.connected, 'the connection');
    expect(c.connected!.trust, TrustKind.known);
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('ssh: through a jump, the route in the details, and back after '
      'a drop', (tester) async {
    final fixtures = await _servers();
    if (fixtures == null) return markTestSkipped('S2 servers not running');
    final common = SettingsSpec(
      user: 'demo',
      identityFiles: ['$fixtures/id_ed25519'],
      agent: AgentKind.off,
      hostKeyPolicy: KeyPolicy.acceptNew,
    );
    final bastion = await app.createHost(
      spec: HostSpec(
        label: 'bastion',
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: common.user,
          port: 22100,
          identityFiles: common.identityFiles,
          agent: common.agent,
          hostKeyPolicy: common.hostKeyPolicy,
        ),
      ),
    );
    await app.createHost(
      spec: HostSpec(
        label: 'target1',
        address: 'target1',
        settings: SettingsSpec(
          user: common.user,
          identityFiles: common.identityFiles,
          agent: common.agent,
          hostKeyPolicy: common.hostKeyPolicy,
          route: RouteKind.jump,
          jumps: [JumpSpec(hostId: bastion)],
        ),
      ),
    );
    final container = await launch(tester);
    await _doubleTap(tester, 'target1');
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.connected, 'the connection');
    expect(c.route, ['bastion', 'target1']);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('Conectado'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('este equipo → bastion → target1'), findsOneWidget);
    await _shot(tester, '7-connection-info');
    await tester.tap(find.text('Cerrar'));
    await tester.pump(const Duration(milliseconds: 400));

    // Drop the connection on the bastion: it comes back by itself.
    c.session.text(
      text:
          r'echo ppid-$PPID-end'
          '\n',
    );
    await _until(
      tester,
      () => c.session.screenText().contains('-end\n'),
      'the pid',
    );
    final line = c.session
        .screenText()
        .split('\n')
        .firstWhere((l) => l.startsWith('ppid-'));
    final pid = line.substring(5, line.length - 4);
    final runtime = Platform.environment['S2_RUNTIME'] ?? 'podman';
    // The shell runs on target1; its sshd's connection is the one carried
    // through the bastion.
    final killed = await Process.run(runtime, [
      'exec',
      'target1',
      'kill',
      '-9',
      pid,
    ]);
    expect(killed.exitCode, 0, reason: '${killed.stderr}');
    await _until(
      tester,
      () => c.phase == Phase.reconnecting && c.reconnectAt != null,
      'the reconnection banner',
    );
    await tester.pump();
    expect(find.textContaining('Se perdió la conexión'), findsOneWidget);
    await _shot(tester, '8-reconnecting');
    await _until(tester, () => c.phase == Phase.connected, 'the reconnection');
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('ssh: the host key question in the tab, then the shell', (
    tester,
  ) async {
    final fixtures = await _servers();
    if (fixtures == null) return markTestSkipped('S2 servers not running');
    await app.createHost(
      spec: HostSpec(
        label: 'bastion',
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: 'demo',
          port: 22100,
          identityFiles: ['$fixtures/id_ed25519'],
          agent: AgentKind.off,
        ),
      ),
    );
    final container = await launch(tester);

    await _doubleTap(tester, 'bastion');
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.prompts.isNotEmpty, 'the host key question');
    // Not pumpAndSettle: a terminal pane repaints every frame.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('SHA256:'), findsOneWidget);
    await _shot(tester, '3-host-key');

    await tester.tap(find.text('Confiar y conectar'));
    await _until(tester, () => c.phase == Phase.connected, 'the connection');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('poscuántico'), findsOneWidget);
    c.session.text(text: 'echo ssh-ui-\$((6*7))\n');
    await _until(
      tester,
      () => c.session.screenText().contains('ssh-ui-42'),
      'the echo',
    );
    await _shot(tester, '4-ssh');
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('first run: pick hosts from ~/.ssh/config, a theme, and go', (
    tester,
  ) async {
    final config = File('${dir.path}/config')
      ..writeAsStringSync('''
Host bastion
    HostName bastion.example.com
    User ops
Host web-1
    HostName web-1.example.com
    ProxyJump bastion
Host db
    HostName 10.0.0.5
''');
    final container = await launch(
      tester,
      welcomed: false,
      sshConfig: config.path,
    );
    await _until(
      tester,
      () => find.text('Importar 3 hosts').evaluate().isNotEmpty,
      'the preview',
    );
    expect(find.text('Te damos la bienvenida a OpenWard'), findsOneWidget);
    await _shot(tester, '12-first-run');

    // Leaving out the bastion leaves out what jumps through it ...
    await tester.tap(find.text('bastion'));
    await _settle(tester);
    expect(find.text('Importar 1 host'), findsOneWidget);
    // ... and picking web-1 brings the bastion back.
    await tester.tap(find.text('web-1'));
    await _settle(tester);
    await tester.tap(find.text('db'));
    await _settle(tester);
    expect(find.text('Importar 2 hosts'), findsOneWidget);
    await tester.tap(find.text('Importar 2 hosts'));
    await _settle(tester);

    await tester.tap(find.text('Claro'));
    await _settle(tester);
    expect(container.read(settingsProvider).theme, ThemeChoice.light);
    await tester.tap(find.text('Siguiente'));
    await _settle(tester);
    await tester.tap(find.text('Empezar'));
    await _settle(tester);

    expect(container.read(settingsProvider).welcomed, isTrue);
    expect(app.hosts().map((h) => h.label).toSet(), {'bastion', 'web-1'});
    expect(find.text('Empieza aquí'), findsOneWidget);
    expect(find.text('web-1'), findsOneWidget);
    await _shot(tester, '13-start-light');
  });

  testWidgets('ssh: a quick connection to an address that is not saved', (
    tester,
  ) async {
    final fixtures = await _servers();
    if (fixtures == null) return markTestSkipped('S2 servers not running');
    final container = await launch(tester);
    await tester.enterText(
      find.byKey(const ValueKey('quick.address')),
      'web 1',
    );
    await tester.tap(find.text('Conectar'));
    await _settle(tester);
    expect(container.read(tabsProvider).tabs, isEmpty);
    expect(
      find.text('Escribe una dirección como usuario@servidor:puerto.'),
      findsOneWidget,
    );

    // The button took the focus: back to the field first.
    await tester.tap(find.byKey(const ValueKey('quick.address')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('quick.address')),
      'demo@127.0.0.1:22100',
    );
    await tester.tap(find.text('Conectar'));
    await tester.pump();
    final c = container.read(tabsProvider).currentSession!;
    expect(c.target?.port, 22100);
    expect(c.displayTitle, 'demo@127.0.0.1:22100');
    // A new key asks first (unless ~/.ssh/known_hosts already has it, and
    // then the user's own keys decide): either way the session runs.
    await _until(
      tester,
      () => c.prompts.isNotEmpty || c.phase != Phase.connecting,
      'the address to answer',
    );
    if (c.prompts.isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Primera conexión con 127.0.0.1'), findsOneWidget);
      await tester.tap(find.text('No confiar'));
      await _until(tester, () => c.phase == Phase.closed, 'the refusal');
    }
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('appearance: a theme from the gallery, a layer, accessibility', (
    tester,
  ) async {
    final container = await launch(tester);
    Settings settings() => container.read(settingsProvider);
    OwTheme shown() =>
        Theme.of(tester.element(find.byType(SettingsPage)))
            .extension<OwTheme>()!;
    await tester.tap(find.byTooltip('Ajustes'));
    await _settle(tester);
    await tester.tap(find.text('Apariencia'));
    await _settle(tester);

    await tester.tap(_segment('Oscuro'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('family.fosforo')));
    await _settle(tester);
    expect(settings().darkTheme, 'fosforo');
    expect(shown().id, 'fosforo');
    await _shot(tester, '14-fosforo');
    await tester.tap(find.byKey(const ValueKey('family.nativo')));
    await _settle(tester);
    expect(shown().id, 'nativo-oscuro');
    await _shot(tester, '14-nativo');

    // A light-only theme switches the fixed mode to light.
    await tester.tap(find.byKey(const ValueKey('family.papel')));
    await _settle(tester);
    expect(
      (settings().theme, settings().lightTheme),
      (ThemeChoice.light, 'papel'),
    );
    expect(shown().terminal.dark, isFalse);
    await tester.ensureVisible(find.text('Siempre oscuro'));
    await _settle(tester);
    await tester.tap(find.text('Siempre oscuro'));
    await _settle(tester);
    expect(settings().overrides['papel']!.terminal, TerminalColors.dark);
    expect(shown().terminal.dark, isTrue);
    await _shot(tester, '15-papel-dark-terminal');
    await tester.ensureVisible(find.text('Restablecer'));
    await _settle(tester);
    await tester.tap(find.text('Restablecer'));
    await _settle(tester);
    expect(settings().overrides, isEmpty);

    await tester.ensureVisible(find.text('Barra'));
    await tester.tap(find.text('Barra'));
    await _settle(tester);
    expect(settings().cursor, CursorChoice.bar);
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('terminal: find, links, bell and the tab\'s text size', (
    tester,
  ) async {
    final container = await launch(tester);
    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.running, 'the shell');
    // Printed so that the command line itself holds none of it.
    c.session.text(
      text:
          r"printf 'uno\nlinea FIND-%s\n\033]8;;https://openward.dev\033\\docs\033]8;;\033\\ http://x.%s/a\n\a' ME test"
          '\n',
    );
    await _until(
      tester,
      () => c.session.screenText().contains('http://x.test/a'),
      'the output',
    );
    await _until(tester, () => c.bells > 0, 'the bell');
    expect(c.bellUnseen, isFalse, reason: 'the tab is in front');

    await _shortcut(tester, LogicalKeyboardKey.keyF, letter: true);
    expect(c.findOpen, isTrue);
    await tester.enterText(find.byKey(const ValueKey('find.text')), 'find-me');
    await _until(
      tester,
      () => c.findTotal == 1 && c.findSelected == 1,
      'the match',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.currentRenderer!.search.where((h) => h.selected), hasLength(1));
    expect(find.text('1 de 1'), findsOneWidget);
    await _shot(tester, '16-find');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.findOpen, isFalse);

    final m = c.currentRenderer!.metrics;
    final row = c.session
        .screenText()
        .split('\n')
        .indexWhere((l) => l.startsWith('docs '));
    expect(row, isNonNegative);
    double y = (row + 0.5) * m.height;
    expect(
      c.session.linkAt(x: 1.5 * m.width, y: y)?.url,
      'https://openward.dev',
    );
    expect(c.session.linkAt(x: 8.5 * m.width, y: y)?.url, 'http://x.test/a');

    final size = c.currentRenderer!.metrics.fontSize;
    await _shortcut(tester, LogicalKeyboardKey.equal);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.zoom, 1);
    expect(c.currentRenderer!.metrics.fontSize, size + 1);
    await _shortcut(tester, LogicalKeyboardKey.digit0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.currentRenderer!.metrics.fontSize, size);

    // A selection dragged past the top edge scrolls back through history.
    c.session.text(text: 'for i in \$(seq 1 80); do echo line\$i; done\n');
    await _until(
      tester,
      () => c.session.screenText().contains('line80'),
      'the lines',
    );
    await tester.pump(const Duration(milliseconds: 100));
    final grid = tester.getTopLeft(find.byType(TerminalGrid));
    final drag = await tester.startGesture(
      grid + Offset(m.width * 2, m.height * 3),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await drag.moveTo(grid + Offset(m.width * 2, -m.height * 2));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.currentRenderer!.displayOffset, greaterThan(0));
    expect(c.session.selectionText(), isNotNull);
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('panes: split, move, broadcast, paste with it, and close', (
    tester,
  ) async {
    final container = await launch(tester);
    // No newline: with bracketed paste the shell would not run it anyway.
    String? clipboard = 'echo pasted-\$((20+1))';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': clipboard} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Future<void> keys(
      List<LogicalKeyboardKey> mods,
      LogicalKeyboardKey key,
    ) async {
      for (final k in mods) {
        await tester.sendKeyDownEvent(k);
      }
      await tester.sendKeyEvent(key);
      for (final k in mods.reversed) {
        await tester.sendKeyUpEvent(k);
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    final cmd = isApple
        ? [LogicalKeyboardKey.metaLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
    final cmdShift = isApple
        ? [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
    final move = isApple
        ? [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];

    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final tab = container.read(tabsProvider).current! as SessionTab;
    final a = tab.panes.active.controller!;
    await _until(tester, () => a.phase == Phase.running, 'the first shell');

    // Split right: the new pane asks; Enter opens the same as before.
    await keys(cmd, LogicalKeyboardKey.keyD);
    expect(tab.panes.isSplit, isTrue);
    expect(find.text('¿Qué abres en este panel?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    final b = tab.panes.active.controller!;
    expect(b, isNot(same(a)));
    await _until(tester, () => b.phase == Phase.running, 'the second shell');

    // The keyboard moves left, to the first pane.
    await keys(move, LogicalKeyboardKey.arrowLeft);
    expect(tab.panes.active.controller, same(a));

    // Broadcast: one Enter typed in the first pane runs both lines.
    await keys(cmdShift, LogicalKeyboardKey.keyB);
    expect(tab.panes.broadcast, isTrue);
    expect(find.textContaining('va a 2 de 2 paneles'), findsOneWidget);
    a.session.text(text: 'echo from-\$((1+1))a');
    b.session.text(text: 'echo from-\$((1+1))b');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    List<String> lines(TerminalController c) =>
        c.session.screenText().split('\n');
    await _until(
      tester,
      () => lines(a).contains('from-2a') && lines(b).contains('from-2b'),
      'both lines to run',
    );
    await _shot(tester, '17-broadcast');

    // Left out, the second pane gets nothing.
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(tab.panes.receives(tab.panes.leaves.last), isFalse);
    a.session.text(text: 'echo again-\$((1+1))a');
    b.session.text(text: 'echo again-\$((1+1))b');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _until(tester, () => lines(a).contains('again-2a'), 'the first');
    await tester.pump(const Duration(milliseconds: 300));
    expect(lines(b).contains('again-2b'), isFalse);
    // Clean the second pane's line for what comes next.
    for (final kind in [KeyKind.down, KeyKind.up]) {
      b.session.key(
        hidUsage: 0x00070006,
        kind: kind,
        mods: Mods.ctrl,
        text: kind == KeyKind.down ? 'c' : '',
        unshifted: 0x63,
      );
    }
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();

    // A paste always asks, and goes to both.
    await keys(cmd, LogicalKeyboardKey.keyV);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('¿Pegar en 2 paneles a la vez?'), findsOneWidget);
    await _shot(tester, '18-broadcast-paste');
    await tester.tap(find.text('Pegar en 2 paneles'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _until(
      tester,
      () => lines(a).contains('pasted-21') && lines(b).contains('pasted-21'),
      'the paste in both',
    );
    clipboard = null;

    await tester.tap(find.byKey(const ValueKey('broadcast.exit')));
    await tester.pump();
    expect(tab.panes.broadcast, isFalse);

    // ⌘W closes the active pane; the other fills the tab.
    await keys(cmd, LogicalKeyboardKey.keyW);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tab.panes.isSplit, isFalse);
    expect(container.read(tabsProvider).tabs, hasLength(1));
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });
}
