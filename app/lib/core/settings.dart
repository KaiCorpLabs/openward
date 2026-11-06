import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/highlight.dart';
import '../terminal/keys.dart' as keys;
import '../terminal/schemes.dart';
import 'json_file.dart';

/// Light, dark, or as the system is.
enum ThemeChoice { system, dark, light }

/// The interface language: the system's (English when it is neither), or
/// one chosen.
enum Language { system, es, en }

/// Animations: as the system says, always fewer, or always.
enum MotionChoice { system, reduce, full }

/// macOS: which Option keys act as Alt.
enum OptionAltChoice { off, both, left, right }

/// Which shortcuts the window answers to: with ⌘, a Mac's, or with
/// Ctrl+Shift, a PC's; the system's own unless chosen.
enum ShortcutProfile { system, mac, pc }

/// The cursor's shape when the program does not choose one.
enum CursorChoice { block, bar, underline }

/// What happens to a terminal's pane (or tab) when its shell ends.
enum OnExit {
  /// Closed when it ends well: `exit` or `logout`, without an error.
  clean,

  /// Closed whenever the program ends, also with an error.
  always,

  /// Left open.
  never,
}

/// How much room the sidebar takes: all of it, a rail of icons, or none
/// (it shows over the window when the pointer reaches the left edge).
enum SidebarMode { open, rail, hidden }

/// What the sidebar does when a terminal or file tab comes to the front;
/// back on the start page or a library page, it is as [SidebarMode] says.
enum SidebarOnSession { keep, rail, hide }

/// Where the terminal's colors come from.
enum TerminalColors {
  /// The theme's own, light or dark with it.
  theme,

  /// The theme's, but always dark.
  dark,

  /// A scheme from the gallery or imported ([ThemeOverrides.scheme]).
  scheme,
}

/// The layers of one theme that the user took from elsewhere. Null keeps
/// the theme's own; an empty font name is the system's font.
@immutable
class ThemeOverrides {
  const ThemeOverrides({
    this.colors,
    this.shape,
    this.uiFont,
    this.terminalFont,
    this.terminal = TerminalColors.theme,
    this.scheme,
  });

  /// Id of the theme whose interface colors to use.
  final String? colors;

  /// Id of the theme whose corners and tabs to use.
  final String? shape;
  final String? uiFont;
  final String? terminalFont;
  final TerminalColors terminal;
  final String? scheme;

  bool get isEmpty =>
      colors == null &&
      shape == null &&
      uiFont == null &&
      terminalFont == null &&
      terminal == TerminalColors.theme;

  ThemeOverrides copyWith({
    String? Function()? colors,
    String? Function()? shape,
    String? Function()? uiFont,
    String? Function()? terminalFont,
    TerminalColors? terminal,
    String? Function()? scheme,
  }) => ThemeOverrides(
    colors: colors == null ? this.colors : colors(),
    shape: shape == null ? this.shape : shape(),
    uiFont: uiFont == null ? this.uiFont : uiFont(),
    terminalFont: terminalFont == null ? this.terminalFont : terminalFont(),
    terminal: terminal ?? this.terminal,
    scheme: scheme == null ? this.scheme : scheme(),
  );

  Map<String, Object> toJson() => {
    'colors': ?colors,
    'shape': ?shape,
    'ui_font': ?uiFont,
    'terminal_font': ?terminalFont,
    'terminal': terminal.name,
    'scheme': ?scheme,
  };

  static ThemeOverrides fromJson(Object? json) {
    if (json is! Map) return const ThemeOverrides();
    String? text(String key) =>
        json[key] is String ? json[key] as String : null;
    return ThemeOverrides(
      colors: text('colors'),
      shape: text('shape'),
      uiFont: text('ui_font'),
      terminalFont: text('terminal_font'),
      terminal: TerminalColors.values.firstWhere(
        (t) => t.name == json['terminal'],
        orElse: () => TerminalColors.theme,
      ),
      scheme: text('scheme'),
    );
  }
}

