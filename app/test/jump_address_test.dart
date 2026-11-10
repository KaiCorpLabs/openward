import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/address.dart';
import 'package:openward/src/rust/api/vault.dart';

void main() {
  test('jump addresses', () {
    String? show(String text) {
      final j = parseJumpAddress(text);
      return j == null ? null : '${j.user}|${j.address}|${j.port}';
    }

    expect(show('bastion'), 'null|bastion|null');
    expect(show('ops@bastion:2222'), 'ops|bastion|2222');
    expect(show('ops@[::1]:22'), 'ops|::1|22');
    expect(show('[fe80::1]'), 'null|fe80::1|null');
    expect(show('host:port'), isNull);
    expect(show('@host'), isNull);
    expect(show('a b'), isNull);
    expect(show('host:70000'), isNull);
    expect(show(''), isNull);
  });

  test('quick connect labels', () {
    expect(QuickTarget.parse('ops@[::1]:2222')!.label, 'ops@[::1]:2222');
    expect(QuickTarget.parse('web-1')!.label, 'web-1');
    expect(QuickTarget.parse('root@10.0.0.7')!.port, isNull);
  });

  /// Telnet and serial ports are written so that recents, logs and
  /// workspaces open them again the same way.
  test('telnet:// and serial://, read back as written', () {
    final telnet = QuickTarget.parse('telnet://admin@10.0.9.2:2323')!;
    expect(telnet.protocol, ProtocolKind.telnet);
    expect(
      (telnet.user, telnet.address, telnet.port),
      ('admin', '10.0.9.2', 2323),
    );
    expect(telnet.label, 'telnet://admin@10.0.9.2:2323');
    expect(QuickTarget.parse('TELNET://sw-1')!.label, 'telnet://sw-1');
    expect(QuickTarget.parse('telnet://'), isNull);

    final plain = QuickTarget.parse('serial:///dev/cu.usbserial-1410')!;
    expect(plain.isSerial, isTrue);
    expect(plain.address, '/dev/cu.usbserial-1410');
    expect(plain.serial, defaultSerialLine);
    expect(plain.label, 'serial:///dev/cu.usbserial-1410');

    final fast = QuickTarget.parse('serial://COM3:115200')!;
    expect((fast.address, fast.serial!.baud), ('COM3', 115200));
    expect(fast.label, 'serial://COM3:115200');

    final odd = QuickTarget.parse('serial://COM4:9600,7E2,rtscts')!;
    expect(
      odd.serial,
      const SerialLineSpec(
        baud: 9600,
        dataBits: 7,
        parity: ParityKind.even,
        stopBits: 2,
        flow: FlowKind.hardware,
      ),
    );
    expect(odd.label, 'serial://COM4:9600,7E2,rtscts');
    for (final bad in [
      'serial://',
      'serial://COM3:0',
      'serial://COM3:9600,9X1',
    ]) {
      expect(QuickTarget.parse(bad), isNull, reason: bad);
    }
  });

  test('a jump is an SSH address', () {
    expect(parseJumpAddress('telnet://bastion'), isNull);
    expect(parseJumpAddress('serial://COM3'), isNull);
  });
}
