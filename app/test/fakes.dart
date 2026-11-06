// A core that is not there: the Dart that drives it (tabs, connections,
// the transfer queue, workspaces) tested on its own, without Rust. Only what
// those tests call is here; anything else fails loudly, as a Fake does.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/src/rust/api/sftp.dart';
import 'package:openward/src/rust/api/snippets.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/api/workspaces.dart';

class FakeSession extends Fake implements TerminalSession {
  final notes = <String>[];
  bool closed = false;
  bool _disposed = false;
  final _wakes = StreamController<bool>.broadcast();

  @override
  Stream<bool> watch() => _wakes.stream;

  @override
  void note({required String text}) => notes.add(text);

  /// No session log is kept.
  @override
  LogStateView? logState() => null;

  @override
  void close() => closed = true;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_wakes.close());
  }

  @override
  bool get isDisposed => _disposed;
}

class FakeOpenWard extends Fake implements OpenWard {
  List<HostView> hostList = [];
  List<GroupView> groupList = [];
  List<TransferView> transferList = [];
  List<WorkspaceView> workspaceList = [];
  List<SnippetView> snippetList = [];

  /// Each session started, and where its events come from.
  final sessions = <FakeSession>[];
  final events = <FakeSession, StreamController<SessionEvent>>{};

  /// What was asked of the core, in order: `answer 7`, `pause 3`…
  final calls = <String>[];

  /// The events of the last session started.
  StreamController<SessionEvent> get lastEvents => events[sessions.last]!;

  @override
  List<HostView> hosts() => hostList;

  @override
  List<GroupView> groups() => groupList;

  @override
  List<WorkspaceView> workspaces() => workspaceList;

  @override
  List<SnippetView> snippets() => snippetList;

  @override
  TerminalSession terminal({
    required int cols,
    required int rows,
    required int scrollback,
  }) {
    final s = FakeSession();
    sessions.add(s);
    return s;
  }

  Stream<SessionEvent> _events(TerminalSession session, String call) {
    calls.add(call);
    final c = StreamController<SessionEvent>();
    events[session as FakeSession] = c;
    return c.stream;
  }

  @override
  Stream<SessionEvent> openLocal({required TerminalSession session}) =>
      _events(session, 'local');

  @override
  Stream<SessionEvent> connect({
    required TerminalSession session,
    required String hostId,
  }) => _events(session, 'connect $hostId');

  @override
  Stream<SessionEvent> connectAddress({
    required TerminalSession session,
    required String address,
    String? user,
    int? port,
    required ProtocolKind protocol,
  }) => _events(
    session,
    protocol == ProtocolKind.ssh
        ? 'connect $address'
        : 'connect ${protocol.name} $address',
  );

  /// What [serialPorts] finds.
  List<SerialPortView> ports = const [];

  @override
  Future<List<SerialPortView>> serialPorts() async => ports;

  @override
  Stream<SessionEvent> openSerial({
    required TerminalSession session,
    required String path,
    required SerialLineSpec line,
  }) => _events(session, 'serial $path ${line.baud} ${line.dataBits}');

  @override
  bool answer({required BigInt promptId, required PromptAnswer answer}) {
    calls.add('answer $promptId');
    return true;
  }

  @override
  List<TransferView> transfers() => transferList;

  @override
  void pauseTransfer({required BigInt id}) => calls.add('pause $id');

  @override
  void resumeTransfer({required BigInt id}) => calls.add('resume $id');

  @override
  void cancelTransfer({required BigInt id}) => calls.add('cancel $id');

  @override
  void removeTransfer({required BigInt id}) => calls.add('remove $id');

  @override
  void pauseTransfers() => calls.add('pause all');

  @override
  void clearFinishedTransfers() => calls.add('clear finished');
}

/// A container with [app] for the core and its files in a folder of its
/// own, removed after the test.
ProviderContainer fakeContainer(FakeOpenWard app) {
  final dir = Directory.systemTemp.createTempSync('openward-test-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final container = ProviderContainer(
    overrides: [
      openWardProvider.overrideWithValue(app),
      settingsFileProvider.overrideWithValue(File('${dir.path}/settings.json')),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

SessionEvent event(
  SessionEventKind kind, {
  List<String> route = const [],
  StageView? stage,
  PromptView? prompt,
  ConnectedView? connected,
  ReconnectingView? reconnecting,
  HealthView? health,
  ClosedView? closed,
  List<String> unknownSystems = const [],
}) => SessionEvent(
  kind: kind,
  route: route,
  stage: stage,
  prompt: prompt,
  connected: connected,
  reconnecting: reconnecting,
  health: health,
  hopRttMs: const [],
  closed: closed,
  unknownSystems: unknownSystems,
);
