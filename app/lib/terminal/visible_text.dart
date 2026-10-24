// What a paste really holds, before it is sent: control characters, the
// ones that turn text around (bidi) and the ones of no width, which a
// terminal would obey without showing them, made visible.

import 'package:flutter/painting.dart';

/// The names of the invisible characters that change what text says.
const _named = {
  0x061C: 'ALM',
  0x200B: 'ZWSP',
  0x200C: 'ZWNJ',
  0x200D: 'ZWJ',
  0x200E: 'LRM',
  0x200F: 'RLM',
  0x202A: 'LRE',
  0x202B: 'RLE',
  0x202C: 'PDF',
  0x202D: 'LRO',
  0x202E: 'RLO',
  0x2060: 'WJ',
  0x2066: 'LRI',
  0x2067: 'RLI',
  0x2068: 'FSI',
  0x2069: 'PDI',
  0xFEFF: 'BOM',
};

/// How `rune` shows when it would not: a control picture (␛) or its name
/// (⟨RLO⟩); null for what shows as itself. Line breaks and tabs are text.
String? visibleForm(int rune) {
  if (rune == 0x0A || rune == 0x09) return null;
  if (rune < 0x20) return String.fromCharCode(0x2400 + rune);
  if (rune == 0x7F) return '␡';
  if (rune >= 0x80 && rune < 0xA0) {
    return '⟨U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}⟩';
  }
  final name = _named[rune];
  return name == null ? null : '⟨$name⟩';
}

/// `text` with what would not show marked in `mark`. `hidden` is told
/// whether there was any.
TextSpan visibleText(
  String text, {
  required TextStyle style,
  required TextStyle mark,
  void Function(bool hidden)? hidden,
}) {
  final spans = <TextSpan>[];
  final plain = StringBuffer();
  var any = false;
  void flush() {
    if (plain.isEmpty) return;
    spans.add(TextSpan(text: plain.toString()));
    plain.clear();
  }

  for (final rune in text.runes) {
    final shown = visibleForm(rune);
    if (shown == null) {
      plain.writeCharCode(rune);
      continue;
    }
    any = true;
    flush();
    spans.add(TextSpan(text: shown, style: mark));
  }
  flush();
  hidden?.call(any);
  return TextSpan(style: style, children: spans);
}

/// Whether `text` holds anything [visibleText] would mark.
bool hasHidden(String text) => text.runes.any((r) => visibleForm(r) != null);
