import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/address.dart';
import 'package:openward/tabs/tabs.dart';

import 'fakes.dart';

void main() {
  late FakeOpenWard app;
  late TabsNotifier tabs;
  late TabsState Function() state;

  setUp(() {
    app = FakeOpenWard();
    final container = fakeContainer(app);
    tabs = container.read(tabsProvider.notifier);
    state = () => container.read(tabsProvider);
  });

  List<String> kinds() => [
    for (final t in state().tabs)
      switch (t) {
        PageTab(:final page) => page.name,
        SessionTab(:final controller) => controller?.label ?? '?',
        SftpTab(:final controller) => 'sftp ${controller.label}',
      },
  ];

  testWidgets('a page opens once; selecting and going round wraps', (
    tester,
  ) async {
    tabs.openPage(PageKind.settings);
    tabs.openPage(PageKind.keys);
    tabs.openPage(PageKind.settings);
    expect(kinds(), ['settings', 'keys']);
    expect(state().active, 0, reason: 'the open one comes to front');
    tabs.cycle(-1);
    expect(state().active, 1);
    tabs.cycle(1);
    expect(state().active, 0);
    tabs.select(7);
    expect(state().active, 0, reason: 'no such tab');
  });

  testWidgets('sessions start their connection; renamed, and back to '
      'their name', (tester) async {
    tabs.openLocal();
    tabs.openAddress(QuickTarget.parse('deploy@db.example.com:2222')!);
    expect(app.calls, ['local', 'connect db.example.com']);
    expect(state().active, 1);
    final c = state().current! as SessionTab;
    tabs.rename(1, '  base de datos ');
    expect(c.controller!.customTitle, 'base de datos');
    expect(c.controller!.displayTitle, 'base de datos');
    tabs.rename(1, '   ');
    expect(c.controller!.customTitle, isNull);
  });

  testWidgets('Telnet and serial ports open as what they are', (tester) async {
    tabs.openAddress(QuickTarget.parse('telnet://sw-1')!);
    tabs.openAddress(QuickTarget.parse('serial://COM3:115200')!);
    expect(app.calls, ['connect telnet sw-1', 'serial COM3 115200 8']);
    final serial = state().current! as SessionTab;
    expect(serial.controller!.displayTitle, 'COM3', reason: 'by its name');
    expect(serial.controller!.overSsh, isFalse);
  });

  testWidgets('moved tabs keep the one in front; closed ones open again '
      'where they were going', (tester) async {
    tabs
      ..openPage(PageKind.settings)
      ..openLocal()
      ..openPage(PageKind.keys);
    final front = state().current;
    tabs.move(2, 0);
    expect(kinds().first, 'keys');
    expect(state().current, same(front));

    tabs.close(0);
    expect(kinds(), ['settings', isNot('keys')]);
    expect(tabs.canReopen, isTrue);
    tabs.reopen();
    expect(kinds().last, 'keys');

    // A session comes back as a new connection to the same place.
    final local = state().tabs.indexWhere((t) => t is SessionTab);
    tabs.close(local);
    await tester.pump();
    final before = app.sessions.length;
    tabs.reopen();
    expect(app.sessions.length, before + 1);
    expect(app.calls.last, 'local');
  });

  testWidgets('a split tab closes a pane at a time', (tester) async {
    tabs.openLocal();
    final tab = state().current! as SessionTab;
    tabs.split(Axis.horizontal);
    expect(tab.panes.isSplit, isTrue);
    // The new pane asks what to open: filled with a local shell.
    tabs.fillPane(tab, tab.panes.active);
    expect(app.calls, ['local', 'local']);
    tabs.closeCurrent();
    expect(state().tabs, hasLength(1));
    expect(tab.panes.isSplit, isFalse);
    tabs.closeCurrent();
    expect(state().tabs, isEmpty);
    await tester.pump();
  });
}
