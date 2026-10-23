import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openward/l10n/app_localizations.dart';
import 'package:openward/sftp/dialogs.dart';
import 'package:openward/sftp/files.dart';
import 'package:openward/sftp/format.dart';
import 'package:openward/sftp/queue_view.dart';
import 'package:openward/src/rust/api/sftp.dart';
import 'package:openward/ui/themes.dart';
import 'package:path/path.dart' as p;

FileEntry entry(
  String name, {
  FileKind kind = FileKind.file,
  int size = 0,
  int? modified,
  int? mode,
  bool linkDir = false,
  String? owner,
}) => FileEntry(
  name: name,
  kind: kind,
  linkDir: linkDir,
  size: size,
  modified: modified,
  mode: mode,
  owner: owner,
);

/// A server in memory: folder paths and what is in them.
class FakeFiles implements FileSystem {
  FakeFiles(this.tree);

  final Map<String, List<FileEntry>> tree;

  @override
  p.Context get paths => p.posix;

  @override
  Future<String> home() async => '/home/demo';

  @override
  Future<List<FileEntry>> list(String dir) async {
    final found = tree[dir];
    if (found == null) {
      throw FileError(kind: FileErrorKind.denied, path: dir, message: '');
    }
    return found;
  }

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<void> remove(List<String> paths) async {}

  @override
  Future<int> chmod(String path, int mode, {required bool recursive}) async {
    chmods.add((path, mode, recursive));
    return 1;
  }

  final chmods = <(String, int, bool)>[];
}

TransferView job({
  TransferState state = TransferState.running,
  TransferDirection direction = TransferDirection.upload,
  int total = 0,
  int done = 0,
  double rate = 0,
  int skipped = 0,
  FileError? error,
}) => TransferView(
  id: BigInt.one,
  direction: direction,
  name: 'build.tar.gz',
  source: '/Users/ana/dist/build.tar.gz',
  destDir: '/var/www/app',
  host: 'web-1',
  isDir: false,
  files: 1,
  filesDone: 0,
  skipped: skipped,
  total: total,
  done: done,
  rate: rate,
  state: state,
  error: error,
);

