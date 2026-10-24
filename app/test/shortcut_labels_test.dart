import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/app_localizations_en.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/window/shortcuts.dart';

List<String> _keys(List<ShortcutGroup> groups) => [
  for (final g in groups)
    for (final r in g.rows) ...r.keys,
];

void main() {
  /// The sheet in each language and platform: the keys as that keyboard
  /// and that language name them.
  test('the shortcuts, named as each keyboard and language do', () {
    final es = AppLocalizationsEs(), en = AppLocalizationsEn();
    final mac = _keys(shortcutGroups(es, apple: true)).join(' ');
    expect(mac, isNot(contains('Ctrl')));
    expect(mac, isNot(contains('Mayús')));
    final esOther = _keys(shortcutGroups(es, apple: false)).join(' ');
    for (final apple in ['⌘', '⌥', '⌫', '⇧', 'Shift', 'Del ']) {
      expect(esOther, isNot(contains(apple)), reason: apple);
    }
    expect(esOther, contains('Ctrl+Mayús+'));
    expect(esOther, contains('Retroceso'));
    final enOther = _keys(shortcutGroups(en, apple: false)).join(' ');
    for (final word in ['Mayús', 'Supr', 'Retroceso', '⌘']) {
      expect(enOther, isNot(contains(word)), reason: word);
    }
  });

  /// One model: no screen writes a shortcut of its own that skips it.
  test('no shortcut is written by hand outside the model', () {
    final banned = {
      "'Ctrl+Shift": 'use l.ctrlShiftPrefix',
      '⇧⌘': '⌘ first, as everywhere in the app',
      "'Supr'": 'use l.keyDelete',
      "'Del'": 'use l.keyDelete',
      '+⌫': 'use l.keyBackspace',
    };
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/l10n/') || f.path.contains('/src/rust/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        for (final MapEntry(key: bad, value: why) in banned.entries) {
          if (line.contains(bad)) found.add('${f.path}:${i + 1}: $bad ($why)');
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
