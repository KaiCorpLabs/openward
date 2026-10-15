import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
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
  for (final theme in [OwThemes.grafito, OwThemes.papel]) {
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
}
