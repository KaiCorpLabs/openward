// What a session's state looks like in words, in the interface's language.

import 'dart:io' show Platform;

import '../core/errors.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../terminal/keys.dart' show isApple;
import '../terminal/controller.dart';

String stageText(AppLocalizations l, StageView s) {
  final hop = s.hops > 1 ? ' (${s.hop + 1}/${s.hops})' : '';
  return switch (s.stage) {
    StageKind.connecting => l.stageConnecting(s.label, hop),
    StageKind.authenticating => l.stageAuthenticating(s.label, hop),
    StageKind.touchKey => l.stageTouchKey(s.label),
    StageKind.openingShell => l.stageOpeningShell(s.label),
    StageKind.openingSftp => l.stageOpeningSftp(s.label),
  };
}

String failureText(AppLocalizations l, FailureView f) {
  return switch (f.kind) {
    FailureKind.hostKeyChanged => l.failureHostKeyChanged(
      f.label,
      f.fingerprint,
    ),
    FailureKind.hostKeyRejected => l.failureHostKeyRejected(f.label),
    FailureKind.hostKeyRevoked => l.failureHostKeyRevoked(
      f.label,
      f.fingerprint,
    ),
    FailureKind.badCertificate => l.failureBadCertificate(
      f.label,
      switch (f.cert) {
        CertKind.notHost => l.certNotHost,
        CertKind.noAuthority => l.certNoAuthority,
        CertKind.untrusted => l.certUntrusted,
        CertKind.outOfDate => l.certOutOfDate,
        CertKind.notForHost || null => l.certNotForHost,
      },
    ),
    // What it likely failed for first: a security key that did not sign,
    // a certificate that ran out.
    FailureKind.authFailed when f.securityKey != null =>
      l.failureAuthSecurityKey(
        f.user,
        f.label,
        securityKeyReason(l, f.securityKey!),
      ),
    FailureKind.authFailed when f.expiredCertificate.isNotEmpty =>
      l.failureAuthCertExpired(f.user, f.label, f.expiredCertificate),
    FailureKind.authFailed =>
      f.methods.isEmpty
          ? l.failureAuth(f.user, f.label)
          : l.failureAuthMethods(f.user, f.label, f.methods.join(', ')),
    FailureKind.cancelled => l.cancelled,
    FailureKind.noSftp => l.failureNoSftp(f.label),
    FailureKind.network => '${f.label}: ${networkReason(l, f)}',
    FailureKind.serial => serialReason(l, f),
    // The core's words are in «Detalles».
    FailureKind.other || null => l.failureOther,
  };
}

/// A network failure, in words, by the kind the core gives it; one it
/// could not tell, with the core's words in «Detalles».
String networkReason(AppLocalizations l, FailureView f) => switch (f.net) {
  NetKind.refused => l.netRefused,
  NetKind.notFound => l.netNotFound,
  // On macOS, also what an app without the Local Network permission gets.
  NetKind.unreachable => isApple ? l.netUnreachableMac : l.netUnreachable,
  NetKind.silent => f.seconds == 0 ? l.netTimeout : l.netNoAnswer(f.seconds),
  NetKind.lost => l.netLost,
  // What the command wrote: its words, not the core's.
  NetKind.proxyCommand => l.netProxyCommand(f.reason),
  NetKind.other || null => l.netOther,
};

/// Why a security key did not sign or make a key, in words.
String securityKeyReason(AppLocalizations l, SecurityKeyKind k) => switch (k) {
  SecurityKeyKind.noKey => l.skNoKey,
  SecurityKeyKind.tooManyKeys => l.skTooManyKeys,
  SecurityKeyKind.pinRequired => l.skPinRequired,
  SecurityKeyKind.wrongPin => l.skWrongPin,
  SecurityKeyKind.locked => l.skLocked,
  SecurityKeyKind.notTouched => l.skNotTouched,
  SecurityKeyKind.notThisKey => l.skNotThisKey,
  // Linux without the udev rule; Windows without administrator rights.
  SecurityKeyKind.noAccess =>
    Platform.isLinux ? l.skNoAccessLinux : l.skNoAccess,
  SecurityKeyKind.other => l.skOther,
};

/// A serial port that did not open or went away, in words; the core's
/// own words in «Detalles».
String serialReason(AppLocalizations l, FailureView f) => switch (f.serial) {
  SerialKind.missing => l.failureSerialMissing(f.host),
  SerialKind.busy => l.failureSerialBusy(f.host),
  // On Linux the port's group is the usual reason: say how to join it.
  SerialKind.denied =>
    Platform.isLinux
        ? l.failureSerialDeniedLinux(f.host)
        : l.failureSerialDenied(f.host),
  SerialKind.settings => l.failureSerialSettings(f.host),
  SerialKind.gone => l.failureSerialGone(f.host),
  SerialKind.other || null => l.failureSerialOther(f.host),
};

/// The hops before the target, for "via bastion".
String? viaText(AppLocalizations l, ConnectionController c) {
  if (c.route.length < 2) return null;
  return l.via(c.route.sublist(0, c.route.length - 1).join(' → '));
}

/// One line about the session when it is not simply connected.
String statusText(AppLocalizations l, ConnectionController c) {
  final error = c.error;
  if (error != null) {
    final cause = c.errorCause;
    return l.statusError(cause == null ? error : errorReason(l, cause));
  }
  switch (c.phase) {
    case Phase.connecting:
      final s = c.stage;
      if (c.prompts.isNotEmpty) return l.waitingAnswer;
      return s == null
          ? (c.isLocal ? l.starting : l.connectingEllipsis)
          : stageText(l, s);
    case Phase.reconnecting:
      final s = c.stage;
      if (s != null) return l.reconnectingStage(stageText(l, s));
      return l.reconnectingEllipsis;
    case Phase.running:
      return l.localTerminal;
    case Phase.connected:
      return l.statusConnected;
    case Phase.closed:
      if (c.cancelled) return l.cancelled;
      final closed = c.closed;
      final failure = closed?.failure;
      if (failure != null) return failureText(l, failure);
      final code = closed?.exitCode;
      return code == null ? l.sessionClosed : l.sessionClosedCode(code);
  }
}
