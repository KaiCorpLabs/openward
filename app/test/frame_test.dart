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
}
