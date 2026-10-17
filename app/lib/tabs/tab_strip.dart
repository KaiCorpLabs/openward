import 'package:flutter/gestures.dart'
    show kMiddleMouseButton, kPrimaryMouseButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hosts/sidebar.dart' show tabStatus;
import '../l10n/l10n.dart';
import '../sftp/queue_view.dart';
import '../terminal/controller.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/chrome.dart';
import '../workspaces/workspaces_page.dart';
import 'drag.dart';
import 'tabs.dart';

/// The row of tabs at the top of the window: click to bring to front, drag
/// to reorder (or onto a terminal, to split it), double-click to rename,
/// right-click for a menu, middle-click or × to close. Panes and hosts
/// dropped on it get a tab of their own. Its empty part moves the window,
/// as a title bar does.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final ow = context.ow;
    final l = context.l10n;
    final style = ow.shape.tabs;
    // Folder tabs sit on the line under the bar; blocks fill the bar; pills
    // and segments float in the middle of it.
    final (
      double height,
      double gap,
      CrossAxisAlignment align,
    ) = switch (style) {
      TabStyle.folder => (33, 2, CrossAxisAlignment.end),
      TabStyle.pill => (30, 6, CrossAxisAlignment.center),
      TabStyle.block => (topBarHeight - 1, 0, CrossAxisAlignment.start),
      TabStyle.segment => (28, 4, CrossAxisAlignment.center),
    };
    return Container(
      height: topBarHeight,
      decoration: BoxDecoration(
        color: ow.colors.window,
        border: style == TabStyle.pill
            ? null
            : Border(bottom: BorderSide(color: ow.colors.border)),
      ),
      padding: EdgeInsets.only(left: style == TabStyle.block ? 0 : 6),
      child: Row(
        crossAxisAlignment: align,
        children: [
          Flexible(
            child: SizedBox(
              height: height,
              child: _TabRow(
                state: state,
                gap: gap,
                onRename: (i) => _rename(context, ref, i),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 2,
              bottom: style == TabStyle.folder ? 3 : 0,
              top: style == TabStyle.block ? 4 : 0,
            ),
            child: IconButton(
              tooltip: l.newLocalTerminal,
              icon: const Icon(Icons.add, size: 16),
              onPressed: tabs.openLocal,
            ),
          ),
          const Expanded(child: WindowDragArea()),
          const TransferIndicator(),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, int index) async {
    final tab = ref.read(tabsProvider).tabs[index];
    if (tab is! SessionTab) return;
    final l = context.l10n;
    final field = TextEditingController(
      text: tab.controller?.displayTitle ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.renameTabTitle),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: field,
            autofocus: true,
            decoration: InputDecoration(helperText: l.renameTabHelp),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(l.rename),
          ),
        ],
      ),
    );
    field.dispose();
    if (name != null) ref.read(tabsProvider.notifier).rename(index, name);
  }
}

/// The tabs, each draggable, and where something dragged over them would
/// land: a line in the gap.
class _TabRow extends ConsumerStatefulWidget {
  const _TabRow({
    required this.state,
    required this.gap,
    required this.onRename,
  });

  final TabsState state;
  final double gap;
  final ValueChanged<int> onRename;

  @override
  ConsumerState<_TabRow> createState() => _TabRowState();
}

class _TabRowState extends ConsumerState<_TabRow> {
  final Map<OpenTab, GlobalKey> _keys = {};
  final GlobalKey _row = GlobalKey();

  /// The gap something dragged would land in: 0 is before the first tab.
  int? _over;

  /// The tab in front before a press brought another: while that one is
  /// dragged, this one stays in view, to drop it on.
  OpenTab? _before;

  GlobalKey _key(OpenTab t) => _keys.putIfAbsent(t, GlobalKey.new);

  /// The gap nearest to a point of the screen.
  int _gapAt(Offset global) {
    final tabs = widget.state.tabs;
    for (var i = 0; i < tabs.length; i++) {
      final box = _keys[tabs[i]]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      if (global.dx < center.dx) return i;
    }
    return tabs.length;
  }

  /// Where the line of a gap goes, from the left of the row.
  double? _lineAt(int gap) {
    final tabs = widget.state.tabs;
    final row = _row.currentContext?.findRenderObject();
    if (row is! RenderBox || tabs.isEmpty) return null;
    final at = gap < tabs.length ? tabs[gap] : tabs.last;
    final box = _keys[at]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final edge = gap < tabs.length
        ? Offset.zero
        : Offset(box.size.width - widget.gap, 0);
    return row.globalToLocal(box.localToGlobal(edge)).dx;
  }

