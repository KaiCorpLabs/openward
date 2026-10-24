import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/address.dart';
import 'package:openward/src/rust/api/workspaces.dart';
import 'package:openward/tabs/tabs.dart';
import 'package:openward/workspaces/workspaces.dart';

import 'fakes.dart';

void main() {
  testWidgets('the open tabs, laid out as they are, and opened again', (
    tester,
  ) async {
    final app = FakeOpenWard();
    final container = fakeContainer(app);
    final tabs = container.read(tabsProvider.notifier);
    TabsState state() => container.read(tabsProvider);

    tabs
      ..openPage(PageKind.settings)
      ..openLocal()
      ..split(Axis.vertical);
    final split = state().current! as SessionTab;
    tabs.fillPane(
      split,
      split.panes.active,
      target: QuickTarget.parse('deploy@db.example.com:2222'),
    );
    tabs.rename(1, 'db');
    tabs.openPage(PageKind.keys);

    final spec = captureWorkspace(state(), '  Producción ');
    expect(spec.name, 'Producción');
    expect(spec.tabs, hasLength(1), reason: 'pages are left out');
    final panes = spec.tabs.single.panes;
    expect(panes.map((p) => p.split?.vertical), [true, null, null]);
    expect(panes[1].target, const WorkspaceTarget());
    expect(
      panes[2].target,
      const WorkspaceTarget(
        address: 'db.example.com',
        user: 'deploy',
        port: 2222,
      ),
    );
    expect(panes.map((p) => p.active), [false, false, true]);
    expect(spec.tabs.single.title, 'db');
    expect(tabTargets(spec.tabs.single), [panes[1].target, panes[2].target]);

    // Opened again after what is open: new connections, the same layout.
    final calls = app.calls.length;
    late WidgetRef ref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    openWorkspace(
      ref,
      WorkspaceView(id: 'w', rev: BigInt.one, spec: spec, sessions: 2),
    );
    expect(app.calls.sublist(calls), ['local', 'connect db.example.com']);
    final opened = state().current! as SessionTab;
    expect(opened, isNot(same(split)));
    expect(opened.panes.isSplit, isTrue);
    expect(opened.panes.active.controller?.customTitle, 'db');
  });

  testWidgets('the tab in front, or the last kept one before it', (
    tester,
  ) async {
    final container = fakeContainer(FakeOpenWard());
    final tabs = container.read(tabsProvider.notifier);
    TabsState state() => container.read(tabsProvider);

    tabs
      ..openPage(PageKind.settings)
      ..openLocal()
      ..openPage(PageKind.keys)
      ..openLocal();
    expect(capturedActive(state()), 1, reason: 'the second session');
    tabs.select(1);
    expect(capturedActive(state()), 0);
    // A page in front: the session before it, not the one after.
    tabs.select(2);
    expect(capturedActive(state()), 0);
    tabs.select(0);
    expect(capturedActive(state()), 0);
  });
}
