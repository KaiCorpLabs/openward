import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../terminal/palette.dart';
import '../terminal/schemes.dart';
import 'tokens.dart';

/// The themes, by id. Grafito, Fósforo, Monitor, Búnker and Marino are
/// dark, Papel is light; Nativo, Alto contraste, Berenjena and the famous
/// palettes (Catppuccin, Dracula, Tokyo Night) come in both.
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

  /// A real green screen: green text, the programs' colors kept.
  static final monitor = OwTheme(
    id: 'monitor',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF060B07),
      surface: Color(0xFF040904),
      raised: Color(0xFF0B160D),
      sunken: Color(0xFF030703),
      hover: Color(0xFF0E1D11),
      selected: Color(0xFF122817),
      border: Color(0xFF163220),
      control: Color(0xFF2B5636),
      text: Color(0xFF8CFFA6),
      textMuted: Color(0xFF68DB84),
      textSubtle: Color(0xFF55C270),
      primary: Color(0xFF33FF66),
      onPrimary: Color(0xFF021006),
      accent: Color(0xFF33FF66),
      accentText: Color(0xFF5CFF85),
      accentSoft: Color(0xFF0D2E16),
      info: Color(0xFF4DF2E0),
      infoSoft: Color(0xFF082220),
      infoLine: Color(0xFF1A4D47),
      warn: Color(0xFFE6F25C),
      warnSoft: Color(0xFF1C1F07),
      warnLine: Color(0xFF4A5218),
      danger: Color(0xFFFF6B5E),
      dangerSoft: Color(0xFF2A0F0C),
      dangerLine: Color(0xFF6E2A23),
      tagWarm: Color(0xFFE6F25C),
      tagWarmSoft: Color(0xFF1C1F07),
      scrim: Color(0xCC000000),
    ),
    shape: const OwShape(radiusSmall: 0, radius: 2, radiusLarge: 4),
    fonts: const OwFonts(
      ui: 'IBM Plex Mono',
      monoFont: 'IBM Plex Mono',
      terminal: 'IBM Plex Mono',
    ),
    terminal: ThemePalettes.monitor,
  );

  static const _berenjenaShape = OwShape(
    radius: 6,
    radiusLarge: 12,
    tabs: TabStyle.segment,
  );

  /// A grey window in the GNOME manner with an aubergine terminal, dark.
  static final berenjenaOscuro = OwTheme(
    id: 'berenjena-oscuro',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF2B2B2B),
      surface: Color(0xFF1F1F1F),
      raised: Color(0xFF2E2E2E),
      sunken: Color(0xFF191919),
      hover: Color(0xFF363636),
      selected: Color(0xFF404040),
      border: Color(0xFF3A3A3A),
      control: Color(0xFF5C5C5C),
      text: Color(0xFFF6F5F4),
      textMuted: Color(0xFFCFCDCA),
      textSubtle: Color(0xFFB3B1AD),
      primary: Color(0xFFC13F14),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFFE95420),
      accentText: Color(0xFFFF8D5E),
      accentSoft: Color(0xFF47231A),
      info: Color(0xFF78AEED),
      infoSoft: Color(0xFF1E2A38),
      infoLine: Color(0xFF33506F),
      warn: Color(0xFFF5A93A),
      warnSoft: Color(0xFF382A14),
      warnLine: Color(0xFF6E5022),
      danger: Color(0xFFFF7B63),
      dangerSoft: Color(0xFF3A1F1B),
      dangerLine: Color(0xFF7A3B32),
      tagWarm: Color(0xFFEFC14A),
      tagWarmSoft: Color(0xFF3A3114),
      scrim: Color(0x99000000),
    ),
    shape: _berenjenaShape,
    terminal: ThemePalettes.berenjena,
  );

  /// The same in light; the terminal stays aubergine.
  static final berenjenaClaro = OwTheme(
    id: 'berenjena-claro',
    colors: const OwColors(
      brightness: Brightness.light,
      window: Color(0xFFEBEBEB),
      surface: Color(0xFFFAFAFA),
      raised: Color(0xFFFFFFFF),
      sunken: Color(0xFFF1F1F1),
      hover: Color(0xFFE0E0E0),
      selected: Color(0xFFD9D9D9),
      border: Color(0xFFD4D4D4),
      control: Color(0xFFB0B0B0),
      text: Color(0xFF2B2B2B),
      textMuted: Color(0xFF4F4F4F),
      textSubtle: Color(0xFF5C5C5C),
      primary: Color(0xFFC13F14),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFFD9461A),
      accentText: Color(0xFFA9380F),
      accentSoft: Color(0xFFFBE3D8),
      info: Color(0xFF1A65C2),
      infoSoft: Color(0xFFE3EDFA),
      infoLine: Color(0xFFAFCBEF),
      warn: Color(0xFFA55800),
      warnSoft: Color(0xFFFCEFD9),
      warnLine: Color(0xFFEBC68A),
      danger: Color(0xFFB81D27),
      dangerSoft: Color(0xFFFBE6E6),
      dangerLine: Color(0xFFECB2B4),
      tagWarm: Color(0xFF7F5300),
      tagWarmSoft: Color(0xFFF5EACD),
      scrim: Color(0x4D000000),
    ),
    shape: _berenjenaShape,
    terminal: ThemePalettes.berenjena,
    terminalDark: ThemePalettes.berenjena,
  );

  /// A shelter terminal: one phosphor, the active tab inverted, square.
  /// Red stays for danger: production must never look like a lab.
  static final bunker = OwTheme(
    id: 'bunker',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF051209),
      surface: Color(0xFF071A0D),
      raised: Color(0xFF0B2414),
      sunken: Color(0xFF040E07),
      hover: Color(0xFF0E2C18),
      selected: Color(0xFF12381F),
      border: Color(0xFF174526),
      control: Color(0xFF2A6E41),
      text: Color(0xFF8CFFB4),
      textMuted: Color(0xFF66DD94),
      textSubtle: Color(0xFF55C881),
      primary: Color(0xFF4DFF91),
      onPrimary: Color(0xFF03140A),
      accent: Color(0xFF4DFF91),
      accentText: Color(0xFF7DFFAA),
      accentSoft: Color(0xFF0F361D),
      info: Color(0xFFB2FFD6),
      infoSoft: Color(0xFF0D2B1C),
      infoLine: Color(0xFF2C6B4A),
      warn: Color(0xFFE1FF6B),
      warnSoft: Color(0xFF1B2309),
      warnLine: Color(0xFF4C5E1C),
      danger: Color(0xFFFF7259),
      dangerSoft: Color(0xFF2B110C),
      dangerLine: Color(0xFF77301F),
      tagWarm: Color(0xFFE1FF6B),
      tagWarmSoft: Color(0xFF1B2309),
      scrim: Color(0xCC000000),
    ),
    shape: const OwShape(
      radiusSmall: 0,
      radius: 0,
      radiusLarge: 0,
      tabs: TabStyle.block,
    ),
    fonts: const OwFonts(
      ui: 'Share Tech Mono',
      display: 'VT323',
      label: 'Share Tech Mono',
      monoFont: 'Share Tech Mono',
      terminal: 'Share Tech Mono',
    ),
    terminal: ThemePalettes.bunker,
  );

  /// Green text on indigo navy, a blue-grey window and a green accent.
  static final marino = OwTheme(
    id: 'marino',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF1E2030),
      surface: Color(0xFF1A1C2B),
      raised: Color(0xFF262939),
      sunken: Color(0xFF151724),
      hover: Color(0xFF2A2D3F),
      selected: Color(0xFF30344A),
      border: Color(0xFF2A2D3E),
      control: Color(0xFF40445B),
      text: Color(0xFFF2F3F6),
      textMuted: Color(0xFFBABECD),
      textSubtle: Color(0xFFA3A7BA),
      primary: Color(0xFF22B565),
      onPrimary: Color(0xFF08160F),
      accent: Color(0xFF22B565),
      accentText: Color(0xFF52D18D),
      accentSoft: Color(0xFF173730),
      info: Color(0xFF5AA2FF),
      infoSoft: Color(0xFF192840),
      infoLine: Color(0xFF2D4C78),
      warn: Color(0xFFF0B44C),
      warnSoft: Color(0xFF2C2416),
      warnLine: Color(0xFF5E4A22),
      danger: Color(0xFFFF6B73),
      dangerSoft: Color(0xFF33191F),
      dangerLine: Color(0xFF723039),
      tagWarm: Color(0xFFF0B44C),
      tagWarmSoft: Color(0xFF2C2416),
      scrim: Color(0x990A0C16),
    ),
    shape: const OwShape(
      radiusSmall: 6,
      radius: 8,
      radiusLarge: 12,
      tabs: TabStyle.segment,
    ),
    fonts: const OwFonts(
      monoFont: 'JetBrains Mono',
      terminal: 'JetBrains Mono',
    ),
    terminal: ThemePalettes.marino,
  );

  static const _famousFonts = OwFonts(
    ui: 'IBM Plex Sans',
    monoFont: 'JetBrains Mono',
    terminal: 'JetBrains Mono',
  );

  static const _catppuccinShape = OwShape(
    radiusSmall: 6,
    radius: 8,
    radiusLarge: 12,
    pills: true,
    tabs: TabStyle.pill,
  );

  /// Catppuccin Latte, for the whole window.
  static final catppuccinLatte = OwTheme(
    id: 'catppuccin-latte',
    colors: const OwColors(
      brightness: Brightness.light,
      window: Color(0xFFE6E9EF),
      surface: Color(0xFFEFF1F5),
      raised: Color(0xFFF9FAFC),
      sunken: Color(0xFFDCE0E8),
      hover: Color(0xFFE1E4EB),
      selected: Color(0xFFDCE0E8),
      border: Color(0xFFD3D7E0),
      control: Color(0xFFACB0BE),
      text: Color(0xFF4C4F69),
      textMuted: Color(0xFF5C5F77),
      textSubtle: Color(0xFF5C5F77),
      primary: Color(0xFF8839EF),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF8839EF),
      accentText: Color(0xFF7A2FD9),
      accentSoft: Color(0xFFE6DCFA),
      info: Color(0xFF1D5BD6),
      infoSoft: Color(0xFFDFE7F8),
      infoLine: Color(0xFFA9C0F0),
      warn: Color(0xFFA84C06),
      warnSoft: Color(0xFFF7E4D6),
      warnLine: Color(0xFFE9B48F),
      danger: Color(0xFFB80D32),
      dangerSoft: Color(0xFFF5DDE2),
      dangerLine: Color(0xFFE3A3B1),
      tagWarm: Color(0xFF85570A),
      tagWarmSoft: Color(0xFFF3E6CC),
      scrim: Color(0x4D4C4F69),
    ),
    shape: _catppuccinShape,
    fonts: _famousFonts,
    terminal: ThemePalettes.catppuccinLatte,
    terminalDark: ThemePalettes.catppuccinMocha,
  );

  /// Catppuccin Mocha, for the whole window.
  static final catppuccinMocha = OwTheme(
    id: 'catppuccin-mocha',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF181825),
      surface: Color(0xFF1E1E2E),
      raised: Color(0xFF313244),
      sunken: Color(0xFF11111B),
      hover: Color(0xFF2A2B3C),
      selected: Color(0xFF45475A),
      border: Color(0xFF313244),
      control: Color(0xFF585B70),
      text: Color(0xFFCDD6F4),
      textMuted: Color(0xFFBAC2DE),
      textSubtle: Color(0xFFB4BBD6),
      primary: Color(0xFFCBA6F7),
      onPrimary: Color(0xFF11111B),
      accent: Color(0xFFCBA6F7),
      accentText: Color(0xFFCBA6F7),
      accentSoft: Color(0xFF3A3350),
      info: Color(0xFF89B4FA),
      infoSoft: Color(0xFF252E44),
      infoLine: Color(0xFF46598A),
      warn: Color(0xFFFAB387),
      warnSoft: Color(0xFF3A2E30),
      warnLine: Color(0xFF7D5C55),
      danger: Color(0xFFF38BA8),
      dangerSoft: Color(0xFF3A2B3B),
      dangerLine: Color(0xFF7A4D63),
      tagWarm: Color(0xFFF9E2AF),
      tagWarmSoft: Color(0xFF3A3741),
      scrim: Color(0x9911111B),
    ),
    shape: _catppuccinShape,
    fonts: _famousFonts,
    terminal: ThemePalettes.catppuccinMocha,
  );

  static const _draculaShape = OwShape(radius: 6);

  /// Alucard, Dracula's light, for the whole window.
  static final alucard = OwTheme(
    id: 'alucard',
    colors: const OwColors(
      brightness: Brightness.light,
      window: Color(0xFFF4EFD9),
      surface: Color(0xFFFFFBEB),
      raised: Color(0xFFFFFDF6),
      sunken: Color(0xFFEFEAD3),
      hover: Color(0xFFECE6CE),
      selected: Color(0xFFE6E2D6),
      border: Color(0xFFE3DCC2),
      control: Color(0xFFB5AE94),
      text: Color(0xFF1F1F1F),
      textMuted: Color(0xFF4A4636),
      textSubtle: Color(0xFF5C5640),
      primary: Color(0xFF644AC9),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF644AC9),
      accentText: Color(0xFF5A41BA),
      accentSoft: Color(0xFFE9E2F6),
      info: Color(0xFF036A96),
      infoSoft: Color(0xFFE0EEF0),
      infoLine: Color(0xFF9CC7D6),
      warn: Color(0xFF8F430F),
      warnSoft: Color(0xFFF7E8D6),
      warnLine: Color(0xFFDDB28F),
      danger: Color(0xFFA82E20),
      dangerSoft: Color(0xFFF8E2D9),
      dangerLine: Color(0xFFE3A99D),
      tagWarm: Color(0xFF6E5B10),
      tagWarmSoft: Color(0xFFF1EAC8),
      scrim: Color(0x4D1F1F1F),
    ),
    shape: _draculaShape,
    fonts: _famousFonts,
    terminal: ThemePalettes.alucard,
    terminalDark: ThemePalettes.dracula,
  );

  /// Dracula, for the whole window.
  static final dracula = OwTheme(
    id: 'dracula',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF21222C),
      surface: Color(0xFF282A36),
      raised: Color(0xFF343746),
      sunken: Color(0xFF191A21),
      hover: Color(0xFF2F3141),
      selected: Color(0xFF44475A),
      border: Color(0xFF2F3141),
      control: Color(0xFF565B7A),
      text: Color(0xFFF8F8F2),
      textMuted: Color(0xFFCDD0E2),
      textSubtle: Color(0xFFB8BCD4),
      primary: Color(0xFFBD93F9),
      onPrimary: Color(0xFF191A21),
      accent: Color(0xFFBD93F9),
      accentText: Color(0xFFC9A6FA),
      accentSoft: Color(0xFF3D3557),
      info: Color(0xFF8BE9FD),
      infoSoft: Color(0xFF2A3B48),
      infoLine: Color(0xFF4D7F91),
      warn: Color(0xFFFFB86C),
      warnSoft: Color(0xFF3D3536),
      warnLine: Color(0xFF86684D),
      danger: Color(0xFFFF7A7A),
      dangerSoft: Color(0xFF3A2A33),
      dangerLine: Color(0xFF8A4248),
      tagWarm: Color(0xFFF1FA8C),
      tagWarmSoft: Color(0xFF3A3F3E),
      scrim: Color(0x99191A21),
    ),
    shape: _draculaShape,
    fonts: _famousFonts,
    terminal: ThemePalettes.dracula,
  );

  static const _tokyoShape = OwShape(radius: 6, tabs: TabStyle.segment);

  /// Tokyo Night Day, for the whole window.
  static final tokyoNightDay = OwTheme(
    id: 'tokyo-night-day',
    colors: const OwColors(
      brightness: Brightness.light,
      window: Color(0xFFD6D8E1),
      surface: Color(0xFFECEDF0),
      raised: Color(0xFFF4F5F7),
      sunken: Color(0xFFD0D5E3),
      hover: Color(0xFFCED1DD),
      selected: Color(0xFFC8CCDB),
      border: Color(0xFFC8CBD8),
      control: Color(0xFF9AA0BB),
      text: Color(0xFF2C4C99),
      textMuted: Color(0xFF3A4F8A),
      textSubtle: Color(0xFF434D7D),
      primary: Color(0xFF2563C9),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF2468D1),
      accentText: Color(0xFF1C54AA),
      accentSoft: Color(0xFFD3DCF0),
      info: Color(0xFF005E7E),
      infoSoft: Color(0xFFCBDDE5),
      infoLine: Color(0xFF86B3C6),
      warn: Color(0xFF8A4700),
      warnSoft: Color(0xFFE6D6C8),
      warnLine: Color(0xFFC9A27E),
      danger: Color(0xFFB01242),
      dangerSoft: Color(0xFFF0DCE3),
      dangerLine: Color(0xFFD891A8),
      tagWarm: Color(0xFF6E5530),
      tagWarmSoft: Color(0xFFE1DBCF),
      scrim: Color(0x4D3760BF),
    ),
    shape: _tokyoShape,
    fonts: _famousFonts,
    terminal: ThemePalettes.tokyoNightDay,
    terminalDark: ThemePalettes.tokyoNight,
  );

  /// Tokyo Night, for the whole window.
  static final tokyoNight = OwTheme(
    id: 'tokyo-night',
    colors: const OwColors(
      brightness: Brightness.dark,
      window: Color(0xFF16161E),
      surface: Color(0xFF1A1B26),
      raised: Color(0xFF1F2335),
      sunken: Color(0xFF13131A),
      hover: Color(0xFF222436),
      selected: Color(0xFF292E42),
      border: Color(0xFF232433),
      control: Color(0xFF3B4261),
      text: Color(0xFFC0CAF5),
      textMuted: Color(0xFFA9B1D6),
      textSubtle: Color(0xFF9AA2CC),
      primary: Color(0xFF7AA2F7),
      onPrimary: Color(0xFF16161E),
      accent: Color(0xFF7AA2F7),
      accentText: Color(0xFF7AA2F7),
      accentSoft: Color(0xFF283457),
      info: Color(0xFF7DCFFF),
      infoSoft: Color(0xFF1D2C3D),
      infoLine: Color(0xFF3A6A8C),
      warn: Color(0xFFFF9E64),
      warnSoft: Color(0xFF33261F),
      warnLine: Color(0xFF7A4F38),
      danger: Color(0xFFF7768E),
      dangerSoft: Color(0xFF33212B),
      dangerLine: Color(0xFF7A3F4E),
      tagWarm: Color(0xFFE0AF68),
      tagWarmSoft: Color(0xFF2E2A26),
      scrim: Color(0x9916161E),
    ),
    shape: _tokyoShape,
    fonts: _famousFonts,
    terminal: ThemePalettes.tokyoNight,
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
      monitor,
      berenjenaOscuro,
      berenjenaClaro,
      bunker,
      marino,
      catppuccinLatte,
      catppuccinMocha,
      alucard,
      dracula,
      tokyoNightDay,
      tokyoNight,
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
    ThemeFamily('monitor', 'Monitor', dark: monitor),
    ThemeFamily(
      'berenjena',
      'Berenjena',
      light: berenjenaClaro,
      dark: berenjenaOscuro,
    ),
    ThemeFamily('bunker', 'Búnker', dark: bunker),
    ThemeFamily('marino', 'Marino', dark: marino),
    ThemeFamily(
      'catppuccin',
      'Catppuccin',
      light: catppuccinLatte,
      dark: catppuccinMocha,
    ),
    ThemeFamily('dracula', 'Dracula', light: alucard, dark: dracula),
    ThemeFamily(
      'tokyo-night',
      'Tokyo Night',
      light: tokyoNightDay,
      dark: tokyoNight,
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
    // Links and secondary actions in the text's color, underlined on
    // hover: the accent is for what is alive, chosen or the main action.
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            foregroundColor: c.text,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: control,
          ).copyWith(
            textStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                decoration: states.contains(WidgetState.hovered)
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
            ),
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
