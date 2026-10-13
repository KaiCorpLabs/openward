// What a session's state looks like in words. Spanish only for the alpha;
// the other languages come with i18n (ARCHITECTURE §3.1).

import '../src/rust/api/session.dart';
import '../terminal/controller.dart';

String stageText(StageView s) {
  final hop = s.hops > 1 ? ' (${s.hop + 1}/${s.hops})' : '';
  return switch (s.stage) {
    StageKind.connecting => 'Conectando con ${s.label}$hop…',
    StageKind.authenticating => 'Autenticando en ${s.label}$hop…',
    StageKind.openingShell => 'Abriendo el shell en ${s.label}…',
  };
}

String failureText(FailureView f) {
  return switch (f.kind) {
    FailureKind.hostKeyChanged =>
      'La clave de ${f.label} ha cambiado (ahora ${f.fingerprint}). '
          'Puede ser un ataque: no se ha conectado.',
    FailureKind.hostKeyRejected =>
      'No se ha confiado en la clave de ${f.label}.',
    FailureKind.badCertificate =>
      'El certificado de ${f.label} no es válido: ${f.reason}.',
    FailureKind.authFailed =>
      '${f.user}@${f.label} no ha podido autenticarse'
          '${f.methods.isEmpty ? '' : ' (el servidor acepta: ${f.methods.join(', ')})'}.',
    FailureKind.cancelled => 'Cancelado.',
    FailureKind.network => '${f.label}: ${networkReason(f.reason)}',
    FailureKind.other || null => f.reason.isEmpty ? f.message : f.reason,
  };
}

/// The usual network errors, in words; the rest as they come.
String networkReason(String reason) {
  final r = reason.toLowerCase();
  if (r.contains('connection refused')) return 'conexión rechazada.';
  if (r.contains('timed out')) return 'tiempo de espera agotado.';
  if (r.contains('failed to lookup') ||
      r.contains('nodename nor servname') ||
      r.contains('name or service not known')) {
    return 'no se encuentra el host.';
  }
  if (r.contains('connection lost') || r.contains('disconnected')) {
    return 'se ha perdido la conexión.';
  }
  return reason;
}

/// One line for the status bar.
String statusText(TerminalController c) {
  final error = c.error;
  if (error != null) return 'Error: $error';
  switch (c.phase) {
    case Phase.connecting:
      final s = c.stage;
      if (c.prompts.isNotEmpty) return 'Esperando respuesta…';
      return s == null
          ? (c.isLocal ? 'Arrancando…' : 'Conectando…')
          : stageText(s);
    case Phase.running:
      return 'Terminal local';
    case Phase.connected:
      final k = c.connected!;
      final pq = k.postQuantum ? 'poscuántico (${k.kex})' : k.kex;
      final via = k.hops > 1
          ? ' · ${k.hops - 1} salto${k.hops > 2 ? 's' : ''}'
          : '';
      return 'Conectado · $pq · ${k.cipher}$via';
    case Phase.closed:
      final closed = c.closed;
      final failure = closed?.failure;
      if (failure != null) return failureText(failure);
      final code = closed?.exitCode;
      return code == null
          ? 'Sesión cerrada.'
          : 'Sesión cerrada (código $code).';
  }
}
