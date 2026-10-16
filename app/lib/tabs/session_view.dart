import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../hosts/sidebar.dart' show tabStatus;
import '../terminal/keys.dart';
import '../terminal/palette.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../terminal/controller.dart';
import '../terminal/terminal_pane.dart';
import '../snippets/palette.dart';
import '../tunnels/tunnels_page.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'connection_panels.dart';
import 'find_bar.dart';
import 'messages.dart';
import 'drag.dart';
import 'prompt_card.dart';
import 'tab_strip.dart' show menuHint, menuItem;
import 'tabs.dart';

/// A session tab: its panes (or the one maximized), a banner while
/// broadcasting, and the status line of the active pane.
class TabView extends ConsumerWidget {
  const TabView({super.key, required this.tab});

  final SessionTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: tab.panes,
      builder: (context, _) {
        final ow = context.ow;
        final panes = tab.panes;
        final alone = panes.maximized ?? (panes.isSplit ? null : panes.root);
        final active = panes.active.controller;
        return ColoredBox(
          color: ow.shape.insetTerminal || panes.isSplit
              ? ow.colors.window
              : ow.colors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (panes.broadcast) _BroadcastBanner(tab: tab),
              if (active?.hostId case final host?) TunnelNotices(hostId: host),
              Expanded(
                child: alone is Pane && !panes.isSplit
                    ? _Single(tab: tab, pane: alone)
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: alone is Pane
                            ? _PaneFrame(tab: tab, pane: alone)
                            : _Layout(tab: tab, node: panes.root),
                      ),
              ),
              if (active != null)
                ListenableBuilder(
                  listenable: active,
                  builder: (context, _) =>
                      _StatusBar(controller: active, panes: panes),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A tab with one pane: the terminal fills it, as before panes existed.
class _Single extends StatelessWidget {
  const _Single({required this.tab, required this.pane});

  final SessionTab tab;
  final Pane pane;

  @override
  Widget build(BuildContext context) {
    final c = pane.controller;
    return PaneDropTarget(
      tab: tab,
      pane: pane,
      child: c == null
          ? _PanePicker(tab: tab, pane: pane)
          : PaneContent(
              controller: c,
              active: true,
              inset: true,
              menu: (context) => paneMenu(context, tab, pane),
            ),
    );
  }
}

/// What a terminal's right-click menu adds for its pane: split it,
/// maximize it, close it, and that tabs and hosts can be dropped on it.
List<PopupMenuEntry<VoidCallback>> paneMenu(
  BuildContext context,
  SessionTab tab,
  Pane pane,
) {
  final l = context.l10n;
  final tabs = ProviderScope.containerOf(context).read(tabsProvider.notifier);
  final key = isApple ? '⌘' : l.ctrlShiftPrefix;
  void here(void Function() f) {
    tab.panes.focus(pane);
    f();
  }

  return [
    const PopupMenuDivider(),
    menuItem(context, l.splitRight, '${key}D', () {
      here(() => tabs.split(Axis.horizontal));
    }),
    menuItem(context, l.splitDown, isApple ? '⌘⇧D' : '${key}E', () {
      here(() => tabs.split(Axis.vertical));
    }),
    if (tab.panes.isSplit)
      menuItem(
        context,
        tab.panes.maximized == null ? l.maximizePane : l.restorePanes,
        isApple ? '⌘⇧↩' : '$key↩',
        () => here(tabs.toggleMaximize),
      ),
    const PopupMenuDivider(),
    menuItem(
      context,
      tab.panes.isSplit ? l.closePane : l.closeTab,
      '${key}W',
      () => tabs.closePane(tab, pane),
    ),
    menuHint(context, l.terminalMenuHint),
  ];
}

/// A split: two parts and the handle between them, which drags.
class _Layout extends ConsumerWidget {
  const _Layout({required this.tab, required this.node});

  final SessionTab tab;
  final PaneNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = node;
    if (n is Pane) return _PaneFrame(tab: tab, pane: n);
    final split = n as PaneSplit;
    const gap = 6.0;
    final across = split.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, box) {
        final total = (across ? box.maxWidth : box.maxHeight) - gap;
        final first = total * split.ratio;
        return Flex(
          direction: split.axis,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: across ? first : null,
              height: across ? null : first,
              child: _Layout(tab: tab, node: split.first),
            ),
            MouseRegion(
              cursor: across
                  ? SystemMouseCursors.resizeColumn
                  : SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => tab.panes.resize(
                  split,
                  split.ratio + (across ? d.delta.dx : d.delta.dy) / total,
                ),
                child: SizedBox(
                  width: across ? gap : null,
                  height: across ? null : gap,
                ),
              ),
            ),
            Expanded(
              child: _Layout(tab: tab, node: split.second),
            ),
          ],
        );
      },
    );
  }
}

