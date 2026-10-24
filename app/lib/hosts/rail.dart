import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart' show HostView;
import '../tabs/tab_strip.dart' show tabTitle;
import '../tabs/tabs.dart';
import '../terminal/controller.dart';
import '../terminal/keys.dart';
import '../tunnels/tunnels.dart';
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/chrome.dart';
import '../window/shortcuts.dart';
import '../window/sidebar_state.dart';
import 'host_actions.dart';
import 'sidebar.dart'
    show hostStatus, libraryEntries, tabBadge, tabHost, tabStatus;

/// The sidebar folded to a column of icons. Fixed at the top, the search
/// and the Hosts page; in the middle, the favorites to launch and a counter
/// of the open tabs that lists them; fixed at the bottom, the library (a
/// menu of its pages), opening the sidebar and the settings. However many
/// tabs are open, nothing pushes the ends out of sight.
class SidebarRail extends ConsumerWidget {
  const SidebarRail({super.key, required this.onSearch});

  /// Opens the palette.
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final state = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final library = ref.watch(libraryProvider);
    final current = state.current;
    bool here(PageKind kind) => current is PageTab && current.page == kind;
    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: OwSpace.s3),
      child: SizedBox(width: 24, child: Divider(height: 1, color: c.border)),
    );
    final open = [
      for (final (i, t) in state.tabs.indexed)
        if (t is SessionTab || t is SftpTab) (i, t),
    ];
    final favorites = library.favorites;
    final sessions = state.sessions.toList();
    return ColoredBox(
      color: c.window,
      child: Column(
        children: [
          const WindowButtonsSpace(),
          _RailButton(
            key: const ValueKey('rail.search'),
            tooltip:
                '${l.search} (${isApple ? '⌘K' : '${l.ctrlShiftPrefix}K'})',
            onPressed: onSearch,
            child: Icon(Icons.search, size: 18, color: c.textMuted),
          ),
          _RailButton(
            key: const ValueKey('rail.hosts'),
            tooltip: withKeys(l.hosts, hostsKeys(l)),
            selected: here(PageKind.hosts),
            onPressed: () => tabs.openPage(PageKind.hosts),
            child: Icon(Icons.dns_outlined, size: 18, color: c.accentText),
          ),
          Expanded(
            // The favorites scroll when they do not fit; the counter stays
            // right under them.
            child: Column(
              children: [
                if (favorites.isNotEmpty) divider(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final h in favorites)
                        Center(
                          child: _FavoriteButton(
                            host: h,
                            sessions: [
                              for (final s in sessions)
                                if (s.hostId == h.id) s,
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (open.isNotEmpty) ...[
                  divider(),
                  _OpenCounter(open: open, active: state.active),
                ],
              ],
            ),
          ),
          divider(),
          const _LibraryButton(),
          _RailButton(
            key: const ValueKey('rail.expand'),
            tooltip: withKeys(l.showSidebar, sidebarKeys(l)),
            onPressed: ref.read(sidebarProvider.notifier).toggle,
            child: Icon(
              Icons.view_sidebar_outlined,
              size: 18,
              color: c.textMuted,
            ),
          ),
          _RailButton(
            key: const ValueKey('rail.settings'),
            tooltip: l.settings,
            selected: here(PageKind.settings),
            onPressed: () => tabs.openPage(PageKind.settings),
            child: Icon(Icons.settings_outlined, size: 18, color: c.textMuted),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A menu beside the rail button at `context`, level with it.
Future<T?> _menuBeside<T>(BuildContext context, List<PopupMenuEntry<T>> items) {
  final box = context.findRenderObject()! as RenderBox;
  final at = box.localToGlobal(Offset(box.size.width + 6, 0));
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    items: items,
  );
}

/// A favorite: its tab comes to the front if it has one; otherwise it
/// connects. A dot says it is open.
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.host, required this.sessions});

  final HostView host;
  final List<TerminalController> sessions;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final h = host;
    final open = sessions.isNotEmpty;
    return Consumer(
      builder: (context, ref, _) => ListenableBuilder(
        listenable: Listenable.merge(sessions),
        builder: (context, _) {
          final status = open ? hostStatus(sessions) : null;
          return _RailButton(
            key: ValueKey('rail.favorite.${h.label}'),
            tooltip: [
              h.label,
              if (h.environment case final e?) shownEnv(l, e).short,
              hostAddress(h),
              l.favoriteLower,
              if (status == Status.connected) l.hostsOpenNow,
            ].join(' · '),
            onPressed: () {
              final state = ref.read(tabsProvider);
              final tabs = ref.read(tabsProvider.notifier);
              final at = state.tabs.indexWhere(
                (t) =>
                    t is SessionTab &&
                    t.panes.controllers.any((s) => s.hostId == h.id),
              );
              at >= 0 ? tabs.select(at) : tabs.openHost(h);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SystemBadge(
                  code: h.system?.code,
                  env: h.environment,
                  size: 24,
                  tagged: true,
                ),
                if (status != null)
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(OwSpace.s1),
                      decoration: BoxDecoration(
                        color: context.ow.colors.window,
                        shape: BoxShape.circle,
                      ),
                      child: StatusDot(status, size: 7),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// How many terminal and file tabs are open; a click lists them, each
/// with its mark, to bring one to the front.
class _OpenCounter extends ConsumerWidget {
  const _OpenCounter({required this.open, required this.active});

  final List<(int, OpenTab)> open;
  final int active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final inFront = open.any((e) => e.$1 == active);
    return Builder(
      builder: (context) => _RailButton(
        key: const ValueKey('rail.open'),
        tooltip: l.openTabsCount(open.length),
        selected: inFront,
        onPressed: () async {
          final library = ref.read(libraryProvider);
          final picked = await _menuBeside<int>(context, [
            PopupMenuItem<int>(
              enabled: false,
              height: 28,
              child: SectionLabel(l.openSection, trailing: '${open.length}'),
            ),
            for (final (i, t) in open)
              PopupMenuItem<int>(
                key: ValueKey('rail.open.${tabTitle(context, t)}'),
                value: i,
                height: 36,
                child: _OpenItem(
                  tab: t,
                  library: library,
                  current: i == active,
                ),
              ),
          ]);
          if (picked != null) ref.read(tabsProvider.notifier).select(picked);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_outlined, size: 15, color: c.text),
            Text(
              '${open.length}',
              style: monoStyle(
                context,
                size: 12,
                color: c.text,
              ).copyWith(fontWeight: FontWeight.w600, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of the open tabs' list.
class _OpenItem extends StatelessWidget {
  const _OpenItem({
    required this.tab,
    required this.library,
    required this.current,
  });

  final OpenTab tab;
  final Library library;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final env = tabHost(tab, library)?.environment;
    final t = tab;
    final status = t is SessionTab
        ? (t.panes.active.controller ?? t.panes.controllers.firstOrNull)?.let(
            tabStatus,
          )
        : null;
    return SizedBox(
      width: 260,
      child: Row(
        children: [
          tabBadge(tab, library, tagged: true),
          const SizedBox(width: 10),
          // The name and its mark together; how it is doing, at the end.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    tabTitle(context, tab),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      color: c.text,
                    ),
                  ),
                ),
                if (env != null) ...[const SizedBox(width: 8), EnvChip(env)],
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: 8),
            StatusDot(status, size: 7),
          ],
        ],
      ),
    );
  }
}

/// The library: a menu of its pages, with how many things each has.
class _LibraryButton extends ConsumerWidget {
  const _LibraryButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ow.colors;
    final l = context.l10n;
    final board = ref.watch(tunnelBoardProvider);
    final current = ref.watch(tabsProvider.select((s) => s.current));
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) => Consumer(
        builder: (context, ref, _) {
          final entries = libraryEntries(context, ref);
          final here = entries.any(
            (e) => current is PageTab && current.page == e.page,
          );
          final open = board.open;
          return Builder(
            builder: (context) => _RailButton(
              key: const ValueKey('rail.library'),
              tooltip: open > 0
                  ? '${l.library} · ${l.tunnels} · ${l.openCount(open)}'
                  : l.library,
              selected: here,
              onPressed: () async {
                final page = await _menuBeside<PageKind>(context, [
                  for (final e in entries)
                    PopupMenuItem<PageKind>(
                      key: ValueKey('rail.library.${e.page.name}'),
                      value: e.page,
                      height: 36,
                      child: Row(
                        children: [
                          Icon(e.icon, size: 16, color: c.textMuted),
                          const SizedBox(width: 10),
                          Expanded(child: Text(e.label)),
                          const SizedBox(width: 16),
                          Text(
                            [
                              if (e.count > 0) '${e.count}',
                              if (e.open > 0) l.openCount(e.open),
                            ].join(' · '),
                            style: monoStyle(context, size: 12),
                          ),
                        ],
                      ),
                    ),
                ]);
                if (page != null) {
                  ref.read(tabsProvider.notifier).openPage(page);
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.apps, size: 18, color: c.textMuted),
                  if (open > 0)
                    const Positioned(
                      right: -3,
                      top: -2,
                      child: StatusDot(Status.connected, size: 6),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.selected = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OwSpace.s1),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        waitDuration: OwMotion.hintSoon,
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          onTap: onPressed,
          excludeSemantics: true,
          child: FocusOutline(
            radius: ow.shape.radius + 2,
            child: Material(
              color: selected ? ow.colors.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(ow.shape.radius + 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(ow.shape.radius + 2),
                onTap: onPressed,
                child: SizedBox(
                  width: 40,
                  height: 36,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension<T extends Object> on T {
  R let<R>(R Function(T) f) => f(this);
}
