// Terminal color schemes: the proposed themes' own, and a gallery of known
// ones. The known schemes are published under the MIT license by their
// authors (NOTICE); the values are copied as they publish them.

import 'palette.dart';

/// A terminal color scheme with a name, for galleries and settings.
class TerminalScheme {
  const TerminalScheme(this.id, this.name, this.palette);

  /// Stable, as settings keep it. Imported schemes start with `custom:`.
  final String id;
  final String name;
  final TermPalette palette;

  Map<String, Object> toJson() => {'id': id, 'name': name, ...palette.toJson()};

  static TerminalScheme? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'];
    final palette = TermPalette.fromJson(json);
    if (id is! String || name is! String || palette == null) return null;
    return TerminalScheme(id, name, palette);
  }
}

/// The scheme `id` names, among the gallery's and those imported
/// (`imported`); null if there is none by that id.
TerminalScheme? schemeById(String id, List<TerminalScheme> imported) {
  if (id.isEmpty) return null;
  for (final s in [...knownSchemes, ...imported]) {
    if (s.id == id) return s;
  }
  return null;
}

abstract final class ThemePalettes {
  /// Papel's terminal when it is set to stay dark: the warm card of the
  /// first proposal.
  static final papelOscuro = TermPalette.hex(
    foreground: '#E8E4DC',
    background: '#1C1B19',
    cursor: '#E8E4DC',
    selection: '#3E5C55',
    ansi: [
      '#2A2825', '#F2766B', '#5ED6BF', '#F2B36B', //
      '#9DB8F5', '#D7A3F0', '#7FD6E8', '#E8E4DC',
      '#6F6A61', '#FF968C', '#8BE6D3', '#F7CB93',
      '#BBCEF8', '#E6C2F6', '#A6E5F0', '#FFFFFF',
    ],
  );

  static final fosforo = TermPalette.hex(
    foreground: '#C9D6CE',
    background: '#0A0D0B',
    cursor: '#5CF2B5',
    selection: '#1F5A44',
    ansi: [
      '#1A2420', '#FF7A6B', '#5CF2B5', '#F2C14E', //
      '#7FB8FF', '#D29BFF', '#7FD6E8', '#C9D6CE',
      '#4F6359', '#FF9C90', '#8CF7CD', '#F7D57E',
      '#A5CCFF', '#E2BDFF', '#A8E5F0', '#EAF5EE',
    ],
  );

  static final nativoOscuro = TermPalette.hex(
    foreground: '#E5E5E7',
    background: '#1E1E1E',
    cursor: '#C7C7CC',
    selection: '#1B4F8C',
    ansi: [
      '#3A3A3C', '#FF6961', '#32D74B', '#FFD60A', //
      '#409CFF', '#DA8FFF', '#64D2FF', '#E5E5E7',
      '#8E8E93', '#FF8A80', '#5AE87A', '#FFE066',
      '#70B4FF', '#E5A9FF', '#8CDEFF', '#FFFFFF',
    ],
  );

  static final nativoClaro = TermPalette.hex(
    foreground: '#1D1D1F',
    background: '#FFFFFF',
    cursor: '#1D1D1F',
    selection: '#9EC5F0',
    ansi: [
      '#1D1D1F', '#C9302C', '#1E7F33', '#8A6D00', //
      '#0060C0', '#8E3DBA', '#0B7285', '#6E6E73',
      '#8E8E93', '#E0413B', '#248A3D', '#A67C00',
      '#0A84FF', '#A550D0', '#1592A6', '#AEAEB2',
    ],
  );

  static final contrasteOscuro = TermPalette.hex(
    foreground: '#FFFFFF',
    background: '#000000',
    cursor: '#FFE14D',
    selection: '#665A1F',
    ansi: [
      '#666666', '#FF6B6B', '#5CFF5C', '#FFE14D', //
      '#6BB8FF', '#FF8CFF', '#5CFFFF', '#E6E6E6',
      '#9E9E9E', '#FF9E9E', '#9EFF9E', '#FFF09E',
      '#A8D4FF', '#FFB8FF', '#9EFFFF', '#FFFFFF',
    ],
  );

  static final contrasteClaro = TermPalette.hex(
    foreground: '#000000',
    background: '#FFFFFF',
    cursor: '#000000',
    selection: '#8FA8E6',
    ansi: [
      '#000000', '#A30000', '#006600', '#6B4F00', //
      '#0033A0', '#7A0099', '#005F6B', '#4D4D4D',
      '#333333', '#C00000', '#007A00', '#7A5C00',
      '#0040C0', '#8F00B3', '#00707D', '#1A1A1A',
    ],
  );

  /// Monitor's: green phosphor that keeps the programs' colors.
  static final monitor = TermPalette.hex(
    foreground: '#33FF66',
    background: '#040904',
    cursor: '#33FF66',
    selection: '#1C5E30',
    ansi: [
      '#0F2A17', '#FF5C57', '#33FF66', '#E6F25C', //
      '#5CB8FF', '#E07CFF', '#4DF2E0', '#A8E6B8',
      '#3E7A50', '#FF8A80', '#8AFFA6', '#F5FF8A',
      '#8FD0FF', '#EEA8FF', '#8AFFF0', '#E6FFEC',
    ],
  );

