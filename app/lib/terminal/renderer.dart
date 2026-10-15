import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'frame.dart';
import 'glyph_atlas.dart';
import 'metrics.dart';
import 'palette.dart';

export 'metrics.dart' show CellMetrics;

/// Turns damage frames into one cached [ui.Picture] per visible row, so a
/// frame only re-records the rows that changed. Glyphs come from an atlas
/// and each row is one `drawRawAtlas`; paragraphs only for emoji and text
/// the atlas cannot place (spike S1.4, docs/spikes/S1-terminal-resultados.md).
class TerminalRenderer extends ChangeNotifier {
  TerminalRenderer({
    required this.metrics,
    required this.palette,
    required this.devicePixelRatio,
    this.minimumContrast = 1,
  }) : _atlas = GlyphAtlas(
         metrics: metrics,
         devicePixelRatio: devicePixelRatio,
       );

  final CellMetrics metrics;
  final TermPalette palette;
  final double devicePixelRatio;

  /// Text is made to reach this contrast on its background; 1 is off.
  final double minimumContrast;
  final Map<(int, int), Color> _contrasted = {};
  final GlyphAtlas? _atlas;

  int cols = 0;
  int rows = 0;
  int displayOffset = 0;
  TermCursor? cursor;

  /// Selected columns per visible row (both inclusive), painted over the
  /// text.
  List<({int row, int start, int end})> selection = const [];

  /// The find bar's matches on screen; the selected one stands out.
  List<({int row, int start, int end, bool selected})> search = const [];

  /// The link under the pointer, underlined while it can be opened.
  ({int row, int start, int end})? link;

  /// Off during the dark half of a blink.
  bool cursorOn = true;
  List<ui.Picture?> _rows = [];
  final Paint _paint = Paint();
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;

  /// Spans drawn with a paragraph in atlas mode (emoji, odd clusters).
  int paragraphFallbacks = 0;
  int get atlasGlyphs => _atlas?.glyphCount ?? 0;
  int get atlasHeightPx => _atlas?.heightPx ?? 0;

  // Reused buffers for drawRawAtlas.
  final _transforms = <double>[];
  final _rects = <double>[];
  final _colors = <int>[];

  void setSelection(List<({int row, int start, int end})> rows) {
    if (rows.isEmpty && selection.isEmpty) return;
    selection = rows;
    notifyListeners();
  }

  void setSearch(List<({int row, int start, int end, bool selected})> hits) {
    if (hits.isEmpty && search.isEmpty) return;
    search = hits;
    notifyListeners();
  }

  void setLink(({int row, int start, int end})? value) {
    if (value == link) return;
    link = value;
    notifyListeners();
  }

  void setCursorOn(bool on) {
    if (on == cursorOn) return;
    cursorOn = on;
    notifyListeners();
  }

