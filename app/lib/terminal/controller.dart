import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/address.dart';
import '../src/rust/api/app.dart';
import '../src/rust/api/session.dart';
import 'frame.dart';
import 'palette.dart';
import 'renderer.dart';

/// Where a tab's session stands.
enum Phase { connecting, connected, reconnecting, running, closed }

/// One terminal tab: the Rust session, its renderer and what the session
/// reported. Lives as long as the tab, visible or not.
class TerminalController extends ChangeNotifier {
  TerminalController({
    required this.app,
    required this.label,
    this.hostId,
    this.target,
    int scrollback = 0,
  }) : session = app.terminal(cols: 80, rows: 24, scrollback: scrollback);

  final OpenWard app;

  /// The saved host, if it is one.
  final String? hostId;

  /// An address that is not saved, if it is one.
  final QuickTarget? target;

  /// The host's label, or the shell's name.
  final String label;

  /// Set by the user (rename); wins over [label] and the program's title.
  String? customTitle;

  final TerminalSession session;
  StreamSubscription<SessionEvent>? _events;

  Phase phase = Phase.connecting;

  /// The hops of the connection, target last.
  List<String> route = const [];
  StageView? stage;
  ConnectedView? connected;
  ClosedView? closed;

  /// While waiting to reconnect: why, and when the next try starts.
  ReconnectingView? reconnecting;
  DateTime? reconnectAt;

  /// The session got as far as a shell at least once: the screen has
  /// something worth keeping on view.
  bool everConnected = false;

  /// The user gave up on the connection.
  bool cancelled = false;

  /// An error before the session could start (a plan that cannot run).
  String? error;

  /// Questions from the session, oldest first.
  final Queue<PromptView> prompts = Queue();

  // From the last frame.
  String title = '';
  bool mouseTracking = false;
  bool bracketedPaste = false;
  bool reportAllKeys = false;

  TerminalRenderer? _renderer;

  /// The renderer in use, if the tab has been shown.
  TerminalRenderer? get currentRenderer => _renderer;
  Timer? _background;
  bool _disposed = false;

  /// A shell on this machine: neither a saved host nor an address.
  bool get isLocal => hostId == null && target == null;

  /// What the tab shows.
  String get displayTitle {
    final custom = customTitle;
    if (custom != null && custom.isNotEmpty) return custom;
    return isLocal && title.isNotEmpty ? title : label;
  }

  /// Connects (or reconnects, keeping the screen), or starts the shell.
  void start() {
    phase = everConnected && !isLocal ? Phase.reconnecting : Phase.connecting;
    stage = null;
    connected = null;
    closed = null;
    error = null;
    reconnectAt = null;
    cancelled = false;
    prompts.clear();
    final hostId = this.hostId;
    final target = this.target;
    final events = hostId != null
        ? app.connect(session: session, hostId: hostId)
        : target != null
        ? app.connectAddress(
            session: session,
            address: target.address,
            user: target.user,
            port: target.port,
          )
        : app.openLocal(session: session);
    _events?.cancel();
    _events = events.listen(
      _onEvent,
      onError: (Object e) {
        phase = Phase.closed;
        error = '$e';
        _notify();
      },
    );
    _notify();
  }

  void _onEvent(SessionEvent e) {
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
      case SessionEventKind.reconnecting:
        final r = e.reconnecting!;
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
        stage = null;
        reconnecting = null;
        reconnectAt = null;
        // Questions of a session that is gone cannot be answered.
        prompts.clear();
    }
    _notify();
  }

  /// Gives up on the connection (or its reconnection); the screen stays.
  void cancel() {
    _events?.cancel();
    session.close();
    phase = Phase.closed;
    cancelled = true;
    stage = null;
    reconnecting = null;
    reconnectAt = null;
    prompts.clear();
    _notify();
  }

  void answer(PromptView prompt, PromptAnswer answer) {
    prompts.remove(prompt);
    app.answer(promptId: prompt.id, answer: answer);
    _notify();
  }

  /// The renderer for this pixel density, font size and palette, made anew
  /// (and the screen asked for again) when any of them changes.
  TerminalRenderer renderer(
    double devicePixelRatio, {
    required double fontSize,
    required TermPalette palette,
  }) {
    final current = _renderer;
    if (current != null &&
        current.devicePixelRatio == devicePixelRatio &&
        current.metrics.fontSize == fontSize &&
        identical(current.palette, palette)) {
      return current;
    }
    if (current == null || !identical(current.palette, palette)) {
      session.setTheme(
        dark: palette.dark,
        foreground: TermPalette.rgb(palette.foreground),
        background: TermPalette.rgb(palette.background),
      );
    }
    current?.dispose();
    final metrics = CellMetrics.measure(
      fontSize: fontSize,
      devicePixelRatio: devicePixelRatio,
    );
    session.setCellPixels(width: metrics.width, height: metrics.height);
    session.redraw();
    return _renderer = TerminalRenderer(
      metrics: metrics,
      palette: palette,
      devicePixelRatio: devicePixelRatio,
    );
  }

  /// Applies what changed since the last poll. Returns true if anything did.
  bool poll() {
    final renderer = _renderer;
    if (renderer == null || _disposed) return false;
    final f = session.poll();
    if (f == null) return false;
    renderer.apply(decodeFrame(f.frame));
    renderer.setSelection([
      for (final r in f.selection) (row: r.row, start: r.start, end: r.end),
    ]);
    if (f.title != title ||
        f.mouseTracking != mouseTracking ||
        f.bracketedPaste != bracketedPaste ||
        f.reportAllKeys != reportAllKeys) {
      title = f.title;
      mouseTracking = f.mouseTracking;
      bracketedPaste = f.bracketedPaste;
      reportAllKeys = f.reportAllKeys;
      _notify();
    }
    return true;
  }

  /// A visible tab is polled every frame by its pane; a hidden one a few
  /// times a second, so its title stays current and damage does not pile up.
  set visible(bool visible) {
    _background?.cancel();
    _background = visible || _disposed
        ? null
        : Timer.periodic(const Duration(milliseconds: 250), (_) => poll());
  }

  bool get isDisposed => _disposed;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _background?.cancel();
    session.close();
    session.dispose();
    _renderer?.dispose();
    super.dispose();
  }
}
