import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show ShortcutActivator;

/// libghostty-vt modifier bits (`openward_ghostty::mods`).
abstract final class Mods {
  static const shift = 1;
  static const ctrl = 2;
  static const alt = 4;
  static const superKey = 8;
  static const capsLock = 16;
  static const numLock = 32;
  static const altRight = 256;
}

/// USB HID usages (page 7) the key bar and the text path send.
abstract final class Hid {
  static const a = 0x00070004;
  static const enter = 0x00070028;
  static const escape = 0x00070029;
  static const backspace = 0x0007002A;
  static const tab = 0x0007002B;
  static const home = 0x0007004A;
  static const pageUp = 0x0007004B;
  static const end = 0x0007004D;
  static const pageDown = 0x0007004E;
  static const arrowRight = 0x0007004F;
  static const arrowLeft = 0x00070050;
  static const arrowDown = 0x00070051;
  static const arrowUp = 0x00070052;
}

final bool isApple = Platform.isMacOS || Platform.isIOS;

/// Shortcuts go with ⌘ (a Mac's) rather than Ctrl+Shift (a PC's): the
/// system's way unless the settings choose (`Settings.shortcutProfile`).
/// Platform matters (Option as Alt, ⌘-click on links) stay [isApple].
bool macShortcuts = isApple;

/// In a terminal, the window takes only Ctrl+Shift shortcuts: Ctrl+Tab,
/// Ctrl+= and the like go to the program (`Settings.terminalKeysFirst`).
bool terminalKeysFirst = false;

/// Modifiers held on the hardware keyboard, as [Mods] bits.
int hardwareMods() {
  final k = HardwareKeyboard.instance;
  final pressed = k.physicalKeysPressed;
  var m = 0;
  if (k.isShiftPressed) m |= Mods.shift;
  if (k.isControlPressed) m |= Mods.ctrl;
  if (k.isAltPressed) m |= Mods.alt;
  if (k.isMetaPressed) m |= Mods.superKey;
  if (k.lockModesEnabled.contains(KeyboardLockMode.capsLock)) {
    m |= Mods.capsLock;
  }
  if (k.lockModesEnabled.contains(KeyboardLockMode.numLock)) {
    m |= Mods.numLock;
  }
  if (pressed.contains(PhysicalKeyboardKey.altRight) &&
      !pressed.contains(PhysicalKeyboardKey.altLeft)) {
    m |= Mods.altRight;
  }
  return m;
}

/// Ctrl and the left Alt with a digit from 1 to 9: going to a tab, off
/// Apple platforms. The right Alt is AltGr, which types (@ on many
/// layouts) and is left alone.
class TabDigitActivator extends ShortcutActivator {
  const TabDigitActivator(this.digit);

  /// From 1 to 9.
  final int digit;

  LogicalKeyboardKey get _key =>
      LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + digit - 1);

  @override
  Iterable<LogicalKeyboardKey>? get triggers => [_key];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      event is KeyDownEvent && event.logicalKey == _key && isTabDigit(state);

  @override
  String debugDescribeKeys() => 'Ctrl+Alt+$digit';
}

/// Ctrl and the left Alt held, nothing else: [TabDigitActivator]'s keys.
bool isTabDigit(HardwareKeyboard state) {
  final pressed = state.physicalKeysPressed;
  return state.isControlPressed &&
      pressed.contains(PhysicalKeyboardKey.altLeft) &&
      !state.isShiftPressed &&
      !state.isMetaPressed;
}

/// The keypad's keys but Enter (which is always the encoder's): digits,
/// operators, the decimal point, `=` and `,`.
bool isKeypadKey(int hid) {
  if (hid >> 16 != 0x0007) return false;
  final id = hid & 0xFFFF;
  return (id >= 0x54 && id <= 0x57) ||
      (id >= 0x59 && id <= 0x63) ||
      id == 0x67 ||
      id == 0x85;
}

/// Keys that never produce text: they always go to the encoder, never to
/// the input method.
bool isFunctionalKey(int hid) {
  if (hid >> 16 != 0x0007) return false;
  final id = hid & 0xFFFF;
  return (id >= 0x28 && id <= 0x2B) || // Enter, Escape, Backspace, Tab
      (id >= 0x3A && id <= 0x52) || // F1–F12, PrintScreen…Arrows
      id == 0x58 || // Numpad Enter
      (id >= 0x68 && id <= 0x73); // F13–F24
}

/// The character a logical key stands for without Shift, or 0.
int unshiftedCodepoint(LogicalKeyboardKey key) {
  final id = key.keyId;
  // Printable logical keys live in Flutter's Unicode plane: id = codepoint.
  if (id & LogicalKeyboardKey.planeMask != LogicalKeyboardKey.unicodePlane) {
    return 0;
  }
  return id <= 0x10FFFF ? id : 0;
}

/// HID usage of the US-layout key for a lowercase ASCII letter, or 0. Used
/// when a sticky modifier from the key bar applies to soft keyboard text.
int hidForChar(String c) {
  final code = c.toLowerCase().codeUnitAt(0);
  if (c.length == 1 && code >= 0x61 && code <= 0x7A) return Hid.a + code - 0x61;
  return 0;
}

bool isControlText(String s) =>
    s.runes.any((r) => r < 0x20 || r == 0x7F || (r >= 0xF700 && r <= 0xF8FF));

/// Keys the window keeps for itself (tabs, search), never sent to the
/// program: ⌘ anything with a Mac's shortcuts; with a PC's, Ctrl+Shift
/// and a letter, and Ctrl+Tab, as other terminals do (unless the program
/// comes first: [terminalKeysFirst]).
bool isAppShortcut(KeyEvent event, int mods) {
  if (macShortcuts) return mods & Mods.superKey != 0;
  final ctrlShift = Mods.ctrl | Mods.shift;
  final key = event.logicalKey;
  // Ctrl+Tab, Ctrl+, (the settings), the text size and Ctrl+Alt+digit:
  // the program's, when it comes first.
  final ctrlOnly = !terminalKeysFirst;
  if (ctrlOnly && key == LogicalKeyboardKey.tab && mods & Mods.ctrl != 0) {
    return true;
  }
  if (ctrlOnly && key == LogicalKeyboardKey.comma && mods & Mods.ctrl != 0) {
    return true;
  }
  // Ctrl+Shift+arrows move between panes; Ctrl+Shift+Enter maximizes one.
  if (mods & ctrlShift == ctrlShift &&
      mods & Mods.alt == 0 &&
      (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.enter)) {
    return true;
  }
  // Ctrl+Shift+/ shows the shortcuts.
  if (mods & ctrlShift == ctrlShift &&
      mods & Mods.alt == 0 &&
      (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.question)) {
    return true;
  }
  // Ctrl+= / Ctrl+- / Ctrl+0 size the tab's text, as in other terminals.
  if (ctrlOnly &&
      mods & Mods.ctrl != 0 &&
      mods & Mods.alt == 0 &&
      (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.digit0)) {
    return true;
  }
  // Ctrl+(left) Alt+1…9 go to a tab; AltGr+digit types.
  if (ctrlOnly &&
      key.keyId >= LogicalKeyboardKey.digit1.keyId &&
      key.keyId <= LogicalKeyboardKey.digit9.keyId &&
      isTabDigit(HardwareKeyboard.instance)) {
    return true;
  }
  final letter =
      key.keyId >= LogicalKeyboardKey.keyA.keyId &&
      key.keyId <= LogicalKeyboardKey.keyZ.keyId;
  return letter && mods & ctrlShift == ctrlShift && mods & Mods.alt == 0;
}
