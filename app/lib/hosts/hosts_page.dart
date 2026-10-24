// The «Hosts» page: every saved host in its groups, a search over them,
// filters by environment, favorite, tag and system, and what each one can
// do. The sidebar keeps only what is used every day.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../home/recent.dart';
import '../l10n/l10n.dart';
import '../palette/command_palette.dart' show agoText;
import '../src/rust/api/vault.dart';
import '../tabs/drag.dart';
import '../tabs/tabs.dart';
import '../terminal/controller.dart';
import '../terminal/keys.dart';
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'host_actions.dart';
import 'sidebar.dart' show hostStatus;

class HostsPage extends ConsumerStatefulWidget {
  const HostsPage({super.key});

  @override
  ConsumerState<HostsPage> createState() => _HostsPageState();
}

/// A group (or the hosts in none) and its hosts that pass the filters.
class _Section {
  const _Section(this.group, this.depth, this.count, this.open, this.hosts);

  /// Null for the hosts in no group.
  final GroupView? group;
  final int depth;

  /// Hosts in it and under it that pass the filters.
  final int count;
  final bool open;
  final List<HostView> hosts;
}

/// Which columns the list has room for.
class _Columns {
  const _Columns(this.width)
    : address = width >= 620,
      environment = width >= 760,
      system = width >= 900;

  final double width;
  final bool address;
  final bool environment;
  final bool system;
}

class _HostsPageState extends ConsumerState<HostsPage> {
  final _query = TextEditingController();
  final Set<String> _collapsed = {};

  /// An environment, by its name.
  String? _env;
  bool _favorites = false;
  final Set<String> _tags = {};
  final Set<String> _systems = {};
  String? _selected;

  /// Cards instead of rows; the choice lasts while the app runs.
  static bool _cards = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _query.text.trim().isNotEmpty ||
      _env != null ||
      _favorites ||
      _tags.isNotEmpty ||
      _systems.isNotEmpty;

  void _clear() => setState(() {
    _query.clear();
    _env = null;
    _favorites = false;
    _tags.clear();
    _systems.clear();
  });

  /// The system's filter: unknown («?») whether connecting could not tell
  /// it or has not yet.
  static String _systemKey(HostView h) {
    final code = h.system?.code;
    return systemKnown(code) ? code! : '?';
  }

