import 'dart:ui' as ui;

import 'metrics.dart';

/// Glyphs rendered once, in white, into a texture. Rows are then drawn with
/// one `drawRawAtlas` call that tints each glyph, instead of shaping text on
/// every frame.
///
/// Slots never move: the atlas only grows, so pictures recorded against an
/// older image stay valid.
final class GlyphAtlas {
  GlyphAtlas({required this.metrics, required this.devicePixelRatio});

  static const int bold = 1;
  static const int italic = 2;
  static const int _width = 1024;
  static const int _maxHeight = 4096;

  final CellMetrics metrics;

  /// Glyphs are rasterized at physical resolution and drawn scaled by
  /// `1 / devicePixelRatio`.
  final double devicePixelRatio;

  ui.Image? _image;
  ui.Image? get image => _image;
  int _height = 256;
  double _x = 0;
  double _y = 0;
  final _slots = <String, ui.Rect>{};
  final _pending = <(String, int, ui.Rect)>[];

  int get glyphCount => _slots.length;
  int get heightPx => _height;

  double get _slotHeight => (metrics.height * devicePixelRatio).ceilToDouble();
  double _slotWidth(int cells) =>
      (metrics.width * cells * devicePixelRatio).ceilToDouble();

  static String _key(String text, int style, int cells) => '$style$cells$text';

  /// Where the glyph lives in [image], once [flush] has run after [ensure].
  ui.Rect? slot(String text, int style, int cells) =>
      _slots[_key(text, style, cells)];

  /// Reserves a slot for the glyph. Returns false when the atlas is full and
  /// the caller must draw the text another way.
  bool ensure(String text, int style, int cells) {
    final key = _key(text, style, cells);
    if (_slots.containsKey(key)) return true;
    // One pixel of padding on each side keeps bilinear sampling inside.
    final w = _slotWidth(cells) + 2;
    final h = _slotHeight + 2;
    if (_x + w > _width) {
      _x = 0;
      _y += h;
    }
    while (_y + h > _height) {
      if (_height * 2 > _maxHeight) return false;
      _height *= 2;
    }
    final rect = ui.Rect.fromLTWH(_x + 1, _y + 1, w - 2, h - 2);
    _slots[key] = rect;
    _pending.add((text, style, rect));
    _x += w;
    return true;
  }

  /// Rasterizes pending glyphs into a new image (copying the old one).
  /// Returns true if the image changed.
  bool flush() {
    if (_pending.isEmpty) return false;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final old = _image;
    if (old != null) canvas.drawImage(old, ui.Offset.zero, ui.Paint());
    for (final (text, style, rect) in _pending) {
      final p = metrics.paragraph(
        text,
        color: const ui.Color(0xFFFFFFFF),
        bold: style & bold != 0,
        italic: style & italic != 0,
      );
      canvas
        ..save()
        ..clipRect(rect)
        ..translate(rect.left, rect.top)
        ..scale(devicePixelRatio)
        ..drawParagraph(p, ui.Offset.zero)
        ..restore();
      p.dispose();
    }
    _pending.clear();
    final picture = recorder.endRecording();
    _image = picture.toImageSync(_width, _height);
    picture.dispose();
    // Pictures recorded earlier keep their own reference to the old image.
    old?.dispose();
    return true;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}
