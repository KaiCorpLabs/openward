import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hosts/sidebar.dart';
import 'settings_dialog.dart';
import 'tabs/session_view.dart';
import 'tabs/tab_strip.dart';
import 'tabs/tabs.dart';
import 'terminal/keys.dart';

/// The main window: hosts on the left, tabs and the front terminal on the
/// right.
class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  final FocusNode _search = FocusNode(debugLabel: 'host search');

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Window shortcuts. Terminal panes let these through (`isAppShortcut`).
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final tabs = ref.read(tabsProvider.notifier);
    void closeCurrent() => tabs.close(ref.read(tabsProvider).active);
    void search() {
      _search.requestFocus();
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
          tabs.cycle(1),
      const SingleActivator(
        LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      ): () =>
          tabs.cycle(-1),
    };
    void settings() => showSettings(context);
    if (isApple) {
      bindings.addAll({
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): settings,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
            tabs.openLocal,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            closeCurrent,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): search,
        const SingleActivator(
          LogicalKeyboardKey.bracketRight,
          meta: true,
          shift: true,
        ): () =>
            tabs.cycle(1),
        const SingleActivator(
          LogicalKeyboardKey.bracketLeft,
          meta: true,
          shift: true,
        ): () =>
            tabs.cycle(-1),
        for (var i = 1; i <= 9; i++)
          SingleActivator(
            LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i - 1),
            meta: true,
          ): () => tabs.select(
            i == 9 ? ref.read(tabsProvider).tabs.length - 1 : i - 1,
          ),
      });
    } else {
      bindings.addAll({
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            settings,
        const SingleActivator(
          LogicalKeyboardKey.keyT,
          control: true,
          shift: true,
        ): tabs.openLocal,
        const SingleActivator(
          LogicalKeyboardKey.keyW,
          control: true,
          shift: true,
        ): closeCurrent,
        const SingleActivator(
          LogicalKeyboardKey.keyK,
          control: true,
          shift: true,
        ): search,
      });
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(tabsProvider.select((s) => s.current));
    final hasTabs = ref.watch(tabsProvider.select((s) => s.tabs.isNotEmpty));
    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 280, child: Sidebar(searchFocus: _search)),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasTabs) const TabStrip(),
                  Expanded(
                    child: current == null
                        ? const _Welcome()
                        : SessionView(
                            key: ObjectKey(current),
                            controller: current,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = isApple ? '⌘' : 'Ctrl+Mayús+';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('OpenWard', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Doble clic en un host para conectar, o abre un terminal local.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: ref.read(tabsProvider.notifier).openLocal,
            icon: const Icon(Icons.add),
            label: Text('Terminal local (${key}T)'),
          ),
          const SizedBox(height: 8),
          Text(
            '${key}K busca hosts · ${key}W cierra la pestaña',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
