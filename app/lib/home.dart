import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/settings.dart';
import 'home/start_page.dart';
import 'hosts/editors.dart';
import 'hosts/sidebar.dart';
import 'settings/settings_page.dart';
import 'tabs/session_view.dart';
import 'tabs/tab_strip.dart';
import 'tabs/tabs.dart';
import 'terminal/keys.dart';
import 'ui/tokens.dart';
import 'welcome/first_run.dart';

/// The main window: hosts on the left; tabs on the right, with the front
/// one below them. On the first run with nothing saved, the guide instead.
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

  Future<void> _newHost() async {
    if (await showHostEditor(context, ref)) {
      ref.read(libraryProvider.notifier).refresh();
    }
  }

  /// Window shortcuts. Terminal panes let these through (`isAppShortcut`).
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final tabs = ref.read(tabsProvider.notifier);
    void closeCurrent() => tabs.close(ref.read(tabsProvider).active);
    void settings() => tabs.openPage(PageKind.settings);
    void last() => tabs.select(ref.read(tabsProvider).tabs.length - 1);
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
    if (isApple) {
      bindings.addAll({
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): settings,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
            tabs.openLocal,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newHost,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            closeCurrent,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _search.requestFocus,
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
          ): i == 9
              ? last
              : () => tabs.select(i - 1),
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
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): _newHost,
        const SingleActivator(
          LogicalKeyboardKey.keyW,
          control: true,
          shift: true,
        ): closeCurrent,
        const SingleActivator(
          LogicalKeyboardKey.keyK,
          control: true,
          shift: true,
        ): _search.requestFocus,
      });
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    final welcomed = ref.watch(settingsProvider.select((s) => s.welcomed));
    final empty = ref.watch(
      libraryProvider.select((l) => l.hosts.isEmpty && l.groups.isEmpty),
    );
    if (!welcomed && empty) return const FirstRun();
    final current = ref.watch(tabsProvider.select((s) => s.current));
    final ow = context.ow;
    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Scaffold(
        backgroundColor: ow.colors.window,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 272, child: Sidebar(searchFocus: _search)),
            if (!ow.shape.pills)
              VerticalDivider(width: 1, thickness: 1, color: ow.colors.border),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TabStrip(),
                  Expanded(
                    child: switch (current) {
                      SessionTab(:final controller) => SessionView(
                        key: ObjectKey(controller),
                        controller: controller,
                      ),
                      PageTab(page: PageKind.settings) => const SettingsPage(),
                      null => StartPage(searchFocus: _search),
                    },
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
