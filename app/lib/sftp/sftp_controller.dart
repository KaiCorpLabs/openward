import '../core/connection.dart';
import '../src/rust/api/session.dart';
import '../src/rust/api/sftp.dart';
import 'files.dart';
import 'remote_edit.dart';
import 'transfers.dart';

export 'files.dart';

/// What to do with each conflicting source, by its path; a source left out
/// is not copied. `null` cancels the whole copy.
typedef ConflictAnswer = Map<String, ConflictChoice>?;

/// One SFTP tab: the connection, this machine's side and the server's.
class SftpController extends ConnectionController {
  SftpController({
    required super.app,
    required super.label,
    required this.queue,
    super.hostId,
    super.target,
  }) : browser = app.sftp() {
    local = FilePane(Side.local, const LocalFileSystem());
    remote = FilePane(Side.remote, RemoteFileSystem(browser));
    queue.addListener(_onQueue);
    local.goHome();
  }

  final SftpBrowser browser;
  final TransferQueue queue;
  late final FilePane local;
  late final FilePane remote;

  /// Remote files opened in an app here, uploaded as they are saved.
  late final RemoteEdits edits = RemoteEdits(
    app: app,
    browser: browser,
    queue: queue,
  );

  /// The side with the keyboard.
  Side active = Side.local;

  /// Copies this tab queued, and the side and folder they go to, to show
  /// them there when they finish.
  final Map<BigInt, (Side, String)> _mine = {};

  /// Those of [_mine] that stopped on the way, and were shown so.
  final _stopped = <BigInt>{};

  FilePane pane(Side side) => side == Side.local ? local : remote;
  FilePane get activePane => pane(active);
  FilePane get otherPane =>
      pane(active == Side.local ? Side.remote : Side.local);

  void focus(Side side) {
    if (active == side) return;
    active = side;
    notify();
  }

  @override
  Stream<SessionEvent> open() {
    final hostId = this.hostId;
    final target = this.target;
    return hostId != null
        ? app.connectSftp(browser: browser, hostId: hostId)
        : app.connectSftpAddress(
            browser: browser,
            address: target!.address,
            user: target.user,
            port: target.port,
          );
  }

  @override
  void stop() => browser.close();

  @override
  void onEvent(SessionEvent e) {
    super.onEvent(e);
    if (e.kind == SessionEventKind.connected) {
      // The first time it starts at home; after a reconnection, where it was.
      remote.path.isEmpty ? remote.goHome() : remote.refresh();
    }
  }

  /// Copies `sources` (paths on the `from` side) into `destDir` on the
  /// other. Those that already exist there are asked about with `ask`.
  /// Returns how many copies were queued.
  Future<int> copy(
    Side from,
    List<String> sources,
    String destDir, {
    required Future<ConflictAnswer> Function(List<ConflictView>) ask,
  }) async {
    if (sources.isEmpty) return 0;
    final direction = from == Side.local
        ? TransferDirection.upload
        : TransferDirection.download;
    final conflicts = await browser.conflicts(
      direction: direction,
      sources: sources,
      destDir: destDir,
    );
    var choices = <String, ConflictChoice>{};
    if (conflicts.isNotEmpty) {
      final answer = await ask(conflicts);
      if (answer == null) return 0;
      choices = answer;
    }
    final asked = {for (final c in conflicts) c.source};
    var queued = 0;
    for (final s in sources) {
      final choice = choices[s];
      if (asked.contains(s) && choice == null) continue;
      final id = app.transfer(
        browser: browser,
        direction: direction,
        source: s,
        destDir: destDir,
        onConflict: choice ?? ConflictChoice.replace,
      );
      _mine[id] = (from == Side.local ? Side.remote : Side.local, destDir);
      queued++;
    }
    queue.poke();
    return queued;
  }

  /// Shows what copies brought, if their folder is on view: when one
  /// ends, and when one stops on the way (paused, failed) with what it
  /// copied so far. A stopped one is still followed: it may go on.
  void _onQueue() {
    if (_mine.isEmpty) return;
    final refresh = <Side>{};
    for (final j in queue.jobs) {
      final mine = _mine[j.id];
      if (mine == null) continue;
      if (j.finished) {
        _mine.remove(j.id);
        _stopped.remove(j.id);
      } else if (j.moving) {
        _stopped.remove(j.id);
        continue;
      } else if (!_stopped.add(j.id)) {
        // Stopped before, and shown then.
        continue;
      }
      final (side, dir) = mine;
      if (pane(side).path == dir) refresh.add(side);
    }
    for (final side in refresh) {
      pane(side).refresh();
    }
  }

  @override
  void dispose() {
    queue.removeListener(_onQueue);
    edits.dispose();
    browser.close();
    browser.dispose();
    local.dispose();
    remote.dispose();
    super.dispose();
  }
}
