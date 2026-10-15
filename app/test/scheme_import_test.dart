import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/palette.dart';
import 'package:openward/terminal/scheme_import.dart';

String _hex(Color c) => TermPalette.toHex(c);

void main() {
  test('an iTerm2 preset', () {
    String color(String name, double r, double g, double b) =>
        '''
	<key>$name</key>
	<dict>
		<key>Alpha Component</key>
		<real>1</real>
		<key>Blue Component</key>
		<real>$b</real>
		<key>Color Space</key>
		<string>sRGB</string>
		<key>Green Component</key>
		<real>$g</real>
		<key>Red Component</key>
		<real>$r</real>
	</dict>''';
    final xml =
        '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
${color('Ansi 1 Color', 1, 0, 0)}
${color('Background Color', 0.0392156862745098, 0.0509803921568627, 0.0431372549019608)}
${color('Foreground Color', 1, 1, 1)}
${color('Cursor Color', 0, 1, 0)}
</dict>
</plist>''';
    final s = parseScheme('/Users/ana/Downloads/Mi Tema.itermcolors', xml)!;
    expect(s.name, 'Mi Tema');
    expect(s.id, 'custom:mi-tema');
    expect(_hex(s.palette.background), '#0a0d0b');
    expect(_hex(s.palette.foreground), '#ffffff');
    expect(_hex(s.palette.cursor), '#00ff00');
    expect(_hex(s.palette.ansi16[1]), '#ff0000');
    // Left out: xterm's.
    expect(_hex(s.palette.ansi16[2]), '#00cd00');
    expect(s.palette.dark, isTrue);
  });

  test('a Ghostty theme', () {
    const text = '''
# A light theme
palette = 0=#1d1f21
palette = 1=#cc6666
palette = 15=ffffff
background = fdf6e3
foreground = #657b83
cursor-color = #586e75
selection-background = #eee8d5
''';
    final s = parseScheme('solar-ish', text)!;
    expect(s.name, 'solar-ish');
    expect(_hex(s.palette.background), '#fdf6e3');
    expect(_hex(s.palette.ansi16[0]), '#1d1f21');
    expect(_hex(s.palette.ansi16[15]), '#ffffff');
    expect(s.palette.dark, isFalse);
  });

  test('anything else is not a scheme', () {
    expect(parseScheme('notes.txt', 'hello = world'), isNull);
    expect(
      parseScheme('x.itermcolors', '<plist><dict></dict></plist>'),
      isNull,
    );
  });
}
