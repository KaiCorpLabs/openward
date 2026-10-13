import 'dart:math' as math;
import 'dart:ui' as ui;

/// Box drawing (U+2500–U+257F), block elements (U+2580–U+259F) and the
/// Powerline separators (U+E0B0–U+E0B3) drawn as geometry that fills the
/// cell exactly, so lines join across cells with no gaps. Fonts draw these
/// with their own metrics, which rarely match the cell.
///
/// Everything is drawn in whole device pixels into [rect] (a cell, in device
/// pixels) with [color]; the atlas then tints it like any other glyph.
abstract final class BoxDrawing {
  static bool handles(int r) =>
      (r >= 0x2500 && r <= 0x259F) || (r >= 0xE0B0 && r <= 0xE0B3);

  static void paint(
    ui.Canvas canvas,
    int r,
    ui.Rect rect,
    double devicePixelRatio,
    ui.Color color,
  ) {
    final c = _Cell(canvas, rect, devicePixelRatio, color);
    if (r >= 0x2580 && r <= 0x259F) {
      c.block(r);
    } else if (r >= 0xE0B0) {
      c.powerline(r);
    } else if (r >= 0x256D && r <= 0x2570) {
      c.arc(r);
    } else if (r >= 0x2571 && r <= 0x2573) {
      c.diagonal(r);
    } else if (_dashes.containsKey(r)) {
      final (vertical, heavy, n) = _dashes[r]!;
      c.dashes(vertical: vertical, heavy: heavy, count: n);
    } else {
      final arms = _arms[r - 0x2500];
      c.lines(
        up: _w(arms, 0),
        right: _w(arms, 1),
        down: _w(arms, 2),
        left: _w(arms, 3),
      );
    }
  }

  static int _w(String arms, int i) => arms.codeUnitAt(i) - 0x30;

  /// (vertical, heavy, dashes) for the dashed lines.
  static const _dashes = {
    0x2504: (false, false, 3),
    0x2505: (false, true, 3),
    0x2506: (true, false, 3),
    0x2507: (true, true, 3),
    0x2508: (false, false, 4),
    0x2509: (false, true, 4),
    0x250A: (true, false, 4),
    0x250B: (true, true, 4),
    0x254C: (false, false, 2),
    0x254D: (false, true, 2),
    0x254E: (true, false, 2),
    0x254F: (true, true, 2),
  };

  /// Arm weights up, right, down, left for U+2500… (0 none, 1 light,
  /// 2 heavy, 3 double). Dashes, arcs and diagonals are handled apart.
  static const _arms = [
    '0101', '0202', '1010', '2020', '----', '----', '----', '----', // 2500
    '----', '----', '----', '----', '0110', '0210', '0120', '0220', // 2508
    '0011', '0012', '0021', '0022', '1100', '1200', '2100', '2200', // 2510
    '1001', '1002', '2001', '2002', '1110', '1210', '2110', '1120', // 2518
    '2120', '2210', '1220', '2220', '1011', '1012', '2011', '1021', // 2520
    '2021', '2012', '1022', '2022', '0111', '0112', '0211', '0212', // 2528
    '0121', '0122', '0221', '0222', '1101', '1102', '1201', '1202', // 2530
    '2101', '2102', '2201', '2202', '1111', '1112', '1211', '1212', // 2538
    '2111', '1121', '2121', '2112', '2211', '1122', '1221', '2212', // 2540
    '1222', '2122', '2221', '2222', '----', '----', '----', '----', // 2548
    '0303', '3030', '0310', '0130', '0330', '0013', '0031', '0033', // 2550
    '1300', '3100', '3300', '1003', '3001', '3003', '1310', '3130', // 2558
    '3330', '1013', '3031', '3033', '0313', '0131', '0333', '1303', // 2560
    '3101', '3303', '1313', '3131', '3333', '----', '----', '----', // 2568
    '----', '----', '----', '----', '0001', '1000', '0100', '0010', // 2570
    '0002', '2000', '0200', '0020', '0201', '1020', '0102', '2010', // 2578
  ];
}

class _Cell {
  _Cell(this.canvas, this.rect, double dpr, ui.Color color)
    : w = rect.width,
      h = rect.height,
      paint = ui.Paint()
        ..color = color
        ..isAntiAlias = false {
    // Light lines are about one logical pixel, whole device pixels.
    light = math.max(1, dpr.round()).toDouble();
    heavy = light * 2;
    gap = light;
    cx = (w / 2).floorToDouble();
    cy = (h / 2).floorToDouble();
  }

