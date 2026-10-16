// Every screen and editor against Flutter's accessibility guidelines:
// whatever can be pressed has a name, and is at least 24×24 (WCAG 2.2,
// target size minimum).
//
//   fvm flutter test integration_test/a11y_test.dart -d macos

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openward/app.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/identities.dart';
import 'package:openward/src/rust/api/snippets.dart';
import 'package:openward/src/rust/api/tunnels.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/controller.dart';
import 'package:openward/terminal/keys.dart';

final _frame = GlobalKey();

/// Where screenshots go: `--dart-define=OPENWARD_SHOTS=…` (the CI), or the
/// temporary folder. A define, because the test app does not see the
/// environment of `flutter test`.
String get _shotsPath {
  const defined = String.fromEnvironment('OPENWARD_SHOTS');
  return defined.isNotEmpty
      ? defined
      : '${Directory.systemTemp.path}/openward-shots';
}

/// A screenshot, next to those of the window tests.
Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final dir = Directory(_shotsPath)..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

const _targetSize = MinimumTapTargetGuideline(
  size: Size(24, 24),
  link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  testWidgets('every screen and editor: named, and big enough to press', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('openward-a11y-');
    addTearDown(() => dir.delete(recursive: true));
    final ssh = Directory('${dir.path}/ssh')..createSync();
    const key =
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f';
    File('${ssh.path}/known_hosts').writeAsStringSync('10.0.4.21 $key\n');
    final app = await OpenWard.openWithSshDir(
      dataDir: '${dir.path}/data',
      sshDir: ssh.path,
    );
    final group = await app.createGroup(spec: const GroupSpec(name: 'prod'));
    final web = await app.createHost(
      spec: HostSpec(label: 'web', address: 'web.example.com', groupId: group),
    );
    await app.createHost(
      spec: const HostSpec(label: 'db', address: '10.0.4.21'),
    );
    await app.createTunnel(
      spec: TunnelSpec(
        label: 'Postgres',
        hostId: web,
        kind: TunnelKind.local,
        listenPort: 15432,
        destHost: 'localhost',
        destPort: 5432,
        autostart: false,
      ),
    );
    await app.createIdentity(
      spec: const IdentitySpec(label: 'deploy', user: 'deploy'),
    );
    await app.createSnippet(
      spec: const SnippetSpec(label: 'Logs', script: 'journalctl -n {{n}}'),
    );
    await app.trustHostKey(host: 'web.example.com', port: 22, key: key);
    final settings = File('${dir.path}/data/settings.json')
      ..writeAsStringSync('{"language": "es", "welcomed": true}');

    tester.view.physicalSize = const Size(1280, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final semantics = tester.ensureSemantics();
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

    final problems = <String>[];
    Future<void> audit(String where) async {
      await tester.pump(const Duration(milliseconds: 400));
      for (final g in [labeledTapTargetGuideline, _targetSize]) {
        final e = await g.evaluate(tester);
        if (!e.passed) problems.add('== $where\n${e.reason}');
      }
    }

    Future<void> tapText(String text, {bool secondary = false}) async {
      await tester.tap(
        find.text(text).first,
        buttons: secondary ? kSecondaryButton : kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> close() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Who updated sees the news once.
    expect(find.text('Qué hay de nuevo'), findsOneWidget);
    await audit("what's new");
    await _shot(tester, '37-whats-new');
    await tester.tap(find.byKey(const ValueKey('news.start')));
    await tester.pump(const Duration(milliseconds: 400));
    await audit('start');
    await tapText('web', secondary: true);
    await tapText('Editar…');
    await audit('host editor');
    await close();
    // The group's name, upper-cased or not by the theme.
    await tester.tap(
      find.textContaining(RegExp(r'^prod$', caseSensitive: false)).first,
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tapText('Editar grupo…');
    await audit('group editor');
    await close();

    tabs.openPage(PageKind.settings);
    await audit('settings: general');
    await tester.tap(find.byKey(const ValueKey('about.report')));
    await tester.pump(const Duration(milliseconds: 400));
    await audit('report a problem');
    await _shot(tester, '38-report');
    await close();
    await tapText('Apariencia');
    await audit('settings: appearance');
    await tapText('Terminal');
    await audit('settings: terminal');

    tabs.openPage(PageKind.tunnels);
    await audit('tunnels');
    await tapText('Postgres');
    await audit('tunnel editor');
    await close();

    tabs.openPage(PageKind.identities);
    await audit('identities');
    await tapText('deploy');
    await audit('identity editor');
    await close();
    await tapText('Usar en…');
    await audit('use an identity');
    await close();

    tabs.openPage(PageKind.snippets);
    await audit('snippets');
    await tapText('Logs');
    await audit('snippet editor');
    await close();

    tabs.openPage(PageKind.knownHosts);
    await audit('known hosts');
    await tester.tap(find.byTooltip('Olvidar').first);
    await tester.pump(const Duration(milliseconds: 400));
    await audit('forget a key');
    await close();

    tabs.openLocal();
    final term = container.read(tabsProvider).currentSession!;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (term.phase != Phase.running && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await audit('terminal');
    for (final k in [
      isApple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(
      isApple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    );
    await audit('snippet palette');
    await close();

    final report = problems.join('\n');
    // Also in a file, to read the whole list when it fails.
    File('${Directory.systemTemp.path}/openward-a11y.txt')
        .writeAsStringSync(report);
    tabs.closeCurrent();
    await tester.pump(const Duration(milliseconds: 300));
    semantics.dispose();
    expect(problems, isEmpty, reason: report);
  });
}
