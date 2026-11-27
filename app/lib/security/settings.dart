import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';
import '../core/providers.dart';
import '../history/history.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/security.dart';
import '../ui/tokens.dart';
import 'state.dart';
import 'credentials.dart';
import 'backups.dart';
import 'recovery.dart';
import 'unlock.dart';

String _formatAutoLock(AppLocalizations l, int seconds) {
  if (seconds == 0) return l.vaultNever;
  if (seconds < 60) return l.durationSec(seconds);
  if (seconds >= 3600) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return minutes == 0 ? '$hours h' : l.durationHours(hours, minutes);
  }
  final minutes = seconds ~/ 60;
  final rem = seconds % 60;
  return rem == 0 ? l.durationMinutes(minutes) : l.durationMinSec(minutes, rem);
}

class VaultSettings extends ConsumerStatefulWidget {
  const VaultSettings({super.key});
  @override
  ConsumerState<VaultSettings> createState() => _VaultSettingsState();
}

class _VaultSettingsState extends ConsumerState<VaultSettings> {
  bool busy = false;
  bool linuxAck = false;
  String? error;
  Future<void> native(bool enable) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final app = ref.read(openWardProvider);
      if (enable) {
        await app.enableNative(linuxAck: linuxAck);
      } else {
        await app.disableNative();
      }
    } on Object {
      if (mounted) setState(() => error = context.l10n.vaultNativeError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = owOf(context).colors;
    final view = ref.watch(securityProvider);
    final app = ref.read(openWardProvider);
    final nativeKind = app.nativeProtection();
    final deviceOnly = app.vaultNeedsPassword();
    final autoLockOptions = {
      0,
      60,
      300,
      900,
      1800,
      3600,
      view.autoLockSeconds.toInt(),
    }.toList()..sort();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.vaultScope),
          if (view.phase == VaultPhase.legacy || deviceOnly) ...[
            const SizedBox(height: 12),
            Text(l.vaultCloseSessions),
            const SizedBox(height: 12),
            Text(
              deviceOnly
                  ? (Device.mobile
                        ? l.vaultDeviceWarningMobile
                        : l.vaultDeviceWarning)
                  : l.vaultLegacy,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const VaultSetup(),
              ),
              child: Text(deviceOnly ? l.vaultFinishSetup : l.vaultEnable),
            ),
            if (view.phase != VaultPhase.legacy) const SizedBox(height: 24),
          ],
          if (view.phase != VaultPhase.legacy) ...[
            if (!deviceOnly) ...[
              const SizedBox(height: 16),
              Text(
                view.recoveryAvailable
                    ? l.vaultProtectedStatus
                    : l.vaultMissingKitStatus,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const VaultPasswordChange(),
                    ),
                    child: Text(l.vaultChangePassword),
                  ),
                  OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const VaultSetup(regenerate: true),
                    ),
                    child: Text(l.vaultRegenerateKit),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            const StoredCredentials(),
            const SizedBox(height: 24),
            Text(l.vaultSessions),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                ref.read(historyProvider.notifier).flush();
                app.lockVault();
              },
              child: Text(l.vaultLock),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              initialValue: view.autoLockSeconds.toInt(),
              decoration: InputDecoration(labelText: l.vaultAutoLock),
              items: [
                for (final n in autoLockOptions)
                  DropdownMenuItem(
                    value: n,
                    child: Text(_formatAutoLock(l, n)),
                  ),
              ],
              onChanged: (n) async {
                if (n == null) return;
                try {
                  await app.setAutoLock(seconds: BigInt.from(n));
                } on Object {
                  if (mounted) setState(() => error = l.errStorage);
                }
              },
            ),
            if (!deviceOnly) ...[
              const SizedBox(height: 24),
              Text(
                nativeLabel(l, nativeKind),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(l.vaultNativeExplain),
              if (nativeKind == NativeProtection.sessionKeyring) ...[
                const SizedBox(height: 8),
                Text(l.vaultLinuxWarning),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: linuxAck,
                  title: Text(l.vaultLinuxAccept),
                  onChanged: busy
                      ? null
                      : (v) => setState(() => linuxAck = v ?? false),
                ),
              ],
              const SizedBox(height: 12),
              if (nativeKind != NativeProtection.unsupported)
                OutlinedButton(
                  onPressed:
                      busy ||
                          (!view.nativeEnabled &&
                              nativeKind == NativeProtection.sessionKeyring &&
                              !linuxAck)
                      ? null
                      : () => native(!view.nativeEnabled),
                  child: Text(
                    view.nativeEnabled
                        ? l.vaultNativeDisable
                        : l.vaultNativeEnable,
                  ),
                ),
            ],
          ],
          if (!deviceOnly) ...[
            const SizedBox(height: 24),
            const VaultBackups(),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: c.danger)),
          ],
        ],
      ),
    );
  }
}

class VaultSetup extends ConsumerStatefulWidget {
  const VaultSetup({this.regenerate = false, super.key});
  final bool regenerate;
  @override
  ConsumerState<VaultSetup> createState() => _VaultSetupState();
}

