import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
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
import '../import/import_dialog.dart';
import '../tabs/drag.dart';

/// Saved hosts in their groups, a search box over them, and the actions
/// that add to them. Double-click (or Enter in the search) connects in a
/// new tab.
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({
    super.key,
    required this.searchFocus,
    this.overWindow = false,
  });

  /// The filter over the list.
  final FocusNode searchFocus;

  /// Shown over the window (the sidebar is hidden or a rail): no room for
  /// the window buttons, and a button to keep it open instead of folding.
  final bool overWindow;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final _search = TextEditingController();
  final Set<String> _collapsed = {};
  String? _selected;

  /// Opened or folded by hand; until then, folded while the start page
  /// shows (it has the favorites in the middle) and open otherwise.
  bool? _favoritesOpen;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _connect(HostView host) {
    ref.read(tabsProvider.notifier).openHost(host);
  }

  void _refresh() => ref.read(libraryProvider.notifier).refresh();

  Future<void> _favorite(HostView h, bool on) async {
    await ref.read(openWardProvider).setFavorite(id: h.id, favorite: on);
    _refresh();
  }

  Future<void> _editHost({String? id, String? groupId}) async {
    if (await showHostEditor(context, ref, id: id, groupId: groupId)) {
      _refresh();
    }
  }

  Future<void> _editGroup({String? id, String? parentId}) async {
    if (await showGroupEditor(context, ref, id: id, parentId: parentId)) {
      _refresh();
    }
  }

  Future<void> _import() async {
    await showImport(context, ref);
    _refresh();
  }

  Future<void> _delete(String id, String name, {required bool group}) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(group ? l.deleteGroupTitle(name) : l.deleteHostTitle(name)),
        content: Text(group ? l.deleteGroupBody : l.deleteHostBody),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(openWardProvider).delete(id: id);
    } catch (e) {
      if (!mounted) return;
      final inUse = '$e'.contains('jump host');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(inUse ? l.hostInUse(name) : l.deleteFailed('$e')),
        ),
      );
    }
    _refresh();
  }

  Future<void> _menu(
    Offset at,
    List<PopupMenuEntry<VoidCallback>> items,
  ) async {
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: items,
    );
    action?.call();
  }

  PopupMenuItem<VoidCallback> _item(String text, VoidCallback action) =>
      PopupMenuItem(value: action, height: 36, child: Text(text));

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final results = ref.watch(searchResultsProvider);
    final sessions = ref.watch(tabsProvider).sessions.toList();
    final ow = context.ow;
    final l = context.l10n;
    final empty = library.hosts.isEmpty && library.groups.isEmpty;
    return ColoredBox(
      color: ow.colors.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.overWindow) const WindowButtonsSpace(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: _SearchField(
              controller: _search,
              focusNode: widget.searchFocus,
              onSubmitted: () {
                final first = results?.firstOrNull;
                if (first != null) _connect(first);
              },
            ),
          ),
          Expanded(
            child: empty
                ? _Empty(onNew: () => _editHost(), onImport: _import)
                : results != null && results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      l.noResults,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ow.colors.textSubtle),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: results != null
                        ? [for (final h in results) _hostRow(h, 0, sessions)]
                        : [
                            ..._favorites(library, sessions),
                            ..._tree(library, null, 0, sessions),
                          ],
                  ),
          ),
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
                          onPressed: () => _editHost(),
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
                      _menu(at, [
                        _item(l.newGroup, () => _editGroup()),
                        _item(l.importEllipsis, _import),
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

  List<Widget> _tree(
    Library library,
    String? parent,
    int depth,
    List<TerminalController> sessions,
  ) {
    return [
      for (final g in library.groupsIn(parent)) ...[
        _groupRow(g, depth, library),
        if (!_collapsed.contains(g.id))
          ..._tree(library, g.id, depth + 1, sessions),
      ],
      for (final h in library.hostsIn(parent)) _hostRow(h, depth, sessions),
    ];
  }

  /// The favorites first, in their order; they stay in their groups too.
  List<Widget> _favorites(Library library, List<TerminalController> sessions) {
    final favorites = library.favorites;
    if (favorites.isEmpty) return const [];
    final l = context.l10n;
    final ow = context.ow;
    final start = ref.watch(tabsProvider.select((s) => s.current == null));
    final open = _favoritesOpen ?? !start;
    return [
      FocusOutline(
        radius: ow.shape.radius,
        child: Semantics(
          expanded: open,
          button: true,
          child: InkWell(
            key: const ValueKey('sidebar.favorites'),
            borderRadius: BorderRadius.circular(ow.shape.radius),
            onTap: () => setState(() => _favoritesOpen = !open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, size: 14, color: ow.colors.warn),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SectionLabel(
                      l.favorites,
                      trailing: '${favorites.length}',
                      keepCase: true,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: ow.colors.textSubtle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (open)
        for (final h in favorites) _hostRow(h, 0, sessions),
    ];
  }

  Widget _groupRow(GroupView g, int depth, Library library) {
    final open = !_collapsed.contains(g.id);
    final l = context.l10n;
    final ow = context.ow;
    return GestureDetector(
      // The menu's actions are on the row itself for screen readers.
      excludeFromSemantics: true,
      onSecondaryTapDown: (d) => _menu(d.globalPosition, [
        _item(l.newHostHere, () => _editHost(groupId: g.id)),
        _item(l.newSubgroup, () => _editGroup(parentId: g.id)),
        _item(l.editGroup, () => _editGroup(id: g.id)),
        _item(l.deleteGroup, () => _delete(g.id, g.name, group: true)),
      ]),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              setState(() => _collapsed.add(g.id)),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              setState(() => _collapsed.remove(g.id)),
        },
        child: FocusOutline(
          radius: ow.shape.radius,
          child: MergeSemantics(
            child: Semantics(
              expanded: open,
              button: true,
              customSemanticsActions: {
                CustomSemanticsAction(label: l.newHostHere): () =>
                    _editHost(groupId: g.id),
                CustomSemanticsAction(label: l.editGroup): () =>
                    _editGroup(id: g.id),
              },
              child: _groupInk(g, depth, library, open),
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupInk(GroupView g, int depth, Library library, bool open) {
    final ow = context.ow;
    return InkWell(
      borderRadius: BorderRadius.circular(ow.shape.radius),
      onTap: () => setState(() {
        open ? _collapsed.add(g.id) : _collapsed.remove(g.id);
      }),
      onDoubleTap: () => _editGroup(id: g.id),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8.0 + depth * 12, 12, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: SectionLabel(
                g.name,
                trailing: '${library.countUnder(g.id)}',
                keepCase: true,
              ),
            ),
            if (g.environment case final env?)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Semantics(label: env.name, child: EnvChip(env)),
              ),
            const SizedBox(width: 4),
            Icon(
              open ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: ow.colors.textSubtle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _hostRow(HostView h, int depth, List<TerminalController> sessions) {
    final ow = context.ow;
    final l = context.l10n;
    final selected = h.id == _selected;
    final address = h.port == 22 ? h.address : '${h.address}:${h.port}';
    final mine = [
      for (final c in sessions)
        if (c.hostId == h.id) c,
    ];
    // Dragged onto a terminal, it opens in a pane there; onto the tab bar,
    // in a tab.
    return WindowDraggable(
      data: HostDrag(h),
      subtitle: '${h.user}@$address',
      child: GestureDetector(
        excludeFromSemantics: true,
        onSecondaryTapDown: (d) {
          setState(() => _selected = h.id);
          _menu(d.globalPosition, [
            _item(l.connect, () => _connect(h)),
            _item(
              l.openSftp,
              () => ref
                  .read(tabsProvider.notifier)
                  .openSftp(hostId: h.id, label: h.label),
            ),
            _item(
              h.favorite == null ? l.addFavorite : l.removeFavorite,
              () => _favorite(h, h.favorite == null),
            ),
            _item(l.editEllipsis, () => _editHost(id: h.id)),
            _item(l.delete, () => _delete(h.id, h.label, group: false)),
          ]);
        },
        child: Padding(
          padding: EdgeInsets.only(left: depth * 12.0, bottom: 2),
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
                    _connect(h),
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                    _connect(h),
              },
              child: FocusOutline(
                child: MergeSemantics(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    customSemanticsActions: {
                      CustomSemanticsAction(label: l.connect): () =>
                          _connect(h),
                      CustomSemanticsAction(label: l.openSftp): () => ref
                          .read(tabsProvider.notifier)
                          .openSftp(hostId: h.id, label: h.label),
                      CustomSemanticsAction(label: l.editEllipsis): () =>
                          _editHost(id: h.id),
                      CustomSemanticsAction(
                        label: h.favorite == null
                            ? l.addFavorite
                            : l.removeFavorite,
                      ): () =>
                          _favorite(h, h.favorite == null),
                    },
                    child: _hostInk(h, selected, address, mine),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hostInk(
    HostView h,
    bool selected,
    String address,
    List<TerminalController> mine,
  ) {
    final ow = context.ow;
    final l = context.l10n;
    final env = h.environment;
    final system = h.system;
    return _Hovered(
      builder: (hovered) => InkWell(
        borderRadius: BorderRadius.circular(ow.shape.radius + 2),
        onTap: () => setState(() => _selected = h.id),
        onDoubleTap: () {
          setState(() => _selected = h.id);
          _connect(h);
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
                      '${h.user}@$address',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 12),
                    ),
                  ],
                ),
              ),
              for (final t in h.tags.take(2))
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Pill.tag(t),
                ),
              // On hover, the star; otherwise how its tabs are doing.
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
                    onPressed: () => _favorite(h, h.favorite == null),
                  ),
                )
              else if (mine.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _HostStatus(sessions: mine),
                ),
            ],
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
          controller: controller,
          focusNode: focusNode,
          onChanged: ref.read(searchProvider.notifier).set,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: l.filterHosts,
            prefixIcon: const Icon(Icons.filter_list, size: 16),
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

/// What is kept besides hosts: tunnels, identities, keys, snippets,
/// workspaces and trusted host keys.
class _Library extends ConsumerWidget {
  const _Library();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final board = ref.watch(tunnelBoardProvider);
    final identities = ref.watch(identitiesProvider);
    final snippets = ref.watch(snippetsProvider);
    final keys = ref.watch(keysProvider);
    final workspaces = ref.watch(workspacesProvider);
    // Read again whenever this rebuilds (a tab opens or closes): new keys
    // are trusted as connections come up.
    final known = ref.read(openWardProvider).knownHostRows(query: '').length;
    final current = ref.watch(tabsProvider.select((s) => s.current));
    bool here(PageKind page) => current is PageTab && current.page == page;
    // A count only when there is something: zeros are noise. Empty
    // entries are quieter.
    Widget count(int n) => n == 0
        ? const SizedBox.shrink()
        : Text('$n', style: monoStyle(context, size: 12));
    Widget entry({
      required String key,
      required PageKind page,
      required IconData icon,
      required String label,
      required List<Widget> trailing,
      bool empty = false,
    }) => FocusOutline(
      child: Material(
        color: here(page) ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(ow.shape.radius + 2),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(ow.shape.radius + 2),
          onTap: () => ref.read(tabsProvider.notifier).openPage(page),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(icon, size: 16, color: empty ? c.textSubtle : c.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: empty ? TextStyle(color: c.textMuted) : null,
                  ),
                ),
                ...trailing,
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: SectionLabel(l.library),
          ),
          ListenableBuilder(
            listenable: board,
            builder: (context, _) => entry(
              key: 'library.tunnels',
              page: PageKind.tunnels,
              icon: Icons.swap_horiz,
              label: l.tunnels,
              trailing: [
                if (board.open > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      l.openCount(board.open),
                      style: TextStyle(fontSize: 12, color: c.accentText),
                    ),
                  ),
                count(board.tunnels.length),
              ],
              empty: board.tunnels.isEmpty,
            ),
          ),
          entry(
            key: 'library.identities',
            page: PageKind.identities,
            icon: Icons.badge_outlined,
            label: l.identities,
            trailing: [count(identities.length)],
            empty: identities.isEmpty,
          ),
          entry(
            key: 'library.keys',
            page: PageKind.keys,
            icon: Icons.key_outlined,
            label: l.keys,
            trailing: [count(keys.length)],
            empty: keys.isEmpty,
          ),
          entry(
            key: 'library.snippets',
            page: PageKind.snippets,
            icon: Icons.terminal,
            label: l.snippets,
            trailing: [count(snippets.length)],
            empty: snippets.isEmpty,
          ),
          entry(
            key: 'library.workspaces',
            page: PageKind.workspaces,
            icon: Icons.dashboard_outlined,
            label: l.workspaces,
            trailing: [count(workspaces.length)],
            empty: workspaces.isEmpty,
          ),
          entry(
            key: 'library.knownHosts',
            page: PageKind.knownHosts,
            icon: Icons.verified_user_outlined,
            label: l.knownHosts,
            trailing: [count(known)],
            empty: known == 0,
          ),
        ],
      ),
    );
  }
}
