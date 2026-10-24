// How a connection looks while it comes up, while the server does not
// answer, once it is lost and when it is back: the way from this computer
// to the host, drawn and animated (still when motion is reduced).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../terminal/controller.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'connection_panels.dart';
import 'messages.dart';
import 'tabs.dart';

/// A stretch of the way between two machines.
enum LinkState { done, going, ahead, broken }

/// A machine on the way.
class RouteNode {
  const RouteNode(
    this.label, {
    this.server = true,
    this.sub,
    this.tone = NodeTone.ahead,
    this.ring = false,
  });

  final String label;
  final bool server;
  final String? sub;
  final NodeTone tone;

  /// Pulses: it is being reached.
  final bool ring;
}

enum NodeTone { reached, current, ahead, warn, gone }

/// This computer, the jump hosts and the target in a row, with what links
/// them: reached, being reached (dots that travel), still ahead, or broken.
class RouteGraphic extends StatefulWidget {
  const RouteGraphic({super.key, required this.nodes, required this.links})
    : assert(links.length == nodes.length - 1);

  final List<RouteNode> nodes;
  final List<LinkState> links;

  @override
  State<RouteGraphic> createState() => _RouteGraphicState();
}

class _RouteGraphicState extends State<RouteGraphic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.stop();
      _t.value = 0.5;
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Color _color(OwColors c, NodeTone tone) => switch (tone) {
    NodeTone.reached => c.accent,
    NodeTone.current => c.text,
    NodeTone.ahead => c.textSubtle,
    NodeTone.warn => c.warn,
    NodeTone.gone => c.textSubtle,
  };

  Widget _node(BuildContext context, RouteNode n) {
    final c = context.ow.colors;
    final color = _color(c, n.tone);
    final dim = n.tone == NodeTone.gone || n.tone == NodeTone.ahead;
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 84,
      child: Opacity(
        opacity: n.tone == NodeTone.gone ? 0.5 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 52,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (n.ring && !still)
                    AnimatedBuilder(
                      animation: _t,
                      builder: (context, _) {
                        final v = _t.value;
                        return Transform.scale(
                          scale: 0.9 + v * 0.7,
                          child: Opacity(
                            opacity: (1 - v).clamp(0, 1),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: color, width: 2),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.sunken,
                      border: Border.all(
                        color: color,
                        width: n.ring && still ? 2.5 : 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      n.server ? Icons.dns_outlined : Icons.laptop_mac,
                      size: 22,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              n.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: dim ? c.textMuted : c.text,
              ),
            ),
            if (n.sub != null)
              Text(
                n.sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context, size: 12, color: c.textSubtle),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final children = <Widget>[];
    for (var i = 0; i < widget.nodes.length; i++) {
      children.add(_node(context, widget.nodes[i]));
      if (i < widget.links.length) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: SizedBox(
                height: 52,
                child: AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) => CustomPaint(
                    painter: _LinkPainter(
                      state: widget.links[i],
                      t: _t.value,
                      accent: c.accent,
                      warn: c.warn,
                      line: c.control,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _LinkPainter extends CustomPainter {
  _LinkPainter({
    required this.state,
    required this.t,
    required this.accent,
    required this.warn,
    required this.line,
  });

  final LinkState state;
  final double t;
  final Color accent, warn, line;

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 5.0, gap = 4.0;
    final length = (b - a).distance;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, length), p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const pad = 6.0;
    final a = Offset(pad, y), b = Offset(size.width - pad, y);
    final solid = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    switch (state) {
      case LinkState.done:
        canvas.drawLine(a, b, solid..color = accent);
      case LinkState.ahead:
        _dashed(canvas, a, b, solid..color = line);
      case LinkState.going:
        _dashed(canvas, a, b, solid..color = line);
        final dot = Paint()..color = accent;
        for (var k = 0; k < 3; k++) {
          final p = (t + k / 3) % 1;
          // Fades in and out at the ends.
          final alpha = math.min(1.0, math.min(p, 1 - p) * 6);
          canvas.drawCircle(
            Offset.lerp(a, b, p)!,
            4,
            dot..color = accent.withValues(alpha: alpha),
          );
        }
      case LinkState.broken:
        final mid = Offset.lerp(a, b, 0.5)!;
        canvas.drawLine(a, mid - const Offset(8, 0), solid..color = warn);
        _dashed(
          canvas,
          mid + const Offset(8, 0),
          b,
          solid..color = line.withValues(alpha: 0.6),
        );
        final x = Paint()
          ..color = warn
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          mid + const Offset(-4, -4),
          mid + const Offset(4, 4),
          x,
        );
        canvas.drawLine(
          mid + const Offset(-4, 4),
          mid + const Offset(4, -4),
          x,
        );
        // A try that does not get across.
        final p = (t * 1.3).clamp(0.0, 1.0);
        final alpha = p < 0.8 ? 1.0 : (1 - p) * 5;
        canvas.drawCircle(
          Offset.lerp(a, mid - const Offset(10, 0), p)!,
          4,
          Paint()..color = warn.withValues(alpha: alpha.clamp(0, 1)),
        );
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.t != t || old.state != state || old.accent != accent;
}

/// The way of `s` as it connects: this computer, then each hop.
RouteGraphic connectingRoute(AppLocalizations l, ConnectionController s) {
  final hops = s.route.isEmpty ? [s.label] : s.route;
  final current = s.stage?.hop ?? 0;
  return RouteGraphic(
    nodes: [
      RouteNode(l.thisComputer, server: false, tone: NodeTone.reached),
      for (var i = 0; i < hops.length; i++)
        RouteNode(
          hops[i],
          tone: i < current
              ? NodeTone.reached
              : i == current
              ? NodeTone.current
              : NodeTone.ahead,
          ring: i == current,
        ),
    ],
    links: [
      for (var i = 0; i < hops.length; i++)
        i < current
            ? LinkState.done
            : i == current
            ? LinkState.going
            : LinkState.ahead,
    ],
  );
}

/// `1 min 12 s`, `40 s`.
String awayText(AppLocalizations l, Duration d) {
  final s = d.inSeconds;
  return s >= 60 ? l.durationMinSec(s ~/ 60, s % 60) : l.durationSec(s);
}

/// Over the terminal while the server does not answer: since when, and that
/// it is being checked. Nothing is cut yet.
class StalledNotice extends StatefulWidget {
  const StalledNotice({super.key, required this.controller});

  final ConnectionController controller;

  @override
  State<StalledNotice> createState() => _StalledNoticeState();
}

class _StalledNoticeState extends State<StalledNotice> {
  // Started in initState: a `late` initializer runs at the first read,
  // which would be dispose().
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final since = widget.controller.stalledSince;
    if (since == null) return const SizedBox.shrink();
    final secs = DateTime.now().difference(since).inSeconds;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('pane.stalled'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: c.warnSoft,
          border: Border.all(color: c.warnLine),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Blink(),
            const SizedBox(width: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: l.notResponding(widget.controller.label),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' · ${l.sinceSeconds(secs)}'),
                ],
              ),
              style: TextStyle(fontSize: 12, color: c.text),
            ),
            const SizedBox(width: 10),
            Text(
              l.checking,
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A warning dot that blinks (still when motion is reduced).
class _Blink extends StatefulWidget {
  const _Blink();

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.stop();
      _t.value = 1;
    } else if (!_t.isAnimating) {
      _t.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.25, end: 1.0).animate(_t),
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: context.ow.colors.warn,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// Over a terminal whose connection was lost: the way broken, the next try
/// and when, and what is kept (a tmux session) or not (an ordinary shell).
class ReconnectCard extends ConsumerStatefulWidget {
  const ReconnectCard({super.key, required this.controller});

  final ConnectionController controller;

  @override
  ConsumerState<ReconnectCard> createState() => _ReconnectCardState();
}

class _ReconnectCardState extends ConsumerState<ReconnectCard> {
  // Started in initState: a `late` initializer runs at the first read,
  // which would be dispose().
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  /// Why it was lost, in words.
  String _why(AppLocalizations l, FailureView f) {
    if (f.kind != FailureKind.network) return failureText(l, f);
    return switch (f.net) {
      NetKind.silent when f.seconds > 0 => l.noAnswerFor(f.seconds),
      NetKind.lost => '',
      _ => networkReason(l, f),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = widget.controller;
    final r = s.reconnecting;
    final at = s.reconnectAt;
    final trying = at == null || DateTime.now().isAfter(at);
    final max = ref.read(openWardProvider).reconnectAttempts();
    final kept = switch (s.persistent?.state) {
      PersistenceKind.new_ || PersistenceKind.resumed => true,
      _ => false,
    };
    final why = r == null ? '' : _why(l, r.reason);
    final graphic = trying
        ? RouteGraphic(
            nodes: [
              RouteNode(l.thisComputer, server: false, tone: NodeTone.reached),
              RouteNode(s.label, tone: NodeTone.current, ring: true),
            ],
            links: const [LinkState.going],
          )
        : RouteGraphic(
            nodes: [
              RouteNode(l.thisComputer, server: false, tone: NodeTone.warn),
              RouteNode(s.label, sub: l.noResponse, tone: NodeTone.gone),
            ],
            links: const [LinkState.broken],
          );
    final Widget next;
    if (!trying && r != null) {
      final total = Duration(milliseconds: r.delayMs.toInt());
      final left = at.difference(DateTime.now());
      final secs = (left.inMilliseconds / 1000).ceil().clamp(0, 60);
      final share = total.inMilliseconds == 0
          ? 0.0
          : (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
      next = Row(
        children: [
          SizedBox.square(
            dimension: 30,
            child: CircularProgressIndicator(
              value: share,
              strokeWidth: 3,
              color: c.warn,
              backgroundColor: c.warnLine,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.retryIn(r.attempt, max, secs),
              style: TextStyle(color: c.text),
            ),
          ),
        ],
      );
    } else {
      final stage = s.stage;
      next = Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.text),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              stage == null
                  ? l.reconnectingEllipsis
                  : l.reconnectingStage(stageText(l, stage)),
              style: TextStyle(color: c.text),
            ),
          ),
        ],
      );
    }
    return Semantics(
      liveRegion: true,
      child: OverlayPanel(
        key: const ValueKey('pane.reconnect'),
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.connectionLostTitle(s.label),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (why.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(why, style: TextStyle(color: c.textMuted)),
            ],
            const SizedBox(height: 16),
            graphic,
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: c.warnSoft,
                border: Border.all(color: c.warnLine),
                borderRadius: BorderRadius.circular(ow.shape.radius),
              ),
              child: next,
            ),
            const SizedBox(height: 12),
            Text(
              kept ? l.lostKeptInTmux(s.label) : l.lostNewShell(s.label),
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const ValueKey('reconnect.close'),
                  onPressed: () =>
                      ref.read(tabsProvider.notifier).closeConnection(s),
                  child: Text(l.closeTab),
                ),
                if (!trying) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('reconnect.now'),
                    onPressed: s.start,
                    child: Text(l.retryNow),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// For a few seconds after a connection came back: how long it was away,
/// and whether the tmux session was found again.
class BackToast extends StatefulWidget {
  const BackToast({super.key, required this.controller});

  final ConnectionController controller;

  @override
  State<BackToast> createState() => _BackToastState();
}

class _BackToastState extends State<BackToast> {
  Timer? _hide;

  static const shown = Duration(seconds: 4);

  void _arm() {
    _hide?.cancel();
    final back = widget.controller.backAt;
    if (back == null) return;
    final left = shown - DateTime.now().difference(back);
    if (left > Duration.zero) {
      _hide = Timer(left, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(BackToast old) {
    super.didUpdateWidget(old);
    _arm();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = widget.controller;
    final back = s.backAt;
    final away = s.lastOutage;
    final visible =
        back != null && away != null && DateTime.now().difference(back) < shown;
    final resumed = s.persistent?.state == PersistenceKind.resumed;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: !visible
            ? const SizedBox.shrink()
            : Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('pane.back'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: c.raised,
                    border: Border.all(color: c.accent),
                    borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: c.accent,
                      ),
                      const SizedBox(width: 10),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: l.backAgain(s.label),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: resumed
                                  ? ' · ${l.sessionResumed}'
                                  : ' · ${l.awayFor(awayText(l, away))}',
                            ),
                          ],
                        ),
                        style: TextStyle(fontSize: 12, color: c.text),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// While the server does not answer: a thin bar across the top that moves
/// (still when motion is reduced).
class StalledBar extends StatelessWidget {
  const StalledBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: still ? 1 : null,
        color: c.warn,
        backgroundColor: c.warnSoft,
      ),
    );
  }
}

/// The comeback line's words for a terminal, in the interface's language.
String comebackWords(AppLocalizations l, DateTime at, Duration away) {
  return l.comebackLine(
    DateFormat.Hm(l.localeName).format(at),
    awayText(l, away),
  );
}

/// Pill for the status bar: the shell is in tmux (or tmux was missing).
Widget tmuxPill(BuildContext context, PersistentView p) {
  final l = context.l10n;
  final c = context.ow.colors;
  final missing = p.state == PersistenceKind.noTmux;
  return Tooltip(
    message: missing ? l.tmuxMissingTip : l.tmuxTip,
    child: Padding(
      padding: const EdgeInsets.only(left: 8),
      child: missing
          ? Text(l.tmuxMissing, style: TextStyle(fontSize: 12, color: c.warn))
          : const Pill('tmux'),
    ),
  );
}
