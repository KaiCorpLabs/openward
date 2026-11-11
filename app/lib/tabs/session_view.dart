import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../terminal/keys.dart';
import '../terminal/palette.dart';

import '../l10n/l10n.dart';
import '../terminal/controller.dart';
import '../terminal/terminal_pane.dart';
import '../tunnels/tunnels_page.dart';
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'close_guard.dart' as guard;
import 'connection_motion.dart';
import 'connection_panels.dart';
import 'find_bar.dart';
import 'drag.dart';
import 'prompt_card.dart';
import 'tab_strip.dart' show menuHint, menuItem;
import 'tabs.dart';
import 'pane_header.dart';
import 'status_bar.dart';

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
                        padding: const EdgeInsets.all(OwSpace.s3),
                        child: alone is Pane
                            ? _PaneFrame(tab: tab, pane: alone)
                            : _Layout(tab: tab, node: panes.root),
                      ),
              ),
              if (active != null)
                ListenableBuilder(
                  listenable: active,
                  builder: (context, _) =>
                      StatusBar(controller: active, panes: panes),
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
          ? PanePicker(tab: tab, pane: pane)
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
  final key = macShortcuts ? '⌘' : l.ctrlShiftPrefix;
  void here(void Function() f) {
    tab.panes.focus(pane);
    f();
  }

  final split = tab.panes.isSplit;
  final partner = tab.panes.swapPartner(pane);
  final names = paneNames(tab.panes, (p) => paneTitle(context, p));
  return [
    const PopupMenuDivider(),
    if (split) ...[
      menuItem(context, l.moveToNewTab, '', () => tabs.moveToNewTab(tab, pane)),
      if (partner != null)
        menuItem(
          context,
          l.swapWith(names[partner] ?? ''),
          '',
          () => tabs.swapPane(tab, pane),
        ),
    ],
    if (pane.controller != null)
      menuItem(
        context,
        l.openOtherHere,
        '',
        () => tabs.openOtherHere(tab, pane),
      ),
    const PopupMenuDivider(),
    menuItem(context, l.splitRight, '${key}D', () {
      here(() => tabs.split(Axis.horizontal));
    }),
    menuItem(context, l.splitDown, macShortcuts ? '⌘⇧D' : '${key}E', () {
      here(() => tabs.split(Axis.vertical));
    }),
    if (split) ...[
      menuItem(
        context,
        l.equalizePanes,
        macShortcuts ? '⌘⌥=' : '',
        () => here(tab.panes.equalize),
      ),
      menuItem(
        context,
        tab.panes.maximized == null ? l.maximizePane : l.restorePanes,
        macShortcuts ? '⌘⇧↩' : '$key↩',
        () => here(tabs.toggleMaximize),
      ),
    ],
    const PopupMenuDivider(),
    menuItem(
      context,
      tab.panes.isSplit ? l.closePane : l.closeTab,
      '${key}W',
      () => guard.closePane(context, tab, pane),
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
    const gap = 8.0;
    final across = split.axis == Axis.horizontal;
    // Made again when the share changes: the same widget would not be.
    Widget layout() => LayoutBuilder(
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
            _Divider(
              panes: tab.panes,
              split: split,
              total: total,
              thickness: gap,
            ),
            Expanded(
              child: _Layout(tab: tab, node: split.second),
            ),
          ],
        );
      },
    );
    return ListenableBuilder(
      listenable: tab.panes.sizes,
      builder: (context, _) => layout(),
    );
  }
}

/// The border between two parts: it lights up under the pointer, drags
/// to share the room, and a double click shares it evenly.
class _Divider extends StatefulWidget {
  const _Divider({
    required this.panes,
    required this.split,
    required this.total,
    required this.thickness,
  });

