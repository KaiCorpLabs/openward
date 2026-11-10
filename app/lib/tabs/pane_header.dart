// A pane's header: what it shows and its menu; and the picker an empty
// pane asks with.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/match.dart';
import '../core/providers.dart';
import '../hosts/sidebar.dart' show tabStatus;
import '../terminal/keys.dart';

import '../l10n/l10n.dart';
import '../logs/log_chip.dart';
import '../src/rust/api/vault.dart' show EnvironmentView, HostView;
import '../terminal/controller.dart';
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'close_guard.dart' as guard;
import 'drag.dart';
import 'tab_strip.dart' show tabTitle;
import 'tabs.dart';

class PaneHeader extends ConsumerWidget {
  const PaneHeader({
    super.key,
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
    final key = macShortcuts ? '⌘' : l.ctrlShiftPrefix;
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
          Text(keys, style: monoStyle(context, size: 12)),
        ],
      ),
    );
    // Numbered where two are alike: «Local 1», «Local 2».
    final names = paneNames(panes, (p) => paneTitle(context, p));
    final partner = panes.swapPartner(pane);
    Widget title(TerminalController? s) => Row(
      children: [
        // The header drags the pane: the grip says so.
        Tooltip(
          message: l.dragPaneHint,
          child: Icon(Icons.drag_indicator, size: 14, color: c.textSubtle),
        ),
        const SizedBox(width: 4),
        if (s != null) ...[
          StatusDot(tabStatus(s), size: 7),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            names[pane] ?? l.newPane,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: OwText.small,
              fontWeight: FontWeight.w500,
              color: active ? c.text : c.textMuted,
            ),
          ),
        ),
      ],
    );
    // 28 inside its line, for the controls in it.
    return Container(
      height: 29,
      padding: const EdgeInsets.only(left: OwSpace.s2, right: OwSpace.s1),
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
          // The box and its word, one target: a click on either.
          if (panes.broadcast && controller != null)
            MergeSemantics(
              child: InkWell(
                key: const ValueKey('pane.receives'),
                borderRadius: BorderRadius.circular(context.ow.shape.radius),
                onTap: () {
                  panes.setReceives(pane, !receives);
                  tabs.focusActive(tab);
                },
                child: SizedBox(
                  height: 28,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 28,
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
                          fontSize: OwText.small,
                          color: receives ? c.warn : c.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
          if (controller != null)
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(left: OwSpace.s3),
                child: LogChip(
                  controller: controller,
                  onDone: () => tabs.focusActive(tab),
                ),
              ),
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
              if (panes.isSplit) ...[
                item(l.moveToNewTab, '', () => tabs.moveToNewTab(tab, pane)),
                if (partner != null)
                  item(
                    l.swapWith(names[partner] ?? ''),
                    '',
                    () => tabs.swapPane(tab, pane),
                  ),
              ],
              if (controller != null)
                item(l.openOtherHere, '', () => tabs.openOtherHere(tab, pane)),
              if (panes.isSplit || controller != null) const PopupMenuDivider(),
              item(l.splitRight, macShortcuts ? '⌘D' : '${key}D', () {
                panes.focus(pane);
                tabs.split(Axis.horizontal);
              }),
              item(l.splitDown, macShortcuts ? '⌘⇧D' : '${key}E', () {
                panes.focus(pane);
                tabs.split(Axis.vertical);
              }),
              if (panes.isSplit) ...[
                item(
                  l.equalizePanes,
                  macShortcuts ? '⌘⌥=' : '',
                  panes.equalize,
                ),
                item(
                  panes.maximized == null ? l.maximizePane : l.restorePanes,
                  macShortcuts ? '⌘⇧↩' : '$key↩',
                  () {
                    panes.focus(pane);
                    tabs.toggleMaximize();
                  },
                ),
              ],
              const PopupMenuDivider(),
              if (panes.isSplit)
                item(
                  panes.broadcast ? l.broadcastOff : l.broadcastOn,
                  macShortcuts ? '⌘⇧B' : '${key}B',
                  tabs.toggleBroadcast,
                ),
              item(
                l.closePane,
                macShortcuts ? '⌘W' : '${key}W',
                () => guard.closePane(context, tab, pane),
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
/// One thing a new pane can open.
class _Choice {
  const _Choice({
    required this.section,
    required this.title,
    required this.lead,
    required this.open,
    this.detail,
    this.env,
  });

  final String section;
  final String title;
  final String? detail;
  final Widget lead;
  final EnvironmentView? env;
  final VoidCallback open;
}

class PanePicker extends ConsumerStatefulWidget {
  const PanePicker({super.key, required this.tab, required this.pane});

  final SessionTab tab;
  final Pane pane;

  @override
  ConsumerState<PanePicker> createState() => _PanePickerState();
}

class _PanePickerState extends ConsumerState<PanePicker> {
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
    bool matches(String text) => q.isEmpty || text.toLowerCase().contains(q);
    final hosts = HostMatcher(q, library);
    final state = ref.watch(tabsProvider);
    HostView? hostOf(String? id) => id == null ? null : library.host(id);
    Widget badgeOf(HostView? h) => h == null
        ? SizedBox(
            width: 28,
            child: Icon(Icons.terminal, size: 15, color: c.textMuted),
          )
        : SystemBadge(code: h.system?.code, env: h.environment, size: 22);
    // Tabs already open first: they move into this pane.
    final open = [
      for (final t in state.tabs)
        if (t is SessionTab &&
            !identical(t, widget.tab) &&
            matches(tabTitle(context, t)))
          t,
    ];
    final fromHost = hostOf(from?.hostId);
    final choices = <_Choice>[
      for (final t in open)
        _Choice(
          section: l.paneOpenTabs,
          title: tabTitle(context, t),
          lead: badgeOf(hostOf(t.panes.active.controller?.hostId)),
          env: hostOf(t.panes.active.controller?.hostId)?.environment,
          open: () => tabs.bringTab(t, widget.tab, widget.pane),
        ),
      if (from != null && q.isEmpty)
        _Choice(
          section: l.paletteHosts,
          title: from.label,
          detail: l.sameHost,
          lead: badgeOf(fromHost),
          env: fromHost?.environment,
          open: () => tabs.fillSame(widget.tab, widget.pane),
        ),
      for (final h in q.isEmpty ? library.hosts : hosts.filter(library.hosts))
        if (q.isNotEmpty || h.id != from?.hostId)
          _Choice(
            section: l.paletteHosts,
            title: h.label,
            lead: badgeOf(h),
            env: h.environment,
            open: () => tabs.fillPane(widget.tab, widget.pane, host: h),
          ),
      if (matches(l.localTerminal))
        _Choice(
          section: l.thisComputer,
          title: l.localTerminal,
          lead: badgeOf(null),
          open: () => tabs.fillPane(widget.tab, widget.pane),
        ),
    ];
    final at = choices.isEmpty ? 0 : _at.clamp(0, choices.length - 1);
    return ColoredBox(
      color: c.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OwSpace.s6),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  tabs.closePane(widget.tab, widget.pane),
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (choices.isNotEmpty) choices[at].open();
              },
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  setState(() => _at = (at + 1).clamp(0, choices.length - 1)),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  setState(() => _at = (at - 1).clamp(0, choices.length - 1)),
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(OwSpace.s6),
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
                    decoration: InputDecoration(hintText: l.paneSearch),
                    onChanged: (_) => setState(() => _at = 0),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < choices.length && i < 10; i++) ...[
                    if (i == 0 || choices[i].section != choices[i - 1].section)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          OwSpace.s4,
                          OwSpace.s5,
                          OwSpace.s4,
                          OwSpace.s2,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: SectionLabel(choices[i].section)),
                            if (choices[i].section == l.paneOpenTabs)
                              Text(
                                l.paneOpenTabsNote,
                                style: TextStyle(
                                  fontSize: OwText.small,
                                  color: c.textSubtle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    Material(
                      color: i == at ? c.selected : Colors.transparent,
                      borderRadius: BorderRadius.circular(ow.shape.radius),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(ow.shape.radius),
                        key: ValueKey('pane.choice.${choices[i].title}'),
                        onTap: choices[i].open,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: OwSpace.s4,
                            vertical: OwSpace.s3,
                          ),
                          child: Row(
                            children: [
                              choices[i].lead,
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    text: choices[i].title,
                                    children: [
                                      if (choices[i].detail != null)
                                        TextSpan(
                                          text: ' · ${choices[i].detail}',
                                          style: TextStyle(color: c.textMuted),
                                        ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (choices[i].env case final env?) ...[
                                const SizedBox(width: 8),
                                EnvChip(env),
                              ],
                              const Spacer(),
                              if (i == at) const KeyCap('↩'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
