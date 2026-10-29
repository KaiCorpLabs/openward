// The whole window against the real core:
//
//   fvm flutter test integration_test/ui_test.dart -d macos
//
// Screenshots (rendered by the app itself) go to $TMPDIR/openward-shots, or
// where --dart-define=OPENWARD_SHOTS says.
// The SSH part needs the S2 test servers (spikes/s2-ssh/servers/up.sh).

@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
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
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openward/app.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/history/history.dart';
import 'package:openward/identities/identities.dart';
import 'package:openward/keys/keys.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/identities.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/src/rust/api/sftp.dart'
    show ConflictChoice, TransferDirection;
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';
import 'package:openward/hosts/hosts_page.dart';
import 'package:openward/hosts/sidebar.dart';
import 'package:openward/logs/log_viewer.dart';
import 'package:openward/logs/logs.dart';
import 'package:openward/src/rust/api/logs.dart';
import 'package:openward/tabs/close_guard.dart' show confirmQuit;
import 'package:openward/tabs/session_view.dart';
import 'package:openward/tabs/tab_strip.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/terminal/terminal_pane.dart';
import 'package:openward/terminal/controller.dart';
import 'package:openward/terminal/keys.dart';
import 'package:openward/terminal/renderer.dart';
import 'package:openward/settings/settings_page.dart';
import 'package:openward/snippets/snippets.dart';
import 'package:openward/sftp/sftp_controller.dart';
import 'package:openward/sftp/transfers.dart';
import 'package:openward/src/rust/api/tunnels.dart';
import 'package:openward/tunnels/tunnels.dart';
import 'package:openward/ui/environment.dart';
import 'package:openward/ui/tokens.dart';
import 'package:openward/welcome/whats_new.dart';
import 'package:openward/window/sidebar_state.dart';
import 'package:openward/workspaces/workspaces.dart';

/// Where screenshots go: `--dart-define=OPENWARD_SHOTS=…` (the CI), or the
/// temporary folder. A define, because the test app does not see the
/// environment of `flutter test`.
String get _shotsPath {
  const defined = String.fromEnvironment('OPENWARD_SHOTS');
  return defined.isNotEmpty
      ? defined
      : '${Directory.systemTemp.path}/openward-shots';
}

final _shots = Directory(_shotsPath);
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
  String what, {
  Duration within = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(within);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The repository, found up from the test app's executable (the app does
/// not see the environment or the working directory of `flutter test`).
String get _repo {
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/core/crates/openward-import').existsSync()) {
    if (dir.parent.path == dir.path) fail('repository not found');
    dir = dir.parent;
  }
  return dir.path;
}

/// Copies the made-up Termius data (core/crates/openward-import/tests/
/// fixtures/termius) to where Termius keeps it under `home`.
void _termiusIn(String home) {
  final from = Directory(
    '$_repo/core/crates/openward-import/tests/fixtures/termius/Termius/IndexedDB/file__0.indexeddb.leveldb',
  );
  final data = Platform.isMacOS
      ? '$home/Library/Application Support/Termius'
      : Platform.isWindows
      ? '$home/AppData/Roaming/Termius'
      : '$home/.config/Termius';
  final to = Directory('$data/IndexedDB/file__0.indexeddb.leveldb')
    ..createSync(recursive: true);
  for (final f in from.listSync().whereType<File>()) {
    f.copySync('${to.path}/${f.uri.pathSegments.last}');
  }
}

/// The key the Termius fixture is encrypted with.
final _termiusKey = List.filled(32, 0x42);

