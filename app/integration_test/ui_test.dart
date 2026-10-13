// The whole window against the real core:
//
//   fvm flutter test integration_test/ui_test.dart -d macos
//
// Screenshots (rendered by the app itself) go to $TMPDIR/openward-shots.
// The SSH part needs the S2 test servers (spikes/s2-ssh/servers/up.sh).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kDoubleTapMinTime, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openward/app.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/controller.dart';

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
          overrides: [openWardProvider.overrideWithValue(app)],
          child: const OpenWardApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('db'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

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

    container.read(tabsProvider.notifier).close(0);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs, isEmpty);
  });

  testWidgets('a group and a host from the editors, with inheritance', (
    tester,
  ) async {
    await launch(tester);
    Finder field(String label) => find.widgetWithText(TextField, label);

    await tester.tap(find.text('Grupo'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Nombre'), 'prod');
    await tester.enterText(field('Usuario'), 'deploy');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('prod'), findsOneWidget);

    await tester.tap(find.text('Host'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Nombre'), 'web');
    await tester.enterText(field('Dirección'), 'web.example.com');
    await tester.enterText(field('Puerto'), '2222');
    await tester.tap(find.text('Sin grupo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('prod').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    // The user comes from the group.
    expect(find.text('deploy@web.example.com:2222'), findsOneWidget);

    final detail = app.host(id: app.hosts().single.id);
    expect(detail.spec.settings.user, isNull);
    expect(detail.effective.user, 'deploy');

    // The editor says where inherited values come from.
    await tester.tap(find.text('web'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar…'));
    await tester.pumpAndSettle();
    expect(find.text('Heredado: deploy (grupo prod)'), findsOneWidget);
    await _shot(tester, '5-host-editor');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('ssh: the host key question in the tab, then the shell', (
    tester,
  ) async {
    final fixtures =
        Platform.environment['S2_FIXTURES'] ??
        '${Platform.environment['HOME']}/Library/Caches/openward/s2-fixtures';
    final up = await Socket.connect(
      '127.0.0.1',
      22100,
      timeout: const Duration(milliseconds: 300),
    ).then((s) => (s..destroy()) == s).catchError((_) => false);
    if (!up || !File('$fixtures/id_ed25519').existsSync()) {
      markTestSkipped('S2 servers not running');
      return;
    }
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

    await tester.tap(find.text('bastion'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('bastion'));
    await tester.pump();
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
    await tester.pumpAndSettle();
  });
}
