// The command palette (⌘K, also ⌘P and ⌘⇧P; Ctrl+Shift+K or Ctrl+Shift+P
// elsewhere): the open tabs, recent connections, everything the window
// does, the saved hosts and workspaces, the snippets and the commands run
// before, found by typing a few letters. `>` first: only the actions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/match.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../history/history.dart';
import '../home/recent.dart';
import '../hosts/editors.dart';
import '../import/import_dialog.dart';
import '../keys/key_dialogs.dart';
import '../l10n/l10n.dart';
import '../snippets/palette.dart';
import '../snippets/snippets.dart';
import '../src/rust/api/vault.dart' show HostView;
import '../tabs/tab_strip.dart' show pageIcon, tabTitle;
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../welcome/whats_new.dart';
import '../window/shortcuts.dart';
import '../window/sidebar_state.dart';
import '../workspaces/workspaces.dart';
import '../workspaces/workspaces_page.dart';

/// In the order they are listed.
enum _Kind { tab, recent, host, snippet, history, workspace, action }

/// One thing the palette can do.
class _Entry {
  _Entry({
    required this.kind,
    required this.title,
    required this.icon,
    required this.run,
    this.subtitle,
    this.keys,
    this.pill,
    this.history,
    this.host,
    this.id,
    this.rank = 0,
    this.favorite = false,
    this.typed = false,
  });

  /// Only once something is typed: one per host or tab, too many to list
  /// before.
  final bool typed;

  final _Kind kind;

  /// A favorite host: shown before typing, and first among hosts.
  final bool favorite;

  /// An action's name for counting how often it runs.
  final String? id;

  /// Within the same match, lower first: how recently a host was used.
  final int rank;
  final String title;
  final String? subtitle;
  final IconData icon;

  /// A shortcut that does the same.
  final String? keys;

  /// Where a command ran.
  final String? pill;
  final HistoryEntry? history;

  /// A saved host: found by [HostMatcher], as everywhere.
  final HostView? host;

  /// `alt`: ⌥↩, type a command without running it.
  final Future<void> Function(bool alt) run;
}

/// Opens the palette over the window whose `context` and `ref` are given:
/// what it picks runs there, once the palette is gone.
Future<void> showCommandPalette(BuildContext context, WidgetRef ref) async {
  ref.read(snippetsProvider.notifier).refresh();
  ref.read(workspacesProvider.notifier).refresh();
  final picked = await showDialog<(_Entry, bool)>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => _Palette(window: context, home: ref),
  );
  if (picked == null) {
    ref.read(tabsProvider).currentSession?.focusTerminal?.call();
    return;
  }
  final (entry, alt) = picked;
  if (entry.id case final id?) ref.read(recentProvider.notifier).used(id);
  await entry.run(alt);
}

class _Palette extends ConsumerStatefulWidget {
  const _Palette({required this.window, required this.home});

  /// The window's context and ref: entries run after the palette closes.
  final BuildContext window;
  final WidgetRef home;

  @override
  ConsumerState<_Palette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<_Palette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _selected = 0;

  /// The entries, made once (the palette shows a moment of the window),
  /// and what shows for the query, scored once per query: moving the
  /// selection with the arrows changes neither.
  List<_Entry>? _entries;
  List<_Entry>? _shownNow;
  String? _shownFor;

