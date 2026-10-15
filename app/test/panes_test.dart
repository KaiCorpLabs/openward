import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/tabs/panes.dart';

void main() {
  test('splits, moves between panes and closes back to one', () {
    final panes = Panes(null);
    final a = panes.active;
    // a | b, then b over c.
    final b = panes.split(Axis.horizontal);
    expect(panes.active, same(b));
    final c = panes.split(Axis.vertical);
    expect(panes.leaves, [a, b, c]);

    final rects = panes.layout();
    expect(rects[a], const Rect.fromLTWH(0, 0, 0.5, 1));
    expect(rects[c], const Rect.fromLTWH(0.5, 0.5, 0.5, 0.5));

    expect(panes.neighbor(AxisDirection.up), same(b));
    expect(panes.neighbor(AxisDirection.left), same(a));
    expect(panes.neighbor(AxisDirection.right), isNull);
    panes.focus(a);
    // Both b and c touch a's right side: the higher one wins on a tie.
    expect(panes.neighbor(AxisDirection.right), same(b));

    // Closing b lets c take the whole right half.
    expect(panes.remove(b), isTrue);
    expect(panes.leaves, [a, c]);
    expect(panes.layout()[c], const Rect.fromLTWH(0.5, 0, 0.5, 1));
    expect(panes.remove(c), isTrue);
    expect(panes.isSplit, isFalse);
    expect(panes.remove(a), isFalse, reason: 'the last pane closes the tab');
  });

  test('closing the active pane gives the keyboard to its neighbour', () {
    final panes = Panes(null);
    final a = panes.active;
    final b = panes.split(Axis.horizontal);
    expect(panes.remove(b), isTrue);
    expect(panes.active, same(a));
  });

  test('a pane maximized fills the tab until restored or closed', () {
    final panes = Panes(null);
    panes.toggleMaximize();
    expect(panes.maximized, isNull, reason: 'one pane is already all');
    final b = panes.split(Axis.horizontal);
    panes.toggleMaximize();
    expect(panes.maximized, same(b));
    panes.remove(b);
    expect(panes.maximized, isNull);
  });

  test('resizing keeps both parts visible', () {
    final panes = Panes(null);
    panes.split(Axis.horizontal);
    final split = panes.root as PaneSplit;
    panes.resize(split, 0.99);
    expect(split.ratio, 0.85);
    panes.resize(split, 0);
    expect(split.ratio, 0.15);
  });

  test('broadcast needs two panes and is off again with one', () {
    final panes = Panes(null);
    panes.setBroadcast(true);
    expect(panes.broadcast, isFalse);
    final b = panes.split(Axis.horizontal);
    panes.setBroadcast(true);
    expect(panes.broadcast, isTrue);
    panes.remove(b);
    expect(panes.broadcast, isFalse);
  });
}
