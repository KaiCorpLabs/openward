// Every screen and editor against Flutter's accessibility guidelines:
// whatever can be pressed has a name, and is at least 24×24 (WCAG 2.2,
// target size minimum); and no text on screen is under 12 px.
//
//   fvm flutter test integration_test/a11y_test.dart -d macos

@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
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
import 'package:openward/home/recent.dart';
import 'package:openward/hosts/sidebar.dart';
import 'package:openward/import/program_preview.dart';
import 'package:openward/import/termius_consent.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/identities.dart';
import 'package:openward/src/rust/api/keychain.dart';
import 'package:openward/src/rust/api/snippets.dart';
import 'package:openward/src/rust/api/tunnels.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/api/workspaces.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/controller.dart';
import 'package:openward/terminal/keys.dart';
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

/// No text on screen under 12 px (before the user's own text size).
class _TextSize extends AccessibilityGuideline {
  const _TextSize();

  static const minimum = 12.0;

  @override
  String get description => 'Text is at least $minimum px';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    final small = <String>{};
    void visit(InlineSpan span, double size) {
      final here = span.style?.fontSize ?? size;
      if (span is TextSpan) {
        // Without the invisible characters some widgets lay out with, nor
        // icons, which are glyphs of a font in Unicode's private use area.
        final text = (span.text ?? '')
            .replaceAll(RegExp('[\u200b-\u200f\u2060\ufeff\ue000-\uf8ff]'), '')
            .trim();
        if (text.isNotEmpty && here < minimum) {
          small.add(
            '${here.toStringAsFixed(1)} px: «${text.length > 40 ? '${text.substring(0, 40)}…' : text}»',
          );
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, here);
        }
      }
    }

    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      visit(w.text, 14);
    }
    return small.isEmpty
        ? const Evaluation.pass()
        : Evaluation.fail(small.join('\n'));
  }
}

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
    await app.generateKey(
      name: 'id_ed25519',
      kind: SshKeyType.ed25519,
      comment: 'ana@portatil',
    );
    await app.createWorkspace(
      spec: WorkspaceSpec(
        name: 'Producción',
        tabs: [
          WorkspaceTabSpec(
            panes: [
              const WorkspacePane(
                split: WorkspaceSplit(vertical: false, ratio: 0.5),
                active: false,
              ),
              WorkspacePane(target: WorkspaceTarget(hostId: web), active: true),
              const WorkspacePane(target: WorkspaceTarget(), active: false),
            ],
          ),
        ],
        active: 0,
      ),
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
      for (final g in [
        labeledTapTargetGuideline,
        _targetSize,
        const _TextSize(),
      ]) {
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
    await tester.tap(find.byKey(const ValueKey('settings.advanced')));
    await audit('host editor: advanced');
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

    // With connections behind: the recent ones, what the quick connection
    // suggests, and every shortcut.
    final recent = container.read(recentProvider.notifier);
    recent.add(
      'host:$web',
      'web',
      now: DateTime.now().subtract(const Duration(hours: 1)),
    );
    recent.end('host:$web', tmux: true);
    recent.add('address:ops@10.0.0.9', 'ops@10.0.0.9');
    await audit('start: recent connections');
    await _shot(tester, '39-start-recent');
    final quick = find.byKey(const ValueKey('quick.address'));
    await tester.enterText(quick, 'w');
    await audit('start: suggestions');
    await tester.enterText(quick, '');
    await tester.tap(find.byKey(const ValueKey('start.shortcuts')));
    await audit('shortcuts');
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

    // Importing from another program: where from, Termius's warning, and
    // what would come (the made-up Termius data).
    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pump(const Duration(milliseconds: 400));
    await tapText('Importar…');
    await audit('import: where from');
    await close();
    final sidebar = tester.element(find.byType(Sidebar));
    unawaited(confirmTermius(sidebar));
    await audit("import: Termius's warning");
    await close();
    final termius = await app.readProgramWithKey(
      path: '$_repo/core/crates/openward-import/tests/fixtures/termius/Termius',
      termiusKey: List.filled(32, 0x42),
    );
    unawaited(
      showProgramPreview(sidebar, app.previewProgram(data: termius.data!)),
    );
    await audit('import: what comes');
    await close();

    tabs.openPage(PageKind.knownHosts);
    await audit('known hosts');
    await tester.tap(find.byTooltip('Olvidar').first);
    await tester.pump(const Duration(milliseconds: 400));
    await audit('forget a key');
    await close();

    tabs.openPage(PageKind.keys);
    await audit('keys');
    await tester.tap(find.byKey(const ValueKey('keys.new')));
    await tester.pump(const Duration(milliseconds: 400));
    await audit('new key');
    await close();
    await tester.tap(find.byKey(const ValueKey('keys.import')));
    await tester.pump(const Duration(milliseconds: 400));
    await audit('import a key');
    await close();

    tabs.openPage(PageKind.workspaces);
    await audit('workspaces');

    tabs.openLocal();
    final term = container.read(tabsProvider).currentSession!;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (term.phase != Phase.running && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await audit('terminal');
    // The sidebar as a rail, and shown over the window.
    final sidebarState = container.read(sidebarProvider.notifier);
    sidebarState.chose(SidebarMode.rail);
    await audit('rail');
    sidebarState.setPeek(true);
    await audit('sidebar over the window');
    sidebarState.setPeek(false);
    sidebarState.chose(SidebarMode.open);
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
    for (final k in [
      isApple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(
      isApple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    );
    await audit('command palette');
    await close();
    tabs.openPage(PageKind.workspaces);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('workspaces.save')));
    await tester.pump(const Duration(milliseconds: 400));
    await audit('save a workspace');
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
