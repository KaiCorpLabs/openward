// Box drawing geometry: every character paints, and lines reach the cell
// edges they should, so neighbouring cells join without gaps.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:render_harness/term/box_drawing.dart';

const _w = 16;
const _h = 32;

Future<ByteData> _render(int rune, {double dpr = 2}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  BoxDrawing.paint(
    canvas,
    rune,
    const ui.Rect.fromLTWH(0, 0, _w * 1.0, _h * 1.0),
    dpr,
    const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(_w, _h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

bool _ink(ByteData d, int x, int y) => d.getUint8((y * _w + x) * 4 + 3) > 128;

void main() {
  test('every handled character paints something', () async {
    final runes = [
      for (var r = 0x2500; r <= 0x259F; r++) r,
      for (var r = 0xE0B0; r <= 0xE0B3; r++) r,
    ];
    for (final r in runes) {
      expect(BoxDrawing.handles(r), isTrue);
      final d = await _render(r);
      var any = false;
      for (var y = 0; y < _h && !any; y++) {
        for (var x = 0; x < _w && !any; x++) {
          any = d.getUint8((y * _w + x) * 4 + 3) > 0;
        }
      }
      expect(any, isTrue, reason: 'U+${r.toRadixString(16)} drew nothing');
    }
    expect(BoxDrawing.handles(0x24FF), isFalse);
    expect(BoxDrawing.handles(0x25A0), isFalse);
  });

  test('lines reach the edges they connect to', () async {
    // ─ joins left and right, │ top and bottom, ┼ all four, ╔ right and down.
    final cases = {
      0x2500: (left: true, right: true, top: false, bottom: false),
      0x2502: (left: false, right: false, top: true, bottom: true),
      0x253C: (left: true, right: true, top: true, bottom: true),
      0x2554: (left: false, right: true, top: false, bottom: true),
      0x2550: (left: true, right: true, top: false, bottom: false),
    };
    for (final MapEntry(key: r, value: e) in cases.entries) {
      final d = await _render(r);
      bool rowHasInk(int y) =>
          [for (var x = 0; x < _w; x++) _ink(d, x, y)].any((v) => v);
      bool colHasInk(int x) =>
          [for (var y = 0; y < _h; y++) _ink(d, x, y)].any((v) => v);
      final hex = 'U+${r.toRadixString(16)}';
      expect(colHasInk(0), e.left, reason: '$hex left edge');
      expect(colHasInk(_w - 1), e.right, reason: '$hex right edge');
      expect(rowHasInk(0), e.top, reason: '$hex top edge');
      expect(rowHasInk(_h - 1), e.bottom, reason: '$hex bottom edge');
    }
  });

  test('full block fills the cell and half blocks fill half', () async {
    final full = await _render(0x2588);
    final upper = await _render(0x2580);
    var fullInk = 0, upperInk = 0, upperTop = 0;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        if (_ink(full, x, y)) fullInk++;
        if (_ink(upper, x, y)) {
          upperInk++;
          if (y < _h / 2) upperTop++;
        }
      }
    }
    expect(fullInk, _w * _h);
    expect(upperInk, _w * _h ~/ 2);
    expect(upperTop, upperInk);
  });
}
