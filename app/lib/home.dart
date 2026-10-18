import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/settings.dart';
import 'home/start_page.dart';
import 'hosts/editors.dart';
import 'hosts/rail.dart';
import 'hosts/sidebar.dart';
import 'settings/settings_page.dart';
import 'sftp/sftp_view.dart';
import 'tabs/session_view.dart';
import 'tabs/tab_strip.dart';
import 'tabs/tabs.dart';
import 'terminal/controller.dart';
import 'terminal/keys.dart';
import 'identities/identities_page.dart';
import 'keys/keys_page.dart';
import 'known_hosts/known_hosts_page.dart';
import 'palette/command_palette.dart';
import 'snippets/palette.dart';
import 'snippets/snippets_page.dart';
import 'tunnels/tunnels_page.dart';
import 'ui/announcer.dart';
import 'welcome/whats_new.dart';
import 'workspaces/workspaces_page.dart';
import 'ui/tokens.dart';
import 'l10n/l10n.dart';
import 'window/chrome.dart';
import 'window/shortcuts.dart';
import 'window/sidebar_state.dart';
import 'welcome/first_run.dart';

/// Arrow keys and the way each moves between panes.
const _arrows = [
  (LogicalKeyboardKey.arrowLeft, AxisDirection.left),
  (LogicalKeyboardKey.arrowRight, AxisDirection.right),
  (LogicalKeyboardKey.arrowUp, AxisDirection.up),
  (LogicalKeyboardKey.arrowDown, AxisDirection.down),
];