  /// Berenjena's, in light and dark: Tango on aubergine, its blue and
  /// gray lifted to read there.
  static final berenjena = TermPalette.hex(
    foreground: '#FFFFFF',
    background: '#300A24',
    cursor: '#FFFFFF',
    selection: '#7A4D6E',
    ansi: [
      '#2E3436', '#EF2929', '#73D216', '#EDD400', //
      '#729FCF', '#C49BC0', '#2BC4C4', '#D3D7CF',
      '#888A85', '#FF6B6B', '#8AE234', '#FCE94F',
      '#9DBFEA', '#DDB8D9', '#5FF0F0', '#EEEEEC',
    ],
  );

  /// Búnker's: one phosphor; each color a brightness.
  static final bunker = TermPalette.hex(
    foreground: '#66FF9F',
    background: '#071A0D',
    cursor: '#66FF9F',
    selection: '#1E6B3D',
    ansi: [
      '#123A20', '#3BBF6A', '#66FF9F', '#B8FFD2', //
      '#2E9E58', '#4FD785', '#94FFC0', '#7DF0AA',
      '#2C7247', '#5FE08E', '#8CFFB8', '#DAFFE8',
      '#45BE74', '#73EBA2', '#BBFFD7', '#EDFFF4',
    ],
  );

  /// Marino's: green text on indigo navy.
  static final marino = TermPalette.hex(
    foreground: '#21B263',
    background: '#131729',
    cursor: '#21B263',
    selection: '#1F4A3E',
    ansi: [
      '#262B3F', '#E5484F', '#0E9A6E', '#DDB03E', //
      '#2E73C9', '#C8378A', '#2B92F5', '#BAC0D0',
      '#666D87', '#FF6B73', '#3DDC86', '#F2CC5C',
      '#5A9BEA', '#E163A6', '#5CB2FF', '#EEF0F6',
    ],
  );

  /// Catppuccin Mocha, as published.
  static final catppuccinMocha = TermPalette.hex(
    foreground: '#CDD6F4',
    background: '#1E1E2E',
    cursor: '#F5E0DC',
    selection: '#585B70',
    ansi: [
      '#45475A', '#F38BA8', '#A6E3A1', '#F9E2AF', //
      '#89B4FA', '#F5C2E7', '#94E2D5', '#BAC2DE',
      '#585B70', '#F38BA8', '#A6E3A1', '#F9E2AF',
      '#89B4FA', '#F5C2E7', '#94E2D5', '#A6ADC8',
    ],
  );

  /// Catppuccin Latte, as published.
  static final catppuccinLatte = TermPalette.hex(
    foreground: '#4C4F69',
    background: '#EFF1F5',
    cursor: '#DC8A78',
    selection: '#ACB0BE',
    ansi: [
      '#5C5F77', '#D20F39', '#40A02B', '#DF8E1D', //
      '#1E66F5', '#EA76CB', '#179299', '#ACB0BE',
      '#6C6F85', '#D20F39', '#40A02B', '#DF8E1D',
      '#1E66F5', '#EA76CB', '#179299', '#BCC0CC',
    ],
  );

  /// Dracula, as published.
  static final dracula = TermPalette.hex(
    foreground: '#F8F8F2',
    background: '#282A36',
    cursor: '#F8F8F2',
    selection: '#44475A',
    ansi: [
      '#21222C', '#FF5555', '#50FA7B', '#F1FA8C', //
      '#BD93F9', '#FF79C6', '#8BE9FD', '#F8F8F2',
      '#6272A4', '#FF6E6E', '#69FF94', '#FFFFA5',
      '#D6ACFF', '#FF92DF', '#A4FFFF', '#FFFFFF',
    ],
  );

  /// Alucard, Dracula's light palette, as published.
  static final alucard = TermPalette.hex(
    foreground: '#1F1F1F',
    background: '#FFFBEB',
    cursor: '#1F1F1F',
    selection: '#CFCFDE',
    ansi: [
      '#FFFBEB', '#CB3A2A', '#14710A', '#846E15', //
      '#644AC9', '#A3144D', '#036A96', '#1F1F1F',
      '#6C664B', '#D74C3D', '#198D0C', '#9E841A',
      '#7862D0', '#BF185A', '#047FB4', '#2C2B31',
    ],
  );

  /// Tokyo Night, as published.
  static final tokyoNight = TermPalette.hex(
    foreground: '#C0CAF5',
    background: '#1A1B26',
    cursor: '#C0CAF5',
    selection: '#33467C',
    ansi: [
      '#15161E', '#F7768E', '#9ECE6A', '#E0AF68', //
      '#7AA2F7', '#BB9AF7', '#7DCFFF', '#A9B1D6',
      '#414868', '#F7768E', '#9ECE6A', '#E0AF68',
      '#7AA2F7', '#BB9AF7', '#7DCFFF', '#C0CAF5',
    ],
  );

