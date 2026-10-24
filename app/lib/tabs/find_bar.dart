import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../terminal/controller.dart';
import '../ui/tokens.dart';

/// Search through the terminal and its history (⌘F). Enter goes to the
/// next match towards older output, Shift+Enter back; Esc closes.
class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.controller});

  final TerminalController controller;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final _text = TextEditingController(text: widget.controller.findText);
  final _focus = FocusNode(debugLabel: 'find');

  TerminalController get _c => widget.controller;

  /// Each change starts the search over: it waits for a pause in the
  /// typing, or for Enter.
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 120), () => _search(text));
  }

  void _search(String text) {
    _pending = null;
    _c.find(text);
    // The newest match, nearest the prompt, comes into view at once.
    _c.findStep();
  }

  /// Enter right after typing searches for what is there first.
  void _step({bool older = true}) {
    if (_pending != null) {
      _pending!.cancel();
      _search(_text.text);
      if (older) return;
    }
    _c.findStep(older: older);
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final count = _c.findText.isEmpty
        ? ''
        : _c.findSearching && _c.findTotal == 0
        ? l.findSearching
        : _c.findSelected != null
        ? l.findCount(_c.findSelected!, _c.findTotal)
        : l.findTotal(_c.findTotal);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _c.closeFind,
        const SingleActivator(LogicalKeyboardKey.enter): _step,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
            _step(older: false),
      },
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(
          OwSpace.s5,
          OwSpace.s2,
          OwSpace.s2,
          OwSpace.s2,
        ),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
          border: Border.all(color: c.control),
          boxShadow: OwElevation.raised,
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: c.textSubtle),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                key: const ValueKey('find.text'),
                controller: _text,
                focusNode: _focus,
                autofocus: true,
                onChanged: _changed,
                style: const TextStyle(fontSize: OwText.body),
                decoration: InputDecoration(
                  hintText: l.findHint,
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: OwSpace.s4,
                  ),
                ),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                count,
                style: TextStyle(fontSize: OwText.small, color: c.textMuted),
              ),
            ),
            // Older output is further up.
            IconButton(
              tooltip: l.findOlder,
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              onPressed: _c.findText.isEmpty ? null : () => _c.findStep(),
            ),
            IconButton(
              tooltip: l.findNewer,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              onPressed: _c.findText.isEmpty
                  ? null
                  : () => _c.findStep(older: false),
            ),
            IconButton(
              tooltip: l.findClose,
              icon: const Icon(Icons.close, size: 16),
              onPressed: _c.closeFind,
            ),
          ],
        ),
      ),
    );
  }
}

/// A short flash over the terminal on each BEL, if the setting asks for
/// it. With fewer animations it is a still outline instead.
class BellFlash extends ConsumerStatefulWidget {
  const BellFlash({super.key, required this.controller});

  final TerminalController controller;

  @override
  ConsumerState<BellFlash> createState() => _BellFlashState();
}

class _BellFlashState extends ConsumerState<BellFlash> {
  late int _seen = widget.controller.bells;
  bool _on = false;
  Timer? _off;

  @override
  void dispose() {
    _off?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bells = widget.controller.bells;
    if (bells != _seen) {
      _seen = bells;
      if (ref.read(settingsProvider).bellFlash) {
        _on = true;
        _off?.cancel();
        _off = Timer(const Duration(milliseconds: 180), () {
          if (mounted) setState(() => _on = false);
        });
      }
    }
    final ow = context.ow;
    final still = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _on ? 1 : 0,
        duration: still ? Duration.zero : OwMotion.fast,
        child: Container(
          decoration: BoxDecoration(
            color: still
                ? null
                : ow.terminal.foreground.withValues(alpha: 0.08),
            border: Border.all(color: ow.colors.warn, width: 2),
          ),
        ),
      ),
    );
  }
}
