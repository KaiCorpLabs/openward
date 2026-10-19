import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/ui/environment.dart';
import 'package:openward/ui/svg_path.dart';
import 'package:openward/ui/system_logos.dart';
import 'package:openward/ui/themes.dart';

/// The outline's bounds, measured along it (getBounds counts the curves'
/// control points).
Rect outline(Path path) {
  Rect? b;
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += 0.05) {
      final p = metric.getTangentForOffset(d)!.position;
      final r = Rect.fromPoints(p, p);
      b = b == null ? r : b.expandToInclude(r);
    }
  }
  return b!;
}

void main() {
  group('SVG path data', () {
    test('packed numbers, relative commands and implicit lines', () {
      // «.5.5» is two numbers; after m, more pairs are lines.
      final p = parseSvgPath('m2 2 .5.5h10v1-1zM4,8l2-2');
      final b = p.getBounds();
      expect(b.left, 2);
      expect(b.top, 2);
      expect(b.right, 12.5);
      expect(b.bottom, 8);
      // Between the line back to the start and the one along y = 2.5.
      expect(p.contains(const Offset(10, 2.45)), isTrue);
      expect(p.contains(const Offset(10, 2.6)), isFalse);
    });

    test('arcs, with flags that touch what follows', () {
      // A half circle of radius 5 from (2, 12) to (12, 12), over the top
      // (sweep 1: clockwise on the screen), and the other half back.
      final p = parseSvgPath('M2 12a5 5 0 0110 0A5 5 0 012 12z');
      final b = outline(p);
      expect(b.left, closeTo(2, 0.01));
      expect(b.right, closeTo(12, 0.01));
      expect(b.top, closeTo(7, 0.01));
      expect(b.bottom, closeTo(17, 0.01));
      expect(p.contains(const Offset(7, 12)), isTrue);
      // Over the top only.
      final half = outline(parseSvgPath('M2 12a5 5 0 0110 0'));
      expect(half.top, closeTo(7, 0.01));
      expect(half.bottom, closeTo(12, 0.01));
    });

    test('S and T mirror the last control point', () {
      final s = outline(parseSvgPath('M0 10C0 0 10 0 10 10S20 20 20 10'));
      expect(s.top, closeTo(2.5, 0.05));
      expect(s.bottom, closeTo(17.5, 0.05));
      final t = outline(parseSvgPath('M0 10Q5 0 10 10T20 10'));
      expect(t.top, closeTo(5, 0.05));
      expect(t.bottom, closeTo(15, 0.05));
      // Without a curve before, S's first control point is where it is.
      final alone = outline(parseSvgPath('M0 0S10 10 10 0'));
      expect(alone.bottom, lessThan(10));
    });

    test('exponents, and Z goes back to the start', () {
      final p = parseSvgPath('M1e1 1E1h1e-1zl2 0');
      expect(p.getBounds().left, 10);
      expect(p.getBounds().right, closeTo(12, 1e-9));
    });

    test('what is not a path says so', () {
      for (final bad in ['10 10', 'M1', 'Mx 1', 'M1 1A1 1 0 2 1 2 2', 'Z1']) {
        expect(() => parseSvgPath(bad), throwsFormatException, reason: bad);
      }
    });
  });

  test('each logo fills its 24×24 box and nothing outside it', () {
    expect(systemLogos, isNotEmpty);
    for (final MapEntry(key: code, value: d) in systemLogos.entries) {
      final b = outline(parseSvgPath(d));
      expect(b.left, greaterThanOrEqualTo(-0.05), reason: code);
      expect(b.top, greaterThanOrEqualTo(-0.05), reason: code);
      expect(b.right, lessThanOrEqualTo(24.05), reason: code);
      expect(b.bottom, lessThanOrEqualTo(24.05), reason: code);
      expect(b.longestSide, greaterThan(20), reason: code);
    }
  });

  test('every system can be chosen, with a name and something to show', () {
    final l = AppLocalizationsEs();
    expect(systemCodes.toSet(), hasLength(systemCodes.length));
    expect(systemCodes.last, '?');
    final names = {for (final c in systemCodes) systemName(l, c)};
    expect(names, hasLength(systemCodes.length));
    for (final code in systemCodes) {
      // Four letters at most: the vault keeps it, and a version that does
      // not know it shows it as text.
      expect(code.length, lessThanOrEqualTo(4), reason: code);
      // A logo, except macOS and Windows (whose logos are not lent: an
      // icon) and «?».
      expect(
        systemLogos.containsKey(code),
        !{'mac', 'win', '?'}.contains(code),
        reason: code,
      );
    }
    // No logo that cannot be chosen.
    expect(systemCodes, containsAll(systemLogos.keys));
    expect(systemKnown(null), isFalse);
    expect(systemKnown('?'), isFalse);
    expect(systemKnown('deb'), isTrue);
  });

  Widget badge(String? code, {EnvironmentView? env}) => MaterialApp(
    theme: materialTheme(OwThemes.grafito),
    home: Center(
      child: SystemBadge(code: code, env: env, size: 26),
    ),
  );

  testWidgets("a logo is drawn in its environment's color", (tester) async {
    const prod = EnvironmentView(
      name: 'Producción',
      short: 'prod',
      color: 'red',
    );
    await tester.pumpWidget(badge('deb', env: prod));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(SystemGlyph),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.size, Size.square(26 * 0.6));
    final colors = OwThemes.grafito.colors;
    expect(
      (paint.painter! as SystemLogoPainter).color,
      envColors(colors, 'red').fg,
    );
    expect(
      tester.widget<Container>(find.byType(Container)).decoration,
      isA<BoxDecoration>().having(
        (d) => d.color,
        'fill',
        envColors(colors, 'red').soft,
      ),
    );
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('unknown, it is a server; macOS and Windows, neutral icons; '
      'a newer code, its letters', (tester) async {
    for (final code in [null, '?']) {
      await tester.pumpWidget(badge(code));
      expect(find.byIcon(Icons.dns_outlined), findsOneWidget, reason: code);
      expect(find.byType(Text), findsNothing, reason: code);
    }
    await tester.pumpWidget(badge('mac'));
    expect(find.byIcon(Icons.keyboard_command_key), findsOneWidget);
    await tester.pumpWidget(badge('win'));
    expect(find.byIcon(Icons.window_outlined), findsOneWidget);
    await tester.pumpWidget(badge('hurd'));
    expect(find.text('hurd'), findsOneWidget);
  });
}