/// How the app looks and behaves on this machine. Not in the vault: these
/// are preferences of the device, not data (ARCHITECTURE §4.1).
@immutable
class Settings {
  const Settings({
    this.fontSize = 13,
    this.theme = ThemeChoice.system,
    this.lightTheme = 'papel',
    this.darkTheme = 'grafito',
    this.overrides = const {},
    this.schemes = const [],
    this.optionAsAlt = OptionAltChoice.off,
    this.scrollback = 10000,
    this.language = Language.system,
    this.welcomed = false,
    this.seenNews = '',
    this.textScale = 1,
    this.lineHeight = 1.2,
    this.minimumContrast = true,
    this.motion = MotionChoice.system,
    this.cursor = CursorChoice.block,
    this.cursorBlink = false,
    this.bellFlash = true,
    this.onExit = OnExit.clean,
    this.commandHistory = true,
    this.sidebar = SidebarMode.open,
    this.sidebarOnSession = SidebarOnSession.keep,
    this.sidebarWidth = defaultSidebarWidth,
    this.terminalPadding = 12,
    this.recentConnections = true,
    this.readOsRelease = false,
    this.sessionLog = false,
    this.copyOnSelect = false,
    this.rightClickPaste = false,
    this.highlight = true,
    this.highlightRules = defaultHighlights,
    this.shortcutProfile = ShortcutProfile.system,
    this.terminalKeysFirst = false,
    this.autocomplete = true,
    this.openWith = '',
  });

  /// Terminal font size, in logical pixels.
  final double fontSize;
  final ThemeChoice theme;

  /// Theme families (`OwThemes.families`) for light and for dark.
  final String lightTheme;
  final String darkTheme;

  /// Layers changed per theme, by theme id.
  final Map<String, ThemeOverrides> overrides;

  /// Terminal schemes imported from other terminals.
  final List<TerminalScheme> schemes;

  /// macOS: Option sends Alt (Esc-prefixed keys) instead of typing symbols.
  final OptionAltChoice optionAsAlt;

  /// Lines of history for new terminals.
  final int scrollback;

  final Language language;

  /// The first-run guide was done or skipped.
  final bool welcomed;

  /// The version whose «what's new» was shown (`newsVersion`).
  final String seenNews;

  /// The interface's text size, on top of the system's.
  final double textScale;

  /// The terminal's line height, as a multiple of the font size.
  final double lineHeight;

  /// Terminal text that does not read on its background is made to.
  final bool minimumContrast;
  final MotionChoice motion;
  final CursorChoice cursor;
  final bool cursorBlink;

  /// A BEL flashes the terminal (besides marking its tab).
  final bool bellFlash;

  /// Whether a pane closes by itself when its shell ends. A connection
  /// that drops never does: it reconnects.
  final OnExit onExit;

  /// Commands typed in terminals are kept on this device, to find and
  /// send again (never in the vault).
  final bool commandHistory;

  final SidebarMode sidebar;
  final SidebarOnSession sidebarOnSession;

  /// The open sidebar's width, between [minSidebarWidth] and
  /// [maxSidebarWidth].
  final double sidebarWidth;

  /// Room around a terminal's text, in logical pixels (0 to 24).
  final double terminalPadding;

  /// Connections opened are kept on this device (`recent.json`), for the
  /// palette and the start page.
  final bool recentConnections;

  /// `/etc/os-release` is read after connecting to the hosts that do not
  /// say otherwise, to tell their system; on this device only.
  final bool readOsRelease;

  /// The session log is kept for the hosts that do not say otherwise, and
  /// for addresses typed by hand; on this device only.
  final bool sessionLog;

  /// Text selected with the mouse goes to the clipboard at once.
  final bool copyOnSelect;

  /// A right click pastes; with Ctrl, the terminal's menu.
  final bool rightClickPaste;

