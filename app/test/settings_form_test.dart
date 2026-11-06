import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/settings.dart' show Language;
import 'package:openward/hosts/editor/form.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/src/rust/api/vault.dart';

void main() {
  final l = stringsFor(Language.en);

  test('set here or inherited: taken from what it would inherit, and '
      'given back', () {
    final f = SettingsForm(const SettingsSpec(user: 'deploy'));
    addTearDown(f.dispose);
    expect(f.setHere, {'user'});
    expect(f.user.text, 'deploy');

    const inherited = SettingsSpec(
      port: 2222,
      route: RouteKind.jump,
      jumps: [JumpSpec(address: 'bastion.example.com', port: 22)],
      environment: EnvironmentKind.mark,
      environmentName: 'Producción',
      environmentShort: 'prod',
      environmentColor: 'red',
    );
    f
      ..take('port', inherited)
      ..take('route', inherited)
      ..take('environment', inherited);
    expect(f.port.text, '2222');
    expect(f.jumps.single.address, 'bastion.example.com');
    expect(f.envMark?.name, 'Producción');

    final spec = f.toSpec();
    expect(spec.user, 'deploy');
    expect(spec.port, 2222);
    expect(spec.route, RouteKind.jump);
    expect(spec.jumps, hasLength(1));
    expect(spec.environment, EnvironmentKind.mark);
    expect(spec.environmentShort, 'prod');
    expect(spec.proxyCommand, '', reason: 'only with a command route');

    f
      ..drop('user')
      ..drop('environment');
    expect(f.toSpec().user, isNull);
    expect(f.toSpec().environment, isNull);
    expect(f.envMark, isNull);
  });

  /// The protocol and the port's settings are fields like the rest: an
  /// imported Telnet host edited here stays Telnet.
  test('the protocol and a serial line, kept and inherited', () {
    final telnet = SettingsForm(
      const SettingsSpec(protocol: ProtocolKind.telnet),
    );
    addTearDown(telnet.dispose);
    expect(telnet.toSpec().protocol, ProtocolKind.telnet);
    expect(telnet.toSpec().serial, isNull);

    final f = SettingsForm(const SettingsSpec());
    addTearDown(f.dispose);
    const fromGroup = SettingsSpec(
      protocol: ProtocolKind.serial,
      serial: SerialLineSpec(
        baud: 115200,
        dataBits: 8,
        parity: ParityKind.none,
        stopBits: 1,
        flow: FlowKind.none,
      ),
    );
    expect(f.protocolWith(fromGroup), ProtocolKind.serial);
    expect(f.protocolWith(const SettingsSpec()), ProtocolKind.ssh);
    f.take('serial', fromGroup);
    expect(f.toSpec().serial?.baud, 115200);
    expect(f.toSpec().protocol, isNull, reason: 'still inherited');
    f.take('protocol', const SettingsSpec());
    expect(f.toSpec().protocol, ProtocolKind.ssh);
    expect(f.protocolWith(fromGroup), ProtocolKind.ssh, reason: 'its own');
    f.drop('serial');
    expect(f.toSpec().serial, isNull);
  });

  test('Mosh, and where its server is, set here or inherited', () {
    final f = SettingsForm(const SettingsSpec(mosh: true));
    addTearDown(f.dispose);
    expect(f.setHere, contains('mosh'));
    expect(f.toSpec().mosh, isTrue);
    expect(f.toSpec().moshServer, isNull);
    f.take('mosh_server', const SettingsSpec());
    expect(f.moshServer.text, 'mosh-server');
    f.moshServer.text = '/opt/homebrew/bin/mosh-server';
    expect(f.toSpec().moshServer, '/opt/homebrew/bin/mosh-server');
    f
      ..drop('mosh')
      ..drop('mosh_server');
    expect(f.toSpec().mosh, isNull);
    expect(f.toSpec().moshServer, isNull);
  });

  test('what stops it from saving, on its field', () {
    final f = SettingsForm(const SettingsSpec());
    addTearDown(f.dispose);
    expect(f.validate(l), isNull);

    f.take('port', const SettingsSpec());
    f.port.text = '70000';
    expect(f.validate(l)?.field, 'port');
    f.port.text = '22';
    expect(f.validate(l), isNull);

    f.take('route', const SettingsSpec());
    f.update(() => f.route = RouteKind.command);
    expect(f.validate(l)?.field, 'command');
    f.command.text = 'nc %h %p';
    expect(f.validate(l), isNull);
    f.update(() => f.route = RouteKind.jump);
    expect(f.validate(l)?.field, 'route', reason: 'a jump route needs a jump');
    f.drop('route');

    f.take('proxy', const SettingsSpec());
    f.update(() => f.proxy = ProxyKind.socks5);
    expect(f.validate(l)?.field, 'proxy');
    f.proxyHost.text = 'proxy.example.com';
    f.proxyPort.text = '1080';
    expect(f.validate(l), isNull);
    expect(f.toSpec().proxyPort, 1080);

    f.take('environment', const SettingsSpec());
    f.setEnv(const EnvironmentView(name: ' ', short: '', color: 'red'));
    expect(f.validate(l)?.field, 'environment');

    // The problem goes once its field is typed in.
    f.problem.value = f.validate(l);
    expect(f.errorOn('environment'), isNotNull);
    f.edited('environment');
    expect(f.errorOn('environment'), isNull);
  });

  test('whoever shows it is told of each change; the signature follows', () {
    final f = SettingsForm(const SettingsSpec());
    addTearDown(f.dispose);
    var told = 0;
    f.addListener(() => told++);
    final before = f.signature;

    f.take('environment', const SettingsSpec());
    f.setEnv(
      const EnvironmentView(name: 'Pruebas', short: 'qa', color: 'teal'),
    );
    f.update(() => f.keepalive = 30);
    f.drop('environment');
    expect(told, 4);
    expect(f.signature, isNot(before));
    expect(f.toSpec().keepaliveSecs, isNull, reason: 'keepalive not set here');
  });
}
