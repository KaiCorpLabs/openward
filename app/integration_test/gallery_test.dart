// The review gallery: the main screens with each theme, light and dark,
// to look at without installing on every system. They go to
// $TMPDIR/openward-shots/gallery, and are also reported to
// test_driver/integration_test.dart when run with `flutter drive` (the
// CI, which keeps them as an artifact).
//
//   fvm flutter test integration_test/gallery_test.dart -d macos

@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openward/app.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/hosts/sidebar.dart';
import 'package:openward/import/program_preview.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/tunnels.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/controller.dart';
import 'package:openward/welcome/whats_new.dart';
import 'package:openward/window/sidebar_state.dart';

final _frame = GlobalKey();

/// The repository, found up from the test app's executable.
String get _repo {
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/core/crates/openward-import').existsSync()) {
    if (dir.parent.path == dir.path) fail('repository not found');
    dir = dir.parent;
  }
  return dir.path;
}

/// Where screenshots go: `--dart-define=OPENWARD_SHOTS=…` (the CI), or the
/// temporary folder. A define, because the test app does not see the
/// environment of `flutter test`.
String get _shotsPath {
  const defined = String.fromEnvironment('OPENWARD_SHOTS');
  return defined.isNotEmpty
      ? defined
      : '${Directory.systemTemp.path}/openward-shots';
}

/// Every theme in the gallery: (family, light?).
const _themes = [
  ('grafito', false),
  ('papel', true),
  ('fosforo', false),
  ('nativo', true),
  ('nativo', false),
  ('contraste', true),
  ('contraste', false),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  testWidgets('the main screens with every theme, light and dark', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('openward-gallery-');
    addTearDown(() => dir.delete(recursive: true));
    final ssh = Directory('${dir.path}/ssh')..createSync();
    final app = await OpenWard.openWithSshDir(
      dataDir: '${dir.path}/data',
      sshDir: ssh.path,
    );
    // Marked as production: its hosts' tabs and terminals say so.
    final prod = await app.createGroup(
      spec: const GroupSpec(
        name: 'prod',
        settings: SettingsSpec(
          environment: EnvironmentKind.mark,
          environmentName: 'Producción',
          environmentShort: 'prod',
          environmentColor: 'red',
        ),
      ),
    );
    final web = await app.createHost(
      spec: HostSpec(
        label: 'web-1',
        address: 'web-1.example.com',
        groupId: prod,
        tags: const ['nginx'],
        settings: const SettingsSpec(user: 'deploy'),
      ),
    );
    await app.createHost(
      spec: HostSpec(
        label: 'db-primary',
        address: '10.0.4.21',
        groupId: prod,
        settings: const SettingsSpec(user: 'admin'),
        favorite: true,
        systemCode: 'deb',
      ),
    );
    await app.createHost(
      spec: const HostSpec(
        label: 'bastion',
        address: 'bastion.example.com',
        systemCode: 'alp',
      ),
    );
    await app.createTunnel(
      spec: TunnelSpec(
        label: 'Postgres',
        hostId: web,
        kind: TunnelKind.local,
        listenPort: 15432,
        destHost: '10.0.4.21',
        destPort: 5432,
        autostart: true,
      ),
    );
    // What importing the made-up Termius data would bring.
    final termius = await app.readProgramWithKey(
      path: '$_repo/core/crates/openward-import/tests/fixtures/termius/Termius',
      termiusKey: List.filled(32, 0x42),
    );
    final importPreview = app.previewProgram(data: termius.data!);
    final settings = File('${dir.path}/data/settings.json')
      ..writeAsStringSync(
        '{"language": "es", "welcomed": true, "seen_news": "$newsVersion"}',
      );

    tester.view.physicalSize = const Size(1280, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        child: ProviderScope(
          overrides: [
            openWardProvider.overrideWithValue(app),
            settingsFileProvider.overrideWithValue(settings),
            sshConfigFileProvider.overrideWithValue('${dir.path}/no-config'),
          ],
          child: const OpenWardApp(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OpenWardApp)),
    );
    final tabs = container.read(tabsProvider.notifier);
    final out = Directory('$_shotsPath/gallery')..createSync(recursive: true);
    final reported = <String, String>{};

    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 400));
      final boundary =
          _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = png!.buffer.asUint8List();
      File('${out.path}/$name.png').writeAsBytesSync(bytes);
      reported['gallery/$name'] = base64Encode(bytes);
    }

    // A terminal to show, with something in it.
    tabs.openLocal();
    final term = container.read(tabsProvider).currentSession!;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (term.phase != Phase.running && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    term.session.text(text: 'printf "\\033[32mok\\033[0m %s\\n" galería\n');

    for (final (family, light) in _themes) {
      final name = '$family-${light ? 'claro' : 'oscuro'}';
      container
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(
              theme: light ? ThemeChoice.light : ThemeChoice.dark,
              lightTheme: light ? family : null,
              darkTheme: light ? null : family,
            ),
          );
      await tester.pump(const Duration(milliseconds: 300));

      tabs.select(0);
      await shot('$name-1-terminal');

      // The editor of a new host in prod: what it inherits, and where from.
      await tester.tap(
        find.descendant(of: find.byType(Sidebar), matching: find.text('web-1')),
      );
      await tester.tap(find.text('Nuevo host'));
      await tester.pump(const Duration(milliseconds: 500));
      await shot('$name-2-host-editor');
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(milliseconds: 400));

      tabs.openPage(PageKind.tunnels);
      await shot('$name-3-tunnels');

      tabs.openPage(PageKind.settings);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Apariencia').first);
      await shot('$name-4-appearance');

      unawaited(
        showProgramPreview(tester.element(find.byType(Sidebar)), importPreview),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await shot('$name-5-import');
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(milliseconds: 400));
      // Back to the terminal alone.
      while (container.read(tabsProvider).tabs.length > 1) {
        tabs.select(1);
        tabs.closeCurrent();
      }
      await tester.pump(const Duration(milliseconds: 200));

      // The sidebar folded to a rail, with the terminal's tab in it.
      final sidebar = container.read(sidebarProvider.notifier);
      sidebar.chose(SidebarMode.rail);
      await tester.pump(const Duration(milliseconds: 300));
      await shot('$name-6-rail');
      sidebar.chose(SidebarMode.open);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(
      out.listSync().where((f) => f.path.endsWith('.png')).length,
      greaterThanOrEqualTo(_themes.length * 6),
    );
    binding.reportData = {'screenshots': reported};
    tabs.closeCurrent();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