  /// What the system is called, for the column and the search.
  static String systemText(BuildContext context, HostView h) {
    final s = h.system;
    if (s == null) return '—';
    return s.name.isEmpty ? systemName(context.l10n, s.code) : s.name;
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final library = ref.watch(libraryProvider);
    // Which sessions there are, not every change of focus or panes.
    ref.watch(tabsProvider.select((s) => Object.hashAll(s.sessions)));
    final sessions = ref.read(tabsProvider).sessions.toList();
    final recent = ref.watch(recentProvider).connections;
    final actions = HostActions(context, ref);
    // When each host was last connected: the newest entry comes first.
    final last = <String, int>{};
    for (final r in recent) {
      if (r.hostId case final id?) last.putIfAbsent(id, () => r.at);
    }
    final q = _query.text.trim();
    final found = q.isEmpty
        ? null
        : ref.read(openWardProvider).search(query: q).toSet();
    final lower = q.toLowerCase();
    bool keep(HostView h) {
      if (found != null &&
          !found.contains(h.id) &&
          !(h.system != null &&
              (h.system!.code == lower ||
                  systemText(context, h).toLowerCase().contains(lower)))) {
        return false;
      }
      if (_env != null && h.environment?.name != _env) return false;
      if (_favorites && h.favorite == null) return false;
      if (_tags.isNotEmpty && !h.tags.any(_tags.contains)) return false;
      if (_systems.isNotEmpty && !_systems.contains(_systemKey(h))) {
        return false;
      }
      return true;
    }

    final filtering = _filtering;
    final counted = <String, int>{};
    int countUnder(String id) => counted[id] ??=
        library.hostsIn(id).where(keep).length +
        library.groupsIn(id).fold(0, (n, g) => n + countUnder(g.id));
    final sections = <_Section>[];
    void walk(String? parent, int depth) {
      for (final g in library.groupsIn(parent)) {
        final n = countUnder(g.id);
        if (filtering && n == 0) continue;
        // A search or a filter opens every group it finds something in.
        final open = filtering || !_collapsed.contains(g.id);
        sections.add(
          _Section(
            g,
            depth,
            n,
            open,
            open ? library.hostsIn(g.id).where(keep).toList() : const [],
          ),
        );
        if (open) walk(g.id, depth + 1);
      }
    }

    walk(null, 0);
    final loose = library.hostsIn(null).where(keep).toList();
    if (loose.isNotEmpty) {
      sections.add(_Section(null, 0, loose.length, true, loose));
    }
    final empty = library.hosts.isEmpty && library.groups.isEmpty;
    return ColoredBox(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, library, actions),
            const SizedBox(height: 14),
            if (empty)
              Expanded(child: _empty(context, actions))
            else ...[
              _search(context),
              const SizedBox(height: 12),
              _filters(context, library),
              const SizedBox(height: 12),
              Expanded(
                child: sections.isEmpty
                    ? _nothing(context)
                    : LayoutBuilder(
                        builder: (context, box) => _list(
                          context,
                          sections,
                          _Columns(box.maxWidth),
                          sessions,
                          last,
                          actions,
                          showLoose: sections.any((s) => s.group != null),
                        ),
                      ),
              ),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 10),
              _hints(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Library library, HostActions actions) {
    final l = context.l10n;
    final c = context.ow.colors;
    return LayoutBuilder(
      builder: (context, box) {
        // Narrow: the lesser buttons keep only their icon.
        final narrow = box.maxWidth < 620;
        Widget lesser(String key, IconData icon, String text, VoidCallback f) =>
            narrow
            ? IconButton(
                key: ValueKey(key),
                tooltip: text,
                onPressed: f,
                icon: Icon(icon, size: 18),
              )
            : OutlinedButton.icon(
                key: ValueKey(key),
                onPressed: f,
                icon: Icon(icon, size: 16),
                label: Text(text),
              );
        return Row(
          children: [
            Semantics(
              header: true,
              child: Text(
                l.hosts,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${library.hosts.length}',
              style: monoStyle(context, size: 13, color: c.textSubtle),
            ),
            const Spacer(),
            lesser(
              'hosts.import',
              Icons.file_download_outlined,
              l.importEllipsis,
              actions.import,
            ),
            const SizedBox(width: 8),
            lesser(
              'hosts.newGroup',
              Icons.create_new_folder_outlined,
              l.newGroup,
              () => actions.editGroup(),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('hosts.new'),
              onPressed: () => actions.editHost(),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l.newHost),
            ),
          ],
        );
      },
    );
  }

  Widget _search(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    return Row(
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  setState(_query.clear),
            },
            child: TextField(
              key: const ValueKey('hosts.search'),
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: l.hostsSearchHint,
                prefixIcon: Icon(Icons.search, size: 16, color: c.textSubtle),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(
              value: false,
              tooltip: l.hostsViewList,
              icon: Icon(
                Icons.view_list_outlined,
                key: const ValueKey('hosts.view.list'),
                size: 16,
                semanticLabel: l.hostsViewList,
              ),
            ),
            ButtonSegment(
              value: true,
              tooltip: l.hostsViewCards,
              icon: Icon(
                Icons.grid_view,
                key: const ValueKey('hosts.view.cards'),
                size: 16,
                semanticLabel: l.hostsViewCards,
              ),
            ),
          ],
          selected: {_cards},
          onSelectionChanged: (s) => setState(() => _cards = s.first),
        ),
      ],
    );
  }

  /// All, each environment, the favorites; then the tags and the systems.
  Widget _filters(BuildContext context, Library library) {
    final l = context.l10n;
    final c = context.ow.colors;
    final hosts = library.hosts;
    final envs = <String, (EnvironmentView, int)>{};
    final tags = <String, int>{};
    final systems = <String, int>{};
    for (final h in hosts) {
      if (h.environment case final e?) {
        envs[e.name] = (e, (envs[e.name]?.$2 ?? 0) + 1);
      }
      for (final t in h.tags) {
        tags[t] = (tags[t] ?? 0) + 1;
      }
      final system = _systemKey(h);
      systems[system] = (systems[system] ?? 0) + 1;
    }
    int byCount(MapEntry<String, int> a, MapEntry<String, int> b) {
      final n = b.value - a.value;
      return n != 0 ? n : a.key.compareTo(b.key);
    }

    final favorites = hosts.where((h) => h.favorite != null).length;
    Widget gap() => Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: c.border,
    );
    return Semantics(
      label: l.hostsFilters,
      container: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _FilterChip(
            key: const ValueKey('hosts.filter.all'),
            text: l.hostsAll,
            count: hosts.length,
            on: !_filtering,
            onTap: _clear,
          ),
          for (final (e, n)
              in (envs.values.toList()..sort((a, b) => b.$2 - a.$2)))
            _FilterChip(
              key: ValueKey('hosts.filter.env.${e.name}'),
              text: e.name,
              count: n,
              env: e,
              on: _env == e.name,
              onTap: () =>
                  setState(() => _env = _env == e.name ? null : e.name),
            ),
          if (favorites > 0)
            _FilterChip(
              key: const ValueKey('hosts.filter.favorites'),
              text: l.favorites,
              count: favorites,
              star: true,
              on: _favorites,
              onTap: () => setState(() => _favorites = !_favorites),
            ),
          if (tags.isNotEmpty) gap(),
          for (final t in tags.entries.toList()..sort(byCount))
            _FilterChip(
              key: ValueKey('hosts.filter.tag.${t.key}'),
              text: t.key,
              count: t.value,
              on: _tags.contains(t.key),
              onTap: () => setState(
                () => _tags.contains(t.key)
                    ? _tags.remove(t.key)
                    : _tags.add(t.key),
              ),
            ),
          // Only with some system known: «unknown» alone is all of them.
          if (systems.keys.any(systemKnown)) ...[
            gap(),
            for (final code in [
              for (final s in systemCodes)
                if (systems.containsKey(s)) s,
            ])
              _FilterChip(
                key: ValueKey('hosts.filter.system.$code'),
                text: systemName(l, code),
                system: code,
                count: systems[code]!,
                on: _systems.contains(code),
                onTap: () => setState(
                  () => _systems.contains(code)
                      ? _systems.remove(code)
                      : _systems.add(code),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<_Section> sections,
    _Columns cols,
    List<TerminalController> sessions,
    Map<String, int> last,
    HostActions actions, {
    required bool showLoose,
  }) {
    final l = context.l10n;
    List<TerminalController> mine(HostView h) => [
      for (final s in sessions)
        if (s.hostId == h.id) s,
    ];
    void select(HostView h) => setState(() => _selected = h.id);
    // A host dropped on a group goes into it; on «No group», out of any.
    Widget head(_Section s) => _GroupDrop(
      groupId: s.group?.id,
      onDrop: (h) => actions.moveToGroup(h, s.group?.id),
      child: _GroupHeader(
        key: ValueKey('hosts.group.${s.group?.name ?? ''}'),
        title: s.group?.name ?? l.hostsNoGroup,
        env: s.group?.environment,
        count: s.count,
        depth: s.depth,
        open: s.open,
        onToggle: s.group == null || _filtering
            ? null
            : () => setState(() {
                final id = s.group!.id;
                _collapsed.contains(id)
                    ? _collapsed.remove(id)
                    : _collapsed.add(id);
              }),
        onEdit: s.group == null
            ? null
            : () => actions.editGroup(id: s.group!.id),
        onMenu: s.group == null
            ? null
            : (at) => actions.menu(at, actions.groupMenu(s.group!)),
      ),
    );
    // Rows are made as they scroll into view: a thousand hosts make as many
    // widgets as fit on the screen.
    final items = <Widget Function()>[
      if (!_cards) () => _ColumnTitles(cols: cols),
      for (final s in sections) ...[
        if (s.group != null || showLoose) () => head(s),
        if (_cards && s.hosts.isNotEmpty)
          () => Padding(
            padding: EdgeInsets.fromLTRB(s.depth * 16.0, 4, 0, 8),
            child: LayoutBuilder(
              builder: (context, box) {
                final n = ((box.maxWidth + 10) / 250).floor().clamp(1, 6);
                final w = (box.maxWidth - 10 * (n - 1)) / n;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final h in s.hosts)
                      SizedBox(
                        width: w,
                        child: _HostItem(
                          host: h,
                          card: true,
                          depth: 0,
                          cols: cols,
                          sessions: mine(h),
                          last: last[h.id],
                          selected: h.id == _selected,
                          onSelect: () => select(h),
                          actions: actions,
                        ),
                      ),
                  ],
                );
              },
            ),
          )
        else
          for (final h in s.hosts)
            () => _HostItem(
              host: h,
              card: false,
              depth: s.depth,
              cols: cols,
              sessions: mine(h),
              last: last[h.id],
              selected: h.id == _selected,
              onSelect: () => select(h),
              actions: actions,
            ),
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      itemBuilder: (context, i) => items[i](),
    );
  }

  Widget _nothing(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(l.noResults, style: TextStyle(color: c.textMuted)),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('hosts.clear'),
          onPressed: _clear,
          child: Text(l.hostsClearFilters),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, HostActions actions) {
    final l = context.l10n;
    final c = context.ow.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 36, color: c.textSubtle),
            const SizedBox(height: 12),
            Text(
              l.noHostsTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l.noHostsBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, height: 1.45),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => actions.editHost(),
                  child: Text(l.newHost),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: actions.import,
                  child: Text(l.importEllipsis),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hints(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final style = TextStyle(fontSize: 12, color: c.textMuted);
    Widget hint(String keys, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyCap(keys),
        const SizedBox(width: 6),
        Text(text, style: style),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        hint('↩', l.hostsHintConnect),
        hint(isApple ? '⌥↩' : 'Alt+↩', 'SFTP'),
        hint('E', l.hostsHintEdit),
        hint('F', l.hostsHintFavorite),
        Text(l.hostsHintDrag, style: style),
      ],
    );
  }
}

