import '../src/rust/api/vault.dart';

/// 9600 8N1 without flow control: what most consoles use.
const defaultSerialLine = SerialLineSpec(
  baud: 9600,
  dataBits: 8,
  parity: ParityKind.none,
  stopBits: 1,
  flow: FlowKind.none,
);

/// An address typed by hand, to connect to without saving a host: by SSH
/// or Telnet, or a serial port of this computer.
class QuickTarget {
  const QuickTarget({
    required this.address,
    this.user,
    this.port,
    this.protocol = ProtocolKind.ssh,
    this.serial,
  });

  /// A serial port (`/dev/cu.usbserial-1410`, `COM3`) with its settings.
  const QuickTarget.serialPort(String path, SerialLineSpec line)
    : this(address: path, protocol: ProtocolKind.serial, serial: line);

  /// The host, or the serial port.
  final String address;
  final String? user;
  final int? port;
  final ProtocolKind protocol;

  /// With a serial port.
  final SerialLineSpec? serial;

  bool get isSerial => protocol == ProtocolKind.serial;

  /// As the user would write it: `ops@[::1]:2222`, `telnet://10.0.9.2`,
  /// `serial://COM3:115200`. [parse] reads it back.
  String get label {
    if (isSerial) return 'serial://$address${_line(serial)}';
    final host = address.contains(':') ? '[$address]' : address;
    final plain =
        '${user == null ? '' : '$user@'}$host'
        '${port == null ? '' : ':$port'}';
    return protocol == ProtocolKind.telnet ? 'telnet://$plain' : plain;
  }

  /// `:115200`, `:115200,7E1`, `:9600,8N1,rtscts`: only what differs
  /// from the defaults.
  static String _line(SerialLineSpec? l) {
    if (l == null || l == defaultSerialLine) return '';
    final frame = '${l.dataBits}${_parityLetter[l.parity]}${l.stopBits}';
    final flow = switch (l.flow) {
      FlowKind.none => '',
      FlowKind.software => ',xonxoff',
      FlowKind.hardware => ',rtscts',
    };
    return frame == '8N1' && flow.isEmpty
        ? ':${l.baud}'
        : ':${l.baud},$frame$flow';
  }

  static const _parityLetter = {
    ParityKind.none: 'N',
    ParityKind.odd: 'O',
    ParityKind.even: 'E',
  };

  /// `[user@]host[:port]`, with `[…]` around IPv6 addresses, after
  /// `telnet://` for Telnet; or `serial://port[:baud[,8N1[,flow]]]`. Null
  /// if it does not parse.
  static QuickTarget? parse(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('serial://')) {
      return _serial(trimmed.substring('serial://'.length));
    }
    if (lower.startsWith('telnet://')) {
      final t = _plain(trimmed.substring('telnet://'.length));
      return t == null
          ? null
          : QuickTarget(
              address: t.address,
              user: t.user,
              port: t.port,
              protocol: ProtocolKind.telnet,
            );
    }
    return _plain(trimmed);
  }

  static QuickTarget? _plain(String text) {
    var rest = text;
    if (rest.isEmpty || rest.contains(' ')) return null;
    String? user;
    final at = rest.lastIndexOf('@');
    if (at >= 0) {
      user = rest.substring(0, at);
      rest = rest.substring(at + 1);
      if (user.isEmpty) return null;
    }
    String host = rest;
    int? port;
    if (rest.startsWith('[')) {
      final close = rest.indexOf(']');
      if (close < 0) return null;
      host = rest.substring(1, close);
      final after = rest.substring(close + 1);
      if (after.isNotEmpty) {
        if (!after.startsWith(':')) return null;
        port = int.tryParse(after.substring(1));
        if (port == null) return null;
      }
    } else if (rest.contains(':')) {
      final colon = rest.lastIndexOf(':');
      host = rest.substring(0, colon);
      port = int.tryParse(rest.substring(colon + 1));
      if (port == null || host.contains(':')) return null;
    }
    if (host.isEmpty || (port != null && (port < 1 || port > 65535))) {
      return null;
    }
    return QuickTarget(address: host, user: user, port: port);
  }

  static QuickTarget? _serial(String text) {
    var path = text;
    var line = defaultSerialLine;
    final colon = text.lastIndexOf(':');
    if (colon > 0) {
      final parts = text.substring(colon + 1).split(',');
      final baud = int.tryParse(parts.first);
      // Not a speed: the colon is the port's own (`\\.\COM10:` is not
      // written so, but a path could have one).
      if (baud != null) {
        if (baud < 1) return null;
        path = text.substring(0, colon);
        line = SerialLineSpec(
          baud: baud,
          dataBits: line.dataBits,
          parity: line.parity,
          stopBits: line.stopBits,
          flow: line.flow,
        );
        if (parts.length > 1) {
          final f = RegExp(r'^([5-8])([NOE])([12])$')
              .firstMatch(parts[1].toUpperCase());
          if (f == null) return null;
          line = SerialLineSpec(
            baud: baud,
            dataBits: int.parse(f[1]!),
            parity: _parityLetter.entries
                .firstWhere((e) => e.value == f[2])
                .key,
            stopBits: int.parse(f[3]!),
            flow: line.flow,
          );
        }
        if (parts.length > 2) {
          final flow = switch (parts[2].toLowerCase()) {
            'xonxoff' => FlowKind.software,
            'rtscts' => FlowKind.hardware,
            _ => null,
          };
          if (flow == null || parts.length > 3) return null;
          line = SerialLineSpec(
            baud: line.baud,
            dataBits: line.dataBits,
            parity: line.parity,
            stopBits: line.stopBits,
            flow: flow,
          );
        }
      }
    }
    return path.isEmpty ? null : QuickTarget.serialPort(path, line);
  }
}

/// A jump through an address, from the same notation (SSH only).
JumpSpec? parseJumpAddress(String text) {
  final t = QuickTarget.parse(text);
  return t == null || t.protocol != ProtocolKind.ssh
      ? null
      : JumpSpec(address: t.address, user: t.user, port: t.port);
}
