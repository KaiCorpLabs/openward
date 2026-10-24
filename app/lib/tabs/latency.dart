// The connection's latency in sight: the last round trip and a small
// chart of the ones before it, amber when it is well above the usual.
// Hovering shows the chart larger with the route, the key exchange, the
// cipher and the host key; a click opens the connection's details.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/connection.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/session.dart' show TrustKind;
import '../ui/tokens.dart';
import '../ui/widgets.dart' show monoStyle;
import 'connection_panels.dart' show showConnectionInfo;

/// For the status bar: «34 ms» and its chart.
class LatencyChip extends StatelessWidget {
  const LatencyChip({super.key, required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final rtt = c.rttMs;
    if (rtt == null) return const SizedBox.shrink();
    final ow = context.ow;
    final l = context.l10n;
    final color = c.rttHigh ? ow.colors.warn : ow.colors.textMuted;
    return Tooltip(
      key: const ValueKey('status.latency'),
      richMessage: WidgetSpan(child: LatencyCard(controller: c)),
      decoration: BoxDecoration(
        color: ow.colors.raised,
        border: Border.all(color: ow.colors.control),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24)],
      ),
      padding: const EdgeInsets.all(14),
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: Semantics(
        button: true,
        label: c.rttHigh ? l.latencyHighLabel(rtt) : l.latencyLabel(rtt),
        onTap: () => showConnectionInfo(context, c),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(ow.shape.radius),
          onTap: () => showConnectionInfo(context, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // High: more than its color says it.
                if (c.rttHigh)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(Icons.arrow_drop_up, size: 16, color: color),
                  ),
                Text(
                  l.milliseconds(rtt),
                  style: monoStyle(
                    context,
                    size: 12,
                    color: color,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                // A line needs two points.
                if (c.rttHistory.length > 1) ...[
                  const SizedBox(width: 6),
                  Sparkline(values: c.rttHistory, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last round trips as a line, to scale from 0 to the larger of
/// 100 ms and the highest one.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.width = 56,
    this.height = 14,
    this.grid = const [],
    this.threshold,
    this.fill = false,
  });

  final List<int> values;
  final Color color;
  final double width;
  final double height;

  /// Lines across, at these values.
  final List<int> grid;

  /// A dashed line across, at this value.
  final int? threshold;
  final bool fill;

  /// The top of the scale.
  static double top(List<int> values) =>
      math.max(100, values.fold(0, math.max)) * 1.15;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(
      painter: _SparkPainter(
        values,
        color,
        top(values),
        grid,
        threshold,
        fill,
        context.ow.colors.border,
      ),
    ),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(
    this.values,
    this.color,
    this.top,
    this.grid,
    this.threshold,
    this.fill,
    this.gridColor,
  );

  final List<int> values;
  final Color color;
  final double top;
  final List<int> grid;
  final int? threshold;
  final bool fill;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 2.0;
    double y(num v) => size.height - pad - v / top * (size.height - 2 * pad);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final g in grid) {
      canvas.drawLine(
        Offset(pad, y(g)),
        Offset(size.width - pad, y(g)),
        gridPaint,
      );
    }
    final t = threshold;
    if (t != null) {
      final dash = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = pad; x < size.width - pad; x += 7) {
        canvas.drawLine(Offset(x, y(t)), Offset(x + 4, y(t)), dash);
      }
    }
    if (values.isEmpty) return;
    final step = values.length < 2
        ? 0.0
        : (size.width - 2 * pad) / (values.length - 1);
    final points = [
      for (final (i, v) in values.indexed) Offset(pad + i * step, y(v)),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    if (fill && points.length > 1) {
      final area = Path.from(line)
        ..lineTo(points.last.dx, size.height - pad)
        ..lineTo(points.first.dx, size.height - pad)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(points.last, 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values.length != values.length ||
      old.values.lastOrNull != values.lastOrNull ||
      old.color != color ||
      old.top != top;
}

/// Round values for the chart's lines, one to three of them: a step of
/// 25, 50, 100, 200, 500… ms that fits under the top of the scale.
List<int> latencyTicks(double top) {
  const steps = [25, 50, 100, 200, 500, 1000, 2000, 5000, 10000];
  final step = steps.firstWhere((s) => top / s <= 3, orElse: () => steps.last);
  return [for (var v = step; v <= top; v += step) v];
}

/// The hover card: the latency now, its chart, and what the connection is
/// made of.
class LatencyCard extends StatelessWidget {
  const LatencyCard({super.key, required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ow = context.ow;
    final colors = ow.colors;
    final l = context.l10n;
    final k = c.connected;
    final rtt = c.rttMs;
    final usual = c.usualRttMs;
    final high = c.rttHigh;
    final color = high ? colors.warn : colors.accent;
    final top = Sparkline.top(c.rttHistory);
    final ticks = latencyTicks(top);
    final small = TextStyle(fontSize: 12, color: colors.textMuted);
    const chartHeight = 64.0;
    // Where a value falls on the chart, as Sparkline draws it.
    double y(int v) => chartHeight - 2 - v / top * (chartHeight - 4);
    Widget row(String name, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(name, style: small)),
          Expanded(child: value),
        ],
      ),
    );
    Text mono(String text) =>
        Text(text, style: monoStyle(context, size: 12, color: colors.text));
    return DefaultTextStyle(
      style: TextStyle(fontSize: 13, color: colors.text),
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The latency now, large: the chart's scale is at its side.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.latencyWith(c.label),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (usual != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(l.latencyUsual(usual), style: small),
                        ),
                    ],
                  ),
                ),
                if (rtt != null)
                  Text(
                    l.milliseconds(rtt),
                    key: const ValueKey('latency.now'),
                    style: monoStyle(
                      context,
                      size: 18,
                      color: high ? colors.warn : colors.text,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            if (high && rtt != null && usual != null && usual > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.warnSoft,
                  border: Border.all(color: colors.warnLine),
                  borderRadius: BorderRadius.circular(ow.shape.radius),
                ),
                child: Text(
                  l.latencyHigh(rtt, (rtt / usual).round()),
                  style: TextStyle(fontSize: 12, color: colors.warn),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Sparkline(
                  values: c.rttHistory,
                  color: color,
                  width: 308,
                  height: chartHeight,
                  grid: ticks,
                  threshold: high && usual != null ? usual * 3 : null,
                  fill: true,
                ),
                const SizedBox(width: 8),
                // The scale: each line's value, beside it.
                SizedBox(
                  width: 44,
                  height: chartHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final t in ticks)
                        Positioned(
                          left: 0,
                          top: y(t) - 8,
                          child: Text(
                            t == ticks.last ? l.milliseconds(t) : '$t',
                            style: monoStyle(
                              context,
                              size: 12,
                              color: colors.textSubtle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.latencyChecks(c.rttHistory.length),
                    style: small,
                  ),
                ),
                Text(l.agoNow, style: small),
              ],
            ),
            if (k != null) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: colors.border),
              const SizedBox(height: 2),
              if (c.route.length > 1)
                row(
                  l.route,
                  Text.rich(
                    key: const ValueKey('latency.route'),
                    TextSpan(
                      children: [
                        TextSpan(text: l.routeStart),
                        // Each hop with the round trip from here to it.
                        for (final (i, hop) in c.route.indexed) ...[
                          TextSpan(text: ' → $hop'),
                          if ((i == c.route.length - 1
                                  ? rtt
                                  : c.hopRttMs.elementAtOrNull(i))
                              case final ms?)
                            TextSpan(
                              // Kept with its hop on one line.
                              text:
                                  '\u00a0${l.milliseconds(ms).replaceAll(' ', '\u00a0')}',
                              style: monoStyle(
                                context,
                                size: 12,
                                color: colors.textMuted,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              row(
                l.keyExchange,
                mono(k.postQuantum ? l.postQuantumKex(k.kex) : k.kex),
              ),
              row(l.cipher, mono(k.cipher)),
              row(
                l.hostKey,
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: k.hostKeyAlgorithm,
                        style: monoStyle(context, size: 12, color: colors.text),
                      ),
                      TextSpan(
                        text:
                            ' · ${switch (k.trust) {
                              TrustKind.known => l.trustKnown,
                              TrustKind.new_ => l.trustNew,
                              TrustKind.certified => l.trustCertified(k.ca),
                            }}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(l.latencyClick, style: small),
            ],
          ],
        ),
      ),
    );
  }
}
