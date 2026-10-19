import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/ui/themes.dart';
import 'package:openward/ui/umbral.dart';

void main() {
  test("the mark's paths are the brand's silhouette", () {
    // The SVG's open O (radius 300 round 460, 512) and chevron (to 814),
    // measured along the outline: getBounds counts the arcs' control
    // points.
    var b = Rect.zero;
    for (final metric in UmbralPainter.path.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += 0.5) {
        final p = metric.getTangentForOffset(d)!.position;
        b = b == Rect.zero
            ? Rect.fromPoints(p, p)
            : b.expandToInclude(Rect.fromPoints(p, p));
      }
    }
    expect(b.left, closeTo(160, 0.5));
    expect(b.top, closeTo(212, 0.5));
    expect(b.right, closeTo(814, 0.5));
    expect(b.bottom, closeTo(812, 0.5));
    // The gap of the O and the one before the chevron stay open.
    expect(UmbralPainter.path.contains(const Offset(460, 512)), isFalse);
    expect(UmbralPainter.path.contains(const Offset(700, 512)), isFalse);
    expect(UmbralPainter.path.contains(const Offset(212, 512)), isTrue);
    expect(UmbralPainter.path.contains(const Offset(760, 512)), isTrue);
  });

  testWidgets("it takes the theme's accent and stays out of the way of "
      'screen readers beside the name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.monitor),
        home: const Center(child: UmbralMark(size: 40)),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(UmbralMark),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(
      (paint.painter! as UmbralPainter).color,
      OwThemes.monitor.colors.accent,
    );
    expect(tester.getSize(find.byType(UmbralMark)), const Size(40, 40));
    expect(find.bySemanticsLabel('OpenWard'), findsNothing);
  });

  testWidgets('alone, it says what it is', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.papel),
        home: const Center(
          child: UmbralMark(size: 48, semanticLabel: 'OpenWard'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('OpenWard'), findsOneWidget);
  });
}
