import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/glyph_atlas.dart';
import 'package:openward/terminal/metrics.dart';

void main() {
  GlyphAtlas atlas() =>
      GlyphAtlas(metrics: CellMetrics.measure(), devicePixelRatio: 2);

  test('a glyph gets one slot, by text, style and width', () {
    final a = atlas();
    expect(a.ensure('a', 0, 1), isTrue);
    expect(a.ensure('a', 0, 1), isTrue);
    expect(a.glyphCount, 1);
    a.ensure('a', GlyphAtlas.bold, 1);
    a.ensure('a', 0, 2);
    expect(a.glyphCount, 3);
    expect(a.slot('a', 0, 1), isNot(a.slot('a', GlyphAtlas.bold, 1)));
    expect(a.slot('b', 0, 1), isNull);
    a.dispose();
  });

  test('slots never move while it grows, and it says when it is full', () {
    final a = atlas();
    a.ensure('first', 0, 1);
    final first = a.slot('first', 0, 1);
    expect(a.flush(), isTrue);
    expect(a.flush(), isFalse, reason: 'nothing new');
    final firstImage = a.image!;
    final startHeight = a.heightPx;

    var n = 0;
    while (a.ensure('g$n', 0, 1)) {
      n++;
      expect(n, lessThan(1 << 20), reason: 'it never filled');
    }
    expect(a.heightPx, greaterThan(startHeight));
    expect(a.heightPx, lessThanOrEqualTo(4096));
    expect(a.slot('first', 0, 1), first);
    // Full: what was there stays, the glyph that did not fit has no slot.
    expect(a.slot('g$n', 0, 1), isNull);
    expect(a.glyphCount, n + 1);
    expect(a.flush(), isTrue);
    expect(a.image, isNot(same(firstImage)));
    expect(a.image!.height, a.heightPx);
    a.dispose();
    expect(a.image, isNull);
  });
}
