import 'dart:io' show Platform;
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
  );

  factory CellMetrics.measure({double fontSize = 13, double lineHeight = 1.2}) {
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
      p.maxIntrinsicWidth / 64,
      p.height,
      style,
    );
    p.dispose();
    return metrics;
  }

  final String fontFamily;
  final List<String> fallback;
  final double fontSize;
  final double width;
  final double height;
  final ui.ParagraphStyle paragraphStyle;

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
