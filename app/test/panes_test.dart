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

  test('a pane swaps with its neighbour, each keeping its place', () {
    final panes = Panes(null);
    final a = panes.active;
    // a | (b over c)
    final b = panes.split(Axis.horizontal);
    final c = panes.split(Axis.vertical);
    // a's neighbour is the nearest pane of the other half; c's, b.
    expect(panes.swapPartner(a), same(b));
    expect(panes.swapPartner(c), same(b));
    expect(panes.swapPartner(b), same(c));
    panes.swap(a, b);
    expect(panes.leaves, [b, a, c]);
    panes.swap(a, c);
    expect(panes.leaves, [b, c, a]);
    expect(Panes(null).swapPartner(Panes(null).active), isNull);
  });

  test('equal sizes share the room by the panes on each side', () {
    final panes = Panes(null);
    final a = panes.active;
    // a | b | c in a row, the last two split from b.
    panes.split(Axis.horizontal);
    panes.split(Axis.horizontal);
    final root = panes.root as PaneSplit;
    final inner = root.second as PaneSplit;
    panes.resize(root, 0.8);
    panes.equalize();
    expect(root.ratio, closeTo(1 / 3, 1e-9));
    expect(inner.ratio, 0.5);
    final rects = panes.layout();
    expect(rects[a]!.width, closeTo(1 / 3, 1e-9));
    // One split alone, from its divider.
    panes.resize(inner, 0.2);
    panes.equalizeSplit(inner);
    expect(inner.ratio, 0.5);
  });

  test('a pane that asks takes the panes of another tab', () {
    final panes = Panes(null);
    final a = panes.active;
    final fresh = panes.split(Axis.horizontal);
    final other = Panes(null);
    final x = other.active;
    final y = other.split(Axis.vertical);
    panes.replace(fresh, other.root, focus: y);
    expect(panes.leaves, [a, x, y]);
    expect(panes.active, same(y));
  });

  test('panes alike are numbered in their tab', () {
    final panes = Panes(null);
    final a = panes.active;
    final b = panes.split(Axis.horizontal);
    final c = panes.split(Axis.vertical);
    final titles = {a: 'Local', b: 'web-1', c: 'Local'};
    expect(paneNames(panes, (p) => titles[p]!).values, [
      'Local 1',
      'web-1',
      'Local 2',
    ]);
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

  test('dragging a divider tells only the layout', () {
    final panes = Panes(null)..split(Axis.horizontal);
    var everyone = 0, layout = 0;
    panes.addListener(() => everyone++);
    panes.sizes.addListener(() => layout++);
    panes.resize(panes.root as PaneSplit, 0.7);
    panes.resize(panes.root as PaneSplit, 0.99);
    expect((everyone, layout), (0, 2));
    expect((panes.root as PaneSplit).ratio, 0.85, reason: 'kept in bounds');
  });
}
