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

  /// Text on a [danger] fill: a button that deletes.
  Color get onDanger => _on(danger);

  /// Text on a [warn] fill: a button that reaches more than one place.
  Color get onWarn => _on(warn);

  /// Text on the snack bar, the tooltip and other inverted boxes, whose
  /// background is [text]: its action too, in bold.
  Color get onInverse => surface;

  /// The theme's own dark or light that reads on `fill` (4.5:1), or black
  /// or white when neither does.
  Color _on(Color fill) {
    for (final c in [surface, text]) {
      if (TermPalette.contrast(c, fill) >= 4.5) return c;
    }
    const black = Color(0xFF000000), white = Color(0xFFFFFFFF);
    return TermPalette.contrast(black, fill) >=
            TermPalette.contrast(white, fill)
        ? black
        : white;
  }
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

  /// Fully round (dots, pills, bars' ends), except where the theme's
  /// corners are square.
  double get round => radiusSmall == 0 ? 0 : 999;
}

/// The platform's monospace font.
String get platformMono => Platform.isMacOS || Platform.isIOS
    ? 'Menlo'
    : Platform.isWindows
    ? 'Consolas'
    : Platform.isAndroid
    ? 'monospace'
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

/// Space: padding and margins on a grid of 2 px, a step each; [hair] is
/// for optical nudges. Widgets take space from here, never as literals.
abstract final class OwSpace {
  static const double hair = 1;
  static const double s1 = 2;
  static const double s2 = 4;
  static const double s3 = 6;
  static const double s4 = 8;
  static const double s5 = 10;
  static const double s6 = 12;
  static const double s7 = 14;
  static const double s8 = 16;
  static const double s9 = 18;
  static const double s10 = 20;
  static const double s11 = 22;
  static const double s12 = 24;
  static const double s14 = 28;
  static const double s15 = 30;
  static const double s16 = 32;
  static const double s18 = 36;
  static const double s24 = 48;
}

/// Text sizes by role, as the theme's text styles have them: a
/// `TextStyle` of its own takes its size from here.
abstract final class OwText {
  /// Notes, hints, captions, table cells (`bodySmall`, `labelMedium`).
  static const double small = 12;

  /// Body text and controls (`bodyMedium`, `labelLarge`).
  static const double body = 13;

  /// Titles of sections and dialogs (`titleMedium`).
  static const double title = 15;

  /// What a whole surface says first: a drop target, an editor's title.
  static const double heading = 17;
}

/// Time: how long the interface takes to move, and to answer a pointer.
/// What a timer of the app's own waits for (debounces, polls) is not here.
abstract final class OwMotion {
  /// A bar that comes and goes (find).
  static const fast = Duration(milliseconds: 120);

  /// A panel sliding in.
  static const normal = Duration(milliseconds: 160);

  /// A notice fading in or out.
  static const slow = Duration(milliseconds: 250);

  /// A tooltip.
  static const hint = Duration(milliseconds: 600);

  /// A card that answers hovering (the latency, the rail's sections).
  static const hintSoon = Duration(milliseconds: 300);

  /// Hovering this long opens what peeks (the sidebar over the window).
  static const hoverIntent = Duration(milliseconds: 150);

  /// Leaving for this long closes it again.
  static const hoverLeave = Duration(milliseconds: 300);

  /// What appears only if it lasts (connecting), not as a flash.
  static const showAfter = Duration(milliseconds: 400);

  /// A slow pulse while something waits (connecting).
  static const pulse = Duration(milliseconds: 1400);

  /// A blink that draws the eye.
  static const blink = Duration(milliseconds: 1200);
}

/// Shadows, by how far above the window a surface floats.
abstract final class OwElevation {
  /// A card resting on the page.
  static const card = [
    BoxShadow(color: Color(0x14281E0A), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// A bar or chip above the content (find, a dragged tab, a drop).
  static const raised = [
    BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// A panel or card over the window (a connection's details, a question).
  static const overlay = [
    BoxShadow(color: Color(0x33000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
}
