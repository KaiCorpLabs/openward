// What a session's state looks like in words, in the interface's language.

import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../terminal/keys.dart' show isApple;
import '../terminal/controller.dart';

String stageText(AppLocalizations l, StageView s) {
  final hop = s.hops > 1 ? ' (${s.hop + 1}/${s.hops})' : '';
  return switch (s.stage) {
    StageKind.connecting => l.stageConnecting(s.label, hop),
    StageKind.authenticating => l.stageAuthenticating(s.label, hop),
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
    FailureKind.badCertificate => l.failureBadCertificate(f.label, f.reason),
    FailureKind.authFailed =>
      f.methods.isEmpty
          ? l.failureAuth(f.user, f.label)
          : l.failureAuthMethods(f.user, f.label, f.methods.join(', ')),
    FailureKind.cancelled => l.cancelled,
    FailureKind.noSftp => l.failureNoSftp(f.label),
    FailureKind.network => '${f.label}: ${networkReason(l, f.reason)}',
    FailureKind.other || null => f.reason.isEmpty ? f.message : f.reason,
  };
}

/// The usual network errors, in words; the rest as they come.
String networkReason(AppLocalizations l, String reason) {
  final r = reason.toLowerCase();
  if (r.contains('connection refused')) return l.netRefused;
  if (r.contains('timed out')) return l.netTimeout;
  if (r.contains('failed to lookup') ||
      r.contains('nodename nor servname') ||
      r.contains('name or service not known')) {
    return l.netNotFound;
  }
  if (r.contains('connection lost') || r.contains('disconnected')) {
    return l.netLost;
  }
  // On macOS, also what an app without the Local Network permission gets.
  if (r.contains('no route to host') || r.contains('host is unreachable')) {
    return isApple ? l.netUnreachableMac : l.netUnreachable;
  }
  final silent = RegExp(r'no answer for (\d+) s$').firstMatch(reason);
  if (silent != null) return l.netNoAnswer(int.parse(silent.group(1)!));
  return reason;
}

/// The hops before the target, for "via bastion".
String? viaText(AppLocalizations l, ConnectionController c) {
  if (c.route.length < 2) return null;
  return l.via(c.route.sublist(0, c.route.length - 1).join(' → '));
}

/// One line about the session when it is not simply connected.
String statusText(AppLocalizations l, ConnectionController c) {
  final error = c.error;
  if (error != null) return l.statusError(error);
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
