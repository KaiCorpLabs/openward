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
       _indexed = _buildIndexed(ansi16);

  /// Programs are told whether the theme is dark (DSR 996).
  final bool dark;
  final Color foreground;
  final Color background;
  final Color cursor;

  /// Painted over selected cells, so it must let the text through.
  final Color selection;
  final List<Color> _indexed;

  static final TermPalette darkTheme = TermPalette(
    dark: true,
    foreground: const Color(0xFFD4D4D4),
    background: const Color(0xFF16181D),
    cursor: const Color(0xFF7FDBCA),
    selection: const Color(0x597FDBCA),
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

  /// Light, with ANSI colors dark enough to read on white.
  static final TermPalette lightTheme = TermPalette(
    dark: false,
    foreground: const Color(0xFF24292F),
    background: const Color(0xFFFAFAFA),
    cursor: const Color(0xFF1B7C83),
    selection: const Color(0x4D0969DA),
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
