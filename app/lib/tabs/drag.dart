import '../core/platform.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import '../ui/tokens.dart';
import 'tabs.dart';

/// What can be dragged around the window: a tab, a pane by its header, or
/// a host from the sidebar. Dropped on a terminal, it takes half of it;
/// on the tab bar, a place there.
sealed class WindowDrag {
  const WindowDrag();

  String get label;
}

final class TabDrag extends WindowDrag {
  const TabDrag(this.tab, this.label);

  final OpenTab tab;
  @override
  final String label;
}

final class PaneDrag extends WindowDrag {
  const PaneDrag(this.tab, this.pane, this.label);

  final SessionTab tab;
  final Pane pane;
  @override
  final String label;
}

final class HostDrag extends WindowDrag {
  const HostDrag(this.host);

  final HostView host;
  @override
  String get label => host.label;
}

/// What a pane is called before numbering: its session's title, or «new
/// pane» while it asks what to open.
String paneTitle(BuildContext context, Pane pane) =>
    pane.controller?.displayTitle ?? context.l10n.newPane;

/// Esc while dragging: nothing is dropped. It does not reach the terminal
/// either.
final dragCancelled = ValueNotifier<bool>(false);

bool _onKey(KeyEvent e) {
  if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
    dragCancelled.value = true;
    return true;
  }
  return false;
}

void _dragStarted() {
  dragCancelled.value = false;
  HardwareKeyboard.instance.addHandler(_onKey);
}

void _dragEnded() => HardwareKeyboard.instance.removeHandler(_onKey);

/// Makes `child` draggable as `data`, with its label following the
/// pointer. Clicks on `child` still work: a drag starts once it moves.
class WindowDraggable extends StatelessWidget {
  const WindowDraggable({
    super.key,
    required this.data,
    required this.child,
    this.subtitle,
    this.onStarted,
  });

  final WindowDrag data;
  final Widget child;
  final String? subtitle;

  /// Once the pointer has moved enough for a drag, not just a click.
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context) => Draggable<WindowDrag>(
    data: data,
    // On a touch screen a drag is a scroll; dropping into panes is the
    // desktop's.
    maxSimultaneousDrags: touchFirst ? 0 : null,
    dragAnchorStrategy: pointerDragAnchorStrategy,
    feedback: DragGhost(label: data.label, subtitle: subtitle),
    childWhenDragging: Opacity(opacity: 0.4, child: child),
    onDragStarted: () {
      _dragStarted();
      onStarted?.call();
    },
    onDragEnd: (_) => _dragEnded(),
    child: child,
  );
}

/// The label that follows the pointer while dragging.
class DragGhost extends StatelessWidget {
  const DragGhost({super.key, required this.label, this.subtitle});

