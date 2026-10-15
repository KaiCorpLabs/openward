import 'dart:math' as math;
import 'dart:ui';

/// Resolves wire colors (see `Span.fg`) against a theme.
final class TermPalette {
  TermPalette({
    required this.dark,
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.selection,
    required List<Color> ansi16,
  }) : assert(ansi16.length == 16),
       ansi16 = List.unmodifiable(ansi16),
       _indexed = _buildIndexed(ansi16);

  /// From `#rrggbb` strings; dark when the background is.
  factory TermPalette.hex({
    required String foreground,
    required String background,
    String? cursor,
    String? selection,
    required List<String> ansi,
  }) {
    final bg = parseHex(background)!;
    final fg = parseHex(foreground)!;
    final cur = cursor == null ? fg : parseHex(cursor)!;
    return TermPalette(
      dark: luminance(bg) < 0.4,
      foreground: fg,
      background: bg,
      cursor: cur,
      selection: selection == null
          ? cur.withValues(alpha: 0.35)
          : parseHex(selection)!.withValues(alpha: 0.6),
      ansi16: [for (final h in ansi) parseHex(h)!],
    );
  }

  /// The 16 base colors, as given.
  final List<Color> ansi16;

  /// `#rrggbb` or `rrggbb`; null if it is neither.
  static Color? parseHex(String text) {
    var t = text.trim();
    if (t.startsWith('#')) t = t.substring(1);
    if (t.length != 6) return null;
    final v = int.tryParse(t, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  static String toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Map<String, Object> toJson() => {
    'foreground': toHex(foreground),
    'background': toHex(background),
    'cursor': toHex(cursor),
    'selection': toHex(selection.withValues(alpha: 1)),
    'ansi': [for (final c in ansi16) toHex(c)],
  };

  static TermPalette? fromJson(Object? json) {
    if (json is! Map) return null;
    final ansi = json['ansi'];
    if (ansi is! List || ansi.length != 16) return null;
    try {
      return TermPalette.hex(
        foreground: json['foreground'] as String,
        background: json['background'] as String,
        cursor: json['cursor'] as String?,
        selection: json['selection'] as String?,
        ansi: [for (final a in ansi) a as String],
      );
    } catch (_) {
      return null;
    }
  }

  /// Relative luminance (WCAG 2).
  static double luminance(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  /// WCAG 2 contrast ratio, from 1 to 21.
  static double contrast(Color a, Color b) {
    final x = luminance(a), y = luminance(b);
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  /// `fg`, or the closest color to it (towards black or white, away from
  /// `bg`) that reads at `ratio` on `bg`: the minimum contrast option.
  static Color ensureContrast(Color fg, Color bg, double ratio) {
    if (ratio <= 1 || contrast(fg, bg) >= ratio) return fg;
    final toward = luminance(bg) > 0.18
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    if (contrast(toward, bg) < ratio) return toward;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      if (contrast(Color.lerp(fg, toward, mid)!, bg) >= ratio) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return Color.lerp(fg, toward, hi)!.withValues(alpha: fg.a);
  }

  /// Programs are told whether the theme is dark (DSR 996).
  final bool dark;
  final Color foreground;
  final Color background;
  final Color cursor;

  /// Painted over selected cells, so it must let the text through.
  final Color selection;
  final List<Color> _indexed;

  /// Grafito's: dark, on the same background as its windows.
  static final TermPalette grafito = TermPalette(
    dark: true,
    foreground: const Color(0xFFD4D9E0),
    background: const Color(0xFF12161B),
    cursor: const Color(0xFF3CC8B0),
    selection: const Color(0x593CC8B0),
    ansi16: const [
      Color(0xFF1E2127),
      Color(0xFFE06C75),
      Color(0xFF98C379),
      Color(0xFFD19A66),
      Color(0xFF61AFEF),
      Color(0xFFC678DD),
      Color(0xFF56B6C2),
      Color(0xFFABB2BF),
      Color(0xFF5C6370),
      Color(0xFFFF7A85),
      Color(0xFFB5E890),
      Color(0xFFE5C07B),
      Color(0xFF7CC4FF),
      Color(0xFFDE9CF0),
      Color(0xFF7BD6E0),
      Color(0xFFFFFFFF),
    ],
  );

  /// Papel's: light, with ANSI colors dark enough to read on paper.
  static final TermPalette papel = TermPalette(
    dark: false,
    foreground: const Color(0xFF1F1D1A),
    background: const Color(0xFFFFFEFB),
    cursor: const Color(0xFF1F1D1A),
    selection: const Color(0x400E8F7D),
    ansi16: const [
      Color(0xFF24292E),
      Color(0xFFCF222E),
      Color(0xFF116329),
      Color(0xFF7D4E00),
      Color(0xFF0969DA),
      Color(0xFF8250DF),
      Color(0xFF1B7C83),
      Color(0xFF6E7781),
      Color(0xFF57606A),
      Color(0xFFA40E26),
      Color(0xFF1A7F37),
      Color(0xFF633C01),
      Color(0xFF218BFF),
      Color(0xFFA475F9),
      Color(0xFF3192AA),
      Color(0xFF8C959F),
    ],
  );

  /// `0xRRGGBB`, as the core takes colors.
  static int rgb(Color c) => c.toARGB32() & 0xFFFFFF;

  Color resolve(int raw, {required bool foreground}) {
    final value = raw & 0xFFFFFF;
    switch (raw >>> 24) {
      case 1:
        if (value < 16) return _indexed[value];
        if (value < 24) return _indexed[value - 16].withValues(alpha: 0.66);
      case 2:
        return _indexed[value & 0xFF];
      case 3:
        return Color(0xFF000000 | value);
    }
    return foreground ? this.foreground : background;
  }

  static List<Color> _buildIndexed(List<Color> ansi16) {
    const levels = [0, 95, 135, 175, 215, 255];
    return [
      ...ansi16,
      for (var r = 0; r < 6; r++)
        for (var g = 0; g < 6; g++)
          for (var b = 0; b < 6; b++)
            Color.fromARGB(255, levels[r], levels[g], levels[b]),
      for (var i = 0; i < 24; i++)
        Color.fromARGB(255, 8 + 10 * i, 8 + 10 * i, 8 + 10 * i),
    ];
  }
}
