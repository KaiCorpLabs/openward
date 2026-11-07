// Remote files opened in an app of this computer: a copy here, followed
// while the SFTP tab is open; each time it is saved it goes back up, and
// if the server's changed meanwhile, the user is asked first.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../src/rust/api/app.dart';
import '../src/rust/api/sftp.dart';
import 'open_safety.dart';
import 'transfers.dart';

/// How the folders of the copies start, in the system's temporary folder.
const openCopiesPrefix = 'openward-open-';

/// Held while its folder is in use: a later start leaves it alone.
const _lockName = '.openward-lock';

/// The folders this run made: its own lock does not keep them from it.
final _ours = <String>{};

/// One remote file with its copy here.
class RemoteEdit {
  RemoteEdit({
    required this.remote,
    required this.local,
    required this.remoteModified,
    required this.seen,
  });

  /// Its path on the server.
  final String remote;

  /// Its copy on this computer.
  final String local;

  /// The server's modification time when it was last read or written
  /// (seconds since the epoch).
  int? remoteModified;

  /// The copy as last seen: its time and size. A save changes them.
  (DateTime, int) seen;

  /// When it last went up; null if not yet.
  DateTime? uploaded;

  /// Why the last upload failed; null if it did not.
  String? failure;
  bool busy = false;

  String get name => remote.split('/').last;
}

/// What to do when the server's file changed since it was opened: true
/// uploads over it.
typedef ChangedThere = Future<bool> Function(RemoteEdit edit);

/// The files of one SFTP tab opened here.
class RemoteEdits extends ChangeNotifier {
  RemoteEdits({required this.app, required this.browser, required this.queue});

  final OpenWard app;
  final SftpBrowser browser;
  final TransferQueue queue;

  /// Asked when the server's copy changed: set by the view.
  ChangedThere? onChangedThere;

  final List<RemoteEdit> edits = [];
  Timer? _watch;
  bool _disposed = false;

  /// The folder the copies go to, made once, for this user alone: the
  /// files may hold secrets. It goes with the tab; if the app ends first,
  /// the next start takes it ([cleanStaleOpenCopies]).
  Directory? _dir;
  RandomAccessFile? _lock;
  Directory get _folder {
    final made = _dir;
    if (made != null) return made;
    final dir = Directory.systemTemp.createTempSync(openCopiesPrefix);
    if (!Platform.isWindows) Process.runSync('chmod', ['700', dir.path]);
    _ours.add(dir.path);
    _lock = File('${dir.path}/$_lockName').openSync(mode: FileMode.write)
      ..lockSync();
    return _dir = dir;
  }

