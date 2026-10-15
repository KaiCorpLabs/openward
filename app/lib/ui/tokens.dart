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

/// Corners and spacing: another layer.
@immutable
class OwShape {
  const OwShape({
    this.radiusSmall = 4,
    this.radius = 7,
    this.radiusLarge = 10,
    this.pills = false,
    this.insetTerminal = false,
  });

  /// Tags and key caps.
  final double radiusSmall;

  /// Fields, buttons and rows.
  final double radius;

  /// Cards and panels.
  final double radiusLarge;

  /// Buttons, tabs and the search field fully rounded.
  final bool pills;

  /// The terminal as a card inside the window instead of edge to edge.
  final bool insetTerminal;

  /// For buttons and tabs.
  double get control => pills ? 999 : radius;
}

/// Type: another layer. Null families mean the platform's own.
@immutable
class OwFonts {
  const OwFonts({this.ui, this.display});

  /// The interface.
  final String? ui;

  /// Large titles; falls back to [ui].
  final String? display;

  /// Addresses, fingerprints and commands outside the terminal.
  String get mono => Platform.isMacOS || Platform.isIOS
      ? 'Menlo'
      : Platform.isWindows
      ? 'Consolas'
      : 'DejaVu Sans Mono';
}

/// A whole theme: its layers and the terminal's colors. Reach it with
/// `context.ow`.
@immutable
class OwTheme extends ThemeExtension<OwTheme> {
  const OwTheme({
    required this.id,
    required this.colors,
    required this.terminal,
    this.shape = const OwShape(),
    this.fonts = const OwFonts(),
  });

  /// Stable name, as settings keep it.
  final String id;
  final OwColors colors;
  final OwShape shape;
  final OwFonts fonts;
  final TermPalette terminal;

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
  );

  /// Themes switch at once: nothing in between makes sense for a terminal.
  @override
  OwTheme lerp(OwTheme? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension OwContext on BuildContext {
  OwTheme get ow => Theme.of(this).extension<OwTheme>()!;
}
