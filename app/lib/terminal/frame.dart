/// Decoder for damage frames v1, the format the Rust core sends to the UI.
///
/// The reference definition lives in `core/crates/openward-term/src/frame.rs`;
/// `test/frame_test.dart` checks this decoder against frames encoded there.
library;

import 'dart:convert';
import 'dart:typed_data';

const int kFrameVersion = 1;
const int _flagFull = 1;

enum CursorShape { block, underline, beam, hollowBlock }

/// Text attribute bits in [Span.attrs].
abstract final class Attr {
  static const int bold = 1 << 0;
  static const int dim = 1 << 1;
  static const int italic = 1 << 2;
  static const int underline = 1 << 3;
  static const int doubleUnderline = 1 << 4;
  static const int undercurl = 1 << 5;
  static const int dottedUnderline = 1 << 6;
  static const int dashedUnderline = 1 << 7;
  static const int inverse = 1 << 8;
  static const int hidden = 1 << 9;
  static const int strikeout = 1 << 10;

  static const int anyUnderline =
      underline |
      doubleUnderline |
      undercurl |
      dottedUnderline |
      dashedUnderline;
}

/// Cells sharing one style. Either single-width cells or exactly one wide
/// cell, so the renderer can place it at `col * cellWidth` without shaping
/// across spans.
final class Span {
  const Span({
    required this.col,
    required this.width,
    required this.fg,
    required this.bg,
    required this.attrs,
    required this.text,
  });

  final int col;
  final int width;

  /// Colors on the wire: tag in the high byte (0 default, 1 named, 2 indexed,
  /// 3 RGB), resolved against the active theme by `TermPalette`.
  final int fg;
  final int bg;
  final int attrs;
  final String text;
}

/// A row to repaint from scratch: clear it, then paint its spans.
final class RowUpdate {
  const RowUpdate(this.index, this.spans);

  final int index;
  final List<Span> spans;
}

final class TermCursor {
  const TermCursor({
    required this.row,
    required this.col,
    required this.shape,
    required this.visible,
  });

  final int row;
  final int col;
  final CursorShape shape;
  final bool visible;
}

final class TermFrame {
  const TermFrame({
    required this.full,
    required this.cols,
    required this.rows,
    required this.cursor,
    required this.displayOffset,
    required this.lines,
  });

  /// When true, rows not listed in [lines] must be cleared.
  final bool full;
  final int cols;
  final int rows;
  final TermCursor cursor;
  final int displayOffset;
  final List<RowUpdate> lines;
}

class FrameFormatException implements Exception {
  const FrameFormatException(this.message);

  final String message;

  @override
  String toString() => 'FrameFormatException: $message';
}

TermFrame decodeFrame(Uint8List bytes) {
  final r = _Reader(bytes);
  final version = r.u8();
  if (version != kFrameVersion) {
    throw FrameFormatException('unsupported frame version $version');
  }
  final flags = r.u8();
  final cols = r.u16();
  final rows = r.u16();
  final cursorRow = r.u16();
  final cursorCol = r.u16();
  final shapeCode = r.u8();
  if (shapeCode >= CursorShape.values.length) {
    throw FrameFormatException('invalid cursor shape $shapeCode');
  }
  final cursor = TermCursor(
    row: cursorRow,
    col: cursorCol,
    shape: CursorShape.values[shapeCode],
    visible: r.u8() != 0,
  );
  final displayOffset = r.u32();
  final rowCount = r.u16();
  final lines = <RowUpdate>[];
  for (var i = 0; i < rowCount; i++) {
    final index = r.u16();
    final spanCount = r.u16();
    final spans = <Span>[];
    for (var j = 0; j < spanCount; j++) {
      final col = r.u16();
      final width = r.u16();
      final fg = r.u32();
      final bg = r.u32();
      final attrs = r.u16();
      final text = utf8.decode(r.take(r.u16()), allowMalformed: true);
      spans.add(
        Span(col: col, width: width, fg: fg, bg: bg, attrs: attrs, text: text),
      );
    }
    lines.add(RowUpdate(index, spans));
  }
  if (r.pos != bytes.length) {
    throw const FrameFormatException('trailing bytes after frame');
  }
  return TermFrame(
    full: flags & _flagFull != 0,
    cols: cols,
    rows: rows,
    cursor: cursor,
    displayOffset: displayOffset,
    lines: lines,
  );
}

final class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  int pos = 0;

  void _need(int n) {
    if (pos + n > bytes.length) {
      throw const FrameFormatException('truncated frame');
    }
  }

  int u8() {
    _need(1);
    return data.getUint8(pos++);
  }

  int u16() {
    _need(2);
    final v = data.getUint16(pos, Endian.little);
    pos += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = data.getUint32(pos, Endian.little);
    pos += 4;
    return v;
  }

  Uint8List take(int n) {
    _need(n);
    final v = Uint8List.sublistView(bytes, pos, pos + n);
    pos += n;
    return v;
  }
}
