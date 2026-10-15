import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../src/rust/api/vault.dart';
import '../terminal/controller.dart';

/// What a tab holds: a terminal session, or one of the app's pages. Pages
/// open once; asking for one again brings its tab to the front.
sealed class OpenTab {
  const OpenTab();
}

final class SessionTab extends OpenTab {
  const SessionTab(this.controller);

  final TerminalController controller;
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

  /// The front tab's session, if it is one.
  TerminalController? get currentSession => switch (current) {
    SessionTab(:final controller) => controller,
    _ => null,
  };

  /// Every open session, in tab order.
  Iterable<TerminalController> get sessions =>
      tabs.whereType<SessionTab>().map((t) => t.controller);
}

class TabsNotifier extends Notifier<TabsState> {
  /// Every live controller, to dispose with the notifier (`state` cannot be
  /// read while disposing).
  final Set<TerminalController> _live = {};

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

  void _add(TerminalController c) {
    _live.add(c);
    c.start();
    final tabs = [...state.tabs, SessionTab(c)];
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

  /// Closes a tab; the one after it (or before, at the end) comes to front.
  void close(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final tabs = [...state.tabs];
    final closed = tabs.removeAt(index);
    if (closed case SessionTab(:final controller)) {
      _live.remove(controller);
      // After the frame that unmounts its pane, which may still poll it.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => controller.dispose(),
      );
    }
    var active = state.active;
    if (index < active || active >= tabs.length) active--;
    state = TabsState(
      tabs,
      tabs.isEmpty ? -1 : active.clamp(0, tabs.length - 1),
    );
  }

  /// Moves a tab to index `to` of the resulting list.
  void move(int from, int to) {
    if (from == to || from < 0 || from >= state.tabs.length) return;
    final tabs = [...state.tabs];
    final current = state.current;
    tabs.insert(to.clamp(0, tabs.length - 1), tabs.removeAt(from));
    state = TabsState(tabs, current == null ? -1 : tabs.indexOf(current));
  }

  void rename(int index, String title) {
    if (index < 0 || index >= state.tabs.length) return;
    final tab = state.tabs[index];
    if (tab is! SessionTab) return;
    tab.controller.customTitle = title.trim().isEmpty ? null : title.trim();
    state = TabsState(state.tabs, state.active);
  }
}

final tabsProvider = NotifierProvider<TabsNotifier, TabsState>(
  TabsNotifier.new,
);
