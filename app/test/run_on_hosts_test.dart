import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/snippets/run_on_hosts.dart';
import 'package:openward/tabs/panes.dart';

/// The grid's rows, each with its panes' count, and the share of each.
List<int> rowsOf(PaneNode n) => switch (n) {
  Pane() => [1],
  PaneSplit(axis: Axis.vertical, :final first, :final second) => [
    ...rowsOf(first),
    ...rowsOf(second),
  ],
  PaneSplit(axis: Axis.horizontal) => [_leaves(n)],
};

int _leaves(PaneNode n) => switch (n) {
  Pane() => 1,
  PaneSplit(:final first, :final second) => _leaves(first) + _leaves(second),
};

void main() {
  test('hosts go in rows as even as they can, the same size each', () {
    List<Pane> panes(int n) => [for (var i = 0; i < n; i++) Pane()];
    expect(rowsOf(gridOf(panes(1))), [1]);
    expect(rowsOf(gridOf(panes(2))), [2]);
    expect(rowsOf(gridOf(panes(4))), [2, 2]);
    expect(rowsOf(gridOf(panes(5))), [3, 2]);
    expect(rowsOf(gridOf(panes(9))), [3, 3, 3]);
    expect(rowsOf(gridOf(panes(16))), [4, 4, 4, 4]);
    // Nine: three rows of a third each, three panes of a third each.
    final nine = gridOf(panes(9)) as PaneSplit;
    expect(nine.axis, Axis.vertical);
    expect(nine.ratio, closeTo(1 / 3, 1e-9));
    final top = nine.first as PaneSplit;
    expect(top.axis, Axis.horizontal);
    expect(top.ratio, closeTo(1 / 3, 1e-9));
    expect((top.second as PaneSplit).ratio, closeTo(1 / 2, 1e-9));
  });
}
