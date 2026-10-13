import 'dart:async';

import 'package:flutter/material.dart';

import 'keys.dart';

/// Extra keys for soft keyboards: Esc, Tab, sticky Ctrl/Alt, arrows,
/// navigation and the symbols shells need most. Never takes focus, so the
/// terminal (and its soft keyboard) stays up.
class KeyBar extends StatelessWidget {
  const KeyBar({
    super.key,
    required this.sticky,
    required this.onKey,
    required this.onText,
    required this.onToggle,
    required this.onPaste,
  });

  /// [Mods] bits currently latched.
  final int sticky;
  final void Function(int hid) onKey;
  final void Function(String text) onText;
  final void Function(int mod) onToggle;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: Material(
        color: const Color(0xFF0E0F12),
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              _Key('esc', () => onKey(Hid.escape)),
              _Key('tab', () => onKey(Hid.tab)),
              _Key(
                'ctrl',
                () => onToggle(Mods.ctrl),
                on: sticky & Mods.ctrl != 0,
              ),
              _Key('alt', () => onToggle(Mods.alt), on: sticky & Mods.alt != 0),
              _Key('←', () => onKey(Hid.arrowLeft), repeat: true),
              _Key('↓', () => onKey(Hid.arrowDown), repeat: true),
              _Key('↑', () => onKey(Hid.arrowUp), repeat: true),
              _Key('→', () => onKey(Hid.arrowRight), repeat: true),
              _Key('home', () => onKey(Hid.home)),
              _Key('end', () => onKey(Hid.end)),
              _Key('pgup', () => onKey(Hid.pageUp)),
              _Key('pgdn', () => onKey(Hid.pageDown)),
              for (final s in const ['|', '/', '-', '~', '_', '*', '&', r'$'])
                _Key(s, () => onText(s)),
              _Key('pegar', onPaste),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key(this.label, this.onTap, {this.on = false, this.repeat = false});

  final String label;
  final VoidCallback onTap;
  final bool on;

  /// Repeats while held, like a hardware key.
  final bool repeat;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  Timer? _timer;

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: GestureDetector(
        onLongPressStart: widget.repeat
            ? (_) {
                widget.onTap();
                _timer = Timer.periodic(
                  const Duration(milliseconds: 60),
                  (_) => widget.onTap(),
                );
              }
            : null,
        onLongPressEnd: widget.repeat ? (_) => _stop() : null,
        onLongPressCancel: widget.repeat ? _stop : null,
        child: Material(
          color: widget.on ? scheme.primary : const Color(0xFF23262D),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: widget.onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.on ? scheme.onPrimary : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
