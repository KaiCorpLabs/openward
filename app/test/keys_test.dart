import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/keys.dart';

void main() {
  test('keypad keys but Enter, functional keys, and the rest', () {
    // Keypad 1, *, ., =, and Enter (the encoder's).
    for (final id in [0x59, 0x55, 0x63, 0x67, 0x85]) {
      expect(isKeypadKey(0x00070000 | id), isTrue, reason: '$id');
    }
    expect(isKeypadKey(0x00070058), isFalse);
    expect(isKeypadKey(Hid.a), isFalse);
    // Another usage page is never one.
    expect(isKeypadKey(0x000C0059), isFalse);

    for (final hid in [
      Hid.enter,
      Hid.escape,
      Hid.backspace,
      Hid.tab,
      Hid.home,
      Hid.arrowUp,
      0x0007003A, // F1
      0x00070058, // keypad Enter
      0x00070073, // F24
    ]) {
      expect(isFunctionalKey(hid), isTrue, reason: hid.toRadixString(16));
    }
    expect(isFunctionalKey(Hid.a), isFalse);
    expect(isFunctionalKey(0x0007002C), isFalse, reason: 'space types');
    expect(isFunctionalKey(0x000C003A), isFalse);
  });

  test('the character a key stands for, and a letter\'s key', () {
    expect(unshiftedCodepoint(LogicalKeyboardKey.keyA), 'a'.codeUnitAt(0));
    expect(unshiftedCodepoint(LogicalKeyboardKey.digit1), '1'.codeUnitAt(0));
    expect(unshiftedCodepoint(LogicalKeyboardKey.arrowUp), 0);
    expect(unshiftedCodepoint(LogicalKeyboardKey.f1), 0);

    expect(hidForChar('a'), Hid.a);
    expect(hidForChar('Z'), Hid.a + 25);
    expect(hidForChar('1'), 0);
    expect(hidForChar('ñ'), 0);
    expect(hidForChar('ab'), 0);
  });

  test('control text: C0, DEL and Apple\'s function-key characters', () {
    expect(isControlText('\x1b[A'), isTrue);
    expect(isControlText('\x7f'), isTrue);
    expect(isControlText(String.fromCharCode(0xF700)), isTrue);
    expect(isControlText('héllo 世界'), isFalse);
    expect(isControlText(''), isFalse);
  });

  test('what the window keeps for itself', () {
    KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );
    final t = down(LogicalKeyboardKey.keyT);
    if (isApple) {
      expect(isAppShortcut(t, Mods.superKey), isTrue);
      expect(isAppShortcut(t, Mods.ctrl | Mods.shift), isFalse);
      expect(isAppShortcut(t, Mods.ctrl), isFalse);
      return;
    }
    expect(isAppShortcut(t, Mods.ctrl | Mods.shift), isTrue);
    // Ctrl+T, and Ctrl+Shift+Alt+T (AltGr on some layouts), are the
    // program's.
    expect(isAppShortcut(t, Mods.ctrl), isFalse);
    expect(isAppShortcut(t, Mods.ctrl | Mods.shift | Mods.alt), isFalse);
    expect(isAppShortcut(down(LogicalKeyboardKey.tab), Mods.ctrl), isTrue);
    expect(isAppShortcut(down(LogicalKeyboardKey.comma), Mods.ctrl), isTrue);
    expect(
      isAppShortcut(down(LogicalKeyboardKey.arrowLeft), Mods.ctrl | Mods.shift),
      isTrue,
    );
    expect(
      isAppShortcut(down(LogicalKeyboardKey.arrowLeft), Mods.ctrl),
      isFalse,
    );
    expect(isAppShortcut(down(LogicalKeyboardKey.equal), Mods.ctrl), isTrue);
    expect(isAppShortcut(down(LogicalKeyboardKey.keyC), Mods.ctrl), isFalse);
  });

  test('Ctrl and the left Alt with a digit go to a tab off Apple', () {
    const activator = TabDigitActivator(3);
    expect(activator.triggers, [LogicalKeyboardKey.digit3]);
    expect(activator.debugDescribeKeys(), 'Ctrl+Alt+3');
  });

  test('either profile on any system; the program first takes Ctrl keys', () {
    KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );
    addTearDown(() {
      macShortcuts = isApple;
      terminalKeysFirst = false;
    });
    final t = down(LogicalKeyboardKey.keyT);
    final tab = down(LogicalKeyboardKey.tab);
    macShortcuts = true;
    expect(isAppShortcut(t, Mods.superKey), isTrue);
    expect(isAppShortcut(t, Mods.ctrl | Mods.shift), isFalse);
    macShortcuts = false;
    expect(isAppShortcut(t, Mods.ctrl | Mods.shift), isTrue);
    expect(isAppShortcut(t, Mods.superKey), isFalse);
    expect(isAppShortcut(tab, Mods.ctrl), isTrue);
    terminalKeysFirst = true;
    // Ctrl alone goes to the program; Ctrl+Shift stays the window's.
    expect(isAppShortcut(tab, Mods.ctrl), isFalse);
    expect(isAppShortcut(down(LogicalKeyboardKey.equal), Mods.ctrl), isFalse);
    expect(isAppShortcut(down(LogicalKeyboardKey.comma), Mods.ctrl), isFalse);
    expect(isAppShortcut(t, Mods.ctrl | Mods.shift), isTrue);
    expect(
      isAppShortcut(down(LogicalKeyboardKey.arrowLeft), Mods.ctrl | Mods.shift),
      isTrue,
    );
  });
}
