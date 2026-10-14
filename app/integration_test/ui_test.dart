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

  Future<ProviderContainer> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        child: ProviderScope(
          overrides: [
            openWardProvider.overrideWithValue(app),
            settingsFileProvider.overrideWithValue(
              File('${dir.path}/data/settings.json'),
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

    expect(find.text('~/.ssh/config'), findsOneWidget);
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

    await tester.tap(find.textContaining('Terminal local'));
    await tester.pump();
    final tabs = container.read(tabsProvider);
    expect(tabs.tabs, hasLength(1));
    final c = tabs.current!;
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
    c.session.text(
      text:
          r"printf '\033[?1000l'"
          '\n',
    );
    await _until(tester, () => !c.mouseTracking, 'mouse tracking off');

    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
    expect(container.read(tabsProvider).tabs, isEmpty);
  });

  testWidgets('settings: light theme and a bigger font, kept on disk', (
    tester,
  ) async {
    final container = await launch(tester);
    await tester.tap(find.byTooltip('Ajustes'));
    await _settle(tester);
    await tester.tap(find.text('Claro'));
    await _settle(tester);
    await tester.tap(find.text('13 px'));
    await _settle(tester);
    await tester.tap(find.text('16 px').last);
    await _settle(tester);
    await _shot(tester, '10-settings');
    await tester.tap(find.text('Cerrar'));
    await _settle(tester);
    expect(container.read(settingsProvider).theme, ThemeChoice.light);
    final saved = File('${dir.path}/data/settings.json').readAsStringSync();
    expect(saved, contains('"theme": "light"'));
    expect(saved, contains('"font_size": 16.0'));

    await tester.tap(find.textContaining('Terminal local'));
    await tester.pump();
    final c = container.read(tabsProvider).current!;
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
    Finder field(String label) => find.widgetWithText(TextField, label);

    await tester.tap(find.text('Grupo'));
    await _settle(tester);
    await tester.enterText(field('Nombre'), 'prod');
    await tester.enterText(field('Usuario'), 'deploy');
    await tester.tap(find.text('Guardar'));
    await _settle(tester);
    expect(find.text('prod'), findsOneWidget);

    await tester.tap(find.text('Host'));
    await _settle(tester);
    await tester.enterText(field('Nombre'), 'web');
    await tester.enterText(field('Dirección'), 'web.example.com');
    await tester.enterText(field('Puerto'), '2222');
    await tester.tap(find.text('Sin grupo'));
    await _settle(tester);
    await tester.tap(find.text('prod').last);
    await _settle(tester);
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
    expect(find.text('Heredado: deploy (grupo prod)'), findsOneWidget);
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
    final c = container.read(tabsProvider).current!;
    await _until(tester, () => c.phase == Phase.closed, 'the refusal');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('La clave de ninetwo ha cambiado'), findsOneWidget);
    await tester.tap(find.text('Revisar la clave…').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('SHA256:OcXwgqVGP3Hoo1XR2bnfs1DJan7drTyBcfSdQo6EdIE'),
      findsOneWidget,
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
    final c = container.read(tabsProvider).current!;
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
    expect(find.textContaining('Conexión perdida'), findsOneWidget);
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
    final c = container.read(tabsProvider).current!;
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
}
