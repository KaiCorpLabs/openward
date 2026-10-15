import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

/// `{name}` placeholders and the heads of `{name, plural, …}`, without the
/// sub-messages of a plural.
Set<String> _holes(String text) => {
  for (final m in RegExp(r'\{(\w+)(?:\}|, )').allMatches(text))
    if (!RegExp(r'(=\d+|zero|one|two|few|many|other)$')
        .hasMatch(text.substring(0, m.start)))
      m[1]!,
};

void main() {
  test('English has every Spanish text, with the same placeholders', () {
    final es = _arb('es');
    final en = _arb('en');
    final keys = es.keys.where((k) => !k.startsWith('@'));
    expect(en.keys.where((k) => !k.startsWith('@')).toSet(), keys.toSet());
    for (final k in keys) {
      expect(_holes(en[k]! as String), _holes(es[k]! as String), reason: k);
    }
  });
}