/// A mouse drag from one point to another, in steps, as a hand moves.
Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  // A pointer of its own: a real mouse on the test machine uses low ones.
  final g = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
    pointer: 900,
  );
  for (var i = 1; i <= 12; i++) {
    await g.moveTo(Offset.lerp(from, to, i / 12)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Scrolls to `finder`, into the middle of its scrollable: clear of what
/// floats over its edges (an editor's buttons).
/// A field with the focus would scroll back to its caret: it lets go.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.4);
  await tester.pump(const Duration(milliseconds: 100));
}

/// A tab of the tab bar, by its title.
Finder _tab(String title) => find.descendant(
  of: find.byType(TabStrip),
  matching: find.textContaining(title),
);

/// `make ci` passes it: there a skipped SSH case would pass untested.
const _requireServers = bool.fromEnvironment('OPENWARD_REQUIRE_SERVERS');

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
  if (up && File('$fixtures/id_ed25519').existsSync()) return fixtures;
  if (_requireServers) {
    fail('S2 servers not running (spikes/s2-ssh/servers/up.sh)');
  }
  return null;
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

/// ⌘⇧T (Ctrl+Shift+Alt+T elsewhere): the last closed tab, again.
Future<void> _reopen(WidgetTester tester) async {
  final mods = isApple
      ? [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft]
      : [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.altLeft,
        ];
  for (final k in mods) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
  for (final k in mods.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
}

/// Connects to a saved host as a person would: a double click on its row
/// of the Hosts page, opened from the sidebar when it shows. The page is
/// closed after (⌘W), so the tabs are the ones the test opened.
Future<void> _connect(WidgetTester tester, String label) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(OpenWardApp)),
  );
  final row = find.byKey(ValueKey('hosts.row.$label'));
  if (row.evaluate().isEmpty) {
    final entry = find.byKey(const ValueKey('sidebar.hosts'));
    if (entry.evaluate().isNotEmpty) {
      await tester.tap(entry);
    } else {
      container.read(tabsProvider.notifier).openPage(PageKind.hosts);
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(row);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(row);
  await tester.pump();
  final page = container
      .read(tabsProvider)
      .tabs
      .indexWhere((t) => t is PageTab && t.page == PageKind.hosts);
  if (page >= 0) container.read(tabsProvider.notifier).close(page);
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
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1280, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The same theme on every machine (Grafito): following a light system,
    // Papel would draw section titles in a serif instead of capitals.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final settings = File('${dir.path}/data/settings.json');
    if (!settings.existsSync()) {
      // Past this release's news too, unless the first run is under test.
      settings.writeAsStringSync(
        '{"language": "es", "welcomed": $welcomed, "seen_news": "$newsVersion"}',
      );
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
            ...overrides,
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
    Finder field(String key) => find.byKey(ValueKey(key));

    // The sidebar keeps what is used every day; every host is on its page,
    // a click below.
    expect(field('sidebar.hosts'), findsOneWidget);
    expect(find.text('4 · 1 grupo'), findsOneWidget);
    expect(field('sidebar.host.web-1'), findsNothing);
    await _shot(tester, '1-sidebar');
    await tester.tap(field('sidebar.hosts'));
    await _settle(tester);
    expect(find.byType(HostsPage), findsOneWidget);
    // Group names are as written: never in capitals, they are the user's.
    expect(find.text('~/.ssh/config'), findsOneWidget);
    expect(field('hosts.row.web-1'), findsOneWidget);
    expect(find.text('admin@10.0.0.5'), findsOneWidget);
    expect(field('hosts.filter.tag.postgres'), findsOneWidget);
    await _shot(tester, '1-hosts');

    // A tag keeps its hosts; «Todos» brings back the rest. A search too.
    await tester.tap(field('hosts.filter.tag.postgres'));
    await _settle(tester);
    expect(field('hosts.row.db'), findsOneWidget);
    expect(field('hosts.row.web-1'), findsNothing);
    await tester.tap(field('hosts.filter.all'));
    await _settle(tester);
    expect(field('hosts.row.web-1'), findsOneWidget);
    await tester.enterText(field('hosts.search'), 'web');
    await _settle(tester);
    expect(field('hosts.row.web-1'), findsOneWidget);
    expect(field('hosts.row.web-2'), findsOneWidget);
    expect(field('hosts.row.db'), findsNothing);
    // As cards, the same.
    await tester.tap(field('hosts.view.cards'));
    await _settle(tester);
    expect(field('hosts.card.web-1'), findsOneWidget);
    expect(field('hosts.row.web-1'), findsNothing);
    await _shot(tester, '1b-hosts-cards');
    await tester.tap(field('hosts.view.list'));
    await _settle(tester);

    // The sidebar's search finds them as well.
    await tester.enterText(field('sidebar.search'), 'web');
    await _settle(tester);
    expect(field('sidebar.host.web-1'), findsOneWidget);
    expect(field('sidebar.host.db'), findsNothing);
    await tester.enterText(field('sidebar.search'), '');
    await _settle(tester);
    container.read(tabsProvider.notifier).close(0);
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
    // The page keeps where Apariencia was scrolled to.
    await tester.ensureVisible(find.text('Español'));
    await _settle(tester);
    await tester.tap(find.text('Español'));
    await _settle(tester);
    await tester.tap(find.text('English').last);
    await _settle(tester);
    expect(find.text('Appearance'), findsOneWidget);
    // The menu fades out: its «English» goes a moment after the choice.
    await _until(
      tester,
      () => find.text('English').evaluate().length == 1,
      'the menu closed',
    );
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

  testWidgets('window shortcuts with nothing focused: at start, after a page '
      'and after a terminal', (tester) async {
    final container = await launch(tester);
    // At start no field has the focus, and ⌘, still opens the settings…
    await _shortcut(tester, LogicalKeyboardKey.comma);
    await _settle(tester);
    expect(container.read(tabsProvider).current, isA<PageTab>());
    // …and ⌘W closes them, though the page took its focus with it; ⌘⇧T
    // opens them again.
    await _shortcut(tester, LogicalKeyboardKey.keyW, letter: true);
    await _settle(tester);
    expect(container.read(tabsProvider).tabs, isEmpty);
    await _reopen(tester);
    await _settle(tester);
    expect(
      container.read(tabsProvider).current,
      isA<PageTab>().having((t) => t.page, 'page', PageKind.settings),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyW, letter: true);
    await _settle(tester);
    expect(container.read(tabsProvider).tabs, isEmpty);
    // ⌘T opens a terminal, which takes the focus; closing its tab with the
    // mouse leaves nothing focused, and ⌘K still opens the palette.
    await _shortcut(tester, LogicalKeyboardKey.keyT, letter: true);
    await tester.pump();
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.running, 'the shell');
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyK, letter: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('palette.query')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
  });

  testWidgets('focus: the sidebar folds, peeks and widens; ⌘K for everything', (
    tester,
  ) async {
    await app.createHost(
      spec: const HostSpec(
        label: 'web-1',
        address: 'web-1.example.com',
        settings: SettingsSpec(user: 'deploy'),
      ),
    );
    final container = await launch(tester);
    final tabs = container.read(tabsProvider.notifier);
    Finder field(String key) => find.byKey(ValueKey(key));
    Finder keyed(String prefix) => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(prefix),
    );
    Future<void> wait() => tester.pump(const Duration(milliseconds: 300));
    tabs.openLocal();
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.running, 'the shell');

    // In the open sidebar: the open tab, in its section.
    expect(field('sidebar.open.Local'), findsOneWidget);

    // Folded to a rail: the open tabs, in a counter that lists them.
    await tester.tap(field('sidebar.fold'));
    await wait();
    expect(find.byType(Sidebar), findsNothing);
    expect(field('rail.search'), findsOneWidget);
    expect(field('rail.hosts'), findsOneWidget);
    expect(container.read(settingsProvider).sidebar, SidebarMode.rail);
    await _shot(tester, '85-rail');
    await tester.tap(field('rail.open'));
    await wait();
    expect(keyed('rail.open.'), findsOneWidget);
    await _shot(tester, '85b-rail-open');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait();
    // The library, in a menu.
    await tester.tap(field('rail.library'));
    await wait();
    expect(field('rail.library.keys'), findsOneWidget);
    await tester.tap(field('rail.library.keys'));
    await wait();
    expect(container.read(tabsProvider).current, isA<PageTab>());
    tabs.closeCurrent();
    await wait();

    // Hosts, on their page.
    await tester.tap(field('rail.hosts'));
    await wait();
    expect(find.byType(HostsPage), findsOneWidget);
    expect(field('hosts.row.web-1'), findsOneWidget);

    // The sidebar over the window; kept open with the pin.
    container.read(sidebarProvider.notifier).setPeek(true);
    await wait();
    expect(field('sidebar.peek'), findsOneWidget);
    await _shot(tester, '86-peek');
    await tester.tap(field('sidebar.pin'));
    await wait();
    expect(field('sidebar.peek'), findsNothing);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(container.read(settingsProvider).sidebar, SidebarMode.open);

    // A search still on when it folds is there when it comes back.
    final search = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byType(TextField),
    );
    await tester.enterText(search.first, 'web');
    await wait();

    // Hidden: the tab bar has a button for it, and ⌘B brings it back.
    container.read(sidebarProvider.notifier).chose(SidebarMode.hidden);
    await wait();
    expect(find.byType(Sidebar), findsNothing);
    expect(field('tabs.showSidebar'), findsOneWidget);
    await _shot(tester, '87-hidden');
    if (isApple) {
      await _shortcut(tester, LogicalKeyboardKey.keyB);
    } else {
      await tester.tap(field('tabs.showSidebar'));
    }
    await wait();
    expect(find.byType(Sidebar), findsOneWidget);
    expect(tester.widget<TextField>(search.first).controller!.text, 'web');
    expect(container.read(searchProvider), 'web');
    await tester.enterText(search.first, '');
    await wait();

    // Folding by itself with a terminal in front; open on a page.
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(sidebarOnSession: SidebarOnSession.rail));
    tabs.openPage(PageKind.settings);
    await wait();
    expect(find.byType(Sidebar), findsOneWidget);
    await tester.ensureVisible(field('settings.terminalPadding'));
    await wait();
    await _shot(tester, '88-settings-window');
    tabs.select(0);
    await wait();
    expect(find.byType(Sidebar), findsNothing);
    expect(field('rail.search'), findsOneWidget);

    // A wider sidebar, from its edge (here, its notifier), is kept.
    tabs.openPage(PageKind.settings);
    await wait();
    container.read(sidebarProvider.notifier)
      ..drag(340)
      ..endDrag();
    await wait();
    expect(container.read(settingsProvider).sidebarWidth, 340);
    expect(tester.getSize(find.byType(Sidebar)).width, 340);

    // ⌘K: the open tabs first, with nothing typed.
    await _shortcut(tester, LogicalKeyboardKey.keyK, letter: true);
    await wait();
    expect(field('palette.query'), findsOneWidget);
    expect(keyed('palette.tab.'), findsNWidgets(3));
    await _shot(tester, '89-palette-tabs');
    // `>`: only the actions (here on a page: no terminal actions).
    await tester.enterText(field('palette.query'), '>ajus');
    await wait();
    expect(field('palette.action.Ajustes'), findsOneWidget);
    expect(keyed('palette.tab.'), findsNothing);
    // A tab by its name.
    await tester.enterText(field('palette.query'), 'ajus');
    await wait();
    expect(field('palette.tab.Ajustes'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await wait();
    expect(container.read(tabsProvider).current, isA<PageTab>());

    while (container.read(tabsProvider).tabs.isNotEmpty) {
      tabs.close(0);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _settle(tester);
  });

  testWidgets('panes: an open tab into a new pane, its menu, names, equal '
      'sizes and out to a tab again', (tester) async {
    final container = await launch(tester);
    final tabs = container.read(tabsProvider.notifier);
    Finder key(String k) => find.byKey(ValueKey(k));
    Future<TerminalController> local(String name) async {
      tabs.openLocal();
      await tester.pump();
      final c = container.read(tabsProvider).currentSession!;
      await _until(tester, () => c.phase == Phase.running, 'the shell');
      c.customTitle = name;
      return c;
    }

    final uno = await local('uno');
    final dos = await local('dos');
    tabs.select(0);
    await tester.pump(const Duration(milliseconds: 300));

    // A new pane offers the tabs already open: dos moves into it.
    tabs.split(Axis.horizontal);
    await tester.pump(const Duration(milliseconds: 300));
    expect(key('pane.choice.dos'), findsOneWidget);
    await _shot(tester, '63-pane-picker');
    await tester.tap(key('pane.choice.dos'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(tabsProvider).tabs, hasLength(1));
    final tab = container.read(tabsProvider).current! as SessionTab;
    expect(tab.panes.leaves.map((p) => p.controller), [uno, dos]);
    // The tab says which panes it has.
    expect(_tab('uno · dos'), findsOneWidget);

    // The pane's menu: swap with the neighbour.
    await tester.tap(find.byTooltip('Opciones del panel').first);
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '64-pane-menu');
    await tester.tap(find.text('Intercambiar con dos'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tab.panes.leaves.map((p) => p.controller), [dos, uno]);

    // Equal sizes: from the menu, with ⌘⌥=, and a double click on the
    // border between them.
    final root = tab.panes.root as PaneSplit;
    tab.panes.resize(root, 0.7);
    await tester.pump();
    await tester.tap(find.byTooltip('Opciones del panel').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Igualar tamaños'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(root.ratio, 0.5);
    if (isApple) {
      tab.panes.resize(root, 0.3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(root.ratio, 0.5);
    }
    tab.panes.resize(root, 0.3);
    await tester.pump();
    final divider = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('pane.divider.'),
    );
    await tester.tap(divider);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 300));
    expect(root.ratio, 0.5);

    // Two panes alike are numbered.
    uno.customTitle = 'web';
    dos.customTitle = 'web';
    tab.panes.focus(tab.panes.leaves.last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: find.byType(TabView), matching: find.text('web 1')),
      findsOneWidget,
    );
    expect(_tab('web 1 · web 2'), findsOneWidget);
    uno.customTitle = 'uno';
    dos.customTitle = 'dos';
    tab.panes.focus(tab.panes.leaves.first);
    await tester.pump(const Duration(milliseconds: 300));

    // Something else here: the session goes on in a tab of its own, and
    // the pane asks again.
    await tester.tap(find.byTooltip('Opciones del panel').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Abrir otra cosa aquí…'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(tabsProvider).tabs, hasLength(2));
    expect(tab.panes.leaves.last.controller, isNull);
    expect(find.text('¿Qué abres en este panel?'), findsOneWidget);
    // It takes uno back, from the tab it went to.
    await tester.tap(key('pane.choice.uno'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(tabsProvider).tabs, hasLength(1));
    expect(tab.panes.leaves.map((p) => p.controller), [dos, uno]);

    // A pane's header dragged to the empty bar: it says so, and makes a
    // tab of its own.
    final header = tester.getCenter(
      find.descendant(of: find.byType(TabView), matching: find.text('uno')),
    );
    final bar =
        tester.getTopRight(find.byType(TabStrip)) + const Offset(-200, 20);
    final g = await tester.startGesture(
      header,
      kind: PointerDeviceKind.mouse,
      pointer: 900,
    );
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(header, bar, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await _shot(tester, '65-pane-to-tab');
    expect(find.text('Soltar aquí: uno en una pestaña nueva'), findsOneWidget);
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(tabsProvider).tabs, hasLength(2));
    expect(tab.panes.isSplit, isFalse);

    // «Dividir con …» from the palette.
    tabs.select(0);
    await tester.pump(const Duration(milliseconds: 300));
    await _shortcut(tester, LogicalKeyboardKey.keyK, letter: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(key('palette.query'), 'dividir con uno');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(key('palette.action.Dividir con uno'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(tabsProvider).tabs, hasLength(1));
    final again = container.read(tabsProvider).current! as SessionTab;
    expect(again.panes.leaves.map((p) => p.controller), [dos, uno]);
  });

  testWidgets('a single terminal dragged onto a half of itself splits '
      'around it', (tester) async {
    final container = await launch(tester);
    final tabs = container.read(tabsProvider.notifier);
    tabs.openLocal();
    await tester.pump();
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.running, 'the shell');
    tabs.rename(0, 'uno');
    await tester.pump(const Duration(milliseconds: 300));
    final tab = container.read(tabsProvider).current! as SessionTab;

    // By its tab, onto its own right half: it goes there, and the left is a
    // new pane that asks what to open.
    final from = tester.getCenter(_tab('uno'));
    final to =
        tester.getRect(find.byType(TerminalPane)).centerRight -
        const Offset(40, 0);
    final g = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      pointer: 900,
    );
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await _shot(tester, '66-split-around');
    expect(
      find.textContaining('a la derecha; a la izquierda, un panel nuevo'),
      findsOneWidget,
    );
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tab.panes.leaves.map((p) => p.controller), [null, c]);
    expect(tab.panes.active, same(tab.panes.leaves.first));
    expect(find.text('¿Qué abres en este panel?'), findsOneWidget);
    tabs.closePane(tab, tab.panes.leaves.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tab.panes.isSplit, isFalse);

    // By its header (in a split pane too), onto its own bottom half.
    tabs.split(Axis.horizontal);
    await tester.pump(const Duration(milliseconds: 300));
    tabs.fillSame(tab, tab.panes.leaves.last);
    await tester.pump(const Duration(milliseconds: 300));
    final header = tester.getCenter(
      find.descendant(of: find.byType(TabView), matching: find.text('uno')),
    );
    final first = tester.getRect(find.byType(TerminalPane).first);
    await _drag(tester, header, first.bottomCenter - const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tab.panes.leaves, hasLength(3));
    expect(tab.panes.leaves[1].controller, same(c));
    expect(tab.panes.leaves.first.controller, isNull);
    final root = tab.panes.root as PaneSplit;
    expect((root.first as PaneSplit).axis, Axis.vertical);
  });

  /// What R2 of the audit promises: a terminal with nothing new asks for no
  /// frames, output brings them back, and a thousand hosts do not make the
  /// window slow to build. The times are of a debug build, and only bound
  /// loosely; they are printed for the record.
  testWidgets(
    'an idle terminal asks for no frames; a thousand hosts stay quick',
    (tester) async {
      final config = File('${dir.path}/thousand.config')
        ..writeAsStringSync(
          [
            for (var i = 0; i < 1000; i++)
              'Host web-$i\n  HostName 10.0.${i ~/ 250}.${i % 250}\n  User deploy\n',
          ].join(),
        );
      final report = await app.importSshConfig(file: config.path);
      expect(report.created, 1000);
      final container = await launch(tester);
      final tabs = container.read(tabsProvider.notifier);
      tabs.openLocal();
      final c = container.read(tabsProvider).currentSession!;
      await _until(tester, () => c.phase == Phase.running, 'the shell');
      TerminalPaneState pane() =>
          tester.state<TerminalPaneState>(find.byType(TerminalPane));
      await _until(tester, () => !pane().polling, 'the terminal to go idle');
      // Nothing comes: it stays idle.
      await tester.pump(const Duration(seconds: 1));
      expect(pane().polling, isFalse);
      // Output brings frames back, and they stop once it is drawn.
      c.session.text(text: 'sleep 0.3; echo idle-\$((6*7))\n');
      await _until(tester, () => pane().polling, 'frames for the output');
      await _until(
        tester,
        () => c.session.screenText().contains('idle-42'),
        'the output',
      );
      await _until(
        tester,
        () => !pane().polling,
        'the terminal to go idle again',
      );

      // A thousand hosts: a new tab rebuilds the window around them.
      final watch = Stopwatch()..start();
      tabs.openLocal();
      await tester.pump();
      watch.stop();
      debugPrint('a new tab with 1000 hosts: ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 500)));
      // A search that finds them all builds only the rows on view.
      container.read(searchProvider.notifier).set('web');
      final search = Stopwatch()..start();
      await tester.pump();
      search.stop();
      debugPrint(
        'a search finding 1000 hosts: ${search.elapsedMilliseconds} ms',
      );
      expect(search.elapsed, lessThan(const Duration(milliseconds: 500)));
      container.read(searchProvider.notifier).set('');
      while (container.read(tabsProvider).tabs.isNotEmpty) {
        tabs.close(0);
      }
      await _settle(tester);
    },
  );

  testWidgets('import from Termius: read it, pick, save a key, and again', (
    tester,
  ) async {
    // A home of its own: the tester's own Termius and ~/.ssh stay out.
    final home = Directory('${dir.path}/home')..createSync();
    _termiusIn(home.path);
    // The one setUp opened lets go of the vault first: one at a time.
    app.dispose();
    app = await OpenWard.openWithHome(
      dataDir: '${dir.path}/data',
      home: home.path,
    );
    final container = await launch(
      tester,
      overrides: [termiusKeyProvider.overrideWithValue(_termiusKey)],
    );
    Future<void> openImport() async {
      await tester.tap(find.byTooltip('Más acciones'));
      await _settle(tester);
      await tester.tap(find.text('Importar…').last);
      await _settle(tester);
    }

    await openImport();
    expect(find.text('Importar hosts'), findsOneWidget);
    expect(find.text('Termius'), findsOneWidget);
    await _shot(tester, '50-import-origin');
    await tester.tap(find.text('Leer Termius'));
    await _settle(tester);
    await _shot(tester, '51-import-termius');
    await tester.tap(find.text('Continuar'));
    await _until(
      tester,
      () => find.text('Importar de Termius').evaluate().isNotEmpty,
      'the preview',
    );
    await _settle(tester);
    // Its groups and hosts; the telnet one cannot come.
    for (final t in ['Producción', 'Web', 'bastion', 'web-1', 'old-switch']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Telnet: aún no se puede usar'), findsOneWidget);
    // Neither stored key is in this home's ~/.ssh: save the ci one.
    await tester.tap(find.textContaining('~/.ssh/termius-ci,'));
    await tester.pump();
    await _shot(tester, '52-import-preview');
    await tester.tap(find.text('Importar 4 hosts'));
    await _settle(tester);
    expect(find.text('4 hosts importados de Termius'), findsOneWidget);
    expect(find.text('Clave guardada en ~/.ssh/termius-ci'), findsOneWidget);
    expect(find.textContaining('lab-mosh usaba Mosh'), findsOneWidget);
    await _shot(tester, '53-import-report');
    await tester.tap(find.text('Aceptar'));
    await _settle(tester);

    final hosts = app.hosts().map((h) => h.label).toSet();
    expect(hosts, {'bastion', 'web-1', 'lab-mosh', 'packed'});
    expect(File('${dir.path}/home/.ssh/termius-ci').existsSync(), isTrue);
    expect(container.read(snippetsProvider).map((s) => s.spec.label), [
      'Reiniciar nginx',
    ]);

    // Again: everything is there already, so there is nothing to import.
    await openImport();
    await tester.tap(find.text('Leer Termius'));
    await _settle(tester);
    await tester.tap(find.text('Continuar'));
    await _until(
      tester,
      () => find.text('Importar de Termius').evaluate().isNotEmpty,
      'the preview again',
    );
    await _settle(tester);
    expect(find.text('ya importado'), findsWidgets);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Importar'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Cancelar'));
    await _settle(tester);
    expect(app.hosts(), hasLength(4));
  });

  testWidgets(
    'tabs and panes: drag to reorder and split, menus, close on exit',
    (tester) async {
      final far = await app.createHost(
        spec: const HostSpec(label: 'lejos', address: '192.0.2.1'),
      );
      // A favorite, to be in the sidebar.
      await app.setFavorite(id: far, favorite: true);
      final container = await launch(tester);
      final tabs = container.read(tabsProvider.notifier);
      List<String> titles() => [
        for (final t in container.read(tabsProvider).tabs)
          switch (t) {
            SessionTab() => t.controller?.displayTitle ?? '',
            PageTab(:final page) => page.name,
            _ => '',
          },
      ];
      Future<TerminalController> local(String name) async {
        tabs.openLocal();
        await tester.pump();
        final c = container.read(tabsProvider).currentSession!;
        await _until(tester, () => c.phase == Phase.running, 'the shell');
        c.customTitle = name;
        return c;
      }

      final uno = await local('uno');
      final dos = await local('dos');
      tabs.openPage(PageKind.tunnels);
      await tester.pump(const Duration(milliseconds: 400));
      expect(titles(), ['uno', 'dos', 'tunnels']);

      // Dragging a tab along the bar reorders it.
      await _drag(
        tester,
        tester.getCenter(_tab('Túneles')),
        tester.getTopLeft(_tab('uno')) + const Offset(2, 8),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(titles(), ['tunnels', 'uno', 'dos']);

      // Onto a terminal's right half, a tab joins it: two panes, one tab.
      tabs.select(1);
      await tester.pump(const Duration(milliseconds: 400));
      final term = tester.getRect(find.byType(TerminalPane).first);
      await _drag(
        tester,
        tester.getCenter(_tab('dos')),
        term.centerRight - const Offset(40, 0),
      );
      await tester.pump(const Duration(milliseconds: 400));
      // The pane dropped has the keyboard, so the tab is named after it.
      expect(titles(), ['tunnels', 'dos']);
      final split = container.read(tabsProvider).current! as SessionTab;
      expect(split.panes.leaves.map((p) => p.controller), [uno, dos]);
      await _shot(tester, '60-dropped-tab');
      split.panes.focus(split.panes.leaves.first);
      await tester.pump();

      // A favorite from the sidebar, onto the bottom half of the first pane.
      final first = tester.getRect(find.byType(TerminalPane).first);
      await _drag(
        tester,
        tester.getCenter(
          find.descendant(
            of: find.byType(Sidebar),
            matching: find.text('lejos'),
          ),
        ),
        first.bottomCenter - const Offset(0, 30),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(split.panes.leaves, hasLength(3));
      expect(split.panes.active.controller?.label, 'lejos');
      split.panes.focus(split.panes.leaves.first);
      await tester.pump();

      // A pane by its header, onto the tab bar: a tab of its own.
      await _drag(
        tester,
        tester.getCenter(
          find.descendant(of: find.byType(TabView), matching: find.text('dos')),
        ),
        tester.getTopRight(_tab('uno')) + const Offset(30, 8),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(titles(), ['tunnels', 'uno', 'dos']);
      expect(split.panes.leaves, hasLength(2));

      // The tab's menu splits it and separates its panes again.
      tabs.select(1);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_tab('uno'), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Duplicar'), findsOneWidget);
      await _shot(tester, '61-tab-menu');
      await tester.tap(find.text('Separar los paneles en pestañas'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(titles(), hasLength(4));

      // The terminal's menu splits the pane it was opened on.
      tabs.select(titles().indexOf('dos'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byType(TerminalPane).first,
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Dividir abajo'), findsOneWidget);
      await _shot(tester, '62-terminal-menu');
      await tester.tap(find.text('Dividir abajo'));
      await tester.pump(const Duration(milliseconds: 400));
      final dosTab = container.read(tabsProvider).current! as SessionTab;
      expect(dosTab.panes.leaves, hasLength(2));
      // The new pane asks what to open; it goes again.
      final fresh = dosTab.panes.leaves.last;
      if (fresh.controller == null) tabs.closePane(dosTab, fresh);
      await tester.pump(const Duration(milliseconds: 400));

      // exit closes the pane (and the tab, with the last one); an error stays.
      final failing = await local('falla');
      failing.session.text(text: 'exit 3\n');
      await _until(tester, () => failing.phase == Phase.closed, 'exit 3');
      await tester.pump(const Duration(milliseconds: 300));
      expect(titles(), contains('falla'));
      final n = titles().length;
      dos.session.text(text: 'exit\n');
      await _until(tester, () => titles().length == n - 1, 'dos to close');
      expect(titles(), isNot(contains('dos')));

      // Unless the setting says to keep it.
      container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(onExit: OnExit.never));
      final stays = await local('se queda');
      stays.session.text(text: 'exit\n');
      await _until(tester, () => stays.phase == Phase.closed, 'its exit');
      await tester.pump(const Duration(milliseconds: 300));
      expect(titles(), contains('se queda'));
      while (container.read(tabsProvider).tabs.isNotEmpty) {
        tabs.close(0);
      }
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

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
    // Inherited until changed here: a click on the inherited value sets it
    // here, and its field takes the focus.
    await _reveal(tester, field('setting.user'));
    await tester.tap(field('setting.user'));
    await _settle(tester);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>()
          ?.key,
      const ValueKey('settings.user'),
    );
    await tester.enterText(field('settings.user'), 'deploy');
    await tester.tap(find.text('Guardar'));
    await _settle(tester);
    await tester.tap(field('sidebar.hosts'));
    await _settle(tester);
    expect(find.text('prod'), findsOneWidget);

    await tester.tap(field('hosts.new'));
    await _settle(tester);
    await tester.enterText(field('host.label'), 'web');
    await tester.enterText(field('host.address'), 'web.example.com');
    await _reveal(tester, field('setting.port'));
    await tester.tap(field('setting.port'));
    await _settle(tester);
    // Out of range: said on the field itself, which gets the focus.
    await tester.enterText(field('settings.port'), '70000');
    await tester.tap(find.text('Guardar'));
    await _settle(tester);
    expect(find.text('El puerto va de 1 a 65535.'), findsNWidgets(2));
    expect(
      tester.widget<TextField>(field('settings.port')).focusNode?.hasFocus,
      isTrue,
    );
    await _shot(tester, '18-port-out-of-range');
    await tester.enterText(field('settings.port'), '2222');
    await tester.pump();
    expect(
      find.text('El puerto va de 1 a 65535.'),
      findsOneWidget,
      reason: 'off the field once it is typed in; still in the footer',
    );
    await _reveal(tester, field('host.group'));
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
    await _reveal(tester, field('setting.port.reset'));
    await _shot(tester, '5-host-editor');
    // ↺ inherits again; «Advanced» opens with the rest.
    await tester.tap(field('setting.port.reset'));
    await _settle(tester);
    expect(field('settings.port'), findsNothing);
    expect(field('setting.port'), findsOneWidget);
    expect(field('setting.proxy'), findsNothing);
    await _reveal(tester, field('settings.advanced'));
    await tester.tap(field('settings.advanced'));
    await _settle(tester);
    expect(field('setting.proxy'), findsOneWidget);
    await tester.ensureVisible(field('setting.agent'));
    await _settle(tester);
    await _shot(tester, '5b-host-editor-advanced');
    // A change not saved: leaving asks first, Esc too, and saves nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar').last);
    await _settle(tester);
    expect(find.text('¿Descartar los cambios?'), findsNothing);
    expect(field('setting.agent'), findsOneWidget, reason: 'still editing');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar'));
    await _settle(tester);
    await tester.tap(find.text('Descartar'));
    await _settle(tester);
    expect(field('setting.agent'), findsNothing);
    expect(app.host(id: app.hosts().single.id).spec.settings.port, 2222);
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
    await _connect(tester, 'ninetwo');
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

  testWidgets('ssh: a server that does not tell its system, found out in '
      'one click', (tester) async {
    final fixtures = await _servers();
    if (fixtures == null) return markTestSkipped('S2 servers not running');
    final settings = SettingsSpec(
      user: 'demo',
      port: 22200,
      identityFiles: ['$fixtures/id_ed25519'],
      agent: AgentKind.off,
      hostKeyPolicy: KeyPolicy.acceptNew,
    );
    final alpine = await app.createHost(
      spec: HostSpec(label: 'alpine', address: '127.0.0.1', settings: settings),
    );
    final other = await app.createHost(
      spec: HostSpec(label: 'other', address: '127.0.0.1'),
    );
    final container = await launch(tester);
    HostView? host(String id) => container.read(libraryProvider).host(id);
    await _connect(tester, 'alpine');
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.connected, 'the connection');
    // Dropbear's banner does not say: the window offers to read it.
    await _until(
      tester,
      () => find.byKey(const ValueKey('system.offer')).evaluate().isNotEmpty,
      'the offer',
    );
    expect(host(alpine)?.system?.code, '?');
    expect(
      find.text('«alpine» no dice su sistema al conectar.'),
      findsOneWidget,
    );
    // Once it has come in.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '7b-system-offer');
    await tester.tap(
      find.widgetWithText(SnackBarAction, 'Leer /etc/os-release'),
    );
    await _until(
      tester,
      () => host(alpine)?.system?.code == 'alp',
      'the system read',
    );
    expect(host(alpine)?.system?.kind, SystemKind.osRelease);
    await _until(
      tester,
      () => find
          .textContaining('«alpine» es Alpine Linux 3.')
          .evaluate()
          .isNotEmpty,
      'what came of it',
    );
    // From now on, for this host.
    expect(app.host(id: alpine).spec.settings.readOsRelease, isTrue);

    // Never connected: the menu offers it too, for the next connection.
    container.read(tabsProvider.notifier).openPage(PageKind.hosts);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('hosts.row.other')),
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Averiguar el sistema'));
    await _until(
      tester,
      () => find.text('Se leerá al conectar a «other».').evaluate().isNotEmpty,
      'the next connection',
    );
    expect(app.host(id: other).spec.settings.readOsRelease, isTrue);

    // In Ajustes, for every host that does not say otherwise, on this
    // device.
    final loose = await app.createHost(
      spec: HostSpec(label: 'loose', address: '127.0.0.1'),
    );
    expect(app.host(id: loose).effective.readOsRelease, isFalse);
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(readOsRelease: true));
    await tester.pump();
    expect(app.host(id: loose).effective.readOsRelease, isTrue);
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(readOsRelease: false));
    await tester.pump();
    expect(app.host(id: loose).effective.readOsRelease, isFalse);
    container.read(tabsProvider.notifier).closeCurrent();
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
    final target = await app.createHost(
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
    await _connect(tester, 'target1');
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.connected, 'the connection');
    expect(c.route, ['bastion', 'target1']);
    // Connecting told each saved hop's system by its banner: the Hosts page
    // shows their logos.
    await _until(
      tester,
      () => container.read(libraryProvider).host(target)?.system?.code == 'deb',
      'the system told',
    );
    expect(
      container.read(libraryProvider).host(bastion)?.system?.name,
      'Debian 13',
    );
    container.read(tabsProvider.notifier).openPage(PageKind.hosts);
    await tester.pump(const Duration(milliseconds: 300));
    // Both rows, and the filter by system, by its name.
    expect(
      find.descendant(
        of: find.byType(HostsPage),
        matching: find.byWidgetPredicate(
          (w) => w is SystemGlyph && w.code == 'deb',
        ),
      ),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hosts.filter.system.deb')),
        matching: find.text('Debian'),
      ),
      findsOneWidget,
    );
    container.read(tabsProvider.notifier).closeCurrent();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.textContaining('Conectado'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('este equipo → bastion → target1'), findsOneWidget);
    await _shot(tester, '7-connection-info');
    await tester.tap(find.text('Cerrar'));
    await tester.pump(const Duration(milliseconds: 400));

    // The latency, once the first check answers: in the status bar, and
    // over it the chart, the route and the algorithms.
    await _until(
      tester,
      () => c.rttMs != null,
      'the first check',
      within: const Duration(seconds: 25),
    );
    await tester.pump();
    final latency = find.byKey(const ValueKey('status.latency'));
    expect(latency, findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(latency));
    // The wait before a tooltip, then its fade.
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Latencia con target1'), findsOneWidget);
    // The latency now, in the card as in the bar.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('latency.now'))).data,
      '${c.rttMs} ms',
    );
    // Each hop with its round trip from here: the bastion's is asked as
    // often as the target's.
    expect(c.hopRttMs, hasLength(1));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('latency.route')))
          .textSpan!
          .toPlainText(),
      // Each latency kept with its hop, by spaces that do not break.
      matches(
        RegExp(
          '^este equipo → bastion\u00a0\\d+\u00a0ms → target1\u00a0\\d+\u00a0ms\$',
        ),
      ),
    );
    await _shot(tester, '90-latency');
    await mouse.moveTo(Offset.zero);
    await mouse.removePointer();
    await tester.pump(const Duration(milliseconds: 300));

    // Drop the connection on the bastion: it comes back by itself.
    c.session.text(
      text:
          r'echo ppid-$PPID-end'
          '\n',
    );
    // The output line, not the echo of the command (which has `-end` too).
    bool pidLine(String l) => l.startsWith('ppid-') && l.endsWith('-end');
    await _until(
      tester,
      () => c.session.screenText().split('\n').any(pidLine),
      'the pid',
    );
    final line = c.session.screenText().split('\n').firstWhere(pidLine);
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

  testWidgets('ssh: connecting, a server that stops answering, and back', (
    tester,
  ) async {
    final fixtures = await _servers();
    if (fixtures == null) return markTestSkipped('S2 servers not running');
    await app.createHost(
      spec: HostSpec(
        label: 'minipc',
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: 'demo',
          port: 22101,
          identityFiles: ['$fixtures/id_ed25519'],
          agent: AgentKind.off,
          hostKeyPolicy: KeyPolicy.acceptNew,
        ),
      ),
    );
    final container = await launch(tester);
    final runtime = Platform.environment['S2_RUNTIME'] ?? 'podman';
    Future<void> freeze(bool on) async {
      final r = await Process.run(runtime, [
        on ? 'pause' : 'unpause',
        's2-freeze',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    // Frozen while it connects: the way there, animated.
    await freeze(true);
    late final TerminalController c;
    try {
      await _connect(tester, 'minipc');
      c = container.read(tabsProvider).currentSession!;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Conectando con minipc'), findsOneWidget);
      expect(find.text('Este equipo'), findsWidgets);
      await _shot(tester, '80-connecting');
    } finally {
      await freeze(false);
    }
    await _until(tester, () => c.phase == Phase.connected, 'the connection');
    c.session.text(text: 'echo ready-\$((6*7))\n');
    await _until(
      tester,
      () => c.session.screenText().contains('ready-42'),
      'the shell',
    );

    // Frozen while connected: it does not respond, then it is lost.
    await freeze(true);
    try {
      await _until(
        tester,
        () => c.stalledSince != null,
        'no answer',
        within: const Duration(seconds: 20),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('pane.stalled')), findsOneWidget);
      expect(find.textContaining('minipc no responde'), findsOneWidget);
      await _shot(tester, '81-not-responding');
      await _until(
        tester,
        () => c.phase == Phase.reconnecting && c.reconnectAt != null,
        'giving it up',
        within: const Duration(seconds: 30),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('pane.reconnect')), findsOneWidget);
      expect(find.text('Se perdió la conexión con minipc'), findsOneWidget);
      expect(find.text('Sin respuesta desde hace 20 s.'), findsOneWidget);
      await _shot(tester, '82-lost');
    } finally {
      await freeze(false);
    }
    await _until(
      tester,
      () => c.phase == Phase.connected,
      'back',
      within: const Duration(seconds: 60),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('pane.back')), findsOneWidget);
    expect(find.textContaining('Conectado de nuevo a minipc'), findsOneWidget);
    await _until(
      tester,
      () => c.session.screenText().contains('conectado de nuevo a las'),
      'the line where the new terminal starts',
    );
    await _shot(tester, '83-back');
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('ssh: a persistent session in tmux, found again after a cut', (
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
          hostKeyPolicy: KeyPolicy.acceptNew,
          persistentSession: true,
        ),
      ),
    );
    final container = await launch(tester);
    await _connect(tester, 'bastion');
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.connected, 'the connection');
    expect(c.persistent?.state, PersistenceKind.new_);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('tmux'), findsOneWidget);
    c.session.text(text: 'MARK=kept-\$((6*7)); echo set-\$MARK\n');
    await _until(
      tester,
      () => c.session.screenText().contains('set-kept-42'),
      'the variable',
    );
    // Cut it: the sshd above the tmux client goes, tmux stays.
    c.session.text(
      text:
          "echo sshd-\$(ps -o ppid= -p \$(tmux display -p '#{client_pid}') "
          "| tr -d ' ')-end\n",
    );
    String? pid;
    await _until(tester, () {
      pid = RegExp(
        r'^sshd-(\d+)-end$',
        multiLine: true,
      ).firstMatch(c.session.screenText())?.group(1);
      return pid != null;
    }, 'the sshd pid');
    final runtime = Platform.environment['S2_RUNTIME'] ?? 'podman';
    final killed = await Process.run(runtime, [
      'exec',
      'bastion',
      'kill',
      '-9',
      pid!,
    ]);
    expect(killed.exitCode, 0, reason: '${killed.stderr}');
    await _until(
      tester,
      () => c.phase == Phase.reconnecting,
      'the cut',
      within: const Duration(seconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Tu sesión sigue en tmux'), findsOneWidget);
    await _until(
      tester,
      () => c.phase == Phase.connected,
      'back',
      within: const Duration(seconds: 30),
    );
    expect(c.persistent?.state, PersistenceKind.resumed);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('sesión de tmux recuperada'), findsOneWidget);
    c.session.text(text: 'echo again-\$MARK\n');
    await _until(
      tester,
      () => c.session.screenText().contains('again-kept-42'),
      'the same shell',
    );
    await _shot(tester, '84-tmux-back');
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

    await _connect(tester, 'bastion');
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
    await _shot(tester, '13-start-light');
    await tester.tap(find.byKey(const ValueKey('sidebar.hosts')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('hosts.row.web-1')), findsOneWidget);
  });

  testWidgets('start: a quick connection that completes, the recent ones '
      'and the shortcuts sheet', (tester) async {
    for (final (label, address) in [
      ('web-1', '10.0.0.11'),
      ('web-2', '10.0.0.12'),
      ('db', '10.0.0.5'),
    ]) {
      await app.createHost(
        spec: HostSpec(label: label, address: address),
      );
    }
    final web2 = app.hosts().firstWhere((h) => h.label == 'web-2').id;
    // web-2 an hour ago, 38 minutes in tmux; an address two days ago.
    final now = DateTime.now().millisecondsSinceEpoch;
    const hour = 3600 * 1000;
    File('${dir.path}/data/recent.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'connections': [
          {
            'where': 'host:$web2',
            'label': 'web-2',
            'at': now - hour,
            'ended': now - hour + 38 * 60 * 1000,
            'tmux': true,
          },
          {
            'where': 'address:ops@10.0.0.9',
            'label': 'ops@10.0.0.9',
            'at': now - 48 * hour,
            'ended': now - 48 * hour + 2 * 60 * 1000,
          },
        ],
      }),
    );
    final container = await launch(tester);
    expect(find.byKey(ValueKey('recent.host:$web2')), findsOneWidget);
    expect(find.text('38 min · tmux'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recent.address:ops@10.0.0.9')),
      findsOneWidget,
    );
    await _shot(tester, '91-start');

    // «Conectar» on one line, the button wider instead: in Berenjena's
    // font at the biggest text size it read «Connec / t».
    final settings = container.read(settingsProvider);
    container
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            theme: ThemeChoice.dark,
            darkTheme: 'berenjena',
            textScale: 1.5,
          ),
        );
    await _settle(tester);
    final label = tester.renderObject<RenderBox>(
      find.descendant(
        of: find.byKey(const ValueKey('quick.connect')),
        matching: find.byType(RichText),
      ),
    );
    expect(label.size.height, label.getMaxIntrinsicHeight(double.infinity));
    await _shot(tester, '91b-start-big-text');
    container.read(settingsProvider.notifier).update((_) => settings);
    await _settle(tester);

    // Saved hosts first; of two as good, the one used last.
    final quick = find.byKey(const ValueKey('quick.address'));
    await tester.enterText(quick, 'web');
    await _settle(tester);
    final w1 = find.byKey(const ValueKey('quick.host.web-1'));
    final w2 = find.byKey(const ValueKey('quick.host.web-2'));
    expect(w1, findsOneWidget);
    expect(tester.getTopLeft(w2).dy, lessThan(tester.getTopLeft(w1).dy));
    // Not an address: nothing to connect to as typed.
    expect(find.textContaining('Conectar a '), findsNothing);
    await _shot(tester, '92-quick-hosts');

    // An address used before comes back.
    await tester.enterText(quick, 'ops@10');
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('quick.used.ops@10.0.0.9')),
      findsOneWidget,
    );

    // A new one: as typed (⌥↩), or saved as a host with what it says.
    await tester.enterText(quick, 'admin@10.0.0.20:2222');
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('quick.typed.Conectar a admin@10.0.0.20:2222')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('quick.save.Guardar como host…')),
    );
    await _settle(tester);
    expect(find.widgetWithText(TextField, 'admin'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2222'), findsOneWidget);
    await _shot(tester, '93-save-as-host');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);
    expect(
      app.hosts().any(
        (h) => h.address == '10.0.0.20' && h.port == 2222 && h.user == 'admin',
      ),
      isTrue,
    );

    // ⌥↩ connects to what was typed, whatever is suggested.
    await tester.tap(quick);
    await tester.enterText(quick, 'nadie@127.0.0.1:1');
    await _settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(container.read(tabsProvider).currentSession?.target?.port, 1);
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);

    // Every shortcut, from the start page, with a search.
    await tester.tap(find.byKey(const ValueKey('start.shortcuts')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('shortcuts')), findsOneWidget);
    await _shot(tester, '94-shortcuts');
    final search = find.byKey(const ValueKey('shortcuts.search'));
    await tester.enterText(search, 'dividir');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('shortcut.Dividir a la derecha')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('shortcut.Ajustes')), findsNothing);
    await tester.enterText(search, 'qqq');
    await tester.pump();
    expect(find.text('Ningún atajo con «qqq»'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const ValueKey('shortcuts')), findsNothing);

    // ⌘/ (Ctrl+Shift+/ elsewhere) opens it once, whichever key heard it.
    await _shortcut(tester, LogicalKeyboardKey.slash, letter: true);
    await _settle(tester);
    expect(find.byKey(const ValueKey('shortcuts')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
  });

  testWidgets('host identity: the environment from the group, one of its '
      'own, the system by hand and the favorites', (tester) async {
    final shop = await app.createGroup(spec: const GroupSpec(name: 'tienda'));
    final web = await app.createHost(
      spec: HostSpec(
        label: 'web-1',
        address: 'web-1.example.com',
        groupId: shop,
      ),
    );
    final lab = await app.createHost(
      spec: const HostSpec(
        label: 'lab',
        address: '127.0.0.1',
        settings: SettingsSpec(port: 1),
      ),
    );
    final container = await launch(tester);
    Finder key(String k) => find.byKey(ValueKey(k));
    HostView host(String id) => app.hosts().firstWhere((h) => h.id == id);

    // The group marks its hosts as production.
    await tester.tap(key('sidebar.hosts'));
    await _settle(tester);
    await tester.tap(find.text('tienda'), buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Editar grupo…'));
    await _settle(tester);
    await tester.tap(key('setting.environment'));
    await _settle(tester);
    await tester.tap(key('env.prod'));
    await _settle(tester);
    expect(find.text('prod · Producción'), findsWidgets);
    await _shot(tester, '96-group-environment');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);
    expect(host(web).environment?.short, 'prod');
    expect(host(lab).environment, isNull);

    // The host inherits it, says from where, and gets a system by hand
    // and a star.
    await tester.tap(find.text('web-1'), buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Editar…'));
    await _settle(tester);
    expect(find.text('prod · Producción'), findsOneWidget);
    expect(find.text('Del grupo tienda'), findsWidgets);
    expect(
      find.text('Se sabrá al conectar, por el banner del servidor.'),
      findsOneWidget,
    );
    await _reveal(tester, key('system.arch'));
    await tester.tap(key('system.arch'));
    await tester.pump();
    expect(tester.widget<Text>(key('system.name')).data, 'Arch');
    await _reveal(tester, key('host.favorite'));
    await tester.tap(key('host.favorite'));
    await tester.pump();
    await _reveal(tester, key('system.arch'));
    await _shot(tester, '97-host-identity');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);
    expect(host(web).system?.code, 'arch');
    expect(host(web).system?.kind, SystemKind.manual);
    expect(host(web).favorite, isNotNull);

    // A mark of its own, with its name and color.
    await tester.tap(find.text('lab'), buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Editar…'));
    await _settle(tester);
    await _reveal(tester, key('setting.environment'));
    await tester.tap(key('setting.environment'));
    await _settle(tester);
    await _reveal(tester, key('env.other'));
    await tester.tap(key('env.other'));
    await _settle(tester);
    await tester.enterText(key('envDialog.name'), 'Cliente A');
    await tester.enterText(key('envDialog.short'), 'cli-a');
    await tester.tap(key('envDialog.color.green'));
    await tester.pump();
    await tester.tap(key('envDialog.ok'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);
    expect(host(lab).environment?.short, 'cli-a');
    expect(host(lab).environment?.color, 'green');

    // The star on its row makes it a favorite too.
    await tester.tap(key('hosts.star.lab'));
    // The vault answers on its own thread.
    await _until(tester, () => host(lab).favorite != null, 'the star');
    await _settle(tester);
    await _shot(tester, '97b-hosts-page');
    // Both in the sidebar now, in their order.
    expect(key('sidebar.host.web-1'), findsOneWidget);
    expect(key('sidebar.host.lab'), findsOneWidget);
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);

    // The start page has them as cards, in their order; a drag reorders.
    expect(key('start.favorite.web-1'), findsOneWidget);
    expect(key('start.favorite.lab'), findsOneWidget);
    expect(
      tester.getTopLeft(key('start.favorite.web-1')).dx,
      lessThan(tester.getTopLeft(key('start.favorite.lab')).dx),
    );
    await _shot(tester, '98-start-favorites');
    await _drag(
      tester,
      tester.getCenter(key('start.favorite.lab')),
      tester.getCenter(key('start.favorite.web-1')),
    );
    await _until(
      tester,
      () => host(lab).favorite! < host(web).favorite!,
      'the new order',
    );
    await _settle(tester);
    expect(
      tester.getTopLeft(key('start.favorite.lab')).dx,
      lessThan(tester.getTopLeft(key('start.favorite.web-1')).dx),
    );

    // The palette has them before anything is typed.
    await _shortcut(tester, LogicalKeyboardKey.keyK, letter: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(key('palette.host.lab'), findsOneWidget);
    expect(key('palette.host.web-1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(key('palette.query'), findsNothing);

    // Its tab and its terminal carry the mark.
    await tester.tap(key('start.favorite.lab'));
    await tester.pump(const Duration(milliseconds: 300));
    final c = container.read(tabsProvider).currentSession!;
    await _until(tester, () => c.phase == Phase.closed, 'the refusal');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: find.byType(TabStrip), matching: find.text('cli-a')),
      findsOneWidget,
    );
    await _shot(tester, '99-tab-environment');
    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
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
  testWidgets(
    'sftp: from the terminal, folders, copies both ways, conflicts, permissions',
    (tester) async {
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
            hostKeyPolicy: KeyPolicy.acceptNew,
            // Marked: closing its terminal asks first.
            environment: EnvironmentKind.mark,
            environmentName: 'Producción',
            environmentShort: 'prod',
            environmentColor: 'red',
          ),
        ),
      );
      final work = Directory('${dir.path}/work')..createSync();
      File('${work.path}/hola.txt').writeAsStringSync('hola desde la ui\n');
      File('${work.path}/otro.txt').writeAsStringSync('otro\n');
      final container = await launch(tester);
      await _connect(tester, 'bastion');
      final term = container.read(tabsProvider).currentSession!;
      await _until(tester, () => term.phase == Phase.connected, 'the shell');
      await tester.pump(const Duration(milliseconds: 100));

      // From the terminal's status bar, over the same connection.
      await tester.tap(find.byKey(const ValueKey('status.sftp')));
      await tester.pump();
      final tab = container.read(tabsProvider).current! as SftpTab;
      final c = tab.controller;
      expect(_tab('SFTP · bastion'), findsOneWidget);
      await _until(tester, () => c.remote.path == '/home/demo', 'home');
      await c.local.open(work.path);
      await tester.pump(const Duration(milliseconds: 100));
      List<String> names(FilePane p) => [for (final e in p.entries) e.name];

      // A folder of its own on the server, opened with a double click.
      final folder = 'ow-ui-$pid';
      await tester.tap(find.byKey(const ValueKey('remote.newFolder')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const ValueKey('name.field')), folder);
      await tester.pump();
      await tester.tap(find.text('Crear'));
      await _until(
        tester,
        () => names(c.remote).contains(folder),
        'the folder',
      );
      final row = find.byKey(ValueKey('remote.row.$folder'));
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(row);
      await _until(
        tester,
        () => c.remote.path == '/home/demo/$folder',
        'inside the folder',
      );

      // Up with the button.
      await tester.tap(find.byKey(const ValueKey('local.row.hola.txt')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('local.copy')));
      await _until(
        tester,
        () => names(c.remote).contains('hola.txt'),
        'upload',
      );
      // And by dragging it across.
      final from = tester.getCenter(
        find.byKey(const ValueKey('local.row.otro.txt')),
      );
      final to = tester.getCenter(find.byKey(const ValueKey('remote.filter')));
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          Offset.lerp(from, to + const Offset(0, 120), i / 10)!,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await _until(
        tester,
        () => names(c.remote).contains('otro.txt'),
        'the drag',
      );
      await _shot(tester, '19-sftp');

      // Again: it exists. Both kept.
      await tester.tap(find.byKey(const ValueKey('local.row.hola.txt')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('local.copy')));
      await _until(
        tester,
        () => find.text('Ya existe en bastion').evaluate().isNotEmpty,
        'the question',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _shot(tester, '20-sftp-conflict');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Mantener los dos'));
      await tester.pump();
      await tester.tap(find.text('Seguir'));
      await _until(
        tester,
        () => names(c.remote).contains('hola (1).txt'),
        'the copy kept apart',
      );

      // Permissions with ⌘I, in octal.
      await tester.tap(find.byKey(const ValueKey('remote.row.hola.txt')));
      await tester.pump();
      await _shortcut(tester, LogicalKeyboardKey.keyI);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Permisos de hola.txt'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('perm.octal')), '600');
      // The boxes follow the number: one frame starts their animation,
      // the next one shows it done.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _shot(tester, '21-sftp-permissions');
      await tester.tap(find.text('Aplicar'));
      await _until(
        tester,
        () =>
            c.remote.entries.firstWhere((e) => e.name == 'hola.txt').mode ==
            0x180,
        'the new mode',
      );

      // Down with the button: it lands in the local folder on view.
      await tester.tap(find.byKey(const ValueKey('remote.row.hola (1).txt')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote.copy')));
      await _until(
        tester,
        () => names(c.local).contains('hola (1).txt'),
        'the download',
      );
      expect(
        File('${work.path}/hola (1).txt').readAsStringSync(),
        'hola desde la ui\n',
      );

      // The folder goes, after asking.
      await _shortcut(tester, LogicalKeyboardKey.arrowUp);
      await _until(tester, () => c.remote.path == '/home/demo', 'back home');
      await tester.tap(find.byKey(ValueKey('remote.row.$folder')));
      await tester.pump();
      await _shortcut(tester, LogicalKeyboardKey.backspace);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('¿Eliminar $folder?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await _until(
        tester,
        () => !names(c.remote).contains(folder),
        'the folder gone',
      );

      // The queue, opened and cleared.
      await tester.tap(find.byKey(const ValueKey('queue.open')));
      await tester.pump();
      expect(find.text('Todo terminado'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('queue.clear')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(transferQueueProvider).jobs, isEmpty);

      // Quitting asks while the terminal is up and a copy is on its way,
      // paused too; Cancel keeps it all.
      final big = File('${work.path}/grande.bin');
      big.openSync(mode: FileMode.write)
        ..truncateSync(1 << 30)
        ..closeSync();
      final copy = app.transfer(
        browser: c.browser,
        direction: TransferDirection.upload,
        source: big.path,
        destDir: '/home/demo',
        onConflict: ConflictChoice.replace,
      );
      app.pauseTransfer(id: copy);
      final queue = container.read(transferQueueProvider)..poke();
      await _until(
        tester,
        () => queue.jobs.any((j) => j.id == copy),
        'the copy in the queue',
      );
      final quitting = confirmQuit(tester.element(find.byType(Sidebar)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('¿Salir de OpenWard?'), findsOneWidget);
      expect(find.textContaining('1 transferencia en curso'), findsOneWidget);
      expect(find.textContaining('1 sesión abierta'), findsOneWidget);
      await _shot(tester, '21b-quit');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(await quitting, isFalse);
      app.cancelTransfer(id: copy);

      // A filter still on when the tab is left is there when it comes back.
      final filter = find.byKey(const ValueKey('remote.filter'));
      await tester.enterText(filter, 'hola');
      await tester.pump();
      container.read(tabsProvider.notifier).select(0);
      await tester.pump(const Duration(milliseconds: 100));
      container.read(tabsProvider.notifier).select(1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<TextField>(filter).controller!.text, 'hola');
      await tester.enterText(filter, '');
      await tester.pump();

      // ⌘W on the terminal of a marked host asks first; ⌘⇧T opens it again.
      final tabs = container.read(tabsProvider.notifier)..select(0);
      await tester.pump();
      await _shortcut(tester, LogicalKeyboardKey.keyW, letter: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('¿Cerrar «bastion»?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar'));
      await _settle(tester);
      expect(container.read(tabsProvider).tabs, hasLength(1));
      await _reopen(tester);
      await _settle(tester);
      expect(container.read(tabsProvider).currentSession?.label, 'bastion');

      // Renamed while open: the session goes by its new name.
      final reopened = container.read(tabsProvider).currentSession!;
      final read = app.host(id: reopened.hostId!);
      final spec = read.spec;
      await app.updateHost(
        id: reopened.hostId!,
        rev: read.rev,
        spec: HostSpec(
          label: 'bastion-eu',
          address: spec.address,
          groupId: spec.groupId,
          tags: spec.tags,
          notes: spec.notes,
          settings: spec.settings,
          favorite: spec.favorite,
          systemCode: spec.systemCode,
        ),
      );
      await _until(
        tester,
        () => reopened.label == 'bastion-eu',
        'the new name in the tab',
      );

      tabs
        ..close(1)
        ..close(0);
      await _settle(tester);
    },
  );
  testWidgets('tunnels: from the page, through it, and on connect', (
    tester,
  ) async {
    final fixtures = await _servers();
    if (fixtures == null) return markTestSkipped('S2 servers not running');
    final hostId = await app.createHost(
      spec: HostSpec(
        label: 'bastion',
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: 'demo',
          port: 22100,
          identityFiles: ['$fixtures/id_ed25519'],
          agent: AgentKind.off,
          hostKeyPolicy: KeyPolicy.acceptNew,
        ),
      ),
    );
    Future<int> freePort() async {
      final s = await ServerSocket.bind('127.0.0.1', 0);
      final port = s.port;
      await s.close();
      return port;
    }

    final port = await freePort();
    final container = await launch(tester);
    final board = container.read(tunnelBoardProvider);
    TunnelView? named(String label) =>
        board.tunnels.where((t) => t.spec.label == label).firstOrNull;

    await tester.tap(find.byKey(const ValueKey('library.tunnels')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Aún no hay túneles'), findsOneWidget);

    // A new one, saved and opened from the editor.
    await tester.tap(find.byKey(const ValueKey('tunnels.new')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byKey(const ValueKey('tunnel.label')),
      'SSH del bastión',
    );
    await tester.tap(find.byKey(const ValueKey('tunnel.host')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('bastion').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('tunnel.listen')),
      '$port',
    );
    await tester.enterText(
      find.byKey(const ValueKey('tunnel.dest')),
      '127.0.0.1',
    );
    await tester.enterText(find.byKey(const ValueKey('tunnel.destPort')), '22');
    await tester.pump(const Duration(milliseconds: 100));
    await _shot(tester, '22-tunnel-editor');
    await tester.tap(find.text('Guardar y abrir'));
    await _until(
      tester,
      () => named('SSH del bastión')?.state == TunnelStateKind.open,
      'the tunnel open',
    );
    // Through it, the bastion's own SSH server.
    final socket = await Socket.connect('127.0.0.1', port);
    final banner = await socket.first.timeout(const Duration(seconds: 5));
    expect(String.fromCharCodes(banner), startsWith('SSH-2.0-OpenSSH'));
    socket.destroy();
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '23-tunnels');

    // With no tab open, the start page has it among the open ones, with
    // a button to stop it.
    container.read(tabsProvider.notifier).close(0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('start.tunnel.SSH del bastión')),
      findsOneWidget,
    );
    await _shot(tester, '95-start-tunnels');
    await tester.tap(
      find.byKey(const ValueKey('start.tunnel.stop.SSH del bastión')),
    );
    await _until(
      tester,
      () => named('SSH del bastión')?.state == TunnelStateKind.closed,
      'the tunnel closed',
    );

    // On connect: one opens, one whose port is taken says so.
    final taken = await ServerSocket.bind('127.0.0.1', 0);
    await app.createTunnel(
      spec: TunnelSpec(
        label: 'pgAdmin',
        hostId: hostId,
        kind: TunnelKind.local,
        listenPort: taken.port,
        destHost: 'localhost',
        destPort: 80,
        autostart: true,
      ),
    );
    final autoPort = await freePort();
    await app.createTunnel(
      spec: TunnelSpec(
        label: 'Proxy SOCKS',
        hostId: hostId,
        kind: TunnelKind.dynamic_,
        listenPort: autoPort,
        autostart: true,
      ),
    );
    board.refresh();
    await _connect(tester, 'bastion');
    final term = container.read(tabsProvider).currentSession!;
    await _until(tester, () => term.phase == Phase.connected, 'the shell');
    await _until(
      tester,
      () => named('Proxy SOCKS')?.state == TunnelStateKind.open,
      'the tunnel that opens on connect',
    );
    await _until(
      tester,
      () => find
          .textContaining('No se abrió «pgAdmin» al conectar')
          .evaluate()
          .isNotEmpty,
      'the notice',
    );
    expect(find.text('1 túnel abierto'), findsOneWidget);
    await _shot(tester, '24-tunnel-notice');
    await tester.tap(find.byKey(const ValueKey('status.tunnels')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Túneles de bastion'), findsOneWidget);
    await _shot(tester, '25-tunnel-popover');
    await tester.tapAt(const Offset(10, 400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Ignorar'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('No se abrió «pgAdmin»'), findsNothing);
    await taken.close();

    for (final t in board.tunnels) {
      board.close(t.id);
    }
    container.read(tabsProvider.notifier)
      ..close(1)
      ..close(0);
    await _settle(tester);
  });

  testWidgets(
    'identities: made, used on a group, shown in the editor, and in',
    (tester) async {
      final fixtures = await _servers();
      if (fixtures == null) return markTestSkipped('S2 servers not running');
      final group = await app.createGroup(
        spec: const GroupSpec(
          name: 'Producción',
          settings: SettingsSpec(
            agent: AgentKind.off,
            hostKeyPolicy: KeyPolicy.acceptNew,
          ),
        ),
      );
      // No user or key of its own: they come from the identity.
      await app.createHost(
        spec: HostSpec(
          label: 'bastion',
          address: '127.0.0.1',
          groupId: group,
          settings: const SettingsSpec(port: 22100),
        ),
      );
      await app.createHost(
        spec: HostSpec(
          label: 'web-1',
          address: 'web-1.example.com',
          groupId: group,
          settings: const SettingsSpec(user: 'root'),
        ),
      );
      final container = await launch(tester);
      Finder field(String key) => find.byKey(ValueKey(key));
      IdentityView? named(String label) => container
          .read(identitiesProvider)
          .where((i) => i.spec.label == label)
          .firstOrNull;

      await tester.tap(field('library.identities'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Aún no hay identidades'), findsOneWidget);

      // The key only gets in through its certificate, found next to it.
      await tester.tap(field('identities.new'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(field('identity.label'), 'demo en S2');
      await tester.enterText(field('identity.user'), 'demo');
      await tester.enterText(field('identity.keyPath'), '$fixtures/id_cert');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(tildePath('$fixtures/id_cert')), findsOneWidget);
      expect(find.textContaining('Ed25519 · SHA256:'), findsOneWidget);
      expect(find.text('id_cert-cert.pub'), findsOneWidget);
      await tester.tap(field('identity.only'));
      await tester.pump(const Duration(milliseconds: 200));
      await _shot(tester, '26-identity-editor');
      await tester.tap(find.text('Guardar'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(named('demo en S2')?.spec.identitiesOnly, isTrue);
      expect(find.text('Nadie la usa todavía'), findsOneWidget);

      // On the group: both hosts get it; web-1 keeps its own user.
      await tester.tap(field('identity.use.demo en S2'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Usar «demo en S2» en…'), findsOneWidget);
      await tester.tap(field('use.Producción'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Cambian 2 hosts · la usarán 2'), findsOneWidget);
      expect(find.text('La hereda de Producción'), findsNWidgets(2));
      expect(
        find.text('Pone su propio usuario (root), que seguirá mandando.'),
        findsOneWidget,
      );
      await _shot(tester, '27-identity-use');
      await tester.tap(field('identity.use.apply'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(named('demo en S2')!.hostCount, 2);
      expect(find.text('Grupo Producción · 2 hosts'), findsOneWidget);
      await _shot(tester, '28-identities');
      // The Hosts page shows the identity's user.
      await tester.tap(field('sidebar.hosts'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('demo@127.0.0.1:22100'), findsOneWidget);

      // The host editor says where each value comes from.
      await tester.tap(find.text('bastion'), buttons: kSecondaryButton);
      await _settle(tester);
      await tester.tap(find.text('Editar…'));
      await _settle(tester);
      expect(find.text('Del grupo Producción'), findsWidgets);
      expect(find.text('Editar la identidad'), findsOneWidget);
      expect(find.text('De la identidad demo en S2'), findsWidgets);
      await _shot(tester, '29-identity-host');
      await tester.tap(find.text('Cancelar'));
      await _settle(tester);

      // The group's editor, with the choice open.
      await tester.tap(
        field('hosts.group.Producción'),
        buttons: kSecondaryButton,
      );
      await _settle(tester);
      await tester.tap(find.text('Editar grupo…'));
      await _settle(tester);
      await tester.tap(find.text('demo en S2').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nueva identidad…'), findsOneWidget);
      await _shot(tester, '30-identity-group');
      await tester.tap(find.text('demo en S2').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancelar'));
      await _settle(tester);

      // In with the identity's user, key and certificate, nothing asked.
      await _connect(tester, 'bastion');
      final term = container.read(tabsProvider).currentSession!;
      await _until(tester, () => term.phase == Phase.connected, 'the shell');
      expect(term.prompts, isEmpty);
      term.session.text(text: 'echo who-\$(whoami)-end\n');
      await _until(
        tester,
        () => term.session.screenText().contains('who-demo-end'),
        'whoami',
      );

      // Gone: its hosts go back to inheriting.
      container.read(tabsProvider.notifier).close(1);
      await _settle(tester);
      await tester.tap(field('identity.demo en S2'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Eliminar'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('¿Eliminar «demo en S2»?'), findsOneWidget);
      await tester.tap(field('identity.delete.confirm'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Aún no hay identidades'), findsOneWidget);
      expect(app.host(id: app.hosts().first.id).spec.settings.identity, isNull);
      container.read(tabsProvider.notifier).close(0);
      await _settle(tester);
    },
  );

  testWidgets('snippets: made on the page, run with ⌘⇧S, and to every pane', (
    tester,
  ) async {
    final container = await launch(tester);
    Finder field(String key) => find.byKey(ValueKey(key));
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
      await tester.pump(const Duration(milliseconds: 150));
    }

    final cmdShift = isApple
        ? [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];

    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final tab = container.read(tabsProvider).current! as SessionTab;
    final a = tab.panes.active.controller!;
    await _until(tester, () => a.phase == Phase.running, 'the shell');

    await tester.tap(field('library.snippets'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Aún no hay snippets'), findsOneWidget);
    await tester.tap(field('snippets.new'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(field('snippet.label'), 'Saludo');
    await tester.enterText(
      field('snippet.script'),
      'echo hola-{{nombre}}-{{host}}',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field('snippet.default.nombre'), 'mundo');
    await tester.pump(const Duration(milliseconds: 100));
    await _shot(tester, '31-snippet-editor');
    await tester.tap(find.text('Guardar'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saludo'), findsOneWidget);
    await _shot(tester, '32-snippets');

    // Back in the terminal: ⌘⇧S, find it, Enter, fill in the variable.
    container.read(tabsProvider.notifier).select(0);
    await tester.pump(const Duration(milliseconds: 300));
    await keys(cmdShift, LogicalKeyboardKey.keyS);
    expect(field('snippets.query'), findsOneWidget);
    await tester.enterText(field('snippets.query'), 'salu');
    await tester.pump(const Duration(milliseconds: 100));
    await _shot(tester, '33-snippet-palette');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ejecutar «Saludo»'), findsOneWidget);
    await tester.enterText(field('snippet.var.nombre'), 'ana');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(field('snippet.send'));
    await tester.pump(const Duration(milliseconds: 200));
    await _until(
      tester,
      () => a.session.screenText().contains('hola-ana-Local'),
      'the snippet run',
    );

    // With broadcast, to both panes, each with its own values.
    container.read(tabsProvider.notifier).split(Axis.horizontal);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    final b = tab.panes.active.controller!;
    await _until(tester, () => b.phase == Phase.running, 'the second shell');
    await keys(cmdShift, LogicalKeyboardKey.keyB);
    expect(tab.panes.broadcast, isTrue);
    await tester.tap(field('status.snippets').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('palette.Saludo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Va a los 2 paneles que reciben el broadcast'),
      findsOneWidget,
    );
    expect(find.text('Enviar a 2 paneles'), findsOneWidget);
    await _shot(tester, '34-snippet-broadcast');
    await tester.tap(field('snippet.send'));
    for (final c in [a, b]) {
      await _until(
        tester,
        () => c.session.screenText().contains('hola-mundo-Local'),
        'the snippet in every pane',
      );
    }

    // Deleted from its editor, it comes back from the notice.
    container.read(tabsProvider.notifier).select(1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('snippet.Saludo'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Eliminar'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.snippets(), isEmpty);
    expect(find.text('Snippet «Saludo» eliminado'), findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await _until(
      tester,
      () => app.snippets().any((s) => s.spec.label == 'Saludo'),
      'the snippet back',
    );

    container.read(tabsProvider.notifier)
      ..close(1)
      ..close(0);
    await _settle(tester);
  });

  testWidgets('known hosts: both sources, a hashed line, and forgetting one', (
    tester,
  ) async {
    const key =
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f';
    const other =
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJON9ypgHeCkesivXcy8heayyTUCM9gTjTKSUZit/91';
    const hashed =
        '|1|MDEyMzQ1Njc4OWFiY2RlZmdoaWo=|xBEZ8so+rs/llqU4DkVYMFhGsbE=';
    // A ~/.ssh of its own: the tester's known_hosts stays out.
    final ssh = Directory('${dir.path}/ssh')..createSync();
    final file = File('${ssh.path}/known_hosts')
      ..writeAsStringSync(
        '$hashed $other\n10.0.4.21 $key db\n@revoked old.example.com $other\n',
      );
    app = await OpenWard.openWithSshDir(
      dataDir: '${dir.path}/own',
      sshDir: ssh.path,
    );
    await app.createHost(
      spec: const HostSpec(label: 'bastion', address: 'bastion.example.com'),
    );
    await app.trustHostKey(host: 'bastion.example.com', port: 22, key: key);
    await launch(tester);
    Finder field(String key) => find.byKey(ValueKey(key));

    await tester.tap(field('library.knownHosts'));
    // The rows come from the core off the UI thread.
    await _until(
      tester,
      () => find.text('Nombre cifrado').evaluate().isNotEmpty,
      'the known hosts',
    );
    expect(find.text('Coincide con bastion.example.com'), findsOneWidget);
    expect(find.text('Revocada: se rechaza siempre'), findsOneWidget);
    expect(find.text('Todas · 4'), findsOneWidget);
    await tester.enterText(field('known.query'), 'bastion.example.com');
    await _until(
      tester,
      () => find.text('2 coinciden').evaluate().isNotEmpty,
      'the search',
    );
    await _shot(tester, '35-known-hosts');

    await tester.tap(field('known.forget.line1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('¿Quitar la clave de bastion de'),
      findsOneWidget,
    );
    await _shot(tester, '36-known-hosts-forget');
    await tester.tap(field('known.forget.confirm'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(file.readAsStringSync(), isNot(contains(hashed)));
    expect(File('${file.path}.old').existsSync(), isTrue);
    await _until(
      tester,
      () => find.text('1 coincide').evaluate().isNotEmpty,
      'the list without it',
    );
    ProviderScope.containerOf(tester.element(find.byType(OpenWardApp)))
        .read(tabsProvider.notifier)
        .close(0);
    await _settle(tester);
  });

  /// ⌘⇧ and a key (Ctrl+Shift off Apple platforms), with time to react.
  Future<void> cmdShift(WidgetTester tester, LogicalKeyboardKey key) async {
    final mods = isApple
        ? [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
    for (final k in mods) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(key);
    for (final k in mods.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  Finder field(String key) => find.byKey(ValueKey(key));

  testWidgets('keys: make one, bring one in, and put it on a server', (
    tester,
  ) async {
    // A home of its own: the tester's ~/.ssh stays out.
    final home = Directory('${dir.path}/home')..createSync();
    app.dispose();
    app = await OpenWard.openWithHome(
      dataDir: '${dir.path}/data',
      home: home.path,
    );
    final container = await launch(tester);
    await tester.tap(field('library.keys'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No hay claves en ~/.ssh'), findsOneWidget);

    await tester.tap(field('keys.new'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nueva clave'), findsOneWidget);
    expect(find.text('~/.ssh/'), findsWidgets);
    await _shot(tester, '70-new-key');
    await tester.tap(field('newKey.make'));
    await _until(
      tester,
      () => container.read(keysProvider).isNotEmpty,
      'the new key',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(field('key.id_ed25519'), findsOneWidget);
    expect(find.text('Sin frase de paso'), findsOneWidget);
    final private = File('${home.path}/.ssh/id_ed25519');
    expect(private.statSync().modeString(), 'rw-------');
    expect(File('${private.path}.pub').existsSync(), isTrue);

    // The same key brought in under another name.
    await tester.tap(field('keys.import'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(field('importKey.text'), private.readAsStringSync());
    await tester.enterText(field('importKey.name'), 'copia');
    await tester.pump();
    await tester.tap(field('importKey.save'));
    await _until(
      tester,
      () => container.read(keysProvider).length == 2,
      'the key brought in',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guardada en ~/.ssh/copia.'), findsOneWidget);
    await _shot(tester, '71-keys');

    // From its menu: renamed, given a passphrase, and deleted.
    Future<void> menu(String key, String item) async {
      await tester.tap(field('key.menu.$key'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(item).last);
      await tester.pump(const Duration(milliseconds: 300));
    }

    await menu('copia', 'Renombrar…');
    await tester.enterText(field('key.rename.name'), 'copia2');
    await tester.tap(field('key.rename.save'));
    await _until(
      tester,
      () => container.read(keysProvider).any((k) => k.name == 'copia2'),
      'the key renamed',
    );
    expect(File('${home.path}/.ssh/copia').existsSync(), isFalse);
    expect(File('${home.path}/.ssh/copia2.pub').existsSync(), isTrue);
    await menu('copia2', 'Cambiar la frase de paso…');
    await tester.enterText(field('key.passphrase.new'), 'frase larga');
    await tester.enterText(field('key.passphrase.again'), 'frase larga');
    await tester.tap(field('key.passphrase.save'));
    await _until(
      tester,
      () => container
          .read(keysProvider)
          .any((k) => k.name == 'copia2' && k.encrypted),
      'the key behind a passphrase',
    );
    await menu('copia2', 'Eliminar…');
    expect(find.text('¿Eliminar copia2?'), findsOneWidget);
    await _shot(tester, '72-delete-key');
    await tester.tap(field('key.delete.confirm'));
    await _until(
      tester,
      () => container.read(keysProvider).length == 1,
      'the key deleted',
    );
    expect(File('${home.path}/.ssh/copia2').existsSync(), isFalse);

    final fixtures = await _servers();
    if (fixtures == null) {
      container.read(tabsProvider.notifier).closeCurrent();
      await _settle(tester);
      return;
    }
    // Onto the server, signing in with the key it takes now.
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
    container.read(libraryProvider.notifier).refresh();
    await tester.pump();
    await tester.tap(field('key.upload.id_ed25519'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Subir id_ed25519 a un servidor'), findsOneWidget);
    await _shot(tester, '73-install-key');
    await tester.tap(field('installKey.host.bastion'));
    await _until(
      tester,
      () => find.text('Confiar y conectar').evaluate().isNotEmpty,
      'the host key question',
    );
    await tester.tap(find.text('Confiar y conectar'));
    await _until(
      tester,
      () => field('installKey.done').evaluate().isNotEmpty,
      'the key on the server',
    );
    expect(find.text('Clave añadida en bastion'), findsOneWidget);
    await _shot(tester, '74-key-installed');
    await tester.tap(field('installKey.close'));
    await tester.pump(const Duration(milliseconds: 300));

    // Now the new key alone signs in.
    await app.createHost(
      spec: const HostSpec(
        label: 'con-la-nueva',
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: 'demo',
          port: 22100,
          identityFiles: ['~/.ssh/id_ed25519'],
          agent: AgentKind.off,
        ),
      ),
    );
    container.read(libraryProvider.notifier).refresh();
    container
        .read(tabsProvider.notifier)
        .openHost(app.hosts().firstWhere((h) => h.label == 'con-la-nueva'));
    final c = container.read(tabsProvider).currentSession!;
    await _until(
      tester,
      () => c.phase == Phase.connected || c.phase == Phase.closed,
      'signing in with the new key',
    );
    expect(c.closed?.failure?.message, isNull);
    expect(c.connected, isNotNull);
    final tabs = container.read(tabsProvider.notifier);
    while (container.read(tabsProvider).tabs.isNotEmpty) {
      tabs.close(0);
    }
    await _settle(tester);
  });

  testWidgets('workspaces: save the panes from the palette, open them again', (
    tester,
  ) async {
    final container = await launch(tester);
    final tabs = container.read(tabsProvider.notifier);
    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final tab = container.read(tabsProvider).current! as SessionTab;
    final a = tab.panes.active.controller!;
    await _until(tester, () => a.phase == Phase.running, 'the shell');
    tabs.split(Axis.vertical);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    final b = tab.panes.active.controller!;
    await _until(tester, () => b.phase == Phase.running, 'the second shell');

    // ⌘⇧P, a few letters, Enter.
    await cmdShift(tester, LogicalKeyboardKey.keyP);
    expect(field('palette.query'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '72-palette');
    await tester.enterText(field('palette.query'), 'guardar las');
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      field('palette.action.Guardar las pestañas abiertas…'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guardar como espacio de trabajo'), findsOneWidget);
    expect(find.text('1 pestaña · 2 sesiones'), findsOneWidget);
    await tester.enterText(field('workspace.name'), 'Dos locales');
    await _shot(tester, '75-save-workspace');
    await tester.tap(field('workspace.save'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(workspacesProvider).single.spec.name, 'Dos locales');

    tabs.close(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('library.workspaces'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(field('workspace.Dos locales'), findsOneWidget);
    await _shot(tester, '76-workspaces');
    await tester.tap(field('workspace.open.Dos locales'));
    await tester.pump(const Duration(milliseconds: 300));
    final state = container.read(tabsProvider);
    final again = state.current! as SessionTab;
    final split = again.panes.root as PaneSplit;
    expect(split.axis, Axis.vertical);
    expect(identical(again.panes.active, again.panes.leaves.last), isTrue);
    for (final c in again.panes.controllers) {
      await _until(tester, () => c.phase == Phase.running, 'a shell again');
    }
    await _shot(tester, '77-workspace-open');

    // Renamed and deleted from its page.
    tabs.select(state.tabs.indexWhere((t) => t is PageTab));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('workspace.menu.Dos locales'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Renombrar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(field('workspace.rename'), 'Locales');
    await tester.tap(find.text('Guardar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(field('workspace.Locales'), findsOneWidget);
    await tester.tap(field('workspace.menu.Locales'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Eliminar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('workspace.delete.confirm'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(workspacesProvider), isEmpty);
    expect(find.text('Aún no hay espacios de trabajo'), findsOneWidget);
    while (container.read(tabsProvider).tabs.isNotEmpty) {
      tabs.close(0);
    }
    await _settle(tester);
  });

  testWidgets('history: what ran is kept, a password never, and runs again', (
    tester,
  ) async {
    final container = await launch(tester);
    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final a = container.read(tabsProvider).currentSession!;
    await _until(tester, () => a.phase == Phase.running, 'the shell');
    await tester.pump(const Duration(milliseconds: 500));
    var pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    List<String> kept() => [
      for (final e in container.read(historyProvider)) e.command,
    ];

    /// Typed as the input method types, then Enter once it shows.
    Future<void> run(String command, {String? shows}) async {
      pane.updateEditingValue(
        TextEditingValue(
          text: '  $command',
          selection: TextSelection.collapsed(offset: command.length + 2),
        ),
      );
      if (shows != null) {
        await _until(
          tester,
          () => a.session.screenText().contains(shows),
          'the echo of $shows',
        );
      } else {
        await tester.pump(const Duration(milliseconds: 400));
      }
      pane.performAction(TextInputAction.newline);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await run(r'echo kept-$((40+2))', shows: r'echo kept-$((40+2))');
    await _until(
      tester,
      () => a.session.screenText().contains('kept-42\n'),
      'the command run',
    );
    expect(kept(), [r'echo kept-$((40+2))']);

    // A space in front: not kept.
    await run(' echo unkept', shows: 'echo unkept');
    expect(kept(), [r'echo kept-$((40+2))']);

    // What the terminal does not show is never kept.
    // (stty and read: the same in bash and zsh.)
    await run(
      "stty -echo; printf 'Password: '; read pw; stty echo; echo got-\${#pw}",
      shows: 'echo got-',
    );
    await _until(
      tester,
      () => a.session.screenText().contains('Password:'),
      'the password prompt',
    );
    await run('hunter2');
    await _until(
      tester,
      () => a.session.screenText().contains('got-7'),
      'the password read',
    );
    expect(kept().any((c) => c.contains('hunter2')), isFalse);
    expect(kept().first, startsWith('stty -echo'));

    // From the palette, again: it runs, and counts twice.
    await cmdShift(tester, LogicalKeyboardKey.keyP);
    await tester.enterText(field('palette.query'), 'kept');
    await tester.pump(const Duration(milliseconds: 100));
    expect(field(r'palette.history.echo kept-$((40+2))'), findsOneWidget);
    await _shot(tester, '78-palette-history');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    await _until(
      tester,
      () => 'kept-42\n'.allMatches(a.session.screenText()).length >= 2,
      'the command run again',
    );
    expect(container.read(historyProvider).first.count, 2);

    // Its row in Ajustes › Registros.
    final tabs = container.read(tabsProvider.notifier);
    tabs.openPage(PageKind.settings);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('settings.section.logs'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(field('settings.commandHistory'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Borrar 2 comandos'), findsOneWidget);
    await _shot(tester, '79-settings-history');
    // Clearing it asks first.
    await tester.tap(field('settings.clearHistory'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('¿Borrar el historial de comandos?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(historyProvider), isNotEmpty);
    tabs.close(1);
    await tester.pump(const Duration(milliseconds: 300));
    // Shown again: a pane of its own.
    pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));

    // Off in the settings: nothing more is kept.
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(commandHistory: false));
    await run('echo off-1', shows: 'echo off-1');
    expect(kept().contains('echo off-1'), isFalse);
    container.read(historyProvider.notifier).clear();
    expect(container.read(historyProvider), isEmpty);

    container.read(tabsProvider.notifier).close(0);
    await _settle(tester);
  });

  testWidgets('logs: a local session recorded, found, watched, kept and '
      'deleted', (tester) async {
    app.setLogsConfig(
      config: LogsConfig(
        recordLocal: true,
        keepDays: 30,
        maxBytes: BigInt.from(1 << 30),
      ),
    );
    final container = await launch(tester);
    await tester.tap(find.text('Abrir un terminal local'));
    await tester.pump();
    final a = container.read(tabsProvider).currentSession!;
    await _until(tester, () => a.phase == Phase.running, 'the shell');
    await tester.pump(const Duration(milliseconds: 500));
    final pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    expect(a.session.logState()!.recording, isTrue);

    Future<void> run(String command, String shows) async {
      pane.updateEditingValue(
        TextEditingValue(
          text: '  $command',
          selection: TextSelection.collapsed(offset: command.length + 2),
        ),
      );
      await _until(
        tester,
        () => a.session.screenText().contains(command),
        'the echo of $command',
      );
      pane.performAction(TextInputAction.newline);
      await _until(
        tester,
        () => a.session.screenText().contains('$shows\n'),
        'what $command shows',
      );
    }

    await run(r'echo logged-$((40+2))', 'logged-42');
    await tester.pump(const Duration(milliseconds: 300));
    await run(r'echo second-$((1+1))', 'second-2');
    pane.updateEditingValue(
      const TextEditingValue(
        text: '  exit',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    pane.performAction(TextInputAction.newline);
    await _until(
      tester,
      () => container.read(logsProvider).firstOrNull?.end == LogEnd.closed,
      'the session to end',
    );
    final entry = container.read(logsProvider).single;
    expect(entry.recorded, isTrue);
    expect(entry.commands, 3);

    // The page, with ⌘⇧R.
    await cmdShift(tester, LogicalKeyboardKey.keyR);
    await tester.pump(const Duration(milliseconds: 500));
    expect(field('logs.row.${entry.id}'), findsOneWidget);
    await _until(
      tester,
      () => tester
          .widgetList<Text>(find.byKey(const ValueKey('logs.preview.lines')))
          .any((t) => t.data!.contains('second-2')),
      'the last lines in the preview',
    );
    await _shot(tester, '100-logs');

    // Searched, ignoring case: the line and the moment.
    await tester.enterText(field('logs.search'), 'LOGGED-42');
    await _until(
      tester,
      () => find.text('1 coincidencia en 1 registro').evaluate().isNotEmpty,
      'the search',
    );
    await tester.tap(find.text('logged-42').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Abrir aquí'), findsOneWidget);
    await _shot(tester, '101-logs-search');

    // Opened there: the terminal as it was.
    await tester.tap(field('logs.open'));
    await _until(
      tester,
      () => container.read(logViewerProvider) != null,
      'the viewer',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final v = container.read(logViewerProvider)!;
    expect(v.commands.map((m) => m.command), [
      r'echo logged-$((40+2))',
      r'echo second-$((1+1))',
      'exit',
    ]);
    expect(v.terminal.session.screenText(), contains('logged-42'));
    expect(find.text('Solo lectura'), findsOneWidget);

    // A command: what it answered, and nothing after.
    await tester.tap(field('log.command.0'));
    await _until(
      tester,
      () =>
          v.currentCommand == 0 &&
          v.terminal.session.screenText().contains('logged-42\n'),
      'the first command',
    );
    expect(v.terminal.session.screenText(), isNot(contains('second-2')));

    // Kept, with a note.
    await tester.tap(field('log.save'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'el arreglo del 502',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Guardar'),
      ),
    );
    await _until(
      tester,
      () => field('log.note').evaluate().isNotEmpty,
      'the note',
    );
    expect(
      find.descendant(
        of: field('log.note'),
        matching: find.text('el arreglo del 502'),
      ),
      findsOneWidget,
    );
    expect(container.read(logsProvider).single.saved, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '102-log-viewer');

    // Played to the end, fast.
    await tester.tap(field('log.speed'));
    await tester.tap(field('log.speed'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(field('log.play'));
    await tester.pump(const Duration(milliseconds: 100));
    await _until(tester, () => !v.playing, 'the end of the recording');
    expect(v.position, v.duration);
    expect(v.terminal.session.screenText(), contains('second-2'));

    // Deleted: the tab closes and the page is empty.
    await tester.tap(field('log.more'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('log.delete'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(field('log.delete.confirm'));
    await _until(
      tester,
      () => container.read(logsProvider).isEmpty,
      'the log deleted',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      container
          .read(tabsProvider)
          .tabs
          .any((t) => t is PageTab && t.page == PageKind.log),
      isFalse,
    );
  });

  testWidgets('logs: turned on in Ajustes, paused and opened from the pane, '
      'and a group that records', (tester) async {
    final group = await app.createGroup(
      spec: const GroupSpec(
        name: 'prod',
        settings: SettingsSpec(sessionLog: true),
      ),
    );
    final container = await launch(tester);
    final tabs = container.read(tabsProvider.notifier);

    // Ajustes › Registros: the group that turns it on by itself, local
    // terminals too, kept 90 days.
    tabs.openPage(PageKind.settings);
    await _settle(tester);
    await tester.tap(field('settings.section.logs'));
    await _settle(tester);
    expect(field('settings.logSetIn.$group'), findsOneWidget);
    expect(find.text('Activado solo en:'), findsOneWidget);
    await tester.tap(field('settings.logLocal'));
    await _settle(tester);
    expect(app.logsConfig().recordLocal, isTrue);
    await tester.tap(field('settings.logDays'));
    await _settle(tester);
    await tester.tap(find.text('A los 90 días').last);
    await _settle(tester);
    expect(app.logsConfig().keepDays, 90);
    await _shot(tester, '103-settings-logs');

    // Its chip opens the group's editor at «Registro de sesión».
    await tester.tap(field('settings.logSetIn.$group'));
    await _settle(tester);
    expect(field('settings.sessionLog'), findsOneWidget);
    expect(find.text('Sí, lo que sale en pantalla'), findsWidgets);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar'));
    await _settle(tester);
    expect(field('settings.sessionLog'), findsNothing);

    // A local terminal now records: «Registro» under it.
    tabs.openLocal();
    await tester.pump();
    final a = container.read(tabsProvider).currentSession!;
    await _until(tester, () => a.phase == Phase.running, 'the shell');
    await _until(
      tester,
      () => field('log.chip').evaluate().isNotEmpty,
      'the log chip',
    );
    final pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));

    Future<void> run(String command, String shows) async {
      pane.updateEditingValue(
        TextEditingValue(
          text: '  $command',
          selection: TextSelection.collapsed(offset: command.length + 2),
        ),
      );
      await _until(
        tester,
        () => a.session.screenText().contains(command),
        'the echo of $command',
      );
      pane.performAction(TextInputAction.newline);
      await _until(
        tester,
        () => a.session.screenText().contains('$shows\n'),
        'what $command shows',
      );
    }

    await run(r'echo before-$((40+2))', 'before-42');

    // Paused from its menu: what comes out meanwhile is not kept.
    await tester.tap(field('log.chip'));
    await _settle(tester);
    await tester.tap(field('log.pause'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(a.log!.paused, isTrue);
    expect(find.textContaining('En pausa · 0:0'), findsOneWidget);
    await _shot(tester, '104-log-paused');
    await run(r'echo hidden-$((3*3))', 'hidden-9');
    await tester.tap(field('log.chip'));
    await _settle(tester);
    await tester.tap(field('log.resume'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(a.log!.paused, isFalse);
    await run(r'echo after-$((2*2))', 'after-4');
    // Written every 2 s.
    var written = '';
    unawaited(
      Future.doWhile(() async {
        written = await app.logText(id: a.logId!);
        return !written.contains('after-4');
      }),
    );
    await _until(tester, () => written.contains('after-4'), 'the log written');

    // Opened from the pane, while it goes on.
    await tester.tap(field('log.chip'));
    await _settle(tester);
    await tester.tap(field('log.openThis'));
    await _until(
      tester,
      () => container.read(logViewerProvider) != null,
      'the viewer',
    );
    final v = container.read(logViewerProvider)!;
    final seen = v.terminal.session.screenText();
    expect(seen, contains('before-42'));
    expect(seen, contains('after-4'));
    expect(seen, isNot(contains('hidden-9')));
    expect(v.pauses, isNotEmpty);
    // Not cut short: going on, its entry with what it has so far.
    expect(find.textContaining('Sigue grabando'), findsOneWidget);
    expect(find.textContaining('se cerró de golpe'), findsNothing);
    final live = app.log(id: a.logId!)!;
    expect(live.commands, 2);
    expect(live.bytes > BigInt.zero, isTrue);
    expect(v.entry.bytes > BigInt.zero, isTrue);

    // Deleting all leaves the session going on.
    tabs.openPage(PageKind.settings);
    await _settle(tester);
    await tester.tap(field('settings.logDeleteAll'));
    await _settle(tester);
    await tester.tap(field('settings.logDeleteAll.confirm'));
    await _settle(tester);
    expect(container.read(logsProvider).single.id, a.logId);
  });
}