  /// Words and addresses in color ([highlightRules]).
  final bool highlight;
  final List<HighlightRule> highlightRules;
  final ShortcutProfile shortcutProfile;

  /// In a terminal, the program has the keys the window would otherwise
  /// take without Ctrl+Shift (Ctrl+Tab, Ctrl+=…): PC shortcuts only.
  final bool terminalKeysFirst;

  /// The rest of a command, suggested dimmed as it is typed (with the
  /// command history on).
  final bool autocomplete;

  /// The program remote files were last opened with («Abrir con…»).
  final String openWith;

  /// Whether shortcuts go with ⌘.
  bool get macShortcuts => switch (shortcutProfile) {
    ShortcutProfile.system => keys.isApple,
    ShortcutProfile.mac => true,
    ShortcutProfile.pc => false,
  };

  static const defaultSidebarWidth = 272.0;
  static const minSidebarWidth = 220.0;
  static const maxSidebarWidth = 420.0;

  static const fontSizes = [
    10.0,
    11.0,
    12.0,
    13.0,
    14.0,
    15.0,
    16.0,
    18.0,
    20.0,
    24.0,
  ];
  static const scrollbacks = [1000, 10000, 50000, 100000];
  static const lineHeights = [1.0, 1.1, 1.2, 1.35, 1.5];

  Settings copyWith({
    double? fontSize,
    ThemeChoice? theme,
    String? lightTheme,
    String? darkTheme,
    Map<String, ThemeOverrides>? overrides,
    List<TerminalScheme>? schemes,
    OptionAltChoice? optionAsAlt,
    int? scrollback,
    Language? language,
    bool? welcomed,
    String? seenNews,
    double? textScale,
    double? lineHeight,
    bool? minimumContrast,
    MotionChoice? motion,
    CursorChoice? cursor,
    bool? cursorBlink,
    bool? bellFlash,
    OnExit? onExit,
    bool? commandHistory,
    SidebarMode? sidebar,
    SidebarOnSession? sidebarOnSession,
    double? sidebarWidth,
    double? terminalPadding,
    bool? recentConnections,
    bool? readOsRelease,
    bool? sessionLog,
    bool? copyOnSelect,
    bool? rightClickPaste,
    bool? highlight,
    List<HighlightRule>? highlightRules,
    ShortcutProfile? shortcutProfile,
    bool? terminalKeysFirst,
    bool? autocomplete,
    String? openWith,
  }) => Settings(
    fontSize: fontSize ?? this.fontSize,
    theme: theme ?? this.theme,
    lightTheme: lightTheme ?? this.lightTheme,
    darkTheme: darkTheme ?? this.darkTheme,
    overrides: overrides ?? this.overrides,
    schemes: schemes ?? this.schemes,
    optionAsAlt: optionAsAlt ?? this.optionAsAlt,
    scrollback: scrollback ?? this.scrollback,
    language: language ?? this.language,
    welcomed: welcomed ?? this.welcomed,
    seenNews: seenNews ?? this.seenNews,
    textScale: textScale ?? this.textScale,
    lineHeight: lineHeight ?? this.lineHeight,
    minimumContrast: minimumContrast ?? this.minimumContrast,
    motion: motion ?? this.motion,
    cursor: cursor ?? this.cursor,
    cursorBlink: cursorBlink ?? this.cursorBlink,
    bellFlash: bellFlash ?? this.bellFlash,
    onExit: onExit ?? this.onExit,
    commandHistory: commandHistory ?? this.commandHistory,
    sidebar: sidebar ?? this.sidebar,
    sidebarOnSession: sidebarOnSession ?? this.sidebarOnSession,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    terminalPadding: terminalPadding ?? this.terminalPadding,
    recentConnections: recentConnections ?? this.recentConnections,
    readOsRelease: readOsRelease ?? this.readOsRelease,
    sessionLog: sessionLog ?? this.sessionLog,
    copyOnSelect: copyOnSelect ?? this.copyOnSelect,
    rightClickPaste: rightClickPaste ?? this.rightClickPaste,
    highlight: highlight ?? this.highlight,
    highlightRules: highlightRules ?? this.highlightRules,
    shortcutProfile: shortcutProfile ?? this.shortcutProfile,
    terminalKeysFirst: terminalKeysFirst ?? this.terminalKeysFirst,
    autocomplete: autocomplete ?? this.autocomplete,
    openWith: openWith ?? this.openWith,
  );

