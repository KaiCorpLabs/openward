import 'dart:ui';

/// Resolves wire colors (see `Span.fg`) against a theme.
final class TermPalette {
  TermPalette({
    required this.foreground,
    required this.background,
    required this.cursor,
    required List<Color> ansi16,
  }) : assert(ansi16.length == 16),
       _indexed = _buildIndexed(ansi16);

  final Color foreground;
  final Color background;
  final Color cursor;
  final List<Color> _indexed;

  /// A neutral dark theme for the spike; real themes come later.
  static final TermPalette dark = TermPalette(
    foreground: const Color(0xFFD4D4D4),
    background: const Color(0xFF16181D),
    cursor: const Color(0xFF7FDBCA),
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
