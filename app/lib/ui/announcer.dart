import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/tunnels.dart';
import '../tabs/messages.dart';
import '../tabs/tabs.dart';
import '../terminal/controller.dart';
import '../tunnels/tunnels.dart';
import '../tunnels/tunnels_page.dart';

/// Tells screen readers what changes away from the focus: a session that
/// connects, drops or asks something, and a tunnel that opens or fails.
/// The focus stays where it is.
class Announcer extends ConsumerStatefulWidget {
  const Announcer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<Announcer> createState() => _AnnouncerState();
}

class _AnnouncerState extends ConsumerState<Announcer> {
  final Map<TerminalController, (Phase, int)> _sessions = {};
  final Map<String, TunnelStateKind> _tunnels = {};
  late final TunnelBoard _board = ref.read(tunnelBoardProvider);

  @override
  void initState() {
    super.initState();
    for (final t in _board.tunnels) {
      _tunnels[t.id] = t.state;
    }
    _board.addListener(_onTunnels);
  }

  @override
  void dispose() {
    _board.removeListener(_onTunnels);
    for (final c in _sessions.keys) {
      c.removeListener(_onSessions);
    }
    super.dispose();
  }

  void _say(String message) {
    if (!mounted || message.isEmpty) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  /// Follows the sessions that are open now.
  void _track(Iterable<TerminalController> open) {
    final now = open.where((c) => !c.isDisposed).toSet();
    for (final gone in _sessions.keys.where((c) => !now.contains(c)).toList()) {
      gone.removeListener(_onSessions);
      _sessions.remove(gone);
    }
    for (final c in now) {
      if (_sessions.containsKey(c)) continue;
      _sessions[c] = (c.phase, c.prompts.length);
      c.addListener(_onSessions);
    }
  }

  void _onSessions() {
    final l = context.l10n;
    for (final MapEntry(key: c, value: (was, asked))
        in _sessions.entries.toList()) {
      if (c.isDisposed) continue;
      final name = c.displayTitle;
      if (c.phase != was) {
        _say(switch (c.phase) {
          Phase.connected => l.announceConnected(name),
          Phase.reconnecting => l.announceReconnecting(name),
          Phase.closed when c.closed?.failure != null => l.announceFailed(
            name,
            failureText(l, c.closed!.failure!),
          ),
          Phase.closed => l.announceClosed(name),
          _ => '',
        });
      }
      if (c.prompts.length > asked) _say(l.announcePrompt(name));
      _sessions[c] = (c.phase, c.prompts.length);
    }
  }

  void _onTunnels() {
    final l = context.l10n;
    for (final t in _board.tunnels) {
      final was = _tunnels[t.id];
      _tunnels[t.id] = t.state;
      if (was == null || was == t.state) continue;
      _say(switch (t.state) {
        TunnelStateKind.open => l.announceTunnelOpen(t.spec.label, t.port),
        TunnelStateKind.failed when t.error?.kind == TunnelErrorKind.lost =>
          l.announceTunnelLost(t.spec.label),
        TunnelStateKind.failed => l.announceTunnelFailed(
          t.spec.label,
          tunnelErrorText(l, t),
        ),
        _ => '',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _track(ref.watch(tabsProvider).sessions);
    return widget.child;
  }
}
