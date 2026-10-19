import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../home/recent.dart';
import '../l10n/l10n.dart';
import '../palette/command_palette.dart' show agoText;
import '../src/rust/api/vault.dart';
import '../tabs/tab_strip.dart' show pageIcon, tabTitle;
import '../tabs/tabs.dart';
import '../terminal/controller.dart';
import '../identities/identities.dart';
import '../keys/keys.dart';
import '../snippets/snippets.dart';
import '../tunnels/tunnels.dart';
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/chrome.dart';
import '../window/shortcuts.dart';
import '../window/sidebar_state.dart';
import '../workspaces/workspaces.dart';
import 'editors.dart';
import 'host_actions.dart';
import '../tabs/drag.dart';

/// What is used every day: the open tabs, the favorites and the recent
/// connections, with a search over every host (Enter connects, to an
/// address too). Every host is on the Hosts page, one click below; the
/// library is a row of icons under it.
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({
    super.key,
    required this.searchFocus,
    this.overWindow = false,
  });

  /// The search over the hosts.
  final FocusNode searchFocus;

  /// Shown over the window (the sidebar is hidden or a rail): no room for
  /// the window buttons, and a button to keep it open instead of folding.
  final bool overWindow;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final _search = TextEditingController();
  String? _selected;

  /// Each section opened or folded by hand; until then the open tabs show,
  /// and the favorites and recent ones fold while the start page shows
  /// them in the middle.
  bool? _openShown;
  bool? _favoritesShown;
  bool? _recentShown;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  HostActions get _actions => HostActions(context, ref);

  /// What was typed, as an address, if it looks like one.
  QuickTarget? _typed(String text) =>
      RegExp(r'[@.:]').hasMatch(text) ? QuickTarget.parse(text.trim()) : null;

  void _clearSearch() {
    _search.clear();
    ref.read(searchProvider.notifier).set('');
  }

  /// Enter in the search: the first host found, or the address typed.
  void _submit(List<HostView>? results) {
    final first = results?.firstOrNull;
    if (first != null) return _actions.connect(first);
    final target = _typed(_search.text);
    if (target == null) return;
    ref.read(tabsProvider.notifier).openAddress(target);
    _clearSearch();
  }

  Future<void> _saveAddress(QuickTarget t) async {
    final saved = await showHostEditor(
      context,
      ref,
      draft: HostSpec(
        label: t.address,
        address: t.address,
        settings: SettingsSpec(user: t.user, port: t.port),
      ),
    );
    if (saved) _actions.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final results = ref.watch(searchResultsProvider);
    final sessions = ref.watch(tabsProvider).sessions.toList();
    final start = ref.watch(tabsProvider.select((s) => s.current == null));
    final ow = context.ow;
    final l = context.l10n;
    final actions = _actions;
    final empty = library.hosts.isEmpty && library.groups.isEmpty;
    final Widget body;
    if (empty) {
      body = _Empty(onNew: () => actions.editHost(), onImport: actions.import);
    } else if (results != null && results.isEmpty) {
      final target = _typed(_search.text);
      body = Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (target != null)
              _addressRow(
                target,
                key: 'sidebar.connectTyped',
                title: l.connectToAddress(target.label),
                subtitle: l.notSaved,
                trailing: const KeyCap('↩'),
                clearAfter: true,
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l.noResults,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ow.colors.textSubtle),
                ),
              ),
          ],
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: results != null
            ? [for (final h in results) _hostRow(h, sessions)]
            : [
                _OpenTabs(
                  shown: _openShown ?? true,
                  onToggle: (shown) => setState(() => _openShown = !shown),
                ),
                ..._favorites(library, sessions, start),
                ..._recent(library, sessions, start),
              ],
      );
    }
    return ColoredBox(
      color: ow.colors.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.overWindow) const WindowButtonsSpace(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: _SearchField(
              controller: _search,
              focusNode: widget.searchFocus,
              onSubmitted: () => _submit(results),
            ),
          ),
          Expanded(child: body),
          if (!empty) const _HostsEntry(),
          const _Library(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: ow.colors.border)),
            ),
            child: Row(
              children: [
                // When empty, the empty state has its own button.
                Expanded(
                  child: empty
                      ? const SizedBox.shrink()
                      : OutlinedButton.icon(
                          onPressed: () => actions.editHost(),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(l.newHost),
                        ),
                ),
                const SizedBox(width: 6),
                Builder(
                  builder: (context) => IconButton(
                    tooltip: l.moreActions,
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onPressed: () {
                      final box = context.findRenderObject()! as RenderBox;
                      final at = box.localToGlobal(
                        Offset(0, box.size.height + 4),
                      );
                      actions.menu(at, [
                        actions.item(l.newGroup, () => actions.editGroup()),
                        actions.item(l.importEllipsis, actions.import),
                      ]);
                    },
                  ),
                ),
                IconButton(
                  tooltip: l.settings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  onPressed: () => ref
                      .read(tabsProvider.notifier)
                      .openPage(PageKind.settings),
                ),
                if (widget.overWindow)
                  IconButton(
                    key: const ValueKey('sidebar.pin'),
                    tooltip: withKeys(l.pinSidebar, sidebarKeys(l)),
                    icon: const Icon(Icons.push_pin_outlined, size: 18),
                    onPressed: ref.read(sidebarProvider.notifier).toggle,
                  )
                else
                  IconButton(
                    key: const ValueKey('sidebar.fold'),
                    tooltip: withKeys(l.foldSidebar, sidebarKeys(l)),
                    icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                    onPressed: ref.read(sidebarProvider.notifier).toggle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The favorites, in their order; with none yet, how to have them.
  List<Widget> _favorites(
    Library library,
    List<TerminalController> sessions,
    bool start,
  ) {
    final favorites = library.favorites;
    final l = context.l10n;
    final ow = context.ow;
    final shown = _favoritesShown ?? (favorites.isEmpty || !start);
    return [
      _SectionHeader(
        key: const ValueKey('sidebar.favorites'),
        label: l.favorites,
        count: favorites.length,
        shown: shown,
        lead: Icon(Icons.star_rounded, size: 14, color: ow.colors.warn),
        onToggle: () => setState(() => _favoritesShown = !shown),
      ),
      if (shown && favorites.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Text(
            l.favoritesEmptyShort,
            style: TextStyle(fontSize: 12, color: ow.colors.textSubtle),
          ),
        ),
      if (shown)
        for (final h in favorites) _hostRow(h, sessions),
    ];
  }

  /// The last places connected to that are not already at hand (open, or
  /// a favorite), newest first.
  List<Widget> _recent(
    Library library,
    List<TerminalController> sessions,
    bool start,
  ) {
    final l = context.l10n;
    final recent = ref.watch(recentProvider).connections;
    final open = {for (final s in sessions) ?s.hostId};
    final openAddresses = {for (final s in sessions) ?s.target?.label};
    final rows = <Widget>[];
    for (final r in recent) {
      if (rows.length == 5) break;
      if (r.hostId case final id?) {
        final h = library.host(id);
        if (h == null || h.favorite != null || open.contains(id)) continue;
        rows.add(_hostRow(h, sessions, at: r.at));
      } else if (r.address case final a?) {
        final t = QuickTarget.parse(a);
        if (t == null || openAddresses.contains(t.label)) continue;
        rows.add(
          _addressRow(
            t,
            key: 'sidebar.recent.${t.label}',
            title: t.label,
            subtitle: l.notSaved,
            trailing: _ago(r.at),
          ),
        );
      }
    }
    if (rows.isEmpty) return const [];
    final shown = _recentShown ?? !start;
    return [
      _SectionHeader(
        key: const ValueKey('sidebar.recent'),
        label: l.paletteRecent,
        count: rows.length,
        shown: shown,
        onToggle: () => setState(() => _recentShown = !shown),
      ),
      if (shown) ...rows,
    ];
  }

  Widget _ago(int at) => Text(
    agoText(
      context.l10n,
      DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)),
    ),
    style: TextStyle(fontSize: 12, color: context.ow.colors.textMuted),
  );

  /// An address connected to without saving it: a double click or Enter
  /// connects again; its menu saves it.
  Widget _addressRow(
    QuickTarget t, {
    required String key,
    required String title,
    required String subtitle,
    required Widget trailing,
    bool clearAfter = false,
  }) {
    final ow = context.ow;
    final l = context.l10n;
    void connect() {
      ref.read(tabsProvider.notifier).openAddress(t);
      if (clearAfter) _clearSearch();
    }

    final actions = _actions;
    return GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTapDown: (d) => actions.menu(d.globalPosition, [
        actions.item(l.connect, connect),
        actions.item(l.saveAsHost, () => _saveAddress(t)),
      ]),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): connect,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): connect,
          },
          child: FocusOutline(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(ow.shape.radius + 2),
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  customSemanticsActions: {
                    CustomSemanticsAction(label: l.connect): connect,
                    CustomSemanticsAction(label: l.saveAsHost): () =>
                        _saveAddress(t),
                  },
                  child: InkWell(
                    key: ValueKey(key),
                    borderRadius: BorderRadius.circular(ow.shape.radius + 2),
                    onTap: clearAfter ? connect : null,
                    onDoubleTap: clearAfter ? null : connect,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          const SystemBadge(code: '?'),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: monoStyle(context, size: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          trailing,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A saved host: a click picks it, a double click or Enter connects in a
  /// new tab; dragged onto a terminal it opens in a pane there. `at`: when
  /// it was last connected, for the recent ones.
  Widget _hostRow(HostView h, List<TerminalController> sessions, {int? at}) {
    final ow = context.ow;
    final l = context.l10n;
    final selected = h.id == _selected;
    final actions = _actions;
    final mine = [
      for (final c in sessions)
        if (c.hostId == h.id) c,
    ];
    return WindowDraggable(
      data: HostDrag(h),
      subtitle: hostAddress(h),
      child: GestureDetector(
        excludeFromSemantics: true,
        onSecondaryTapDown: (d) {
          setState(() => _selected = h.id);
          actions.menu(d.globalPosition, actions.hostMenu(h));
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: selected ? ow.colors.selected : Colors.transparent,
            shadowColor: Colors.black26,
            elevation: selected && !ow.colors.dark ? 1 : 0,
            borderRadius: BorderRadius.circular(ow.shape.radius + 2),
            // Enter connects; the row is named by its status, label and
            // address, with «connect» among its actions.
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    actions.connect(h),
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                    actions.connect(h),
              },
              child: FocusOutline(
                child: MergeSemantics(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    customSemanticsActions: {
                      CustomSemanticsAction(label: l.connect): () =>
                          actions.connect(h),
                      CustomSemanticsAction(label: l.openSftp): () =>
                          actions.sftp(h),
                      CustomSemanticsAction(label: l.editEllipsis): () =>
                          actions.editHost(id: h.id),
                      CustomSemanticsAction(
                        label: h.favorite == null
                            ? l.addFavorite
                            : l.removeFavorite,
                      ): () =>
                          actions.toggleFavorite(h),
                    },
                    child: _hostInk(h, mine, at),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hostInk(HostView h, List<TerminalController> mine, int? at) {
    final ow = context.ow;
    final l = context.l10n;
    final env = h.environment;
    final system = h.system;
    final actions = _actions;
    return _Hovered(
      builder: (hovered) => InkWell(
        key: ValueKey('sidebar.host.${h.label}'),
        borderRadius: BorderRadius.circular(ow.shape.radius + 2),
        onTap: () => setState(() => _selected = h.id),
        onDoubleTap: () {
          setState(() => _selected = h.id);
          actions.connect(h);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              SystemBadge(code: system?.code, env: env),
              // Read with the row: «Debian 12, Producción».
              Semantics(
                label: [
                  if (system != null)
                    system.name.isEmpty
                        ? systemName(l, system.code)
                        : system.name,
                  ?env?.name,
                ].join(', '),
                child: const SizedBox(width: 10),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hostAddress(h),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 12),
                    ),
                  ],
                ),
              ),
              // On hover, the star; otherwise how its tabs are doing, or
              // when it was last used.
              if (hovered)
                SizedBox.square(
                  dimension: 26,
                  child: IconButton(
                    key: ValueKey('host.favorite.${h.label}'),
                    tooltip: h.favorite == null
                        ? l.addFavorite
                        : l.removeFavorite,
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    color: h.favorite == null
                        ? ow.colors.textSubtle
                        : ow.colors.warn,
                    icon: Icon(
                      h.favorite == null
                          ? Icons.star_outline_rounded
                          : Icons.star_rounded,
                    ),
                    onPressed: () => actions.toggleFavorite(h),
                  ),
                )
              else if (mine.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _HostStatus(sessions: mine),
                )
              else if (at != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _ago(at),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section's title: it folds and opens its rows.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.label,
    required this.count,
    required this.shown,
    required this.onToggle,
    this.lead,
  });

  final String label;
  final int count;
  final bool shown;
  final VoidCallback onToggle;
  final Widget? lead;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return FocusOutline(
      radius: ow.shape.radius,
      child: Semantics(
        expanded: shown,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(ow.shape.radius),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
            child: Row(
              children: [
                if (lead != null) ...[lead!, const SizedBox(width: 6)],
                Expanded(child: SectionLabel(label, trailing: '$count')),
                const SizedBox(width: 4),
                Icon(
                  shown ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: ow.colors.textSubtle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The open terminal and file tabs, one row each; local shells (and tabs
/// of the same host) with the same name go in one row, «Local × 4», that
/// goes through them.
class _OpenTabs extends ConsumerWidget {
  const _OpenTabs({required this.shown, required this.onToggle});

  final bool shown;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final tabs = state.tabs;
    final listenable = Listenable.merge([
      for (final t in tabs)
        ...switch (t) {
          SessionTab(:final panes) => [panes, ...panes.controllers],
          SftpTab(:final controller) => [controller],
          PageTab() => const <Listenable>[],
        },
    ]);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final rows = <String, List<int>>{};
        for (final (i, t) in tabs.indexed) {
          final key = switch (t) {
            SessionTab(:final panes) when !panes.isSplit =>
              switch (panes.active.controller) {
                final c? =>
                  'session:${c.hostId ?? c.target?.label ?? ''}:'
                      '${tabTitle(context, t)}',
                null => 'tab:$i',
              },
            SessionTab() || SftpTab() => 'tab:$i',
            PageTab() => null,
          };
          if (key != null) rows.putIfAbsent(key, () => []).add(i);
        }
        if (rows.isEmpty) return const SizedBox.shrink();
        final l = context.l10n;
        final count = rows.values.fold(0, (n, r) => n + r.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              key: const ValueKey('sidebar.open'),
              label: l.openSection,
              count: count,
              shown: shown,
              onToggle: () => onToggle(shown),
            ),
            if (shown)
              for (final indices in rows.values)
                _OpenRow(indices: indices, state: state),
          ],
        );
      },
    );
  }
}

class _OpenRow extends ConsumerWidget {
  const _OpenRow({required this.indices, required this.state});

  /// The tabs it stands for, in their order.
  final List<int> indices;
  final TabsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final first = state.tabs[indices.first];
    final title = tabTitle(context, first);
    final controllers = [
      for (final i in indices)
        if (state.tabs[i] case SessionTab(:final panes)) ...panes.controllers,
    ];
    final env = tabHost(first, library)?.environment;
    final lead = tabBadge(first, library);
    final selected = indices.contains(state.active);
    final status = controllers.isEmpty ? null : hostStatus(controllers);
    void open() {
      // Through the tabs of the row, one after another.
      final at = indices.indexOf(state.active);
      tabs.select(at < 0 ? indices.first : indices[(at + 1) % indices.length]);
    }

    void close() {
      for (final i in indices.reversed) {
        tabs.close(i);
      }
    }

    final closeText = indices.length == 1
        ? l.closeTab
        : l.closeTabs(indices.length);
    return GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTapDown: (d) async {
        final action = await showMenu<VoidCallback>(
          context: context,
          position: RelativeRect.fromLTRB(
            d.globalPosition.dx,
            d.globalPosition.dy,
            d.globalPosition.dx,
            d.globalPosition.dy,
          ),
          items: [
            PopupMenuItem(value: close, height: 36, child: Text(closeText)),
          ],
        );
        action?.call();
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: FocusOutline(
          child: Material(
            color: selected ? c.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(ow.shape.radius + 2),
            child: Semantics(
              button: true,
              selected: selected,
              label: [
                title,
                ?env?.name,
                if (indices.length > 1) l.openTabsCount(indices.length),
              ].join(', '),
              customSemanticsActions: {
                CustomSemanticsAction(label: closeText): close,
              },
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('sidebar.open.$title'),
                borderRadius: BorderRadius.circular(ow.shape.radius + 2),
                onTap: open,
                child: SizedBox(
                  height: 32,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        lead,
                        const SizedBox(width: 9),
                        // The name and its mark together; the count and
                        // how it is doing, at the end.
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (env != null) ...[
                                const SizedBox(width: 8),
                                EnvChip(env),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (indices.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '× ${indices.length}',
                              style: monoStyle(context, size: 12),
                            ),
                          ),
                        if (status != null) StatusDot(status, size: 7),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The saved host a tab is connected to, if it is one.
HostView? tabHost(OpenTab tab, Library library) {
  final id = switch (tab) {
    SessionTab(:final panes) =>
      (panes.active.controller ?? panes.controllers.firstOrNull)?.hostId,
    SftpTab(:final controller) => controller.hostId,
    PageTab() => null,
  };
  return id == null ? null : library.host(id);
}

/// A tab's mark: its host's monogram, tinted by its environment; a folder
/// for its files, the panes' glyph when split, a shell for a local one and
/// «?» for an address not saved.
Widget tabBadge(OpenTab tab, Library library, {double size = 22}) {
  final host = tabHost(tab, library);
  final env = host?.environment;
  return switch (tab) {
    SftpTab() => SystemBadge(icon: Icons.folder_outlined, env: env, size: size),
    SessionTab(:final panes) when panes.isSplit => SystemBadge(
      icon: Icons.vertical_split_outlined,
      env: env,
      size: size,
    ),
    SessionTab(:final panes) => switch (panes.active.controller ??
        panes.controllers.firstOrNull) {
      final c? when c.isLocal => SystemBadge(icon: Icons.terminal, size: size),
      final c? when c.hostId == null => SystemBadge(code: '?', size: size),
      _ => SystemBadge(code: host?.system?.code, env: env, size: size),
    },
    PageTab(:final page) => SystemBadge(icon: pageIcon(page), size: size),
  };
}

/// Every host, on their page: how many and in how many groups.
class _HostsEntry extends ConsumerWidget {
  const _HostsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    final current = ref.watch(tabsProvider.select((s) => s.current));
    final here = current is PageTab && current.page == PageKind.hosts;
    final summary = l.hostsSummary(library.hosts.length, library.groups.length);
    final radius = BorderRadius.circular(ow.shape.radiusLarge);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Tooltip(
        message: withKeys(l.shortcutHosts, hostsKeys(l)),
        waitDuration: const Duration(milliseconds: 500),
        child: Semantics(
          button: true,
          selected: here,
          label: '${l.hosts}, $summary',
          excludeSemantics: true,
          child: FocusOutline(
            radius: ow.shape.radiusLarge,
            child: Material(
              color: here ? c.selected : c.raised,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: here ? c.accent : c.border),
              ),
              child: InkWell(
                key: const ValueKey('sidebar.hosts'),
                borderRadius: radius,
                onTap: () =>
                    ref.read(tabsProvider.notifier).openPage(PageKind.hosts),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.dns_outlined, size: 17, color: c.accentText),
                      const SizedBox(width: 10),
                      Text(
                        l.hosts,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                        ),
                      ),
                      KeyCap(hostsKeys(l)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 16, color: c.textSubtle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the mouse is over its child.
class _Hovered extends StatefulWidget {
  const _Hovered({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_Hovered> createState() => _HoveredState();
}

class _HoveredState extends State<_Hovered> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(_hovered),
  );
}

/// A host's mark: how its open tabs are doing, if it has any.
class _HostStatus extends StatelessWidget {
  const _HostStatus({required this.sessions});

  final List<TerminalController> sessions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(sessions),
      builder: (context, _) {
        final l = context.l10n;
        final status = hostStatus(sessions);
        return Tooltip(
          message: switch (status) {
            Status.connected => l.statusConnected,
            Status.connecting => l.statusConnecting,
            Status.failed => l.statusFailed,
            _ => l.statusIdle,
          },
          child: StatusDot(status),
        );
      },
    );
  }
}

/// The best of a host's sessions: connected wins over connecting, which
/// wins over a failure.
Status hostStatus(Iterable<TerminalController> sessions) {
  var best = Status.idle;
  for (final c in sessions) {
    final s = tabStatus(c);
    if (s == Status.connected) return s;
    if (s == Status.connecting) best = s;
    if (s == Status.failed && best == Status.idle) best = s;
  }
  return best;
}

/// One session's mark.
Status tabStatus(TerminalController c) => switch (c.phase) {
  Phase.connecting || Phase.reconnecting => Status.connecting,
  Phase.connected ||
  Phase.running => c.stalledSince != null ? Status.warning : Status.connected,
  Phase.closed =>
    c.closed?.failure != null || c.error != null ? Status.failed : Status.idle,
};

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final l = context.l10n;
    return Consumer(
      builder: (context, ref, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): onSubmitted,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            controller.clear();
            ref.read(searchProvider.notifier).set('');
          },
        },
        child: TextField(
          key: const ValueKey('sidebar.search'),
          controller: controller,
          focusNode: focusNode,
          onChanged: ref.read(searchProvider.notifier).set,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: l.sidebarSearchHint,
            prefixIcon: const Icon(Icons.search, size: 16),
            prefixIconConstraints: const BoxConstraints(minWidth: 34),
            contentPadding: const EdgeInsets.symmetric(vertical: 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ow.shape.control),
              borderSide: BorderSide(color: ow.colors.control),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ow.shape.control),
              borderSide: BorderSide(color: ow.colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ow.shape.control),
              borderSide: BorderSide(color: ow.colors.accent, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onNew, required this.onImport});

  final VoidCallback onNew;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final l = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_outlined, size: 30, color: ow.colors.textSubtle),
          const SizedBox(height: 10),
          Text(l.noHostsTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            l.noHostsBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: ow.colors.textMuted, height: 1.45),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 200,
            child: FilledButton(onPressed: onNew, child: Text(l.newHost)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 200,
            child: OutlinedButton(
              onPressed: onImport,
              child: Text(l.importEllipsis),
            ),
          ),
        ],
      ),
    );
  }
}

/// A library page: its icon, name and how many things it has.
typedef LibraryEntry = ({
  PageKind page,
  IconData icon,
  String label,
  int count,
  int open,
});

/// The library's pages and what is in each; tunnels say how many are open.
/// From a build that listens to the tunnel board.
List<LibraryEntry> libraryEntries(BuildContext context, WidgetRef ref) {
  final l = context.l10n;
  final board = ref.watch(tunnelBoardProvider);
  // Read again whenever this rebuilds (a tab opens or closes): new keys
  // are trusted as connections come up.
  final known = ref.read(openWardProvider).knownHostRows(query: '').length;
  return [
    (
      page: PageKind.tunnels,
      icon: Icons.swap_horiz,
      label: l.tunnels,
      count: board.tunnels.length,
      open: board.open,
    ),
    (
      page: PageKind.identities,
      icon: Icons.badge_outlined,
      label: l.identities,
      count: ref.watch(identitiesProvider).length,
      open: 0,
    ),
    (
      page: PageKind.keys,
      icon: Icons.key_outlined,
      label: l.keys,
      count: ref.watch(keysProvider).length,
      open: 0,
    ),
    (
      page: PageKind.snippets,
      icon: Icons.terminal,
      label: l.snippets,
      count: ref.watch(snippetsProvider).length,
      open: 0,
    ),
    (
      page: PageKind.workspaces,
      icon: Icons.dashboard_outlined,
      label: l.workspaces,
      count: ref.watch(workspacesProvider).length,
      open: 0,
    ),
    (
      page: PageKind.knownHosts,
      icon: Icons.verified_user_outlined,
      label: l.knownHosts,
      count: known,
      open: 0,
    ),
  ];
}

/// «Túneles · 3 · 1 abierto»: zeros are noise.
String libraryEntryText(BuildContext context, LibraryEntry e) => [
  e.label,
  if (e.count > 0) '${e.count}',
  if (e.open > 0) context.l10n.openCount(e.open),
].join(' · ');

/// What is kept besides hosts, in one row of icons: tunnels, identities,
/// keys, snippets, workspaces and trusted host keys. Each says its name
/// and how many on hover.
class _Library extends ConsumerWidget {
  const _Library();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final board = ref.watch(tunnelBoardProvider);
    final current = ref.watch(tabsProvider.select((s) => s.current));
    bool here(PageKind page) => current is PageTab && current.page == page;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: SectionLabel(l.library),
          ),
          // Again as tunnels open and close.
          ListenableBuilder(
            listenable: board,
            builder: (context, _) => Consumer(
              builder: (context, ref, _) => Row(
                children: [
                  for (final e in libraryEntries(context, ref))
                    Expanded(
                      child: _LibraryButton(
                        entry: e,
                        selected: here(e.page),
                        onPressed: () =>
                            ref.read(tabsProvider.notifier).openPage(e.page),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryButton extends StatelessWidget {
  const _LibraryButton({
    required this.entry,
    required this.selected,
    required this.onPressed,
  });

  final LibraryEntry entry;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final e = entry;
    final text = libraryEntryText(context, e);
    final radius = BorderRadius.circular(ow.shape.radius + 2);
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 300),
      child: Semantics(
        button: true,
        selected: selected,
        label: text,
        excludeSemantics: true,
        child: FocusOutline(
          radius: ow.shape.radius + 2,
          child: Material(
            color: selected ? c.selected : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              key: ValueKey('library.${e.page.name}'),
              borderRadius: radius,
              onTap: onPressed,
              child: SizedBox(
                height: 34,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        e.icon,
                        size: 17,
                        color: selected
                            ? c.text
                            : e.count == 0
                            ? c.textSubtle
                            : c.textMuted,
                      ),
                      if (e.open > 0)
                        const Positioned(
                          right: -4,
                          top: -3,
                          child: StatusDot(Status.connected, size: 6),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
