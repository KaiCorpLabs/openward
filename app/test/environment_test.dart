import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/app_localizations_en.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/ui/environment.dart';
import 'package:openward/ui/themes.dart';

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

HostView _host(String label, {int? favorite}) => HostView(
  id: label,
  label: label,
  address: '$label.example.com',
  tags: const [],
  user: 'ops',
  port: 22,
  protocol: ProtocolKind.ssh,
  terminalScheme: '',
  startupSnippet: '',
  favorite: favorite,
);

void main() {
  for (final theme in OwThemes.all.values) {
    test('${theme.id}: every mark reads on its chip and on the surface', () {
      final c = theme.colors;
      for (final name in envColorNames) {
        final colors = envColors(c, name);
        expect(
          _contrast(colors.fg, colors.soft),
          greaterThanOrEqualTo(4.5),
          reason: '$name on its chip',
        );
        expect(
          _contrast(colors.fg, c.surface),
          greaterThanOrEqualTo(3),
          reason: '$name line on the surface',
        );
      }
    });
  }

  test('an unknown color is drawn gray', () {
    final c = OwThemes.grafito.colors;
    expect(envColors(c, 'teal').fg, envColors(c, 'gray').fg);
  });

  test('every install offers four marks, each with its own color', () {
    final presets = envPresets(AppLocalizationsEs());
    expect(
      [for (final p in presets) p.short],
      ['prod', 'pre', 'pruebas', 'casa'],
    );
    expect({for (final p in presets) p.color}.length, 4);
  });

  test('favorites come in their order, the rest are not among them', () {
    final library = Library(
      hosts: [
        _host('a', favorite: 2),
        _host('b'),
        _host('c', favorite: 0),
        _host('d', favorite: 1),
      ],
      groups: const [],
    );
    expect([for (final h in library.favorites) h.label], ['c', 'd', 'a']);
  });

  /// A mark of the four, made in Spanish, reads in English in English;
  /// one of the user's own stays as they wrote it.
  test('the built-in marks read in the interface\'s language', () {
    final es = AppLocalizationsEs(), en = AppLocalizationsEn();
    final made = envPresets(es).first;
    expect(made.name, 'Producción');
    expect(shownEnv(en, made).name, envPresets(en).first.name);
    expect(shownEnv(es, made), made);
    const own = EnvironmentView(name: 'Cliente', short: 'cli', color: 'red');
    expect(shownEnv(en, own), own);
  });
}
