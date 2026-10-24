// Checks the Dart decoder against frames encoded by the Rust core.
// Fixtures come from the S1 bench: regenerate them in
// spikes/s1-terminal/render_harness/rust with
// `cargo run --example gen_fixtures -- ../../../../app/test/fixtures`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/frame.dart';

const _rustShapeNames = {
  CursorShape.block: 'Block',
  CursorShape.underline: 'Underline',
  CursorShape.beam: 'Beam',
  CursorShape.hollowBlock: 'HollowBlock',
};

Map<String, Object?> _asJson(TermFrame f) => {
  'full': f.full,
  'cols': f.cols,
  'rows': f.rows,
  'cursor': {
    'row': f.cursor.row,
    'col': f.cursor.col,
    'shape': _rustShapeNames[f.cursor.shape],
    'visible': f.cursor.visible,
  },
  'display_offset': f.displayOffset,
  'lines': [
    for (final l in f.lines)
      {
        'index': l.index,
        'spans': [
          for (final s in l.spans)
            {
              'col': s.col,
              'width': s.width,
              'fg': s.fg,
              'bg': s.bg,
              'attrs': s.attrs,
              'text': s.text,
            },
        ],
      },
  ],
};

void main() {
  for (final name in ['styled', 'wide', 'partial', 'scrolled']) {
    test('decodes the Rust-encoded "$name" frame', () {
      final bytes = File('test/fixtures/$name.bin').readAsBytesSync();
      final expected = jsonDecode(
        File('test/fixtures/$name.json').readAsStringSync(),
      );
      expect(_asJson(decodeFrame(bytes)), expected);
    });
  }

  test('rejects truncated frames', () {
    final bytes = File('test/fixtures/styled.bin').readAsBytesSync();
    expect(
      () => decodeFrame(Uint8List.sublistView(bytes, 0, bytes.length - 1)),
      throwsA(isA<FrameFormatException>()),
    );
  });

  test('rejects unknown versions', () {
    final bytes = Uint8List.fromList(
      File('test/fixtures/styled.bin').readAsBytesSync(),
    )..[0] = 9;
    expect(() => decodeFrame(bytes), throwsA(isA<FrameFormatException>()));
  });

  /// The span's text at the longest its u16 length allows (TM-2), and one
  /// whose length says less than it has: the rest is refused, not read as
  /// more spans.
  test('a span as long as its length allows, and one that lies', () {
    Uint8List frame(String text, {int? claimed}) {
      final b = BytesBuilder();
      void u8(int v) => b.addByte(v);
      void u16(int v) => b.add([v & 0xFF, v >> 8]);
      void u32(int v) =>
          b.add([for (var i = 0; i < 4; i++) v >> (8 * i) & 0xFF]);
      final bytes = utf8.encode(text);
      u8(kFrameVersion);
      u8(1); // full
      u16(300); // cols
      u16(1); // rows
      u16(0); // cursor row
      u16(0); // cursor col
      u8(0); // block
      u8(1); // visible
      u32(0); // display offset
      u16(1); // one row
      u16(0); // its index
      u16(1); // one span
      u16(0); // col
      u16(300); // width
      u32(0); // fg
      u32(0); // bg
      u16(0); // attrs
      u16(claimed ?? bytes.length);
      b.add(bytes);
      return b.takeBytes();
    }

    // Cells of an `e` and 64 marks of 4 bytes each (257 bytes), and as
    // many `x` as make 65535 bytes.
    final long = 'e${'\u{E0100}' * 64}' * 254 + 'x' * (65535 - 254 * 257);
    expect(utf8.encode(long).length, 65535);
    final decoded = decodeFrame(frame(long));
    expect(decoded.lines.single.spans.single.text, long);

    expect(
      () => decodeFrame(frame(long, claimed: (65535 + 1) & 0xFFFF)),
      throwsA(isA<FrameFormatException>()),
    );
  });
}
