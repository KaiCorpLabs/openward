// OpenWard's mark, Umbral: an open O and a detached chevron. The two paths
// of assets/brand/umbral/svg, on their 1024-unit grid.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The mark, in the theme's accent unless told otherwise: Grafito's accent
/// is the brand's turquoise, and every accent stands out from its theme's
/// backgrounds. Drawn from the vector paths, so it is sharp at any size.
class UmbralMark extends StatelessWidget {
  const UmbralMark({super.key, this.size = 24, this.color, this.semanticLabel});

  /// The side of the square it is drawn in, clear space included.
  final double size;
  final Color? color;

  /// Only where the mark stands for the app on its own; beside the name it
  /// is decoration.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: UmbralPainter(color ?? context.ow.colors.accent),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: mark)
        : Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class UmbralPainter extends CustomPainter {
  const UmbralPainter(this.color);

  final Color color;

  /// The silhouette (x 160–814, y 212–812) with the brand's clear space of
  /// 49 units around it.
  static const box = Rect.fromLTWH(111, 163, 752, 698);

  static final Path path = Path()
    // The open O: the outer arc round the left, the inner one back.
    ..moveTo(689.813, 319.164)
    ..arcToPoint(
      const Offset(689.813, 704.836),
      radius: const Radius.circular(300),
      largeArc: true,
      clockwise: false,
    )
    ..lineTo(614.741, 641.843)
    ..arcToPoint(
      const Offset(614.741, 382.157),
      radius: const Radius.circular(202),
      largeArc: true,
    )
    ..close()
    // The chevron.
    ..moveTo(727, 403)
    ..lineTo(814, 512)
    ..lineTo(727, 621)
    ..lineTo(683, 566)
    ..lineTo(726, 512)
    ..lineTo(683, 458)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / box.width, size.height / box.height);
    canvas
      ..translate(
        (size.width - box.width * scale) / 2,
        (size.height - box.height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-box.left, -box.top)
      ..drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(UmbralPainter oldDelegate) => oldDelegate.color != color;
}
