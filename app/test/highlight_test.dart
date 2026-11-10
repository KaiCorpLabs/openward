import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/frame.dart';
import 'package:openward/terminal/highlight.dart';

/// A row of plain text in the default colors.
List<Span> row(String text, {int col = 0, int fg = 0}) => [
  Span(col: col, width: text.length, fg: fg, bg: 0, attrs: 0, text: text),
];

/// What each colored stretch says, with its color.
List<(String, int)> colored(List<Span> spans) => [
  for (final s in spans)
    if (s.fg != 0) (s.text, s.fg & 0xFF),
];

void main() {
  final h = Highlighter(defaultHighlights);

  test('words and addresses take their color; the rest stays', () {
    final out = h.apply(row('ERROR: connect to 10.0.9.14 failed, retry ok'));
    expect(colored(out), [
      ('ERROR', 1),
      ('10.0.9.14', 6),
      ('failed', 1),
      ('ok', 2),
    ]);
    // Every cell is still there, in its place.
    expect(
      out.map((s) => s.text).join(),
      'ERROR: connect to 10.0.9.14 failed, retry ok',
    );
    var at = 0;
    for (final s in out) {
      expect(s.col, at);
      at += s.width;
    }
  });

  test('addresses: IPv4 with its mask, IPv6, MAC; not times or versions', () {
    List<String> found(String text) =>
        colored(h.apply(row(text))).map((c) => c.$1).toList();
    expect(found('route 192.168.1.0/24 via fe80::1'), [
      '192.168.1.0/24',
      'fe80::1',
    ]);
    expect(found('2001:db8::8a2e:370:7334'), ['2001:db8::8a2e:370:7334']);
    expect(found('link/ether 52:54:00:12:34:56 brd'), ['52:54:00:12:34:56']);
    expect(found('Cisco 0011.2233.4455'), ['0011.2233.4455']);
    expect(found('at 12:30:45 version 1.2.3 port 999.1.1.1'), isEmpty);
  });

  test("the program's own colors win", () {
    // ls paints this red itself: left as it is.
    final out = h.apply(row('error.log', fg: 0x01000004));
    expect(out.single.fg, 0x01000004);
  });

  test('rules off, broken or empty color nothing', () {
    final off = Highlighter([
      defaultHighlights.first.copyWith(enabled: false),
      const HighlightRule(id: 'custom:a', pattern: '(', color: 3),
      const HighlightRule(id: 'custom:b', pattern: 'x*', color: 3),
    ]);
    expect(off.isEmpty, isTrue);
    final spans = row('error');
    expect(identical(off.apply(spans), spans), isTrue);
    expect(HighlightRule.valid(r'\bretry\b'), isTrue);
    expect(HighlightRule.valid('x*'), isFalse);
    expect(HighlightRule.valid('['), isFalse);
  });

  test('a match does not run from one span into the next', () {
    final spans = [
      const Span(col: 0, width: 3, fg: 0, bg: 0, attrs: 0, text: 'err'),
      const Span(col: 5, width: 2, fg: 0, bg: 0, attrs: 0, text: 'or'),
    ];
    expect(colored(h.apply(spans)), [('err', 1)]);
  });

  test('wide characters keep their cells', () {
    final spans = [
      const Span(col: 0, width: 2, fg: 0, bg: 0, attrs: 0, text: '日'),
      const Span(col: 2, width: 6, fg: 0, bg: 0, attrs: 0, text: ' done '),
    ];
    final out = h.apply(spans);
    expect(colored(out), [('done', 2)]);
    expect(out.first.width, 2);
    expect(out.last.col + out.last.width, 8);
  });

  test('one highlighter while the rules stay the same', () {
    final a = highlighterFor(on: true, rules: defaultHighlights);
    final b = highlighterFor(on: true, rules: [...defaultHighlights]);
    expect(identical(a, b), isTrue);
    expect(highlighterFor(on: false, rules: defaultHighlights), isNull);
  });
}
