import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../ui/tokens.dart';
import '../ui/umbral.dart';
import '../window/chrome.dart';
import '../src/rust/api/security.dart';
import 'settings.dart';
import 'state.dart';
import 'unlock.dart';

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
    final c = owOf(context).colors;
    final view = ref.watch(securityProvider);
    final pending = busy || view.phase == VaultPhase.changing;
    final linux =
        ref.read(openWardProvider).nativeProtection() ==
        NativeProtection.sessionKeyring;
    final topBar = customTitleBar && !ref.watch(fullScreenProvider);
    return Material(
      color: c.surface,
      child: Stack(
        children: [
          const Positioned.fill(child: WindowDragArea()),
          SafeArea(
            child: Column(
              children: [
                if (topBar)
                  const SizedBox(height: topBarHeight, child: WindowDragArea()),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(OwSpace.s8),
                      child: SizedBox(
                        width: 520,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: UmbralMark(size: 56, color: c.accent),
                            ),
                            const SizedBox(height: 16),
                            Semantics(
                              header: true,
                              child: Text(
                                l.vaultOnboardingTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(l.vaultOnboardingBody),
                            const SizedBox(height: 24),
                            if (view.phase == VaultPhase.legacyPaused)
                              FilledButton(
                                onPressed: pending
                                    ? null
                                    : () => ref
                                          .read(openWardProvider)
                                          .resumeLegacyVault(),
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
                                child: Text(
                                  pending ? l.vaultBusy : l.vaultEnable,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                Device.mobile
                                    ? l.vaultDeviceWarningMobile
                                    : l.vaultDeviceWarning,
                                style: TextStyle(color: c.textMuted),
                              ),
                              if (linux) ...[
                                const SizedBox(height: 12),
                                Text(
                                  l.vaultLinuxWarning,
                                  style: TextStyle(color: c.textMuted),
                                ),
                                const SizedBox(height: 4),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: acknowledged,
                                  title: Text(l.vaultLinuxAccept),
                                  onChanged: pending
                                      ? null
                                      : (v) => setState(
                                          () => acknowledged = v ?? false,
                                        ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextButton(
                                key: const ValueKey('vault.onboarding.later'),
                                onPressed: pending || (linux && !acknowledged)
                                    ? null
                                    : later,
                                child: Text(l.vaultLater),
                              ),
                            ],
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: OwSpace.s4),
                                child: Text(
                                  error!,
                                  style: TextStyle(color: c.danger),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Persists until password + confirmed recovery kit commit successfully.
class VaultReminder extends ConsumerWidget {
  const VaultReminder({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = owOf(context).colors;
    final buttons = customTitleBar && !ref.watch(fullScreenProvider);
    // Its color goes on under a phone's status bar; its words below it.
    return Material(
      color: c.warnSoft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.warnLine)),
        ),
        child: WindowDragArea(
          child: SafeArea(
            bottom: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: buttons ? topBarHeight : 0,
              ),
              child: Row(
                children: [
                  if (buttons)
                    const SizedBox(
                      width: windowButtonsWidth,
                      height: topBarHeight,
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OwSpace.s4,
                        vertical: OwSpace.s2,
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: c.warn,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  Device.mobile
                                      ? l.vaultDeviceReminderMobile
                                      : l.vaultDeviceReminder,
                                  style: TextStyle(color: c.text),
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: c.text,
                            ),
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
