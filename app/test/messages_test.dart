import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/tabs/messages.dart';

FailureView _failure(
  FailureKind kind, {
  NetKind? net,
  CertKind? cert,
  int seconds = 0,
  String reason = '',
}) => FailureView(
  kind: kind,
  message: 'db: $reason',
  label: 'db',
  host: '',
  port: 0,
  user: '',
  algorithm: '',
  fingerprint: '',
  key: '',
  methods: const [],
  reason: reason,
  previous: const [],
  cert: cert,
  net: net,
  seconds: seconds,
);

FailureView _network(NetKind net, {int seconds = 0, String reason = ''}) =>
    _failure(FailureKind.network, net: net, seconds: seconds, reason: reason);

void main() {
  test('network failures in words, by kind: never by the English text', () {
    final l = AppLocalizationsEs();
    expect(
      networkReason(l, _network(NetKind.silent, seconds: 15)),
      'no responde (15 s sin respuesta).',
    );
    expect(networkReason(l, _network(NetKind.silent)), l.netTimeout);
    // The words do not matter: the kind does.
    expect(
      networkReason(l, _network(NetKind.refused, reason: 'whatever')),
      l.netRefused,
    );
    // On macOS, also what the Local Network permission being off looks like.
    expect(
      networkReason(l, _network(NetKind.unreachable)),
      startsWith('no se llega al host'),
    );
    expect(failureText(l, _network(NetKind.notFound)), 'db: ${l.netNotFound}');
    // A ProxyCommand that failed: what it wrote.
    expect(
      networkReason(
        l,
        _network(
          NetKind.proxyCommand,
          reason: 'cloudflared: command not found',
        ),
      ),
      'el ProxyCommand ha fallado: cloudflared: command not found',
    );
    // One the core could not tell: in words too; its own under «Detalles».
    expect(
      networkReason(l, _network(NetKind.other, reason: 'odd thing')),
      l.netOther,
    );
  });

  test('a bad certificate says what is wrong with it, in words', () {
    final l = AppLocalizationsEs();
    final text = failureText(
      l,
      _failure(
        FailureKind.badCertificate,
        cert: CertKind.outOfDate,
        reason: 'expired or not yet valid',
      ),
    );
    expect(text, l.failureBadCertificate('db', l.certOutOfDate));
    expect(text, isNot(contains('expired')));
  });

  test('a failure the core could not tell is said in words too', () {
    final l = AppLocalizationsEs();
    final f = _failure(FailureKind.other, reason: 'opening the shell: boom');
    expect(failureText(l, f), l.failureOther);
  });

  test('a serial port says what happened to it, by kind', () {
    final l = AppLocalizationsEs();
    String say(SerialKind kind) {
      final f = FailureView(
        kind: FailureKind.serial,
        message: 'COM3 went away',
        label: 'COM3',
        host: 'COM3',
        port: 0,
        user: '',
        algorithm: '',
        fingerprint: '',
        key: '',
        methods: const [],
        reason: '',
        previous: const [],
        serial: kind,
        seconds: 0,
      );
      return failureText(l, f);
    }

    expect(say(SerialKind.missing), l.failureSerialMissing('COM3'));
    expect(say(SerialKind.busy), l.failureSerialBusy('COM3'));
    expect(say(SerialKind.gone), l.failureSerialGone('COM3'));
    expect(say(SerialKind.settings), l.failureSerialSettings('COM3'));
    expect(say(SerialKind.denied), contains('COM3'));
    for (final k in SerialKind.values) {
      expect(say(k), isNot(contains('went away')), reason: '$k');
    }
  });
}
