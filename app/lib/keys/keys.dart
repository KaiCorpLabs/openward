// The keys in ~/.ssh as the app holds them, and putting a public key on a
// server (what `ssh-copy-id` does): over SFTP, into
// ~/.ssh/authorized_keys, unless it is there already.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/connection.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/app.dart';
import '../src/rust/api/keychain.dart';
import '../src/rust/api/session.dart';
import '../src/rust/api/sftp.dart';
import '../tabs/messages.dart' show securityKeyReason;

/// The private keys in `~/.ssh`, by name.
class KeysNotifier extends AsyncNotifier<List<SshKey>> {
  @override
  Future<List<SshKey>> build() => ref.read(openWardProvider).keys();

  void refresh() => ref.invalidateSelf();
}

final keysProvider = AsyncNotifierProvider<KeysNotifier, List<SshKey>>(
  KeysNotifier.new,
);

/// Why a key could not be made or brought in, in words.
String keyFailureText(AppLocalizations l, SshKeyFailure f, String name) =>
    switch (f.kind) {
      SshKeyFailureKind.exists => l.keyNameTaken(name),
      SshKeyFailureKind.badName => l.keyNameInvalid,
      SshKeyFailureKind.notAKey => l.keyNotReadable,
      // The core's words are in «Detalles».
      SshKeyFailureKind.io || SshKeyFailureKind.make => l.keyFailed,
      SshKeyFailureKind.wrongPassphrase => l.wrongPassphrase,
      SshKeyFailureKind.notOpenSsh => l.keyNotOpenSsh,
      SshKeyFailureKind.securityKey => _capital(
        securityKeyReason(l, f.securityKey ?? SecurityKeyKind.other),
      ),
    };

String _capital(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}.';

/// A name for a new key of `type` that no file in `~/.ssh` has.
/// On a security key (`securityKey`), OpenSSH's `_sk` names.
String freeKeyName(
  SshKeyType type,
  Iterable<String> taken, {
  bool securityKey = false,
  bool enclaveKey = false,
}) {
  final base =
      switch (type) {
        SshKeyType.ed25519 => 'id_ed25519',
        SshKeyType.ecdsa => 'id_ecdsa',
        SshKeyType.rsa => 'id_rsa',
      } +
      (enclaveKey
          ? '_enclave'
          : securityKey
          ? '_sk'
          : '');
  final names = taken.toSet();
  if (!names.contains(base)) return base;
  for (var i = 2; ; i++) {
    if (!names.contains('${base}_$i')) return '${base}_$i';
  }
}

/// Where a key is being put: how the connection goes, then whether it
/// went in.
enum InstallStep { connecting, installing, done, failed }

/// A connection made only to put one public key on a server; it closes
/// when that is done.
class KeyInstall extends ConnectionController {
  KeyInstall({
    required super.app,
    required super.label,
    required this.line,
    super.hostId,
    super.target,
  }) : browser = app.sftp();

  final SftpBrowser browser;

  /// The `authorized_keys` line.
  final String line;

  InstallStep step = InstallStep.connecting;

  /// Once done: false when the server had the key already.
  bool added = false;

  /// Why it failed once connected (writing the file).
  Object? writeError;

  @override
  Stream<SessionEvent> open() {
    final hostId = this.hostId;
    final target = this.target;
    return hostId != null
        ? app.connectSftp(browser: browser, hostId: hostId)
        : app.connectSftpAddress(
            browser: browser,
            address: target!.address,
            user: target.user,
            port: target.port,
          );
  }

  @override
  void stop() => browser.close();

  @override
  void onEvent(SessionEvent e) {
    super.onEvent(e);
    if (e.kind == SessionEventKind.connected &&
        step == InstallStep.connecting) {
      _install();
    } else if (e.kind == SessionEventKind.closed &&
        step == InstallStep.connecting) {
      step = InstallStep.failed;
      notify();
    }
  }

  Future<void> _install() async {
    step = InstallStep.installing;
    notify();
    try {
      added = await browser.installPublicKey(line: line);
      step = InstallStep.done;
    } catch (e) {
      writeError = e;
      step = InstallStep.failed;
    }
    browser.close();
    notify();
  }

  @override
  void cancel() {
    super.cancel();
    if (step == InstallStep.connecting) step = InstallStep.failed;
    notify();
  }
}

/// Starts putting `line` on a saved host or on an address.
KeyInstall startKeyInstall(
  OpenWard app,
  String line, {
  String? hostId,
  QuickTarget? target,
  required String label,
}) => KeyInstall(
  app: app,
  label: label,
  line: line,
  hostId: hostId,
  target: target,
)..start();

/// A key's public half for copying, or null when there is none to read
/// (an encrypted key without its `.pub`).
Future<String?> publicLineOf(WidgetRef ref, SshKey key) =>
    ref.read(openWardProvider).publicKeyLine(path: key.path);

/// The key's type as people say it.
String keyTypeLabel(SshKeyType t) => switch (t) {
  SshKeyType.ed25519 => 'Ed25519',
  SshKeyType.ecdsa => 'ECDSA P-256',
  SshKeyType.rsa => 'RSA 4096',
};
