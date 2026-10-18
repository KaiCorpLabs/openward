import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../home/recent.dart';
import '../sftp/sftp_controller.dart';
import '../sftp/transfers.dart';
import '../src/rust/api/vault.dart';
import '../terminal/controller.dart';
import 'panes.dart';

export 'panes.dart' show DropSide, Pane, PaneNode, PaneSplit, Panes, paneNames;

/// What a tab holds: terminal sessions in panes, or one of the app's
/// pages. Pages open once; asking for one again brings its tab to the
/// front.
sealed class OpenTab {
  const OpenTab();
}

final class SessionTab extends OpenTab {
  SessionTab(TerminalController first) : panes = Panes(first);

  /// With panes taken from elsewhere: a pane dragged out, say.
  SessionTab.withPanes(this.panes);

  final Panes panes;

  /// The active pane's session; null while that pane asks what to open.
  TerminalController? get controller => panes.active.controller;
}

/// An SFTP browser for a host.
final class SftpTab extends OpenTab {
  SftpTab(this.controller);

  final SftpController controller;
}

enum PageKind {
  settings,
  tunnels,
  identities,
  keys,
  snippets,
  workspaces,
  knownHosts,
}

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
    c.addListener(() => _closeOnExit(c));
    c.addListener(() => _keepRecent(c));
    c.start();
    return c;
  }

  /// Sessions that are up now, as the recent list knows them.
  final Set<ConnectionController> _up = {};

  /// A session that comes up goes first in the recent connections; when
  /// it closes, its entry says when.
  void _keepRecent(ConnectionController c) {
    final up = c.phase == Phase.connected || c.phase == Phase.running;
    if (up && _up.add(c)) {
      ref.read(recentProvider.notifier).connected(c);
    } else if (c.phase == Phase.closed && _up.remove(c)) {
      ref.read(recentProvider.notifier).ended(c);
    }
  }

  /// When a shell ends by itself, its pane (or tab) closes, as the user's
  /// setting says: when it ended well (`exit`, `logout`), or always. Never
  /// for a connection that failed, nor one the user gave up on.
  void _closeOnExit(TerminalController c) {
    final closed = c.closed;
    if (c.phase != Phase.closed || closed == null || c.cancelled) return;
    if (c.isDisposed || closed.failure != null || !_live.contains(c)) return;
    final close = switch (ref.read(settingsProvider).onExit) {
      OnExit.clean => (closed.exitCode ?? 0) == 0,
      OnExit.always => true,
      OnExit.never => false,
    };
    // After the frame: the event that closed it is still being handled.
    if (close) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_live.contains(c) && c.phase == Phase.closed) closeSession(c);
      });
    }
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
    if (_up.remove(c)) ref.read(recentProvider.notifier).ended(c);
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
    final tabs = [
      ...state.tabs,
      SftpTab(startSftp(hostId: hostId, target: target, label: label)),
    ];
    state = TabsState(tabs, tabs.length - 1);
  }

  /// A browser started for a tab put together elsewhere (a workspace).
  SftpController startSftp({
    String? hostId,
    QuickTarget? target,
    required String label,
  }) {
    final c = SftpController(
      app: ref.read(openWardProvider),
      label: label,
      hostId: hostId,
      target: target,
      queue: ref.read(transferQueueProvider),
    );
    _live.add(c);
    c.start();
    return c;
  }

  /// A session started for a pane put together elsewhere (a workspace): a
  /// saved host, an address, or (neither) a local shell.
  TerminalController startSession({HostView? host, QuickTarget? target}) =>
      _start(
        host != null
            ? _controller(label: host.label, hostId: host.id)
            : target != null
            ? _controller(label: target.label, target: target)
            : _controller(label: 'Local'),
      );

  /// Adds tabs put together elsewhere, after the open ones, with `front`
  /// in front.
  void addTabs(List<OpenTab> added, {OpenTab? front}) {
    if (added.isEmpty) return;
    final tabs = [...state.tabs, ...added];
    final shown = front ?? added.first;
    state = TabsState(tabs, tabs.indexOf(shown));
    if (shown is SessionTab) focusActive(shown);
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
    final c = startSession(host: host, target: target);
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

  /// Moves a tab to the gap before `gap` (0 to the number of tabs), as
  /// dropping between tabs says.
  void moveToGap(int from, int gap) => move(from, gap > from ? gap - 1 : gap);

  /// A tab dropped on the `side` half of `at`: its panes join `target`,
  /// and it closes (its sessions go on, in their new place).
  void dropTab(OpenTab dragged, SessionTab target, Pane at, DropSide side) {
    if (dragged is! SessionTab || identical(dragged, target)) return;
    if (!state.tabs.contains(dragged) || !state.tabs.contains(target)) return;
    final tabs = [...state.tabs]..remove(dragged);
    target.panes.insertBeside(
      at,
      dragged.panes.root,
      side,
      focus: dragged.panes.active,
    );
    state = TabsState(tabs, tabs.indexOf(target));
    focusActive(target);
  }

  /// A pane dragged by its header onto the `side` half of `at`, in its own
  /// tab or another. A tab left without panes closes.
  void dropPane(
    SessionTab from,
    Pane pane,
    SessionTab target,
    Pane at,
    DropSide side,
  ) {
    if (identical(pane, at)) return;
    final alone = !from.panes.isSplit;
    if (alone && identical(from, target)) return;
    final tabs = [...state.tabs];
    if (alone) {
      tabs.remove(from);
    } else {
      from.panes.remove(pane);
    }
    target.panes.insertBeside(at, pane, side, focus: pane);
    state = TabsState(tabs, tabs.indexOf(target));
    focusActive(target);
  }

  /// A pane dragged onto the tab bar: a tab of its own, in that gap.
  void detachPane(SessionTab from, Pane pane, int gap) {
    final at = state.tabs.indexOf(from);
    if (at < 0) return;
    if (!from.panes.isSplit) return moveToGap(at, gap);
    from.panes.remove(pane);
    final tab = SessionTab.withPanes(Panes.of(pane));
    final tabs = [...state.tabs]..insert(gap.clamp(0, state.tabs.length), tab);
    state = TabsState(tabs, tabs.indexOf(tab));
    focusActive(tab);
  }

  /// A pane in a tab of its own, right after its tab.
  void moveToNewTab(SessionTab from, Pane pane) {
    final at = state.tabs.indexOf(from);
    if (at >= 0) detachPane(from, pane, at + 1);
  }

  /// Swaps a pane with its neighbour in the split.
  void swapPane(SessionTab tab, Pane pane) {
    final other = tab.panes.swapPartner(pane);
    if (other == null) return;
    tab.panes.swap(pane, other);
    _refresh();
    focusActive(tab);
  }

  /// The pane asks again what to open; its session goes on in a tab of its
  /// own, right after this one, so nothing is closed by surprise.
  void openOtherHere(SessionTab tab, Pane pane) {
    final c = pane.controller;
    final at = state.tabs.indexOf(tab);
    if (c == null || at < 0) return;
    pane.controller = null;
    tab.panes.focus(pane);
    final moved = SessionTab.withPanes(Panes.of(Pane(c)));
    final tabs = [...state.tabs]..insert(at + 1, moved);
    state = TabsState(tabs, tabs.indexOf(tab));
  }

  /// A tab already open, brought into a pane that asked what to open: its
  /// panes take that place, and it closes.
  void bringTab(OpenTab other, SessionTab target, Pane pane) {
    if (other is! SessionTab || identical(other, target)) return;
    if (!state.tabs.contains(other)) return;
    final tabs = [...state.tabs]..remove(other);
    target.panes.replace(pane, other.panes.root, focus: other.panes.active);
    state = TabsState(tabs, tabs.indexOf(target));
    focusActive(target);
  }

  /// A host, or a tab already open, beside the front tab's active pane (on
  /// its right).
  void splitWith({HostView? host, OpenTab? other}) {
    final target = state.current;
    if (target is! SessionTab) return;
    final at = target.panes.active;
    if (other != null) return dropTab(other, target, at, DropSide.right);
    if (host != null) dropHost(host, target, at, DropSide.right);
  }

  /// ⌘⌥=: the same room for every pane of the front tab.
  void equalize() {
    final tab = state.current;
    if (tab is! SessionTab || !tab.panes.isSplit) return;
    tab.panes.equalize();
  }

  /// A host dropped on the `side` half of `at`: connected in a new pane.
  void dropHost(HostView host, SessionTab target, Pane at, DropSide side) {
    final pane = Pane(_start(_controller(label: host.label, hostId: host.id)));
    target.panes.insertBeside(at, pane, side, focus: pane);
    state = TabsState(state.tabs, state.tabs.indexOf(target));
    focusActive(target);
  }

  /// A host dropped on the tab bar: a tab for it, in that gap.
  void openHostAt(HostView host, int gap) {
    openHost(host);
    moveToGap(state.tabs.length - 1, gap);
  }

  /// Another tab with the same host (or address, or a local shell) as the
  /// tab's active pane, right after it.
  void duplicate(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final tab = state.tabs[index];
    final c = tab is SessionTab
        ? tab.controller ?? tab.panes.controllers.firstOrNull
        : null;
    if (c == null) return;
    _add(_controller(label: c.label, hostId: c.hostId, target: c.target));
    moveToGap(state.tabs.length - 1, index + 1);
  }

  /// Each pane of a tab in a tab of its own, after it; the active one
  /// stays.
  void separate(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final tab = state.tabs[index];
    if (tab is! SessionTab || !tab.panes.isSplit) return;
    final keep = tab.panes.active;
    final others = tab.panes.leaves.where((p) => !identical(p, keep)).toList();
    for (final p in others) {
      tab.panes.remove(p);
    }
    final tabs = [...state.tabs]
      ..insertAll(index + 1, [
        for (final p in others) SessionTab.withPanes(Panes.of(p)),
      ]);
    state = TabsState(tabs, index);
  }

  /// Closes every tab but this one.
  void closeOthers(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final keep = state.tabs[index];
    for (var i = state.tabs.length - 1; i >= 0; i--) {
      if (!identical(state.tabs[i], keep)) close(i);
    }
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
