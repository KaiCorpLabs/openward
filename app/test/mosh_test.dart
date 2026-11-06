import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/tabs/connection_motion.dart';

void main() {
  test('why Mosh was not, in words, by kind', () {
    final l = AppLocalizationsEs();
    String say(MoshFallbackKind kind, [String said = '']) =>
        moshFallbackWords(l, MoshFallbackView(kind: kind, said: said));
    expect(say(MoshFallbackKind.noServer), l.moshFallbackNoServer);
    expect(say(MoshFallbackKind.noUdp), l.moshFallbackNoUdp);
    expect(
      say(MoshFallbackKind.other, 'the locale is not UTF-8'),
      l.moshFallbackOther('the locale is not UTF-8'),
    );
    expect(say(MoshFallbackKind.noClient), contains('SSH'));
    for (final k in MoshFallbackKind.values) {
      expect(say(k), contains('Mosh'), reason: '$k');
    }
  });
}
