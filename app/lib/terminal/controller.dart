import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/connection.dart';
import '../history/line_tracker.dart';
import '../src/rust/api/session.dart';
import 'frame.dart';
import 'palette.dart';
import 'renderer.dart';

export '../core/connection.dart' show ConnectionController, Phase;

/// One terminal tab: the Rust session, its renderer and what the session
/// reported. Lives as long as the tab, visible or not.
class TerminalController extends ConnectionController {
  TerminalController({
    required super.app,
    required super.label,
    super.hostId,
    super.target,
    int scrollback = 0,
  }) : session = app.terminal(cols: 80, rows: 24, scrollback: scrollback) {
    _wakes = session.watch().listen((_) => _onWake());
  }

  /// A recording played back into `session` (its player's): drawn like
  /// any terminal, never connected nor typed into.
  TerminalController.playback({
    required super.app,
    required super.label,
    required this.session,
  }) {
    _wakes = session.watch().listen((_) => _onWake());
  }

  /// Set by the user (rename); wins over [label] and the program's title.
  String? customTitle;

  final TerminalSession session;

  // From the last frame.
  String title = '';
  bool mouseTracking = false;
  bool bracketedPaste = false;
  bool reportAllKeys = false;

  /// DECKPAM (with mode 1035 off): the keypad goes to the encoder.
  bool keypadApplication = false;

  /// `0xRRGGBB` the program set for itself (OSC 10, 11, 12), over the
  /// theme's; null where it set nothing.
  ({int? foreground, int? background, int? cursor}) programColors = (
    foreground: null,
    background: null,
    cursor: null,
  );

  /// A full-screen program (an editor, a pager) is on view.
  bool altScreen = false;

  /// What is being typed at the prompt, for the command history.
  final LineTracker line = LineTracker();

  /// The find bar is open, and what it shows.
  bool findOpen = false;
  String findText = '';
  int findTotal = 0;

  /// 1-based from the newest match; null before the first step.
  int? findSelected;

  /// The search is still going through the history.
  bool findSearching = false;

  /// Extra font size for this tab only (⌘+ and ⌘−).
  double zoom = 0;

  /// BELs so far, for the flash; and one rang while the tab was hidden.
  int bells = 0;
  bool bellUnseen = false;

  /// The program (or the default) wants a blinking cursor.
  bool cursorBlinks = false;

  /// Set by the visible pane: gives it the keyboard back (after the find
  /// bar, say).
  VoidCallback? focusTerminal;

  /// Set by the visible pane: there is something new to draw, so it asks
  /// for frames again (it stops while nothing changes).
  VoidCallback? wakePane;

  /// The core says when the screen changed after the last look.
  StreamSubscription<bool>? _wakes;

  /// Its size in columns and rows, as the visible pane lays it out.
  final grid = ValueNotifier<(int, int)>((80, 24));

  bool _shown = false;

  TerminalRenderer? _renderer;

  /// The font family asked for the renderer: null is the platform's, which
  /// its metrics name by what it resolves to.
  String? _fontFamily;

  /// The theme's palette as the engine has it (programs ask for it).
  TermPalette? _theme;

  /// [_theme] with what the program set over it, and what it was made of.
  TermPalette? _painted;
  Object? _paintedOf;

  /// `theme`, with the program's own foreground, background and cursor.
  TermPalette _withProgram(TermPalette theme) {
    final p = programColors;
    if (p.foreground == null && p.background == null && p.cursor == null) {
      return theme;
    }
    final of = (theme, p);
    if (_paintedOf == of) return _painted!;
    Color color(int rgb) => Color(0xFF000000 | rgb);
    final bg = p.background == null ? theme.background : color(p.background!);
    _paintedOf = of;
    return _painted = TermPalette(
      dark: TermPalette.luminance(bg) < 0.4,
      foreground: p.foreground == null
          ? theme.foreground
          : color(p.foreground!),
      background: bg,
      cursor: p.cursor == null ? theme.cursor : color(p.cursor!),
      selection: theme.selection,
      ansi16: theme.ansi16,
    );
  }

