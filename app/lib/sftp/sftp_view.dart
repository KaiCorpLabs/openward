// An SFTP tab: this machine on the left, the server on the right, the
// transfer queue below and the connection's state at the bottom.

import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection.dart';
import '../core/errors.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/sftp.dart';
import '../tabs/connection_panels.dart';
import '../tabs/messages.dart';
import '../tabs/prompt_card.dart';
import '../terminal/keys.dart';
import '../ui/move_draggable.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/shortcuts.dart';
import 'dialogs.dart';
import 'format.dart';
import 'queue_view.dart';
import 'sftp_controller.dart';

/// Rows of the listings, in logical pixels: more as the text grows.
double _rowHeightIn(BuildContext context) => heightForText(context, 30);

/// What is dragged from one side to the other.
class FileDrag {
  const FileDrag(this.from, this.paths);

  final Side from;
  final List<String> paths;
}

class SftpView extends StatefulWidget {
  const SftpView({super.key, required this.controller});

  final SftpController controller;

  @override
  State<SftpView> createState() => _SftpViewState();
}

class _SftpViewState extends State<SftpView> {
  bool _queueOpen = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ow = context.ow;
    return ColoredBox(
      color: ow.colors.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(OwSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: FilePaneView(controller: c, side: Side.local),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilePaneView(controller: c, side: Side.remote),
                  ),
                ],
              ),
            ),
          ),
          QueueView(
            open: _queueOpen,
            onToggle: () => setState(() => _queueOpen = !_queueOpen),
          ),
          _SftpStatusBar(controller: c),
        ],
      ),
    );
  }
}

/// One side: where it is, the files there and what can be done with them.
class FilePaneView extends ConsumerStatefulWidget {
  const FilePaneView({super.key, required this.controller, required this.side});

  final SftpController controller;
  final Side side;

  @override
  ConsumerState<FilePaneView> createState() => _FilePaneViewState();
}

class _FilePaneViewState extends ConsumerState<FilePaneView> {
  final FocusNode _focus = FocusNode(debugLabel: 'file pane');
  final FocusNode _filterFocus = FocusNode(debugLabel: 'file filter');
  final TextEditingController _filter = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _dropping = false;

  // A second press on the same row soon after opens it.
  String? _lastClick;
  DateTime _lastClickAt = DateTime(0);

  SftpController get _c => widget.controller;
  FilePane get _pane => _c.pane(widget.side);
  bool get _remote => widget.side == Side.remote;
  FilePane get _other => _c.pane(_remote ? Side.local : Side.remote);

  /// The other side's name, for "upload to" and "download".
  String get _otherName => _remote ? context.l10n.thisComputer : _c.label;

  @override
  void initState() {
    super.initState();
    // Back from another tab with a filter still on: it shows.
    _filter.text = _pane.filter;
    _pane.addListener(_onPane);
    _c.addListener(_onController);
    _focus.addListener(() {
      if (_focus.hasFocus) _c.focus(widget.side);
    });
  }