  /// Tokyo Night Day; its foreground (#3760BF) a touch darker to read
  /// at 4.5:1 on its background.
  static final tokyoNightDay = TermPalette.hex(
    foreground: '#3459B5',
    background: '#E1E2E7',
    cursor: '#3760BF',
    selection: '#B7C1E3',
    ansi: [
      '#B4B5B9', '#F52A65', '#587539', '#8C6C3E', //
      '#2E7DE9', '#9854F1', '#007197', '#6172B0',
      '#A1A6C5', '#FF4774', '#5C8524', '#A27629',
      '#358AFF', '#A463FF', '#007EA8', '#3760BF',
    ],
  );
}

/// Well-known schemes, to pick for any theme.
final knownSchemes = <TerminalScheme>[
  TerminalScheme(
    'solarized-dark',
    'Solarized Dark',
    TermPalette.hex(
      foreground: '#839496',
      background: '#002B36',
      cursor: '#93A1A1',
      ansi: [
        '#073642', '#DC322F', '#859900', '#B58900', //
        '#268BD2', '#D33682', '#2AA198', '#EEE8D5',
        '#002B36', '#CB4B16', '#586E75', '#657B83',
        '#839496', '#6C71C4', '#93A1A1', '#FDF6E3',
      ],
    ),
  ),
  TerminalScheme(
    'solarized-light',
    'Solarized Light',
    TermPalette.hex(
      foreground: '#657B83',
      background: '#FDF6E3',
      cursor: '#586E75',
      ansi: [
        '#073642', '#DC322F', '#859900', '#B58900', //
        '#268BD2', '#D33682', '#2AA198', '#EEE8D5',
        '#002B36', '#CB4B16', '#586E75', '#657B83',
        '#839496', '#6C71C4', '#93A1A1', '#FDF6E3',
      ],
    ),
  ),
  TerminalScheme('dracula', 'Dracula', ThemePalettes.dracula),
  TerminalScheme('alucard', 'Alucard', ThemePalettes.alucard),
  TerminalScheme(
    'nord',
    'Nord',
    TermPalette.hex(
      foreground: '#D8DEE9',
      background: '#2E3440',
      cursor: '#D8DEE9',
      selection: '#434C5E',
      ansi: [
        '#3B4252', '#BF616A', '#A3BE8C', '#EBCB8B', //
        '#81A1C1', '#B48EAD', '#88C0D0', '#E5E9F0',
        '#4C566A', '#BF616A', '#A3BE8C', '#EBCB8B',
        '#81A1C1', '#B48EAD', '#8FBCBB', '#ECEFF4',
      ],
    ),
  ),
  TerminalScheme(
    'gruvbox-dark',
    'Gruvbox Dark',
    TermPalette.hex(
      foreground: '#EBDBB2',
      background: '#282828',
      cursor: '#EBDBB2',
      selection: '#504945',
      ansi: [
        '#282828', '#CC241D', '#98971A', '#D79921', //
        '#458588', '#B16286', '#689D6A', '#A89984',
        '#928374', '#FB4934', '#B8BB26', '#FABD2F',
        '#83A598', '#D3869B', '#8EC07C', '#EBDBB2',
      ],
    ),
  ),
  TerminalScheme(
    'gruvbox-light',
    'Gruvbox Light',
    TermPalette.hex(
      foreground: '#3C3836',
      background: '#FBF1C7',
      cursor: '#3C3836',
      selection: '#D5C4A1',
      ansi: [
        '#FBF1C7', '#CC241D', '#98971A', '#D79921', //
        '#458588', '#B16286', '#689D6A', '#7C6F64',
        '#928374', '#9D0006', '#79740E', '#B57614',
        '#076678', '#8F3F71', '#427B58', '#3C3836',
      ],
    ),
  ),
  TerminalScheme(
    'one-dark',
    'One Dark',
    TermPalette.hex(
      foreground: '#ABB2BF',
      background: '#282C34',
      cursor: '#528BFF',
      selection: '#3E4451',
      ansi: [
        '#282C34', '#E06C75', '#98C379', '#E5C07B', //
        '#61AFEF', '#C678DD', '#56B6C2', '#ABB2BF',
        '#5C6370', '#E06C75', '#98C379', '#E5C07B',
        '#61AFEF', '#C678DD', '#56B6C2', '#FFFFFF',
      ],
    ),
  ),
  TerminalScheme('tokyo-night', 'Tokyo Night', ThemePalettes.tokyoNight),
  TerminalScheme(
    'tokyo-night-day',
    'Tokyo Night Day',
    ThemePalettes.tokyoNightDay,
  ),
  TerminalScheme(
    'catppuccin-mocha',
    'Catppuccin Mocha',
    ThemePalettes.catppuccinMocha,
  ),
  TerminalScheme(
    'catppuccin-latte',
    'Catppuccin Latte',
    ThemePalettes.catppuccinLatte,
  ),
];