  void _drop(WindowDrag d) {
    final gap = _over;
    setState(() => _over = null);
    if (gap == null || dragCancelled.value) return;
    final tabs = ref.read(tabsProvider.notifier);
    switch (d) {
      case TabDrag(:final tab):
        final from = widget.state.tabs.indexOf(tab);
        if (from >= 0) tabs.moveToGap(from, gap);
        // Reordered, it comes to the front, as in a browser.
        final now = ref.read(tabsProvider).tabs.indexOf(tab);
        if (now >= 0) tabs.select(now);
      case PaneDrag(:final tab, :final pane):
        tabs.detachPane(tab, pane, gap);
      case HostDrag(:final host):
        tabs.openHostAt(host, gap);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final tabs = ref.read(tabsProvider.notifier);
    final c = context.ow.colors;
    _keys.removeWhere((t, _) => !state.tabs.contains(t));
    return DragTarget<WindowDrag>(
      onMove: (d) {
        final gap = _gapAt(d.offset);
        if (gap != _over) setState(() => _over = gap);
      },
      onLeave: (_) => setState(() => _over = null),
      onAcceptWithDetails: (d) => _drop(d.data),
      builder: (context, candidates, _) {
        final line = _over == null || candidates.isEmpty
            ? null
            : _lineAt(_over!);
        return Stack(
          key: _row,
          clipBehavior: Clip.none,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, t) in state.tabs.indexed)
                    WindowDraggable(
                      key: ObjectKey(t),
                      data: TabDrag(t, tabTitle(context, t)),
                      onStarted: () {
                        final before = _before;
                        if (before == null || identical(before, t)) return;
                        final at = ref.read(tabsProvider).tabs.indexOf(before);
                        if (at >= 0) tabs.select(at);
                      },
                      child: Padding(
                        key: _key(t),
                        padding: EdgeInsets.only(right: widget.gap),
                        child: _Tab(
                          tab: t,
                          active: i == state.active,
                          onSelect: () {
                            _before = ref.read(tabsProvider).current;
                            tabs.select(i);
                          },
                          onClose: () => tabs.close(i),
                          onRename: () => widget.onRename(i),
                          onMenu: (at) => _menu(context, i, at),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (line != null)
              ValueListenableBuilder(
                valueListenable: dragCancelled,
                builder: (context, cancelled, _) => cancelled
                    ? const SizedBox.shrink()
                    : Positioned(
                        left: line - 2,
                        top: 4,
                        bottom: 4,
                        child: IgnorePointer(
                          child: Container(
                            width: 3,
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }

  /// Right-click on a tab: what can be done with it, and that it drags.
  Future<void> _menu(BuildContext context, int index, Offset at) async {
    final l = context.l10n;
    final tabs = ref.read(tabsProvider.notifier);
    final tab = widget.state.tabs[index];
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    final split = tab is SessionTab && tab.panes.isSplit;
    final many = widget.state.tabs.length > 1;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        if (tab is SessionTab) ...[
          menuItem(context, l.renameTab, '', () => widget.onRename(index)),
          menuItem(context, l.duplicateTab, '', () => tabs.duplicate(index)),
          const PopupMenuDivider(),
          menuItem(context, l.splitRight, '${key}D', () {
            tabs.select(index);
            tabs.split(Axis.horizontal);
          }),
          menuItem(context, l.splitDown, isApple ? '⌘⇧D' : '${key}E', () {
            tabs.select(index);
            tabs.split(Axis.vertical);
          }),
          if (split)
            menuItem(context, l.separatePanes, '', () => tabs.separate(index)),
          const PopupMenuDivider(),
        ],
        menuItem(context, l.closeTab, '${key}W', () => tabs.close(index)),
        if (many)
          menuItem(
            context,
            l.closeOtherTabs,
            '',
            () => tabs.closeOthers(index),
          ),
        const PopupMenuDivider(),
        menuItem(
          context,
          l.saveOpenTabs,
          '',
          () => saveWorkspaceDialog(context, ref),
        ),
        menuHint(context, l.tabMenuHint),
      ],
    );
    action?.call();
  }
}

/// A tab's name, as its label says.
String tabTitle(BuildContext context, OpenTab tab) {
  final l = context.l10n;
  return switch (tab) {
    SessionTab(:final panes) =>
      (panes.active.controller ?? panes.controllers.firstOrNull)
              ?.displayTitle ??
          l.newPane,
    SftpTab(:final controller) => l.sftpTabTitle(controller.label),
    PageTab(:final page) => switch (page) {
      PageKind.settings => l.settings,
      PageKind.tunnels => l.tunnels,
      PageKind.identities => l.identities,
      PageKind.keys => l.keys,
      PageKind.snippets => l.snippets,
      PageKind.workspaces => l.workspaces,
      PageKind.knownHosts => l.knownHosts,
    },
  };
}

/// A row of a context menu: what it does, and its shortcut.
PopupMenuItem<VoidCallback> menuItem(
  BuildContext context,
  String text,
  String keys,
  VoidCallback f,
) => PopupMenuItem(
  value: f,
  height: 34,
  child: Row(
    children: [
      Expanded(child: Text(text)),
      const SizedBox(width: 16),
      Text(keys, style: monoStyle(context, size: 11)),
    ],
  ),
);

/// The last line of a menu: a note, not an action.
PopupMenuItem<VoidCallback> menuHint(BuildContext context, String text) {
  final c = context.ow.colors;
  return PopupMenuItem(
    enabled: false,
    height: 40,
    child: SizedBox(
      width: 260,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.open_with, size: 13, color: c.textSubtle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: c.textSubtle, height: 1.35),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onRename,
    required this.onMenu,
  });

  final OpenTab tab;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback onRename;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      SessionTab(:final panes) => ListenableBuilder(
        listenable: Listenable.merge([panes, ...panes.controllers]),
        builder: (context, _) {
          final all = panes.controllers.toList();
          // The active pane's session; the first while it asks what to open.
          final shown = panes.active.controller ?? all.firstOrNull;
          final more = panes.leaves.length - 1;
          final c = context.ow.colors;
          return _frame(
            context,
            leading: panes.broadcast
                ? Icon(Icons.podcasts, size: 14, color: c.warn)
                : shown == null
                ? const SizedBox(width: 7)
                : StatusDot(
                    tabStatus(shown),
                    size: 7,
                    // On an accent block the accent would not show.
                    onAccent: active && context.ow.shape.tabs == TabStyle.block
                        ? c.onPrimary
                        : null,
                  ),
            title: '${shown?.displayTitle ?? ''}${more > 0 ? ' +$more' : ''}',
            waiting: all.any((s) => s.prompts.isNotEmpty),
            bell: all.any((s) => s.bellUnseen),
            onRename: onRename,
          );
        },
      ),
      SftpTab(:final controller) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = context.ow.colors;
          return _frame(
            context,
            leading: Icon(
              Icons.folder_outlined,
              size: 14,
              color: active && context.ow.shape.tabs == TabStyle.block
                  ? c.onPrimary
                  : switch (controller.phase) {
                      Phase.connected => c.accent,
                      Phase.closed => c.danger,
                      _ => c.textMuted,
                    },
            ),
            title: context.l10n.sftpTabTitle(controller.label),
            waiting: controller.prompts.isNotEmpty,
          );
        },
      ),
      PageTab(:final page) => _frame(
        context,
        leading: Icon(switch (page) {
          PageKind.settings => Icons.settings_outlined,
          PageKind.tunnels => Icons.swap_horiz,
          PageKind.identities => Icons.badge_outlined,
          PageKind.keys => Icons.key_outlined,
          PageKind.snippets => Icons.terminal,
          PageKind.workspaces => Icons.dashboard_outlined,
          PageKind.knownHosts => Icons.verified_user_outlined,
        }, size: 14),
        title: tabTitle(context, tab),
      ),
    };
  }

  Widget _frame(
    BuildContext context, {
    required Widget leading,
    required String title,
    bool waiting = false,
    bool bell = false,
    VoidCallback? onRename,
  }) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final style = ow.shape.tabs;
    // The active tab inverted: ink pills, accent blocks.
    final inverted =
        active && (style == TabStyle.pill || style == TabStyle.block);
    final fg = inverted
        ? c.onPrimary
        : active || style == TabStyle.pill
        ? c.text
        : c.textMuted;
    final decoration = switch (style) {
      TabStyle.pill => BoxDecoration(
        color: active ? c.primary : c.raised,
        borderRadius: BorderRadius.circular(999),
        border: active ? null : Border.all(color: c.border),
      ),
      TabStyle.block => BoxDecoration(
        color: active ? c.accent : Colors.transparent,
        border: Border(right: BorderSide(color: c.border)),
      ),
      TabStyle.segment => BoxDecoration(
        color: active ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(ow.shape.radius),
      ),
      TabStyle.folder => BoxDecoration(
        color: active ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ow.shape.radius + 1),
        ),
        border: active
            ? Border(
                top: BorderSide(color: c.border),
                left: BorderSide(color: c.border),
                right: BorderSide(color: c.border),
              )
            : null,
      ),
    };
    return Semantics(
      selected: active,
      button: true,
      label: title,
      child: Listener(
        // At once on press, without waiting to tell a click from a double
        // click; middle click closes, as in browsers.
        onPointerDown: (e) {
          if (e.buttons == kPrimaryMouseButton) onSelect();
          if (e.buttons == kMiddleMouseButton) onClose();
          if (e.buttons == kSecondaryMouseButton) onMenu(e.position);
        },
        child: GestureDetector(
          onDoubleTap: onRename,
          child: Container(
            constraints: const BoxConstraints(minWidth: 96, maxWidth: 220),
            padding: EdgeInsets.only(left: 12, right: active ? 2 : 12),
            decoration: decoration,
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  const SizedBox(width: 8),
                  if (bell)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: l.bellRang,
                        child: Icon(
                          Icons.notifications_active_outlined,
                          size: 14,
                          color: inverted ? fg : c.warn,
                        ),
                      ),
                    ),
                  if (waiting)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: l.waitingForYou,
                        child: Icon(
                          Icons.help_outline,
                          size: 14,
                          color: inverted ? fg : c.warn,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ExcludeSemantics(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: fg,
                          fontWeight: active
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  if (active)
                    IconButton(
                      tooltip: l.closeTab,
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      color: fg,
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
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
