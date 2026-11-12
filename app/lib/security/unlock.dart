import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../ui/tokens.dart';
import '../src/rust/api/security.dart';
import 'state.dart';

class VaultUnlock extends ConsumerStatefulWidget {
  const VaultUnlock({super.key});
  @override
  ConsumerState<VaultUnlock> createState() => _VaultUnlockState();
}

class _VaultUnlockState extends ConsumerState<VaultUnlock> {
  final password = TextEditingController();
  bool kit = false;
  bool pending = false;
  String? error;
  @override
  void dispose() {
    password.clear();
    password.dispose();
    super.dispose();
  }

  Future<void> unlock({bool native = false}) async {
    if (pending) return;
    setState(() {
      pending = true;
      error = null;
    });
    final app = ref.read(openWardProvider);
    try {
      if (native) {
        await app.unlockNative();
      } else if (kit) {
        await app.recoverVault(kit: password.text);
      } else {
        await app.unlockVault(password: password.text);
      }
    } on Object {
      if (mounted) {
        setState(
          () => error = native
              ? context.l10n.vaultNativeError
              : context.l10n.vaultAuthError,
        );
      }
    } finally {
      password.clear();
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final view = ref.watch(securityProvider);
    final busy = pending || view.phase == VaultPhase.changing;
    final paused = view.phase == VaultPhase.legacyPaused;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OwSpace.s8),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 20),
                Text(
                  'OpenWard',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  paused ? l.vaultPaused : l.vaultLocked,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (paused)
                  FilledButton(
                    onPressed: () =>
                        ref.read(openWardProvider).resumeLegacyVault(),
                    child: Text(l.vaultResume),
                  )
                else ...[
                  TextField(
                    key: const ValueKey('vault.password'),
                    controller: password,
                    autofocus: true,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: kit ? 256 : 4096,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: kit ? l.vaultKit : l.vaultPassword,
                      counterText: '',
                    ),
                    onSubmitted: (_) => unlock(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('vault.unlock'),
                    onPressed: busy ? null : unlock,
                    child: Text(busy ? l.vaultBusy : l.vaultUnlock),
                  ),
                  if (view.nativeEnabled)
                    OutlinedButton(
                      onPressed: busy ? null : () => unlock(native: true),
                      child: Text(
                        nativeLabel(
                          l,
                          ref.read(openWardProvider).nativeProtection(),
                        ),
                      ),
                    ),
                  if (view.recoveryAvailable)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              password.clear();
                              setState(() {
                                kit = !kit;
                                error = null;
                              });
                            },
                      child: Text(kit ? l.vaultPassword : l.vaultRecovery),
                    ),
                  const SizedBox(height: 16),
                  Text(l.vaultSessions, textAlign: TextAlign.center),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: OwSpace.s4),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String nativeLabel(AppLocalizations l, NativeProtection protection) =>
    switch (protection) {
      NativeProtection.touchId => l.vaultTouchId,
      NativeProtection.windowsHello => l.vaultHello,
      NativeProtection.sessionKeyring => l.vaultKeyring,
      NativeProtection.unsupported => l.vaultNativeEnable,
    };
