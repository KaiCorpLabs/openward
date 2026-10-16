import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../terminal/controller.dart';

/// A node of a tab's layout: one pane, or two parts side by side.
sealed class PaneNode {}

/// One terminal, or, right after a split, none yet: the pane asks what to
/// open in it.
final class Pane extends PaneNode {
  Pane([this.controller, this.from]);

  TerminalController? controller;

  /// The pane it was split from, for "the same host".
  final TerminalController? from;
}

/// Two parts: side by side ([Axis.horizontal]) or one above the other.
final class PaneSplit extends PaneNode {
  PaneSplit(this.axis, this.first, this.second, [this.ratio = 0.5]);

  final Axis axis;
  PaneNode first;
  PaneNode second;

  /// The first part's share of the space.
  double ratio;
}

/// Where something dropped on a pane goes: the half of it that it takes.
enum DropSide {
  left,
  right,
  top,
  bottom;

  Axis get axis =>
      this == left || this == right ? Axis.horizontal : Axis.vertical;

  /// What is dropped comes first (left of, or above, the pane).
  bool get before => this == left || this == top;
}

/// A tab's panes: how they are laid out, which one has the keyboard, and
/// whether what is typed goes to several (broadcast). Broadcast lives with
/// the tab only and is never saved.
class Panes extends ChangeNotifier {
  /// With one pane; its session may come later (tests leave it out).
  Panes(TerminalController? first) : root = Pane(first) {
    active = root as Pane;
  }

  /// Panes laid out already: one taken from another tab, or all of them.
  Panes.of(this.root, {Pane? active}) {
    this.active = active ?? _leaves(root).first;
  }

  PaneNode root;
  late Pane active;

  /// Shown alone, filling the tab.
  Pane? maximized;

  bool broadcast = false;
  final Set<Pane> _left = {};

  /// Every pane, left to right and top to bottom.
  List<Pane> get leaves => [..._leaves(root)];

  Iterable<Pane> _leaves(PaneNode n) sync* {
    switch (n) {
      case Pane():
        yield n;
      case PaneSplit(:final first, :final second):
        yield* _leaves(first);
        yield* _leaves(second);
    }
  }

  Iterable<TerminalController> get controllers =>
      leaves.map((p) => p.controller).nonNulls;

  bool get isSplit => root is PaneSplit;

  /// A new pane next to the active one (right of it, or below), which
  /// becomes active and asks what to open.
  Pane split(Axis axis) {
    final fresh = Pane(null, active.controller);
    _replace(active, PaneSplit(axis, active, fresh));
    active = fresh;
    maximized = null;
    notifyListeners();
    return fresh;
  }

  void _replace(PaneNode old, PaneNode next) {
    if (identical(root, old)) {
      root = next;
      return;
    }
    final parent = _parent(old)!;
    if (identical(parent.first, old)) {
      parent.first = next;
    } else {
      parent.second = next;
    }
  }

  PaneSplit? _parent(PaneNode child, [PaneNode? from]) {
    final n = from ?? root;
    if (n is! PaneSplit) return null;
    if (identical(n.first, child) || identical(n.second, child)) return n;
    return _parent(child, n.first) ?? _parent(child, n.second);
  }

  /// Takes a pane out; its neighbour fills the space. False if it is the
  /// only one (the tab closes instead).
  bool remove(Pane pane) {
    final parent = _parent(pane);
    if (parent == null) return false;
    final sibling = identical(parent.first, pane)
        ? parent.second
        : parent.first;
    _replace(parent, sibling);
    _left.remove(pane);
    if (identical(active, pane)) active = _leaves(sibling).first;
    if (identical(maximized, pane)) maximized = null;
    if (leaves.length < 2) broadcast = false;
    notifyListeners();
    return true;
  }

