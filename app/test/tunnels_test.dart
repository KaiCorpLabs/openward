import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/app_localizations.dart';
import 'package:openward/src/rust/api/tunnels.dart';
import 'package:openward/tunnels/tunnels_page.dart';

TunnelView tunnel(
  TunnelKind kind, {
  String? listenAddress,
  TunnelStateKind state = TunnelStateKind.closed,
  int connections = 0,
  TunnelErrorView? error,
}) => TunnelView(
  id: '1',
  rev: BigInt.one,
  spec: TunnelSpec(
    label: 'Postgres',
    hostId: 'h',
    kind: kind,
    listenPort: kind == TunnelKind.remote ? 8080 : 5433,
    listenAddress: listenAddress,
    destHost: kind == TunnelKind.dynamic_ ? null : '10.0.4.21',
    destPort: kind == TunnelKind.dynamic_ ? null : 5432,
    autostart: false,
  ),
  hostLabel: 'db-primary',
  imported: false,
  state: state,
  port: 0,
  connections: connections,
  error: error,
  onConnect: false,
);

TunnelErrorView error(
  TunnelErrorKind kind, {
  int port = 0,
  bool remote = false,
}) => TunnelErrorView(kind: kind, port: port, remote: remote, message: 'm');

void main() {
  final es = lookupAppLocalizations(const Locale('es'));

  test('what a tunnel forwards, in a line', () {
    expect(
      forwardText(tunnel(TunnelKind.local)),
      'localhost:5433 → 10.0.4.21:5432',
    );
    expect(
      forwardText(tunnel(TunnelKind.local, listenAddress: '0.0.0.0')),
      '*:5433 → 10.0.4.21:5432',
    );
    expect(forwardText(tunnel(TunnelKind.dynamic_)), 'localhost:5433 (SOCKS5)');
    expect(
      forwardText(tunnel(TunnelKind.remote)),
      'db-primary:8080 → 10.0.4.21:5432',
    );
  });

  test('how it stands, and why it failed', () {
    expect(stateText(es, tunnel(TunnelKind.local)), 'Detenido');
    expect(
      stateText(
        es,
        tunnel(TunnelKind.local, state: TunnelStateKind.open, connections: 2),
      ),
      'Abierto · 2 conexiones',
    );
    final busy = tunnel(
      TunnelKind.local,
      state: TunnelStateKind.failed,
      error: error(TunnelErrorKind.portInUse, port: 5433),
    );
    expect(stateText(es, busy), 'No se abrió');
    expect(
      tunnelErrorText(es, busy),
      'el puerto 5433 de este equipo está ocupado.',
    );
    final remote = tunnel(
      TunnelKind.remote,
      state: TunnelStateKind.failed,
      error: error(TunnelErrorKind.portInUse, port: 8080, remote: true),
    );
    expect(
      tunnelErrorText(es, remote),
      'db-primary no abrió el puerto 8080 (en uso o no permitido).',
    );
    final lost = tunnel(
      TunnelKind.local,
      state: TunnelStateKind.failed,
      error: error(TunnelErrorKind.lost),
    );
    expect(stateText(es, lost), 'Se cortó');
    expect(
      es.tunnelDidNotOpen('pgAdmin', tunnelErrorText(es, busy)),
      'No se abrió «pgAdmin» al conectar: el puerto 5433 de este equipo está ocupado.',
    );
  });
}
