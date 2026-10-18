import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../tabs/tab_strip.dart' show tabTitle;
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../tunnels/tunnels.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/chrome.dart';
import '../window/sidebar_state.dart';
import 'sidebar.dart' show tabStatus;

/// The sidebar folded to a column of icons: search, the open tabs, the
/// whole host list (shown over the window), the library and the settings.
class SidebarRail extends ConsumerWidget {
  const SidebarRail({super.key, required this.onSearch});

  /// Opens the palette.
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final state = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final board = ref.watch(tunnelBoardProvider);
    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(width: 24, child: Divider(height: 1, color: c.border)),
    );
    Widget page(PageKind kind, IconData icon, String label, {Widget? mark}) {
      final here =
          state.current is PageTab && (state.current! as PageTab).page == kind;
      return _RailButton(
        key: ValueKey('rail.${kind.name}'),
        tooltip: label,
        selected: here,
        onPressed: () => tabs.openPage(kind),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 18, color: c.textMuted),
            if (mark != null) Positioned(right: -3, top: -2, child: mark),
          ],
        ),
      );
    }

    final sessions = [
      for (final (i, t) in state.tabs.indexed)
        if (t is SessionTab || t is SftpTab) (i, t),
    ];
    return ColoredBox(
      color: c.window,
      child: Column(
        children: [
          const WindowButtonsSpace(),
          _RailButton(
            key: const ValueKey('rail.search'),
            tooltip:
                '${l.search} (${isApple ? '⌘K' : '${l.ctrlShiftPrefix}K'})',
            onPressed: onSearch,
            child: Icon(Icons.search, size: 18, color: c.textMuted),
          ),
          divider(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final (i, t) in sessions)
                  Center(
                    child: _TabBadge(
                      tab: t,
                      selected: i == state.active,
                      onPressed: () => tabs.select(i),
                    ),
                  ),
                Center(
                  child: _RailButton(
                    key: const ValueKey('rail.allHosts'),
                    tooltip: l.allHosts,
                    onPressed: () =>
                        ref.read(sidebarProvider.notifier).setPeek(true),
                    child: Icon(Icons.list, size: 18, color: c.textMuted),
                  ),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: board,
            builder: (context, _) => page(
              PageKind.tunnels,
              Icons.swap_horiz,
              board.open > 0
                  ? '${l.tunnels} · ${l.openCount(board.open)}'
                  : l.tunnels,
              mark: board.open > 0
                  ? const StatusDot(Status.connected, size: 6)
                  : null,
            ),
          ),
          page(PageKind.identities, Icons.badge_outlined, l.identities),
          page(PageKind.keys, Icons.key_outlined, l.keys),
          page(PageKind.snippets, Icons.terminal, l.snippets),
          page(PageKind.workspaces, Icons.dashboard_outlined, l.workspaces),
          page(PageKind.knownHosts, Icons.verified_user_outlined, l.knownHosts),
          divider(),
          _RailButton(
            key: const ValueKey('rail.expand'),
            tooltip: isApple ? '${l.showSidebar} (⌘B)' : l.showSidebar,
            onPressed: ref.read(sidebarProvider.notifier).toggle,
            child: Icon(
              Icons.view_sidebar_outlined,
              size: 18,
              color: c.textMuted,
            ),
          ),
          page(PageKind.settings, Icons.settings_outlined, l.settings),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.selected = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 300),
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          excludeSemantics: true,
          child: FocusOutline(
            radius: ow.shape.radius + 2,
            child: Material(
              color: selected ? ow.colors.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(ow.shape.radius + 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(ow.shape.radius + 2),
                onTap: onPressed,
                child: SizedBox(
                  width: 40,
                  height: 36,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An open terminal or file tab in the rail: its initials and how it is
/// doing.
class _TabBadge extends StatelessWidget {
  const _TabBadge({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final OpenTab tab;
  final bool selected;
  final VoidCallback onPressed;

  /// Two letters for a name: the first of each part (`web-1` → `w1`), or
  /// its first two.
  static String initials(String name) {
    final parts = name
        .split(RegExp(r'[\s\-_.@:]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toLowerCase();
    final one = parts.firstOrNull ?? '?';
    return (one.length >= 2 ? one.substring(0, 2) : one).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final listenable = switch (tab) {
      SessionTab(:final panes) => Listenable.merge([
        panes,
        ...panes.controllers,
      ]),
      SftpTab(:final controller) => controller,
      _ => Listenable.merge(const []),
    };
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final title = tabTitle(context, tab);
        final status = switch (tab) {
          SessionTab(:final panes) =>
            (panes.active.controller ?? panes.controllers.firstOrNull)?.let(
                  tabStatus,
                ) ??
                Status.idle,
          _ => Status.idle,
        };
        final sftp = tab is SftpTab;
        return _RailButton(
          tooltip: title,
          selected: selected,
          onPressed: onPressed,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.raised,
                    border: Border.all(color: c.control),
                    borderRadius: BorderRadius.circular(ow.shape.radius),
                  ),
                  child: sftp
                      ? Icon(
                          Icons.folder_outlined,
                          size: 14,
                          color: c.textMuted,
                        )
                      : Text(
                          initials(title),
                          style: monoStyle(
                            context,
                            size: 12,
                            color: c.text,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                ),
                if (!sftp)
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: c.window,
                        shape: BoxShape.circle,
                      ),
                      child: StatusDot(status, size: 7),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension<T extends Object> on T {
  R let<R>(R Function(T) f) => f(this);
}
