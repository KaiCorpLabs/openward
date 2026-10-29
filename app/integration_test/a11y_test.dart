// Every screen and editor against the accessibility guidelines, in three
// looks (two themes and a high-contrast one, two languages, two text
// sizes, a large window and the smallest): whatever can be pressed has a
// name, an action a screen reader can use, and is at least 28×28; text
// reads on what it sits on (4.5:1) and is never under 12 px; and the
// terminal reads its lines to a screen reader.
//
//   fvm flutter test integration_test/a11y_test.dart -d macos

@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:openward/l10n/l10n.dart';
import 'package:openward/logs/log_viewer.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/identities.dart';
import 'package:openward/src/rust/api/keychain.dart';
import 'package:openward/src/rust/api/logs.dart';
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

/// 28×28: the least the app gives a control in a line of text (32 apart),
/// WCAG 2.2's target size and some. A control partly scrolled out of view
/// is not measured: its rect is what shows of it.
class _TargetSize extends AccessibilityGuideline {
  const _TargetSize();

  static const least = 28.0;

  @override
  String get description => 'Every control is at least 28×28';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    final small = find.semantics.byPredicate((n) {
      final d = n.getSemanticsData();
      if (!d.hasAction(SemanticsAction.tap)) return false;
      if (n.isMergedIntoParent || n.isInvisible) return false;
      final r = n.rect;
      final clip = n.parentPaintClipRect;
      if (clip != null &&
          (r.top <= clip.top + 0.5 ||
              r.bottom >= clip.bottom - 0.5 ||
              r.left <= clip.left + 0.5 ||
              r.right >= clip.right - 0.5)) {
        return false;
      }
      return r.width < least - 0.01 || r.height < least - 0.01;
    }).evaluate();
    return small.isEmpty
        ? const Evaluation.pass()
        : Evaluation.fail(
            small
                .map(
                  (n) =>
                      '${n.rect.size.width.toStringAsFixed(1)}×'
                      '${n.rect.size.height.toStringAsFixed(1)} '
                      '«${n.label.isEmpty ? n.tooltip : n.label}»',
                )
                .join('\n'),
          );
  }
}

/// Every button a screen reader finds can be pressed from it: a button
/// node without a tap action is one VoiceOver names and cannot use.
class _ButtonsAct extends AccessibilityGuideline {
  const _ButtonsAct();

  @override
  String get description => 'Every button node has a tap action';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    final mute = find.semantics.byPredicate((n) {
      final f = n.flagsCollection;
      if (!f.isButton) return false;
      if (f.isEnabled == ui.Tristate.isFalse) return false;
      return !n.getSemanticsData().hasAction(SemanticsAction.tap);
    }).evaluate();
    return mute.isEmpty
        ? const Evaluation.pass()
        : Evaluation.fail(
            mute.map((n) => 'no tap: «${n.label}» at ${n.rect}').join('\n'),
          );
  }
}

/// Text reads on what it sits on: 4.5:1, 3:1 when large (WCAG 1.4.3). Its
/// colors from the tree, as drawn (the guideline that reads pixels takes a
/// button's outline for its text); what is under it, the nearest colored
/// ancestors, blended until one is opaque. Disabled controls are exempt.
class _TextContrast extends AccessibilityGuideline {
  const _TextContrast();

  @override
  String get description => 'Text reads at 4.5:1 on its background';

