import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../ui/themes.dart';
import '../ui/tokens.dart';
import '../ui/umbral.dart';
import '../window/chrome.dart';
import '../src/rust/api/security.dart';
import '../src/rust/api/vault.dart';
import 'state.dart';

/// Returns the active [OwTheme], falling back to the matching default theme
/// when a widget is mounted without [OwTheme] (for example in unit tests).
OwTheme owOf(BuildContext context) =>
    Theme.of(context).extension<OwTheme>() ??
    (Theme.of(context).brightness == Brightness.dark
        ? OwThemes.grafito
        : OwThemes.papel);

/// A secret text field (password or recovery kit) with an accessible
/// visibility toggle.
class VaultSecretField extends StatefulWidget {
  const VaultSecretField({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.autofocus = false,
    this.maxLength,
    this.counterText,
    this.onChanged,
    this.onSubmitted,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool autofocus;
  final int? maxLength;
  final String? counterText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VaultSecretField> createState() => _VaultSecretFieldState();
}

class _VaultSecretFieldState extends State<VaultSecretField> {
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: obscure,
      enableSuggestions: false,
      autocorrect: false,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        counterText: widget.counterText,
        suffixIcon: IconButton(
          style: IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          tooltip: obscure ? l.vaultShowPassword : l.vaultHidePassword,
          onPressed: widget.enabled
              ? () => setState(() => obscure = !obscure)
              : null,
        ),
      ),
    );
  }
}

class VaultUnlock extends ConsumerStatefulWidget {
  const VaultUnlock({super.key});
  @override
  ConsumerState<VaultUnlock> createState() => _VaultUnlockState();
}

class _VaultUnlockState extends ConsumerState<VaultUnlock> {
  final password = TextEditingController();
  bool kit = false;
  bool obscure = true;
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
      if (app.vaultNeedsPassword()) {
        await app.unlockDeviceVault();
      } else if (native) {
        await app.unlockNative();
      } else if (kit) {
        await app.recoverVault(kit: password.text);
      } else {
        await app.unlockVault(password: password.text);
      }
    } on VaultError catch (failure) {
      if (mounted) {
        setState(
          () => error = failure.kind == VaultErrorKind.storage
              ? context.l10n.vaultLocalDataError
              : app.vaultNeedsPassword()
              ? context.l10n.vaultDeviceError
              : context.l10n.vaultAuthError,
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => error = app.vaultNeedsPassword()
              ? context.l10n.vaultDeviceError
              : native
              ? context.l10n.vaultNativeError
              : context.l10n.vaultAuthError,
        );
      }
    } finally {
      if (mounted) {
        password.clear();
        setState(() {
          pending = false;
          obscure = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = owOf(context).colors;
    final view = ref.watch(securityProvider);
    final busy = pending || view.phase == VaultPhase.changing;
    final paused = view.phase == VaultPhase.legacyPaused;
    final deviceOnly = ref.read(openWardProvider).vaultNeedsPassword();
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
                        width: 420,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: UmbralMark(size: 56, color: c.accent),
                            ),
                            const SizedBox(height: 20),
                            Semantics(
                              header: true,
                              child: Text(
                                'OpenWard',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              paused ? l.vaultPaused : l.vaultLocked,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.textMuted),
                            ),
                            const SizedBox(height: 24),
                            if (paused)
                              FilledButton(
                                onPressed: () => ref
                                    .read(openWardProvider)
                                    .resumeLegacyVault(),
                                child: Text(l.vaultResume),
                              )
                            else if (deviceOnly) ...[
                              Text(
                                Device.mobile
                                    ? l.vaultDeviceWarningMobile
                                    : l.vaultDeviceWarning,
                                style: TextStyle(color: c.textMuted),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: busy ? null : unlock,
                                child: Text(
                                  busy
                                      ? l.vaultBusy
                                      : Device.mobile
                                      ? l.vaultDeviceUnlockMobile
                                      : l.vaultDeviceUnlock,
                                ),
                              ),
                            ] else ...[
                              TextField(
                                key: const ValueKey('vault.password'),
                                controller: password,
                                autofocus: true,
                                obscureText: obscure,
                                enableSuggestions: false,
                                autocorrect: false,
                                maxLength: kit ? 256 : 4096,
                                enabled: !busy,
                                decoration: InputDecoration(
                                  labelText: kit ? l.vaultKit : l.vaultPassword,
                                  counterText: '',
                                  suffixIcon: IconButton(
                                    key: const ValueKey(
                                      'vault.password.visibility',
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(40, 40),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    tooltip: obscure
                                        ? l.vaultShowPassword
                                        : l.vaultHidePassword,
                                    onPressed: busy
                                        ? null
                                        : () => setState(
                                            () => obscure = !obscure,
                                          ),
                                  ),
                                ),
                                onSubmitted: (_) => unlock(),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                key: const ValueKey('vault.unlock'),
                                onPressed: busy ? null : unlock,
                                child: Text(busy ? l.vaultBusy : l.vaultUnlock),
                              ),
                              if (view.nativeEnabled) ...[
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => unlock(native: true),
                                  child: Text(
                                    nativeLabel(
                                      l,
                                      ref
                                          .read(openWardProvider)
                                          .nativeProtection(),
                                    ),
                                  ),
                                ),
                              ],
                              if (view.recoveryAvailable) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () {
                                          password.clear();
                                          setState(() {
                                            kit = !kit;
                                            obscure = true;
                                            error = null;
                                          });
                                        },
                                  child: Text(
                                    kit ? l.vaultPassword : l.vaultRecovery,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                l.vaultSessions,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.textMuted),
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

String nativeLabel(AppLocalizations l, NativeProtection protection) =>
    switch (protection) {
      NativeProtection.touchId => l.vaultTouchId,
      NativeProtection.windowsHello => l.vaultHello,
      // Face ID or Touch ID on iOS; the fingerprint or the face on Android.
      NativeProtection.biometric =>
        Platform.isIOS ? l.vaultFaceId : l.vaultBiometricAndroid,
      NativeProtection.sessionKeyring => l.vaultKeyring,
      NativeProtection.unsupported => l.vaultNativeEnable,
    };
