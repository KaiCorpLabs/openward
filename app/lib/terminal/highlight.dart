// Keyword highlighting: words and patterns (error, warning, ok, IP and MAC
// addresses, and the user's own) painted in a color of the terminal's
// palette. Only when painting: the program's output, the screen's text and
// the session log stay as they are.

import 'package:flutter/foundation.dart';

import 'frame.dart';

/// A word or pattern and the palette color it is painted in.
@immutable
class HighlightRule {
  const HighlightRule({
    required this.id,
    required this.pattern,
    required this.color,
    this.name = '',
    this.enabled = true,
    this.caseSensitive = false,
  });

  /// `error`, `warning`, `ok`, `ip` and `mac` are the app's own (their
  /// names are the app's words); the user's start with `custom:`.
  final String id;

  /// The user's name for one of their own; empty for the app's.
  final String name;

  /// A regular expression, as Dart reads it.
  final String pattern;

  /// One of the 16 palette colors (1 red, 2 green, 3 yellow, 4 blue,
  /// 5 magenta, 6 cyan; 8 more for the bright ones): it follows the scheme.
  final int color;
  final bool enabled;
  final bool caseSensitive;

  bool get builtIn => !id.startsWith('custom:');

  HighlightRule copyWith({
    String? name,
    String? pattern,
    int? color,
    bool? enabled,
    bool? caseSensitive,
  }) => HighlightRule(
    id: id,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    color: color ?? this.color,
    enabled: enabled ?? this.enabled,
    caseSensitive: caseSensitive ?? this.caseSensitive,
  );

  Map<String, Object> toJson() => {
    'id': id,
    if (name.isNotEmpty) 'name': name,
    'pattern': pattern,
    'color': color,
    'enabled': enabled,
    if (caseSensitive) 'case_sensitive': true,
  };

  static HighlightRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], pattern = json['pattern'], color = json['color'];
    if (id is! String || pattern is! String || color is! int) return null;
    if (color < 0 || color > 15) return null;
    return HighlightRule(
      id: id,
      name: json['name'] is String ? json['name'] as String : '',
      pattern: pattern,
      color: color,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      caseSensitive: json['case_sensitive'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HighlightRule &&
      other.id == id &&
      other.name == name &&
      other.pattern == pattern &&
      other.color == color &&
      other.enabled == enabled &&
      other.caseSensitive == caseSensitive;

  @override
  int get hashCode =>
      Object.hash(id, name, pattern, color, enabled, caseSensitive);

  /// Whether `pattern` reads as a regular expression that matches
  /// something: an empty match would color nothing and loop.
  static bool valid(String pattern) {
    if (pattern.trim().isEmpty) return false;
    try {
      return !RegExp(pattern).hasMatch('');
    } on FormatException {
      return false;
    }
  }
}

/// The app's rules, in the order they are tried: the first to match a
/// stretch of text colors it.
const defaultHighlights = [
  HighlightRule(
    id: 'error',
    pattern:
        r'\b(?:error|errors|err|failed|failure|fail|fatal|critical|denied|'
        r'refused|panic|exception|unreachable|down)\b',
    color: 1,
  ),
  HighlightRule(
    id: 'warning',
    pattern: r'\b(?:warning|warnings|warn|deprecated|timeout|timed out)\b',
    color: 3,
  ),
  HighlightRule(
    id: 'ok',
    pattern:
        r'\b(?:ok|success|successful|succeeded|passed|done|active|running|'
        r'up|enabled|connected)\b',
    color: 2,
  ),
  HighlightRule(
    id: 'ip',
    pattern:
        r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)'
        r'(?:/\d{1,2})?\b'
        r'|\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b'
        r'|\b(?:[0-9a-fA-F]{1,4}:){1,6}(?::[0-9a-fA-F]{1,4}){1,6}\b',
    color: 6,
    caseSensitive: true,
  ),
  HighlightRule(
    id: 'mac',
    pattern:
        r'\b[0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5}\b'
        r'|\b[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\b',
    color: 5,
    caseSensitive: true,
  ),
];

/// Applies rules to a row's spans: the stretches they match, where the
/// program left the default color, take the rule's.
class Highlighter {
  Highlighter(List<HighlightRule> rules)
    : _rules = [
        for (final r in rules)
          if (r.enabled && HighlightRule.valid(r.pattern))
            (RegExp(r.pattern, caseSensitive: r.caseSensitive), r.color),
      ];

  final List<(RegExp, int)> _rules;

  bool get isEmpty => _rules.isEmpty;

  /// The palette color as spans carry it (tag 1, named).
  static int wire(int color) => 0x01000000 | color;

