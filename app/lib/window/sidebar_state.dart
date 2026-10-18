// How much room the sidebar takes right now: what the settings say, folded
// while a terminal or file tab is in front if the user asked for that,
// and shown over the window ("peeking") when it is hidden.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../tabs/tabs.dart';

/// What the sidebar is doing besides its setting.
class SidebarState {
  const SidebarState({
    this.openedHere = false,
    this.lastFold = SidebarMode.rail,
    this.peek = false,
    this.dragWidth,
  });

  /// ⌘B opened it while a session was in front: it stays open there
  /// until that session leaves the front.
  final bool openedHere;

  /// What ⌘B folds it to: the last folded state, a rail at first.
  final SidebarMode lastFold;

  /// Shown over the window while hidden (or from the rail).
  final bool peek;

  /// The width while its edge is dragged; saved when the drag ends.
  final double? dragWidth;

  SidebarState copyWith({
    bool? openedHere,
    SidebarMode? lastFold,
    bool? peek,
    double? Function()? dragWidth,
  }) => SidebarState(
    openedHere: openedHere ?? this.openedHere,
    lastFold: lastFold ?? this.lastFold,
    peek: peek ?? this.peek,
    dragWidth: dragWidth == null ? this.dragWidth : dragWidth(),
  );
}

/// A terminal or file tab is in front.
bool sessionInFront(TabsState tabs) =>
    tabs.current is SessionTab || tabs.current is SftpTab;

class SidebarNotifier extends Notifier<SidebarState> {
  @override
  SidebarState build() => const SidebarState();

  /// ⌘B: folds the sidebar if it is open, opens it otherwise.
  void toggle() {
    final settings = ref.read(settingsProvider);
    final save = ref.read(settingsProvider.notifier).update;
    final session = sessionInFront(ref.read(tabsProvider));
    final shown = shownSidebar(
      mode: settings.sidebar,
      onSession: settings.sidebarOnSession,
      session: session,
      openedHere: state.openedHere,
    );
    if (shown == SidebarMode.open) {
      // Opened over a session that folds it: back to how sessions show it,
      // without changing the setting.
      final folds =
          session &&
          settings.sidebarOnSession != SidebarOnSession.keep &&
          state.openedHere;
      state = state.copyWith(openedHere: false, peek: false);
      if (!folds) save((s) => s.copyWith(sidebar: state.lastFold));
      return;
    }
    if (settings.sidebar != SidebarMode.open) {
      state = state.copyWith(lastFold: settings.sidebar);
      save((s) => s.copyWith(sidebar: SidebarMode.open));
    }
    state = state.copyWith(openedHere: session, peek: false);
  }

  /// The setting changed by hand (Settings): the next ⌘B folds to it.
  void chose(SidebarMode mode) {
    if (mode != SidebarMode.open) state = state.copyWith(lastFold: mode);
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(sidebar: mode));
  }

  /// The session that opened it left the front.
  void sessionLeft() {
    if (state.openedHere) state = state.copyWith(openedHere: false);
  }

  void setPeek(bool on) {
    if (state.peek != on) state = state.copyWith(peek: on);
  }

  /// Its edge is being dragged.
  void drag(double width) => state = state.copyWith(
    dragWidth: () =>
        width.clamp(Settings.minSidebarWidth, Settings.maxSidebarWidth),
  );

  /// The drag ended: the width is saved.
  void endDrag() {
    final width = state.dragWidth;
    state = state.copyWith(dragWidth: () => null);
    if (width == null) return;
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(sidebarWidth: width.roundToDouble()));
  }

  void resetWidth() => ref
      .read(settingsProvider.notifier)
      .update((s) => s.copyWith(sidebarWidth: Settings.defaultSidebarWidth));
}

final sidebarProvider = NotifierProvider<SidebarNotifier, SidebarState>(
  SidebarNotifier.new,
);

/// How the sidebar shows now. With a session in front, the setting for
/// sessions may fold it further, unless ⌘B opened it there.
final sidebarModeProvider = Provider<SidebarMode>((ref) {
  final (mode, onSession) = ref.watch(
    settingsProvider.select((s) => (s.sidebar, s.sidebarOnSession)),
  );
  return shownSidebar(
    mode: mode,
    onSession: onSession,
    session: ref.watch(tabsProvider.select(sessionInFront)),
    openedHere: ref.watch(sidebarProvider.select((s) => s.openedHere)),
  );
});

/// The rule of [sidebarModeProvider]: the setting, folded further while a
/// session is in front if the setting for sessions says so (the more
/// folded of the two wins), unless ⌘B opened it there.
SidebarMode shownSidebar({
  required SidebarMode mode,
  required SidebarOnSession onSession,
  required bool session,
  required bool openedHere,
}) {
  if (!session || openedHere) return mode;
  final folded = switch (onSession) {
    SidebarOnSession.keep => SidebarMode.open,
    SidebarOnSession.rail => SidebarMode.rail,
    SidebarOnSession.hide => SidebarMode.hidden,
  };
  return folded.index > mode.index ? folded : mode;
}

/// The open sidebar's width, also while its edge is dragged.
final sidebarWidthProvider = Provider<double>(
  (ref) =>
      ref.watch(sidebarProvider.select((s) => s.dragWidth)) ??
      ref.watch(settingsProvider.select((s) => s.sidebarWidth)),
);

/// The width of the rail of icons.
const double railWidth = 56;
