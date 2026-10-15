// Terminal schemes from other terminals' files: iTerm2's `.itermcolors`
// (a property list) and Ghostty's theme files (`key = value` lines).

import 'dart:ui';

import 'palette.dart';
import 'schemes.dart';

/// The scheme in a file of either kind, or null if it is neither (or has
/// no background and foreground). `name` is what the user will see.
TerminalScheme? parseScheme(String fileName, String content) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  final name = (dot > 0 ? base.substring(0, dot) : base).trim();
  final palette = content.contains('<plist') || base.endsWith('.itermcolors')
      ? parseItermColors(content)
      : parseGhosttyTheme(content);
  if (palette == null) return null;
  final id =
      'custom:${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
  return TerminalScheme(id, name.isEmpty ? 'Importado' : name, palette);
}

/// xterm's colors, for entries a file leaves out.
const _xterm = [
  '#000000', '#CD0000', '#00CD00', '#CDCD00', //
  '#0000EE', '#CD00CD', '#00CDCD', '#E5E5E5',
  '#7F7F7F', '#FF0000', '#00FF00', '#FFFF00',
  '#5C5CFF', '#FF00FF', '#00FFFF', '#FFFFFF',
];

/// An iTerm2 color preset. Components are taken as sRGB whatever color
/// space the file names: close enough for terminal colors.
TermPalette? parseItermColors(String xml) {
  Color? color(String key) {
    final block = RegExp(
      '<key>\\s*${RegExp.escape(key)}\\s*</key>\\s*<dict>(.*?)</dict>',
      dotAll: true,
    ).firstMatch(xml);
    if (block == null) return null;
    double? component(String name) {
      final m = RegExp(
        '<key>\\s*$name Component\\s*</key>\\s*<(?:real|integer)>\\s*([-0-9.eE+]+)\\s*</',
      ).firstMatch(block[1]!);
      return m == null ? null : double.tryParse(m[1]!);
    }

    final r = component('Red'), g = component('Green'), b = component('Blue');
    if (r == null || g == null || b == null) return null;
    int byte(double v) => (v.clamp(0, 1) * 255).round();
    return Color.fromARGB(255, byte(r), byte(g), byte(b));
  }

  final bg = color('Background Color');
  final fg = color('Foreground Color');
  if (bg == null || fg == null) return null;
  final cursor = color('Cursor Color');
  final selection = color('Selection Color');
  return TermPalette.hex(
    foreground: TermPalette.toHex(fg),
    background: TermPalette.toHex(bg),
    cursor: cursor == null ? null : TermPalette.toHex(cursor),
    selection: selection == null ? null : TermPalette.toHex(selection),
    ansi: [
      for (var i = 0; i < 16; i++)
        switch (color('Ansi $i Color')) {
          final c? => TermPalette.toHex(c),
          null => _xterm[i],
        },
    ],
  );
}

/// A Ghostty theme: `background`, `foreground`, `cursor-color`,
/// `selection-background` and `palette = N=#rrggbb` lines.
TermPalette? parseGhosttyTheme(String text) {
  final values = <String, String>{};
  final ansi = List<String>.of(_xterm);
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    if (key == 'palette') {
      final inner = value.indexOf('=');
      final index = int.tryParse(value.substring(0, inner < 0 ? 0 : inner));
      final color = inner < 0
          ? null
          : TermPalette.parseHex(value.substring(inner + 1));
      if (index != null && index >= 0 && index < 16 && color != null) {
        ansi[index] = TermPalette.toHex(color);
      }
    } else {
      values[key] = value;
    }
  }
  String? hex(String key) {
    final c = values[key] == null ? null : TermPalette.parseHex(values[key]!);
    return c == null ? null : TermPalette.toHex(c);
  }

  final bg = hex('background'), fg = hex('foreground');
  if (bg == null || fg == null) return null;
  return TermPalette.hex(
    foreground: fg,
    background: bg,
    cursor: hex('cursor-color'),
    selection: hex('selection-background'),
    ansi: ansi,
  );
}
