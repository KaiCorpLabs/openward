// Follows what is typed on a terminal's command line, to say at Enter what
// command was run. Only commands the screen shows are kept: what the
// terminal does not echo (a password) never is.

import '../terminal/keys.dart';

/// What the tracker reads from the screen.
abstract interface class LineScreen {
  /// The cursor's row on the live screen; null when it is not on view.
  int? get cursorRow;

  /// The screen from the start of `row` up to the cursor (rows run
  /// together, trailing spaces trimmed) and what follows the cursor on its
  /// row; null when the cursor is not on view or is above `row`.
  ({String text, String after})? typedFrom(int row);
}

/// The command line of one terminal, from the first key after a prompt to
/// Enter.
class LineTracker {
  /// Typing started on this line.
  bool _active = false;

  /// Keys other than text and Backspace (arrows, Tab, history): what the
  /// line holds is what the screen shows.
  bool _edited = false;

  /// The line cannot be followed (a search, a cleared screen, a pasted
  /// newline): nothing is kept.
  bool _lost = false;

  String _typed = '';
  int _row = 0;

  /// The screen before the first key, on the cursor's row: the prompt.
  String _prompt = '';

  /// What followed the cursor then (a prompt on the right).
  String _after = '';

  void _begin(LineScreen s) {
    if (_active) return;
    _active = true;
    final row = s.cursorRow;
    if (row == null) {
      _lost = true;
      return;
    }
    _row = row;
    final t = s.typedFrom(row);
    _prompt = t?.text ?? '';
    _after = t?.after ?? '';
  }

  /// What was typed on this line, for a suggestion: null once the line
  /// was edited (arrows, Tab) or lost, and where a secret is asked.
  String? get plainTyped =>
      _active && !_lost && !_edited && !_looksSecret(_prompt) ? _typed : null;

  /// Whether the screen shows the prompt and what was typed, the cursor
  /// at its end, and nothing new after it (a shell's own suggestion, the
  /// rest of a line): where a suggestion can go.
  bool showsTyped(LineScreen s) {
    if (!_active || _lost) return false;
    final t = s.typedFrom(_row);
    if (t == null || t.after != _after || !t.text.startsWith(_prompt)) {
      return false;
    }
    // The prompt was read without its last space; the screen's text
    // comes without the line's.
    return t.text.substring(_prompt.length).trimLeft() == _typed.trimRight();
  }

  void reset() {
    _active = false;
    _edited = false;
    _lost = false;
    _typed = '';
    _prompt = '';
    _after = '';
  }

  /// Text typed or pasted.
  void text(String t, LineScreen s) {
    _begin(s);
    if (t.contains('\n') || t.contains('\r')) {
      _lost = true;
      return;
    }
    _typed += t;
  }

  /// A key that is not text: Backspace, arrows, Ctrl and Alt chords…
  /// Enter is [enter].
  void key(int hid, int mods, String text, LineScreen s) {
    final chord = mods & (Mods.ctrl | Mods.alt | Mods.superKey);
    if (chord == 0 && text.isNotEmpty && !isControlText(text)) {
      return this.text(text, s);
    }
    if (hid == Hid.backspace && chord == 0) {
      _begin(s);
      if (_typed.isNotEmpty) {
        final runes = _typed.runes.toList()..removeLast();
        _typed = String.fromCharCodes(runes);
      }
      return;
    }
    if (mods & Mods.ctrl != 0 && hid >= Hid.a && hid < Hid.a + 26) {
      switch (String.fromCharCode(0x61 + hid - Hid.a)) {
        // Interrupt, end of input, suspend, abort: the line is gone.
        case 'c' || 'd' || 'z' || 'g':
          return reset();
        // Searching the shell's history, or clearing the screen.
        case 'r' || 's' || 'l' || 'o':
          _begin(s);
          _lost = true;
          return;
      }
    }
    _begin(s);
    _edited = true;
  }

  /// Enter: the command run, if it can be told and kept; then a new line.
  String? enter(LineScreen s, {required bool altScreen}) {
    final command = altScreen ? null : _command(s);
    reset();
    return command;
  }

  String? _command(LineScreen s) {
    if (!_active || _lost) return null;
    if (_looksSecret(_prompt)) return null;
    // The prompt where it was, or a few rows up if the screen scrolled.
    ({String text, String after})? line;
    for (var k = 0; k <= 3 && _row - k >= 0; k++) {
      final t = s.typedFrom(_row - k);
      if (t != null && t.text.startsWith(_prompt)) {
        line = (text: t.text.substring(_prompt.length).trim(), after: t.after);
        break;
      }
    }
    if (line == null) return null;
    final String command;
    if (!_edited) {
      // A space in front: the shells' way of saying "do not keep this".
      if (_typed.startsWith(' ')) return null;
      final typed = _typed.trim();
      // The screen shows what was typed, though maybe not its last keys
      // yet. A password does not show at all.
      if (line.text.isEmpty ||
          !typed.startsWith(line.text) ||
          typed.length - line.text.length > 2) {
        return null;
      }
      command = typed;
    } else {
      // Text after the cursor, other than a prompt on the right, is a
      // suggestion or the rest of a line edited in the middle: which, the
      // screen does not say.
      if (line.after.isNotEmpty && line.after != _after) return null;
      command = line.text;
    }
    if (command.isEmpty || command.length > 4000) return null;
    return command;
  }

  static const _secret = [
    'password',
    'passphrase',
    'passcode',
    'contraseña',
    'clave',
    'passwort',
    'mot de passe',
    'senha',
    'token',
    'secret',
    'otp',
    'verification',
    'código',
    'pin',
  ];

  /// A program asking for something secret: `[sudo] password for ana:`.
  /// A shell's prompt does not end in a colon, and the folder it names
  /// may have any of these words.
  static bool _looksSecret(String prompt) {
    final p = prompt.trimRight().toLowerCase();
    return p.endsWith(':') && _secret.any(p.contains);
  }
}
