import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/vault.dart';
import '../terminal/controller.dart';

/// The open tabs and which one is in front.
class TabsState {
  const TabsState(this.tabs, this.active);

  final List<TerminalController> tabs;

  /// Index into [tabs]; -1 when there are none.
  final int active;

  TerminalController? get current =>
      active >= 0 && active < tabs.length ? tabs[active] : null;
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
    final tabs = [...state.tabs, c];
    state = TabsState(tabs, tabs.length - 1);
  }

  /// A new tab connected to a saved host.
  void openHost(HostView host) {
    _add(
      TerminalController(
        app: ref.read(openWardProvider),
        label: host.label,
        hostId: host.id,
      ),
    );
  }

  /// A new tab with the user's shell on this machine.
  void openLocal() {
    _add(TerminalController(app: ref.read(openWardProvider), label: 'Local'));
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
    _live.remove(closed);
    // After the frame that unmounts its pane, which may still poll it.
    SchedulerBinding.instance.addPostFrameCallback((_) => closed.dispose());
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
    state.tabs[index].customTitle = title.trim().isEmpty ? null : title.trim();
    state = TabsState(state.tabs, state.active);
  }
}

final tabsProvider = NotifierProvider<TabsNotifier, TabsState>(
  TabsNotifier.new,
);