  static double _lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) * 1.0;
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  static double ratio(Color a, Color b) {
    final (x, y) = (_lum(a), _lum(b));
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  /// What paints under `e`, and how much its opacity lets through; null
  /// when it sits in a disabled control or nothing opaque is found.
  static (Color, double)? _under(Element e) {
    final layers = <Color>[];
    var opacity = 1.0;
    var disabled = false;
    Color? opaque;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is ButtonStyleButton && !w.enabled) disabled = true;
      // A theme's terminal palette as it is: the page says its contrast.
      if (w.key == const ValueKey('appearance.terminalSample')) {
        disabled = true;
      }
      return !disabled;
    });
    if (disabled) return null;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Opacity) opacity *= w.opacity;
      final color = switch (w) {
        ColoredBox(:final color) => color,
        DecoratedBox(decoration: BoxDecoration(:final color?)) => color,
        Material(:final color?, :final type)
            when type != MaterialType.transparency =>
          color,
        _ => null,
      };
      if (color == null || color.a == 0) return true;
      if (color.a >= 1) {
        opaque = color;
        return false;
      }
      layers.add(color);
      return true;
    });
    if (disabled || opaque == null) return null;
    var bg = opaque!;
    for (final c in layers.reversed) {
      bg = Color.alphaBlend(c, bg);
    }
    return (bg, opacity);
  }

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    final low = <String>{};
    for (final e in find.byType(RichText).evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final under = _under(e);
      if (under == null) continue;
      final (bg, opacity) = under;
      final base = DefaultTextStyle.of(e).style;
      void visit(InlineSpan span, TextStyle style) {
        final here = style.merge(span.style);
        if (span is! TextSpan) return;
        final text = (span.text ?? '')
            .replaceAll(RegExp('[\u200b-\u200f\u2060\ufeff\ue000-\uf8ff]'), '')
            .trim();
        final color = here.color;
        if (text.isNotEmpty && color != null && color.a * opacity > 0.05) {
          final fg = Color.alphaBlend(
            color.withValues(alpha: color.a * opacity),
            bg,
          );
          final size = here.fontSize ?? 14;
          final bold = (here.fontWeight?.value ?? 400) >= 700;
          final large = size >= 18 || (bold && size >= 14);
          final r = ratio(fg, bg);
          if (r < (large ? 3 : 4.5)) {
            low.add(
              '${r.toStringAsFixed(2)}:1 «${text.length > 40 ? '${text.substring(0, 40)}…' : text}»',
            );
          }
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, here);
        }
      }

      visit((e.widget as RichText).text, base);
    }
    return low.isEmpty
        ? const Evaluation.pass()
        : Evaluation.fail(low.join('\n'));
  }
}

/// One way of seeing the app: a theme, a language, a text size and a
/// window.
class _Look {
  const _Look(
    this.name, {
    required this.language,
    required this.brightness,
    this.darkTheme,
    this.textScale = 1,
    this.size = const Size(1280, 800),
  });

  final String name;
  final String language;
  final Brightness brightness;
  final String? darkTheme;
  final double textScale;
  final Size size;
}

const _looks = [
  _Look('Grafito, es, 100 %', language: 'es', brightness: Brightness.dark),
  _Look(
    'Papel, en, 150 %',
    language: 'en',
    brightness: Brightness.light,
    textScale: 1.5,
  ),
  _Look(
    'Alto contraste, es, 760×480',
    language: 'es',
    brightness: Brightness.dark,
    darkTheme: 'contraste-oscuro',
    size: Size(760, 480),
  ),
];

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

  for (final look in _looks) {
    testWidgets(
      'every screen and editor, ${look.name}: named, usable by a screen '
      'reader, big enough to press and readable',
      (tester) => _walk(tester, look),
    );
  }
}

