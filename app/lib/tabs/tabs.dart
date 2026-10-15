import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../sftp/sftp_controller.dart';
import '../sftp/transfers.dart';
import '../src/rust/api/vault.dart';
import '../terminal/controller.dart';
import 'panes.dart';

export 'panes.dart' show Pane, PaneNode, PaneSplit, Panes;

/// What a tab holds: terminal sessions in panes, or one of the app's
/// pages. Pages open once; asking for one again brings its tab to the
/// front.
sealed class OpenTab {
  const OpenTab();
}

final class SessionTab extends OpenTab {
  SessionTab(TerminalController first) : panes = Panes(first);

  final Panes panes;

  /// The active pane's session; null while that pane asks what to open.
  TerminalController? get controller => panes.active.controller;
}

/// An SFTP browser for a host.
final class SftpTab extends OpenTab {
  SftpTab(this.controller);

  final SftpController controller;
}

enum PageKind { settings }

final class PageTab extends OpenTab {
  const PageTab(this.page);

  final PageKind page;
}

/// The open tabs and which one is in front.
class TabsState {
  const TabsState(this.tabs, this.active);

  final List<OpenTab> tabs;

  /// Index into [tabs]; -1 when there are none.
  final int active;

  OpenTab? get current =>
      active >= 0 && active < tabs.length ? tabs[active] : null;

  /// The front tab's active session, if it is one.
  TerminalController? get currentSession => switch (current) {
    SessionTab(:final controller) => controller,
    _ => null,
  };

  /// Every open session, in every pane of every tab.
  Iterable<TerminalController> get sessions =>
      tabs.whereType<SessionTab>().expand((t) => t.panes.controllers);
}

class TabsNotifier extends Notifier<TabsState> {
  /// Every live controller, to dispose with the notifier (`state` cannot be
  /// read while disposing).
  final Set<ConnectionController> _live = {};

  @override
  TabsState build() {
    ref.onDispose(() {
      for (final t in _live) {
        t.dispose();
      }
      _live.clear();
    });
    return const TabsState([], -1);
  }

  /// Rebuilds what watches the tabs after a change inside one.
  void _refresh() => state = TabsState(state.tabs, state.active);

  TerminalController _start(TerminalController c) {
    _live.add(c);
    c.start();
    return c;
  }

  void _add(TerminalController c) {
    final tabs = [...state.tabs, SessionTab(_start(c))];
    state = TabsState(tabs, tabs.length - 1);
  }

  TerminalController _controller({
    required String label,
    String? hostId,
    QuickTarget? target,
  }) => TerminalController(
    app: ref.read(openWardProvider),
    label: label,
    hostId: hostId,
    target: target,
    scrollback: ref.read(settingsProvider).scrollback,
  );

  /// A new tab connected to a saved host.
  void openHost(HostView host) =>
      _add(_controller(label: host.label, hostId: host.id));

  /// A new tab connected to an address that is not saved.
  void openAddress(QuickTarget target) =>
      _add(_controller(label: target.label, target: target));

  /// A new tab with the user's shell on this machine.
  void openLocal() => _add(_controller(label: 'Local'));

  /// Brings a page to the front, opening it if it is not open.
  void openPage(PageKind page) {
    final at = state.tabs.indexWhere((t) => t is PageTab && t.page == page);
    if (at >= 0) return select(at);
    final tabs = [...state.tabs, PageTab(page)];
    state = TabsState(tabs, tabs.length - 1);
  }

  void select(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = TabsState(state.tabs, index);
  }

  /// The next (or previous) tab, wrapping around.
  void cycle(int step) {
    final n = state.tabs.length;
    if (n == 0) return;
    select((state.active + step) % n);
  }