/// One pane among several: a header saying which host it is, and its
/// terminal. The active one has an accent outline; those that receive a
/// broadcast, a warning one.
class _PaneFrame extends ConsumerWidget {
  const _PaneFrame({required this.tab, required this.pane});

  final SessionTab tab;
  final Pane pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final panes = tab.panes;
    final active = identical(panes.active, pane);
    final receives = panes.receives(pane);
    final controller = pane.controller;
    final frame = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ow.terminal.background,
        borderRadius: BorderRadius.circular(ow.shape.radius),
        border: Border.all(
          color: receives
              ? c.warn
              : active
              ? c.accent
              : c.border,
          width: receives ? 2 : (active ? 1.5 : 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The header drags the pane: to another half, tab or the bar.
          WindowDraggable(
            data: PaneDrag(
              tab,
              pane,
              controller?.displayTitle ?? context.l10n.newPane,
            ),
            child: _PaneHeader(tab: tab, pane: pane, active: active),
          ),
          Expanded(
            // A click in the terminal gives it the keyboard; the header's
            // controls do not take it from the pane being typed in.
            child: Listener(
              onPointerDown: (_) =>
                  ref.read(tabsProvider.notifier).focusPaneOf(tab, pane),
              child: controller == null
                  ? _PanePicker(tab: tab, pane: pane)
                  : PaneContent(
                      controller: controller,
                      active: active,
                      mirrors: () => panes.mirrorsOf(controller),
                      menu: (context) => paneMenu(context, tab, pane),
                    ),
            ),
          ),
        ],
      ),
    );
    return PaneDropTarget(tab: tab, pane: pane, child: frame);
  }
}

class _PaneHeader extends ConsumerWidget {
  const _PaneHeader({
    required this.tab,
    required this.pane,
    required this.active,
  });