Future<void> _walk(WidgetTester tester, _Look look) async {
  final l = lookupAppLocalizations(Locale(look.language));
  {
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
    // The local terminal recorded: its log's chip, page and viewer.
    app.setLogsConfig(
      config: LogsConfig(
        recordLocal: true,
        keepDays: 30,
        maxBytes: BigInt.from(1 << 30),
      ),
    );
    final settings = File('${dir.path}/data/settings.json')
      ..writeAsStringSync(
        jsonEncode({
          'language': look.language,
          'welcomed': true,
          'text_scale': look.textScale,
          'dark_theme': ?look.darkTheme,
        }),
      );

    tester.view.physicalSize = look.size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.platformBrightnessTestValue = look.brightness;
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
    // Content that does not fit (a small window, large text) is a problem
    // like the rest, said with where it happened, not a crash at the end.
    var step = 'start';
    final reported = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) {
        problems.add(
          '== ${look.name}: after $step\n'
          '${d.toString().split('\n').where((l) => l.trim().isNotEmpty).take(40).join('\n')}',
        );
        return;
      }
      reported?.call(d);
    };
    // Put back before the test ends: the binding checks it then.
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      Future<void> audit(String where) async {
        step = where;
        await tester.pump(const Duration(milliseconds: 400));
        for (final g in [
          labeledTapTargetGuideline,
          const _TargetSize(),
          const _ButtonsAct(),
          const _TextContrast(),
          const _TextSize(),
        ]) {
          final e = await g.evaluate(tester);
          if (!e.passed) problems.add('== ${look.name}: $where\n${e.reason}');
        }
      }

      // Into view first: in a small window or with large text, what comes
      // next may be below the fold.
      // Pressed only once it can be: a closing dialog still holds the
      // pointer for its animation. A press that misses would audit the
      // wrong screen, so it fails the test.
      Future<void> tapOn(Finder f, {bool secondary = false}) async {
        await tester.ensureVisible(f);
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          // What loads above it can push it out of view again.
          await tester.ensureVisible(f.first);
          final target = tester.renderObject(f.first);
          final at = tester.getCenter(f.first, warnIfMissed: false);
          if (tester.hitTestOnBinding(at).path.any((e) => e.target == target)) {
            break;
          }
        }
        await tester.tap(
          f.first,
          buttons: secondary ? kSecondaryButton : kPrimaryButton,
        );
      }

      Future<void> tapText(String text, {bool secondary = false}) async {
        await tapOn(find.text(text).first, secondary: secondary);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> close() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Who updated sees the news once.
      expect(find.text(l.whatsNew), findsOneWidget);
      await audit("what's new");
      await _shot(tester, '37-whats-new');
      await tapOn(find.byKey(const ValueKey('news.start')));
      await tester.pump(const Duration(milliseconds: 400));
      await audit('start');
      // Every host on their page; a host's and a group's editors from there.
      tabs.openPage(PageKind.hosts);
      await audit('hosts page');
      await tapText('web', secondary: true);
      await tapText(l.editEllipsis);
      await audit('host editor');
      await tapOn(find.byKey(const ValueKey('settings.advanced')));
      await audit('host editor: advanced');
      await close();
      // The group's name, upper-cased or not by the theme.
      await tapOn(
        find.textContaining(RegExp(r'^prod$', caseSensitive: false)).first,
        secondary: true,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tapText(l.editGroup);
      await audit('group editor');
      // Its environment: the marks to choose from, and one of its own.
      await tapOn(find.byKey(const ValueKey('setting.environment')));
      await tester.pump(const Duration(milliseconds: 300));
      await tapOn(find.byKey(const ValueKey('env.prod')));
      await audit('group editor: environment');
      await tapOn(find.byKey(const ValueKey('env.other')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('envDialog.name')),
        'Cliente',
      );
      await audit('another environment');
      await close();
      // The mark chosen is a change: leaving asks first.
      await close();
      expect(find.text(l.discardChangesTitle), findsOneWidget);
      await audit('discard changes');
      await tapText(l.discardChanges);
      // Back to the start page.
      tabs.closeCurrent();
      await tester.pump(const Duration(milliseconds: 400));

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
      // And a favorite, in the sidebar and on the start page.
      await app.setFavorite(id: web, favorite: true);
      container.read(libraryProvider.notifier).refresh();
      await audit('start: recent connections');
      await _shot(tester, '39-start-recent');
      final quick = find.byKey(const ValueKey('quick.address'));
      await tester.enterText(quick, 'w');
      await audit('start: suggestions');
      await tester.enterText(quick, '');
      await tapOn(find.byKey(const ValueKey('start.shortcuts')));
      await audit('shortcuts');
      await close();

      tabs.openPage(PageKind.settings);
      await audit('settings: general');
      await tapOn(find.byKey(const ValueKey('about.report')));
      await tester.pump(const Duration(milliseconds: 400));
      await audit('report a problem');
      await _shot(tester, '38-report');
      await close();
      await tapText(l.settingsAppearance);
      await audit('settings: appearance');
      await tapText(l.settingsTerminal);
      await audit('settings: terminal');
      await tapOn(find.byKey(const ValueKey('settings.section.logs')));
      await tester.pump(const Duration(milliseconds: 400));
      await audit('settings: logs');

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
      await tapText(l.useOn);
      await audit('use an identity');
      await close();

      tabs.openPage(PageKind.snippets);
      await audit('snippets');
      await tapText('Logs');
      await audit('snippet editor');
      await close();

      // Importing from another program: where from, Termius's warning, and
      // what would come (the made-up Termius data).
      await tapOn(find.byTooltip(l.moreActions));
      await tester.pump(const Duration(milliseconds: 400));
      await tapText(l.importEllipsis);
      await audit('import: where from');
      await close();
      final sidebar = tester.element(find.byType(Sidebar));
      unawaited(confirmTermius(sidebar));
      await audit("import: Termius's warning");
      await close();
      final termius = await app.readProgramWithKey(
        path:
            '$_repo/core/crates/openward-import/tests/fixtures/termius/Termius',
        termiusKey: List.filled(32, 0x42),
      );
      unawaited(
        showProgramPreview(sidebar, app.previewProgram(data: termius.data!)),
      );
      await audit('import: what comes');
      await close();

      tabs.openPage(PageKind.knownHosts);
      // Its rows come from the core off the UI thread.
      for (var i = 0; find.byTooltip(l.forgetAction).evaluate().isEmpty; i++) {
        if (i == 100) fail('the known hosts never showed');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await audit('known hosts');
      await tapOn(find.byTooltip(l.forgetAction).first);
      await tester.pump(const Duration(milliseconds: 400));
      await audit('forget a key');
      await close();

      tabs.openPage(PageKind.keys);
      await audit('keys');
      await tapOn(find.byKey(const ValueKey('keys.new')));
      await tester.pump(const Duration(milliseconds: 400));
      await audit('new key');
      await close();
      await tapOn(find.byKey(const ValueKey('keys.import')));
      await tester.pump(const Duration(milliseconds: 400));
      await audit('import a key');
      await close();

      tabs.openPage(PageKind.workspaces);
      await audit('workspaces');

      tabs.openPage(PageKind.hosts);
      await audit('hosts page, with a favorite and a recent one');
      await tapOn(find.byKey(const ValueKey('hosts.view.cards')));
      await audit('hosts page, cards');
      await tapOn(find.byKey(const ValueKey('hosts.view.list')));
      await tester.pump(const Duration(milliseconds: 300));

      tabs.openLocal();
      final term = container.read(tabsProvider).currentSession!;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (term.phase != Phase.running && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await audit('terminal');
      // A screen reader hears what the shell said, line by line.
      term.session.text(text: 'echo a11y-\$((6*7))\n');
      for (
        var i = 0;
        find.semantics.byLabel(RegExp(r'^a11y-42$')).evaluate().isEmpty;
        i++
      ) {
        if (i == 200) fail('the terminal did not read its line');
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Its log: the chip and its menu, paused; the page and the viewer.
      for (var i = 0; term.logId == null; i++) {
        if (i == 100) fail('the terminal was not recorded');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tapOn(find.byKey(const ValueKey('log.chip')));
      await audit('log menu');
      await tapOn(find.byKey(const ValueKey('log.pause')));
      await audit('log paused');
      await tapOn(find.byKey(const ValueKey('log.chip')));
      await audit('log menu, paused');
      await tapOn(find.byKey(const ValueKey('log.resume')));
      await tester.pump(const Duration(milliseconds: 400));
      tabs.openPage(PageKind.logs);
      for (
        var i = 0;
        find.byKey(ValueKey('logs.row.${term.logId}')).evaluate().isEmpty;
        i++
      ) {
        if (i == 100) fail('the log never showed on its page');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await audit('logs page');
      // Narrow, without the preview, its row opens it.
      final open = find.byKey(const ValueKey('logs.open'));
      await tapOn(
        open.evaluate().isNotEmpty
            ? open
            : find.byKey(ValueKey('logs.row.${term.logId}')),
      );
      for (var i = 0; container.read(logViewerProvider) == null; i++) {
        if (i == 100) fail('the viewer never opened');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await audit('log viewer');
      tabs.select(
        container
            .read(tabsProvider)
            .tabs
            .indexWhere((t) => t is SessionTab && t.controller == term),
      );
      // The sidebar as a rail, and shown over the window.
      final sidebarState = container.read(sidebarProvider.notifier);
      sidebarState.chose(SidebarMode.rail);
      await audit('rail');
      await tapOn(find.byKey(const ValueKey('rail.open')));
      await audit('rail: the open tabs');
      await close();
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
      // Panes: what a new one opens, and a pane's menu.
      tabs.split(Axis.horizontal);
      await audit('new pane');
      await tapOn(find.byKey(ValueKey('pane.choice.${l.localTerminal}')));
      await tester.pump(const Duration(milliseconds: 400));
      await tapOn(find.byTooltip(l.paneOptions).first);
      await audit('pane menu');
      await close();
      tabs.openPage(PageKind.workspaces);
      await tester.pump(const Duration(milliseconds: 400));
      await tapOn(find.byKey(const ValueKey('workspaces.save')));
      await tester.pump(const Duration(milliseconds: 400));
      await audit('save a workspace');
      await close();

      final report = problems.join('\n');
      // Also in a file, to read the whole list when it fails.
      File(
        '${Directory.systemTemp.path}/openward-a11y-${_looks.indexOf(look)}.txt',
      ).writeAsStringSync(report);
      tabs.closeCurrent();
      await tester.pump(const Duration(milliseconds: 300));
      semantics.dispose();
      expect(problems, isEmpty, reason: report);
    } finally {
      FlutterError.onError = reported;
      WidgetController.hitTestWarningShouldBeFatal = false;
    }
  }
}
