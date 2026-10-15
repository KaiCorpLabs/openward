import '../src/rust/api/vault.dart';

/// An address typed by hand, to connect to without saving a host.
class QuickTarget {
  const QuickTarget({required this.address, this.user, this.port});

  final String address;
  final String? user;
  final int? port;

  /// As the user would write it: `ops@[::1]:2222`.
  String get label {
    final host = address.contains(':') ? '[$address]' : address;
    return '${user == null ? '' : '$user@'}$host'
        '${port == null ? '' : ':$port'}';
  }

  /// `[user@]host[:port]`, with `[…]` around IPv6 addresses; null if it
  /// does not parse.
  static QuickTarget? parse(String text) {
    var rest = text.trim();
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
}

/// A jump through an address, from the same notation.
JumpSpec? parseJumpAddress(String text) {
  final t = QuickTarget.parse(text);
  return t == null
      ? null
      : JumpSpec(address: t.address, user: t.user, port: t.port);
}