  final SessionTab tab;
  final Pane pane;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final panes = tab.panes;
    final tabs = ref.read(tabsProvider.notifier);
    final receives = panes.receives(pane);
    final controller = pane.controller;
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    PopupMenuItem<VoidCallback> item(
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
    Widget title(TerminalController? s) => Row(
      children: [
        if (s != null) ...[
          StatusDot(tabStatus(s), size: 7),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            s?.displayTitle ?? l.newPane,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: active ? c.text : c.textMuted,
            ),
          ),
        ),
      ],
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: receives
            ? c.warnSoft
            : active
            ? c.raised
            : c.sunken,
        border: Border(
          bottom: BorderSide(color: receives ? c.warnLine : c.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: controller == null
                ? title(null)
                : ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => title(controller),
                  ),
          ),
          if (panes.broadcast && controller != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 24,
                  child: Checkbox(
                    value: receives,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) {
                      panes.setReceives(pane, v ?? false);
                      tabs.focusActive(tab);
                    },
                  ),
                ),
                Text(
                  l.receives,
                  style: TextStyle(
                    fontSize: 11,
                    color: receives ? c.warn : c.textMuted,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          PopupMenuButton<VoidCallback>(
            tooltip: l.paneOptions,
            iconSize: 16,
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_horiz, size: 16, color: c.textMuted),
            onSelected: (f) {
              f();
              tabs.focusActive(tab);
            },
            onCanceled: () => tabs.focusActive(tab),
            itemBuilder: (_) => [
              item(l.splitRight, isApple ? '⌘D' : '${key}D', () {
                panes.focus(pane);
                tabs.split(Axis.horizontal);
              }),
              item(l.splitDown, isApple ? '⌘⇧D' : '${key}E', () {
                panes.focus(pane);
                tabs.split(Axis.vertical);
              }),
              if (panes.isSplit)
                item(
                  panes.maximized == null ? l.maximizePane : l.restorePanes,
                  isApple ? '⌘⇧↩' : '$key↩',
                  () {
                    panes.focus(pane);
                    tabs.toggleMaximize();
                  },
                ),
              const PopupMenuDivider(),
              if (panes.isSplit)
                item(
                  panes.broadcast ? l.broadcastOff : l.broadcastOn,
                  isApple ? '⌘⇧B' : '${key}B',
                  tabs.toggleBroadcast,
                ),
              item(
                l.closePane,
                isApple ? '⌘W' : '${key}W',
                () => tabs.closePane(tab, pane),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A new pane: what to open in it. Enter takes the highlighted choice,
/// the arrows move, Esc closes the pane.
class _PanePicker extends ConsumerStatefulWidget {
  const _PanePicker({required this.tab, required this.pane});

  final SessionTab tab;
  final Pane pane;

  @override
  ConsumerState<_PanePicker> createState() => _PanePickerState();
}

class _PanePickerState extends ConsumerState<_PanePicker> {
  final _query = TextEditingController();
  int _at = 0;

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
    final tabs = ref.read(tabsProvider.notifier);
    final library = ref.watch(libraryProvider);
    final from = widget.pane.from;
    final q = _query.text.trim().toLowerCase();
    // (label, detail, open)
    final choices = <(String, String?, VoidCallback)>[
      if (from != null && q.isEmpty)
        (from.label, l.sameHost, () => tabs.fillSame(widget.tab, widget.pane)),
      for (final h in library.hosts)
        if (q.isEmpty
            ? h.id != from?.hostId
            : h.label.toLowerCase().contains(q) ||
                  h.address.toLowerCase().contains(q))
          (
            h.label,
            null,
            () => tabs.fillPane(widget.tab, widget.pane, host: h),
          ),
      if (q.isEmpty || l.localTerminal.toLowerCase().contains(q))
        (l.localTerminal, null, () => tabs.fillPane(widget.tab, widget.pane)),
    ];
    final at = choices.isEmpty ? 0 : _at.clamp(0, choices.length - 1);
    return ColoredBox(
      color: c.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  tabs.closePane(widget.tab, widget.pane),
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (choices.isNotEmpty) choices[at].$3();
              },
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  setState(() => _at = (at + 1).clamp(0, choices.length - 1)),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  setState(() => _at = (at - 1).clamp(0, choices.length - 1)),
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.raised,
                border: Border.all(color: c.control),
                borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.paneWhat,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('pane.search'),
                    controller: _query,
                    autofocus: true,
                    style: fieldTextStyle(context),
                    decoration: InputDecoration(hintText: l.searchHosts),
                    onChanged: (_) => setState(() => _at = 0),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < choices.length && i < 8; i++)
                    Material(
                      color: i == at ? c.selected : Colors.transparent,
                      borderRadius: BorderRadius.circular(ow.shape.radius),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(ow.shape.radius),
                        onTap: choices[i].$3,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    text: choices[i].$1,
                                    children: [
                                      if (choices[i].$2 != null)
                                        TextSpan(
                                          text: ' · ${choices[i].$2}',
                                          style: TextStyle(color: c.textMuted),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (i == at) const KeyCap('↩'),
                            ],
                          ),
                        ),
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

/// Across the top of a tab that broadcasts: where typing goes, and the way
/// out. Always visible while it is on.
class _BroadcastBanner extends ConsumerWidget {
  const _BroadcastBanner({required this.tab});

  final SessionTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final panes = tab.panes;
    final names = [
      for (final p in panes.leaves)
        if (panes.receives(p)) p.controller!.displayTitle,
    ];
    // Ink on the warning color, whichever reads better.
    final ink =
        TermPalette.contrast(const Color(0xFF1E1408), c.warn) >=
            TermPalette.contrast(const Color(0xFFFFFFFF), c.warn)
        ? const Color(0xFF1E1408)
        : const Color(0xFFFFFFFF);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: c.warn,
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        ),
        child: Row(
          children: [
            Icon(Icons.podcasts, size: 16, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.broadcastBanner(
                  names.length,
                  panes.leaves.length,
                  names.join(', '),
                ),
                style: TextStyle(color: ink, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const ValueKey('broadcast.exit'),
              onPressed: ref.read(tabsProvider.notifier).toggleBroadcast,
              style: TextButton.styleFrom(
                backgroundColor: ink,
                foregroundColor: c.warn,
              ),
              child: Text(
                l.broadcastExit(isApple ? '⌘⇧B' : '${l.ctrlShiftPrefix}B'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One session's terminal and whatever its connection needs to say over
/// it (a question, progress, a failure, a reconnection).
class PaneContent extends ConsumerWidget {
  const PaneContent({
    super.key,
    required this.controller,
    required this.active,
    this.inset = false,
    this.mirrors,
    this.menu,
  });

  final TerminalController controller;

  /// What the terminal's right-click menu adds for its pane.
  final List<PopupMenuEntry<VoidCallback>> Function(BuildContext)? menu;

  /// Has the keyboard.
  final bool active;

  /// The theme's terminal card, when it has one (a tab with one pane).
  final bool inset;

  /// Other panes that get what is typed here (broadcast).
  final List<TerminalController> Function()? mirrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final prompt = c.prompts.isEmpty ? null : c.prompts.first;
        final failed = c.phase == Phase.closed && c.closed?.failure != null;
        // Over a terminal that has nothing to show yet.
        final Widget? card = prompt != null
            ? PromptCard(key: ObjectKey(prompt), controller: c, prompt: prompt)
            : c.everConnected
            ? null
            : c.phase == Phase.connecting && !c.isLocal
            ? ConnectingCard(controller: c)
            : failed
            ? FailureCard(controller: c)
            : null;
        Widget terminal = Stack(
          children: [
            Positioned.fill(
              child: TerminalPane(
                // One pane per session: its focus and input method stay
                // with it.
                key: ObjectKey(c),
                controller: c,
                autofocus: active && card == null && !c.findOpen,
                mirrors: mirrors,
                paneMenu: menu,
              ),
            ),
            Positioned.fill(child: BellFlash(controller: c)),
            if (c.findOpen && card == null)
              Positioned(top: 8, right: 12, child: FindBar(controller: c)),
            if (card != null)
              Positioned.fill(
                child: ColoredBox(
                  color: ow.colors.scrim,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: card,
                    ),
                  ),
                ),
              ),
          ],
        );
        if (inset && ow.shape.insetTerminal) {
          // A card on the page, with room around the text.
          terminal = Container(
            margin: const EdgeInsets.fromLTRB(4, 6, 12, 0),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: ow.terminal.background,
              borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
              border: Border.all(color: ow.colors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14281E0A),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: terminal,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.phase == Phase.reconnecting && prompt == null)
              ReconnectBanner(controller: c),
            Expanded(child: terminal),
          ],
        );
      },
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar({required this.controller, this.panes});

  final TerminalController controller;
  final Panes? panes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = controller;
    final failure = s.closed?.failure;
    final failed =
        s.phase == Phase.closed && (failure != null || s.error != null);
    final k = s.phase == Phase.connected ? s.connected : null;
    final pq = k?.postQuantum ?? false;
    final color = failed ? c.danger : c.textMuted;
    final small = TextStyle(fontSize: 12, color: color);
    final Widget line;
    if (k != null) {
      final via = viaText(l, s);
      line = Row(
        children: [
          Icon(
            pq ? Icons.verified_user_outlined : Icons.lock_outline,
            size: 14,
            color: pq ? c.accent : c.textMuted,
          ),
          const SizedBox(width: 8),
          Text(
            l.statusConnected,
            style: TextStyle(
              fontSize: 12,
              color: c.text,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (pq) ...[const SizedBox(width: 8), Pill(l.postQuantum)],
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              [k.kex, k.cipher, ?via].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 11),
            ),
          ),
        ],
      );
    } else {
      line = Row(
        children: [
          Icon(
            switch (s.phase) {
              Phase.connecting => Icons.hourglass_empty,
              Phase.reconnecting => Icons.sync,
              Phase.connected => Icons.lock_outline,
              Phase.running => Icons.computer,
              Phase.closed => failed ? Icons.error_outline : Icons.link_off,
            },
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText(l, s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
          ),
        ],
      );
    }
    final inset = ow.shape.insetTerminal;
    return Container(
      height: 30,
      padding: EdgeInsets.symmetric(horizontal: inset ? 16 : 12),
      decoration: BoxDecoration(
        color: inset ? c.window : c.sunken,
        border: inset ? null : Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (panes?.broadcast ?? false)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                l.broadcastStatus(panes!.receiving),
                style: TextStyle(
                  fontSize: 12,
                  color: c.warn,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: k != null
                ? Tooltip(
                    message: l.connectionDetails,
                    child: InkWell(
                      onTap: () => showConnectionInfo(context, s),
                      child: line,
                    ),
                  )
                : line,
          ),
          if (failure?.kind == FailureKind.hostKeyChanged)
            TextButton(
              onPressed: () => showHostKeyChanged(context, ref, s),
              child: Text(l.reviewKey),
            ),
          if (k != null && s.hostId != null)
            TunnelChip(hostId: s.hostId!, hostLabel: s.label),
          if (s.phase == Phase.connected || s.phase == Phase.running)
            TextButton.icon(
              key: const ValueKey('status.snippets'),
              onPressed: () => showSnippetPalette(context),
              icon: const Icon(Icons.terminal, size: 14),
              label: Text('${l.snippets} ${isApple ? '⌘⇧S' : 'Ctrl+Shift+S'}'),
            ),
          if (k != null)
            TextButton.icon(
              key: const ValueKey('status.sftp'),
              onPressed: () => ref
                  .read(tabsProvider.notifier)
                  .openSftp(hostId: s.hostId, target: s.target, label: s.label),
              icon: const Icon(Icons.folder_outlined, size: 14),
              label: Text('${l.openSftp} ${isApple ? '⌘⇧O' : 'Ctrl+Shift+O'}'),
            ),
          if (s.phase == Phase.closed)
            TextButton.icon(
              onPressed: s.start,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(s.isLocal ? l.restart : l.reconnect),
            ),
        ],
      ),
    );
  }
}
