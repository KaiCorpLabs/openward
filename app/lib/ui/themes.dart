import 'package:flutter/material.dart';

import '../terminal/palette.dart';
import 'tokens.dart';

/// The proposed themes. B1 brings the two defaults (dark and light); the
/// rest, and mixing their layers, come with Apariencia (docs/plan/v0.2.md).
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
    shape: const OwShape(radiusLarge: 14, pills: true, insetTerminal: true),
    terminal: TermPalette.papel,
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
          fontSize: 11,
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
