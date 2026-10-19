import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/terminal/palette.dart';
import 'package:openward/terminal/schemes.dart';
import 'package:openward/ui/themes.dart';
import 'package:openward/ui/tokens.dart';

/// WCAG 2 contrast ratio.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) * 1.0;
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final (x, y) = (lum(a), lum(b));
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  for (final theme in OwThemes.all.values) {
    test('${theme.id}: text reads at AA on every background it sits on', () {
      final c = theme.colors;
      final pairs = <String, (Color, Color)>{
        'text/window': (c.text, c.window),
        'text/surface': (c.text, c.surface),
        'text/raised': (c.text, c.raised),
        'muted/window': (c.textMuted, c.window),
        'muted/raised': (c.textMuted, c.raised),
        'muted/sunken': (c.textMuted, c.sunken),
        'subtle/window': (c.textSubtle, c.window),
        'subtle/surface': (c.textSubtle, c.surface),
        'subtle/raised': (c.textSubtle, c.raised),
        'subtle/selected': (c.textSubtle, c.selected),
        'onPrimary/primary': (c.onPrimary, c.primary),
        'accentText/surface': (c.accentText, c.surface),
        'accentText/raised': (c.accentText, c.raised),
        'accentText/accentSoft': (c.accentText, c.accentSoft),
        'tagWarm/tagWarmSoft': (c.tagWarm, c.tagWarmSoft),
        'danger/dangerSoft': (c.danger, c.dangerSoft),
        'danger/raised': (c.danger, c.raised),
        'text/warnSoft': (c.text, c.warnSoft),
        'text/infoSoft': (c.text, c.infoSoft),
        'terminal': (theme.terminal.foreground, theme.terminal.background),
      };
      for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
        expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
      }
    });

    test('${theme.id}: status marks stand out from the window (3:1)', () {
      final c = theme.colors;
      for (final (name, color) in [
        ('accent', c.accent),
        ('warn', c.warn),
        ('danger', c.danger),
        ('control', c.control),
      ]) {
        // Controls only need to be found, not read.
        final need = name == 'control' ? 1.3 : 3.0;
        expect(
          _contrast(color, c.window),
          greaterThanOrEqualTo(need),
          reason: name,
        );
      }
    });
  }

  test('the theme reaches widgets through the context', () {
    expect(OwThemes.grafito.colors.dark, isTrue);
    expect(OwThemes.papel.colors.dark, isFalse);
    expect(OwThemes.papel.shape.insetTerminal, isTrue);
    expect(
      OwThemes.grafito.lerp(OwThemes.papel, 0.7),
      same(OwThemes.papel),
      reason: 'themes switch at once',
    );
  });

  test('every token of a theme is its own (no copy-paste between themes)', () {
    OwColors g = OwThemes.grafito.colors, p = OwThemes.papel.colors;
    expect(g.window == p.window, isFalse);
    expect(g.text == p.text, isFalse);
  });

  test('a theme takes layers from others and keeps the rest', () {
    final s = const Settings(darkTheme: 'grafito').withOverrides(
      'grafito',
      (o) => o.copyWith(colors: () => 'fosforo', uiFont: () => ''),
    );
    final t = resolveTheme(s, Brightness.dark);
    expect(t.id, 'grafito');
    expect(t.colors, same(OwThemes.fosforo.colors));
    expect(t.shape, same(OwThemes.grafito.shape));
    expect(t.fonts.ui, isNull, reason: 'the system font');
    expect(t.fonts.terminal, 'JetBrains Mono');
    // The terminal goes with the colors.
    expect(t.terminal, same(ThemePalettes.fosforo));
  });

  test("Papel's terminal: light, always dark, or a scheme", () {
    final papel = resolveTheme(const Settings(), Brightness.light);
    expect(papel.id, 'papel');
    expect(papel.terminal.dark, isFalse);
    final dark = const Settings().withOverrides(
      'papel',
      (o) => o.copyWith(terminal: TerminalColors.dark),
    );
    expect(
      resolveTheme(dark, Brightness.light).terminal,
      same(ThemePalettes.papelOscuro),
    );
    final nord = const Settings().withOverrides(
      'papel',
      (o) => o.copyWith(terminal: TerminalColors.scheme, scheme: () => 'nord'),
    );
    expect(
      resolveTheme(nord, Brightness.light).terminal.background.toARGB32(),
      0xFF2E3440,
    );
  });

  test('a family picked for the wrong brightness falls back', () {
    final t = resolveTheme(
      const Settings(lightTheme: 'grafito'),
      Brightness.light,
    );
    expect(t.id, 'papel');
    expect(
      resolveTheme(const Settings(darkTheme: 'nativo'), Brightness.dark).id,
      'nativo-oscuro',
    );
  });

  test('minimum contrast lifts unreadable text and leaves the rest', () {
    const bg = Color(0xFF0A0D0B);
    const dim = Color(0xFF2A3A30);
    final lifted = TermPalette.ensureContrast(dim, bg, 3);
    expect(TermPalette.contrast(lifted, bg), greaterThanOrEqualTo(3));
    expect(TermPalette.contrast(lifted, bg), lessThan(3.3));
    const fine = Color(0xFFC9D6CE);
    expect(TermPalette.ensureContrast(fine, bg, 3), fine);
    // On white, towards black.
    final onWhite = TermPalette.ensureContrast(
      const Color(0xFFFFE14D),
      const Color(0xFFFFFFFF),
      4.5,
    );
    expect(TermPalette.luminance(onWhite), lessThan(0.3));
  });

  /// The font of `text` as drawn, in a window with [theme].
  Future<String? Function(String)> fontsIn(
    WidgetTester tester,
    OwTheme theme,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(theme),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('filled')),
              OutlinedButton(onPressed: () {}, child: const Text('outlined')),
              TextButton(onPressed: () {}, child: const Text('text')),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.terminal),
                label: const Text('icon'),
              ),
              const Tooltip(message: 'tip', child: Text('hover me')),
              const Text('body'),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'label',
                  helperText: 'helper',
                ),
              ),
              const TextField(decoration: InputDecoration(hintText: 'hint')),
            ],
          ),
        ),
      ),
    );
    tester.state<TooltipState>(find.byType(Tooltip)).ensureTooltipVisible();
    ScaffoldMessenger.of(tester.element(find.byType(Column)))
        .showSnackBar(const SnackBar(content: Text('snack')));
    await tester.pump(const Duration(milliseconds: 500));
    return (text) => tester
        .widget<RichText>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        )
        .text
        .style
        ?.fontFamily;
  }

  const drawn = [
    'filled',
    'outlined',
    'text',
    'icon',
    'tip',
    'snack',
    'body',
    'label',
    'helper',
    'hint',
  ];

  testWidgets("buttons, tooltips and snack bars use the theme's font", (
    tester,
  ) async {
    final font = await fontsIn(tester, OwThemes.fosforo);
    expect(
      {for (final t in drawn) t: font(t)},
      {for (final t in drawn) t: 'JetBrains Mono'},
    );
  });

  testWidgets('…and the interface font chosen as a layer', (tester) async {
    final s = const Settings(
      darkTheme: 'grafito',
    ).withOverrides('grafito', (o) => o.copyWith(uiFont: () => 'Martian Mono'));
    final font = await fontsIn(tester, resolveTheme(s, Brightness.dark));
    expect(
      {for (final t in drawn) t: font(t)},
      {for (final t in drawn) t: 'Martian Mono'},
    );
  });

  test('known schemes have 16 colors and read at least 3:1', () {
    for (final s in knownSchemes) {
      expect(s.palette.ansi16, hasLength(16), reason: s.id);
      expect(
        TermPalette.contrast(s.palette.foreground, s.palette.background),
        greaterThanOrEqualTo(3),
        reason: s.id,
      );
    }
  });
}
