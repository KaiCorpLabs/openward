import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/settings.dart';

void main() {
  test('settings go to JSON and back', () {
    const s = Settings(
      fontSize: 15,
      theme: ThemeChoice.light,
      language: Language.en,
      welcomed: true,
    );
    expect(Settings.fromJson(s.toJson()), s);
  });

  test('an old file (no language, no guide) gets the defaults', () {
    final s = Settings.fromJson({'font_size': 14, 'theme': 'dark'});
    expect(s.language, Language.system);
    expect(s.welcomed, isFalse);
    expect(s.fontSize, 14);
  });

  test('unknown values fall back one by one', () {
    final s = Settings.fromJson({'language': 'klingon', 'welcomed': 'yes'});
    expect(s.language, Language.system);
    expect(s.welcomed, isFalse);
  });
}