  /// `spans` with the matched stretches split off and colored; the same
  /// list when nothing matches.
  List<Span> apply(List<Span> spans) {
    if (_rules.isEmpty || spans.isEmpty) return spans;
    // The row's text, and the column of each of its UTF-16 units.
    final text = StringBuffer();
    final colAt = <int>[];
    for (final s in spans) {
      if (s.attrs & Attr.hidden != 0) continue;
      final cells = _cells(s);
      if (cells == null) {
        // Shaped as a whole: one stretch at its column.
        text.write(s.text);
        colAt.addAll(List.filled(s.text.length, s.col));
        continue;
      }
      for (var i = 0; i < cells.length; i++) {
        text.write(cells[i].$1);
        colAt.addAll(List.filled(cells[i].$1.length, cells[i].$2));
      }
      // A gap between spans: no match runs across it.
      text.write('\u0000');
      colAt.add(-1);
    }
    final row = text.toString();
    // Columns (start inclusive, end exclusive) and their color.
    final hits = <(int, int, int)>[];
    final taken = List<bool>.filled(row.length, false);
    for (final (re, color) in _rules) {
      for (final m in re.allMatches(row)) {
        if (m.end <= m.start) continue;
        var free = true;
        for (var i = m.start; i < m.end; i++) {
          if (taken[i] || colAt[i] < 0) {
            free = false;
            break;
          }
        }
        if (!free) continue;
        for (var i = m.start; i < m.end; i++) {
          taken[i] = true;
        }
        hits.add((colAt[m.start], colAt[m.end - 1] + 1, color));
      }
    }
    if (hits.isEmpty) return spans;
    final out = <Span>[];
    for (final s in spans) {
      out.addAll(_split(s, hits));
    }
    return out;
  }

  /// Each cell's text and column, or null when the span does not split
  /// into one cluster per cell (a wide character, an emoji sequence).
  static List<(String, int)>? _cells(Span s) {
    final clusters = <String>[];
    final buf = StringBuffer();
    for (final rune in s.text.runes) {
      if (buf.isNotEmpty && !_combining(rune)) {
        clusters.add(buf.toString());
        buf.clear();
      }
      buf.writeCharCode(rune);
    }
    if (buf.isNotEmpty) clusters.add(buf.toString());
    if (clusters.length != s.width) return null;
    return [for (var i = 0; i < clusters.length; i++) (clusters[i], s.col + i)];
  }

  static bool _combining(int r) =>
      (r >= 0x0300 && r <= 0x036F) ||
      (r >= 0x1AB0 && r <= 0x1AFF) ||
      (r >= 0x1DC0 && r <= 0x1DFF) ||
      (r >= 0x20D0 && r <= 0x20FF) ||
      (r >= 0xFE00 && r <= 0xFE0F) ||
      r == 0x200D;

  static Iterable<Span> _split(Span s, List<(int, int, int)> hits) sync* {
    // The program's own colors, inverse or hidden text: as they are.
    if (s.fg >>> 24 != 0 || s.attrs & (Attr.inverse | Attr.hidden) != 0) {
      yield s;
      return;
    }
    final end = s.col + s.width;
    final inside = [
      for (final h in hits)
        if (h.$1 < end && h.$2 > s.col) h,
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (inside.isEmpty) {
      yield s;
      return;
    }
    final cells = _cells(s);
    if (cells == null) {
      // Not split: colored only when one rule takes all of it.
      final h = inside.first;
      yield h.$1 <= s.col && h.$2 >= end ? _with(s, s.col, s.text, h.$3) : s;
      return;
    }
    var at = s.col;
    String text(int from, int to) => [
      for (final c in cells)
        if (c.$2 >= from && c.$2 < to) c.$1,
    ].join();
    for (final (start, stop, color) in inside) {
      final a = start < s.col ? s.col : start;
      final b = stop > end ? end : stop;
      if (a > at) yield _plain(s, at, text(at, a));
      yield _with(s, a, text(a, b), color, width: b - a);
      at = b;
    }
    if (at < end) yield _plain(s, at, text(at, end));
  }

  static Span _plain(Span s, int col, String text) => Span(
    col: col,
    width: text.runes.where((r) => !_combining(r)).length,
    fg: s.fg,
    bg: s.bg,
    attrs: s.attrs,
    text: text,
  );

  static Span _with(Span s, int col, String text, int color, {int? width}) =>
      Span(
        col: col,
        width: width ?? s.width,
        fg: wire(color),
        bg: s.bg,
        attrs: s.attrs,
        text: text,
      );
}

Highlighter? _shared;
List<HighlightRule>? _sharedRules;

/// The highlighter for these settings, the same one while they last; null
/// when highlighting is off.
Highlighter? highlighterFor({
  required bool on,
  required List<HighlightRule> rules,
}) {
  if (!on) return null;
  if (_shared == null || !listEquals(_sharedRules, rules)) {
    _shared = Highlighter(rules);
    _sharedRules = rules;
  }
  return _shared!.isEmpty ? null : _shared;
}
