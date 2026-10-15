import 'package:flutter/gestures.dart'
    show kMiddleMouseButton, kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hosts/sidebar.dart' show tabStatus;
import '../l10n/l10n.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/chrome.dart';
import 'tabs.dart';

/// The row of tabs at the top of the window: click to bring to front, drag
/// to reorder, double-click to rename, middle-click or × to close. Its
/// empty part moves the window, as a title bar does.
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
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: state.tabs.length,
                onReorderItem: tabs.move,
                proxyDecorator: (child, _, _) =>
                    Material(color: Colors.transparent, child: child),
                itemBuilder: (context, i) => ReorderableDragStartListener(
                  key: ObjectKey(state.tabs[i]),
                  index: i,
                  child: Padding(
                    padding: EdgeInsets.only(right: gap),
                    child: _Tab(
                      tab: state.tabs[i],
                      active: i == state.active,
                      onSelect: () => tabs.select(i),
                      onClose: () => tabs.close(i),
                      onRename: () => _rename(context, ref, i),
                    ),
                  ),
                ),
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
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, int index) async {
    final tab = ref.read(tabsProvider).tabs[index];
    if (tab is! SessionTab) return;
    final l = context.l10n;
    final field = TextEditingController(text: tab.controller.displayTitle);
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

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onRename,
  });

  final OpenTab tab;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      SessionTab(:final controller) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _frame(
          context,
          leading: StatusDot(
            tabStatus(controller),
            size: 7,
            // On an accent block the accent would not show.
            onAccent: active && context.ow.shape.tabs == TabStyle.block
                ? context.ow.colors.onPrimary
                : null,
          ),
          title: controller.displayTitle,
          waiting: controller.prompts.isNotEmpty,
          bell: controller.bellUnseen,
          onRename: onRename,
        ),
      ),
      PageTab(:final page) => _frame(
        context,
        leading: Icon(switch (page) {
          PageKind.settings => Icons.settings_outlined,
        }, size: 14),
        title: switch (page) {
          PageKind.settings => context.l10n.settings,
        },
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
