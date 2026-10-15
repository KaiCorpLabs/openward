import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../src/rust/api/sftp.dart';

/// The two sides of the browser.
enum Side { local, remote }

/// One side's file operations. Errors are [FileError]s.
abstract class FileSystem {
  /// Path rules: this machine's, or POSIX on the server.
  p.Context get paths;

  /// Where browsing starts.
  Future<String> home();
  Future<List<FileEntry>> list(String dir);
  Future<void> mkdir(String path);

  /// Never over something that exists.
  Future<void> rename(String from, String to);
  Future<void> remove(List<String> paths);

  /// Returns how many entries changed.
  Future<int> chmod(String path, int mode, {required bool recursive});
}

class LocalFileSystem implements FileSystem {
  const LocalFileSystem();

  @override
  p.Context get paths => p.context;

  @override
  Future<String> home() async => localHome();

  @override
  Future<List<FileEntry>> list(String dir) => localList(path: dir);

  @override
  Future<void> mkdir(String path) => localMkdir(path: path);

  @override
  Future<void> rename(String from, String to) =>
      localRename(from: from, to: to);

  @override
  Future<void> remove(List<String> paths) => localRemove(paths: paths);

  @override
  Future<int> chmod(String path, int mode, {required bool recursive}) async =>
      (await localChmod(path: path, mode: mode, recursive: recursive)).toInt();
}

class RemoteFileSystem implements FileSystem {
  const RemoteFileSystem(this.browser);

  final SftpBrowser browser;

  @override
  p.Context get paths => p.posix;

  @override
  Future<String> home() => browser.home();

  @override
  Future<List<FileEntry>> list(String dir) => browser.list(path: dir);

  @override
  Future<void> mkdir(String path) => browser.mkdir(path: path);

  @override
  Future<void> rename(String from, String to) =>
      browser.rename(from: from, to: to);

  @override
  Future<void> remove(List<String> paths) => browser.remove(paths: paths);

  @override
  Future<int> chmod(String path, int mode, {required bool recursive}) async =>
      (await browser.chmod(
        path: path,
        mode: mode,
        recursive: recursive,
      )).toInt();
}

enum SortBy { name, size, modified }

extension FileEntryX on FileEntry {
  /// Opens like a folder: a directory or a link to one.
  bool get isDir => kind == FileKind.dir || linkDir;

  bool get hidden => name.startsWith('.');
}

/// One side of the browser: where it is, what is there, what is selected
/// and how it is shown.
class FilePane extends ChangeNotifier {
  FilePane(this.side, this.fs);

  final Side side;
  final FileSystem fs;

  /// The folder shown; empty until the first listing.
  String path = '';

  /// The home folder, shown as `~`.
  String? homePath;

  List<FileEntry> entries = const [];
  bool loading = false;

  /// Why the folder could not be listed.
  FileError? error;

  String filter = '';
  bool showHidden = false;
  SortBy sortBy = SortBy.name;
  bool ascending = true;

  final Set<String> selected = {};

  /// The row with the keyboard.
  String? cursor;
  String? _anchor;
  bool _disposed = false;

  p.Context get paths => fs.paths;

