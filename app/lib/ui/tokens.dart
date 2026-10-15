import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../terminal/palette.dart';

/// The colors of the interface: one layer of a theme. Widgets take colors
/// from here (through [OwTheme]), never as literals.
@immutable
class OwColors {
  const OwColors({
    required this.brightness,
    required this.window,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.hover,
    required this.selected,
    required this.border,
    required this.control,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentText,
    required this.accentSoft,
    required this.info,
    required this.infoSoft,
    required this.infoLine,
    required this.warn,
    required this.warnSoft,
    required this.warnLine,
    required this.danger,
    required this.dangerSoft,
    required this.dangerLine,
    required this.tagWarm,
    required this.tagWarmSoft,
    required this.scrim,
  });

  final Brightness brightness;

  /// The window's own chrome: the sidebar and the tab bar.
  final Color window;

  /// Behind pages and the terminal.
  final Color surface;

  /// Fields, cards and panels that sit on top.
  final Color raised;

  /// Below the surface: code boxes, table headers, the status bar.
  final Color sunken;
  final Color hover;

  /// The row or item that is chosen.
  final Color selected;

  /// Hairlines between areas.
  final Color border;

  /// Outlines of fields and buttons.
  final Color control;

  final Color text;

  /// Second-level text: addresses, descriptions.
  final Color textMuted;

  /// Captions and section labels; still readable (4.5:1 on [window]).
  final Color textSubtle;

  /// The main button of a screen.
  final Color primary;
  final Color onPrimary;

  /// What is alive or chosen: connected, focused, selected.
  final Color accent;

  /// Links and accent text on [surface] and [raised].
  final Color accentText;

  /// Behind accent text: tags, the selected item of a group.
  final Color accentSoft;

  final Color info;
  final Color infoSoft;
  final Color infoLine;
  final Color warn;
  final Color warnSoft;
  final Color warnLine;
  final Color danger;
  final Color dangerSoft;
  final Color dangerLine;

  /// A second color for tags, so neighbouring tags can differ.
  final Color tagWarm;
  final Color tagWarmSoft;

  /// Over the window behind a panel.
  final Color scrim;

  bool get dark => brightness == Brightness.dark;
}

/// How tabs look.
enum TabStyle {
  /// Folder tabs joined to the content below (Grafito).
  folder,

  /// Rounded pills on the bar (Papel).
  pill,

  /// Square blocks; the active one filled with the accent (Fósforo).
  block,

  /// Plain segments, the active one lighter (Nativo).
  segment,
}

/// Corners and spacing: another layer.
@immutable
class OwShape {
  const OwShape({
    this.radiusSmall = 4,
    this.radius = 7,
    this.radiusLarge = 10,
    this.pills = false,
    this.insetTerminal = false,
    this.tabs = TabStyle.folder,
  });

  /// Tags and key caps.
  final double radiusSmall;

  /// Fields, buttons and rows.
  final double radius;

  /// Cards and panels.
  final double radiusLarge;

  /// Buttons and the search field fully rounded.
  final bool pills;

  /// The terminal as a card inside the window instead of edge to edge.
  final bool insetTerminal;

  final TabStyle tabs;

  /// For buttons.
  double get control => pills ? 999 : radius;
}

/// The platform's monospace font.
String get platformMono => Platform.isMacOS || Platform.isIOS
    ? 'Menlo'
    : Platform.isWindows
    ? 'Consolas'
    : 'DejaVu Sans Mono';

/// Type: another layer. Null families mean the platform's own.
@immutable
class OwFonts {
  const OwFonts({
    this.ui,
    this.display,
    this.label,
    this.monoFont,
    this.terminal,
    this.serifLabels = false,
  });

  /// The interface.
  final String? ui;

  /// Large titles; falls back to [ui].
  final String? display;

  /// Section labels; falls back to [ui].
  final String? label;

  /// For [mono]; null for the platform's.
  final String? monoFont;

  /// The terminal; null for the platform's monospace font.
  final String? terminal;

  /// Section labels in [display] italics instead of small capitals.
  final bool serifLabels;

  /// Addresses, fingerprints and commands outside the terminal.
  String get mono => monoFont ?? platformMono;

  OwFonts copyWith({String? Function()? ui, String? Function()? terminal}) =>
      OwFonts(
        ui: ui == null ? this.ui : ui(),
        display: ui == null ? display : null,
        label: ui == null ? label : null,
        monoFont: monoFont,
        terminal: terminal == null ? this.terminal : terminal(),
        serifLabels: ui == null && serifLabels,
      );
}

/// A whole theme: its layers and the terminal's colors. Reach it with
/// `context.ow`.
@immutable
class OwTheme extends ThemeExtension<OwTheme> {
  const OwTheme({
    required this.id,
    required this.colors,
    required this.terminal,
    this.terminalDark,
    this.shape = const OwShape(),
    this.fonts = const OwFonts(),
    this.minimumContrast = 3,
  });

  /// Stable name, as settings keep it.
  final String id;
  final OwColors colors;
  final OwShape shape;
  final OwFonts fonts;
  final TermPalette terminal;

  /// The terminal when it is set to stay dark, for a light theme.
  final TermPalette? terminalDark;

  /// What the terminal's minimum contrast option asks for with this theme.
  final double minimumContrast;

  @override
  OwTheme copyWith({
    OwColors? colors,
    OwShape? shape,
    OwFonts? fonts,
    TermPalette? terminal,
  }) => OwTheme(
    id: id,
    colors: colors ?? this.colors,
    shape: shape ?? this.shape,
    fonts: fonts ?? this.fonts,
    terminal: terminal ?? this.terminal,
    terminalDark: terminalDark,
    minimumContrast: minimumContrast,
  );

  /// Themes switch at once: nothing in between makes sense for a terminal.
  @override
  OwTheme lerp(OwTheme? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension OwContext on BuildContext {
  OwTheme get ow => Theme.of(this).extension<OwTheme>()!;
}