  /// Puts `node` (a pane, or another tab's panes) in the `side` half of
  /// `at`; `focus` (or the first of them) gets the keyboard. While
  /// broadcasting, what comes in does not receive until it is let in.
  void insertBeside(Pane at, PaneNode node, DropSide side, {Pane? focus}) {
    final split = side.before
        ? PaneSplit(side.axis, node, at)
        : PaneSplit(side.axis, at, node);
    _replace(at, split);
    if (broadcast) _left.addAll(_leaves(node));
    active = focus ?? _leaves(node).first;
    maximized = null;
    notifyListeners();
  }

  void focus(Pane pane) {
    if (identical(active, pane)) return;
    active = pane;
    notifyListeners();
  }

  void fill(Pane pane, TerminalController controller) {
    pane.controller = controller;
    notifyListeners();
  }

  void toggleMaximize() {
    maximized = maximized == null && isSplit ? active : null;
    notifyListeners();
  }

  void resize(PaneSplit split, double ratio) {
    split.ratio = ratio.clamp(0.15, 0.85);
    notifyListeners();
  }

  /// Turns broadcast on (every pane receives) or off. Needs two panes.
  void setBroadcast(bool on) {
    broadcast = on && leaves.length > 1;
    _left.clear();
    notifyListeners();
  }

  bool receives(Pane pane) =>
      broadcast && pane.controller != null && !_left.contains(pane);

  void setReceives(Pane pane, bool on) {
    on ? _left.remove(pane) : _left.add(pane);
    notifyListeners();
  }

  int get receiving => leaves.where(receives).length;

  /// Where typing in `pane` also goes: the other receiving panes, while
  /// broadcasting and if `pane` receives too.
  List<TerminalController> mirrorsOf(TerminalController from) {
    final pane = leaves.where((p) => p.controller == from).firstOrNull;
    if (pane == null || !receives(pane)) return const [];
    return [
      for (final p in leaves)
        if (!identical(p, pane) && receives(p)) p.controller!,
    ];
  }

  /// Where each pane sits in the unit square.
  Map<Pane, Rect> layout() {
    final out = <Pane, Rect>{};
    void walk(PaneNode n, Rect r) {
      switch (n) {
        case Pane():
          out[n] = r;
        case PaneSplit(:final axis, :final first, :final second, :final ratio):
          if (axis == Axis.horizontal) {
            final x = r.left + r.width * ratio;
            walk(first, Rect.fromLTRB(r.left, r.top, x, r.bottom));
            walk(second, Rect.fromLTRB(x, r.top, r.right, r.bottom));
          } else {
            final y = r.top + r.height * ratio;
            walk(first, Rect.fromLTRB(r.left, r.top, r.right, y));
            walk(second, Rect.fromLTRB(r.left, y, r.right, r.bottom));
          }
      }
    }

    walk(root, const Rect.fromLTWH(0, 0, 1, 1));
    return out;
  }

  /// The pane next to the active one in `direction`: the nearest that
  /// touches its side, preferring the one most in line with it.
  Pane? neighbor(AxisDirection direction) {
    final rects = layout();
    final from = rects[active]!;
    const eps = 1e-6;
    Pane? best;
    var bestScore = double.infinity;
    for (final MapEntry(key: pane, value: r) in rects.entries) {
      if (identical(pane, active)) continue;
      final (double gap, double overlap) = switch (direction) {
        AxisDirection.right => (
          r.left - from.right,
          _overlap(r.top, r.bottom, from.top, from.bottom),
        ),
        AxisDirection.left => (
          from.left - r.right,
          _overlap(r.top, r.bottom, from.top, from.bottom),
        ),
        AxisDirection.down => (
          r.top - from.bottom,
          _overlap(r.left, r.right, from.left, from.right),
        ),
        AxisDirection.up => (
          from.top - r.bottom,
          _overlap(r.left, r.right, from.left, from.right),
        ),
      };
      if (gap < -eps || overlap <= eps) continue;
      final score = gap * 10 - overlap;
      if (score < bestScore) {
        bestScore = score;
        best = pane;
      }
    }
    return best;
  }

  static double _overlap(double a0, double a1, double b0, double b1) =>
      (a1 < b1 ? a1 : b1) - (a0 > b0 ? a0 : b0);
}
