import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../sftp/transfers.dart';
import '../src/rust/api/sftp.dart' show TransferState;
import '../terminal/controller.dart';
import '../tunnels/tunnels.dart';
import '../ui/confirm.dart';
import '../ui/environment.dart' show shownEnv;
import 'tabs.dart';

/// Closing asks first only when it would cut off a session that is up on
/// a host of a marked environment (production, say). The rest closes at
/// once and comes back with ⌘⇧T; a browser's transfers go on in the app.

ProviderContainer _app(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false);

/// Those of `sessions` that are up on a marked host, with its mark.
List<(TerminalController, String)> _marked(
  BuildContext context,
  Iterable<TerminalController> sessions,
) {
  final library = _app(context).read(libraryProvider);
  return [
    for (final c in sessions)
      if (c.phase == Phase.connected || c.phase == Phase.reconnecting)
        if (c.hostId case final id?)
          if (library.host(id)?.environment case final env?)
            (c, shownEnv(context.l10n, env).name),
  ];
}

Iterable<TerminalController> _sessionsOf(Iterable<OpenTab> tabs) =>
    tabs.whereType<SessionTab>().expand((t) => t.panes.controllers);

/// Whether to go ahead and close what holds `sessions`.
Future<bool> _confirm(
  BuildContext context,
  List<(TerminalController, String)> sessions,
) {
  if (sessions.isEmpty) return Future.value(true);
  final l = context.l10n;
  final [(first, env), ...] = sessions;
  return confirmAction(
    context,
    title: sessions.length == 1
        ? l.closeMarkedOne(first.label)
        : l.closeMarkedMany(sessions.length),
    body: sessions.length == 1
        ? l.closeMarkedOneBody(env)
        : l.closeMarkedManyBody(
            [for (final (c, env) in sessions) '${c.label} ($env)'].join(', '),
          ),
    action: l.closeAction,
    danger: true,
  );
}

/// Closes the tabs at `indices`, asking first if that cuts off a marked
/// session.
Future<void> closeTabs(BuildContext context, List<int> indices) async {
  final app = _app(context);
  final tabs = app.read(tabsProvider).tabs;
  final closing = [for (final i in indices) tabs[i]];
  if (!await _confirm(context, _marked(context, _sessionsOf(closing)))) {
    return;
  }
  final notifier = app.read(tabsProvider.notifier);
  // By identity: the indices move as tabs go.
  for (final tab in closing) {
    final at = app.read(tabsProvider).tabs.indexOf(tab);
    if (at >= 0) notifier.close(at);
  }
}

/// Closes tab `index`, asking first if that cuts off a marked session.
Future<void> closeTab(BuildContext context, int index) =>
    closeTabs(context, [index]);

/// Closes every tab but `index`, asking first as [closeTabs] does.
Future<void> closeOtherTabs(BuildContext context, int index) {
  final count = _app(context).read(tabsProvider).tabs.length;
  return closeTabs(context, [
    for (var i = 0; i < count; i++)
      if (i != index) i,
  ]);
}

/// Closes one pane of `tab`, asking first if its session is a marked one.
Future<void> closePane(BuildContext context, SessionTab tab, Pane pane) async {
  final app = _app(context);
  final c = pane.controller;
  if (c != null && !await _confirm(context, _marked(context, [c]))) return;
  app.read(tabsProvider.notifier).closePane(tab, pane);
}

/// ⌘W: the active pane when the tab is split, else the tab.
Future<void> closeCurrent(BuildContext context) {
  final state = _app(context).read(tabsProvider);
  final tab = state.current;
  if (tab == null) return Future.value();
  if (tab is SessionTab && tab.panes.isSplit) {
    return closePane(context, tab, tab.panes.active);
  }
  return closeTab(context, state.active);
}

/// Quitting (⌘Q, or closing the window) asks first when it cuts off open
/// sessions, transfers under way or open tunnels. True to quit.
Future<bool> confirmQuit(BuildContext context) {
  final app = _app(context);
  final l = context.l10n;
  final sessions = app
      .read(tabsProvider)
      .sessions
      .where(
        (c) =>
            c.phase == Phase.connected ||
            c.phase == Phase.running ||
            c.phase == Phase.reconnecting,
      )
      .length;
  // Paused ones too: the queue does not outlive the app.
  final transfers = app
      .read(transferQueueProvider)
      .jobs
      .where((j) => j.moving || j.state == TransferState.paused)
      .length;
  final tunnels = app.read(tunnelBoardProvider).open;
  final what = [
    if (sessions > 0) l.quitSessions(sessions),
    if (transfers > 0) l.quitTransfers(transfers),
    if (tunnels > 0) l.quitTunnels(tunnels),
  ];
  if (what.isEmpty) return Future.value(true);
  return confirmAction(
    context,
    title: l.quitTitle,
    body: l.quitBody(what.join(', ')),
    action: l.quit,
    danger: true,
  );
}