  /// What shows, after the filter and the hidden files, sorted with folders
  /// first.
  List<FileEntry> get visible {
    final f = filter.toLowerCase();
    final out = [
      for (final e in entries)
        if ((showHidden || !e.hidden) &&
            (f.isEmpty || e.name.toLowerCase().contains(f)))
          e,
    ];
    int by(FileEntry a, FileEntry b) => switch (sortBy) {
      SortBy.name => compareNames(a.name, b.name),
      SortBy.size => a.size.compareTo(b.size),
      SortBy.modified => (a.modified ?? 0).compareTo(b.modified ?? 0),
    };
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final c = by(a, b);
      final r = ascending ? c : -c;
      return r != 0 ? r : compareNames(a.name, b.name);
    });
    return out;
  }

  List<FileEntry> get selection => [
    for (final e in visible)
      if (selected.contains(e.name)) e,
  ];

  int get selectedBytes => selection
      .where((e) => !e.isDir)
      .fold(0, (sum, e) => sum + e.size.toInt());

  String pathOf(String name) => paths.join(path, name);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> goHome() async {
    try {
      homePath = await fs.home();
    } on FileError catch (e) {
      error = e;
      _notify();
      return;
    }
    await open(homePath!);
  }

  /// Lists `dir` and shows it. A folder that cannot be listed leaves the
  /// one shown, with the error.
  Future<void> open(String dir, {bool keepSelection = false}) async {
    loading = true;
    _notify();
    try {
      final list = await fs.list(dir);
      final same = dir == path;
      path = dir;
      entries = list;
      error = null;
      if (!same || !keepSelection) {
        selected.clear();
        cursor = null;
        _anchor = null;
        filter = '';
      } else {
        final names = {for (final e in list) e.name};
        selected.retainWhere(names.contains);
        if (cursor != null && !names.contains(cursor)) cursor = null;
      }
    } on FileError catch (e) {
      error = e;
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> refresh() =>
      path.isEmpty ? Future.value() : open(path, keepSelection: true);

  /// The folder above; selects the one it came from.
  Future<void> up() async {
    final from = path;
    final parent = paths.dirname(path);
    if (parent == path) return;
    await open(parent);
    final name = paths.basename(from);
    if (entries.any((e) => e.name == name)) {
      selected
        ..clear()
        ..add(name);
      cursor = _anchor = name;
      _notify();
    }
  }

  Future<void> enter(FileEntry e) => open(pathOf(e.name));

  /// A click: just this row, or toggled (⌘), or a range from the last (⇧).
  void click(String name, {bool toggle = false, bool range = false}) {
    final names = [for (final e in visible) e.name];
    final anchor = _anchor;
    if (range && anchor != null && names.contains(anchor)) {
      final a = names.indexOf(anchor), b = names.indexOf(name);
      selected
        ..clear()
        ..addAll(names.sublist(a < b ? a : b, (a < b ? b : a) + 1));
    } else if (toggle) {
      if (!selected.remove(name)) selected.add(name);
      _anchor = name;
    } else {
      selected
        ..clear()
        ..add(name);
      _anchor = name;
    }
    cursor = name;
    _notify();
  }

  /// Arrow keys: moves the keyboard row, extending the selection with ⇧.
  void moveCursor(int delta, {bool extend = false}) {
    final names = [for (final e in visible) e.name];
    if (names.isEmpty) return;
    final at = cursor == null ? -1 : names.indexOf(cursor!);
    final next = at < 0
        ? (delta > 0 ? 0 : names.length - 1)
        : (at + delta).clamp(0, names.length - 1);
    click(names[next], range: extend);
    if (!extend) _anchor = names[next];
  }

  void selectAll() {
    selected
      ..clear()
      ..addAll(visible.map((e) => e.name));
    _notify();
  }

  void setFilter(String text) {
    filter = text;
    _notify();
  }

  void toggleHidden() {
    showHidden = !showHidden;
    _notify();
  }

  void sort(SortBy by) {
    if (sortBy == by) {
      ascending = !ascending;
    } else {
      sortBy = by;
      ascending = by == SortBy.name;
    }
    _notify();
  }

  /// The path in parts for the breadcrumb: (label, path), from the root or
  /// from `~` inside the home folder.
  List<(String, String)> crumbs() {
    if (path.isEmpty) return const [];
    final home = homePath;
    final out = <(String, String)>[];
    var parts = paths.split(path);
    var start = 0;
    if (home != null && (path == home || paths.isWithin(home, path))) {
      out.add(('~', home));
      start = paths.split(home).length;
    }
    for (var i = start; i < parts.length; i++) {
      out.add((parts[i], paths.joinAll(parts.sublist(0, i + 1))));
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Names as people sort them: case aside, and numbers by value
/// (`file2` before `file10`).
int compareNames(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).toList();
  final y = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final sa = x[i][0]!, sb = y[i][0]!;
    final na = int.tryParse(sa), nb = int.tryParse(sb);
    final c = na != null && nb != null ? na.compareTo(nb) : sa.compareTo(sb);
    if (c != 0) return c;
  }
  final c = x.length.compareTo(y.length);
  return c != 0 ? c : a.compareTo(b);
}
