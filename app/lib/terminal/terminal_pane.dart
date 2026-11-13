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

import '../core/providers.dart';
import '../core/settings.dart';
import '../history/history.dart';
import '../history/line_tracker.dart';
import '../history/suggest.dart';
import '../l10n/l10n.dart';
import '../snippets/palette.dart' show showSnippetPalette;
import '../snippets/snippets.dart' show snippetsProvider;
import '../src/rust/api/session.dart';
import '../tabs/connection_motion.dart' show comebackWords, moshFallbackWords;
import '../ui/themes.dart' show hostTerminal;
import '../ui/tokens.dart';
import 'controller.dart';
import 'highlight.dart';
import 'key_bar.dart';
import 'keys.dart';
import 'links.dart';
import 'paste.dart';
import 'renderer.dart';
import 'send_target.dart';
import 'visible_text.dart';

class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({
    super.key,
    required this.controller,
    this.autofocus = true,
    this.mirrors,
    this.paneMenu,
    this.readOnly = false,
  });

  final TerminalController controller;
  final bool autofocus;

  /// A recording played back: it is drawn, selected, searched and copied,
  /// never typed into, and keeps its own size.
  final bool readOnly;

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
    with SingleTickerProviderStateMixin, TextInputClient
    implements KeyBarTarget {
  late final Ticker _ticker = createTicker(_onTick);
  final FocusNode focusNode = FocusNode(debugLabel: 'terminal');
  final GlobalKey _gridKey = GlobalKey();

  TerminalController get _c => widget.controller;
  TerminalSession get _session => widget.controller.session;

  /// The program follows the mouse: never in a recording, whose program is
  /// not there.
  bool get _programMouse => !widget.readOnly && _c.mouseTracking;
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

  OptionAltChoice _optionAsAlt = OptionAltChoice.off;

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
    _c.wakePane = _wake;
    _c.visible = true;
    _c.focusTerminal = _focusSoon;
    if (!widget.readOnly) _c.keyBar = this;
    _wake();
    // Its language for the line that marks a new shell after a cut.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = context.l10n;
      _c.comebackLine = (at, away) => comebackWords(l, at, away);
      _c.moshFallbackLine = (why) => moshFallbackWords(l, why);
    });
    final settings = ref.read(settingsProvider);
    _optionAsAlt = settings.optionAsAlt;
    _session.setOptionAsAlt(which: _optionAlt(_optionAsAlt));
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
    _c.setHighlighter(
      highlighterFor(on: settings.highlight, rules: settings.highlightRules),
    );
    // A host with colors of its own (or its groups'), whatever the theme.
    final hostId = _c.hostId;
    final own = hostId == null
        ? ''
        : ref.watch(
            libraryProvider.select((l) => l.host(hostId)?.terminalScheme ?? ''),
          );
    final r = _c.renderer(
      MediaQuery.devicePixelRatioOf(context),
      fontSize: (settings.fontSize + _c.zoom).clamp(6, 48),
      palette: hostTerminal(own, settings) ?? ow.terminal,
      fontFamily: ow.fonts.terminal,
      lineHeight: settings.lineHeight,
      minimumContrast: settings.minimumContrast ? ow.minimumContrast : 1,
    );
    // Another font, theme or density: the whole screen to draw again.
    // Whether it has the keyboard, told after the frame: the renderer may
    // be another pane's still (a terminal moved), and telling it now would
    // rebuild that one mid-build.
    if (!identical(r, _renderer)) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) r.setFocused(focusNode.hasFocus);
        _wake();
      });
    }
    return _renderer = r;
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
      if (oldWidget.controller.wakePane == _wake) {
        oldWidget.controller.wakePane = null;
      }
      if (oldWidget.controller.keyBar == this) {
        oldWidget.controller.keyBar = null;
      }
      _setGhost(null);
      _c.wakePane = _wake;
      _c.visible = true;
      _c.focusTerminal = _focusSoon;
      if (!widget.readOnly) _c.keyBar = this;
      _wake();
      _applyCursor(ref.read(settingsProvider));
      _cols = _rows = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _resize?.cancel();
    _blink?.cancel();
    _autoScroll?.cancel();
    _input?.close();
    focusNode.dispose();
    if (_c.wakePane == _wake) _c.wakePane = null;
    _c.visible = false;
    if (_c.focusTerminal == _focusSoon) _c.focusTerminal = null;
    if (_c.keyBar == this) _c.keyBar = null;
    _touchHold?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- frames

  /// Frames in a row with nothing new.
  int _idleTicks = 0;

  /// It asks for frames: something changed and is being drawn.
  @visibleForTesting
  bool get polling => _ticker.isActive;

  /// There is something to draw: frames until the core has nothing new.
  void _wake() {
    if (!mounted) return;
    _idleTicks = 0;
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration _) {
    final before = _renderer?.cursor;
    if (!_c.poll()) {
      // An idle terminal asks for no frames until the core says otherwise.
      if (++_idleTicks >= 2) _ticker.stop();
      return;
    }
    _idleTicks = 0;
    final after = _renderer?.cursor;
    if (before?.row != after?.row || before?.col != after?.col) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _updateImeRects());
    }
    _suggest();
  }

  // ------------------------------------------------------------ suggestions

  /// The rest of the command line shown dimmed, or null.
  String? _ghost;

  /// Works out the suggestion for what the screen shows now: none in the
  /// alternate screen, where a secret is asked, with the history off,
  /// while broadcasting, or while the shell suggests on its own.
  void _suggest() {
    final s = ref.read(settingsProvider);
    final line = _c.line;
    final typed = line.plainTyped;
    String? rest;
    if (s.autocomplete &&
        s.commandHistory &&
        !widget.readOnly &&
        !_c.altScreen &&
        focusNode.hasFocus &&
        (widget.mirrors?.call() ?? const []).isEmpty &&
        typed != null &&
        typed.isNotEmpty &&
        line.showsTyped(_screen)) {
      final place = historyPlace(_c);
      rest = suggestFor(typed, [
        SuggestionSource(
          ref
              .read(historyProvider)
              .where((e) => historyIsOwnHere(e, place, historyBinding(_c)))
              .map((e) => e.command),
        ),
        SuggestionSource(
          ref
              .read(snippetsProvider)
              .where(
                (v) =>
                    !v.requiresReview &&
                    v.variables.asked.isEmpty &&
                    v.variables.builtins.isEmpty,
              )
              .map((v) => v.spec.script),
        ),
        const SuggestionSource(commonCommands, minTyped: 2),
      ]);
    }
    _setGhost(rest);
  }

  void _setGhost(String? rest) {
    final cursor = _renderer?.cursor;
    if (rest == null || cursor == null) {
      _ghost = null;
      _renderer?.setGhost(null);
      return;
    }
    _ghost = rest;
    _renderer?.setGhost((row: cursor.row, col: cursor.col, text: rest));
  }

  /// → or End with a suggestion shown: it is typed.
  void _takeGhost(String rest) {
    _suggest();
    if (_ghost != rest || !TerminalSendTarget(_c).current) return;
    _setGhost(null);
    _c.line.text(rest, _screen);
    _session.text(text: rest);
  }

  /// The size on its way to the core. Dragging a divider or the window
  /// changes it every frame, and each change reflows the history and sends
  /// the server a window change, which makes the shell redraw its prompt:
  /// the size goes once it stops changing for a moment.
  Timer? _resize;

  void _layout(BoxConstraints c, TerminalRenderer r) {
    final m = r.metrics;
    final cols = math.max(10, (c.maxWidth / m.width).floor());
    final rows = math.max(4, (c.maxHeight / m.height).floor());
    if (cols == _cols && rows == _rows) return;
    final first = _cols == 0;
    _cols = cols;
    _rows = rows;
    void apply() {
      if (!mounted || widget.readOnly) return;
      _session.resize(cols: cols, rows: rows);
      _updateImeRects();
    }

    _resize?.cancel();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // What the pane says it measures follows the drag as it happens.
      widget.controller.grid.value = (cols, rows);
      if (first) apply();
    });
    if (!first) _resize = Timer(const Duration(milliseconds: 120), apply);
  }

  // -------------------------------------------------------------- keyboard

  /// This session and, while broadcasting, the others that receive.
  List<TerminalController> get _targets => [
    _c,
    for (final c in widget.mirrors?.call() ?? const <TerminalController>[])
      if (!c.isDisposed) c,
  ];

  void _key({
    required int hidUsage,
    required KeyKind kind,
    required int mods,
    required String text,
    required int unshifted,
  }) {
    final here = _c;
    for (final c in _targets) {
      if (kind != KeyKind.up) {
        _track(c, hidUsage, mods, text, record: identical(c, here));
      }
      c.session.key(
        hidUsage: hidUsage,
        kind: kind,
        mods: mods,
        text: text,
        unshifted: unshifted,
      );
    }
  }

  /// The screen as the command line tracker reads it.
  LineScreen get _screen => _SessionScreen(_session);

  /// Follows the command line, and at Enter keeps what ran in the history
  /// and marks it in the session's recording.
  void _track(
    TerminalController target,
    int hid,
    int mods,
    String text, {
    required bool record,
  }) {
    final line = target.line;
    final screen = _SessionScreen(target.session);
    final held = mods & (Mods.shift | Mods.ctrl | Mods.alt | Mods.superKey);
    if (hid != Hid.enter || held != 0) {
      line.key(hid, mods, text, screen);
      return;
    }
    final command = line.enterCommand(screen, altScreen: target.altScreen);
    if (command == null || !record) return;
    target.session.logCommand(command: command.text);
    if (ref.read(settingsProvider).commandHistory) {
      ref
          .read(historyProvider.notifier)
          .add(command.text, target, origin: command.origin);
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
    final rest = _ghost;
    if (rest != null &&
        event is KeyDownEvent &&
        mods & (Mods.shift | Mods.ctrl | Mods.alt | Mods.superKey) == 0 &&
        (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.end)) {
      _takeGhost(rest);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        !widget.readOnly &&
        _isPasteShortcut(event, mods)) {
      _paste();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && _isCopyShortcut(event, mods)) {
      _copy();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        macShortcuts &&
        mods & Mods.superKey != 0 &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _session.selectAll();
      return KeyEventResult.handled;
    }
    // Tabs, search and the like: the window's.
    if (isAppShortcut(event, mods)) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.ignored;

    final char = event.character ?? '';
    final printable = char.isNotEmpty && !isControlText(char);
    // On macOS, by which Option is held.
    final altIsMeta =
        !isApple ||
        switch (_optionAsAlt) {
          OptionAltChoice.off => false,
          OptionAltChoice.both => true,
          OptionAltChoice.left => mods & Mods.altRight == 0,
          OptionAltChoice.right => mods & Mods.altRight != 0,
        };
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
        (_c.reportAllKeys && printable) ||
        // DECKPAM: the program wants the keypad's own sequences.
        (_c.keypadApplication && isKeypadKey(hid));
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
    if (macShortcuts) return c && mods & Mods.superKey != 0;
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
    final key = macShortcuts ? '⌘' : l.ctrlShiftPrefix;
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
        if (!widget.readOnly)
          PopupMenuItem(
            value: _paste,
            height: 34,
            child: _MenuRow(l.paste, '${key}V'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _c.openFind,
          height: 34,
          child: _MenuRow(l.findEllipsis, '${key}F'),
        ),
        if (!widget.readOnly) ...[
          PopupMenuItem(
            value: () => showSnippetPalette(context),
            height: 34,
            child: _MenuRow(
              l.snippetsEllipsis,
              macShortcuts ? '⌘⇧S' : '${key}S',
            ),
          ),
          // What scrolled away, forgotten here; the program is not told.
          PopupMenuItem(
            key: const ValueKey('terminal.clearScrollback'),
            value: _session.clearHistory,
            height: 34,
            child: _MenuRow(l.clearScrollback, ''),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _session.selectAll,
          height: 34,
          child: _MenuRow(l.selectAllText, macShortcuts ? '⌘A' : ''),
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
    if (macShortcuts) return v && mods & Mods.superKey != 0;
    return (v && mods & Mods.ctrl != 0 && mods & Mods.shift != 0) ||
        (e.logicalKey == LogicalKeyboardKey.insert && mods & Mods.shift != 0);
  }

  // ------------------------------------------------------------------ paste

  Future<void> _paste() async {
    final here = TerminalSendTarget(_c);
    final also = [
      for (final c in widget.mirrors?.call() ?? <TerminalController>[])
        TerminalSendTarget(c),
    ];
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted || !here.current) return;
    if (also.isNotEmpty) return _pasteBroadcast(text, here, also);
    if (!hasHidden(text) && here.paste(text, allowUnsafe: false)) {
      here.controller.line.text(text, _SessionScreen(here.session));
      return;
    }
    final ok = await confirmPaste(
      context,
      text,
      fontFamily: _renderer?.metrics.fontFamily,
      destination: here.destination,
    );
    if (ok && here.paste(text, allowUnsafe: true)) {
      here.controller.line.text(text, _SessionScreen(here.session));
    }
    if (mounted) focusNode.requestFocus();
  }

  /// Names, sessions and shell generations are frozen before any await.
  Future<void> _pasteBroadcast(
    String text,
    TerminalSendTarget here,
    List<TerminalSendTarget> also,
  ) async {
    final choice = await confirmBroadcastPaste(
      context,
      text,
      here: here.destination,
      names: [here, ...also].map((s) => s.destination).toList(),
      fontFamily: _renderer?.metrics.fontFamily,
    );
    if (choice != null && mounted) {
      final targets = choice ? [here, ...also] : [here];
      for (final target in targets) {
        final sent = target.paste(text, allowUnsafe: true);
        if (sent) {
          target.controller.line.text(text, _SessionScreen(target.session));
        }
      }
    }
    if (mounted) focusNode.requestFocus();
  }

  // ---------------------------------------------------------- input method

  void _onFocusChange() {
    final has = focusNode.hasFocus;
    if (!_c.isDisposed) _session.focus(gained: has);
    _renderer?.setFocused(has);
    if (!has) _setGhost(null);
    if (has && !widget.readOnly) {
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
        // Android's keyboards compose whole words before handing them
        // over, which a shell needs at once (Tab, a single key for less):
        // as a visible password nothing composes, as Termux does. CJK
        // input methods then type Latin; docs/plan/movil.md.
        inputType: Platform.isAndroid
            ? TextInputType.visiblePassword
            : TextInputType.multiline,
        inputAction: Platform.isAndroid
            ? TextInputAction.done
            : TextInputAction.newline,
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
    var typed = text.substring(common);
    // Ctrl or Alt held on the phone's key bar: the first character goes
    // with them, as a key.
    if (typed.isNotEmpty && stickyMods.value != 0) {
      typed = _withSticky(typed);
    }
    if (typed.isNotEmpty) {
      for (final c in _targets) {
        c.line.text(typed, _SessionScreen(c.session));
        c.session.text(text: typed);
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

  // ------------------------------------------------------------- key bar

  @override
  void barKey(int hid, int mods) {
    if (widget.readOnly) return;
    _renderer?.setCursorOn(true);
    _sendKey(hid, mods: mods);
  }

  @override
  void barText(String text) {
    if (widget.readOnly) return;
    final typed = stickyMods.value != 0 ? _withSticky(text) : text;
    if (typed.isEmpty) return;
    for (final c in _targets) {
      c.line.text(typed, _SessionScreen(c.session));
      c.session.text(text: typed);
    }
  }

  @override
  Future<void> barPaste() => _paste();

  @override
  void barKeyboard({required bool show}) {
    if (show) {
      if (!focusNode.hasFocus) focusNode.requestFocus();
      _openInput();
    } else {
      _input?.close();
      _input = null;
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
  }

  /// Sends the first character of [typed] with the key bar's Ctrl or Alt
  /// and returns the rest. A letter goes as its key, so the encoder makes
  /// what the program asked for (Ctrl+C, Alt+B); anything else with Alt
  /// is Esc and the character, as `meta sends escape`.
  String _withSticky(String typed) {
    final mods = stickyMods.take();
    final first = String.fromCharCode(typed.runes.first);
    final rest = typed.substring(first.length);
    final hid = hidForChar(first);
    final upper = first != first.toLowerCase();
    if (hid != 0) {
      _sendKey(
        hid,
        mods: mods | (upper ? Mods.shift : 0),
        text: first,
        unshifted: first.toLowerCase().codeUnitAt(0),
      );
      return rest;
    }
    if (mods & Mods.alt != 0) {
      _sendKey(Hid.escape);
      return typed;
    }
    return typed;
  }

  // ---------------------------------------------------------------- touch

  /// Fingers on the terminal, where each is now.
  final Map<int, Offset> _touches = {};
  Offset _touchStart = Offset.zero;
  DateTime _touchAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _touchMoved = false;

  /// A long press started a selection, which the finger now drags.
  bool _touchSelecting = false;
  Timer? _touchHold;

  /// Two fingers apart this much at the last zoom step.
  double? _pinchFrom;

  void _touchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      _touchHold?.cancel();
      final [a, b] = _touches.values.toList();
      _pinchFrom = (a - b).distance;
      return;
    }
    if (_touches.length > 2) return;
    _touchStart = e.localPosition;
    _touchAt = DateTime.now();
    _touchMoved = false;
    _touchSelecting = false;
    _touchHold?.cancel();
    // Held still: select from there (a long press, as text fields do).
    _touchHold = Timer(kLongPressTimeout, () {
      if (_touchMoved || _touches.length != 1) return;
      HapticFeedback.selectionClick();
      _touchSelecting = true;
      _selecting = true;
      _session.selectPress(x: _touchStart.dx, y: _touchStart.dy);
      _session.selectDrag(
        x: _touchStart.dx,
        y: _touchStart.dy,
        rectangle: false,
      );
    });
  }

  void _touchMove(PointerMoveEvent e) {
    final before = _touches[e.pointer];
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2 && _pinchFrom != null) {
      final [a, b] = _touches.values.toList();
      final now = (a - b).distance;
      final from = _pinchFrom!;
      // A step of the font size every so much apart, as ⌘+ and ⌘-.
      if (from > 0 && (now / from > 1.15 || now / from < 0.87)) {
        _c.zoomBy(now > from ? 1 : -1);
        _pinchFrom = now;
      }
      return;
    }
    if (before == null || _touches.length != 1) return;
    if (_touchSelecting) {
      _session.selectDrag(
        x: e.localPosition.dx,
        y: e.localPosition.dy,
        rectangle: false,
      );
      return;
    }
    if (!_touchMoved && (e.localPosition - _touchStart).distance > kTouchSlop) {
      _touchMoved = true;
      _touchHold?.cancel();
    }
    // Dragging the content down reveals history (positive lines).
    if (_touchMoved) _scroll(e.localDelta.dy, e.localPosition);
  }

  void _touchUp(PointerUpEvent e) {
    _touches.remove(e.pointer);
    if (_touches.isNotEmpty) return;
    _touchHold?.cancel();
    if (_pinchFrom != null) {
      _pinchFrom = null;
      return;
    }
    if (_touchSelecting) {
      _touchSelecting = false;
      _selecting = false;
      _session.selectRelease(x: e.localPosition.dx, y: e.localPosition.dy);
      if (ref.read(settingsProvider).copyOnSelect) _copy();
      _contextMenu(e.position);
      return;
    }
    if (_touchMoved) return;
    if (DateTime.now().difference(_touchAt) > kLongPressTimeout) return;
    // A tap: a link opens; a selection goes; otherwise the keyboard.
    final link = _session.linkAt(x: e.localPosition.dx, y: e.localPosition.dy);
    if (link != null) {
      openTerminalLink(context, link.url);
      return;
    }
    if (_session.selectionText()?.isNotEmpty ?? false) {
      _session.clearSelection();
      return;
    }
    if (_programMouse) {
      _pointer(PointerAction.down, PointerButton.left, e.localPosition);
      _pointer(PointerAction.up, PointerButton.left, e.localPosition);
    }
    focusNode.requestFocus();
    if (!widget.readOnly) _openInput();
  }

  void _touchCancel(PointerCancelEvent e) {
    _touches.remove(e.pointer);
    if (_touches.isNotEmpty) return;
    _touchHold?.cancel();
    _pinchFrom = null;
    if (_touchSelecting) {
      _touchSelecting = false;
      _selecting = false;
    }
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
      _programMouse && !HardwareKeyboard.instance.isShiftPressed;

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

  void _onPointerDown(PointerDownEvent e) {
    _scrollPixels = 0;
    if (_isTouch(e)) return _touchDown(e);
    focusNode.requestFocus();
    final pressed = e.buttons & ~_buttons;
    _buttons = e.buttons;
    final link = _linkUrl;
    if (link != null && pressed & kPrimaryMouseButton != 0 && _linkModifier) {
      openTerminalLink(context, link);
      return;
    }
    if (!_toProgram) {
      if (pressed & kSecondaryMouseButton != 0) {
        // Pasting with a right click (an option): with Ctrl, the menu.
        if (ref.read(settingsProvider).rightClickPaste &&
            !widget.readOnly &&
            !HardwareKeyboard.instance.isControlPressed) {
          _paste();
        } else {
          _contextMenu(e.position);
        }
      } else if (pressed & kPrimaryMouseButton != 0) {
        _selecting = true;
        _session.selectPress(x: e.localPosition.dx, y: e.localPosition.dy);
      }
      return;
    }
    _pointer(PointerAction.down, _button(pressed), e.localPosition);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_isTouch(e)) return _touchMove(e);
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
    if (_programMouse) {
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
    // The history only: not the wheel, which a program in the alternate
    // screen (less, man) takes as arrows, and would lose the selection.
    _session.scrollHistory(lines: y < 0 ? lines : -lines);
    _session.selectDrag(
      x: _dragAt.dx,
      y: edge,
      rectangle: HardwareKeyboard.instance.isAltPressed,
    );
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_isTouch(e)) return _touchUp(e);
    final released = _buttons & ~e.buttons;
    _buttons = e.buttons;
    if (_selecting && released & kPrimaryMouseButton != 0) {
      _selecting = false;
      _autoScroll?.cancel();
      _autoScroll = null;
      _session.selectRelease(x: e.localPosition.dx, y: e.localPosition.dy);
      if (ref.read(settingsProvider).copyOnSelect) _copy();
      return;
    }
    if (!_programMouse || released == 0) return;
    _pointer(PointerAction.up, _button(released), e.localPosition);
  }

  void _onHover(PointerHoverEvent e) {
    _updateLink(e.localPosition);
    if (_programMouse) {
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
    if (widget.readOnly) {
      _session.scrollHistory(lines: lines);
    } else {
      _session.wheel(lines: lines, x: at.dx, y: at.dy, mods: hardwareMods());
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider.select((s) => s.optionAsAlt), (_, which) {
      _optionAsAlt = which;
      _session.setOptionAsAlt(which: _optionAlt(which));
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
                    : _programMouse
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.text,
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _touchCancel,
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
                          cursorLabel: context.l10n.terminalCursorLine,
                        ),
                        if (_link case final link?)
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: LinkTarget(link: link),
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

OptionAlt _optionAlt(OptionAltChoice c) => switch (c) {
  OptionAltChoice.off => OptionAlt.off,
  OptionAltChoice.both => OptionAlt.both,
  OptionAltChoice.left => OptionAlt.left,
  OptionAltChoice.right => OptionAlt.right,
};
