import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection.dart';
import '../core/providers.dart';
import '../src/rust/api/app.dart';
import '../src/rust/api/session.dart';
import '../src/rust/api/tunnels.dart';
import '../tabs/connection_panels.dart';
import '../tabs/prompt_card.dart';
import '../ui/tokens.dart';

/// The saved tunnels and how they stand: asked again when the core says a
/// tunnel changed, and every second while a page shows the connections of
/// remote tunnels (the core has no word for those).
class TunnelBoard extends ChangeNotifier {
  TunnelBoard(this.app) {
    _changes = app.watchTunnels().listen((_) => _soon());
    refresh();
  }

  final OpenWard app;
  List<TunnelView> tunnels = const [];
  StreamSubscription<bool>? _changes;
  Timer? _timer;

  /// A burst of changes (connections coming and going) asks once.
  Timer? _pending;
  int _watchers = 0;
  bool _disposed = false;

  void _soon() {
    _pending ??= Timer(const Duration(milliseconds: 50), () {
      _pending = null;
      refresh();
    });
  }

  /// Asks again now.
  void refresh() {
    if (_disposed) return;
    final next = app.tunnels();
    if (!_same(next, tunnels)) {
      tunnels = next;
      notifyListeners();
    }
    _schedule();
  }

  static bool _same(List<TunnelView> a, List<TunnelView> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Asks every second while `true`, for the connections of remote
  /// tunnels, which come and go without a word (the tunnels page).
  void watch(bool on) {
    _watchers += on ? 1 : -1;
    _schedule();
  }

  void _schedule() {
    final busy =
        _watchers > 0 &&
        tunnels.any(
          (t) =>
              t.state == TunnelStateKind.open &&
              t.spec.kind == TunnelKind.remote,
        );
    if (busy && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    } else if (!busy) {
      _timer?.cancel();
      _timer = null;
    }
  }

  int get open => tunnels.where((t) => t.state == TunnelStateKind.open).length;

  List<TunnelView> ofHost(String hostId) => [
    for (final t in tunnels)
      if (t.spec.hostId == hostId) t,
  ];

  TunnelView? byId(String id) => tunnels.where((t) => t.id == id).firstOrNull;

  void close(String id) {
    app.closeTunnel(id: id);
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    _pending?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

final tunnelBoardProvider = Provider<TunnelBoard>((ref) {
  final board = TunnelBoard(ref.watch(openWardProvider));
  ref.onDispose(board.dispose);
  return board;
});

/// Opening a tunnel: when its host is not connected, the connection's
/// questions (a password, a new host key) show in a dialog.
class _Opening extends ConnectionController {
  _Opening(this.id, {required super.app, required super.label});

  final String id;

  @override
  Stream<SessionEvent> open() => app.openTunnel(id: id);

  @override
  void stop() => app.closeTunnel(id: id);
}

/// Opens tunnel `id`, asking in a dialog whatever its connection needs.
/// The dialog goes on the app's own navigator: the page that opened the
/// tunnel may be gone by the time a question comes.
Future<void> openTunnel(
  BuildContext context,
  WidgetRef ref,
  TunnelView tunnel,
) async {
  final board = ref.read(tunnelBoardProvider);
  final navigator = Navigator.of(context, rootNavigator: true);
  final c = _Opening(
    tunnel.id,
    app: ref.read(openWardProvider),
    label: tunnel.hostLabel,
  );
  // Done when it connected (and listens) or gave up.
  final done = Completer<void>();
  var asking = false;
  void onChange() {
    if (c.phase == Phase.connected || c.phase == Phase.closed) {
      if (!done.isCompleted) done.complete();
    } else if (c.prompts.isNotEmpty && !asking && navigator.mounted) {
      asking = true;
      showDialog<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (context) => _AskDialog(controller: c),
      ).whenComplete(() => asking = false);
    }
  }

  c.addListener(onChange);
  c.start();
  board.refresh();
  await done.future;
  c.removeListener(onChange);
  board.refresh();
  // Let the dialog see the end before the controller goes.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  c.dispose();
}

/// The questions of a tunnel's connection, until it is up or gives up.
class _AskDialog extends StatelessWidget {
  const _AskDialog({required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.phase == Phase.connected || c.phase == Phase.closed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
        }
        final prompt = c.prompts.isEmpty ? null : c.prompts.first;
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: prompt != null
              ? PromptCard(
                  key: ObjectKey(prompt),
                  controller: c,
                  prompt: prompt,
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
                  ),
                  child: ConnectingCard(controller: c),
                ),
        );
      },
    );
  }
}