  /// The renderer in use, if the tab has been shown.
  TerminalRenderer? get currentRenderer => _renderer;
  Timer? _background;

  /// What the tab shows.
  String get displayTitle {
    final custom = customTitle;
    if (custom != null && custom.isNotEmpty) return custom;
    return isLocal && title.isNotEmpty ? title : label;
  }

  @override
  Stream<SessionEvent> open() {
    final hostId = this.hostId;
    final target = this.target;
    return hostId != null
        ? app.connect(session: session, hostId: hostId)
        : target != null
        ? app.connectAddress(
            session: session,
            address: target.address,
            user: target.user,
            port: target.port,
          )
        : app.openLocal(session: session);
  }

  @override
  void stop() => session.close();

  /// The words of the line that marks where a new shell starts after a
  /// cut, set by the pane (it knows the language): when, and after how
  /// long away.
  String Function(DateTime at, Duration away)? comebackLine;

  @override
  void onEvent(SessionEvent e) {
    final down = phase == Phase.reconnecting;
    final since = stalledSince ?? reconnectingSince;
    super.onEvent(e);
    // About to open a new shell after a cut: the old one is gone. Not in
    // tmux, which draws the session as it was (or a new one) itself.
    final inTmux = switch (persistent?.state) {
      PersistenceKind.new_ || PersistenceKind.resumed => true,
      _ => false,
    };
    final line = comebackLine;
    if (down &&
        !inTmux &&
        line != null &&
        e.kind == SessionEventKind.stage &&
        e.stage?.stage == StageKind.openingShell) {
      final now = DateTime.now();
      final text = line(
        now,
        since == null ? Duration.zero : now.difference(since),
      );
      session.note(text: '\r\n\x1b[2m── $text ──\x1b[0m\r\n');
    }
  }

  /// The renderer for this pixel density, font, palette and contrast, made
  /// anew (and the screen asked for again) when any of them changes.
  TerminalRenderer renderer(
    double devicePixelRatio, {
    required double fontSize,
    required TermPalette palette,
    String? fontFamily,
    double lineHeight = 1.2,
    double minimumContrast = 1,
  }) {
    // The engine keeps the theme's; the screen is painted with what the
    // program set over it.
    if (!identical(_theme, palette)) {
      _theme = palette;
      session.setTheme(
        dark: palette.dark,
        foreground: TermPalette.rgb(palette.foreground),
        background: TermPalette.rgb(palette.background),
        cursor: TermPalette.rgb(palette.cursor),
        palette: [
          for (var i = 0; i < 256; i++)
            TermPalette.rgb(palette.resolve(0x02000000 | i, foreground: true)),
        ],
      );
    }
    palette = _withProgram(palette);
    final current = _renderer;
    if (current != null &&
        current.devicePixelRatio == devicePixelRatio &&
        current.metrics.fontSize == fontSize &&
        current.metrics.lineHeight == lineHeight &&
        _fontFamily == fontFamily &&
        current.minimumContrast == minimumContrast &&
        identical(current.palette, palette)) {
      return current;
    }
    current?.dispose();
    _fontFamily = fontFamily;
    final metrics = CellMetrics.measure(
      fontSize: fontSize,
      lineHeight: lineHeight,
      devicePixelRatio: devicePixelRatio,
      family: fontFamily,
    );
    session.setCellPixels(width: metrics.width, height: metrics.height);
    session.redraw();
    return _renderer = TerminalRenderer(
      metrics: metrics,
      palette: palette,
      devicePixelRatio: devicePixelRatio,
      minimumContrast: minimumContrast,
    );
  }

  // ------------------------------------------------------------------ find

  void openFind() {
    findOpen = true;
    _notify();
  }

  /// Looks for `text` through the screen and the history.
  void find(String text) {
    findText = text;
    session.search(needle: text);
  }

  /// The next match towards older output, or newer.
  void findStep({bool older = true}) {
    if (findText.isEmpty) return;
    session.searchStep(older: older);
  }

  void closeFind() {
    findOpen = false;
    findText = '';
    findTotal = 0;
    findSelected = null;
    findSearching = false;
    session.endSearch();
    _renderer?.setSearch(const []);
    _notify();
    focusTerminal?.call();
  }

