// The command palette (⌘⇧P, Ctrl+Shift+P elsewhere): everything the window
// does, the saved hosts and workspaces, the snippets and the commands run
// before, found by typing a few letters.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/settings.dart';
import '../history/history.dart';
import '../hosts/editors.dart';
import '../import/import_dialog.dart';
import '../keys/key_dialogs.dart';
import '../l10n/l10n.dart';
import '../snippets/palette.dart';
import '../snippets/snippets.dart';
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../welcome/whats_new.dart';
import '../workspaces/workspaces.dart';
import '../workspaces/workspaces_page.dart';

enum _Kind { history, workspace, action, host, snippet }

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
  });

  final _Kind kind;
  final String title;
  final String? subtitle;
  final IconData icon;

  /// A shortcut that does the same.
  final String? keys;

  /// Where a command ran.
  final String? pill;
  final HistoryEntry? history;

  /// `alt`: ⌥↩, type a command without running it.
  final Future<void> Function(bool alt) run;
}

/// How well `text` matches `q` (lowercase): lower is better, null is no
/// match. The start, the start of a word, anywhere, then the letters in
/// order.
int? matchScore(String text, String q) {
  if (q.isEmpty) return 0;
  final t = text.toLowerCase();
  if (t.startsWith(q)) return 0;
  final at = t.indexOf(q);
  if (at > 0) {
    final before = t[at - 1];
    return RegExp(r'[\s/._@:-]').hasMatch(before) ? 1 : 2;
  }
  if (q.length < 2) return null;
  var i = 0;
  for (final ch in t.split('')) {
    if (ch == q[i] && ++i == q.length) return 3;
  }
  return null;
}

/// Opens the palette over the window whose `context` and `ref` are given:
/// what it picks runs there, once the palette is gone. `focusSearch` puts
/// the cursor in the hosts' search.
Future<void> showCommandPalette(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback focusSearch,
}) async {
  ref.read(snippetsProvider.notifier).refresh();
  ref.read(workspacesProvider.notifier).refresh();
  final picked = await showDialog<(_Entry, bool)>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) =>
        _Palette(window: context, home: ref, focusSearch: focusSearch),
  );
  if (picked == null) {
    ref.read(tabsProvider).currentSession?.focusTerminal?.call();
    return;
  }
  await picked.$1.run(picked.$2);
}

class _Palette extends ConsumerStatefulWidget {
  const _Palette({
    required this.window,
    required this.home,
    required this.focusSearch,
  });

  /// The window's context and ref: entries run after the palette closes.
  final BuildContext window;
  final WidgetRef home;
  final VoidCallback focusSearch;

