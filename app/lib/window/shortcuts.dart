// Every keyboard shortcut on one sheet (⌘/, Ctrl+Shift+/ elsewhere), with
// a search that finds them by what they do or by their keys; and how a
// tooltip names the shortcut of its button.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// `apple` on macOS, `other` elsewhere.
String keysFor(String apple, String other) => isApple ? apple : other;

/// A button's tooltip with its shortcut: «Carpeta nueva (⌘⇧N)».
String withKeys(String text, String keys) => '$text ($keys)';

/// What folds and opens the sidebar.
String sidebarKeys(AppLocalizations l) =>
    keysFor('⌘B', '${l.ctrlShiftPrefix}L');

/// What opens the Hosts page.
String hostsKeys(AppLocalizations l) => keysFor('⌘⇧H', '${l.ctrlShiftPrefix}H');

/// What opens the session logs.
String logsKeys(AppLocalizations l) => keysFor('⌘⇧R', '${l.ctrlShiftPrefix}R');

/// What opens the last closed tab again: Ctrl+Shift+T elsewhere opens a
/// local shell, so Alt joins it.
String reopenKeys(AppLocalizations l, {bool? apple}) =>
    (apple ?? isApple) ? '⌘⇧T' : '${l.ctrlShiftPrefix}Alt+T';

/// One line of the sheet: what it does and the keys that do it, any of
/// them.
class ShortcutRow {
  const ShortcutRow(this.title, this.keys);

  final String title;
  final List<String> keys;
}

class ShortcutGroup {
  const ShortcutGroup(this.title, this.rows);

  final String title;
  final List<ShortcutRow> rows;
}

/// The shortcuts of the window, as the window binds them (`home.dart`,
/// the terminal, the SFTP browser and the editors), for macOS or not.
List<ShortcutGroup> shortcutGroups(AppLocalizations l, {bool? apple}) {
  final mac = apple ?? isApple;
  final cs = l.ctrlShiftPrefix;
  // Window keys: ⌘ on macOS, Ctrl+Shift elsewhere, so that Ctrl alone
  // stays the terminal's.
  String w(String key) => mac ? '⌘$key' : '$cs$key';
  // In the SFTP browser and the editors, Ctrl alone elsewhere.
  String c(String key) => mac ? '⌘$key' : 'Ctrl+$key';
  String k(String apple, String other) => mac ? apple : other;
  return [
    ShortcutGroup(l.shortcutsWindow, [
      ShortcutRow(l.shortcutPalette, [w('K'), w('P')]),
      ShortcutRow(l.openLocal, [w('T')]),
      ShortcutRow(l.saveNewHost, [w('N')]),
      ShortcutRow(l.shortcutHosts, [k('⌘⇧H', '${cs}H')]),
      ShortcutRow(l.logs, [k('⌘⇧R', '${cs}R')]),
      ShortcutRow(l.closeTab, [w('W')]),
      ShortcutRow(l.reopenTab, [reopenKeys(l, apple: mac)]),
      ShortcutRow(l.toggleSidebar, [k('⌘B', '${cs}L')]),
      ShortcutRow(l.settings, [c(',')]),
      ShortcutRow(l.shortcutsTitle, [w('/')]),
    ]),
    ShortcutGroup(l.shortcutsTabs, [
      ShortcutRow(l.shortcutNextTab, [k('⌃Tab', 'Ctrl+Tab'), if (mac) '⌘⇧]']),
      ShortcutRow(l.shortcutPreviousTab, [
        k('⌃⇧Tab', '${cs}Tab'),
        if (mac) '⌘⇧[',
      ]),
      // Off macOS with the left Alt: the right one is AltGr.
      ShortcutRow(l.shortcutGoToTab, [k('⌘1 … ⌘8', 'Ctrl+Alt+1 … Ctrl+Alt+8')]),
      ShortcutRow(l.shortcutLastTab, [k('⌘9', 'Ctrl+Alt+9')]),
    ]),
    ShortcutGroup(l.shortcutsPanes, [
      ShortcutRow(l.splitRight, [w('D')]),
      ShortcutRow(l.splitDown, [k('⌘⇧D', '${cs}E')]),
      ShortcutRow(l.maximizePane, [k('⌘⇧↩', '$cs↩')]),
      if (mac) ShortcutRow(l.equalizePanes, ['⌘⌥=']),
      ShortcutRow(l.shortcutGoToPane, [k('⌘⌥ ←↑↓→', '$cs←↑↓→')]),
      ShortcutRow(l.paletteBroadcast, [k('⌘⇧B', '${cs}B')]),
    ]),
    ShortcutGroup(l.shortcutsForms, [
      ShortcutRow(l.save, [c('↩')]),
      ShortcutRow(l.close, ['Esc']),
      ShortcutRow(l.shortcutConnectTyped, [k('⌥↩', 'Alt+↩')]),
    ]),
    ShortcutGroup(l.shortcutsTerminal, [
      ShortcutRow(l.findInTerminal, [k('⌘F', '${cs}F')]),
      ShortcutRow(l.shortcutFindOlder, ['↩', if (mac) '⌘G' else '${cs}G']),
      ShortcutRow(l.shortcutFindNewer, [
        k('⇧↩', '${l.shiftPrefix}↩'),
        if (mac) '⌘⇧G',
      ]),
      ShortcutRow(l.copy, [k('⌘C', '${cs}C')]),
      ShortcutRow(l.paste, [k('⌘V', '${cs}V')]),
      if (mac) ShortcutRow(l.selectAllText, ['⌘A']),
      ShortcutRow(l.snippets, [k('⌘⇧S', '${cs}S')]),
      ShortcutRow(l.openSftp, [k('⌘⇧O', '${cs}O')]),
      ShortcutRow(l.shortcutTextBigger, [c('=')]),
      ShortcutRow(l.shortcutTextSmaller, [c('-')]),
      ShortcutRow(l.shortcutTextReset, [c('0')]),
    ]),
    ShortcutGroup('SFTP', [
      ShortcutRow(l.filterFolder, [c('F')]),
      ShortcutRow(l.upOneLevel, [c('↑'), k('⌫', l.keyBackspace)]),
      ShortcutRow(l.reload, [c('R'), 'F5']),
      ShortcutRow(l.newFolder, [k('⌘⇧N', '${cs}N')]),
      ShortcutRow(l.rename, ['F2']),
      ShortcutRow(l.shortcutPermissions, [c('I')]),
      ShortcutRow(l.delete, [k('⌘⌫', l.keyDelete), if (mac) l.keyDelete]),
      ShortcutRow(l.selectAllText, [c('A')]),
      ShortcutRow(l.shortcutSwitchSide, ['Tab']),
    ]),
  ];
}