  final Panes panes;
  final PaneSplit split;
  final double total;
  final double thickness;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final across = widget.split.axis == Axis.horizontal;
    final lit = _hover || widget.panes.resizing;
    return Tooltip(
      message: context.l10n.dividerHint,
      waitDuration: OwMotion.hint,
      child: MouseRegion(
        cursor: across
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          key: ValueKey('pane.divider.${identityHashCode(widget.split)}'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => widget.panes.setResizing(true),
          onPanEnd: (_) => widget.panes.setResizing(false),
          onPanCancel: () => widget.panes.setResizing(false),
          onPanUpdate: (d) => widget.panes.resize(
            widget.split,
            widget.split.ratio +
                (across ? d.delta.dx : d.delta.dy) / widget.total,
          ),
          onDoubleTap: () => widget.panes.equalizeSplit(widget.split),
          child: SizedBox(
            width: across ? widget.thickness : null,
            height: across ? null : widget.thickness,
            child: lit
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: across ? 2 : null,
                        height: across ? null : 2,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(
                            context.ow.shape.radiusSmall,
                          ),
                        ),
                      ),
                      Container(
                        width: across ? widget.thickness : 34,
                        height: across ? 34 : widget.thickness,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(
                            context.ow.shape.radiusSmall,
                          ),
                        ),
                      ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// While a divider is dragged: a pane's size, in columns and rows.
class _GridSize extends StatelessWidget {
  const _GridSize({required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    return IgnorePointer(
      child: Center(
        child: ValueListenableBuilder(
          valueListenable: controller.grid,
          builder: (context, grid, _) => Container(
            padding: const EdgeInsets.symmetric(
              horizontal: OwSpace.s5,
              vertical: OwSpace.s1,
            ),
            decoration: BoxDecoration(
              color: c.raised,
              border: Border.all(color: c.control),
              borderRadius: BorderRadius.circular(context.ow.shape.round),
            ),
            child: Text(
              '${grid.$1} × ${grid.$2}',
              style: monoStyle(context, size: 12, color: c.text),
            ),
          ),
        ),
      ),
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
            child: PaneHeader(tab: tab, pane: pane, active: active),
          ),
          Expanded(
            // A click in the terminal gives it the keyboard; the header's
            // controls do not take it from the pane being typed in.
            child: Listener(
              onPointerDown: (_) =>
                  ref.read(tabsProvider.notifier).focusPaneOf(tab, pane),
              child: controller == null
                  ? PanePicker(tab: tab, pane: pane)
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: PaneContent(
                            controller: controller,
                            active: active,
                            mirrors: () => panes.mirrorsOf(controller),
                            menu: (context) => paneMenu(context, tab, pane),
                          ),
                        ),
                        if (panes.resizing)
                          Positioned.fill(
                            child: _GridSize(controller: controller),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
    return PaneDropTarget(tab: tab, pane: pane, child: frame);
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
        margin: const EdgeInsets.fromLTRB(
          OwSpace.s3,
          OwSpace.s3,
          OwSpace.s3,
          0,
        ),
        padding: const EdgeInsets.fromLTRB(
          OwSpace.s6,
          OwSpace.s3,
          OwSpace.s3,
          OwSpace.s3,
        ),
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
                l.broadcastExit(macShortcuts ? '⌘⇧B' : '${l.ctrlShiftPrefix}B'),
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
    final hostId = controller.hostId;
    // Its group's mark (or its own): a line across the top and its name
    // in the corner, so as not to type into the wrong server.
    final env = hostId == null
        ? null
        : ref.watch(
            libraryProvider.select((lib) => lib.host(hostId)?.environment),
          );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final prompt = c.prompts.isEmpty ? null : c.prompts.first;
        final failed = c.phase == Phase.closed && c.closed?.failure != null;
        // Over a terminal that has nothing to show yet, or whose connection
        // is coming back.
        final Widget? card = prompt != null
            ? PromptCard(key: ObjectKey(prompt), controller: c, prompt: prompt)
            : c.phase == Phase.reconnecting
            ? ReconnectCard(
                controller: c,
                logId: (c.log?.recording ?? false) ? c.log!.id : null,
              )
            : c.everConnected
            ? null
            : c.phase == Phase.connecting && !c.isLocal
            ? ConnectingCard(controller: c)
            : failed
            ? FailureCard(controller: c)
            : null;
        final stalled =
            c.stalledSince != null &&
            card == null &&
            (c.phase == Phase.connected || c.phase == Phase.running);
        final chip = env != null && card == null && !c.findOpen;
        // What goes in the top right corner goes under the mark.
        final corner = (c.findOpen ? 56.0 : 12.0) + (chip ? 30 : 0);
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
            if (env != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 2,
                child: ColoredBox(color: envColors(ow.colors, env.color).fg),
              ),
            if (chip)
              Positioned(
                key: const ValueKey('pane.environment'),
                top: 8,
                right: 12,
                child: IgnorePointer(child: EnvChip(env, big: true)),
              ),
            if (c.findOpen && card == null)
              Positioned(top: 8, right: 12, child: FindBar(controller: c)),
            if (stalled) ...[
              const Positioned(top: 0, left: 0, right: 0, child: StalledBar()),
              Positioned(
                top: corner,
                right: 14,
                child: StalledNotice(controller: c),
              ),
            ],
            if (card == null)
              Positioned(
                top: corner,
                right: 14,
                child: BackToast(controller: c),
              ),
            if (card != null)
              Positioned.fill(
                // A quick connection (a few ms on a local network) never
                // shows its card: only past 400 ms.
                child: Delayed(
                  key: ObjectKey((c, card.runtimeType)),
                  delay: card is ConnectingCard
                      ? OwMotion.showAfter
                      : Duration.zero,
                  child: ColoredBox(
                    color: ow.colors.scrim,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(OwSpace.s8),
                        child: card,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        if (inset && ow.shape.insetTerminal) {
          // A card on the page, with room around the text.
          terminal = Container(
            margin: const EdgeInsets.fromLTRB(
              OwSpace.s2,
              OwSpace.s3,
              OwSpace.s6,
              0,
            ),
            padding: const EdgeInsets.fromLTRB(
              OwSpace.s6,
              OwSpace.s5,
              OwSpace.s3,
              OwSpace.s3,
            ),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: ow.terminal.background,
              borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
              border: Border.all(color: ow.colors.border),
              boxShadow: OwElevation.card,
            ),
            child: terminal,
          );
        }
        return terminal;
      },
    );
  }
}