  void _dispose(ConnectionController c) {
    _live.remove(c);
    // After the frame that unmounts its pane, which may still poll it.
    SchedulerBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  /// Closes a tab; the one after it (or before, at the end) comes to front.
  void close(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final tabs = [...state.tabs];
    final closed = tabs.removeAt(index);
    switch (closed) {
      case SessionTab(:final panes):
        panes.controllers.forEach(_dispose);
      case SftpTab(:final controller):
        _dispose(controller);
      case PageTab():
    }
    var active = state.active;
    if (index < active || active >= tabs.length) active--;
    state = TabsState(
      tabs,
      tabs.isEmpty ? -1 : active.clamp(0, tabs.length - 1),
    );
  }

  /// ⌘W: the active pane when the tab is split, else the tab.
  void closeCurrent() {
    final tab = state.current;
    if (tab is SessionTab && tab.panes.isSplit) {
      return closePane(tab, tab.panes.active);
    }
    close(state.active);
  }

  /// Closes one pane; with the last one, the tab goes.
  void closePane(SessionTab tab, Pane pane) {
    final c = pane.controller;
    if (!tab.panes.remove(pane)) return close(state.tabs.indexOf(tab));
    if (c != null) _dispose(c);
    _refresh();
    focusActive(tab);
  }

  /// Closes the tab or pane of a terminal or a browser.
  void closeConnection(ConnectionController c) {
    if (c is TerminalController) return closeSession(c);
    final at = state.tabs.indexWhere(
      (t) => t is SftpTab && identical(t.controller, c),
    );
    if (at >= 0) close(at);
  }

  /// An SFTP tab for a saved host or an address; the one open for it, if
  /// there is one, comes to the front.
  void openSftp({String? hostId, QuickTarget? target, required String label}) {
    assert(hostId != null || target != null);
    final at = state.tabs.indexWhere(
      (t) =>
          t is SftpTab &&
          t.controller.hostId == hostId &&
          t.controller.target?.label == target?.label,
    );
    if (at >= 0) return select(at);
    final c = SftpController(
      app: ref.read(openWardProvider),
      label: label,
      hostId: hostId,
      target: target,
      queue: ref.read(transferQueueProvider),
    );
    _live.add(c);
    c.start();
    final tabs = [...state.tabs, SftpTab(c)];
    state = TabsState(tabs, tabs.length - 1);
  }

  /// The SFTP tab for the host of the front tab's session.
  void openSftpHere() {
    final c = state.currentSession;
    if (c == null || c.isLocal) return;
    openSftp(hostId: c.hostId, target: c.target, label: c.label);
  }

  /// Closes the pane (or tab) a session is in.
  void closeSession(TerminalController c) {
    for (final tab in state.tabs.whereType<SessionTab>()) {
      for (final pane in tab.panes.leaves) {
        if (pane.controller == c) return closePane(tab, pane);
      }
    }
  }

  /// Splits the front tab's active pane: right of it ([Axis.horizontal])
  /// or below. The new pane asks what to open.
  void split(Axis axis) {
    final tab = state.current;
    if (tab is! SessionTab) return;
    tab.panes.split(axis);
    _refresh();
  }

  /// Opens a session in a pane that asked: a saved host, an address, or
  /// (neither) a local shell.
  void fillPane(
    SessionTab tab,
    Pane pane, {
    HostView? host,
    QuickTarget? target,
  }) {
    final c = _start(
      host != null
          ? _controller(label: host.label, hostId: host.id)
          : target != null
          ? _controller(label: target.label, target: target)
          : _controller(label: 'Local'),
    );
    tab.panes.fill(pane, c);
    _refresh();
    focusActive(tab);
  }

  /// The same host as the pane it was split from (or a local shell).
  void fillSame(SessionTab tab, Pane pane) {
    final from = pane.from;
    final host = from?.hostId == null
        ? null
        : ref.read(libraryProvider).host(from!.hostId!);
    fillPane(tab, pane, host: host, target: from?.target);
  }

  /// Moves the keyboard to the pane in `direction`.
  void focusPane(AxisDirection direction) {
    final tab = state.current;
    if (tab is! SessionTab) return;
    final next = tab.panes.neighbor(direction);
    if (next == null) return;
    tab.panes.focus(next);
    _refresh();
    focusActive(tab);
  }

  void focusPaneOf(SessionTab tab, Pane pane) {
    if (identical(tab.panes.active, pane)) return;
    tab.panes.focus(pane);
    _refresh();
  }

  /// Gives the keyboard back to the active pane's terminal, after the
  /// frame (a click on a pane's header or menu may have taken it).
  void focusActive(SessionTab tab) {
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => tab.panes.active.controller?.focusTerminal?.call(),
    );
  }

  void toggleMaximize() {
    final tab = state.current;
    if (tab is! SessionTab) return;
    tab.panes.toggleMaximize();
  }

  /// ⌘⇧B: broadcast on or off in the front tab (it needs two panes).
  void toggleBroadcast() {
    final tab = state.current;
    if (tab is! SessionTab) return;
    tab.panes.setBroadcast(!tab.panes.broadcast);
    _refresh();
    focusActive(tab);
  }

  /// Moves a tab to index `to` of the resulting list.
  void move(int from, int to) {
    if (from == to || from < 0 || from >= state.tabs.length) return;
    final tabs = [...state.tabs];
    final current = state.current;
    tabs.insert(to.clamp(0, tabs.length - 1), tabs.removeAt(from));
    state = TabsState(tabs, current == null ? -1 : tabs.indexOf(current));
  }

  /// Renames the tab's active session.
  void rename(int index, String title) {
    if (index < 0 || index >= state.tabs.length) return;
    final tab = state.tabs[index];
    final c = tab is SessionTab ? tab.controller : null;
    if (c == null) return;
    c.customTitle = title.trim().isEmpty ? null : title.trim();
    _refresh();
  }
}

final tabsProvider = NotifierProvider<TabsNotifier, TabsState>(
  TabsNotifier.new,
);
