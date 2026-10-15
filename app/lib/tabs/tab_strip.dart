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
    return Container(
      height: topBarHeight,
      decoration: BoxDecoration(
        color: ow.colors.window,
        border: ow.shape.pills
            ? null
            : Border(bottom: BorderSide(color: ow.colors.border)),
      ),
      padding: EdgeInsets.only(left: ow.shape.pills ? 4 : 8),
      child: Row(
        crossAxisAlignment: ow.shape.pills
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.end,
        children: [
          Flexible(
            child: SizedBox(
              height: ow.shape.pills ? 30 : 33,
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
                    padding: EdgeInsets.only(right: ow.shape.pills ? 6 : 2),
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
            padding: EdgeInsets.only(left: 2, bottom: ow.shape.pills ? 0 : 3),
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
          leading: StatusDot(tabStatus(controller), size: 7),
          title: controller.displayTitle,
          waiting: controller.prompts.isNotEmpty,
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
    VoidCallback? onRename,
  }) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final pills = ow.shape.pills;
    final fg = active
        ? (pills ? c.onPrimary : c.text)
        : (pills ? c.text : c.textMuted);
    final decoration = pills
        ? BoxDecoration(
            color: active ? c.primary : c.raised,
            borderRadius: BorderRadius.circular(999),
            border: active ? null : Border.all(color: c.border),
          )
        : BoxDecoration(
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
          );
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
                  if (waiting)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: l.waitingForYou,
                        child: Icon(
                          Icons.help_outline,
                          size: 14,
                          color: pills && active ? fg : c.warn,
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