  /// Brings `remote` here and calls `open` with its copy; from then on,
  /// each save goes up. One open already is opened again, not copied.
  Future<void> open(
    String remote,
    FileEntry entry,
    Future<void> Function(String local) opener,
  ) async {
    final had = edits.where((e) => e.remote == remote).firstOrNull;
    if (had != null) return opener(had.local);
    // A folder of its own: two files of the same name do not meet.
    final dir = Directory(
      '${_folder.path}/${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    await _transfer(TransferDirection.download, remote, dir.path);
    final local = '${dir.path}/${entry.name}';
    await markFromOutside(local);
    final file = File(local);
    final edit = RemoteEdit(
      remote: remote,
      local: local,
      remoteModified: entry.modified,
      seen: (file.lastModifiedSync(), file.lengthSync()),
    );
    edits.add(edit);
    notifyListeners();
    _watch ??= Timer.periodic(const Duration(seconds: 1), (_) => _check());
    await opener(local);
  }

  /// Stops following `edit`: its saves stay here.
  void stop(RemoteEdit edit) {
    edits.remove(edit);
    if (edits.isEmpty) {
      _watch?.cancel();
      _watch = null;
    }
    notifyListeners();
  }

  /// Uploads the copies saved since they were last seen.
  Future<void> _check() async {
    for (final e in [...edits]) {
      if (e.busy || _disposed) continue;
      final file = File(e.local);
      if (!file.existsSync()) continue;
      final now = (file.lastModifiedSync(), file.lengthSync());
      if (now == e.seen) continue;
      e.busy = true;
      try {
        await _upload(e, now);
      } finally {
        e.busy = false;
      }
    }
  }

  Future<void> _upload(RemoteEdit e, (DateTime, int) now) async {
    try {
      final there = await browser.stat(path: e.remote);
      final changed =
          there != null &&
          e.remoteModified != null &&
          there.modified != e.remoteModified;
      if (changed && !(await onChangedThere?.call(e) ?? false)) {
        // Kept here; asked again at the next save.
        e.seen = now;
        e.remoteModified = there.modified;
        return;
      }
      final dir = e.remote.contains('/')
          ? e.remote.substring(0, e.remote.lastIndexOf('/'))
          : '.';
      await _transfer(
        TransferDirection.upload,
        e.local,
        dir.isEmpty ? '/' : dir,
      );
      e.seen = now;
      e.remoteModified = (await browser.stat(path: e.remote))?.modified;
      e.uploaded = DateTime.now();
      e.failure = null;
    } on Object catch (error) {
      e.failure = '$error';
      e.seen = now;
    }
    if (!_disposed) notifyListeners();
  }

  /// Queues one copy and waits for it to end.
  Future<void> _transfer(
    TransferDirection direction,
    String source,
    String destDir,
  ) async {
    final id = app.transfer(
      browser: browser,
      direction: direction,
      source: source,
      destDir: destDir,
      onConflict: ConflictChoice.replace,
    );
    queue.poke();
    while (!_disposed) {
      final job = app.transfers().where((j) => j.id == id).firstOrNull;
      switch (job?.state) {
        case TransferState.done:
          return;
        case TransferState.failed || TransferState.cancelled || null:
          throw StateError(job?.error?.message ?? 'the copy stopped');
        default:
          await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// The tab closes: nothing goes up any more, and the copies go.
  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
    final dir = _dir;
    if (dir != null) {
      _lock?.closeSync();
      _ours.remove(dir.path);
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Open in a program that holds it (Windows): the next start's.
      }
    }
    super.dispose();
  }
}

/// Deletes the copies an earlier run left in `temp` (the system's
/// temporary folder): those whose lock is free, as the run that held it
/// ended however it ended; and those of a version before the lock, a day
/// on. Another OpenWard that is open keeps its own. Only folders: a link
/// of that name is not followed.
Future<void> cleanStaleOpenCopies({Directory? temp, DateTime? now}) async {
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 1));
  try {
    await for (final e in (temp ?? Directory.systemTemp).list(
      followLinks: false,
    )) {
      final name = e.path.substring(
        e.path.lastIndexOf(Platform.pathSeparator) + 1,
      );
      if (e is! Directory || !name.startsWith(openCopiesPrefix)) continue;
      if (_ours.contains(e.path)) continue;
      try {
        if (await _left(e, cutoff)) await e.delete(recursive: true);
      } on FileSystemException {
        // Someone else's, or in use: it stays.
      }
    }
  } on FileSystemException {
    // No temporary folder to look in.
  }
}

/// Whether `dir`'s run is over.
Future<bool> _left(Directory dir, DateTime cutoff) async {
  final stat = await dir.stat();
  // Ours are 0700; one of another user's would not open anyway.
  if (!Platform.isWindows && stat.mode & 0x1ff != 0x1c0) return false;
  final lock = File('${dir.path}/$_lockName');
  if (!await lock.exists()) return stat.modified.isBefore(cutoff);
  final held = await lock.open(mode: FileMode.append);
  try {
    await held.lock();
    return true;
  } on FileSystemException {
    return false;
  } finally {
    await held.close();
  }
}

/// Opens `path` with this computer's app for it. `os` is
/// [Platform.operatingSystem]'s name, to try another's way.
Future<void> openWithSystem(String path, {String? os}) async {
  switch (os ?? Platform.operatingSystem) {
    case 'macos':
      await Process.start('open', [path], mode: ProcessStartMode.detached);
    case 'windows':
      // ShellExecute with the path as the file to open: no `cmd` reads
      // the name, which the server chose (`x&calc` ran `calc`). The plain
      // path, not a file: URL: nothing to encode and decode on the way.
      if (!await launchUrlString(path)) await openWithChooser(path);
    default:
      await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
  }
}

/// Opens `path` with `program`: an app's name or bundle on macOS
/// (`TextEdit`, `/Applications/Visual Studio Code.app`), a command
/// elsewhere (`code`, `gedit`).
Future<void> openWithProgram(String path, String program) async {
  final p = program.trim();
  if (Platform.isMacOS && !p.startsWith('/usr') && !p.contains('/bin/')) {
    await Process.start('open', [
      '-a',
      p,
      path,
    ], mode: ProcessStartMode.detached);
    return;
  }
  // `code --wait`: the command's own words, then the file.
  final words = p.split(RegExp(r'\s+'));
  await Process.start(words.first, [
    ...words.skip(1),
    path,
  ], mode: ProcessStartMode.detached);
}

/// Windows' own «Open with» dialog for `path`.
Future<void> openWithChooser(String path) => Process.start('rundll32.exe', [
  'shell32.dll,OpenAs_RunDLL',
  path,
], mode: ProcessStartMode.detached);
