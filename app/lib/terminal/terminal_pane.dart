// The interactive terminal: frames from the core painted once per refresh,
// and keyboard, input method, paste and mouse sent to it. Grown from the
// S1.5 bench (spikes/s1-terminal/render_harness/lib/shell/shell_page.dart).

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/settings.dart';
import '../history/history.dart';
import '../history/line_tracker.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../tabs/connection_motion.dart' show comebackWords;
import '../ui/tokens.dart';
import 'controller.dart';
import 'keys.dart';
import 'renderer.dart';

class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({
    super.key,
    required this.controller,
    this.autofocus = true,
    this.mirrors,
    this.paneMenu,
  });

  final TerminalController controller;
  final bool autofocus;

  /// What the right-click menu adds for the pane it is in: splitting,
  /// closing, and that things can be dropped on it.
  final List<PopupMenuEntry<VoidCallback>> Function(BuildContext)? paneMenu;

  /// Other sessions that get what is typed here (broadcast), asked for at
  /// each key: panes join and leave while it is on.
  final List<TerminalController> Function()? mirrors;

  @override
  ConsumerState<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends ConsumerState<TerminalPane>
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

  /// A selection drag is under way (the press did not go to the program).
  bool _selecting = false;

  bool _optionAsAlt = false;

  /// Blinks the cursor when the program (or the setting) asks for it.
  Timer? _blink;
  bool _stillMotion = false;

  /// Scrolls the history while a selection is dragged past an edge.
  Timer? _autoScroll;
  Offset _dragAt = Offset.zero;

  /// The link under the pointer while ⌘ (Ctrl elsewhere) is held.
  LinkView? _link;
  String? get _linkUrl => _link?.url;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(_onFocusChange);
    _c.visible = true;
    _c.focusTerminal = _focusSoon;
    _ticker.start();
    // Its language for the line that marks a new shell after a cut.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = context.l10n;
      _c.comebackLine = (at, away) => comebackWords(l, at, away);
    });
    final settings = ref.read(settingsProvider);
    _optionAsAlt = settings.optionAsAlt;
    _session.setOptionAsAlt(enabled: _optionAsAlt);
    _applyCursor(settings);
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      final r = _renderer;
      if (r == null) return;
      final blinking = _c.cursorBlinks && focusNode.hasFocus && !_stillMotion;
      r.setCursorOn(blinking ? !r.cursorOn : true);
    });
    if (widget.autofocus) _focusSoon();
  }

  void _applyCursor(Settings s) {
    _session.setCursor(
      style: switch (s.cursor) {
        CursorChoice.block => CursorStyle.block,
        CursorChoice.bar => CursorStyle.bar,
        CursorChoice.underline => CursorStyle.underline,
      },
      blink: s.cursorBlink,
    );
  }

  /// Takes the keyboard after this frame, even from another field (the
  /// search box a host was opened from).
  void _focusSoon() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  /// The renderer for the current pixel density, font, theme and the
  /// accessibility settings.
  TerminalRenderer _look() {
    final settings = ref.watch(settingsProvider);
    final ow = context.ow;
    return _renderer = _c.renderer(
      MediaQuery.devicePixelRatioOf(context),
      fontSize: (settings.fontSize + _c.zoom).clamp(6, 48),
      palette: ow.terminal,
      fontFamily: ow.fonts.terminal,
      lineHeight: settings.lineHeight,
      minimumContrast: settings.minimumContrast ? ow.minimumContrast : 1,
    );
  }

  @override
  void didUpdateWidget(TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) _focusSoon();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.visible = false;
      if (oldWidget.controller.focusTerminal == _focusSoon) {
        oldWidget.controller.focusTerminal = null;
      }
      _c.visible = true;
      _c.focusTerminal = _focusSoon;
      _applyCursor(ref.read(settingsProvider));
      _cols = _rows = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _blink?.cancel();
    _autoScroll?.cancel();
    _input?.close();
    focusNode.dispose();
    _c.visible = false;
    if (_c.focusTerminal == _focusSoon) _c.focusTerminal = null;
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
      widget.controller.grid.value = (cols, rows);
      _updateImeRects();
    });
  }

  // -------------------------------------------------------------- keyboard

  /// This session and, while broadcasting, the others that receive.
  List<TerminalSession> get _targets => [
    _session,
    for (final c in widget.mirrors?.call() ?? const <TerminalController>[])
      if (!c.isDisposed) c.session,
  ];

  void _key({
    required int hidUsage,
    required KeyKind kind,
    required int mods,
    required String text,
    required int unshifted,
  }) {
    if (kind != KeyKind.up) _track(hidUsage, mods, text);
    for (final s in _targets) {
      s.key(
        hidUsage: hidUsage,
        kind: kind,
        mods: mods,
        text: text,
        unshifted: unshifted,
      );
    }
  }

  /// The screen as the command line tracker reads it.
  late final LineScreen _screen = _SessionScreen(_session);

  /// Follows the command line, and at Enter keeps what ran in the history.
  void _track(int hid, int mods, String text) {
    final line = _c.line;
    final held = mods & (Mods.shift | Mods.ctrl | Mods.alt | Mods.superKey);
    if (hid != Hid.enter || held != 0) {
      line.key(hid, mods, text, _screen);
      return;
    }
    final command = line.enter(_screen, altScreen: _c.altScreen);
    if (command != null && ref.read(settingsProvider).commandHistory) {
      ref.read(historyProvider.notifier).add(command, _c);
    }
  }

  void _sendKey(int hid, {int mods = 0, String text = '', int unshifted = 0}) {
    for (final kind in [KeyKind.down, KeyKind.up]) {
      _key(
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
      _key(
        hidUsage: hid,
        kind: KeyKind.up,
        mods: hardwareMods(),
        text: '',
        unshifted: unshiftedCodepoint(event.logicalKey),
      );
      return KeyEventResult.handled;
    }

    final mods = hardwareMods();
    _renderer?.setCursorOn(true);
    if (event is KeyDownEvent && _isPasteShortcut(event, mods)) {
      _paste();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && _isCopyShortcut(event, mods)) {
      _copy();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        isApple &&
        mods & Mods.superKey != 0 &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _session.selectAll();
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

    _key(
      hidUsage: hid,
      kind: event is KeyRepeatEvent ? KeyKind.repeat : KeyKind.down,
      mods: mods,
      text: char,
      unshifted: unshiftedCodepoint(event.logicalKey),
    );
    _encoderKeys.add(hid);
    return KeyEventResult.handled;
  }

  bool _isCopyShortcut(KeyDownEvent e, int mods) {
    final c = e.logicalKey == LogicalKeyboardKey.keyC;
    if (isApple) return c && mods & Mods.superKey != 0;
    return c && mods & Mods.ctrl != 0 && mods & Mods.shift != 0;
  }

  /// Copies the selection; false if there is none.
  bool _copy() {
    final text = _session.selectionText();
    if (text == null || text.isEmpty) return false;
    Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  Future<void> _contextMenu(Offset at) async {
    final hasSelection = _session.selectionText()?.isNotEmpty ?? false;
    final l = context.l10n;
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(
          enabled: hasSelection,
          value: _copy,
          height: 34,
          child: _MenuRow(l.copy, '${key}C'),
        ),
        PopupMenuItem(
          value: _paste,
          height: 34,
          child: _MenuRow(l.paste, '${key}V'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _session.selectAll,
          height: 34,
          child: _MenuRow(l.selectAllText, isApple ? '⌘A' : ''),
        ),
        PopupMenuItem(
          enabled: hasSelection,
          value: _session.clearSelection,
          height: 34,
          child: _MenuRow(l.clearSelection, ''),
        ),
        ...?widget.paneMenu?.call(context),
      ],
    );
    action?.call();
    focusNode.requestFocus();
  }

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
    _c.line.text(text, _screen);
    final also = widget.mirrors?.call() ?? const <TerminalController>[];
    if (also.isNotEmpty) return _pasteBroadcast(text, also);
    if (_session.paste(text: text, allowUnsafe: false)) return;
    final preview = text.length > 400 ? '${text.substring(0, 400)}…' : text;
    final l = context.l10n;
    final ow = context.ow;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.pasteMultiTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pasteMultiBody),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ow.terminal.background,
                  border: Border.all(color: ow.colors.border),
                  borderRadius: BorderRadius.circular(ow.shape.radius),
                ),
                child: Text(
                  preview,
                  style: TextStyle(
                    fontFamily: _renderer?.metrics.fontFamily,
                    color: ow.terminal.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.paste),
          ),
        ],
      ),
    );
    if (ok == true) _session.paste(text: text, allowUnsafe: true);
    focusNode.requestFocus();
  }

  /// With broadcast, a paste always asks first: where it goes, and what.
  Future<void> _pasteBroadcast(
    String text,
    List<TerminalController> also,
  ) async {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final names = [_c, ...also].map((s) => s.displayTitle).toList();
    final lines = text.split('\n').where((x) => x.isNotEmpty).length;
    final preview = text.length > 600 ? '${text.substring(0, 600)}…' : text;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.podcasts, color: c.warn),
        title: Text(l.broadcastPasteTitle(names.length)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.broadcastPasteBody(lines, names.join(', ')),
                style: const TextStyle(height: 1.45),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ow.terminal.background,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(ow.shape.radius),
                    ),
                    child: Text(
                      preview,
                      style: TextStyle(
                        fontFamily: _renderer?.metrics.fontFamily,
                        fontSize: 12,
                        color: ow.terminal.foreground,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l.broadcastPasteAlways,
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.pasteOnlyHere(_c.displayTitle)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.warn,
              foregroundColor: c.surface,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.pasteInPanes(names.length)),
          ),
        ],
      ),
    );
    if (choice == null) return focusNode.requestFocus();
    final targets = choice
        ? [_session, ...also.map((s) => s.session)]
        : [_session];
    for (final s in targets) {
      s.paste(text: text, allowUnsafe: true);
    }
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
    if (typed.isNotEmpty) {
      _c.line.text(typed, _screen);
      for (final s in _targets) {
        s.text(text: typed);
      }
    }
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

  /// Mouse input goes to the program when it asks for it, unless Shift is
  /// held: then, as everywhere else, it selects text.
  bool get _toProgram =>
      _c.mouseTracking && !HardwareKeyboard.instance.isShiftPressed;

  /// ⌘ on Apple platforms, Ctrl elsewhere: what makes links clickable.
  bool get _linkModifier => isApple
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  void _updateLink(Offset at) {
    final link = _linkModifier ? _session.linkAt(x: at.dx, y: at.dy) : null;
    _renderer?.setLink(
      link == null ? null : (row: link.row, start: link.start, end: link.end),
    );
    if (link?.url != _link?.url || link?.text != _link?.text) {
      setState(() => _link = link);
    }
  }

  /// Web and mail links open in their apps; others are not opened from a
  /// terminal, where anyone's output can carry them.
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!const {'http', 'https', 'mailto', 'ftp'}.contains(uri.scheme)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.linkNotOpened(uri.scheme))),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _onPointerDown(PointerDownEvent e) {
    focusNode.requestFocus();
    _scrollPixels = 0;
    if (_isTouch(e)) return;
    final pressed = e.buttons & ~_buttons;
    _buttons = e.buttons;
    final link = _linkUrl;
    if (link != null && pressed & kPrimaryMouseButton != 0 && _linkModifier) {
      _openLink(link);
      return;
    }
    if (!_toProgram) {
      if (pressed & kSecondaryMouseButton != 0) {
        _contextMenu(e.position);
      } else if (pressed & kPrimaryMouseButton != 0) {
        _selecting = true;
        _session.selectPress(x: e.localPosition.dx, y: e.localPosition.dy);
      }
      return;
    }
    _pointer(PointerAction.down, _button(pressed), e.localPosition);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_isTouch(e)) {
      // Dragging the content down reveals history (positive lines).
      _scroll(e.localDelta.dy, e.localPosition);
      return;
    }
    if (_selecting) {
      _session.selectDrag(
        x: e.localPosition.dx,
        y: e.localPosition.dy,
        // Option/Alt drags a block, as in other terminals.
        rectangle: HardwareKeyboard.instance.isAltPressed,
      );
      _dragAt = e.localPosition;
      final height = _rows * (_renderer?.metrics.height ?? 1);
      final outside = e.localPosition.dy < 0 || e.localPosition.dy > height;
      if (!outside) {
        _autoScroll?.cancel();
        _autoScroll = null;
      } else {
        _autoScroll ??= Timer.periodic(
          const Duration(milliseconds: 60),
          (_) => _autoScrollTick(),
        );
      }
      return;
    }
    _updateLink(e.localPosition);
    if (_c.mouseTracking) {
      _pointer(PointerAction.move, PointerButton.none, e.localPosition);
    }
  }

  /// Past the top edge the history scrolls back, past the bottom forward;
  /// further out, faster. The selection follows to the edge row.
  void _autoScrollTick() {
    final r = _renderer;
    if (r == null || !_selecting) return;
    final ch = r.metrics.height;
    final height = _rows * ch;
    final y = _dragAt.dy;
    final over = y < 0 ? -y : y - height;
    if (over <= 0) return;
    final lines = (1 + over / ch).clamp(1, 6).floor();
    final edge = y < 0 ? 0.0 : height - 1;
    _session.wheel(
      lines: y < 0 ? lines : -lines,
      x: _dragAt.dx,
      y: edge,
      mods: 0,
    );
    _session.selectDrag(
      x: _dragAt.dx,
      y: edge,
      rectangle: HardwareKeyboard.instance.isAltPressed,
    );
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_isTouch(e)) return;
    final released = _buttons & ~e.buttons;
    _buttons = e.buttons;
    if (_selecting && released & kPrimaryMouseButton != 0) {
      _selecting = false;
      _autoScroll?.cancel();
      _autoScroll = null;
      _session.selectRelease(x: e.localPosition.dx, y: e.localPosition.dy);
      return;
    }
    if (!_c.mouseTracking || released == 0) return;
    _pointer(PointerAction.up, _button(released), e.localPosition);
  }

  void _onHover(PointerHoverEvent e) {
    _updateLink(e.localPosition);
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
    ref.listen(settingsProvider.select((s) => s.optionAsAlt), (_, on) {
      _optionAsAlt = on;
      _session.setOptionAsAlt(enabled: on);
    });
    ref.listen(
      settingsProvider.select((s) => (s.cursor, s.cursorBlink)),
      (_, _) => _applyCursor(ref.read(settingsProvider)),
    );
    _stillMotion = MediaQuery.disableAnimationsOf(context);
    final r = _look();
    final m = r.metrics;
    final cursor = r.cursor;
    // Room around the text: on the left and on top (two thirds of it); the
    // grid fills the rest and leaves what does not make a whole cell.
    final pad = ref.watch(settingsProvider.select((s) => s.terminalPadding));
    return ColoredBox(
      color: r.palette.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, (pad * 2 / 3).roundToDouble(), 0, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _layout(constraints, r);
            return Focus(
              focusNode: focusNode,
              onKeyEvent: _onKey,
              child: MouseRegion(
                cursor: _linkUrl != null
                    ? SystemMouseCursors.click
                    : _c.mouseTracking
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
                        if (_link case final link?)
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: _LinkTarget(link: link),
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

/// Whether a link's `text` reads as an address of another host than the
/// `url` it opens (an OSC 8 link's text is anything the program wrote).
bool linkMisleads(String text, String url) {
  final shown = text.trim();
  if (shown == url || !shown.contains('.') || shown.contains(' ')) {
    return false;
  }
  final said = Uri.tryParse(shown.contains('://') ? shown : 'https://$shown');
  final real = Uri.tryParse(url);
  if (said == null || real == null || said.host.isEmpty) return false;
  return said.host.toLowerCase() != real.host.toLowerCase();
}

/// Where the link under the pointer leads, as a browser says it: an OSC 8
/// link's text can name another site than the one it opens.
class _LinkTarget extends StatelessWidget {
  const _LinkTarget({required this.link});

  final LinkView link;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final warn = linkMisleads(link.text, link.url);
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: warn ? ow.colors.warnSoft : ow.colors.raised,
          borderRadius: BorderRadius.circular(ow.shape.radius),
          border: Border.all(
            color: warn ? ow.colors.warnLine : ow.colors.control,
          ),
        ),
        child: Text(
          warn ? context.l10n.linkLeadsElsewhere(link.url) : link.url,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: ow.colors.text),
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

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.text, this.shortcut);

  final String text;
  final String shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(text)),
        if (shortcut.isNotEmpty)
          Text(
            shortcut,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// What the command line tracker reads from a session's screen.
class _SessionScreen implements LineScreen {
  _SessionScreen(this.session);

  final TerminalSession session;

  @override
  int? get cursorRow => session.cursorCell()?.row;

  @override
  ({String text, String after})? typedFrom(int row) {
    final t = session.typedSince(start: CellPos(row: row, col: 0));
    return t == null ? null : (text: t.text, after: t.after);
  }
}