  /// The same settings with one theme's layers changed (or reset).
  Settings withOverrides(
    String themeId,
    ThemeOverrides Function(ThemeOverrides) change,
  ) {
    final next = change(overrides[themeId] ?? const ThemeOverrides());
    return copyWith(
      overrides: {
        for (final MapEntry(:key, :value) in overrides.entries)
          if (key != themeId) key: value,
        if (!next.isEmpty || next.scheme != null) themeId: next,
      },
    );
  }

  Map<String, Object> toJson() => {
    'font_size': fontSize,
    'theme': theme.name,
    'light_theme': lightTheme,
    'dark_theme': darkTheme,
    if (overrides.isNotEmpty)
      'overrides': {
        for (final MapEntry(:key, :value) in overrides.entries)
          key: value.toJson(),
      },
    if (schemes.isNotEmpty)
      'terminal_schemes': [for (final s in schemes) s.toJson()],
    'option_as_alt': optionAsAlt.name,
    'scrollback': scrollback,
    'language': language.name,
    'welcomed': welcomed,
    if (seenNews.isNotEmpty) 'seen_news': seenNews,
    'text_scale': textScale,
    'line_height': lineHeight,
    'minimum_contrast': minimumContrast,
    'motion': motion.name,
    'cursor': cursor.name,
    'cursor_blink': cursorBlink,
    'bell_flash': bellFlash,
    'on_exit': onExit.name,
    'command_history': commandHistory,
    'sidebar': sidebar.name,
    'sidebar_on_session': sidebarOnSession.name,
    'sidebar_width': sidebarWidth,
    'terminal_padding': terminalPadding,
    'recent_connections': recentConnections,
    'read_os_release': readOsRelease,
    'session_log': sessionLog,
    'copy_on_select': copyOnSelect,
    'right_click_paste': rightClickPaste,
    'highlight': highlight,
    if (!listEquals(highlightRules, defaultHighlights))
      'highlight_rules': [for (final r in highlightRules) r.toJson()],
    'shortcut_profile': shortcutProfile.name,
    'terminal_keys_first': terminalKeysFirst,
    'autocomplete': autocomplete,
    if (openWith.isNotEmpty) 'open_with': openWith,
  };

  /// Unknown or broken values fall back to the defaults, one by one.
  factory Settings.fromJson(Map<String, Object?> json) {
    const d = Settings();
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.firstWhere((v) => v.name == json[key], orElse: () => fallback);
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key]! as bool : fallback;
    double number(String key, double min, double max, double fallback) {
      final v = json[key];
      return v is num && v >= min && v <= max ? v.toDouble() : fallback;
    }

