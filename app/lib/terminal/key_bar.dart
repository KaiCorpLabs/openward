import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../ui/tokens.dart';
import 'controller.dart';
import 'keys.dart';

/// What the key bar types into: the pane showing the session in front
/// (`TerminalPaneState`), which sends as its own keyboard does, to the
/// panes broadcasting with it too.
abstract interface class KeyBarTarget {
  /// A key of the bar, with these [Mods] bits.
  void barKey(int hid, int mods);

  /// Text of the bar (`|`, `~`…), as if typed.
  void barText(String text);

  /// Pastes the clipboard, asking first when the terminal's rules say so.
  Future<void> barPaste();

  /// Shows or hides the system's keyboard.
  void barKeyboard({required bool show});
}

/// Ctrl and Alt of the bar: held for the next key, of the bar or of the
/// system's keyboard, then let go (one tap); or until tapped again (two).
class StickyMods extends ChangeNotifier {
  int _once = 0;
  int _locked = 0;

  int get value => _once | _locked;
  bool held(int mod) => value & mod != 0;
  bool locked(int mod) => _locked & mod != 0;

  /// One tap holds it for the next key; another, until tapped again; a
  /// third lets it go.
  void tap(int mod) {
    if (_locked & mod != 0) {
      _locked &= ~mod;
    } else if (_once & mod != 0) {
      _once &= ~mod;
      _locked |= mod;
    } else {
      _once |= mod;
    }
    notifyListeners();
  }

  /// What applies to this key; the one-tap ones are used up.
  int take() {
    final v = value;
    if (_once != 0) {
      _once = 0;
      notifyListeners();
    }
    return v;
  }
}

/// Shared by every pane: the bar is one, under the tab in front.
final stickyMods = StickyMods();

/// The keys a phone's keyboard lacks, over it (ARCHITECTURE §3.4): Esc,
/// Tab, Ctrl and Alt (sticky), the arrows, the symbols shells use most,
/// paging, paste and the keyboard itself. It scrolls sideways when the
/// screen is narrow.
class KeyBar extends StatelessWidget {
  const KeyBar({required this.controller, super.key});

  final TerminalController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    void key(int hid) {
      HapticFeedback.selectionClick();
      controller.keyBar?.barKey(hid, stickyMods.take());
    }

    void text(String s) {
      HapticFeedback.selectionClick();
      controller.keyBar?.barText(s);
    }

    return Material(
      key: const ValueKey('keyBar'),
      color: c.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SizedBox(
          height: 44,
          child: ListenableBuilder(
            listenable: stickyMods,
            builder: (context, _) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: OwSpace.s2),
              children: [
                _Key(
                  label: 'Esc',
                  semantics: 'Escape',
                  onTap: () => key(Hid.escape),
                ),
                _Key(label: 'Tab', semantics: 'Tab', onTap: () => key(Hid.tab)),
                _Key(
                  label: 'Ctrl',
                  semantics: l.keyBarCtrl,
                  held: stickyMods.held(Mods.ctrl),
                  locked: stickyMods.locked(Mods.ctrl),
                  onTap: () => stickyMods.tap(Mods.ctrl),
                ),
                _Key(
                  label: 'Alt',
                  semantics: l.keyBarAlt,
                  held: stickyMods.held(Mods.alt),
                  locked: stickyMods.locked(Mods.alt),
                  onTap: () => stickyMods.tap(Mods.alt),
                ),
                _Key(
                  icon: Icons.keyboard_arrow_left,
                  semantics: l.keyBarLeft,
                  onTap: () => key(Hid.arrowLeft),
                  repeat: true,
                ),
                _Key(
                  icon: Icons.keyboard_arrow_up,
                  semantics: l.keyBarUp,
                  onTap: () => key(Hid.arrowUp),
                  repeat: true,
                ),
                _Key(
                  icon: Icons.keyboard_arrow_down,
                  semantics: l.keyBarDown,
                  onTap: () => key(Hid.arrowDown),
                  repeat: true,
                ),
                _Key(
                  icon: Icons.keyboard_arrow_right,
                  semantics: l.keyBarRight,
                  onTap: () => key(Hid.arrowRight),
                  repeat: true,
                ),
                for (final s in const ['|', '~', '/', '-', '_', r'$', '*', ':'])
                  _Key(label: s, semantics: s, onTap: () => text(s)),
                _Key(
                  label: l.keyBarHome,
                  semantics: l.keyBarHome,
                  onTap: () => key(Hid.home),
                ),
                _Key(
                  label: l.keyBarEnd,
                  semantics: l.keyBarEnd,
                  onTap: () => key(Hid.end),
                ),
                _Key(
                  label: l.keyBarPageUp,
                  semantics: l.keyBarPageUp,
                  onTap: () => key(Hid.pageUp),
                ),
                _Key(
                  label: l.keyBarPageDown,
                  semantics: l.keyBarPageDown,
                  onTap: () => key(Hid.pageDown),
                ),
                _Key(
                  icon: Icons.content_paste,
                  semantics: l.paste,
                  onTap: () => controller.keyBar?.barPaste(),
                ),
                _Key(
                  key: const ValueKey('keyBar.keyboard'),
                  icon: keyboard
                      ? Icons.keyboard_hide_outlined
                      : Icons.keyboard_outlined,
                  semantics: keyboard
                      ? l.keyBarHideKeyboard
                      : l.keyBarShowKeyboard,
                  onTap: () => controller.keyBar?.barKeyboard(show: !keyboard),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    required this.semantics,
    required this.onTap,
    this.label,
    this.icon,
    this.held = false,
    this.locked = false,
    this.repeat = false,
    super.key,
  });

  final String? label;
  final IconData? icon;
  final String semantics;
  final VoidCallback onTap;
  final bool held;
  final bool locked;

  /// Held down, it goes on, as an arrow key does.
  final bool repeat;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _repeating = false;

  Future<void> _repeat() async {
    _repeating = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    while (_repeating && mounted) {
      widget.onTap();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  @override
  void dispose() {
    _repeating = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final on = widget.held;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OwSpace.s1,
        vertical: OwSpace.s2,
      ),
      child: Semantics(
        button: true,
        selected: on,
        label: widget.semantics,
        child: Material(
          color: on ? c.primary : c.control,
          borderRadius: BorderRadius.circular(ow.shape.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(ow.shape.radius),
            onTap: widget.onTap,
            child: GestureDetector(
              onLongPressStart: widget.repeat ? (_) => _repeat() : null,
              onLongPressEnd: widget.repeat ? (_) => _repeating = false : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: OwSpace.s5),
                  child: Center(
                    child: ExcludeSemantics(
                      child: widget.icon != null
                          ? Icon(
                              widget.icon,
                              size: 20,
                              color: on ? c.onPrimary : c.text,
                            )
                          : Text(
                              widget.label!,
                              style: TextStyle(
                                fontFamily: ow.fonts.mono,
                                fontSize: OwText.title,
                                fontWeight: widget.locked
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                decoration: widget.locked
                                    ? TextDecoration.underline
                                    : null,
                                color: on ? c.onPrimary : c.text,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