  final ui.Canvas canvas;
  final ui.Rect rect;
  final double w;
  final double h;
  final ui.Paint paint;
  late final double light;
  late final double heavy;

  /// Half the distance between the two strokes of a double line.
  late final double gap;
  late final double cx;
  late final double cy;

  double _t(int weight) => weight == 2 ? heavy : light;

  void _fill(double l, double t, double r, double b) {
    if (r <= l || b <= t) return;
    canvas.drawRect(
      ui.Rect.fromLTRB(
        rect.left + l,
        rect.top + t,
        rect.left + r,
        rect.top + b,
      ),
      paint,
    );
  }

  /// A horizontal stroke of thickness [t] centered on [y], from [x0] to [x1].
  void _h(double x0, double x1, double y, double t) => _fill(
    math.min(x0, x1),
    y - (t / 2).floor(),
    math.max(x0, x1),
    y - (t / 2).floor() + t,
  );

  void _v(double y0, double y1, double x, double t) => _fill(
    x - (t / 2).floor(),
    math.min(y0, y1),
    x - (t / 2).floor() + t,
    math.max(y0, y1),
  );

  void lines({
    required int up,
    required int right,
    required int down,
    required int left,
  }) {
    final fl = (light / 2).floorToDouble();
    // Edges of the double strokes: the near and far side of each one.
    double before(double p) => p - fl;
    double after(double p) => p - fl + light;
    final hDouble = (left == 3 ? 1 : 0) + (right == 3 ? 1 : 0);
    final vDouble = (up == 3 ? 1 : 0) + (down == 3 ? 1 : 0);
    // Thickest single or heavy line through the center, so corners and
    // crossings of plain lines fill completely.
    final t = [
      up,
      right,
      down,
      left,
    ].where((a) => a == 1 || a == 2).map(_t).fold(0.0, math.max);
    final tf = (t / 2).floorToDouble();
    final anyV = up != 0 || down != 0;
    final anyH = left != 0 || right != 0;

    // Single and heavy arms.
    if (left == 1 || left == 2) {
      final end = switch (vDouble) {
        2 => before(cx - gap), // ╢: stop at the left stroke
        1 => after(cx + gap), // ╖: reach the far stroke
        _ => cx - tf + t,
      };
      _h(0, end, cy, _t(left));
    }
    if (right == 1 || right == 2) {
      final start = switch (vDouble) {
        2 => after(cx + gap), // ╟
        1 => before(cx - gap), // ╓
        _ => cx - tf,
      };
      _h(start, w, cy, _t(right));
    }
    if (up == 1 || up == 2) {
      final end = switch (hDouble) {
        2 => before(cy - gap), // ╧
        1 => after(cy + gap), // ╘
        _ => cy - tf + t,
      };
      _v(0, end, cx, _t(up));
    }
    if (down == 1 || down == 2) {
      final start = switch (hDouble) {
        2 => after(cy + gap), // ╤
        1 => before(cy - gap), // ╒
        _ => cy - tf,
      };
      _v(start, h, cx, _t(down));
    }

    // Double arms. Each stroke ends at an inner corner when the arm on its
    // side exists (the inner strokes of ╔ ╦ ╬) and at the outer corner
    // otherwise; against a plain line it stops at that line.
    final vSingle = anyV && vDouble == 0;
    final hSingle = anyH && hDouble == 0;
    if (left == 3) {
      for (final (y, side) in [(cy - gap, up), (cy + gap, down)]) {
        final end = vSingle
            ? cx - tf
            : side != 0
            ? before(cx - gap)
            : after(cx + gap);
        _h(0, end, y, light);
      }
    }
    if (right == 3) {
      for (final (y, side) in [(cy - gap, up), (cy + gap, down)]) {
        final start = vSingle
            ? cx - tf + t
            : side != 0
            ? after(cx + gap)
            : before(cx - gap);
        _h(start, w, y, light);
      }
    }
    if (up == 3) {
      for (final (x, side) in [(cx - gap, left), (cx + gap, right)]) {
        final end = hSingle
            ? cy - tf
            : side != 0
            ? before(cy - gap)
            : after(cy + gap);
        _v(0, end, x, light);
      }
    }
    if (down == 3) {
      for (final (x, side) in [(cx - gap, left), (cx + gap, right)]) {
        final start = hSingle
            ? cy - tf + t
            : side != 0
            ? after(cy + gap)
            : before(cy - gap);
        _v(start, h, x, light);
      }
    }
  }