    String text(String key, String fallback) =>
        json[key] is String ? json[key]! as String : fallback;
    final scroll = json['scrollback'];
    final overrides = json['overrides'];
    final schemes = json['terminal_schemes'];
    final rules = json['highlight_rules'];
    return Settings(
      fontSize: number('font_size', 8, 40, d.fontSize),
      theme: pick(ThemeChoice.values, 'theme', d.theme),
      lightTheme: text('light_theme', d.lightTheme),
      darkTheme: text('dark_theme', d.darkTheme),
      overrides: overrides is Map
          ? {
              for (final MapEntry(:key, :value) in overrides.entries)
                if (key is String) key: ThemeOverrides.fromJson(value),
            }
          : const {},
      schemes: schemes is List
          ? [for (final s in schemes) ?TerminalScheme.fromJson(s)]
          : const [],
      // It was a yes or no: yes is both.
      optionAsAlt: switch (json['option_as_alt']) {
        true => OptionAltChoice.both,
        false => OptionAltChoice.off,
        _ => pick(OptionAltChoice.values, 'option_as_alt', d.optionAsAlt),
      },
      scrollback: scroll is int && scroll >= 100 && scroll <= 1000000
          ? scroll
          : d.scrollback,
      language: pick(Language.values, 'language', d.language),
      welcomed: flag('welcomed', d.welcomed),
      seenNews: text('seen_news', d.seenNews),
      textScale: number('text_scale', 0.8, 2, d.textScale),
      lineHeight: number('line_height', 1, 2, d.lineHeight),
      minimumContrast: flag('minimum_contrast', d.minimumContrast),
      motion: pick(MotionChoice.values, 'motion', d.motion),
      cursor: pick(CursorChoice.values, 'cursor', d.cursor),
      cursorBlink: flag('cursor_blink', d.cursorBlink),
      bellFlash: flag('bell_flash', d.bellFlash),
      onExit: pick(OnExit.values, 'on_exit', d.onExit),
      commandHistory: flag('command_history', d.commandHistory),
      sidebar: pick(SidebarMode.values, 'sidebar', d.sidebar),
      sidebarOnSession: pick(
        SidebarOnSession.values,
        'sidebar_on_session',
        d.sidebarOnSession,
      ),
      sidebarWidth: number(
        'sidebar_width',
        minSidebarWidth,
        maxSidebarWidth,
        d.sidebarWidth,
      ),
      terminalPadding: number('terminal_padding', 0, 24, d.terminalPadding),
      recentConnections: flag('recent_connections', d.recentConnections),
      readOsRelease: flag('read_os_release', d.readOsRelease),
      sessionLog: flag('session_log', d.sessionLog),
      copyOnSelect: flag('copy_on_select', d.copyOnSelect),
      rightClickPaste: flag('right_click_paste', d.rightClickPaste),
      highlight: flag('highlight', d.highlight),
      highlightRules: rules is List
          ? [for (final r in rules) ?HighlightRule.fromJson(r)]
          : d.highlightRules,
      shortcutProfile: pick(
        ShortcutProfile.values,
        'shortcut_profile',
        d.shortcutProfile,
      ),
      terminalKeysFirst: flag('terminal_keys_first', d.terminalKeysFirst),
      autocomplete: flag('autocomplete', d.autocomplete),
      openWith: text('open_with', d.openWith),
    );
  }

  /// Two settings are equal when they save the same.
  @override
  bool operator ==(Object other) =>
      other is Settings && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Where the settings are kept: `settings.json` in the data directory,
/// set in `main` (or by a test).
final settingsFileProvider = Provider<File>(
  (ref) => throw UnimplementedError('override settingsFileProvider'),
);

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    try {
      final json = readJsonFile(ref.read(settingsFileProvider));
      if (json is Map<String, Object?>) {
        return _keys(Settings.fromJson(json));
      }
    } catch (_) {
      // Not ours to read: the defaults.
    }
    return _keys(const Settings());
  }

  /// The keyboard code reads these where no provider reaches.
  static Settings _keys(Settings s) {
    keys.macShortcuts = s.macShortcuts;
    keys.terminalKeysFirst = s.terminalKeysFirst;
    return s;
  }

  void update(Settings Function(Settings) change) {
    final next = change(state);
    if (next == state) return;
    state = _keys(next);
    final file = ref.read(settingsFileProvider);
    try {
      writeFileAtomically(
        file,
        const JsonEncoder.withIndent('  ').convert(next.toJson()),
      );
    } catch (_) {
      // Kept for this run even if it cannot be saved.
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);