/// A filter: on or off, with how many hosts it has.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.text,
    required this.count,
    required this.on,
    required this.onTap,
    this.env,
    this.star = false,
    this.system,
  });

  final String text;
  final int count;
  final bool on;
  final VoidCallback onTap;
  final EnvironmentView? env;
  final bool star;

  /// A system's code, for its logo before the name.
  final String? system;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final tint = env == null ? null : envColors(c, env!.color);
    final (fg, bg, line) = on
        ? tint != null
              ? (tint.fg, tint.soft, tint.line)
              : (c.onPrimary, c.primary, c.primary)
        : (c.text, Colors.transparent, c.control);
    final style = TextStyle(fontSize: 12.5, color: fg);
    return Semantics(
      button: true,
      selected: on,
      label: '$text, $count',
      onTap: onTap,
      excludeSemantics: true,
      child: FocusOutline(
        radius: 999,
        child: Material(
          color: bg,
          shape: StadiumBorder(side: BorderSide(color: line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tint != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tint.fg,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (star) ...[
                    Icon(Icons.star_rounded, size: 14, color: on ? fg : c.warn),
                    const SizedBox(width: 4),
                  ],
                  if (system case final code?) ...[
                    SystemGlyph(code: code, color: fg, size: 14),
                    const SizedBox(width: 5),
                  ],
                  Text(text, style: style),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: monoStyle(
                      context,
                      size: 12,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The list's column titles.
class _ColumnTitles extends StatelessWidget {
  const _ColumnTitles({required this.cols});

  final _Columns cols;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: c.textSubtle, fontSize: 12, letterSpacing: 0.6);
    Text t(String s) => Text(s.toUpperCase(), style: style, maxLines: 1);
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: _cells(
          cols,
          star: const SizedBox.shrink(),
          badge: const SizedBox.shrink(),
          name: t(l.hostsColName),
          address: t(l.hostsColAddress),
          system: t(l.hostsColSystem),
          env: t(l.hostsColEnvironment),
          dot: const SizedBox.shrink(),
          trailing: Align(
            alignment: Alignment.centerRight,
            child: t(l.hostsColLast),
          ),
        ),
      ),
    );
  }
}

/// A row's cells, in the columns there is room for.
Widget _cells(
  _Columns cols, {
  required Widget star,
  required Widget badge,
  required Widget name,
  required Widget address,
  required Widget system,
  required Widget env,
  required Widget dot,
  required Widget trailing,
  double indent = 0,
}) => Row(
  children: [
    SizedBox(width: indent),
    SizedBox(width: 28, child: star),
    const SizedBox(width: 6),
    SizedBox(width: 32, child: badge),
    const SizedBox(width: 12),
    Expanded(flex: 12, child: name),
    if (cols.address) ...[
      const SizedBox(width: 12),
      Expanded(flex: 15, child: address),
    ],
    if (cols.system) ...[
      const SizedBox(width: 12),
      SizedBox(width: 120, child: system),
    ],
    if (cols.environment) ...[
      const SizedBox(width: 12),
      SizedBox(width: 110, child: env),
    ],
    const SizedBox(width: 12),
    SizedBox(width: 10, child: dot),
    const SizedBox(width: 12),
    SizedBox(width: 196, child: trailing),
  ],
);

/// A group's title: it folds, opens its editor on a double click, and has
/// its menu on a right click.
/// Where a dragged host can be dropped to go into a group: outlined while
/// one is over it, if it is not there already.
class _GroupDrop extends StatelessWidget {
  const _GroupDrop({
    required this.groupId,
    required this.onDrop,
    required this.child,
  });

  final String? groupId;
  final void Function(HostView host) onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return DragTarget<WindowDrag>(
      onWillAcceptWithDetails: (d) =>
          d.data is HostDrag && (d.data as HostDrag).host.groupId != groupId,
      onAcceptWithDetails: (d) => onDrop((d.data as HostDrag).host),
      builder: (context, over, _) => over.isEmpty
          ? child
          : Tooltip(
              message: context.l10n.dropHereToMove,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  color: ow.colors.accentSoft.withValues(alpha: 0.35),
                  border: Border.all(color: ow.colors.accent, width: 2),
                  borderRadius: BorderRadius.circular(ow.shape.radius),
                ),
                child: child,
              ),
            ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    super.key,
    required this.title,
    required this.env,
    required this.count,
    required this.depth,
    required this.open,
    required this.onToggle,
    required this.onEdit,
    required this.onMenu,
  });

  final String title;
  final EnvironmentView? env;
  final int count;
  final int depth;
  final bool open;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final ValueChanged<Offset>? onMenu;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final row = Padding(
      padding: EdgeInsets.fromLTRB(8.0 + depth * 16, 14, 8, 6),
      child: Row(
        children: [
          Icon(
            open ? Icons.expand_more : Icons.chevron_right,
            size: 16,
            color: onToggle == null ? Colors.transparent : c.textSubtle,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
            ),
          ),
          if (env case final env?) ...[
            const SizedBox(width: 8),
            Semantics(label: shownEnv(l, env).name, child: EnvChip(env)),
          ],
          const SizedBox(width: 8),
          Text('$count', style: monoStyle(context, size: 12)),
        ],
      ),
    );
    return GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTapDown: onMenu == null
          ? null
          : (d) => onMenu!(d.globalPosition),
      child: CallbackShortcuts(
        bindings: {
          if (onToggle != null && open)
            const SingleActivator(LogicalKeyboardKey.arrowLeft): onToggle!,
          if (onToggle != null && !open)
            const SingleActivator(LogicalKeyboardKey.arrowRight): onToggle!,
        },
        child: FocusOutline(
          radius: ow.shape.radius,
          child: MergeSemantics(
            child: Semantics(
              header: true,
              expanded: onToggle == null ? null : open,
              button: onToggle != null,
              customSemanticsActions: {
                CustomSemanticsAction(label: l.editGroup): ?onEdit,
              },
              child: InkWell(
                borderRadius: BorderRadius.circular(ow.shape.radius),
                canRequestFocus: onToggle != null,
                onTap: onToggle,
                onDoubleTap: onEdit,
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A host as a row or a card: a click picks it, a double click or Enter
/// connects; ⌥Enter opens its files, E its editor, F stars it. Dragged to
/// the tab bar, it opens there.
class _HostItem extends StatefulWidget {
  const _HostItem({
    required this.host,
    required this.card,
    required this.depth,
    required this.cols,
    required this.sessions,
    required this.last,
    required this.selected,
    required this.onSelect,
    required this.actions,
  });

  final HostView host;
  final bool card;
  final int depth;
  final _Columns cols;

  /// Its open sessions.
  final List<TerminalController> sessions;

  /// When it was last connected, in ms since the epoch.
  final int? last;
  final bool selected;
  final VoidCallback onSelect;
  final HostActions actions;

  @override
  State<_HostItem> createState() => _HostItemState();
}

class _HostItemState extends State<_HostItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final h = widget.host;
    final a = widget.actions;
    final radius = widget.card ? ow.shape.radiusLarge : ow.shape.radius + 2;
    final item = InkWell(
      key: ValueKey('hosts.${widget.card ? 'card' : 'row'}.${h.label}'),
      borderRadius: BorderRadius.circular(radius),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: widget.onSelect,
      onDoubleTap: () {
        widget.onSelect();
        a.connect(h);
      },
      child: widget.card ? _card(context) : _row(context),
    );
    return WindowDraggable(
      data: HostDrag(h),
      subtitle: hostAddress(h),
      child: GestureDetector(
        excludeFromSemantics: true,
        onSecondaryTapDown: (d) {
          widget.onSelect();
          a.menu(d.globalPosition, a.hostMenu(h));
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  a.connect(h),
              const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                  a.connect(h),
              const SingleActivator(LogicalKeyboardKey.enter, alt: true): () =>
                  a.sftp(h),
              const CharacterActivator('e'): () => a.editHost(id: h.id),
              const CharacterActivator('f'): () => a.toggleFavorite(h),
            },
            child: FocusOutline(
              radius: radius,
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.card ? 0 : 2),
                child: Material(
                  color: widget.selected
                      ? c.selected
                      : widget.card
                      ? c.raised
                      : _hovered
                      ? c.hover
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius),
                    side: widget.card
                        ? BorderSide(color: c.control)
                        : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MergeSemantics(
                    child: Semantics(
                      button: true,
                      selected: widget.selected,
                      customSemanticsActions: {
                        CustomSemanticsAction(label: l.connect): () =>
                            a.connect(h),
                        CustomSemanticsAction(label: l.openSftp): () =>
                            a.sftp(h),
                        CustomSemanticsAction(label: l.editEllipsis): () =>
                            a.editHost(id: h.id),
                        CustomSemanticsAction(
                          label: h.favorite == null
                              ? l.addFavorite
                              : l.removeFavorite,
                        ): () =>
                            a.toggleFavorite(h),
                      },
                      child: item,
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

  Widget _star(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final h = widget.host;
    final on = h.favorite != null;
    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        key: ValueKey('hosts.star.${h.label}'),
        tooltip: on ? l.removeFavorite : l.addFavorite,
        padding: EdgeInsets.zero,
        iconSize: 17,
        color: on ? c.warn : c.textSubtle,
        icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded),
        onPressed: () => widget.actions.toggleFavorite(h),
      ),
    );
  }

  /// How it is doing and when it was last used; on hover or focus, its
  /// actions instead.
  Widget _trailing(BuildContext context, {required bool compact}) {
    final l = context.l10n;
    final c = context.ow.colors;
    final h = widget.host;
    final a = widget.actions;
    if (_hovered || _focused) {
      Widget small(String key, IconData icon, String tip, VoidCallback f) =>
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: ValueKey('hosts.$key.${h.label}'),
              tooltip: tip,
              padding: EdgeInsets.zero,
              iconSize: 15,
              style: IconButton.styleFrom(
                side: BorderSide(color: c.control),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.ow.shape.radius),
                ),
              ),
              icon: Icon(icon),
              onPressed: f,
            ),
          );
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            key: ValueKey('hosts.connect.${h.label}'),
            onPressed: () => a.connect(h),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l.connect),
          ),
          if (!compact) ...[
            const SizedBox(width: 6),
            small('sftp', Icons.folder_outlined, l.openSftp, () => a.sftp(h)),
            const SizedBox(width: 4),
            small(
              'edit',
              Icons.edit_outlined,
              l.editEllipsis,
              () => a.editHost(id: h.id),
            ),
          ],
        ],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge(widget.sessions),
      builder: (context, _) {
        final live = hostStatus(widget.sessions) == Status.connected;
        final last = widget.last;
        return Text(
          live
              ? l.hostsOpenNow
              : last == null
              ? '—'
              : agoText(
                  l,
                  DateTime.now().difference(
                    DateTime.fromMillisecondsSinceEpoch(last),
                  ),
                ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 12, color: c.textMuted),
        );
      },
    );
  }

  Widget _dot() => widget.sessions.isEmpty
      ? const SizedBox.shrink()
      : ListenableBuilder(
          listenable: Listenable.merge(widget.sessions),
          builder: (context, _) =>
              Center(child: StatusDot(hostStatus(widget.sessions))),
        );

  Widget _row(BuildContext context) {
    final c = context.ow.colors;
    final h = widget.host;
    final env = h.environment;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _cells(
          widget.cols,
          indent: widget.depth * 16.0,
          star: _star(context),
          badge: SystemBadge(code: h.system?.code, env: env),
          name: Row(
            children: [
              Flexible(
                child: Text(
                  h.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              for (final t in h.tags.take(2))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Pill.tag(t),
                ),
            ],
          ),
          address: Text(
            hostAddress(h),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(context, size: 12),
          ),
          system: Text(
            _HostsPageState.systemText(context, h),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: c.textMuted),
          ),
          env: Align(
            alignment: Alignment.centerLeft,
            child: env == null
                ? Text('—', style: TextStyle(color: c.textSubtle))
                : Semantics(
                    label: shownEnv(context.l10n, env).name,
                    child: EnvChip(env),
                  ),
          ),
          dot: _dot(),
          trailing: Align(
            alignment: Alignment.centerRight,
            child: _trailing(context, compact: false),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final h = widget.host;
    final env = h.environment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 2,
          color: env == null ? c.border : envColors(c, env.color).fg,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SystemBadge(code: h.system?.code, env: env, size: 28),
                  const Spacer(),
                  _dot(),
                  const SizedBox(width: 6),
                  _star(context),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                h.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                hostAddress(h),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context, size: 12),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 28,
                child: Row(
                  children: [
                    if (env != null)
                      Semantics(
                        label: shownEnv(l, env).name,
                        child: EnvChip(env),
                      )
                    else
                      Text(
                        l.envNoneNote,
                        style: TextStyle(fontSize: 12, color: c.textSubtle),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _trailing(context, compact: true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
