import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/visible_text.dart';

void main() {
  /// What a terminal would obey without showing, shown before it is sent.
  test('a paste with what does not show, made visible', () {
    expect(visibleForm('a'.codeUnitAt(0)), isNull);
    expect(visibleForm(0x0A), isNull, reason: 'a line break is text');
    expect(visibleForm(0x09), isNull, reason: 'so is a tab');
    expect(visibleForm(0x1B), '␛');
    expect(visibleForm(0x7F), '␡');
    expect(visibleForm(0x9B), '⟨U+009B⟩', reason: 'C1: an escape in one byte');
    expect(visibleForm(0x202E), '⟨RLO⟩', reason: 'it turns the text around');
    expect(visibleForm(0x200B), '⟨ZWSP⟩');

    // With RLO, «txt.exe» reads as «exe.txt».
    const sneaky = 'echo hi\u001b[2Jls\u202Etxt.exe';
    expect(hasHidden(sneaky), isTrue);
    expect(hasHidden('echo hi\nls -la\n'), isFalse);
    var told = false;
    final span = visibleText(
      sneaky,
      style: const TextStyle(),
      mark: const TextStyle(fontWeight: FontWeight.w700),
      hidden: (h) => told = h,
    );
    expect(told, isTrue);
    expect(span.toPlainText(), 'echo hi␛[2Jls⟨RLO⟩txt.exe');
    final marked = [
      for (final s in span.children!.cast<TextSpan>())
        if (s.style?.fontWeight == FontWeight.w700) s.text,
    ];
    expect(marked, ['␛', '⟨RLO⟩']);
  });
}
