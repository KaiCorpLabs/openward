// Space, text sizes, corners, shadows and the interface's timing come from
// the tokens in `lib/ui`: a literal elsewhere is one more place a theme
// (square corners, say) does not reach, and one more size that drifts.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _edgeInsets = RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB)\(');
final _atom = RegExp(r'(\(|,\s*|:\s*|\?\s*)(\d+(?:\.\d+)?)(?=\s*[,):])');

final _rules = <String, RegExp>{
  'a font size (OwText)': RegExp(r'fontSize: \d'),
  'a corner (OwShape)': RegExp(r'(BorderRadius|Radius)\.circular\(\d'),
  'a shadow (OwElevation)': RegExp(r'BoxShadow\('),
  'a duration of the interface (OwMotion)': RegExp(
    r'(waitDuration|transitionDuration|reverseDuration|duration):\s*'
    r'(const\s+)?Duration\(milliseconds:',
  ),
};

/// The arguments of the call whose `(` is at `open`.
String _args(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '(') depth++;
    if (text[i] == ')' && --depth == 0) return text.substring(open, i + 1);
  }
  return text.substring(open);
}

void main() {
  test('no design literals outside lib/ui', () {
    final found = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) =>
              !f.path.startsWith('lib/ui/') && !f.path.startsWith('lib/src/'),
        )
        .where((f) => !f.path.startsWith('lib/l10n/app_localizations'));
    for (final file in files) {
      final text = file.readAsStringSync();
      int lineOf(int offset) =>
          '\n'.allMatches(text.substring(0, offset)).length + 1;
      for (final MapEntry(key: what, value: rule) in _rules.entries) {
        for (final m in rule.allMatches(text)) {
          found.add('${file.path}:${lineOf(m.start)}: $what');
        }
      }
      for (final m in _edgeInsets.allMatches(text)) {
        final args = _args(text, m.end - 1);
        for (final a in _atom.allMatches(args)) {
          if (double.parse(a.group(2)!) != 0) {
            found.add('${file.path}:${lineOf(m.start)}: a space (OwSpace)');
            break;
          }
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