  /// `fg`, or the nearest color that reads on `bg` (minimum contrast).
  Color _readable(Color fg, Color bg) {
    if (minimumContrast <= 1) return fg;
    return _contrasted.putIfAbsent((
      fg.toARGB32(),
      bg.toARGB32(),
    ), () => TermPalette.ensureContrast(fg, bg, minimumContrast));
  }

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
    final atlas = _atlas;
    if (atlas != null) {
      // Reserve every glyph first so the atlas is rasterized once per frame.
      for (final line in frame.lines) {
        for (final s in line.spans) {
          final glyphs = _atlasGlyphs(s);
          if (glyphs == null) continue;
          for (final g in glyphs.clusters) {
            atlas.ensure(g, glyphs.style, glyphs.cells);
          }
        }
      }
      atlas.flush();
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
    final atlas = _atlas;
    final image = atlas?.image;
    _transforms.clear();
    _rects.clear();
    _colors.clear();
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
      fg = _readable(fg, bg);
      if (s.attrs & Attr.dim != 0) fg = fg.withValues(alpha: 0.6);

      final glyphs = atlas == null ? null : _atlasGlyphs(s);
      final slots = glyphs == null || image == null
          ? null
          : [
              for (final g in glyphs.clusters)
                atlas!.slot(g, glyphs.style, glyphs.cells),
            ];
      if (glyphs == null || slots == null || slots.contains(null)) {
        _drawParagraph(canvas, s, fg);
        if (atlas != null) paragraphFallbacks++;
        continue;
      }
      final scale = 1 / atlas!.devicePixelRatio;
      final argb = fg.toARGB32();
      var x = s.col * cw;
      for (final slot in slots) {
        _transforms.addAll([scale, 0, x, 0]);
        _rects.addAll([slot!.left, slot.top, slot.right, slot.bottom]);
        _colors.add(argb);
        x += glyphs.cells * cw;
      }
      if (s.attrs & Attr.anyUnderline != 0) {
        canvas.drawRect(
          Rect.fromLTWH(s.col * cw, ch - 2, s.width * cw, 1),
          _paint..color = fg,
        );
      }
      if (s.attrs & Attr.strikeout != 0) {
        canvas.drawRect(
          Rect.fromLTWH(s.col * cw, ch / 2, s.width * cw, 1),
          _paint..color = fg,
        );
      }
    }
    if (_transforms.isNotEmpty) {
      canvas.drawRawAtlas(
        image!,
        Float32List.fromList(_transforms),
        Float32List.fromList(_rects),
        Int32List.fromList(_colors),
        BlendMode.modulate,
        null,
        _atlasPaint,
      );
    }
    return recorder.endRecording();
  }

  void _drawParagraph(Canvas canvas, Span s, Color fg) {
    final decorations = <ui.TextDecoration>[
      if (s.attrs & Attr.anyUnderline != 0) ui.TextDecoration.underline,
      if (s.attrs & Attr.strikeout != 0) ui.TextDecoration.lineThrough,
    ];
    final p = metrics.paragraph(
      s.text,
      color: fg,
      bold: s.attrs & Attr.bold != 0,
      italic: s.attrs & Attr.italic != 0,
      decoration: decorations.isEmpty
          ? null
          : ui.TextDecoration.combine(decorations),
    );
    canvas.drawParagraph(p, Offset(s.col * cw, 0));
    p.dispose();
  }

  double get cw => metrics.width;

  /// How a span maps onto atlas glyphs, or null if it must be shaped as a
  /// paragraph (color emoji, or clusters that do not match the cell count).
  static ({List<String> clusters, int style, int cells})? _atlasGlyphs(Span s) {
    if (s.attrs & Attr.hidden != 0 || _hasColorGlyph(s.text)) return null;
    final clusters = _clusters(s.text);
    final int cells;
    if (s.width > 1 && clusters.length == 1) {
      cells = s.width;
    } else if (clusters.length == s.width) {
      cells = 1;
    } else {
      return null;
    }
    final style =
        (s.attrs & Attr.bold != 0 ? GlyphAtlas.bold : 0) |
        (s.attrs & Attr.italic != 0 ? GlyphAtlas.italic : 0);
    return (clusters: clusters, style: style, cells: cells);
  }

  /// Splits text into one string per cell: a base character plus any
  /// combining marks, joiners or variation selectors that follow it.
  static List<String> _clusters(String text) {
    final out = <String>[];
    final buf = StringBuffer();
    for (final rune in text.runes) {
      if (buf.isNotEmpty && !_isCombining(rune)) {
        out.add(buf.toString());
        buf.clear();
      }
      buf.writeCharCode(rune);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  static bool _isCombining(int r) =>
      (r >= 0x0300 && r <= 0x036F) ||
      (r >= 0x1AB0 && r <= 0x1AFF) ||
      (r >= 0x1DC0 && r <= 0x1DFF) ||
      (r >= 0x20D0 && r <= 0x20FF) ||
      (r >= 0xFE00 && r <= 0xFE0F) ||
      (r >= 0xFE20 && r <= 0xFE2F) ||
      r == 0x200D;

  /// Emoji and other color glyphs cannot be tinted from a white atlas.
  static bool _hasColorGlyph(String text) {
    for (final r in text.runes) {
      if (r >= 0x1F000 ||
          (r >= 0x2600 && r <= 0x27BF) ||
          r == 0xFE0F ||
          r == 0x200D) {
        return true;
      }
    }
    return false;
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
    if (search.isNotEmpty) {
      // Amber, readable over light and dark backgrounds alike.
      final other = Paint()..color = const Color(0x59FFC94D);
      final chosen = Paint()..color = const Color(0x99FF9F1A);
      final ring = Paint()
        ..color = const Color(0xFFFF9F1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final h in search) {
        final rect = Rect.fromLTWH(
          h.start * cw,
          h.row * ch,
          (h.end - h.start + 1) * cw,
          ch,
        );
        canvas.drawRect(rect, h.selected ? chosen : other);
        if (h.selected) canvas.drawRect(rect.deflate(0.75), ring);
      }
    }
    final l = link;
    if (l != null) {
      canvas.drawRect(
        Rect.fromLTWH(
          l.start * cw,
          (l.row + 1) * ch - 1.5,
          (l.end - l.start + 1) * cw,
          1.5,
        ),
        Paint()..color = palette.cursor,
      );
    }
    if (selection.isNotEmpty) {
      final paint = Paint()..color = palette.selection;
      for (final r in selection) {
        canvas.drawRect(
          Rect.fromLTWH(
            r.start * cw,
            r.row * ch,
            (r.end - r.start + 1) * cw,
            ch,
          ),
          paint,
        );
      }
    }
    final c = cursor;
    if (c != null && c.visible && cursorOn && displayOffset == 0) {
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

  /// The current screen as a PNG, at [pixelRatio] times its logical size.
  Future<Uint8List?> snapshotPng({double pixelRatio = 2}) async {
    final size = Size(
      math.max(1, cols) * metrics.width,
      math.max(1, rows) * metrics.height,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
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
    _atlas?.dispose();
    super.dispose();
  }
}

/// Paints a [TerminalRenderer] at its natural size: pointer positions map
/// to cells 1:1.
class TerminalGrid extends StatelessWidget {
  const TerminalGrid({
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
    return SizedBox(
      width: math.max(1, cols) * m.width,
      height: math.max(1, rows) * m.height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TerminalPainter(renderer),
          isComplex: true,
          willChange: true,
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
