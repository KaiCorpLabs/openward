import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/terminal/schemes.dart';

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

  test('themes, layers, imported schemes and accessibility come back', () {
    final s =
        const Settings(
              lightTheme: 'nativo',
              darkTheme: 'fosforo',
              textScale: 1.25,
              lineHeight: 1.35,
              minimumContrast: false,
              motion: MotionChoice.reduce,
              cursor: CursorChoice.bar,
              cursorBlink: true,
              bellFlash: false,
            )
            .copyWith(schemes: [knownSchemes.first])
            .withOverrides(
              'fosforo',
              (o) => o.copyWith(
                colors: () => 'grafito',
                terminalFont: () => 'Fira Code',
                terminal: TerminalColors.scheme,
                scheme: () => 'nord',
              ),
            );
    final back = Settings.fromJson(s.toJson());
    expect(back, s);
    expect(back.overrides['fosforo']!.terminalFont, 'Fira Code');
    expect(back.schemes.single.name, 'Solarized Dark');
  });

  test('resetting a theme forgets its layers', () {
    final s = const Settings()
        .withOverrides('grafito', (o) => o.copyWith(shape: () => 'papel'))
        .withOverrides('grafito', (_) => const ThemeOverrides());
    expect(s.overrides, isEmpty);
  });
}
