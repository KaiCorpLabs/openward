import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../terminal/palette.dart';
import '../terminal/schemes.dart';
import 'tokens.dart';

/// The proposed themes, by id. Grafito and Fósforo are dark, Papel is
/// light; Nativo and Alto contraste come in both.
abstract final class OwThemes {
  /// Dark graphite with a teal accent.
  static final grafito = OwTheme(
    id: 'grafito',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF0D1014),
      surface: Color(0xFF12161B),
      raised: Color(0xFF151A21),
      sunken: Color(0xFF0F1318),
      hover: Color(0xFF181D24),
      selected: Color(0xFF1B2129),
      border: Color(0xFF1E242D),
      control: Color(0xFF2E3642),
      text: Color(0xFFE4E8EE),
      textMuted: Color(0xFF98A2B0),
      textSubtle: Color(0xFF8A94A3),
      primary: Color(0xFF3CC8B0),
      onPrimary: Color(0xFF0B1F1B),
      accent: Color(0xFF3CC8B0),
      accentText: Color(0xFF7BE0CF),
      accentSoft: Color(0xFF173A35),
      info: Color(0xFF6CA8FF),
      infoSoft: Color(0xFF141B26),
      infoLine: Color(0xFF2A3A55),
      warn: Color(0xFFF2A65A),
      warnSoft: Color(0xFF241D13),
      warnLine: Color(0xFF5A4320),
      danger: Color(0xFFFF8A7A),
      dangerSoft: Color(0xFF1E1416),
      dangerLine: Color(0xFF6B3530),
      tagWarm: Color(0xFFF5C08A),
      tagWarmSoft: Color(0xFF3A2A18),
      scrim: Color(0x99050710),
    ),
    fonts: const OwFonts(
      ui: 'IBM Plex Sans',
      monoFont: 'JetBrains Mono',
      terminal: 'JetBrains Mono',
    ),
    terminal: TermPalette.grafito,
  );

  /// Warm paper, ink buttons, and a light terminal set in a card.
  static final papel = OwTheme(
    id: 'papel',
    colors: const OwColors(
      brightness: Brightness.light,
      window: Color(0xFFF3F0EA),
      surface: Color(0xFFF3F0EA),
      raised: Color(0xFFFFFEFB),
      sunken: Color(0xFFECE8E0),
      hover: Color(0xFFEAE5DC),
      selected: Color(0xFFFFFFFF),
      border: Color(0xFFDDD6CA),
      control: Color(0xFFCFC7B9),
      text: Color(0xFF1F1D1A),
      textMuted: Color(0xFF5C564D),
      textSubtle: Color(0xFF6B645A),
      primary: Color(0xFF1F1D1A),
      onPrimary: Color(0xFFFBFAF7),
      accent: Color(0xFF0E8F7D),
      accentText: Color(0xFF0E6F62),
      accentSoft: Color(0xFFDCEFEA),
      info: Color(0xFF2F5BB7),
      infoSoft: Color(0xFFE6EDFA),
      infoLine: Color(0xFFB9CBEF),
      warn: Color(0xFF8A4B00),
      warnSoft: Color(0xFFFBEFD9),
      warnLine: Color(0xFFE8C58C),
      danger: Color(0xFFB3261E),
      dangerSoft: Color(0xFFFBE9E7),
      dangerLine: Color(0xFFE8B4AE),
      tagWarm: Color(0xFF7A4A12),
      tagWarmSoft: Color(0xFFF4E3CC),
      scrim: Color(0x591F1D1A),
    ),
    shape: const OwShape(
      radiusLarge: 14,
      pills: true,
      insetTerminal: true,
      tabs: TabStyle.pill,
    ),
    fonts: const OwFonts(
      ui: 'Instrument Sans',
      display: 'Instrument Serif',
      monoFont: 'IBM Plex Mono',
      terminal: 'IBM Plex Mono',
      serifLabels: true,
    ),
    terminal: TermPalette.papel,
    terminalDark: ThemePalettes.papelOscuro,
  );

  /// All monospace, phosphor green on black, square corners.
  static final fosforo = OwTheme(
    id: 'fosforo',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF0A0D0B),
      surface: Color(0xFF0A0D0B),
      raised: Color(0xFF0E1411),
      sunken: Color(0xFF070908),
      hover: Color(0xFF0F1A14),
      selected: Color(0xFF12221A),
      border: Color(0xFF1C2620),
      control: Color(0xFF2E3D35),
      text: Color(0xFFC9D6CE),
      textMuted: Color(0xFF9FB3A8),
      textSubtle: Color(0xFF7D978A),
      primary: Color(0xFF5CF2B5),
      onPrimary: Color(0xFF0A0D0B),
      accent: Color(0xFF5CF2B5),
      accentText: Color(0xFF5CF2B5),
      accentSoft: Color(0xFF10251B),
      info: Color(0xFF7FD6E8),
      infoSoft: Color(0xFF0C1A1E),
      infoLine: Color(0xFF1F3A40),
      warn: Color(0xFFF2C14E),
      warnSoft: Color(0xFF1E1A0C),
      warnLine: Color(0xFF4A3E14),
      danger: Color(0xFFFF7A6B),
      dangerSoft: Color(0xFF1E0F0D),
      dangerLine: Color(0xFF5A2620),
      tagWarm: Color(0xFFF2C14E),
      tagWarmSoft: Color(0xFF1E1A0C),
      scrim: Color(0xB3000000),
    ),
    shape: const OwShape(
      radiusSmall: 0,
      radius: 0,
      radiusLarge: 0,
      tabs: TabStyle.block,
    ),
    fonts: const OwFonts(
      ui: 'JetBrains Mono',
      label: 'Martian Mono',
      display: 'Martian Mono',
      monoFont: 'JetBrains Mono',
      terminal: 'JetBrains Mono',
    ),
    terminal: ThemePalettes.fosforo,
  );

  static const _nativoShape = OwShape(
    radius: 6,
    radiusLarge: 10,
    tabs: TabStyle.segment,
  );

  /// The platform's own look, dark.
  static final nativoOscuro = OwTheme(
    id: 'nativo-oscuro',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF262529),
      surface: Color(0xFF1E1E1E),
      raised: Color(0xFF2B2A2E),
      sunken: Color(0xFF1A191C),
      hover: Color(0xFF323136),
      selected: Color(0xFF3A3940),
      border: Color(0xFF38373C),
      control: Color(0xFF55545A),
      text: Color(0xFFE5E5E7),
      textMuted: Color(0xFFB4B4B9),
      textSubtle: Color(0xFFADADB2),
      primary: Color(0xFF0B6BD8),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF0A84FF),
      accentText: Color(0xFF6CB4FF),
      accentSoft: Color(0xFF15304F),
      info: Color(0xFF64D2FF),
      infoSoft: Color(0xFF13262E),
      infoLine: Color(0xFF2A4D5C),
      warn: Color(0xFFFF9F0A),
      warnSoft: Color(0xFF2B2212),
      warnLine: Color(0xFF5C4419),
      danger: Color(0xFFFF6961),
      dangerSoft: Color(0xFF2E1918),
      dangerLine: Color(0xFF66302C),
      tagWarm: Color(0xFFFFB340),
      tagWarmSoft: Color(0xFF3A2C14),
      scrim: Color(0x99000000),
    ),
    shape: _nativoShape,
    terminal: ThemePalettes.nativoOscuro,
  );

  /// The platform's own look, light.
  static final nativoClaro = OwTheme(
    id: 'nativo-claro',
    colors: const OwColors(
      brightness: Brightness.light,
      window: Color(0xFFEBEBED),
      surface: Color(0xFFFFFFFF),
      raised: Color(0xFFFFFFFF),
      sunken: Color(0xFFF2F2F4),
      hover: Color(0xFFE3E3E6),
      selected: Color(0xFFDCDCE0),
      border: Color(0xFFD8D8DC),
      control: Color(0xFFB8B8BE),
      text: Color(0xFF1D1D1F),
      textMuted: Color(0xFF55555A),
      textSubtle: Color(0xFF616166),
      primary: Color(0xFF0066CC),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF0071E3),
      accentText: Color(0xFF0060C0),
      accentSoft: Color(0xFFE1EEFC),
      info: Color(0xFF0066CC),
      infoSoft: Color(0xFFE8F1FC),
      infoLine: Color(0xFFB6D2F5),
      warn: Color(0xFF9A5400),
      warnSoft: Color(0xFFFFF4E0),
      warnLine: Color(0xFFF0CF94),
      danger: Color(0xFFC0302B),
      dangerSoft: Color(0xFFFDECEB),
      dangerLine: Color(0xFFF1B9B6),
      tagWarm: Color(0xFF8A4B00),
      tagWarmSoft: Color(0xFFFBEBD3),
      scrim: Color(0x4D000000),
    ),
    shape: _nativoShape,
    terminal: ThemePalettes.nativoClaro,
    terminalDark: ThemePalettes.nativoOscuro,
  );

  static const _contrasteFonts = OwFonts(
    monoFont: 'JetBrains Mono',
    terminal: 'JetBrains Mono',
  );

  /// White on black, everything outlined.
  static final contrasteOscuro = OwTheme(
    id: 'contraste-oscuro',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF000000),
      surface: Color(0xFF000000),
      raised: Color(0xFF0A0A0A),
      sunken: Color(0xFF000000),
      hover: Color(0xFF1F1F1F),
      selected: Color(0xFF2E2E2E),
      border: Color(0xFF8C8C8C),
      control: Color(0xFFFFFFFF),
      text: Color(0xFFFFFFFF),
      textMuted: Color(0xFFEBEBEB),
      textSubtle: Color(0xFFD6D6D6),
      primary: Color(0xFFFFE14D),
      onPrimary: Color(0xFF000000),
      accent: Color(0xFFFFE14D),
      accentText: Color(0xFFFFE14D),
      accentSoft: Color(0xFF332D00),
      info: Color(0xFF7FDBFF),
      infoSoft: Color(0xFF001A26),
      infoLine: Color(0xFF7FDBFF),
      warn: Color(0xFFFFB347),
      warnSoft: Color(0xFF261600),
      warnLine: Color(0xFFFFB347),
      danger: Color(0xFFFF8F8F),
      dangerSoft: Color(0xFF260000),
      dangerLine: Color(0xFFFF8F8F),
      tagWarm: Color(0xFFFFB347),
      tagWarmSoft: Color(0xFF261600),
      scrim: Color(0xCC000000),
    ),
    fonts: _contrasteFonts,
    terminal: ThemePalettes.contrasteOscuro,
    minimumContrast: 4.5,
  );

  /// Black on white, everything outlined.
  static final contrasteClaro = OwTheme(
    id: 'contraste-claro',
    colors: const OwColors(
      brightness: Brightness.light,
      window: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      raised: Color(0xFFFFFFFF),
      sunken: Color(0xFFF0F0F0),
      hover: Color(0xFFE6E6E6),
      selected: Color(0xFFD9D9D9),
      border: Color(0xFF595959),
      control: Color(0xFF000000),
      text: Color(0xFF000000),
      textMuted: Color(0xFF1A1A1A),
      textSubtle: Color(0xFF333333),
      primary: Color(0xFF0033A0),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF0033A0),
      accentText: Color(0xFF0033A0),
      accentSoft: Color(0xFFDCE6FF),
      info: Color(0xFF0033A0),
      infoSoft: Color(0xFFE6ECFF),
      infoLine: Color(0xFF0033A0),
      warn: Color(0xFF7A3E00),
      warnSoft: Color(0xFFFFF0DC),
      warnLine: Color(0xFF7A3E00),
      danger: Color(0xFFA30000),
      dangerSoft: Color(0xFFFFE6E6),
      dangerLine: Color(0xFFA30000),
      tagWarm: Color(0xFF7A3E00),
      tagWarmSoft: Color(0xFFFFF0DC),
      scrim: Color(0x80000000),
    ),
    fonts: _contrasteFonts,
    terminal: ThemePalettes.contrasteClaro,
    terminalDark: ThemePalettes.contrasteOscuro,
    minimumContrast: 4.5,
  );

  static final all = {
    for (final t in [
      grafito,
      papel,
      fosforo,
      nativoOscuro,
      nativoClaro,
      contrasteOscuro,
      contrasteClaro,
    ])
      t.id: t,
  };

  /// The cards of the gallery: a family has a light theme, a dark one, or
  /// both.
  static final families = [
    ThemeFamily('grafito', 'Grafito', dark: grafito),
    ThemeFamily('papel', 'Papel', light: papel),
    ThemeFamily('fosforo', 'Fósforo', dark: fosforo),
    ThemeFamily('nativo', 'Nativo', light: nativoClaro, dark: nativoOscuro),
    ThemeFamily(
      'contraste',
      'Alto contraste',
      light: contrasteClaro,
      dark: contrasteOscuro,
    ),
  ];

  static ThemeFamily? family(String id) {
    for (final f in families) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// The family a theme belongs to.
  static ThemeFamily familyOf(OwTheme theme) =>
      families.firstWhere((f) => f.light == theme || f.dark == theme);
}