/// The main window: hosts on the left; tabs on the right, with the front
/// one below them. On the first run with nothing saved, the guide instead.
class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  bool _newsShown = false;

  /// The first-run guide was shown: it stays until it is done, even once
  /// an import there has filled the library.
  bool _guide = false;

  final FocusNode _search = FocusNode(debugLabel: 'host search');

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _palette() => showCommandPalette(context, ref);

  /// Before the tabs when the sidebar is folded: the room the window
  /// buttons need (the rail takes part of it) and, with it hidden, a
  /// button that opens it.
  Widget? _leading(SidebarMode mode) {
    if (mode == SidebarMode.open) return null;
    final l = context.l10n;
    final buttons = customTitleBar && !ref.watch(fullScreenProvider);
    final room = mode == SidebarMode.hidden
        ? windowButtonsWidth
        : windowButtonsWidth - railWidth;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (buttons)
          SizedBox(
            width: room,
            height: topBarHeight,
            child: const WindowDragArea(),
          )
        else if (mode == SidebarMode.hidden)
          const SizedBox(width: 6),
        if (mode == SidebarMode.hidden)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              key: const ValueKey('tabs.showSidebar'),
              tooltip: withKeys(l.showSidebar, sidebarKeys(l)),
              icon: const Icon(Icons.view_sidebar_outlined, size: 18),
              onPressed: ref.read(sidebarProvider.notifier).toggle,
            ),
          ),
      ],
    );
  }

  Future<void> _newHost() async {
    if (await showHostEditor(context, ref)) {
      ref.read(libraryProvider.notifier).refresh();
    }
  }

  /// Window shortcuts. Terminal panes let these through (`isAppShortcut`).
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final tabs = ref.read(tabsProvider.notifier);
    void closeCurrent() => tabs.closeCurrent();
    void splitRight() => tabs.split(Axis.horizontal);
    void splitDown() => tabs.split(Axis.vertical);
    void go(AxisDirection d) => tabs.focusPane(d);
    void settings() => tabs.openPage(PageKind.settings);
    void last() => tabs.select(ref.read(tabsProvider).tabs.length - 1);
    TerminalController? session() => ref.read(tabsProvider).currentSession;
    void find() => session()?.openFind();
    void next() => session()?.findStep(older: true);
    void previous() => session()?.findStep(older: false);
    void bigger() => session()?.zoomBy(1);
    void smaller() => session()?.zoomBy(-1);
    void actualSize() => session()?.resetZoom();
    void snippets() => showSnippetPalette(context);
    void palette() => _palette();
    void shortcuts() => showShortcuts(context);
    final sidebar = ref.read(sidebarProvider.notifier).toggle;
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
          tabs.cycle(1),
      const SingleActivator(
        LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      ): () =>
          tabs.cycle(-1),
    };
    if (isApple) {
      bindings.addAll({
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): settings,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
            tabs.openLocal,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newHost,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            closeCurrent,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): palette,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): sidebar,
        // ⌘/ wherever the layout has the slash (⌘⇧7 on a Spanish one).
        const SingleActivator(LogicalKeyboardKey.slash, meta: true): shortcuts,
        const CharacterActivator('/', meta: true): shortcuts,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): find,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): next,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true, shift: true):
            previous,
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): bigger,
        const SingleActivator(
          LogicalKeyboardKey.equal,
          meta: true,
          shift: true,
        ): bigger,
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): smaller,
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true):
            actualSize,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): splitRight,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true):
            splitDown,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          shift: true,
        ): tabs.toggleMaximize,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true):
            tabs.toggleBroadcast,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true):
            tabs.openSftpHere,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            snippets,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true):
            palette,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): palette,
        for (final (key, d) in _arrows)
          SingleActivator(key, meta: true, alt: true): () => go(d),
        const SingleActivator(
          LogicalKeyboardKey.bracketRight,
          meta: true,
          shift: true,
        ): () =>
            tabs.cycle(1),
        const SingleActivator(
          LogicalKeyboardKey.bracketLeft,
          meta: true,
          shift: true,
        ): () =>
            tabs.cycle(-1),
        for (var i = 1; i <= 9; i++)
          SingleActivator(
            LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i - 1),
            meta: true,
          ): i == 9
              ? last
              : () => tabs.select(i - 1),
      });
    } else {
      bindings.addAll({
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            settings,
        const SingleActivator(
          LogicalKeyboardKey.keyT,
          control: true,
          shift: true,
        ): tabs.openLocal,
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): _newHost,
        const SingleActivator(
          LogicalKeyboardKey.keyW,
          control: true,
          shift: true,
        ): closeCurrent,
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): tabs.openSftpHere,
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): snippets,
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): palette,
        const SingleActivator(
          LogicalKeyboardKey.keyK,
          control: true,
          shift: true,
        ): palette,
        const SingleActivator(
          LogicalKeyboardKey.keyL,
          control: true,
          shift: true,
        ): sidebar,
        const SingleActivator(
          LogicalKeyboardKey.slash,
          control: true,
          shift: true,
        ): shortcuts,
        const SingleActivator(
          LogicalKeyboardKey.question,
          control: true,
          shift: true,
        ): shortcuts,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): find,
        const SingleActivator(
          LogicalKeyboardKey.keyG,
          control: true,
          shift: true,
        ): next,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): bigger,
        const SingleActivator(LogicalKeyboardKey.minus, control: true): smaller,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            actualSize,
        const SingleActivator(
          LogicalKeyboardKey.keyD,
          control: true,
          shift: true,
        ): splitRight,
        const SingleActivator(
          LogicalKeyboardKey.keyE,
          control: true,
          shift: true,
        ): splitDown,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          shift: true,
        ): tabs.toggleMaximize,
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          shift: true,
        ): tabs.toggleBroadcast,
        for (final (key, d) in _arrows)
          SingleActivator(key, control: true, shift: true): () => go(d),
      });
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    final welcomed = ref.watch(settingsProvider.select((s) => s.welcomed));
    final empty = ref.watch(
      libraryProvider.select((l) => l.hosts.isEmpty && l.groups.isEmpty),
    );
    if (!welcomed && (empty || _guide)) {
      _guide = true;
      return const FirstRun();
    }
    // Once per release, for who used an earlier one.
    if (!_newsShown && shouldShowNews(ref.read(settingsProvider))) {
      _newsShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showWhatsNew(context, ref);
      });
    }
    final current = ref.watch(tabsProvider.select((s) => s.current));
    final mode = ref.watch(sidebarModeProvider);
    final width = ref.watch(sidebarWidthProvider);
    final peek = ref.watch(sidebarProvider.select((s) => s.peek));
    // A session that opened the sidebar with ⌘B leaves the front: sessions
    // fold it again; anything new in front closes it if it was peeking.
    ref.listen(tabsProvider.select(sessionInFront), (before, now) {
      if (before == true && !now) {
        ref.read(sidebarProvider.notifier).sessionLeft();
      }
    });
    ref.listen(tabsProvider.select((s) => s.current), (_, _) {
      ref.read(sidebarProvider.notifier).setPeek(false);
    });
    final ow = context.ow;
    return CallbackShortcuts(
      bindings: _shortcuts(),
      // Shortcuts only hear keys from below them. With no field focused (at
      // start, or once the focused terminal or page is gone), the focus would
      // fall back to the route's scope, above this widget; this scope keeps
      // it here, so the window's shortcuts work with nothing focused too.
      child: FocusScope(
        debugLabel: 'window',
        autofocus: true,
        child: Announcer(
          child: Scaffold(
            backgroundColor: ow.colors.window,
            body: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tab goes through the sidebar, then the tabs and what they show.
                    if (mode == SidebarMode.open) ...[
                      SizedBox(
                        width: width,
                        child: FocusTraversalGroup(
                          child: Sidebar(searchFocus: _search),
                        ),
                      ),
                      _SidebarEdge(line: !ow.shape.pills),
                    ] else if (mode == SidebarMode.rail) ...[
                      SizedBox(
                        width: railWidth,
                        child: FocusTraversalGroup(
                          child: SidebarRail(onSearch: _palette),
                        ),
                      ),
                      if (!ow.shape.pills)
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: ow.colors.border,
                        ),
                    ],
                    Expanded(
                      child: FocusTraversalGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TabStrip(leading: _leading(mode)),
                            Expanded(
                              child: switch (current) {
                                final SessionTab tab => TabView(
                                  key: ObjectKey(tab),
                                  tab: tab,
                                ),
                                final SftpTab tab => SftpView(
                                  key: ObjectKey(tab),
                                  controller: tab.controller,
                                ),
                                PageTab(page: PageKind.settings) =>
                                  const SettingsPage(),
                                PageTab(page: PageKind.tunnels) =>
                                  const TunnelsPage(),
                                PageTab(page: PageKind.identities) =>
                                  const IdentitiesPage(),
                                PageTab(page: PageKind.keys) =>
                                  const KeysPage(),
                                PageTab(page: PageKind.snippets) =>
                                  const SnippetsPage(),
                                PageTab(page: PageKind.workspaces) =>
                                  const WorkspacesPage(),
                                PageTab(page: PageKind.knownHosts) =>
                                  const KnownHostsPage(),
                                null => const StartPage(),
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (mode == SidebarMode.hidden && !peek)
                  const Positioned(
                    left: 0,
                    top: topBarHeight,
                    bottom: 0,
                    width: 5,
                    child: _PeekEdge(),
                  ),
                if (peek && mode != SidebarMode.open)
                  Positioned(
                    left: 0,
                    top: topBarHeight,
                    bottom: 0,
                    width: width,
                    child: _Peek(
                      child: FocusTraversalGroup(
                        child: Sidebar(searchFocus: _search, overWindow: true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The open sidebar's right edge: dragging it changes the width (between
/// 220 and 420 px), a double click puts it back.
class _SidebarEdge extends ConsumerWidget {
  const _SidebarEdge({required this.line});

  /// Draw the hairline (themes with pills have none).
  final bool line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sidebar = ref.read(sidebarProvider.notifier);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => sidebar.drag(d.globalPosition.dx),
        onHorizontalDragEnd: (_) => sidebar.endDrag(),
        onDoubleTap: sidebar.resetWidth,
        child: SizedBox(
          width: 5,
          child: Center(
            child: line
                ? VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: context.ow.colors.border,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// The left edge while the sidebar is hidden: resting the pointer there a
/// moment shows it over the window.
class _PeekEdge extends ConsumerStatefulWidget {
  const _PeekEdge();

  @override
  ConsumerState<_PeekEdge> createState() => _PeekEdgeState();
}

class _PeekEdgeState extends ConsumerState<_PeekEdge> {
  Timer? _wait;

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _wait = Timer(
      const Duration(milliseconds: 150),
      () => ref.read(sidebarProvider.notifier).setPeek(true),
    ),
    onExit: (_) => _wait?.cancel(),
    child: const SizedBox.expand(),
  );
}

/// The sidebar shown over the window: it goes when the pointer leaves it,
/// or when a tab comes to the front.
class _Peek extends ConsumerStatefulWidget {
  const _Peek({required this.child});

  final Widget child;

  @override
  ConsumerState<_Peek> createState() => _PeekState();
}

class _PeekState extends ConsumerState<_Peek> {
  Timer? _leave;

  @override
  void dispose() {
    _leave?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return MouseRegion(
      onEnter: (_) => _leave?.cancel(),
      onExit: (_) => _leave = Timer(
        const Duration(milliseconds: 300),
        () => ref.read(sidebarProvider.notifier).setPeek(false),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              ref.read(sidebarProvider.notifier).setPeek(false),
        },
        child: Material(
          key: const ValueKey('sidebar.peek'),
          color: c.window,
          elevation: 12,
          shadowColor: Colors.black54,
          shape: Border(right: BorderSide(color: c.control)),
          child: widget.child,
        ),
      ),
    );
  }
}