  @override
  ConsumerState<_Palette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<_Palette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _selected = 0;

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
      String title,
      IconData icon,
      VoidCallback f, {
      String? keys,
    }) => _Entry(
      kind: _Kind.action,
      title: title,
      icon: icon,
      keys: keys,
      run: (_) async => f(),
    );
    final out = <_Entry>[];

    if (terminal) {
      final here = historyPlace(session);
      final history = [...ref.read(historyProvider)];
      // This host's first, then the rest; newest first in each.
      history.sort((a, b) {
        final ha = a.where == here ? 0 : 1;
        final hb = b.where == here ? 0 : 1;
        return ha != hb ? ha - hb : b.at - a.at;
      });
      for (final h in history) {
        out.add(
          _Entry(
            kind: _Kind.history,
            title: h.command,
            icon: Icons.history,
            pill: h.label,
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
      action(l.openLocal, Icons.terminal, tabs.openLocal, keys: '${key}T'),
      action(l.saveNewHost, Icons.add, () async {
        if (await showHostEditor(window, home)) {
          home.read(libraryProvider.notifier).refresh();
        }
      }, keys: '${key}N'),
      action(l.searchHosts, Icons.search, widget.focusSearch, keys: '${key}K'),
      if (terminal) ...[
        action(
          l.splitRight,
          Icons.vertical_split_outlined,
          () => tabs.split(Axis.horizontal),
          keys: '${key}D',
        ),
        action(
          l.splitDown,
          Icons.horizontal_split_outlined,
          () => tabs.split(Axis.vertical),
          keys: isApple ? '⌘⇧D' : '${key}E',
        ),
        action(
          l.maximizePane,
          Icons.fullscreen,
          tabs.toggleMaximize,
          keys: isApple ? '⌘⇧↩' : '$key↩',
        ),
        action(
          l.paletteBroadcast,
          Icons.cell_tower,
          tabs.toggleBroadcast,
          keys: isApple ? '⌘⇧B' : '${key}B',
        ),
        action(
          l.findInTerminal,
          Icons.manage_search,
          () => home.read(tabsProvider).currentSession?.openFind(),
          keys: isApple ? '⌘F' : '${key}F',
        ),
        action(
          l.snippets,
          Icons.terminal,
          () => showSnippetPalette(window),
          keys: isApple ? '⌘⇧S' : '${key}S',
        ),
        if (!session.isLocal)
          action(
            l.openSftp,
            Icons.folder_outlined,
            tabs.openSftpHere,
            keys: isApple ? '⌘⇧O' : '${key}O',
          ),
      ],
      if (captureTabs(state).isNotEmpty)
        action(l.saveOpenTabs, Icons.bookmark_add_outlined, () {
          saveWorkspaceDialog(window, home);
        }),
      if (state.current != null)
        action(
          l.closeTab,
          Icons.close,
          tabs.closeCurrent,
          keys: isApple ? '⌘W' : '${key}W',
        ),
      action(l.newKeyAction, Icons.key_outlined, () async {
        if (await showNewKeyDialog(window) != null) {
          tabs.openPage(PageKind.keys);
        }
      }),
      action(
        l.importEllipsis,
        Icons.file_download_outlined,
        () => showImport(window, home),
      ),
      for (final (page, title, icon) in [
        (PageKind.keys, l.keys, Icons.key_outlined),
        (PageKind.workspaces, l.workspaces, Icons.dashboard_outlined),
        (PageKind.identities, l.identities, Icons.badge_outlined),
        (PageKind.snippets, l.snippets, Icons.terminal),
        (PageKind.tunnels, l.tunnels, Icons.swap_horiz),
        (PageKind.knownHosts, l.knownHosts, Icons.verified_user_outlined),
      ])
        action(l.goToPage(title), icon, () => tabs.openPage(page)),
      action(
        l.settings,
        Icons.settings_outlined,
        () => tabs.openPage(PageKind.settings),
        keys: isApple ? '⌘,' : 'Ctrl+,',
      ),
      action(
        l.whatsNew,
        Icons.auto_awesome_outlined,
        () => showWhatsNew(window, home),
      ),
    ]);

    for (final h in ref.read(libraryProvider).hosts) {
      out.add(
        _Entry(
          kind: _Kind.host,
          title: h.label,
          subtitle:
              '${h.user.isEmpty ? '' : '${h.user}@'}${h.address}'
              '${h.port == 22 ? '' : ':${h.port}'}',
          icon: Icons.dns_outlined,
          run: (alt) async => alt
              ? tabs.openSftp(hostId: h.id, label: h.label)
              : tabs.openHost(h),
        ),
      );
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
    return out;
  }

  /// With nothing typed, a few of each; otherwise what matches, best
  /// first.
  List<_Entry> _shown(List<_Entry> all) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) {
      final counts = <_Kind, int>{};
      const most = {
        _Kind.history: 5,
        _Kind.workspace: 5,
        _Kind.action: 1000,
        _Kind.host: 0,
        _Kind.snippet: 0,
      };
      return [
        for (final e in all)
          if ((counts[e.kind] = (counts[e.kind] ?? 0) + 1) <= most[e.kind]!) e,
      ];
    }
    final scored = <(_Entry, int)>[];
    for (final e in all) {
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
      return score != 0 ? score : order[a.$1]! - order[b.$1]!;
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
        setState(() {});
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
    final shown = _shown(_all());
    final selected = shown.isEmpty ? -1 : _selected.clamp(0, shown.length - 1);
    final mono = monoStyle(context, size: 11);
    Widget hint(String keys, String text) => Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: keys, style: mono),
            TextSpan(text: ' $text'),
          ],
        ),
        style: TextStyle(fontSize: 11, color: c.textSubtle),
      ),
    );
    final rows = <Widget>[];
    _Kind? last;
    for (final (i, e) in shown.indexed) {
      if (e.kind != last) {
        last = e.kind;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
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
            padding: const EdgeInsets.all(6),
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
                    padding: const EdgeInsets.all(14),
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
                      padding: const EdgeInsets.only(bottom: 4),
                      children: rows,
                    ),
                  ),
                Divider(height: 1, color: c.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
                  child: Wrap(
                    children: [
                      hint('↑↓', l.paletteChoose),
                      hint('↩', switch (current?.kind) {
                        _Kind.history || _Kind.snippet => l.paletteRun,
                        _Kind.host || _Kind.workspace => l.open.toLowerCase(),
                        _ => l.paletteDo,
                      }),
                      if (current?.kind == _Kind.history ||
                          current?.kind == _Kind.snippet)
                        hint(isApple ? '⌥↩' : 'Alt+↩', l.paletteTypeOnly),
                      if (current?.kind == _Kind.host)
                        hint(isApple ? '⌥↩' : 'Alt+↩', l.openSftp),
                      if (current?.kind == _Kind.history)
                        hint(isApple ? '⌘⌫' : 'Ctrl+Shift+⌫', l.paletteForget),
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
                              size: 11,
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
                    padding: const EdgeInsets.only(left: 8),
                    child: Pill(e.pill!, tone: PillTone.neutral),
                  ),
                if (e.keys != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
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
