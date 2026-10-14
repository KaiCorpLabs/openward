import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/controller.dart';
import 'tabs.dart';

/// The row of tabs: click to bring to front, drag to reorder, double-click
/// to rename, middle-click or × to close.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final theme = Theme.of(context);
    return Container(
      height: 36,
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: state.tabs.length,
              onReorderItem: tabs.move,
              itemBuilder: (context, i) => ReorderableDragStartListener(
                key: ObjectKey(state.tabs[i]),
                index: i,
                child: _Tab(
                  controller: state.tabs[i],
                  active: i == state.active,
                  onSelect: () => tabs.select(i),
                  onClose: () => tabs.close(i),
                  onRename: () => _rename(context, ref, i),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Terminal local',
            icon: const Icon(Icons.add, size: 18),
            onPressed: tabs.openLocal,
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, int index) async {
    final c = ref.read(tabsProvider).tabs[index];
    final field = TextEditingController(text: c.displayTitle);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar pestaña'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'Vacío para volver al nombre del host',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Renombrar'),
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
    required this.controller,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onRename,
  });

  final TerminalController controller;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final dot = switch (c.phase) {
          Phase.connecting || Phase.reconnecting => scheme.tertiary,
          Phase.connected || Phase.running => scheme.primary,
          Phase.closed =>
            c.closed?.failure != null || c.error != null
                ? scheme.error
                : scheme.outline,
        };
        return Listener(
          // Middle click closes, as in browsers.
          onPointerDown: (e) {
            if (e.buttons == 4) onClose();
          },
          child: InkWell(
            onTap: onSelect,
            onDoubleTap: onRename,
            child: Container(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                color: active ? scheme.surface : null,
                border: Border(
                  top: BorderSide(
                    color: active ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                  right: BorderSide(color: scheme.outlineVariant, width: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (c.prompts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.help_outline,
                        size: 14,
                        color: scheme.tertiary,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      c.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: active
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    visualDensity: VisualDensity.compact,
                    iconSize: 14,
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
