// The interactive terminal: frames from the core painted once per refresh,
// and keyboard, input method, paste and mouse sent to it. Grown from the
// S1.5 bench (spikes/s1-terminal/render_harness/lib/shell/shell_page.dart).

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/session.dart';
import 'controller.dart';
import 'keys.dart';
import 'renderer.dart';

class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.controller,
    this.autofocus = true,
  });

  final TerminalController controller;
  final bool autofocus;

  @override
  State<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends State<TerminalPane>
    with SingleTickerProviderStateMixin, TextInputClient {
  late final Ticker _ticker = createTicker(_onTick);
  final FocusNode focusNode = FocusNode(debugLabel: 'terminal');
  final GlobalKey _gridKey = GlobalKey();

  TerminalController get _c => widget.controller;
  TerminalSession get _session => widget.controller.session;
  TerminalRenderer? _renderer;

  int _cols = 0;
  int _rows = 0;

  // Input method state. The editing value is a fixed placeholder so that
  // there is always something to delete: a shorter value means Backspace,
  // extra text is input (see [updateEditingValue]).
  static const _placeholder = '  ';
  static const _idle = TextEditingValue(
    text: _placeholder,
    selection: TextSelection.collapsed(offset: _placeholder.length),
  );
  TextInputConnection? _input;
  TextEditingValue _value = _idle;
  String _composing = '';

  /// Keys whose press went to the encoder, so their release does too.
  final Set<int> _encoderKeys = {};

  int _buttons = 0;
  double _scrollPixels = 0;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(_onFocusChange);
    _c.visible = true;
    _ticker.start();
    if (widget.autofocus) _focusSoon();
  }

  /// Takes the keyboard after this frame, even from another field (the
  /// search box a host was opened from).
  void _focusSoon() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _renderer = _c.renderer(MediaQuery.devicePixelRatioOf(context));
  }

  @override
  void didUpdateWidget(TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) _focusSoon();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.visible = false;
      _c.visible = true;
      _renderer = _c.renderer(MediaQuery.devicePixelRatioOf(context));
      _cols = _rows = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _input?.close();
    focusNode.dispose();
    _c.visible = false;
    super.dispose();
  }

  // ---------------------------------------------------------------- frames

  void _onTick(Duration _) {
    final before = _renderer?.cursor;
    if (!_c.poll()) return;
    final after = _renderer?.cursor;
    if (before?.row != after?.row || before?.col != after?.col) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _updateImeRects());
    }
  }

  void _layout(BoxConstraints c, TerminalRenderer r) {
    final m = r.metrics;
    final cols = math.max(10, (c.maxWidth / m.width).floor());
    final rows = math.max(4, (c.maxHeight / m.height).floor());
    if (cols == _cols && rows == _rows) return;
    _cols = cols;
    _rows = rows;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session.resize(cols: cols, rows: rows);
      _updateImeRects();
    });
  }

  // -------------------------------------------------------------- keyboard

  void _sendKey(int hid, {int mods = 0, String text = '', int unshifted = 0}) {
    for (final kind in [KeyKind.down, KeyKind.up]) {
      _session.key(
        hidUsage: hid,
        kind: kind,
        mods: mods,
        text: kind == KeyKind.down ? text : '',
        unshifted: unshifted,
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // While composing, keys belong to the input method (candidate
    // selection, commit). macOS never even shows them to the framework.
    if (_composing.isNotEmpty) return KeyEventResult.ignored;
    final hid = event.physicalKey.usbHidUsage;

    if (event is KeyUpEvent) {
      if (!_encoderKeys.remove(hid)) return KeyEventResult.ignored;
      _session.key(
        hidUsage: hid,
        kind: KeyKind.up,
        mods: hardwareMods(),
        text: '',
        unshifted: unshiftedCodepoint(event.logicalKey),
      );
      return KeyEventResult.handled;
    }

    final mods = hardwareMods();
    if (event is KeyDownEvent && _isPasteShortcut(event, mods)) {
      _paste();
      return KeyEventResult.handled;
    }
    // Tabs, search and the like: the window's.
    if (isAppShortcut(event, mods)) return KeyEventResult.ignored;

    final char = event.character ?? '';
    final printable = char.isNotEmpty && !isControlText(char);
    final altIsMeta = !isApple || _optionAsAlt;
    final chord = mods & Mods.ctrl != 0 || (altIsMeta && mods & Mods.alt != 0);
    // AltGr on Windows is Ctrl+Alt and types characters (@ on many layouts).
    final altGr =
        Platform.isWindows &&
        mods & Mods.ctrl != 0 &&
        mods & Mods.alt != 0 &&
        printable;
    final toEncoder =
        isFunctionalKey(hid) ||
        (chord && !altGr) ||
        (_c.reportAllKeys && printable);
    // Everything else is text: the input method delivers it, so dead keys,
    // compose sequences and IMEs work.
    if (!toEncoder) return KeyEventResult.ignored;

    _session.key(
      hidUsage: hid,
      kind: event is KeyRepeatEvent ? KeyKind.repeat : KeyKind.down,
      mods: mods,
      text: char,
      unshifted: unshiftedCodepoint(event.logicalKey),
    );
    _encoderKeys.add(hid);
    return KeyEventResult.handled;
  }

  // Settings come with A5; until then Option types symbols, as on macOS.
  static const bool _optionAsAlt = false;

  bool _isPasteShortcut(KeyDownEvent e, int mods) {
    final v = e.logicalKey == LogicalKeyboardKey.keyV;
    if (isApple) return v && mods & Mods.superKey != 0;
    return (v && mods & Mods.ctrl != 0 && mods & Mods.shift != 0) ||
        (e.logicalKey == LogicalKeyboardKey.insert && mods & Mods.shift != 0);
  }

  // ------------------------------------------------------------------ paste

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    if (_session.paste(text: text, allowUnsafe: false)) return;
    final preview = text.length > 400 ? '${text.substring(0, 400)}…' : text;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Pegar varias líneas?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'El texto contiene saltos de línea u otras secuencias que '
                'pueden ejecutar comandos al pegarlo.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black,
                child: Text(
                  preview,
                  style: TextStyle(fontFamily: _renderer?.metrics.fontFamily),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pegar'),
          ),
        ],
      ),
    );
    if (ok == true) _session.paste(text: text, allowUnsafe: true);
    focusNode.requestFocus();
  }

  // ---------------------------------------------------------- input method

  void _onFocusChange() {
    final has = focusNode.hasFocus;
    if (!_c.isDisposed) _session.focus(gained: has);
    if (has) {
      _openInput();
    } else {
      _input?.close();
      _input = null;
      if (_composing.isNotEmpty) setState(() => _composing = '');
    }
  }

  void _openInput() {
    if (_input?.attached ?? false) {
      _input!.show();
      return;
    }
    _input = TextInput.attach(
      this,
      TextInputConfiguration(
        viewId: View.of(context).viewId,
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        keyboardAppearance: Brightness.dark,
      ),
    );
    _value = _idle;
    _input!
      ..setEditingState(_value)
      ..show();
    _updateImeRects();
  }

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _value = value;
    final composing = value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      setState(() => _composing = composing.textInside(value.text));
      SchedulerBinding.instance.addPostFrameCallback((_) => _updateImeRects());
      return;
    }
    if (_composing.isNotEmpty) setState(() => _composing = '');
    final text = value.text;
    if (text == _placeholder) return;
    // Common prefix with the placeholder: what is missing was deleted,
    // what follows was typed.
    var common = 0;
    while (common < text.length &&
        common < _placeholder.length &&
        text.codeUnitAt(common) == _placeholder.codeUnitAt(common)) {
      common++;
    }
    for (var i = common; i < _placeholder.length; i++) {
      _sendKey(Hid.backspace);
    }
    final typed = text.substring(common);
    if (typed.isNotEmpty) _session.text(text: typed);
    _value = _idle;
    _input?.setEditingState(_value);
  }

  @override
  void performAction(TextInputAction action) {
    switch (action) {
      case TextInputAction.newline:
      case TextInputAction.done:
      case TextInputAction.go:
      case TextInputAction.send:
      case TextInputAction.search:
        _sendKey(Hid.enter);
      default:
        break;
    }
  }

  /// macOS editing commands for keys the framework let through.
  @override
  void performSelector(String selectorName) {
    const keys = {
      'deleteBackward:': Hid.backspace,
      'insertNewline:': Hid.enter,
      'insertTab:': Hid.tab,
      'cancelOperation:': Hid.escape,
      'moveLeft:': Hid.arrowLeft,
      'moveRight:': Hid.arrowRight,
      'moveUp:': Hid.arrowUp,
      'moveDown:': Hid.arrowDown,
    };
    final hid = keys[selectorName];
    if (hid != null) _sendKey(hid);
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _input = null;
    if (_composing.isNotEmpty) setState(() => _composing = '');
  }

  /// Where the IME puts its candidate window: at the cursor.
  void _updateImeRects() {
    final input = _input;
    final r = _renderer;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (input == null ||
        !input.attached ||
        r == null ||
        box == null ||
        !box.hasSize) {
      return;
    }
    final m = r.metrics;
    final c = r.cursor;
    final caret = Rect.fromLTWH(
      (c?.col ?? 0) * m.width,
      (c?.row ?? 0) * m.height,
      m.width,
      m.height,
    );
    input
      ..setEditableSizeAndTransform(box.size, box.getTransformTo(null))
      ..updateStyle(
        TextInputStyle(
          fontFamily: m.fontFamily,
          fontSize: m.fontSize,
          fontWeight: FontWeight.normal,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
        ),
      )
      ..setCaretRect(caret)
      ..setComposingRect(
        Rect.fromLTWH(
          caret.left,
          caret.top,
          math.max(1, _composing.runes.length * 2) * m.width,
          m.height,
        ),
      );
  }

  // ------------------------------------------------------------------ mouse

  PointerButton _button(int bits) {
    if (bits & kPrimaryMouseButton != 0) return PointerButton.left;
    if (bits & kSecondaryMouseButton != 0) return PointerButton.right;
    if (bits & kMiddleMouseButton != 0) return PointerButton.middle;
    return PointerButton.none;
  }

  bool _isTouch(PointerEvent e) =>
      e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;

  void _pointer(PointerAction action, PointerButton button, Offset at) {
    _session.pointer(
      action: action,
      button: button,
      mods: hardwareMods(),
      x: at.dx,
      y: at.dy,
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    focusNode.requestFocus();
    _scrollPixels = 0;
    if (_isTouch(e) || !_c.mouseTracking) return;
    final pressed = e.buttons & ~_buttons;
    _buttons = e.buttons;
    _pointer(PointerAction.down, _button(pressed), e.localPosition);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_isTouch(e)) {
      // Dragging the content down reveals history (positive lines).
      _scroll(e.localDelta.dy, e.localPosition);
      return;
    }
    if (_c.mouseTracking) {
      _pointer(PointerAction.move, PointerButton.none, e.localPosition);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_isTouch(e)) return;
    final released = _buttons & ~e.buttons;
    _buttons = e.buttons;
    if (!_c.mouseTracking || released == 0) return;
    _pointer(PointerAction.up, _button(released), e.localPosition);
  }

  void _onHover(PointerHoverEvent e) {
    if (_c.mouseTracking) {
      _pointer(PointerAction.move, PointerButton.none, e.localPosition);
    }
  }

  void _onSignal(PointerSignalEvent e) {
    // Wheel: positive dy scrolls towards the end.
    if (e is PointerScrollEvent) _scroll(-e.scrollDelta.dy, e.localPosition);
  }

  void _onPanZoom(PointerPanZoomUpdateEvent e) {
    // Trackpad: fingers moving down reveal history, as with touch.
    _scroll(e.localPanDelta.dy, e.localPosition);
  }

  void _scroll(double pixels, Offset at) {
    final r = _renderer;
    if (r == null) return;
    final h = r.metrics.height;
    _scrollPixels += pixels;
    final lines = (_scrollPixels / h).truncate();
    if (lines == 0) return;
    _scrollPixels -= lines * h;
    _session.wheel(lines: lines, x: at.dx, y: at.dy, mods: hardwareMods());
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final r = _renderer!;
    final m = r.metrics;
    final cursor = r.cursor;
    return ColoredBox(
      color: r.palette.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 0, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _layout(constraints, r);
            return Focus(
              focusNode: focusNode,
              onKeyEvent: _onKey,
              child: MouseRegion(
                cursor: _c.mouseTracking
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.text,
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerHover: _onHover,
                  onPointerSignal: _onSignal,
                  onPointerPanZoomUpdate: _onPanZoom,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Stack(
                      children: [
                        TerminalGrid(
                          key: _gridKey,
                          renderer: r,
                          cols: _cols,
                          rows: _rows,
                        ),
                        if (_composing.isNotEmpty && cursor != null)
                          Positioned(
                            left: cursor.col * m.width,
                            top: cursor.row * m.height,
                            child: _ComposingText(
                              text: _composing,
                              renderer: r,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// IME composition drawn in place, at the cursor, underlined.
class _ComposingText extends StatelessWidget {
  const _ComposingText({required this.text, required this.renderer});

  final String text;
  final TerminalRenderer renderer;

  @override
  Widget build(BuildContext context) {
    final m = renderer.metrics;
    final p = renderer.palette;
    return Container(
      color: p.background,
      height: m.height,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: m.fontFamily,
          fontFamilyFallback: m.fallback,
          fontSize: m.fontSize,
          height: 1,
          color: p.foreground,
          decoration: TextDecoration.underline,
          decorationColor: p.cursor,
          decorationThickness: 2,
        ),
      ),
    );
  }
}
