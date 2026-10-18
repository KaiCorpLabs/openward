import 'dart:async';

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
  }) : session = app.terminal(cols: 80, rows: 24, scrollback: scrollback);

  /// Set by the user (rename); wins over [label] and the program's title.
  String? customTitle;

  final TerminalSession session;

  // From the last frame.
  String title = '';
  bool mouseTracking = false;
  bool bracketedPaste = false;
  bool reportAllKeys = false;

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

  bool _shown = false;

  TerminalRenderer? _renderer;

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
    final current = _renderer;
    if (current != null &&
        current.devicePixelRatio == devicePixelRatio &&
        current.metrics.fontSize == fontSize &&
        current.metrics.lineHeight == lineHeight &&
        current.metrics.fontFamily ==
            (fontFamily ?? current.metrics.fontFamily) &&
        current.minimumContrast == minimumContrast &&
        identical(current.palette, palette)) {
      return current;
    }
    if (current == null || !identical(current.palette, palette)) {
      session.setTheme(
        dark: palette.dark,
        foreground: TermPalette.rgb(palette.foreground),
        background: TermPalette.rgb(palette.background),
      );
    }
    current?.dispose();
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
    renderer.apply(decodeFrame(f.frame));
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
        (search.total != findTotal || search.selected != findSelected)) {
      findTotal = search.total;
      findSelected = search.selected;
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
        f.reportAllKeys != reportAllKeys) {
      title = f.title;
      mouseTracking = f.mouseTracking;
      bracketedPaste = f.bracketedPaste;
      reportAllKeys = f.reportAllKeys;
      _notify();
    }
    return true;
  }

  /// A visible tab is polled every frame by its pane; a hidden one a few
  /// times a second, so its title stays current and damage does not pile up.
  set visible(bool visible) {
    _shown = visible;
    if (visible && bellUnseen) {
      bellUnseen = false;
      // Shown from a pane's build: tell the tab after it.
      SchedulerBinding.instance.addPostFrameCallback((_) => _notify());
    }
    _background?.cancel();
    _background = visible || isDisposed
        ? null
        : Timer.periodic(const Duration(milliseconds: 250), (_) => poll());
  }

  void _notify() => notify();

  @override
  void dispose() {
    _background?.cancel();
    session.close();
    session.dispose();
    _renderer?.dispose();
    super.dispose();
  }
}