/// A gallery card: one name, with a light theme, a dark one, or both.
class ThemeFamily {
  const ThemeFamily(this.id, this.name, {this.light, this.dark});

  final String id;

  /// Proper names, the same in every language.
  final String name;
  final OwTheme? light;
  final OwTheme? dark;

  OwTheme? variant(Brightness b) => b == Brightness.light ? light : dark;
}

/// The theme to use for `brightness`, as the settings choose it: the
/// family picked for that brightness, with the layers taken from other
/// themes where the user changed them.
OwTheme resolveTheme(Settings s, Brightness brightness) {
  final light = brightness == Brightness.light;
  final base =
      OwThemes.family(light ? s.lightTheme : s.darkTheme)
          ?.variant(brightness) ??
      (light ? OwThemes.papel : OwThemes.grafito);
  final o = s.overrides[base.id] ?? const ThemeOverrides();
  final colorsFrom = OwThemes.all[o.colors] ?? base;
  final shapeFrom = OwThemes.all[o.shape] ?? base;
  final scheme = o.terminal == TerminalColors.scheme
      ? [
          ...knownSchemes,
          ...s.schemes,
        ].where((x) => x.id == o.scheme).firstOrNull
      : null;
  final terminal = switch (o.terminal) {
    TerminalColors.theme => colorsFrom.terminal,
    TerminalColors.dark =>
      colorsFrom.terminal.dark
          ? colorsFrom.terminal
          : colorsFrom.terminalDark ?? TermPalette.grafito,
    TerminalColors.scheme => scheme?.palette ?? colorsFrom.terminal,
  };
  return OwTheme(
    id: base.id,
    colors: colorsFrom.colors,
    shape: shapeFrom.shape,
    fonts: base.fonts.copyWith(
      ui: o.uiFont == null ? null : () => o.uiFont!.isEmpty ? null : o.uiFont,
      terminal: o.terminalFont == null
          ? null
          : () => o.terminalFont!.isEmpty ? null : o.terminalFont,
    ),
    terminal: terminal,
    terminalDark: colorsFrom.terminalDark,
    minimumContrast: base.minimumContrast,
  );
}