/// Lowercase and without accents, to find «búsqueda» by «busqueda».
String _fold(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

/// The groups with only the lines that match `query`, by what they do or
/// by their keys; the groups left empty go.
List<ShortcutGroup> filterShortcuts(List<ShortcutGroup> groups, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return groups;
  bool keyed(ShortcutRow r) => r.keys.any((k) => _fold(k).contains(q));
  return [
    for (final g in groups)
      if ([
            for (final r in g.rows)
              if (_fold(r.title).contains(q) || keyed(r)) r,
          ]
          case final rows when rows.isNotEmpty)
        ShortcutGroup(g.title, rows),
  ];
}

bool _open = false;

/// Shows the sheet; once, however many keys asked for it.
Future<void> showShortcuts(BuildContext context) async {
  if (_open) return;
  _open = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => const ShortcutsSheet(),
    );
  } finally {
    _open = false;
  }
}

class ShortcutsSheet extends StatefulWidget {
  const ShortcutsSheet({super.key});

  @override
  State<ShortcutsSheet> createState() => _ShortcutsSheetState();
}

class _ShortcutsSheetState extends State<ShortcutsSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final groups = filterShortcuts(shortcutGroups(l), _query.text);
    // Two columns when there is room: the window's on the left, the
    // terminal's and the SFTP browser's on the right.
    final split = groups.indexWhere((g) => g.title == l.shortcutsTerminal);
    Widget column(List<ShortcutGroup> gs) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final g in gs) _Group(g)],
    );
    return CallbackShortcuts(
      // Also with the cursor in the search, which would keep Esc otherwise.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Dialog(
        key: const ValueKey('shortcuts'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  OwSpace.s10,
                  OwSpace.s7,
                  OwSpace.s4,
                  OwSpace.s4,
                ),
                child: Row(
                  children: [
                    Icon(Icons.keyboard_outlined, size: 18, color: c.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.shortcutsTitle,
                        style: const TextStyle(
                          fontSize: OwText.title,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: withKeys(l.close, 'Esc'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: OwSpace.s10),
                child: TextField(
                  key: const ValueKey('shortcuts.search'),
                  controller: _query,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: fieldTextStyle(context),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.shortcutsSearch,
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: c.textSubtle,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  ),
                ),
              ),
              Flexible(
                child: groups.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(OwSpace.s14),
                        child: Text(
                          l.shortcutsNone(_query.text.trim()),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textMuted),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            OwSpace.s10,
                            OwSpace.s4,
                            OwSpace.s10,
                            OwSpace.s10,
                          ),
                          child: box.maxWidth >= 640 && split > 0
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: column(groups.sublist(0, split)),
                                    ),
                                    const SizedBox(width: 32),
                                    Expanded(
                                      child: column(groups.sublist(split)),
                                    ),
                                  ],
                                )
                              : column(groups),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.group);

  final ShortcutGroup group;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: OwSpace.s7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(group.title),
        const SizedBox(height: 4),
        for (final r in group.rows)
          Semantics(
            // Read as one: «Dividir a la derecha, ⌘D».
            label: '${r.title}, ${r.keys.join(', ')}',
            excludeSemantics: true,
            child: Padding(
              key: ValueKey('shortcut.${r.title}'),
              padding: const EdgeInsets.symmetric(vertical: OwSpace.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.title,
                      style: const TextStyle(fontSize: OwText.body),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final k in r.keys) KeyCap(k)],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