void main() {
  late AppLocalizations es;
  late AppLocalizations en;

  setUpAll(() async {
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
    es = lookupAppLocalizations(const Locale('es'));
    en = lookupAppLocalizations(const Locale('en'));
  });

  test('names sort as people expect', () {
    final names = ['file10', 'File2', 'file1', 'b', 'a10b', 'a9b'];
    names.sort(compareNames);
    expect(names, ['a9b', 'a10b', 'b', 'file1', 'File2', 'file10']);
  });

  /// A big folder is sorted once per change, not once per row, key or
  /// footer that asks: ⌘A and an arrow fit in a frame.
  test(
    'a folder of 5000 files is sorted once, however often it is asked',
    () async {
      final pane = FilePane(
        Side.remote,
        FakeFiles({
          '/big': [for (var i = 0; i < 5000; i++) entry('file$i.log', size: i)],
        }),
      );
      await pane.open('/big');
      final shown = pane.visible;
      expect(shown.take(3).map((e) => e.name), [
        'file0.log',
        'file1.log',
        'file2.log',
      ]);
      pane.selectAll();
      final watch = Stopwatch()..start();
      for (var i = 0; i < 5000; i++) {
        expect(identical(pane.visible, shown), isTrue);
        expect(pane.selection.length, 5000);
      }
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 200)));
      pane.selected.remove('file0.log');
      expect(pane.selection.length, 4999);
      pane.setFilter('file1');
      expect(identical(pane.visible, shown), isFalse);
    },
  );

  group('a pane', () {
    late FilePane pane;

    setUp(() async {
      pane = FilePane(
        Side.remote,
        FakeFiles({
          '/home/demo': [
            entry('zeta.txt', size: 10, modified: 300),
            entry('Alpha.txt', size: 30, modified: 100),
            entry('.env', size: 5),
            entry('releases', kind: FileKind.dir),
            entry('current', kind: FileKind.link, linkDir: true),
            entry('beta.log', size: 20, modified: 200),
          ],
          '/home/demo/releases': [entry('one', kind: FileKind.dir)],
          '/home': [entry('demo', kind: FileKind.dir)],
        }),
      );
      await pane.goHome();
    });

    List<String> names() => [for (final e in pane.visible) e.name];

    test('folders first, hidden files apart, filter and sort', () {
      expect(names(), [
        'current',
        'releases',
        'Alpha.txt',
        'beta.log',
        'zeta.txt',
      ]);
      pane.toggleHidden();
      expect(names().last, 'zeta.txt');
      expect(names(), contains('.env'));
      pane.toggleHidden();
      pane.setFilter('TXT');
      expect(names(), ['Alpha.txt', 'zeta.txt']);
      pane.setFilter('');
      // Size and date: the largest and the newest first, as in the Finder.
      pane.sort(SortBy.size);
      expect(names().skip(2), ['Alpha.txt', 'beta.log', 'zeta.txt']);
      pane.sort(SortBy.size);
      expect(names().skip(2), ['zeta.txt', 'beta.log', 'Alpha.txt']);
      pane.sort(SortBy.modified);
      expect(names().skip(2), ['zeta.txt', 'beta.log', 'Alpha.txt']);
      expect(names().take(2), ['current', 'releases'], reason: 'folders first');
    });

    test('clicks, ⌘ and ⇧ select as in the Finder', () {
      pane.click('Alpha.txt');
      expect(pane.selected, {'Alpha.txt'});
      pane.click('zeta.txt', range: true);
      expect(pane.selected, {'Alpha.txt', 'beta.log', 'zeta.txt'});
      pane.click('beta.log', toggle: true);
      expect(pane.selected, {'Alpha.txt', 'zeta.txt'});
      expect(pane.selectedBytes, 40);
      pane.moveCursor(-1);
      expect(pane.selected, {'Alpha.txt'});
      pane.moveCursor(1, extend: true);
      expect(pane.selected, {'Alpha.txt', 'beta.log'});
      pane.selectAll();
      expect(pane.selected.length, 5);
    });

    test('a press within the selection keeps it until released', () {
      pane.click('Alpha.txt');
      pane.click('zeta.txt', range: true);
      pane.press('beta.log');
      expect(pane.selected, {'Alpha.txt', 'beta.log', 'zeta.txt'});
      expect(pane.cursor, 'beta.log');
      // Dragged: all of it went, and it stays selected.
      pane.keepSelection();
      pane.release('beta.log');
      expect(pane.selected, {'Alpha.txt', 'beta.log', 'zeta.txt'});
      // Released without a drag: a click there, as in the Finder.
      pane.press('beta.log');
      pane.release('beta.log');
      expect(pane.selected, {'beta.log'});
      // With ⌘, or outside the selection, the press is the click.
      pane.click('zeta.txt', toggle: true);
      pane.press('zeta.txt', toggle: true);
      expect(pane.selected, {'beta.log'});
      pane.press('Alpha.txt');
      expect(pane.selected, {'Alpha.txt'});
      pane.release('Alpha.txt');
      expect(pane.selected, {'Alpha.txt'});
    });

    test('folders, the way up and the breadcrumb', () async {
      expect(pane.crumbs(), [('~', '/home/demo')]);
      await pane.enter(pane.visible.firstWhere((e) => e.name == 'releases'));
      expect(pane.path, '/home/demo/releases');
      expect(pane.crumbs(), [
        ('~', '/home/demo'),
        ('releases', '/home/demo/releases'),
      ]);
      await pane.up();
      expect(pane.path, '/home/demo');
      expect(pane.selected, {'releases'}, reason: 'it came from there');
      await pane.up();
      expect(pane.crumbs(), [('/', '/'), ('home', '/home')]);
    });

    test('a folder that cannot be listed leaves the one shown', () async {
      await pane.open('/root');
      expect(pane.path, '/home/demo');
      expect(pane.error?.kind, FileErrorKind.denied);
      expect(fileErrorText(es, pane.error!), 'Sin permiso: /root');
    });
  });

  test('sizes, permissions and times', () {
    expect(formatSize(es, 68), '68 B');
    expect(formatSize(es, 184 * 1024), '184 KB');
    expect(formatSize(es, (2.1 * 1024 * 1024).round()), '2,1 MB');
    expect(formatSize(en, (2.1 * 1024 * 1024).round()), '2.1 MB');
    expect(formatSize(es, 940 * 1024 * 1024), '940 MB');
    expect(formatMode(0x1ec), 'rwxr-xr--');
    expect(octal(0x1ec), '754');
    expect(formatDuration(const Duration(seconds: 19)), '19 s');
    expect(formatDuration(const Duration(seconds: 65)), '1 min 5 s');
    expect(formatDuration(const Duration(minutes: 123)), '2 h 3 min');
    final now = DateTime(2026, 10, 15, 12);
    int at(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
    expect(
      formatDate(es, at(DateTime(2026, 10, 15, 10, 2)), now: now),
      'hoy 10:02',
    );
    expect(
      formatDate(es, at(DateTime(2026, 10, 14, 18, 40)), now: now),
      'ayer 18:40',
    );
    expect(
      formatDate(en, at(DateTime(2026, 10, 14, 18, 40)), now: now),
      'yesterday 18:40',
    );
    expect(formatDate(es, at(DateTime(2026, 10, 2)), now: now), '2 oct');
    expect(
      formatDate(es, at(DateTime(2024, 9, 2)), now: now),
      startsWith('2 sept'),
    );
    expect(formatDate(es, null), '');
  });

  test('conflicts suggest replacing only what is older', () {
    ConflictView c(FileEntry ours, FileEntry theirs) =>
        ConflictView(source: '/x', ours: ours, theirs: theirs);
    expect(
      suggestedChoice(c(entry('a', modified: 200), entry('a', modified: 100))),
      ConflictChoice.replace,
    );
    expect(
      suggestedChoice(c(entry('a', modified: 100), entry('a', modified: 200))),
      ConflictChoice.skip,
    );
    expect(suggestedChoice(c(entry('a'), entry('a'))), ConflictChoice.skip);
    final dir = entry('d', kind: FileKind.dir);
    expect(suggestedChoice(c(dir, dir)), ConflictChoice.newer);
    expect(suggestedChoice(c(dir, entry('d'))), ConflictChoice.skip);
  });

  test('the queue in words', () {
    expect(
      queueSummary(es, [
        job(),
        job(state: TransferState.queued),
        job(state: TransferState.queued),
        job(state: TransferState.failed),
      ]),
      '1 en curso · 2 en cola · 1 con error',
    );
    expect(
      queueSummary(es, [job(state: TransferState.done)]),
      'Todo terminado',
    );
    final mb = 1024 * 1024;
    expect(
      jobStatus(es, job(total: 940 * mb, done: 584 * mb, rate: 18.4 * mb)),
      '584 MB de 940 MB · 18 MB/s · quedan 20 s',
    );
    expect(jobStatus(es, job(total: 0)), 'Contando…');
    expect(
      jobStatus(
        es,
        job(
          state: TransferState.failed,
          total: 1229 * mb,
          done: 312 * mb,
          error: const FileError(
            kind: FileErrorKind.lost,
            path: '',
            message: '',
          ),
        ),
      ),
      'Se cortó la conexión con 312 MB de 1,2 GB copiados',
    );
    expect(
      jobStatus(es, job(state: TransferState.done, total: 2048, skipped: 2)),
      'Hecho · 2,0 KB · 2 ya estaban',
    );
    expect(jobRoute(es, job()), '/Users/ana/dist → web-1:/var/www/app');
    expect(
      jobRoute(es, job(direction: TransferDirection.download)),
      'web-1:/Users/ana/dist → /var/www/app',
    );
  });

  testWidgets('permissions: boxes and octal agree, and apply', (tester) async {
    final fs = FakeFiles({});
    await _showPermissions(tester, fs);
    expect(find.text('Permisos de run.sh'), findsOneWidget);
    expect(find.textContaining('deploy', findRichText: true), findsOneWidget);
    List<bool?> boxes() => [
      for (final c in tester.widgetList<Checkbox>(find.byType(Checkbox)))
        c.value,
    ];
    // 755: rwx r-x r-x.
    expect(boxes(), [true, true, true, true, false, true, true, false, true]);
    await tester.enterText(find.byKey(const ValueKey('perm.octal')), '600');
    await tester.pump();
    expect(boxes(), [
      true,
      true,
      false,
      false,
      false,
      false,
      false,
      false,
      false,
    ]);
    expect(find.text('rw-------'), findsOneWidget);
    // A box changes the number.
    await tester.tap(find.byType(Checkbox).at(3));
    await tester.pump();
    expect(find.widgetWithText(TextField, '640'), findsOneWidget);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(fs.chmods, [('/srv/run.sh', 0x1a0, false)]);
  });
}

/// The permissions dialog, in the app's theme.
Future<void> _showPermissions(WidgetTester tester, FileSystem fs) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: materialTheme(OwThemes.grafito),
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showPermissions(
              context,
              entry: entry('run.sh', mode: 0x1ed, owner: 'deploy'),
              path: '/srv/run.sh',
              fs: fs,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
