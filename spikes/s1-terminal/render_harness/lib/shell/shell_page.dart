// Spike S1.5: interactive input. A real shell (or the key log) on the
// libghostty-vt engine, with keyboard, IME, paste, mouse and a key bar for
// soft keyboards. Manual checklist: docs/spikes/S1-terminal.md.

import 'dart:convert' show jsonEncode;
import 'dart:io' show Platform, exit;
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/shell.dart';
import '../src/rust/api/term.dart' show nowMicros;
import '../term/frame.dart';
import '../term/palette.dart';
import '../term/renderer.dart';
import 'key_bar.dart';
import 'keys.dart';

/// Program name of the key log backend (`shell.rs` KEY_LOG).
const keyLog = 'keylog';

/// Spike S2: type, then flood, measure and exit (`S2RESULT {json}`).
const _autorun = bool.fromEnvironment('S2_AUTORUN');

class ShellPage extends StatefulWidget {
  const ShellPage({super.key, required this.program});

  /// '' for the login shell, [keyLog] for the key log.
  final String program;

  @override
  State<ShellPage> createState() => ShellPageState();
}

class ShellPageState extends State<ShellPage>
    with SingleTickerProviderStateMixin, TextInputClient {
  late final TerminalRenderer _renderer = TerminalRenderer(
    metrics: CellMetrics.measure(devicePixelRatio: _devicePixelRatio()),
    palette: TermPalette.dark,
    mode: RenderMode.atlas,
    devicePixelRatio: _devicePixelRatio(),
  );
  late final Ticker _ticker = createTicker(_onTick);
  final FocusNode _focus = FocusNode(debugLabel: 'terminal');
  final GlobalKey _gridKey = GlobalKey();

  ShellSession? _session;
  String? _error;
  int _cols = 0;
  int _rows = 0;

  // What the program asked for, from the last frame.
  bool _mouseTracking = false;
  bool _bracketedPaste = false;
  bool _reportAllKeys = false;
  bool _exited = false;
  String _title = '';

  // Input method state. The editing value is a fixed placeholder so that
  // soft keyboards always have something to delete: a shorter value means
  // Backspace, extra text is input (see [updateEditingValue]).
  static const _placeholder = '  ';
  static const _idle = TextEditingValue(
    text: _placeholder,
    selection: TextSelection.collapsed(offset: _placeholder.length),
  );
  TextInputConnection? _input;
  TextEditingValue _value = _idle;
  String _composing = '';

  /// Ctrl/Alt latched from the key bar for the next key or character.
  int _sticky = 0;

  /// Keys whose press went to the encoder, so their release does too.
  final Set<int> _encoderKeys = {};
  bool _optionAsAlt = false;
  bool _keyBar = Platform.isAndroid || Platform.isIOS;

  // Pointer state.
  int _buttons = 0;
  double _scrollPixels = 0;

  // Key-to-paint latency: input sent → frame with its echo painted.
  final List<int> _echoUs = [];

  // Key log only: modes injected as if the program had set them.
  final Map<String, bool> _logModes = {};
  int _kittyFlags = 0;

  /// For the integration test (integration_test/input_test.dart).
  @visibleForTesting
  ShellSession? get session => _session;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    createShell(program: widget.program, cols: 80, rows: 24, scrollback: 10000)
        .then((session) {
          if (!mounted) return;
          final m = _renderer.metrics;
          session.setCellPixels(width: m.width, height: m.height);
          setState(() => _session = session);
          if (_cols > 0) session.resize(cols: _cols, rows: _rows);
          _ticker.start();
          _focus.requestFocus();
          if (_autorun) _runAutomatically();
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  int _framesWithOutput = 0;

  /// The S2 measurement through the whole pipeline (keyboard → SSH →
  /// libghostty-vt → Flutter paint): echo of typed keys at a human pace,
  /// then a large output.
  Future<void> _runAutomatically() async {
    final session = _session!;
    await Future<void>.delayed(const Duration(seconds: 2));
    _echoUs.clear();
    const text = 'echo openward-s2-latency ';
    final rng = math.Random(42);
    for (var i = 0; i < 150; i++) {
      await Future<void>.delayed(Duration(milliseconds: 60 + rng.nextInt(121)));
      session.text(text: text[i % text.length]);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    final echo = _summary(_echoUs, 1e3);
    // ^U: drop the typed line.
    session.key(
      hidUsage: 0x00070018,
      kind: KeyKind.down,
      mods: Mods.ctrl,
      text: 'u',
      unshifted: 0x75,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final build = <int>[], raster = <int>[];
    var frozen = 0;
    void onTimings(List<FrameTiming> timings) {
      for (final t in timings) {
        build.add(t.buildDuration.inMicroseconds);
        raster.add(t.rasterDuration.inMicroseconds);
        if (t.totalSpan.inMilliseconds > 100) frozen++;
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);
    const mib = 100;
    _framesWithOutput = 0;
    final sw = Stopwatch()..start();
    session.text(
      text:
          "head -c ${mib * 1048576} /dev/zero | tr '\\0' x | fold -w 200; "
          r'echo S2-$((40+2))-END'
          '\n',
    );
    while (!session.screenText().contains('S2-42-END') &&
        sw.elapsed < const Duration(minutes: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final seconds = sw.elapsed.inMicroseconds / 1e6;
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    final result = {
      'kind': 'ssh-terminal',
      'program': widget.program.replaceAll(RegExp(r'\?key=.*'), ''),
      'echo_ms': echo,
      'flood_mib': mib,
      'flood_seconds': seconds,
      'flood_mib_s': mib * 201 / 200 / seconds,
      'flood_fps': _framesWithOutput / seconds,
      'build_ms': _summary(build, 1e3),
      'raster_ms': _summary(raster, 1e3),
      'frozen_frames_over_100ms': frozen,
      'cols': _cols,
      'rows': _rows,
    };
    // ignore: avoid_print
    print('S2RESULT ${jsonEncode(result)}');
    exit(0);
  }

  static Map<String, num> _summary(List<int> samples, num divisor) {
    if (samples.isEmpty) return const {};
    final s = [...samples]..sort();
    num at(double q) => s[((s.length - 1) * q).round()] / divisor;
    return {
      'p50': at(0.5),
      'p95': at(0.95),
      'max': s.last / divisor,
      'n': s.length,
    };
  }

  @override
  void dispose() {
    _ticker.dispose();
    _input?.close();
    _focus.dispose();
    _renderer.dispose();
    _session?.dispose();
    super.dispose();
  }

  static double _devicePixelRatio() {
    final views = PlatformDispatcher.instance.views;
    return views.isEmpty ? 2 : views.first.devicePixelRatio;
  }

  // ---------------------------------------------------------------- frames

  void _onTick(Duration _) {
    final session = _session;
    final batch = session?.poll();
    if (batch == null) return;
    _framesWithOutput++;
    final before = _renderer.cursor;
    _renderer.apply(decodeFrame(batch.frame));
    final sent = batch.inputMicros.toInt();
    if (sent != 0) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _echoUs.add(nowMicros().toInt() - sent);
        if (_echoUs.length > 500) _echoUs.removeAt(0);
      });
    }
    final after = _renderer.cursor;
    if (before?.row != after?.row || before?.col != after?.col) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _updateImeRects());
    }
    if (batch.mouseTracking != _mouseTracking ||
        batch.bracketedPaste != _bracketedPaste ||
        batch.reportAllKeys != _reportAllKeys ||
        batch.exited != _exited ||
        batch.title != _title ||
        sent != 0) {
      setState(() {
        _mouseTracking = batch.mouseTracking;
        _bracketedPaste = batch.bracketedPaste;
        _reportAllKeys = batch.reportAllKeys;
        _exited = batch.exited;
        _title = batch.title;
      });
    }
  }

  void _layout(BoxConstraints c) {
    final m = _renderer.metrics;
    final cols = math.max(10, (c.maxWidth / m.width).floor());
    final rows = math.max(4, (c.maxHeight / m.height).floor());
    if (cols == _cols && rows == _rows) return;
    _cols = cols;
    _rows = rows;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _session?.resize(cols: cols, rows: rows);
      _updateImeRects();
    });
  }

  // -------------------------------------------------------------- keyboard

  void _sendKey(int hid, {int mods = 0, String text = '', int unshifted = 0}) {
    final session = _session;
    if (session == null) return;
    final all = mods | _takeSticky();
    session.key(
      hidUsage: hid,
      kind: KeyKind.down,
      mods: all,
      text: text,
      unshifted: unshifted,
    );
    session.key(
      hidUsage: hid,
      kind: KeyKind.up,
      mods: all,
      text: '',
      unshifted: unshifted,
    );
  }

  int _takeSticky() {
    final s = _sticky;
    if (s != 0) setState(() => _sticky = 0);
    return s;
  }

  /// Text from the IME, a soft keyboard or the key bar.
  void _sendText(String text) {
    final session = _session;
    if (session == null || text.isEmpty) return;
    if (_sticky == 0) {
      session.text(text: text);
      return;
    }
    // A latched Ctrl/Alt applies to the first character, as a key event.
    final first = String.fromCharCode(text.runes.first);
    _sendKey(
      hidForChar(first),
      text: first,
      unshifted: first.toLowerCase().runes.first,
    );
    final rest = text.substring(first.length);
    if (rest.isNotEmpty) session.text(text: rest);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final session = _session;
    if (session == null) return KeyEventResult.ignored;
    // While composing, keys belong to the input method (candidate
    // selection, commit). macOS never even shows them to the framework.
    if (_composing.isNotEmpty) return KeyEventResult.ignored;
    final hid = event.physicalKey.usbHidUsage;

    if (event is KeyUpEvent) {
      if (!_encoderKeys.remove(hid)) return KeyEventResult.ignored;
      session.key(
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
    // Cmd+key are app shortcuts on Apple platforms, never terminal input.
    if (isApple && mods & Mods.superKey != 0) return KeyEventResult.ignored;

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
        (_reportAllKeys && printable);
    // Everything else is text: let the input method deliver it, so dead
    // keys, compose sequences and IMEs work.
    if (!toEncoder) return KeyEventResult.ignored;

    session.key(
      hidUsage: hid,
      kind: event is KeyRepeatEvent ? KeyKind.repeat : KeyKind.down,
      mods: mods | _takeSticky(),
      text: char,
      unshifted: unshiftedCodepoint(event.logicalKey),
    );
    _encoderKeys.add(hid);
    return KeyEventResult.handled;
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
    final session = _session;
    if (text == null || text.isEmpty || session == null || !mounted) return;
    if (session.paste(text: text, allowUnsafe: false)) return;
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
                  style: TextStyle(fontFamily: _renderer.metrics.fontFamily),
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
    if (ok == true) session.paste(text: text, allowUnsafe: true);
    _focus.requestFocus();
  }

  // ---------------------------------------------------------- input method

  void _onFocusChange() {
    final has = _focus.hasFocus;
    _session?.focus(gained: has);
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

  void _resetEditingState() {
    _value = _idle;
    _input?.setEditingState(_value);
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
    _sendText(text.substring(common));
    _resetEditingState();
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

  /// Where the IME should put its candidate window: at the cursor.
  void _updateImeRects() {
    final input = _input;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (input == null || !input.attached || box == null || !box.hasSize) {
      return;
    }
    final m = _renderer.metrics;
    final c = _renderer.cursor;
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

  void _onPointerDown(PointerDownEvent e) {
    _focus.requestFocus();
    _input?.show();
    _scrollPixels = 0;
    if (_isTouch(e) || !_mouseTracking) return;
    final pressed = e.buttons & ~_buttons;
    _buttons = e.buttons;
    _session?.pointer(
      action: PointerAction.down,
      button: _button(pressed),
      mods: hardwareMods(),
      x: e.localPosition.dx,
      y: e.localPosition.dy,
    );
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_isTouch(e)) {
      // Dragging the content down reveals history (positive lines).
      _scroll(e.localDelta.dy, e.localPosition);
      return;
    }
    if (!_mouseTracking) return;
    _session?.pointer(
      action: PointerAction.move,
      button: PointerButton.none,
      mods: hardwareMods(),
      x: e.localPosition.dx,
      y: e.localPosition.dy,
    );
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_isTouch(e)) return;
    final released = _buttons & ~e.buttons;
    _buttons = e.buttons;
    if (!_mouseTracking || released == 0) return;
    _session?.pointer(
      action: PointerAction.up,
      button: _button(released),
      mods: hardwareMods(),
      x: e.localPosition.dx,
      y: e.localPosition.dy,
    );
  }

  void _onHover(PointerHoverEvent e) {
    if (!_mouseTracking) return;
    _session?.pointer(
      action: PointerAction.move,
      button: PointerButton.none,
      mods: hardwareMods(),
      x: e.localPosition.dx,
      y: e.localPosition.dy,
    );
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
    final h = _renderer.metrics.height;
    _scrollPixels += pixels;
    final lines = (_scrollPixels / h).truncate();
    if (lines == 0) return;
    _scrollPixels -= lines * h;
    _session?.wheel(lines: lines, x: at.dx, y: at.dy, mods: hardwareMods());
  }

  // ---------------------------------------------------------------- key log

  void _toggleLogMode(String name, String on, String off) {
    final enabled = !(_logModes[name] ?? false);
    _logModes[name] = enabled;
    _session?.inject(bytes: (enabled ? on : off).codeUnits);
    _focus.requestFocus();
    setState(() {});
  }

  void _setKitty(int flags) {
    _kittyFlags = flags;
    // CSI = flags ; 1 u: replace the current kitty flags.
    _session?.inject(bytes: '\x1b[=$flags;1u'.codeUnits);
    _focus.requestFocus();
    setState(() {});
  }

  // ------------------------------------------------------------------- build

  String _status() {
    if (_error != null) return 'Error: $_error';
    if (_session == null) return 'Arrancando…';
    final parts = <String>[
      '$_cols×$_rows',
      if (_exited) 'proceso terminado',
      'ratón ${_mouseTracking ? 'app' : 'local'}',
      if (_bracketedPaste) 'pegado entre corchetes',
      if (_reportAllKeys) 'kitty: todas las teclas',
      if (_composing.isNotEmpty) 'componiendo',
    ];
    if (_echoUs.isNotEmpty) {
      final s = [..._echoUs]..sort();
      String at(double q) =>
          (s[((s.length - 1) * q).round()] / 1000).toStringAsFixed(1);
      parts.add('eco p50 ${at(0.5)} ms · p95 ${at(0.95)} ms (n=${s.length})');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final isLog = widget.program == keyLog;
    final m = _renderer.metrics;
    final cursor = _renderer.cursor;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isLog
              ? 'S1.5 · registro de teclas'
              : (_title.isEmpty ? 'S1.5 · shell' : _title),
        ),
        actions: [
          if (isLog)
            PopupMenuButton<void>(
              tooltip: 'Modos que pediría un programa',
              icon: const Icon(Icons.tune),
              itemBuilder: (context) => [
                for (final (name, on, off) in const [
                  (
                    'DECCKM (cursor en modo aplicación)',
                    '\x1b[?1h',
                    '\x1b[?1l',
                  ),
                  (
                    'Ratón SGR con arrastre (1002+1006)',
                    '\x1b[?1002h\x1b[?1006h',
                    '\x1b[?1002l\x1b[?1006l',
                  ),
                  (
                    'Ratón: todo movimiento (1003)',
                    '\x1b[?1003h\x1b[?1006h',
                    '\x1b[?1003l\x1b[?1006l',
                  ),
                  (
                    'Pegado entre corchetes (2004)',
                    '\x1b[?2004h',
                    '\x1b[?2004l',
                  ),
                  ('Eventos de foco (1004)', '\x1b[?1004h', '\x1b[?1004l'),
                ])
                  CheckedPopupMenuItem(
                    checked: _logModes[name] ?? false,
                    onTap: () => _toggleLogMode(name, on, off),
                    child: Text(name),
                  ),
                const PopupMenuDivider(),
                for (final (flags, name) in const [
                  (0, 'Kitty: desactivado'),
                  (1, 'Kitty: desambiguar (1)'),
                  (11, 'Kitty: todas las teclas + soltar (1|2|8)'),
                ])
                  CheckedPopupMenuItem(
                    checked: _kittyFlags == flags,
                    onTap: () => _setKitty(flags),
                    child: Text(name),
                  ),
              ],
            ),
          if (Platform.isMacOS)
            Row(
              children: [
                const Text('Opción = Alt'),
                Switch(
                  value: _optionAsAlt,
                  onChanged: (v) {
                    setState(() => _optionAsAlt = v);
                    _session?.setOptionAsAlt(enabled: v);
                    _focus.requestFocus();
                  },
                ),
              ],
            ),
          IconButton(
            tooltip: 'Barra de teclas',
            isSelected: _keyBar,
            icon: const Icon(Icons.keyboard_alt_outlined),
            onPressed: () {
              setState(() => _keyBar = !_keyBar);
              _focus.requestFocus();
            },
          ),
          IconButton(
            tooltip: 'Pegar',
            icon: const Icon(Icons.content_paste),
            onPressed: _paste,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: _renderer.palette.background,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _layout(constraints);
                  return Focus(
                    focusNode: _focus,
                    autofocus: true,
                    onKeyEvent: _onKey,
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
                            TerminalView(
                              key: _gridKey,
                              renderer: _renderer,
                              cols: _cols,
                              rows: _rows,
                              scaleToFit: false,
                            ),
                            if (_composing.isNotEmpty && cursor != null)
                              Positioned(
                                left: cursor.col * m.width,
                                top: cursor.row * m.height,
                                child: _ComposingText(
                                  text: _composing,
                                  renderer: _renderer,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_keyBar)
            KeyBar(
              sticky: _sticky,
              onKey: (hid) => _sendKey(hid),
              onText: _sendText,
              onToggle: (mod) => setState(() => _sticky ^= mod),
              onPaste: _paste,
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.black,
            child: Text(
              _status(),
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