  List<_Entry> get _visible {
    final all = _entries ??= _all();
    if (_shownNow == null || _shownFor != _query.text) {
      _shownFor = _query.text;
      _shownNow = _shown(all);
    }
    return _shownNow!;
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Everything, before filtering. The palette is gone by the time an
  /// entry runs, so entries use the window's context and ref.
  List<_Entry> _all() {
    final l = context.l10n;
    final window = widget.window;
    final home = widget.home;
    final tabs = ref.read(tabsProvider.notifier);
    final state = ref.read(tabsProvider);
    final session = state.currentSession;
    final terminal = session != null && !session.isDisposed;
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    final container = ProviderScope.containerOf(window);
    _Entry action(
      String id,
      String title,
      IconData icon,
      VoidCallback f, {
      String? keys,
    }) => _Entry(
      kind: _Kind.action,
      id: id,
      title: title,
      icon: icon,
      keys: keys,
      run: (_) async => f(),
    );
    final out = <_Entry>[];
    final library = ref.read(libraryProvider);
    final recent = ref.read(recentProvider);
    final hosts = {for (final h in library.hosts) h.id: h};
    String hostAddress(HostView h) =>
        '${h.user.isEmpty ? '' : '${h.user}@'}${h.address}'
        '${h.port == 22 ? '' : ':${h.port}'}';

    // The open tabs, to jump to by name.
    for (final (i, t) in state.tabs.indexed) {
      final c = switch (t) {
        SessionTab(:final panes) =>
          panes.active.controller ?? panes.controllers.firstOrNull,
        SftpTab(:final controller) => controller,
        _ => null,
      };
      final host = c?.hostId == null ? null : hosts[c!.hostId];
      final last = i == state.tabs.length - 1;
      out.add(
        _Entry(
          kind: _Kind.tab,
          title: tabTitle(window, t),
          subtitle: host != null ? hostAddress(host) : c?.target?.label,
          icon: switch (t) {
            SessionTab() => Icons.terminal,
            SftpTab() => Icons.folder_outlined,
            PageTab(:final page) => pageIcon(page),
          },
          pill: i == state.active ? l.paletteHere : null,
          keys: !isApple
              ? null
              : i < 8
              ? '⌘${i + 1}'
              : last
              ? '⌘9'
              : null,
          run: (_) async => tabs.select(i),
        ),
      );
    }

    // Where it connected lately; a host deleted since is left out.
    final now = DateTime.now();
    final recency = <String, int>{};
    for (final (i, r) in recent.connections.indexed) {
      final id = r.hostId;
      final host = id == null ? null : hosts[id];
      final target = r.address == null ? null : QuickTarget.parse(r.address!);
      if (host == null && target == null) continue;
      if (id != null) recency[id] = i;
      out.add(
        _Entry(
          kind: _Kind.recent,
          title: host?.label ?? target!.label,
          subtitle: host != null ? hostAddress(host) : null,
          icon: Icons.schedule,
          pill: agoText(
            l,
            now.difference(DateTime.fromMillisecondsSinceEpoch(r.at)),
          ),
          rank: i,
          id: null,
          run: (alt) async => host != null
              ? (alt
                    ? tabs.openSftp(hostId: host.id, label: host.label)
                    : tabs.openHost(host))
              : tabs.openAddress(target!),
        ),
      );
    }

    if (terminal) {
      final here = historyPlace(session);
      final history = [...ref.read(historyProvider)];
      // This host's first, then the rest; newest first in each.
      history.sort((a, b) {
        final ha = a.where == here ? 0 : 1;
        final hb = b.where == here ? 0 : 1;
        return ha != hb ? ha - hb : b.at - a.at;
      });
      // A saved host by its name now, if it was renamed since.
      final library = ref.read(libraryProvider);
      String named(HistoryEntry h) => h.where.startsWith('host:')
          ? library.host(h.where.substring(5))?.label ?? h.label
          : h.label;
      for (final h in history) {
        out.add(
          _Entry(
            kind: _Kind.history,
            title: h.command,
            icon: Icons.history,
            pill: named(h),
            history: h,
            run: (alt) async => _send(container, h.command, typeOnly: alt),
          ),
        );
      }
    }

    for (final w in ref.read(workspacesProvider)) {
      out.add(
        _Entry(
          kind: _Kind.workspace,
          title: w.spec.name,
          subtitle: workspaceSummary(l, w.spec.tabs.length, w.sessions),
          icon: Icons.dashboard_outlined,
          run: (_) async => openWorkspace(home, w),
        ),
      );
    }

    out.addAll([
      action(
        'local',
        l.openLocal,
        Icons.terminal,
        tabs.openLocal,
        keys: '${key}T',
      ),
      action('newHost', l.saveNewHost, Icons.add, () async {
        if (await showHostEditor(window, home)) {
          home.read(libraryProvider.notifier).refresh();
        }
      }, keys: '${key}N'),
      action(
        'sidebar',
        l.toggleSidebar,
        Icons.view_sidebar_outlined,
        home.read(sidebarProvider.notifier).toggle,
        keys: sidebarKeys(l),
      ),
      if (terminal) ...[
        action(
          'splitRight',
          l.splitRight,
          Icons.vertical_split_outlined,
          () => tabs.split(Axis.horizontal),
          keys: '${key}D',
        ),
        action(
          'splitDown',
          l.splitDown,
          Icons.horizontal_split_outlined,
          () => tabs.split(Axis.vertical),
          keys: isApple ? '⌘⇧D' : '${key}E',
        ),
        action(
          'maximize',
          l.maximizePane,
          Icons.fullscreen,
          tabs.toggleMaximize,
          keys: isApple ? '⌘⇧↩' : '$key↩',
        ),
        action(
          'broadcast',
          l.paletteBroadcast,
          Icons.cell_tower,
          tabs.toggleBroadcast,
          keys: isApple ? '⌘⇧B' : '${key}B',
        ),
        action(
          'find',
          l.findInTerminal,
          Icons.manage_search,
          () => home.read(tabsProvider).currentSession?.openFind(),
          keys: isApple ? '⌘F' : '${key}F',
        ),
        action(
          'snippets',
          l.snippets,
          Icons.terminal,
          () => showSnippetPalette(window),
          keys: isApple ? '⌘⇧S' : '${key}S',
        ),
        if (!session.isLocal)
          action(
            'sftp',
            l.openSftp,
            Icons.folder_outlined,
            tabs.openSftpHere,
            keys: isApple ? '⌘⇧O' : '${key}O',
          ),
      ],
      if (captureTabs(state).isNotEmpty)
        action('saveTabs', l.saveOpenTabs, Icons.bookmark_add_outlined, () {
          saveWorkspaceDialog(window, home);
        }),
      if (state.current != null)
        action(
          'closeTab',
          l.closeTab,
          Icons.close,
          tabs.closeCurrent,
          keys: isApple ? '⌘W' : '${key}W',
        ),
      action('newKey', l.newKeyAction, Icons.key_outlined, () async {
        if (await showNewKeyDialog(window) != null) {
          tabs.openPage(PageKind.keys);
        }
      }),
      action(
        'import',
        l.importEllipsis,
        Icons.file_download_outlined,
        () => showImport(window, home),
      ),
      action(
        'page.hosts',
        l.goToPage(l.hosts),
        Icons.dns_outlined,
        () => tabs.openPage(PageKind.hosts),
        keys: isApple ? '⌘⇧H' : '${key}H',
      ),
      for (final (page, title, icon) in [
        (PageKind.keys, l.keys, Icons.key_outlined),
        (PageKind.workspaces, l.workspaces, Icons.dashboard_outlined),
        (PageKind.identities, l.identities, Icons.badge_outlined),
        (PageKind.snippets, l.snippets, Icons.terminal),
        (PageKind.tunnels, l.tunnels, Icons.swap_horiz),
        (PageKind.knownHosts, l.knownHosts, Icons.verified_user_outlined),
      ])
        action(
          'page.${page.name}',
          l.goToPage(title),
          icon,
          () => tabs.openPage(page),
        ),
      action(
        'settings',
        l.settings,
        Icons.settings_outlined,
        () => tabs.openPage(PageKind.settings),
        keys: isApple ? '⌘,' : 'Ctrl+,',
      ),
      action(
        'shortcuts',
        l.shortcutsTitle,
        Icons.keyboard_outlined,
        () => showShortcuts(window),
        keys: '$key/',
      ),
      action(
        'news',
        l.whatsNew,
        Icons.auto_awesome_outlined,
        () => showWhatsNew(window, home),
      ),
    ]);

    for (final h in library.hosts) {
      final favorite = h.favorite;
      out.add(
        _Entry(
          kind: _Kind.host,
          host: h,
          title: h.label,
          subtitle: hostAddress(h),
          icon: favorite == null
              ? Icons.dns_outlined
              : Icons.star_outline_rounded,
          pill: favorite == null ? null : l.favoriteLower,
          favorite: favorite != null,
          rank: favorite != null
              ? favorite - 100000
              : recency[h.id] ?? RecentNotifier.limit,
          run: (alt) async => alt
              ? tabs.openSftp(hostId: h.id, label: h.label)
              : tabs.openHost(h),
        ),
      );
    }

    // In a terminal: «Dividir con …» another tab or a host, on the right
    // of the active pane.
    if (state.current is SessionTab) {
      for (final t in state.tabs) {
        if (t is! SessionTab || identical(t, state.current)) continue;
        out.add(
          _Entry(
            kind: _Kind.action,
            id: 'splitWith',
            title: l.splitWith(tabTitle(window, t)),
            subtitle: l.splitWithNote,
            icon: Icons.vertical_split_outlined,
            typed: true,
            run: (_) async => tabs.splitWith(other: t),
          ),
        );
      }
      for (final h in library.hosts) {
        out.add(
          _Entry(
            kind: _Kind.action,
            id: 'splitWith',
            title: l.splitWith(h.label),
            subtitle: l.splitWithNote,
            icon: Icons.vertical_split_outlined,
            typed: true,
            run: (_) async => tabs.splitWith(host: h),
          ),
        );
      }
    }

    if (terminal) {
      for (final s in ref.read(snippetsProvider)) {
        out.add(
          _Entry(
            kind: _Kind.snippet,
            title: s.spec.label,
            subtitle: s.spec.script.split('\n').first,
            icon: Icons.code,
            run: (alt) =>
                runSnippet(window, container, s, typeOnly: alt ? true : null),
          ),
        );
      }
    }
    // The actions that run most go first; the rest keep their order.
    final used = recent.actions;
    final actions = [
      for (final e in out)
        if (e.kind == _Kind.action) e,
    ];
    final order = {for (final (i, e) in actions.indexed) e: i};
    actions.sort((a, b) {
      final n = (used[b.id] ?? 0) - (used[a.id] ?? 0);
      return n != 0 ? n : order[a]! - order[b]!;
    });
    return [
      for (final e in out)
        if (e.kind != _Kind.action) e,
      ...actions,
    ];
  }

  /// With nothing typed, a few of each; otherwise what matches, best
  /// first. `>` first keeps only the actions.
  List<_Entry> _shown(List<_Entry> all) {
    var q = _query.text.trim().toLowerCase();
    final onlyActions = q.startsWith('>');
    if (onlyActions) {
      q = q.substring(1).trim();
      all = [
        for (final e in all)
          if (e.kind == _Kind.action) e,
      ];
    } else if (q.isNotEmpty) {
      // Saved hosts come as hosts while typing; what was typed by hand
      // stays as a recent connection.
      all = [
        for (final e in all)
          if (e.kind != _Kind.recent || e.subtitle == null) e,
      ];
      final target = QuickTarget.parse(_query.text.trim());
      if (target != null && RegExp(r'[@.:]').hasMatch(_query.text)) {
        final tabs = ref.read(tabsProvider.notifier);
        all = [
          ...all,
          _Entry(
            kind: _Kind.action,
            title: context.l10n.connectToAddress(target.label),
            icon: Icons.terminal,
            run: (_) async => tabs.openAddress(target),
          ),
        ];
      }
    }
    if (q.isEmpty) {
      final counts = <_Kind, int>{};
      final most = {
        _Kind.tab: 9,
        _Kind.recent: 5,
        _Kind.history: 5,
        _Kind.workspace: 5,
        _Kind.action: 1000,
        _Kind.host: 0,
        _Kind.snippet: 0,
      };
      final kept = <_Entry>[
        for (final e in all)
          if (!e.typed &&
              (e.favorite ||
                  (counts[e.kind] = (counts[e.kind] ?? 0) + 1) <=
                      most[e.kind]!))
            e,
      ];
      final order = {for (final (i, e) in kept.indexed) e: i};
      return kept..sort(
        (a, b) => a.kind.index != b.kind.index
            ? a.kind.index - b.kind.index
            : a.favorite && b.favorite
            ? a.rank - b.rank
            : order[a]! - order[b]!,
      );
    }
    final scored = <(_Entry, int)>[];
    final hosts = HostMatcher(q, ref.read(libraryProvider));
    for (final e in all) {
      if (e.host case final h?) {
        if (hosts.score(h) case final s?) scored.add((e, s));
        continue;
      }
      final s = [
        matchScore(e.title, q),
        if (e.subtitle != null) matchScore(e.subtitle!, q).let((v) => v + 1),
        if (e.pill != null) matchScore(e.pill!, q).let((v) => v + 2),
      ].nonNulls;
      if (s.isNotEmpty) scored.add((e, s.reduce((a, b) => a < b ? a : b)));
    }
    // Stable: within a score, the order of the kinds.
    final order = {for (final (i, e) in all.indexed) e: i};
    scored.sort((a, b) {
      final kind = a.$1.kind.index - b.$1.kind.index;
      if (kind != 0) return kind;
      final score = a.$2 - b.$2;
      if (score != 0) return score;
      final rank = a.$1.rank - b.$1.rank;
      return rank != 0 ? rank : order[a.$1]! - order[b.$1]!;
    });
    final counts = <_Kind, int>{};
    return [
      for (final (e, _) in scored)
        if ((counts[e.kind] = (counts[e.kind] ?? 0) + 1) <= 30) e,
    ];
  }

  KeyEventResult _key(KeyEvent e, List<_Entry> shown) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    // Also with the cursor in the search, which would keep Esc otherwise.
    if (k == LogicalKeyboardKey.escape) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      if (shown.isEmpty) return KeyEventResult.handled;
      final step = k == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(
        () => _selected = (_selected + step + shown.length) % shown.length,
      );
      _reveal(shown);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (shown.isNotEmpty) {
        final alt = HardwareKeyboard.instance.isAltPressed;
        Navigator.pop(context, (
          shown[_selected.clamp(0, shown.length - 1)],
          alt,
        ));
      }
      return KeyEventResult.handled;
    }
    // ⌘⌫ (Ctrl+Shift+Backspace): out of the history.
    final mods = hardwareMods();
    final forget = isApple
        ? mods & Mods.superKey != 0
        : mods & Mods.ctrl != 0 && mods & Mods.shift != 0;
    if (k == LogicalKeyboardKey.backspace && forget && shown.isNotEmpty) {
      final h = shown[_selected.clamp(0, shown.length - 1)].history;
      if (h != null) {
        ref.read(historyProvider.notifier).remove(h);
        setState(() => _entries = _shownNow = null);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Keeps the selected row on view: rows are 40 high, the headings
  /// before them about 26.
  void _reveal(List<_Entry> shown) {
    if (!_scroll.hasClients) return;
    var headings = 0;
    for (var i = 0; i <= _selected && i < shown.length; i++) {
      if (i == 0 || shown[i].kind != shown[i - 1].kind) headings++;
    }
    final target = _selected * 40.0 + headings * 26;
    final view = _scroll.position.viewportDimension;
    if (target < _scroll.offset) {
      _scroll.jumpTo(target);
    } else if (target + 80 > _scroll.offset + view) {
      _scroll.jumpTo(
        (target + 80 - view).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
  }

  String _heading(AppLocalizations l, _Kind k) => switch (k) {
    _Kind.tab => l.paletteTabs,
    _Kind.recent => l.paletteRecent,
    _Kind.history => l.paletteHistory,
    _Kind.workspace => l.workspaces,
    _Kind.action => l.paletteActions,
    _Kind.host => l.paletteHosts,
    _Kind.snippet => l.snippets,
  };

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final shown = _visible;
    final selected = shown.isEmpty ? -1 : _selected.clamp(0, shown.length - 1);
    final mono = monoStyle(context, size: 12);
    Widget hint(String keys, String text) => Padding(
      padding: const EdgeInsets.only(right: OwSpace.s7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: keys, style: mono),
            TextSpan(text: ' $text'),
          ],
        ),
        style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
      ),
    );
    final rows = <Widget>[];
    _Kind? last;
    for (final (i, e) in shown.indexed) {
      if (e.kind != last) {
        last = e.kind;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OwSpace.s5,
              OwSpace.s4,
              OwSpace.s5,
              OwSpace.s2,
            ),
            child: SectionLabel(_heading(l, e.kind)),
          ),
        );
      }
      rows.add(_item(context, e, i == selected));
    }
    final current = selected < 0 ? null : shown[selected];
    return Align(
      alignment: const Alignment(0, -0.7),
      child: Material(
        color: c.raised,
        elevation: 16,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.control),
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge + 2),
        ),
        child: SizedBox(
          width: 620,
          child: Padding(
            padding: const EdgeInsets.all(OwSpace.s3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  onKeyEvent: (_, e) => _key(e, shown),
                  child: TextField(
                    key: const ValueKey('palette.query'),
                    controller: _query,
                    autofocus: true,
                    onChanged: (_) => setState(() => _selected = 0),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: l.paletteHint,
                      prefixIcon: Icon(
                        Icons.keyboard_command_key,
                        size: 16,
                        color: c.accentText,
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: c.border),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(OwSpace.s7),
                    child: Text(
                      l.paletteNothing,
                      style: TextStyle(color: c.textMuted),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: OwSpace.s2),
                      children: rows,
                    ),
                  ),
                Divider(height: 1, color: c.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OwSpace.s5,
                    OwSpace.s4,
                    OwSpace.s3,
                    OwSpace.s3,
                  ),
                  child: Wrap(
                    children: [
                      hint('↑↓', l.paletteChoose),
                      hint('↩', switch (current?.kind) {
                        _Kind.history || _Kind.snippet => l.paletteRun,
                        _Kind.host ||
                        _Kind.recent ||
                        _Kind.workspace ||
                        _Kind.tab => l.open.toLowerCase(),
                        _ => l.paletteDo,
                      }),
                      if (current?.kind == _Kind.history ||
                          current?.kind == _Kind.snippet)
                        hint(isApple ? '⌥↩' : 'Alt+↩', l.paletteTypeOnly),
                      if (current?.kind == _Kind.host ||
                          (current?.kind == _Kind.recent &&
                              current?.subtitle != null))
                        hint(isApple ? '⌥↩' : 'Alt+↩', l.openSftp),
                      if (!_query.text.trimLeft().startsWith('>'))
                        hint('>', l.paletteOnlyActions),
                      if (current?.kind == _Kind.history)
                        hint(
                          keysFor(
                            '⌘⌫',
                            '${l.ctrlShiftPrefix}${l.keyBackspace}',
                          ),
                          l.paletteForget,
                        ),
                      hint('Esc', l.close.toLowerCase()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, _Entry e, bool selected) {
    final ow = context.ow;
    final c = ow.colors;
    final mono = e.kind == _Kind.history;
    return SizedBox(
      height: 40,
      child: Material(
        color: selected ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(ow.shape.radius),
        child: InkWell(
          key: ValueKey('palette.${e.kind.name}.${e.title}'),
          borderRadius: BorderRadius.circular(ow.shape.radius),
          onTap: () => Navigator.pop(context, (e, false)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OwSpace.s5),
            child: Row(
              children: [
                Icon(e.icon, size: 15, color: c.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono
                              ? monoStyle(context, size: 12, color: c.text)
                              : null,
                        ),
                      ),
                      if (e.subtitle != null) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            e.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(
                              context,
                              size: 12,
                              color: c.textSubtle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (e.pill != null)
                  Padding(
                    padding: const EdgeInsets.only(left: OwSpace.s4),
                    child: Pill(e.pill!, tone: PillTone.neutral),
                  ),
                if (e.keys != null)
                  Padding(
                    padding: const EdgeInsets.only(left: OwSpace.s4),
                    child: KeyCap(e.keys!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Types `command` in the front tab's terminal (and the panes that
/// receive while broadcasting), running it unless `typeOnly`.
void _send(ProviderContainer ref, String command, {required bool typeOnly}) {
  final targets = snippetTargets(ref);
  if (!typeOnly &&
      targets.isNotEmpty &&
      ref.read(settingsProvider).commandHistory) {
    ref.read(historyProvider.notifier).add(command, targets.first);
  }
  for (final c in targets) {
    if (c.isDisposed) continue;
    c.line.reset();
    if (typeOnly) {
      c.session.paste(text: command, allowUnsafe: true);
    } else {
      c.session.text(text: '$command\n');
    }
  }
  targets.firstOrNull?.focusTerminal?.call();
}

extension<T extends Object> on T? {
  R? let<R>(R Function(T) f) {
    final v = this;
    return v == null ? null : f(v);
  }
}

/// How long ago, in a few words: «ahora», «hace 5 min», «hace 3 h»,
/// «hace 2 d».
String agoText(AppLocalizations l, Duration d) {
  if (d.inMinutes < 1) return l.agoNow;
  if (d.inHours < 1) return l.agoMinutes(d.inMinutes);
  if (d.inDays < 1) return l.agoHours(d.inHours);
  return l.agoDays(d.inDays);
}
