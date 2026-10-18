import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../src/rust/api/app.dart';
import '../src/rust/api/session.dart';
import 'address.dart';

/// Where a connection stands.
enum Phase { connecting, connected, reconnecting, running, closed }

/// What a connection to a host reports: its route, progress, questions,
/// how it went and whether it is coming back. Terminals and SFTP browsers
/// both have one, and the cards that show it take either.
abstract class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required this.app,
    required this.label,
    this.hostId,
    this.target,
  });

  final OpenWard app;

  /// The saved host, if it is one.
  final String? hostId;

  /// An address that is not saved, if it is one.
  final QuickTarget? target;

  /// The host's label, or the shell's name.
  final String label;

  Phase phase = Phase.connecting;

  /// The hops of the connection, target last.
  List<String> route = const [];
  StageView? stage;
  ConnectedView? connected;
  ClosedView? closed;

  /// While waiting to reconnect: why, and when the next try starts.
  ReconnectingView? reconnecting;
  DateTime? reconnectAt;

  /// It got as far as working at least once: what it shows is worth
  /// keeping on view.
  bool everConnected = false;

  /// The user gave up on the connection.
  bool cancelled = false;

  /// An error before the session could start (a plan that cannot run).
  String? error;

  /// Since when the server has not answered, while it may still come back.
  DateTime? stalledSince;

  /// The last round trip to the server, in ms.
  int? rttMs;

  /// The last round trips, oldest first: one per check (every keepalive,
  /// 10 s by default), [rttKept] at most.
  final List<int> rttHistory = [];

  static const rttKept = 30;

  /// The last round trip to each jump host, in route order; null for one
  /// that did not answer in time. Empty without jump hosts.
  List<int?> hopRttMs = const [];

  /// The usual round trip: the median of [rttHistory], once there are a
  /// few.
  int? get usualRttMs {
    if (rttHistory.length < 5) return null;
    final sorted = [...rttHistory]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// The round trip is well above the usual: three times it, and over
  /// 100 ms, so a distant but steady server or a few ms on a local network
  /// are not marked.
  bool get rttHigh {
    final rtt = rttMs;
    final usual = usualRttMs;
    return rtt != null && usual != null && rtt >= usual * 3 && rtt > 100;
  }

  /// How the shell of a host with a persistent session started.
  PersistentView? persistent;

  /// When the connection that is coming back went down.
  DateTime? _downSince;

  /// While reconnecting: since when it has been down.
  DateTime? get reconnectingSince => _downSince;

  /// The last time it came back, and after how long away.
  DateTime? backAt;
  Duration? lastOutage;

  /// Questions from the session, oldest first.
  final Queue<PromptView> prompts = Queue();

  StreamSubscription<SessionEvent>? _events;
  bool _disposed = false;

  /// A shell on this machine: neither a saved host nor an address.
  bool get isLocal => hostId == null && target == null;

  bool get isDisposed => _disposed;

  /// Starts the session in Rust: its events.
  @protected
  Stream<SessionEvent> open();

  /// Ends the session in Rust.
  @protected
  void stop();

  /// Connects (or reconnects, keeping what is on view).
  void start() {
    phase = everConnected && !isLocal ? Phase.reconnecting : Phase.connecting;
    stage = null;
    connected = null;
    closed = null;
    error = null;
    reconnectAt = null;
    cancelled = false;
    prompts.clear();
    _events?.cancel();
    _events = open().listen(
      onEvent,
      onError: (Object e) {
        phase = Phase.closed;
        error = '$e';
        notify();
      },
    );
    notify();
  }

  @protected
  @mustCallSuper
  void onEvent(SessionEvent e) {
    switch (e.kind) {
      case SessionEventKind.route:
        route = e.route;
      case SessionEventKind.stage:
        stage = e.stage;
        reconnectAt = null;
      case SessionEventKind.prompt:
        prompts.add(e.prompt!);
      case SessionEventKind.connected:
        phase = Phase.connected;
        connected = e.connected;
        stage = null;
        reconnecting = null;
        reconnectAt = null;
        everConnected = true;
        stalledSince = null;
        final down = _downSince;
        if (down != null) {
          backAt = DateTime.now();
          lastOutage = backAt!.difference(down);
          _downSince = null;
        }
      case SessionEventKind.health:
        final h = e.health!;
        if (h.stalled) {
          stalledSince ??= DateTime.now().subtract(
            Duration(milliseconds: h.silentMs.toInt()),
          );
        } else {
          stalledSince = null;
          if (h.rttMs case final rtt?) {
            rttMs = rtt;
            rttHistory.add(rtt);
            if (rttHistory.length > rttKept) rttHistory.removeAt(0);
          }
        }
      case SessionEventKind.hops:
        hopRttMs = e.hopRttMs;
      case SessionEventKind.persistent:
        persistent = e.persistent;
      case SessionEventKind.reconnecting:
        final r = e.reconnecting!;
        // From when it stopped answering, if it did before it was lost.
        _downSince ??= stalledSince ?? DateTime.now();
        stalledSince = null;
        hopRttMs = const [];
        phase = Phase.reconnecting;
        reconnecting = r;
        stage = null;
        reconnectAt = DateTime.now().add(
          Duration(milliseconds: r.delayMs.toInt()),
        );
      case SessionEventKind.started:
        phase = Phase.running;
        everConnected = true;
      case SessionEventKind.closed:
        phase = Phase.closed;
        closed = e.closed;
        stalledSince = null;
        hopRttMs = const [];
        _downSince = null;
        stage = null;
        reconnecting = null;
        reconnectAt = null;
        // Questions of a session that is gone cannot be answered.
        prompts.clear();
    }
    notify();
  }

  /// Gives up on the connection (or its reconnection).
  void cancel() {
    _events?.cancel();
    stop();
    phase = Phase.closed;
    cancelled = true;
    stalledSince = null;
    _downSince = null;
    stage = null;
    reconnecting = null;
    reconnectAt = null;
    prompts.clear();
    notify();
  }

  void answer(PromptView prompt, PromptAnswer answer) {
    prompts.remove(prompt);
    app.answer(promptId: prompt.id, answer: answer);
    notify();
  }

  void notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    super.dispose();
  }
}
