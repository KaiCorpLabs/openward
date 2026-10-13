import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'frame.dart';
import 'palette.dart';

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
}

/// Turns damage frames into one cached [ui.Picture] per visible row, so a
/// frame only re-records the rows that changed.
class TerminalRenderer extends ChangeNotifier {
  TerminalRenderer({required this.metrics, required this.palette});

  final CellMetrics metrics;
  final TermPalette palette;

  int cols = 0;
  int rows = 0;
  int displayOffset = 0;
  TermCursor? cursor;
  List<ui.Picture?> _rows = [];
  final Paint _paint = Paint();

  /// Applies a frame and returns how long recording took, in microseconds.
  int apply(TermFrame frame) {
    final sw = Stopwatch()..start();
    if (frame.cols != cols || frame.rows != rows) {
      _disposeRows();
      cols = frame.cols;
      rows = frame.rows;
      _rows = List<ui.Picture?>.filled(rows, null);
    } else if (frame.full) {
      _disposeRows();
    }
    for (final line in frame.lines) {
      if (line.index >= rows) continue;
      _rows[line.index]?.dispose();
      _rows[line.index] = line.spans.isEmpty ? null : _record(line.spans);
    }
    cursor = frame.cursor;
    displayOffset = frame.displayOffset;
    notifyListeners();
    return sw.elapsedMicroseconds;
  }

  ui.Picture _record(List<Span> spans) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cw = metrics.width;
    final ch = metrics.height;
    for (final s in spans) {
      var fg = palette.resolve(s.fg, foreground: true);
      var bg = palette.resolve(s.bg, foreground: false);
      if (s.attrs & Attr.inverse != 0) {
        final t = fg;
        fg = bg;
        bg = t;
      }
      if (bg != palette.background) {
        canvas.drawRect(
          Rect.fromLTWH(s.col * cw, 0, s.width * cw, ch),
          _paint..color = bg,
        );
      }
      if (s.attrs & Attr.hidden != 0) continue;
      if (s.attrs & Attr.dim != 0) fg = fg.withValues(alpha: 0.6);
      final decorations = <ui.TextDecoration>[
        if (s.attrs & Attr.anyUnderline != 0) ui.TextDecoration.underline,
        if (s.attrs & Attr.strikeout != 0) ui.TextDecoration.lineThrough,
      ];
      final builder = ui.ParagraphBuilder(metrics.paragraphStyle)
        ..pushStyle(
          ui.TextStyle(
            color: fg,
            fontFamily: metrics.fontFamily,
            fontFamilyFallback: metrics.fallback,
            fontSize: metrics.fontSize,
            fontWeight: s.attrs & Attr.bold != 0
                ? FontWeight.w700
                : FontWeight.w400,
            fontStyle: s.attrs & Attr.italic != 0
                ? FontStyle.italic
                : FontStyle.normal,
            decoration: decorations.isEmpty
                ? null
                : ui.TextDecoration.combine(decorations),
            decorationColor: fg,
          ),
        )
        ..addText(s.text);
      final p = builder.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(p, Offset(s.col * cw, 0));
      p.dispose();
    }
    return recorder.endRecording();
  }

  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _paint..color = palette.background);
    final ch = metrics.height;
    for (var i = 0; i < _rows.length; i++) {
      final picture = _rows[i];
      if (picture == null) continue;
      canvas
        ..save()
        ..translate(0, i * ch)
        ..drawPicture(picture)
        ..restore();
    }
    final c = cursor;
    if (c != null && c.visible && displayOffset == 0) {
      final cw = metrics.width;
      final rect = Rect.fromLTWH(c.col * cw, c.row * ch, cw, ch);
      final paint = _paint..color = palette.cursor;
      switch (c.shape) {
        case CursorShape.block:
          canvas.drawRect(
            rect,
            paint..color = palette.cursor.withValues(alpha: 0.7),
          );
        case CursorShape.hollowBlock:
          canvas.drawRect(
            rect.deflate(0.5),
            Paint()
              ..color = palette.cursor
              ..style = PaintingStyle.stroke,
          );
        case CursorShape.underline:
          canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.bottom - 2, cw, 2),
            paint,
          );
        case CursorShape.beam:
          canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, 2, ch), paint);
      }
    }
  }

  void _disposeRows() {
    for (var i = 0; i < _rows.length; i++) {
      _rows[i]?.dispose();
      _rows[i] = null;
    }
  }

  @override
  void dispose() {
    _disposeRows();
    super.dispose();
  }
}

/// Paints a [TerminalRenderer] at its natural size, scaled down to fit.
class TerminalView extends StatelessWidget {
  const TerminalView({
    super.key,
    required this.renderer,
    required this.cols,
    required this.rows,
  });

  final TerminalRenderer renderer;
  final int cols;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final m = renderer.metrics;
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: math.max(1, cols) * m.width,
        height: math.max(1, rows) * m.height,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _TerminalPainter(renderer),
            isComplex: true,
            willChange: true,
          ),
        ),
      ),
    );
  }
}

class _TerminalPainter extends CustomPainter {
  _TerminalPainter(this.renderer) : super(repaint: renderer);

  final TerminalRenderer renderer;

  @override
  void paint(Canvas canvas, Size size) => renderer.paint(canvas, size);

  @override
  bool shouldRepaint(_TerminalPainter oldDelegate) =>
      oldDelegate.renderer != renderer;
}
