import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../home.dart';
import '../history/history.dart';
import '../src/rust/api/security.dart';
import '../tabs/tabs.dart';
import 'state.dart';
import 'unlock.dart';

/// Does not mount Home until its first permitted frame. Once mounted, sessions
/// and navigator state survive locking, outside focus, semantics and painting.
class VaultHome extends ConsumerStatefulWidget {
  const VaultHome({super.key});
  @override
  ConsumerState<VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends ConsumerState<VaultHome> {
  bool opened = false;
  @override
  Widget build(BuildContext context) {
    opened |= vaultVisible(ref.watch(securityProvider));
    return opened ? const Home() : const SizedBox.shrink();
  }
}

class VaultBoundary extends ConsumerStatefulWidget {
  const VaultBoundary({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<VaultBoundary> createState() => _VaultBoundaryState();
}

class _VaultBoundaryState extends ConsumerState<VaultBoundary> {
  static const channel = MethodChannel('openward/security');
  bool nativeCovered = false;
  DateTime lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method != 'suspend') return;
      setState(() => nativeCovered = true);
      try {
        final app = ref.read(openWardProvider);
        if (app.securityState().phase != VaultPhase.legacy) {
          ref.read(historyProvider.notifier).flush();
          await app.lockVault();
        }
      } finally {
        if (mounted) setState(() => nativeCovered = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ack()));
      }
    });
    unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      await channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      /* Headless tests. */
    }
  }

  Future<void> _ack() async {
    try {
      await channel.invokeMethod<void>('privacyReady');
    } on MissingPluginException {
      /* Headless tests. */
    }
  }

  void activity() {
    final now = DateTime.now();
    if (now.difference(lastActivity) < const Duration(seconds: 1)) return;
    lastActivity = now;
    ref.read(openWardProvider).securityActivity();
  }

  Future<void> lock() async {
    final phase = ref.read(securityProvider).phase;
    if (phase != VaultPhase.unlocked && phase != VaultPhase.changing) return;
    ref.read(historyProvider.notifier).flush();
    await ref.read(openWardProvider).lockVault();
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(securityProvider);
    final visible = vaultVisible(view) && !nativeCovered;
    ref.listen(securityProvider, (previous, next) {
      if (vaultVisible(next) == (previous != null && vaultVisible(previous))) {
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(libraryProvider.notifier).refresh();
      ref.read(searchProvider.notifier).set('');
      if (!vaultVisible(next)) {
        for (final session in ref.read(tabsProvider).sessions) {
          session.redact();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appNavigator.currentState?.popUntil((route) => route.isFirst);
        });
      } else {
        final settings = ref.read(settingsProvider);
        final app = ref.read(openWardProvider);
        app.setReadOsReleaseEverywhere(enabled: settings.readOsRelease);
        app.setSessionLogEverywhere(enabled: settings.sessionLog);
        for (final session in ref.read(tabsProvider).sessions) {
          session.session.redraw();
        }
      }
    });
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyL,
          control: true,
          alt: true,
        ): () =>
            unawaited(lock()),
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () =>
            unawaited(lock()),
      },
      child: Listener(
        onPointerDown: (_) => activity(),
        onPointerSignal: (_) => activity(),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) activity();
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                excluding: !visible,
                child: ExcludeFocus(
                  excluding: !visible,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: Offstage(offstage: !visible, child: widget.child),
                  ),
                ),
              ),
              if (!visible)
                Positioned.fill(
                  child: HeroControllerScope.none(
                    child: Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => const VaultUnlock(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
