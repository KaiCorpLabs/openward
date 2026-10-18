import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/home/recent.dart';
import 'package:openward/home/start_page.dart';
import 'package:openward/palette/command_palette.dart';
import 'package:openward/tabs/latency.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/window/shortcuts.dart';
import 'package:openward/window/sidebar_state.dart';

void main() {
  group('the sidebar shown', () {
    SidebarMode shown(
      SidebarMode mode,
      SidebarOnSession onSession, {
      bool session = true,
      bool openedHere = false,
    }) => shownSidebar(
      mode: mode,
      onSession: onSession,
      session: session,
      openedHere: openedHere,
    );

    test('is the setting with no session in front', () {
      for (final m in SidebarMode.values) {
        expect(shown(m, SidebarOnSession.hide, session: false), m);
      }
    });

    test('folds further with a session in front, never less', () {
      expect(shown(SidebarMode.open, SidebarOnSession.rail), SidebarMode.rail);
      expect(
        shown(SidebarMode.open, SidebarOnSession.hide),
        SidebarMode.hidden,
      );
      expect(
        shown(SidebarMode.hidden, SidebarOnSession.rail),
        SidebarMode.hidden,
      );
      expect(shown(SidebarMode.rail, SidebarOnSession.keep), SidebarMode.rail);
    });

    test('stays as set once ⌘B opened it over a session', () {
      expect(
        shown(SidebarMode.open, SidebarOnSession.hide, openedHere: true),
        SidebarMode.open,
      );
    });
  });

  group('⌘B, the width and the setting', () {
    late Directory dir;
    late ProviderContainer container;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ow-focus');
      container = ProviderContainer(
        overrides: [
          settingsFileProvider.overrideWithValue(
            File('${dir.path}/settings.json'),
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      dir.deleteSync(recursive: true);
    });

    SidebarMode mode() => container.read(sidebarModeProvider);
    SidebarNotifier sidebar() => container.read(sidebarProvider.notifier);

    test('folds to a rail and opens again, and it is saved', () {
      expect(mode(), SidebarMode.open);
      sidebar().toggle();
      expect(mode(), SidebarMode.rail);
      expect(container.read(settingsProvider).sidebar, SidebarMode.rail);
      sidebar().toggle();
      expect(mode(), SidebarMode.open);
    });

    test('folds to what was last chosen', () {
      sidebar().chose(SidebarMode.hidden);
      expect(mode(), SidebarMode.hidden);
      sidebar().toggle();
      expect(mode(), SidebarMode.open);
      sidebar().toggle();
      expect(mode(), SidebarMode.hidden);
    });

    test('the dragged width stays within its bounds and is saved', () {
      sidebar().drag(900);
      expect(container.read(sidebarWidthProvider), Settings.maxSidebarWidth);
      sidebar().drag(100);
      expect(container.read(sidebarWidthProvider), Settings.minSidebarWidth);
      sidebar().drag(301.4);
      sidebar().endDrag();
      expect(container.read(settingsProvider).sidebarWidth, 301);
      sidebar().resetWidth();
      expect(
        container.read(settingsProvider).sidebarWidth,
        Settings.defaultSidebarWidth,
      );
    });
  });

  group('recent connections', () {
    late Directory dir;
    late ProviderContainer container;

    ProviderContainer open() => ProviderContainer(
      overrides: [
        settingsFileProvider.overrideWithValue(
          File('${dir.path}/settings.json'),
        ),
      ],
    );

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ow-recent');
      container = open();
    });

    tearDown(() {
      container.dispose();
      dir.deleteSync(recursive: true);
    });

    RecentNotifier recent() => container.read(recentProvider.notifier);

    test('newest first, once per place, with when it ended', () {
      final t0 = DateTime(2026, 10, 18, 10);
      recent().add('host:a', 'web-1', now: t0);
      recent().add('address:ops@10.0.0.5', 'ops@10.0.0.5', now: t0);
      recent().add('host:a', 'web-1', now: t0.add(const Duration(hours: 1)));
      final list = container.read(recentProvider).connections;
      expect(
        [for (final e in list) e.where],
        ['host:a', 'address:ops@10.0.0.5'],
      );
      expect(list.first.hostId, 'a');
      expect(list.last.address, 'ops@10.0.0.5');
      recent().end('host:a', now: t0.add(const Duration(hours: 2)));
      expect(
        container.read(recentProvider).connections.first.ended,
        t0.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
    });

    test('remember how long they lasted and whether tmux kept them', () {
      final t0 = DateTime(2026, 10, 18, 10);
      recent().add('host:a', 'web-1', now: t0);
      expect(container.read(recentProvider).connections.single.length, null);
      recent().end(
        'host:a',
        now: t0.add(const Duration(minutes: 38)),
        tmux: true,
      );
      final again = open();
      addTearDown(again.dispose);
      final r = again.read(recentProvider).connections.single;
      expect(r.length, const Duration(minutes: 38));
      expect(r.tmux, isTrue);
    });

    test('survive a restart, and the actions are counted', () {
      recent().add('host:a', 'web-1');
      recent().used('splitRight');
      recent().used('splitRight');
      final again = open();
      addTearDown(again.dispose);
      final r = again.read(recentProvider);
      expect(r.connections.single.label, 'web-1');
      expect(r.actions['splitRight'], 2);
    });

    test('are not kept when turned off, and clearing forgets them', () {
      recent().add('host:a', 'web-1');
      recent().clear();
      expect(container.read(recentProvider).connections, isEmpty);
      container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(recentConnections: false));
      recent().add('host:b', 'db');
      expect(container.read(recentProvider).connections, isEmpty);
    });
  });

  test('how long ago, in a few words', () {
    final l = AppLocalizationsEs();
    expect(agoText(l, const Duration(seconds: 20)), 'ahora');
    expect(agoText(l, const Duration(minutes: 5)), 'hace 5 min');
    expect(agoText(l, const Duration(hours: 3)), 'hace 3 h');
    expect(agoText(l, const Duration(days: 2)), 'hace 2 d');
  });

  test('how long, in a few words', () {
    final l = AppLocalizationsEs();
    expect(durationText(l, const Duration(seconds: 40)), 'menos de 1 min');
    expect(durationText(l, const Duration(minutes: 38)), '38 min');
    expect(
      durationText(l, const Duration(hours: 2, minutes: 14)),
      '2 h 14 min',
    );
  });

  group('the shortcuts sheet', () {
    final l = AppLocalizationsEs();
    List<String> keysOf(List<ShortcutGroup> groups, String title) => [
      for (final g in groups)
        for (final r in g.rows)
          if (r.title == title) ...r.keys,
    ];

    test('has the keys of each system', () {
      final mac = shortcutGroups(l, apple: true);
      final other = shortcutGroups(l, apple: false);
      expect(keysOf(mac, l.toggleSidebar), ['⌘B']);
      expect(keysOf(other, l.toggleSidebar), ['Ctrl+Mayús+L']);
      expect(keysOf(mac, l.shortcutsTitle), ['⌘/']);
      expect(keysOf(other, l.shortcutsTitle), ['Ctrl+Mayús+/']);
      expect(keysOf(other, l.settings), ['Ctrl+,']);
      // No ⌘ outside macOS.
      for (final g in other) {
        for (final r in g.rows) {
          expect(r.keys.join(), isNot(contains('⌘')), reason: r.title);
        }
      }
    });

    test('finds by what it does, without accents, or by the keys', () {
      final all = shortcutGroups(l, apple: true);
      final split = filterShortcuts(all, 'dividir');
      expect([for (final g in split) g.title], [l.shortcutsPanes]);
      expect(split.single.rows.length, 2);
      expect([
        for (final g in filterShortcuts(all, 'pestana'))
          for (final r in g.rows) r.title,
      ], containsAll([l.shortcutNextTab, l.shortcutLastTab]));
      expect(
        [
          for (final g in filterShortcuts(all, '⌘⇧o'))
            for (final r in g.rows) r.title,
        ],
        [l.openSftp],
      );
      expect(filterShortcuts(all, 'zzz'), isEmpty);
      expect(filterShortcuts(all, '  '), all);
    });
  });

  test("the latency chart's lines fall on round values under its top", () {
    expect(latencyTicks(115), [50, 100]);
    expect(latencyTicks(250), [100, 200]);
    expect(latencyTicks(60), [25, 50]);
    expect(latencyTicks(1200), [500, 1000]);
  });
}
