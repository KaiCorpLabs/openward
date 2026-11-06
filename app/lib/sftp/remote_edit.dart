// Remote files opened in an app of this computer: a copy here, followed
// while the SFTP tab is open; each time it is saved it goes back up, and
// if the server's changed meanwhile, the user is asked first.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../src/rust/api/app.dart';
import '../src/rust/api/sftp.dart';
import 'transfers.dart';

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

  /// The folder the copies go to, the user's own, made once.
  Directory? _dir;
  Directory get _folder =>
      _dir ??= Directory.systemTemp.createTempSync('openward-open-');

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

  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
    super.dispose();
  }
}

/// Opens `path` with this computer's app for it.
Future<void> openWithSystem(String path) async {
  if (Platform.isMacOS) {
    await Process.start('open', [path], mode: ProcessStartMode.detached);
  } else if (Platform.isWindows) {
    await Process.start('cmd', [
      '/c',
      'start',
      '',
      path,
    ], mode: ProcessStartMode.detached);
  } else {
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