  // ------------------------------------------------------------------ zoom

  void zoomBy(double step) {
    zoom = (zoom + step).clamp(-6, 24);
    _notify();
  }

  void resetZoom() {
    if (zoom == 0) return;
    zoom = 0;
    _notify();
  }

  /// Applies what changed since the last poll. Returns true if anything did.
  bool poll() {
    final renderer = _renderer;
    if (renderer == null || isDisposed) return false;
    final f = session.poll();
    if (f == null) return false;
    final frame = () {
      try {
        return decodeFrame(f.frame);
      } on Object {
        return null;
      }
    }();
    if (frame == null) {
      // A bug, never the server's doing. The core already sent this
      // damage: without a full frame its rows would stay as they were.
      session.redraw();
      return false;
    }
    renderer.apply(frame);
    renderer.setSelection([
      for (final r in f.selection) (row: r.row, start: r.start, end: r.end),
    ]);
    final search = f.search;
    renderer.setSearch([
      for (final h in search?.hits ?? const <SearchHitView>[])
        (row: h.row, start: h.start, end: h.end, selected: h.selected),
    ]);
    var changed = false;
    if (search != null &&
        (search.total != findTotal ||
            search.selected != findSelected ||
            search.searching != findSearching)) {
      findTotal = search.total;
      findSelected = search.selected;
      findSearching = search.searching;
      changed = true;
    }
    if (f.bell) {
      bells++;
      if (!_shown) bellUnseen = true;
      changed = true;
    }
    altScreen = f.altScreen;
    if (f.cursorBlinks != cursorBlinks) {
      cursorBlinks = f.cursorBlinks;
      changed = true;
    }
    if (changed) _notify();
    if (f.title != title ||
        f.mouseTracking != mouseTracking ||
        f.bracketedPaste != bracketedPaste ||
        f.reportAllKeys != reportAllKeys ||
        f.keypadApplication != keypadApplication ||
        f.programForeground != programColors.foreground ||
        f.programBackground != programColors.background ||
        f.programCursor != programColors.cursor) {
      title = f.title;
      mouseTracking = f.mouseTracking;
      bracketedPaste = f.bracketedPaste;
      reportAllKeys = f.reportAllKeys;
      keypadApplication = f.keypadApplication;
      programColors = (
        foreground: f.programForeground,
        background: f.programBackground,
        cursor: f.programCursor,
      );
      _notify();
    }
    return true;
  }

  /// A visible tab is polled by its pane, every frame while something
  /// changes; a hidden one only reads its title and bell, at most a few
  /// times a second and only when something changed, and gets the whole
  /// screen when it shows again.
  set visible(bool visible) {
    _shown = visible;
    if (visible && bellUnseen) {
      bellUnseen = false;
      // Shown from a pane's build: tell the tab after it.
      SchedulerBinding.instance.addPostFrameCallback((_) => _notify());
    }
    _background?.cancel();
    _background = null;
    if (visible && !isDisposed) session.redraw();
  }

  /// Compresses the history once the terminal has been quiet a while.
  Timer? _quiet;

  void _onWake() {
    if (isDisposed) return;
    _quiet?.cancel();
    _quiet = Timer(const Duration(minutes: 1), () {
      if (!isDisposed) session.compressHistory();
    });
    if (_shown) {
      wakePane?.call();
    } else {
      _background ??= Timer(const Duration(milliseconds: 250), _pollMeta);
    }
  }

  void _pollMeta() {
    _background = null;
    if (isDisposed || _shown) return;
    final m = session.pollMeta();
    var changed = false;
    if (m.title != title) {
      title = m.title;
      changed = true;
    }
    if (m.bell) {
      bells++;
      bellUnseen = true;
      changed = true;
    }
    if (changed) _notify();
  }

  void _notify() => notify();

  @override
  void dispose() {
    _wakes?.cancel();
    _quiet?.cancel();
    _background?.cancel();
    grid.dispose();
    session.close();
    session.dispose();
    _renderer?.dispose();
    super.dispose();
  }
}
