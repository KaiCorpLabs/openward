import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/tabs/messages.dart';

void main() {
  test('network failures in words: a silent server, an unreachable host', () {
    final l = AppLocalizationsEs();
    expect(
      networkReason(l, 'no answer for 15 s'),
      'no responde (15 s sin respuesta).',
    );
    expect(networkReason(l, 'Connection refused (os error 61)'), l.netRefused);
    // On macOS, also what the Local Network permission being off looks like.
    expect(
      networkReason(l, 'No route to host (os error 65)'),
      startsWith('no se llega al host'),
    );
  });
}
