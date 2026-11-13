import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hosts/editors.dart';
import '../l10n/l10n.dart';
import '../snippets/palette.dart';
import '../tabs/close_guard.dart' as guard;
import '../tabs/tab_strip.dart' show pageIcon, tabTitle;
import '../tabs/tabs.dart';
import '../ui/tokens.dart';

/// The phone's top bar, in place of the tab strip: the drawer with the
/// hosts, the tab in front (a tap lists them all), search and its actions.
class MobileTopBar extends ConsumerWidget {
  const MobileTopBar({required this.onMenu, required this.onSearch, super.key});

  final VoidCallback onMenu;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final ow = context.ow;
    final tabs = ref.watch(tabsProvider);
    final current = tabs.current;
    final title = current == null ? l.startTitle : tabTitle(context, current);
    return DecoratedBox(
      key: const ValueKey('mobile.topBar'),
      decoration: BoxDecoration(
        color: ow.colors.window,
        border: Border(bottom: BorderSide(color: ow.colors.border)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('mobile.menu'),
              tooltip: l.mobileHostsMenu,
              icon: const Icon(Icons.menu),
              onPressed: onMenu,
            ),
            Expanded(
              child: InkWell(
                key: const ValueKey('mobile.title'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => showTabSwitcher(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OwSpace.s2,
                    vertical: OwSpace.s2,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('mobile.search'),
              tooltip: l.search,
              icon: const Icon(Icons.search),
              onPressed: onSearch,
            ),
            _TabCount(
              count: tabs.tabs.length,
              onTap: () => showTabSwitcher(context),
            ),
            _Actions(current: current),
          ],
        ),
      ),
    );
  }
}

/// How many tabs are open, as mobile browsers show it.
class _TabCount extends StatelessWidget {
  const _TabCount({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return IconButton(
      key: const ValueKey('mobile.tabs'),
      tooltip: context.l10n.mobileTabs(count),
      onPressed: onTap,
      icon: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(color: c.text, width: 1.6),
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? ':D' : '$count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
      ),
    );
  }
}

/// What the tab strip's menus and the window's shortcuts do, for the tab
/// in front.
class _Actions extends ConsumerWidget {
  const _Actions({required this.current});

  final OpenTab? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final tabs = ref.read(tabsProvider.notifier);
    final session = switch (current) {
      SessionTab(:final controller) => controller,
      _ => null,
    };
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('mobile.actions'),
      tooltip: l.moreActions,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => unawaited(showHostEditor(context, ref)),
          child: Text(l.newHost),
        ),
        if (session != null) ...[
          PopupMenuItem(
            value: tabs.openSftpHere,
            child: Text(l.mobileSftpHere),
          ),
          PopupMenuItem(value: session.openFind, child: Text(l.findEllipsis)),
          PopupMenuItem(
            value: () => showSnippetPalette(context),
            child: Text(l.snippetsEllipsis),
          ),
          PopupMenuItem(
            value: () => session.zoomBy(1),
            child: Text(l.mobileBiggerText),
          ),
          PopupMenuItem(
            value: () => session.zoomBy(-1),
            child: Text(l.mobileSmallerText),
          ),
        ],
        if (tabs.canReopen)
          PopupMenuItem(value: tabs.reopen, child: Text(l.reopenTab)),
        if (current != null)
          PopupMenuItem(
            value: () => unawaited(guard.closeCurrent(context)),
            child: Text(l.closeTab),
          ),
      ],
    );
  }
}

/// Every open tab, and the start page: the phone's tab strip.
Future<void> showTabSwitcher(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _TabSwitcher(),
    );

class _TabSwitcher extends ConsumerWidget {
  const _TabSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    void go(VoidCallback action) {
      action();
      Navigator.of(context).pop();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: ListView(
        key: const ValueKey('mobile.switcher'),
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: OwSpace.s6),
        children: [
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(l.startTitle),
            selected: s.active == -1,
            onTap: () => go(tabs.showStart),
          ),
          const Divider(height: 1),
          for (final (i, tab) in s.tabs.indexed)
            ListTile(
              key: ValueKey('mobile.switcher.$i'),
              leading: Icon(switch (tab) {
                SessionTab() => Icons.terminal,
                SftpTab() => Icons.folder_outlined,
                PageTab(:final page) => pageIcon(page),
              }),
              title: Text(
                tabTitle(context, tab),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: i == s.active,
              onTap: () => go(() => tabs.select(i)),
              trailing: IconButton(
                tooltip: l.closeTab,
                icon: const Icon(Icons.close),
                onPressed: () => guard.closeTab(context, i),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tells the system how many sessions are open: Android keeps them alive
/// in the background with a notification, iOS gives them the time it gives
/// (ARCHITECTURE §3.7). `MainActivity.kt` and `AppDelegate.swift` answer.
class SessionKeeper extends ConsumerStatefulWidget {
  const SessionKeeper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SessionKeeper> createState() => _SessionKeeperState();
}

class _SessionKeeperState extends ConsumerState<SessionKeeper> {
  static const channel = MethodChannel('openward/sessions');
  int _told = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      tabsProvider.select((s) => s.sessions.where((c) => !c.isDisposed).length),
      (_, count) => _tell(count),
      fireImmediately: true,
    );
  }

  Future<void> _tell(int count) async {
    if (count == _told) return;
    _told = count;
    try {
      await channel.invokeMethod<void>('count', count);
    } on MissingPluginException {
      /* The desktop, and the tests. */
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
