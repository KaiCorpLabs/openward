import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

/// Monospace cell size for a font, measured once.
final class CellMetrics {
  CellMetrics._(
    this.fontFamily,
    this.fallback,
    this.fontSize,
    this.width,
    this.height,
    this.paragraphStyle,
    this._letterSpacing,
  );

  /// Cells are snapped to whole device pixels, as terminals do: glyphs and
  /// box drawing then land on the pixel grid instead of being resampled.
  factory CellMetrics.measure({
    double fontSize = 13,
    double lineHeight = 1.2,
    double devicePixelRatio = 1,
  }) {
    final families = Platform.isMacOS || Platform.isIOS
        ? const ['Menlo', 'Courier New']
        : Platform.isWindows
        ? const ['Consolas', 'Courier New']
        : Platform.isAndroid
        ? const ['monospace', 'Roboto Mono', 'Droid Sans Mono']
        : const ['DejaVu Sans Mono', 'Liberation Mono', 'monospace'];
    final style = ui.ParagraphStyle(
      fontFamily: families.first,
      fontSize: fontSize,
      height: lineHeight,
      strutStyle: ui.StrutStyle(
        fontFamily: families.first,
        fontFamilyFallback: families.skip(1).toList(),
        fontSize: fontSize,
        height: lineHeight,
        forceStrutHeight: true,
      ),
    );
    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          fontFamily: families.first,
          fontFamilyFallback: families.skip(1).toList(),
          fontSize: fontSize,
        ),
      )
      ..addText('W' * 64);
    final p = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final metrics = CellMetrics._(
      families.first,
      families.skip(1).toList(),
      fontSize,
      _snap(p.maxIntrinsicWidth / 64, devicePixelRatio),
      _snap(p.height, devicePixelRatio),
      style,
      // Paragraphs keep to the snapped grid: the font's own advance is a
      // fraction of a pixel off, which adds up along a line.
      _snap(p.maxIntrinsicWidth / 64, devicePixelRatio) -
          p.maxIntrinsicWidth / 64,
    );
    p.dispose();
    return metrics;
  }

  static double _snap(double logical, double dpr) =>
      math.max(1, (logical * dpr).round()) / dpr;

  final String fontFamily;
  final List<String> fallback;
  final double fontSize;
  final double width;
  final double height;
  final ui.ParagraphStyle paragraphStyle;
  final double _letterSpacing;

  /// A one-line paragraph in this font, laid out and ready to draw.
  ui.Paragraph paragraph(
    String text, {
    required ui.Color color,
    bool bold = false,
    bool italic = false,
    ui.TextDecoration? decoration,
  }) {
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          fontSize: fontSize,
          letterSpacing: _letterSpacing,
          fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
          fontStyle: italic ? ui.FontStyle.italic : ui.FontStyle.normal,
          decoration: decoration,
          decorationColor: color,
        ),
      )
      ..addText(text);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }
}