  void _onPane() {
    if (_filter.text != _pane.filter) _filter.text = _pane.filter;
    if (mounted) setState(() {});
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pane.removeListener(_onPane);
    _c.removeListener(_onController);
    _focus.dispose();
    _filterFocus.dispose();
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _show(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Runs a file operation; its error goes to a snackbar. True if it
  /// went well.
  Future<bool> _run(Future<void> Function() op) async {
    try {
      await op();
      return true;
    } on FileError catch (e) {
      if (!mounted) return false;
      final text = fileErrorText(context.l10n, e);
      e.kind == FileErrorKind.other
          ? showErrorNotice(ScaffoldMessenger.of(context), text, e)
          : _show(text);
      return false;
    }
  }

  void _ensureVisible() {
    final name = _pane.cursor;
    if (name == null || !_scroll.hasClients) return;
    final i = _pane.visible.indexWhere((e) => e.name == name);
    if (i < 0) return;
    final row = _rowHeightIn(context);
    final top = i * row;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + row > _scroll.offset + view) {
      _scroll.jumpTo(top + row - view);
    }
  }

  // ---------------------------------------------------------------- actions

  /// Copies paths of this side into the other side's folder.
  Future<void> _copy(List<String> paths, {Side? from}) async {
    final l = context.l10n;
    final source = from ?? widget.side;
    final dest = _c.pane(source == Side.local ? Side.remote : Side.local);
    if (dest.path.isEmpty || paths.isEmpty) return;
    final where = source == Side.local ? _c.label : l.thisComputer;
    await _run(
      () => _c.copy(
        source,
        paths,
        dest.path,
        ask: (conflicts) => askConflicts(
          context,
          conflicts: conflicts,
          total: paths.length,
          where: where,
          dest: dest.path,
        ),
      ),
    );
  }

  Future<void> _copySelection() =>
      _copy([for (final e in _pane.selection) _pane.pathOf(e.name)]);

  Future<void> _activate(FileEntry e) async {
    if (e.isDir) {
      await _pane.enter(e);
    } else {
      await _copy([_pane.pathOf(e.name)]);
    }
  }

  Future<void> _newFolder() async {
    final l = context.l10n;
    final name = await askName(context, title: l.newFolder, action: l.create);
    if (name == null) return;
    final ok = await _run(() => _pane.fs.mkdir(_pane.pathOf(name)));
    await _pane.refresh();
    if (ok) _pane.click(name);
  }

  Future<void> _rename(FileEntry e) async {
    final l = context.l10n;
    final name = await askName(
      context,
      title: l.renameTitle(e.name),
      action: l.rename,
      initial: e.name,
    );
    if (name == null || name == e.name) return;
    final ok = await _run(
      () => _pane.fs.rename(_pane.pathOf(e.name), _pane.pathOf(name)),
    );
    await _pane.refresh();
    if (ok) _pane.click(name);
  }

  Future<void> _permissions(FileEntry e) async {
    final l = context.l10n;
    final n = await showPermissions(
      context,
      entry: e,
      path: _pane.pathOf(e.name),
      fs: _pane.fs,
    );
    if (n == null) return;
    if (n > 1) _show(l.permApplied(n));
    await _pane.refresh();
  }

  Future<void> _delete() async {
    final entries = _pane.selection;
    if (entries.isEmpty) return;
    final ok = await confirmDelete(
      context,
      entries: entries,
      host: _remote ? _c.label : null,
    );
    if (!ok) return;
    await _run(
      () => _pane.fs.remove([for (final e in entries) _pane.pathOf(e.name)]),
    );
    await _pane.refresh();
  }

  void _copyPath(FileEntry? e) {
    final path = e == null ? _pane.path : _pane.pathOf(e.name);
    Clipboard.setData(ClipboardData(text: path));
  }

  // --------------------------------------------------------------- keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final cmd = isApple ? keys.isMetaPressed : keys.isControlPressed;
    final shift = keys.isShiftPressed;
    final one = _pane.selection.length == 1 ? _pane.selection.first : null;
    void move(int d) {
      _pane.moveCursor(d, extend: shift);
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    }

    if (k == LogicalKeyboardKey.arrowDown) {
      move(1);
    } else if (k == LogicalKeyboardKey.arrowUp && cmd) {
      _pane.up();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      move(-1);
    } else if (k == LogicalKeyboardKey.pageDown) {
      move(10);
    } else if (k == LogicalKeyboardKey.pageUp) {
      move(-10);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      if (one != null) _activate(one);
    } else if (k == LogicalKeyboardKey.backspace && cmd ||
        k == LogicalKeyboardKey.delete) {
      _delete();
    } else if (k == LogicalKeyboardKey.backspace) {
      _pane.up();
    } else if (k == LogicalKeyboardKey.tab) {
      _c.focus(_remote ? Side.local : Side.remote);
    } else if (k == LogicalKeyboardKey.keyA && cmd) {
      _pane.selectAll();
    } else if (k == LogicalKeyboardKey.keyF && cmd) {
      _filterFocus.requestFocus();
    } else if (k == LogicalKeyboardKey.keyN && cmd && shift) {
      _newFolder();
    } else if (k == LogicalKeyboardKey.keyI && cmd) {
      if (one != null) _permissions(one);
    } else if (k == LogicalKeyboardKey.f2) {
      if (one != null) _rename(one);
    } else if (k == LogicalKeyboardKey.f5 ||
        (k == LogicalKeyboardKey.keyR && cmd)) {
      _pane.refresh();
    } else if (k == LogicalKeyboardKey.escape) {
      if (_pane.filter.isNotEmpty) {
        _pane.setFilter('');
      } else {
        _pane.selected.clear();
        _onPane();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------------ mouse

  void _pointerDown(FileEntry e, PointerDownEvent d) {
    _focus.requestFocus();
    if (d.buttons != kPrimaryButton) return;
    final keys = HardwareKeyboard.instance;
    final now = DateTime.now();
    final again =
        _lastClick == e.name &&
        now.difference(_lastClickAt) < const Duration(milliseconds: 400);
    _lastClick = e.name;
    _lastClickAt = now;
    if (again) {
      _lastClick = null;
      _activate(e);
      return;
    }
    _pane.press(
      e.name,
      toggle: isApple ? keys.isMetaPressed : keys.isControlPressed,
      range: keys.isShiftPressed,
    );
  }

  Future<void> _menu(Offset at, FileEntry? e) async {
    final l = context.l10n;
    final key = isApple ? '⌘' : 'Ctrl+';
    if (e != null && !_pane.selected.contains(e.name)) _pane.click(e.name);
    final selection = _pane.selection;
    final one = selection.length == 1 ? selection.first : null;
    final connected = _c.connected != null;
    PopupMenuItem<VoidCallback> item(
      String text,
      String keys,
      VoidCallback? action, {
      bool danger = false,
    }) => PopupMenuItem(
      value: action,
      enabled: action != null,
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: danger ? TextStyle(color: context.ow.colors.danger) : null,
            ),
          ),
          const SizedBox(width: 20),
          Text(keys, style: monoStyle(context, size: 12)),
        ],
      ),
    );
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        if (selection.isNotEmpty) ...[
          item(
            _remote ? l.downloadTo(_other.path) : l.uploadToHost(_c.label),
            '',
            connected && _other.path.isNotEmpty ? _copySelection : null,
          ),
          item(l.copyPath, isApple ? '⌥⌘C' : '', () => _copyPath(one)),
          const PopupMenuDivider(),
          item(l.rename, 'F2', one == null ? null : () => _rename(one)),
          item(
            l.permissionsEllipsis,
            '${key}I',
            one == null || (!_remote && !isUnix)
                ? null
                : () => _permissions(one),
          ),
        ],
        item(l.newFolder, keysFor('⌘⇧N', '${l.ctrlShiftPrefix}N'), _newFolder),
        item(l.reload, isApple ? '⌘R' : 'F5', _pane.refresh),
        item(
          _pane.showHidden ? l.hideHiddenFiles : l.showHiddenFiles,
          '',
          _pane.toggleHidden,
        ),
        if (selection.isNotEmpty) ...[
          const PopupMenuDivider(),
          item(
            l.deleteEllipsis,
            keysFor('⌘⌫', l.keyDelete),
            _delete,
            danger: true,
          ),
        ],
      ],
    );
    action?.call();
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final pane = _pane;
    final focused = _c.active == widget.side;
    if (focused && !_focus.hasFocus && !_filterFocus.hasFocus) {
      // Tab between sides moves the keyboard here.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _c.active == widget.side && !_filterFocus.hasFocus) {
          _focus.requestFocus();
        }
      });
    }
    final card = _remote ? _connectionCard() : null;
    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        _filterField(),
        if (_remote && _c.phase == Phase.reconnecting && _c.prompts.isEmpty)
          ReconnectBanner(controller: _c),
        _columns(),
        Expanded(child: _list()),
        _footer(),
      ],
    );
    body = Stack(
      children: [
        Positioned.fill(child: body),
        if (_dropping) Positioned.fill(child: _dropOverlay()),
        if (card != null)
          Positioned.fill(
            child: ColoredBox(
              color: c.scrim,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(OwSpace.s8),
                  child: card,
                ),
              ),
            ),
          ),
      ],
    );
    final canDrop = _remote && _c.connected != null && pane.path.isNotEmpty;
    // The builder runs later: it must not see `body` reassigned below.
    final content = body;
    body = DragTarget<FileDrag>(
      onWillAcceptWithDetails: (d) =>
          d.data.from != widget.side &&
          _c.connected != null &&
          pane.path.isNotEmpty,
      onMove: (_) {
        if (!_dropping) setState(() => _dropping = true);
      },
      onLeave: (_) => setState(() => _dropping = false),
      onAcceptWithDetails: (d) {
        setState(() => _dropping = false);
        _copy(d.data.paths, from: d.data.from);
      },
      builder: (context, _, _) => content,
    );
    if (_remote) {
      // Files from the Finder or the Explorer go up to the folder on view.
      body = DropTarget(
        enable: canDrop,
        onDragEntered: (_) => setState(() => _dropping = true),
        onDragExited: (_) => setState(() => _dropping = false),
        onDragDone: (d) {
          setState(() => _dropping = false);
          _copy([for (final f in d.files) f.path], from: Side.local);
        },
        child: body,
      );
    }
    return Semantics(
      label: _remote ? _c.label : l.thisComputer,
      container: true,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
            border: Border.all(
              color: focused ? c.accent.withValues(alpha: 0.6) : c.border,
              width: focused ? 1.5 : 1,
            ),
          ),
          child: body,
        ),
      ),
    );
  }

  Widget? _connectionCard() {
    final c = _c;
    final prompt = c.prompts.isEmpty ? null : c.prompts.first;
    if (prompt != null) {
      return PromptCard(key: ObjectKey(prompt), controller: c, prompt: prompt);
    }
    if (c.everConnected) return null;
    if (c.phase == Phase.connecting) return ConnectingCard(controller: c);
    if (c.phase == Phase.closed) return FailureCard(controller: c);
    return null;
  }

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    Key? key,
    bool on = false,
  }) {
    final c = context.ow.colors;
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      color: on ? c.accentText : c.textMuted,
      icon: Icon(icon),
    );
  }

  Widget _header() {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final pane = _pane;
    final crumbs = pane.crumbs();
    final side = _remote ? Side.remote.name : Side.local.name;
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: OwSpace.s6, right: OwSpace.s2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(
            _remote ? Icons.dns_outlined : Icons.laptop_mac,
            size: 16,
            color: c.textMuted,
          ),
          const SizedBox(width: 7),
          Text(
            _remote ? _c.label : l.thisComputer,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (_remote) ...[
            const SizedBox(width: 6),
            StatusDot(switch (_c.phase) {
              Phase.connected => Status.connected,
              Phase.closed => Status.failed,
              Phase.reconnecting => Status.warning,
              _ => Status.connecting,
            }, size: 7),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      Text(
                        ' / ',
                        style: monoStyle(context, color: c.textSubtle),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(
                        context.ow.shape.radiusSmall,
                      ),
                      onTap: () => pane.open(crumbs[i].$2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: OwSpace.s1,
                        ),
                        child: Text(
                          crumbs[i].$1,
                          style: monoStyle(
                            context,
                            color: i == crumbs.length - 1
                                ? c.text
                                : c.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _iconButton(
            Icons.arrow_upward,
            withKeys(l.upOneLevel, keysFor('⌘↑', 'Ctrl+↑')),
            pane.path.isEmpty ? null : pane.up,
          ),
          _iconButton(
            Icons.refresh,
            withKeys(l.reload, keysFor('⌘R', 'F5')),
            pane.path.isEmpty ? null : pane.refresh,
          ),
          _iconButton(
            Icons.create_new_folder_outlined,
            withKeys(l.newFolder, keysFor('⌘⇧N', '${l.ctrlShiftPrefix}N')),
            pane.path.isEmpty ? null : _newFolder,
            key: ValueKey('$side.newFolder'),
          ),
          _iconButton(
            pane.showHidden ? Icons.visibility : Icons.visibility_outlined,
            pane.showHidden ? l.hideHiddenFiles : l.showHiddenFiles,
            pane.toggleHidden,
            on: pane.showHidden,
          ),
        ],
      ),
    );
  }

  Widget _filterField() {
    final c = context.ow.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s4,
        OwSpace.s4,
        OwSpace.s4,
        OwSpace.s1,
      ),
      child: SizedBox(
        height: heightForText(context, 30),
        child: TextField(
          key: ValueKey('${widget.side.name}.filter'),
          controller: _filter,
          focusNode: _filterFocus,
          onChanged: _pane.setFilter,
          onSubmitted: (_) => _focus.requestFocus(),
          style: const TextStyle(fontSize: OwText.small),
          decoration: InputDecoration(
            isDense: true,
            hintText: l.filterFolder,
            prefixIcon: Icon(Icons.search, size: 15, color: c.textSubtle),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: OwSpace.s4),
              child: Text(
                isApple ? '⌘F' : 'Ctrl+F',
                style: monoStyle(context, size: 12, color: c.textSubtle),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(minHeight: 0),
            contentPadding: const EdgeInsets.symmetric(vertical: OwSpace.s3),
          ),
        ),
      ),
    );
  }

  List<(String, SortBy?, double?)> get _cols {
    final l = context.l10n;
    return [
      (l.colName, SortBy.name, null),
      (l.colSize, SortBy.size, 76),
      (l.colModified, SortBy.modified, 100),
      if (_remote) (l.colPermissions, null, 86),
    ];
  }

  Widget _columns() {
    final c = context.ow.colors;
    final pane = _pane;
    final style = TextStyle(
      fontSize: OwText.small,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: c.textSubtle,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s10,
        OwSpace.s3,
        OwSpace.s10,
        OwSpace.s1,
      ),
      child: Row(
        children: [
          for (final (name, by, width) in _cols)
            _cell(
              width,
              InkWell(
                onTap: by == null ? null : () => pane.sort(by),
                child: Row(
                  mainAxisAlignment: width != null && by == SortBy.size
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        name.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                    if (by != null && pane.sortBy == by)
                      Icon(
                        pane.ascending
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                        size: 16,
                        color: c.textSubtle,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(double? width, Widget child) => width == null
      ? Expanded(child: child)
      : Padding(
          padding: const EdgeInsets.only(left: OwSpace.s6),
          child: SizedBox(width: width, child: child),
        );

  Widget _list() {
    final l = context.l10n;
    final pane = _pane;
    final error = pane.error;
    if (pane.path.isEmpty) {
      if (error != null) {
        return _message(fileErrorText(l, error), error: true, details: error);
      }
      return pane.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : const SizedBox.shrink();
    }
    final rows = pane.visible;
    Widget list;
    if (rows.isEmpty) {
      list = _message(
        pane.filter.isNotEmpty ? l.noMatches(pane.filter) : l.emptyFolder,
      );
    } else {
      list = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: OwSpace.s4),
        itemExtent: _rowHeightIn(context),
        itemCount: rows.length,
        itemBuilder: (context, i) => _row(rows[i]),
      );
    }
    return Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OwSpace.s4,
              OwSpace.s2,
              OwSpace.s4,
              OwSpace.s2,
            ),
            child: Callout(
              tone: Tone.danger,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fileErrorText(l, error),
                      style: const TextStyle(fontSize: OwText.small),
                    ),
                  ),
                  if (error.kind == FileErrorKind.other) DetailsButton(error),
                ],
              ),
            ),
          ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) => _menu(d.globalPosition, null),
            child: Opacity(opacity: pane.loading ? 0.6 : 1, child: list),
          ),
        ),
      ],
    );
  }

  Widget _message(String text, {bool error = false, FileError? details}) {
    final c = context.ow.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OwSpace.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: error ? c.danger : c.textMuted),
            ),
            if (details != null && details.kind == FileErrorKind.other)
              DetailsButton(details),
          ],
        ),
      ),
    );
  }

  Widget _row(FileEntry e) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final pane = _pane;
    final selected = pane.selected.contains(e.name);
    final cursor = pane.cursor == e.name && _c.active == widget.side;
    final icon = switch (e.kind) {
      FileKind.dir => Icons.folder,
      FileKind.link => Icons.link,
      FileKind.other => Icons.memory,
      FileKind.file => Icons.insert_drive_file_outlined,
    };
    final iconColor = e.isDir ? c.info : c.textMuted;
    final muted = TextStyle(fontSize: OwText.small, color: c.textMuted);
    final row = Container(
      decoration: BoxDecoration(
        color: selected ? c.selected : null,
        borderRadius: BorderRadius.circular(ow.shape.radius),
        border: cursor ? Border.all(color: c.accent) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: OwSpace.s6),
      child: Row(
        children: [
          _cell(
            null,
            Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: e.hidden ? c.textMuted : c.text),
                  ),
                ),
                if (e.linkTarget != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '→ ${e.linkTarget}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 12, color: c.info),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _cell(
            76,
            Text(
              e.isDir ? '' : formatSize(l, e.size),
              textAlign: TextAlign.right,
              style: monoStyle(context, color: c.textMuted),
            ),
          ),
          _cell(
            100,
            Text(
              formatDate(l, e.modified),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
          if (_remote)
            _cell(
              86,
              Text(
                e.mode == null ? '' : formatMode(e.mode!),
                style: monoStyle(context, size: 12, color: c.textSubtle),
              ),
            ),
        ],
      ),
    );
    final paths = selected
        ? [for (final s in pane.selection) pane.pathOf(s.name)]
        : [pane.pathOf(e.name)];
    return Listener(
      key: ValueKey('${widget.side.name}.row.${e.name}'),
      onPointerDown: (d) => _pointerDown(e, d),
      onPointerUp: (_) => pane.release(e.name),
      onPointerCancel: (_) => pane.keepSelection(),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _menu(d.globalPosition, e),
        // Nothing else here wants the press: a plain Draggable would take
        // it at once and flash its badge on every click.
        child: MoveDraggable<FileDrag>(
          data: FileDrag(widget.side, paths),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: pane.keepSelection,
          feedback: _DragBadge(count: paths.length, name: e.name),
          child: row,
        ),
      ),
    );
  }

  Widget _footer() {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final pane = _pane;
    final n = pane.selection.length;
    final connected = _c.connected != null && _other.path.isNotEmpty;
    final count = l.itemCount(pane.visible.length);
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: OwSpace.s6, right: OwSpace.s4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: count),
                  if (n > 0) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: pane.selection.every((e) => e.isDir)
                          ? l.selectedCountOnly(n)
                          : l.selectedCount(
                              n,
                              formatSize(l, pane.selectedBytes),
                            ),
                      style: TextStyle(color: c.text),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
          ),
          OutlinedButton(
            key: ValueKey('${widget.side.name}.copy'),
            onPressed: n > 0 && connected ? _copySelection : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              foregroundColor: c.accentText,
              backgroundColor: n > 0 && connected ? c.accentSoft : null,
            ),
            child: Text(
              _remote ? l.downloadArrow : l.uploadToArrow(_otherName),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropOverlay() {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final where = _remote ? '${_c.label}:${_pane.path}' : _pane.path;
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(OwSpace.s2),
        decoration: BoxDecoration(
          color: c.accentSoft.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
          border: Border.all(color: c.accent, width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_upload_outlined, size: 36, color: c.accentText),
              const SizedBox(height: 10),
              Text(
                _remote ? l.dropToUpload : l.dropToDownload,
                style: const TextStyle(
                  fontSize: OwText.heading,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(where, style: monoStyle(context, color: c.accentText)),
              const SizedBox(height: 6),
              Text(
                l.dropAskFirst,
                style: TextStyle(fontSize: OwText.small, color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragBadge extends StatelessWidget {
  const _DragBadge({required this.count, required this.name});

  final int count;
  final String name;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: OwSpace.s5,
          vertical: OwSpace.s3,
        ),
        decoration: BoxDecoration(
          color: c.raised,
          border: Border.all(color: c.control),
          borderRadius: BorderRadius.circular(ow.shape.radius),
          boxShadow: OwElevation.raised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 15,
              color: c.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              count == 1 ? name : l.itemCount(count),
              style: TextStyle(fontSize: OwText.small, color: c.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _SftpStatusBar extends StatelessWidget {
  const _SftpStatusBar({required this.controller});

  final SftpController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ow = context.ow;
        final c = ow.colors;
        final l = context.l10n;
        final s = controller;
        final k = s.phase == Phase.connected ? s.connected : null;
        final pq = k?.postQuantum ?? false;
        final failed = s.phase == Phase.closed && s.closed?.failure != null;
        final hint = TextStyle(fontSize: OwText.small, color: c.textSubtle);
        return Container(
          height: heightForText(context, 30),
          padding: const EdgeInsets.symmetric(horizontal: OwSpace.s6),
          decoration: BoxDecoration(
            color: c.sunken,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Icon(
                k != null
                    ? (pq ? Icons.verified_user_outlined : Icons.lock_outline)
                    : failed
                    ? Icons.error_outline
                    : Icons.hourglass_empty,
                size: 14,
                color: k != null && pq
                    ? c.accent
                    : failed
                    ? c.danger
                    : c.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  k != null
                      ? [
                          l.sftpConnected(s.label),
                          ?viaText(l, s),
                          k.cipher,
                        ].join(' · ')
                      : statusText(l, s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: OwText.small,
                    color: failed ? c.danger : c.textMuted,
                  ),
                ),
              ),
              Text(isApple ? l.sftpKeysApple : l.sftpKeysOther, style: hint),
            ],
          ),
        );
      },
    );
  }
}

/// Permissions exist on this machine too, except on Windows.
final bool isUnix = !Platform.isWindows;