  void dashes({
    required bool vertical,
    required bool heavy,
    required int count,
  }) {
    final t = heavy ? this.heavy : light;
    final length = vertical ? h : w;
    final segment = length / count;
    // Dashes centered in equal segments, so the pattern repeats across cells.
    final dash = math.max(1.0, (segment * 0.6).roundToDouble());
    for (var i = 0; i < count; i++) {
      final start = (i * segment + (segment - dash) / 2).roundToDouble();
      if (vertical) {
        _v(start, start + dash, cx, t);
      } else {
        _h(start, start + dash, cy, t);
      }
    }
  }

  void arc(int r) {
    // ╭ ╮ ╯ ╰: a quarter circle joining the two half lines.
    final toRight = r == 0x256D || r == 0x2570;
    final toBottom = r == 0x256D || r == 0x256E;
    final radius = math.min(w, h) / 2;
    // Center of the straight lines' stroke, so the arc meets them.
    final fl = (light / 2).floorToDouble();
    final x = rect.left + cx - fl + light / 2;
    final y = rect.top + cy - fl + light / 2;
    final edgeX = toRight ? rect.right : rect.left;
    final edgeY = toBottom ? rect.bottom : rect.top;
    final sx = toRight ? 1 : -1;
    final sy = toBottom ? 1 : -1;
    final path = ui.Path()
      ..moveTo(edgeX, y)
      ..lineTo(x + sx * radius, y)
      ..arcToPoint(
        ui.Offset(x, y + sy * radius),
        radius: ui.Radius.circular(radius),
        clockwise: (sx * sy) < 0,
      )
      ..lineTo(x, edgeY);
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = paint.color
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = light
        ..isAntiAlias = true,
    );
  }

  void diagonal(int r) {
    final stroke = ui.Paint()
      ..color = paint.color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = light
      ..isAntiAlias = true;
    if (r == 0x2571 || r == 0x2573) {
      canvas.drawLine(rect.topRight, rect.bottomLeft, stroke);
    }
    if (r == 0x2572 || r == 0x2573) {
      canvas.drawLine(rect.topLeft, rect.bottomRight, stroke);
    }
  }

  void block(int r) {
    double eighthsW(int n) => (w * n / 8).roundToDouble();
    double eighthsH(int n) => (h * n / 8).roundToDouble();
    switch (r) {
      case 0x2580:
        _fill(0, 0, w, eighthsH(4));
      case >= 0x2581 && <= 0x2588:
        _fill(0, h - eighthsH(r - 0x2580), w, h);
      case >= 0x2589 && <= 0x258F:
        _fill(0, 0, eighthsW(0x2590 - r), h);
      case 0x2590:
        _fill(eighthsW(4), 0, w, h);
      case 0x2591 || 0x2592 || 0x2593:
        final alpha = (r - 0x2590) / 4;
        canvas.drawRect(
          rect,
          ui.Paint()..color = paint.color.withValues(alpha: alpha),
        );
      case 0x2594:
        _fill(0, 0, w, eighthsH(1));
      case 0x2595:
        _fill(w - eighthsW(1), 0, w, h);
      default:
        // Quadrants: bits upper-left, upper-right, lower-left, lower-right.
        const quads = {
          0x2596: 0x4,
          0x2597: 0x8,
          0x2598: 0x1,
          0x2599: 0xD,
          0x259A: 0x9,
          0x259B: 0x7,
          0x259C: 0xB,
          0x259D: 0x2,
          0x259E: 0x6,
          0x259F: 0xE,
        };
        final q = quads[r] ?? 0;
        final mx = eighthsW(4);
        final my = eighthsH(4);
        if (q & 1 != 0) _fill(0, 0, mx, my);
        if (q & 2 != 0) _fill(mx, 0, w, my);
        if (q & 4 != 0) _fill(0, my, mx, h);
        if (q & 8 != 0) _fill(mx, my, w, h);
    }
  }

  void powerline(int r) {
    final solid = r == 0xE0B0 || r == 0xE0B2;
    final pointsRight = r == 0xE0B0 || r == 0xE0B1;
    final l = rect.left, t = rect.top, rr = rect.right, b = rect.bottom;
    final tip = ui.Offset(pointsRight ? rr : l, t + h / 2);
    final base = pointsRight ? l : rr;
    final path = ui.Path()
      ..moveTo(base, t)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(base, b);
    if (solid) path.close();
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = paint.color
        ..style = solid ? ui.PaintingStyle.fill : ui.PaintingStyle.stroke
        ..strokeWidth = light
        ..isAntiAlias = true,
    );
  }
}
