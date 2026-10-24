// The focus ring: where the keyboard is, and only when the keyboard put it
// there. A click leaves no ring.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../terminal/palette.dart';
import 'tokens.dart';

/// Whether the user is moving with the keyboard: a key turns it on, a
/// press of the pointer off.
abstract final class KeyboardMode {
  static final active = ValueNotifier<bool>(false);
  static bool _watching = false;

  /// From the start of the app, or of a test that looks at the ring.
  static void watch() {
    if (_watching) return;
    _watching = true;
    HardwareKeyboard.instance.addHandler((e) {
      if (e is KeyDownEvent) active.value = true;
      return false;
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent) active.value = false;
    });
  }
}

/// The ring, 2 px outside the control: in the accent, or in the text's
/// color around a `fill` the accent would melt into.
BorderSide focusRingSide(OwColors c, {Color? fill}) => BorderSide(
  color: fill != null && TermPalette.contrast(c.accent, fill) < 3
      ? c.text
      : c.accent,
  width: 2,
  strokeAlign: BorderSide.strokeAlignOutside,
);

/// A button's border: `side`, or the ring while the keyboard has it.
WidgetStateProperty<BorderSide?> ringedSide(
  OwColors c, {
  BorderSide? side,
  Color? fill,
}) => WidgetStateProperty.resolveWith(
  (s) => s.contains(WidgetState.focused) && KeyboardMode.active.value
      ? focusRingSide(c, fill: fill)
      : side,
);
