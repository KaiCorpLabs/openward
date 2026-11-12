import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../ui/tokens.dart';
import '../src/rust/api/security.dart';
import 'settings.dart';
import 'state.dart';

class VaultOnboarding extends ConsumerStatefulWidget {
  const VaultOnboarding({super.key});
  @override
  ConsumerState<VaultOnboarding> createState() => _VaultOnboardingState();
}

class _VaultOnboardingState extends ConsumerState<VaultOnboarding> {
  bool busy = false;
  bool acknowledged = false;
  String? error;
  Future<void> later() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(openWardProvider).deferVaultSetup(linuxAck: acknowledged);
    } on Object {
      if (mounted) setState(() => error = context.l10n.vaultDeviceError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final view = ref.watch(securityProvider);
    final pending = busy || view.phase == VaultPhase.changing;
    final linux =
        ref.read(openWardProvider).nativeProtection() ==
        NativeProtection.sessionKeyring;
    return Material(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OwSpace.s8),
          child: SizedBox(
            width: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  l.vaultOnboardingTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(l.vaultOnboardingBody),
                const SizedBox(height: 24),
                if (view.phase == VaultPhase.legacyPaused)
                  FilledButton(
                    onPressed: pending
                        ? null
                        : () => ref.read(openWardProvider).resumeLegacyVault(),
                    child: Text(l.vaultResume),
                  )
                else ...[
                  FilledButton(
                    key: const ValueKey('vault.onboarding.setup'),
                    onPressed: pending
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const VaultSetup(),
                          ),
                    child: Text(pending ? l.vaultBusy : l.vaultEnable),
                  ),
                  const SizedBox(height: 24),
                  Text(l.vaultDeviceWarning),
                  if (linux) ...[
                    const SizedBox(height: 8),
                    Text(l.vaultLinuxWarning),
                    CheckboxListTile(
                      value: acknowledged,
                      title: Text(l.vaultLinuxAccept),
                      onChanged: pending
                          ? null
                          : (v) => setState(() => acknowledged = v ?? false),
                    ),
                  ],
                  TextButton(
                    key: const ValueKey('vault.onboarding.later'),
                    onPressed: pending || (linux && !acknowledged)
                        ? null
                        : later,
                    child: Text(l.vaultLater),
                  ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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

/// Persists until password + confirmed recovery kit commit successfully.
class VaultReminder extends StatelessWidget {
  const VaultReminder({super.key});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OwSpace.s4,
          vertical: OwSpace.s1,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(l.vaultDeviceReminder),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const VaultSetup(),
              ),
              child: Text(l.vaultFinishSetup),
            ),
          ],
        ),
      ),
    );
  }
}