  final String label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    return Transform.translate(
      // Beside the pointer, not under it: what it is over stays in view.
      offset: const Offset(14, 10),
      child: Material(
        color: c.raised,
        elevation: 8,
        borderRadius: BorderRadius.circular(ow.shape.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: OwSpace.s6,
            vertical: OwSpace.s3,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: c.control),
            borderRadius: BorderRadius.circular(ow.shape.radius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: c.text,
                  fontSize: OwText.body,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontFamily: ow.fonts.mono,
                    fontSize: OwText.small,
                    color: c.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The half of a pane nearest to `local`, over a box of `size`.
DropSide sideAt(Offset local, Size size) {
  final x = size.width == 0 ? 0.5 : local.dx / size.width;
  final y = size.height == 0 ? 0.5 : local.dy / size.height;
  final distances = {
    DropSide.left: x,
    DropSide.right: 1 - x,
    DropSide.top: y,
    DropSide.bottom: 1 - y,
  };
  return distances.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
}

/// A pane that takes tabs, panes and hosts dropped on one of its halves.
class PaneDropTarget extends ConsumerStatefulWidget {
  const PaneDropTarget({
    super.key,
    required this.tab,
    required this.pane,
    required this.child,
  });

  final SessionTab tab;
  final Pane pane;
  final Widget child;

  @override
  ConsumerState<PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends ConsumerState<PaneDropTarget> {
  DropSide? _side;

  /// Dropped on itself, a terminal splits around it: a tab of one pane,
  /// or a pane by its header.
  bool _onItself(WindowDrag d) => switch (d) {
    TabDrag(:final tab) =>
      identical(tab, widget.tab) && !widget.tab.panes.isSplit,
    PaneDrag(:final pane) => identical(pane, widget.pane),
    HostDrag() => false,
  };

  bool _accepts(WindowDrag d) =>
      _onItself(d) ||
      switch (d) {
        TabDrag(:final tab) => tab is SessionTab && !identical(tab, widget.tab),
        PaneDrag(:final tab) =>
          !(identical(tab, widget.tab) && !tab.panes.isSplit),
        HostDrag() => true,
      };

  void _track(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final side = sideAt(box.globalToLocal(global), box.size);
    if (side != _side) setState(() => _side = side);
  }

  void _drop(WindowDrag d) {
    final side = _side;
    setState(() => _side = null);
    if (side == null || dragCancelled.value) return;
    final tabs = ref.read(tabsProvider.notifier);
    if (_onItself(d)) return tabs.splitAround(widget.tab, widget.pane, side);
    switch (d) {
      case TabDrag(:final tab):
        tabs.dropTab(tab, widget.tab, widget.pane, side);
      case PaneDrag(:final tab, :final pane):
        tabs.dropPane(tab, pane, widget.tab, widget.pane, side);
      case HostDrag(:final host):
        tabs.dropHost(host, widget.tab, widget.pane, side);
    }
  }

  @override
  Widget build(BuildContext context) => DragTarget<WindowDrag>(
    onWillAcceptWithDetails: (d) => _accepts(d.data),
    onMove: (d) => _track(d.offset),
    onLeave: (_) => setState(() => _side = null),
    onAcceptWithDetails: (d) => _drop(d.data),
    builder: (context, candidates, _) {
      final over = candidates.whereType<WindowDrag>().firstOrNull;
      return Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (over != null && _side != null)
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: dragCancelled,
                builder: (context, cancelled, _) => cancelled
                    ? const SizedBox.shrink()
                    : DropZone(
                        side: _side!,
                        label: _onItself(over)
                            ? splitAroundLabel(context, over, _side!)
                            : dropLabel(
                                context,
                                over,
                                _side!,
                                pane: paneNames(
                                  widget.tab.panes,
                                  (p) => paneTitle(context, p),
                                )[widget.pane],
                              ),
                      ),
              ),
            ),
        ],
      );
    },
  );
}

/// What dropping `d` on `side` of `pane` would do, in words: «Soltar:
/// lab-1 a la derecha de Local 2».
String dropLabel(
  BuildContext context,
  WindowDrag d,
  DropSide side, {
  String? pane,
}) {
  final l = context.l10n;
  final where = pane == null
      ? switch (side) {
          DropSide.left => l.dropLeft,
          DropSide.right => l.dropRight,
          DropSide.top => l.dropTop,
          DropSide.bottom => l.dropBottom,
        }
      : switch (side) {
          DropSide.left => l.dropLeftOf(pane),
          DropSide.right => l.dropRightOf(pane),
          DropSide.top => l.dropAbove(pane),
          DropSide.bottom => l.dropBelow(pane),
        };
  return d is HostDrag
      ? l.dropOpenHost(d.label, where)
      : l.dropMove(d.label, where);
}

/// What dropping a terminal on a half of itself does: «Soltar: web-1 a la
/// derecha; a la izquierda, un panel nuevo».
String splitAroundLabel(BuildContext context, WindowDrag d, DropSide side) {
  final l = context.l10n;
  return switch (side) {
    DropSide.left => l.dropSplitAround(d.label, l.dropLeft, l.dropRight),
    DropSide.right => l.dropSplitAround(d.label, l.dropRight, l.dropLeft),
    DropSide.top => l.dropSplitAround(d.label, l.dropTop, l.dropBottom),
    DropSide.bottom => l.dropSplitAround(d.label, l.dropBottom, l.dropTop),
  };
}

/// The half a drop would take, marked over the pane.
class DropZone extends StatelessWidget {
  const DropZone({super.key, required this.side, required this.label});

  final DropSide side;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final horizontal = side.axis == Axis.horizontal;
    final zone = FractionallySizedBox(
      widthFactor: horizontal ? 0.5 : 1,
      heightFactor: horizontal ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.all(OwSpace.s3),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.accentSoft.withValues(alpha: 0.6),
            border: Border.all(color: c.accent, width: 2),
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: OwSpace.s6,
              vertical: OwSpace.s3,
            ),
            decoration: BoxDecoration(
              color: c.raised,
              border: Border.all(color: c.accent),
              borderRadius: BorderRadius.circular(context.ow.shape.round),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: c.accentText,
                fontSize: OwText.small,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
    return IgnorePointer(
      child: Align(
        alignment: switch (side) {
          DropSide.left => Alignment.centerLeft,
          DropSide.right => Alignment.centerRight,
          DropSide.top => Alignment.topCenter,
          DropSide.bottom => Alignment.bottomCenter,
        },
        child: zone,
      ),
    );
  }
}