/// Material's theme from ours, so its widgets (fields, menus, dialogs)
/// look like the rest.
ThemeData materialTheme(OwTheme ow) {
  final c = ow.colors;
  final shape = ow.shape;
  final scheme = ColorScheme(
    brightness: c.brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.accentText,
    secondary: c.accent,
    onSecondary: c.onPrimary,
    secondaryContainer: c.accentSoft,
    onSecondaryContainer: c.accentText,
    tertiary: c.warn,
    onTertiary: c.surface,
    tertiaryContainer: c.warnSoft,
    onTertiaryContainer: c.text,
    error: c.danger,
    onError: c.surface,
    errorContainer: c.dangerSoft,
    onErrorContainer: c.text,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.textMuted,
    surfaceContainerLowest: c.sunken,
    surfaceContainerLow: c.window,
    surfaceContainer: c.sunken,
    surfaceContainerHigh: c.raised,
    surfaceContainerHighest: c.hover,
    outline: c.control,
    outlineVariant: c.border,
    shadow: Colors.black,
    scrim: c.scrim,
    inverseSurface: c.text,
    onInverseSurface: c.surface,
    inversePrimary: c.accent,
  );
  final radius = BorderRadius.circular(shape.radius);
  final control = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(shape.control),
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    fontFamily: ow.fonts.ui,
    scaffoldBackgroundColor: c.surface,
    canvasColor: c.raised,
    dividerColor: c.border,
    hoverColor: c.hover,
    focusColor: c.accent.withValues(alpha: 0.18),
    highlightColor: Colors.transparent,
    splashFactory: InkRipple.splashFactory,
    extensions: [ow],
  );
  final text = base.textTheme
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          fontFamily: ow.fonts.display ?? ow.fonts.ui,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 14),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 12),
        // Section labels: small capitals in spirit.
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      )
      .apply(bodyColor: c.text, displayColor: c.text);
  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    textTheme: text,
    iconTheme: IconThemeData(color: c.textMuted, size: 18),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.raised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: outline(c.control),
      enabledBorder: outline(c.control),
      focusedBorder: outline(c.accent, 1.5),
      errorBorder: outline(c.danger),
      focusedErrorBorder: outline(c.danger, 1.5),
      disabledBorder: outline(c.border),
      labelStyle: TextStyle(color: c.textMuted),
      floatingLabelStyle: TextStyle(color: c.textMuted),
      helperStyle: TextStyle(color: c.textSubtle, fontSize: 12),
      hintStyle: TextStyle(color: c.textSubtle),
      prefixIconColor: c.textSubtle,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: control,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.control),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: control,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentText,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: control,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.textMuted,
        minimumSize: const Size(32, 32),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.radiusLarge),
        side: BorderSide(color: c.control),
      ),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.control),
      ),
      textStyle: text.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: c.control),
          ),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.text,
        borderRadius: BorderRadius.circular(shape.radiusSmall),
      ),
      textStyle: TextStyle(color: c.surface, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.control),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : null,
      ),
      checkColor: WidgetStatePropertyAll(c.onPrimary),
      side: BorderSide(color: c.control, width: 1.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.sunken,
      ),
      trackOutlineColor: WidgetStatePropertyAll(c.control),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(c.accent)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.hover : c.sunken,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.text : c.textMuted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.control)),
        shape: WidgetStatePropertyAll(control),
        visualDensity: VisualDensity.compact,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: TextStyle(color: c.surface),
      actionTextColor: c.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.3),
    ),
  );
}