class _VaultSetupState extends ConsumerState<VaultSetup> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final group3 = TextEditingController();
  final group12 = TextEditingController();
  String? kit;
  List<int>? qr;
  String? error;
  bool saved = false;
  bool confirming = false;
  bool busy = false;
  int score = 0;
  int generation = 0;
  Timer? debounce;
  late final Future<void> Function() cancelSetup;
  @override
  void initState() {
    super.initState();
    cancelSetup = ref.read(openWardProvider).cancelVaultSetup;
  }

  @override
  void dispose() {
    debounce?.cancel();
    generation++;
    for (final c in [password, confirmation, group3, group12]) {
      c.clear();
      c.dispose();
    }
    kit = null;
    qr = null;
    unawaited(cancelSetup());
    super.dispose();
  }

  void strength(String value) {
    final request = ++generation;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final result = await ref
            .read(openWardProvider)
            .passwordScore(password: value);
        if (mounted && request == generation) setState(() => score = result);
      } on Object {
        if (mounted && request == generation) setState(() => score = 0);
      }
    });
  }

  Future<void> advance() async {
    setState(() {
      busy = true;
      error = null;
    });
    final app = ref.read(openWardProvider);
    try {
      if (confirming) {
        await app.completeVaultSetup(
          group3: group3.text,
          group12: group12.text,
        );
        if (mounted) Navigator.of(context).pop();
      } else if (kit != null) {
        setState(() {
          kit = null;
          qr = null;
          confirming = true;
        });
      } else if (!widget.regenerate && password.text != confirmation.text) {
        setState(() => error = context.l10n.vaultMismatch);
      } else {
        final text = widget.regenerate
            ? await app.prepareRecoveryKit(password: password.text)
            : await app.prepareVault(password: password.text);
        if (!mounted) {
          await app.cancelVaultSetup();
          return;
        }
        final modules = await app.preparedRecoveryQr();
        if (!mounted) {
          // Cancellation may reach a worker before prepare starts. Clear again
          // after completion so no abandoned password/kit remains prepared.
          await app.cancelVaultSetup();
          return;
        }
        password.clear();
        confirmation.clear();
        setState(() {
          kit = text;
          qr = modules;
        });
      }
    } on Object {
      if (mounted) setState(() => error = context.l10n.vaultSetupError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = owOf(context).colors;
    final app = ref.read(openWardProvider);
    return AlertDialog(
      title: Text(widget.regenerate ? l.vaultRegenerateKit : l.vaultEnable),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (confirming) ...[
                TextField(
                  controller: group3,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 4,
                  decoration: InputDecoration(labelText: l.vaultGroup3),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: group12,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 4,
                  decoration: InputDecoration(labelText: l.vaultGroup12),
                ),
              ] else if (kit case final text?) ...[
                Text(l.vaultKitWarning),
                const SizedBox(height: 8),
                Text(l.vaultKitCopies),
                const SizedBox(height: 16),
                Text(
                  text,
                  style: const TextStyle(fontFamily: 'monospace', height: 1.8),
                ),
                if (qr case final modules?) ...[
                  const SizedBox(height: 16),
                  RecoveryQr(modules: modules),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await saveRecoveryPdf(app);
                          } on Object {
                            if (mounted) {
                              setState(() => error = l.vaultPdfError);
                            }
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(l.vaultSavePdf),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: saved,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => saved = v ?? false),
                  title: Text(l.vaultSaved),
                ),
              ] else ...[
                if (widget.regenerate)
                  Text(l.vaultRotateWarning)
                else
                  Text(l.vaultCompatibility),
                const SizedBox(height: 12),
                Text(l.vaultScope),
                if (!widget.regenerate) ...[
                  const SizedBox(height: 8),
                  Text(l.vaultCloseSessions),
                ],
                const SizedBox(height: 16),
                if (!widget.regenerate) ...[
                  Text(
                    l.vaultPasswordHint,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: c.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                VaultSecretField(
                  controller: password,
                  enabled: !busy,
                  maxLength: 128,
                  label: l.vaultPassword,
                  onChanged: strength,
                ),
                if (!widget.regenerate) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: score / 4,
                    semanticsLabel: l.vaultStrength,
                  ),
                  const SizedBox(height: 12),
                  VaultSecretField(
                    controller: confirmation,
                    enabled: !busy,
                    maxLength: 128,
                    label: l.vaultConfirmPassword,
                  ),
                ],
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: c.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.vaultCancel),
        ),
        FilledButton(
          onPressed: busy || (kit != null && !saved) ? null : advance,
          child: Text(
            busy
                ? l.vaultBusy
                : confirming
                ? widget.regenerate
                      ? l.vaultConfirmReplacement
                      : l.vaultConfirmKit
                : kit != null
                ? l.vaultKitContinue
                : widget.regenerate
                ? l.vaultRegenerateKit
                : l.vaultEnable,
          ),
        ),
      ],
    );
  }
}
