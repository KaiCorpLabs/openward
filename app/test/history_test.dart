import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/address.dart';
import 'package:openward/core/connection.dart';
import 'package:openward/core/match.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/history/history.dart';
import 'package:openward/history/line_tracker.dart';
import 'package:openward/history/suggest.dart';
import 'package:openward/terminal/keys.dart';
import 'package:openward/src/rust/api/session.dart';

/// A screen of one prompt row: the prompt, what the shell echoed, and
/// what shows after the cursor.
class _Screen implements LineScreen {
  _Screen(this.prompt);

  String prompt;
  String echoed = '';
  String after = '';
  int row = 3;

  /// Rows the screen scrolled since the prompt was drawn.
  int scrolled = 0;

  @override
  int? get cursorRow => row;

  @override
  ({String text, String after})? typedFrom(int r) {
    if (r > row) return null;
    if (r == row - scrolled) {
      return (text: '$prompt$echoed'.trimRight(), after: after);
    }
    return (text: 'something else', after: '');
  }
}

/// Types `text` key by key, echoing each one.
void _type(LineTracker t, _Screen s, String text, {bool echo = true}) {
  for (final ch in text.split('')) {
    t.text(ch, s);
    if (echo) s.echoed += ch;
  }
}

void main() {
  group('LineTracker', () {
    test('plain input is own; reconstructed output is screen provenance', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, 'echo own');
      expect(t.enterCommand(s, altScreen: false), (
        text: 'echo own',
        origin: CommandOrigin.own,
      ));
      s.echoed = '';
      _type(t, s, 'e');
      t.key(Hid.tab, 0, '', s);
      s.echoed = 'server supplied command';
      expect(t.enterCommand(s, altScreen: false), (
        text: 'server supplied command',
        origin: CommandOrigin.screen,
      ));
    });

    test(
      'replayed input or a changed shell cannot become a new own command',
      () {
        final s = _Screen('\$ ');
        final t = LineTracker();
        t.untrackedInput();
        _type(t, s, 'legacy command');
        expect(t.enterCommand(s, altScreen: false), isNull);
        s.echoed = '';
        _type(t, s, ' private');
        t.shellChanged();
        _type(t, s, 'suffix');
        expect(t.enterCommand(s, altScreen: false), isNull);
        s.echoed = '';
        t.shellChanged();
        _type(t, s, 'echo own');
        expect(t.enterCommand(s, altScreen: false)?.origin, CommandOrigin.own);
      },
    );
    test('keeps a command typed as is', () {
      final s = _Screen('ana@web:~\$ ');
      final t = LineTracker();
      _type(t, s, 'ls -la');
      expect(t.enter(s, altScreen: false), 'ls -la');
    });

    test('backspace takes back the last character', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, 'gti');
      t.key(Hid.backspace, 0, '', s);
      t.key(Hid.backspace, 0, '', s);
      s.echoed = 'g';
      _type(t, s, 'it status');
      expect(t.enter(s, altScreen: false), 'git status');
    });

    test('what the screen did not echo is never kept', () {
      final s = _Screen('[sudo] password for ana: ');
      final t = LineTracker();
      _type(t, s, 'hunter2', echo: false);
      expect(t.enter(s, altScreen: false), isNull);

      // Even where the prompt does not say so.
      final quiet = _Screen('> ');
      _type(t, quiet, 'hunter2', echo: false);
      expect(t.enter(quiet, altScreen: false), isNull);
    });

    test('a prompt asking for a secret is never kept, even echoed', () {
      final s = _Screen('Enter token: ');
      final t = LineTracker();
      _type(t, s, 'abc123');
      expect(t.enter(s, altScreen: false), isNull);
      // A folder with such a word in the shell's prompt is fine.
      final folder = _Screen('ana@web:~/secret-santa\$ ');
      _type(t, folder, 'make');
      expect(t.enter(folder, altScreen: false), 'make');
    });

    test('the last keys need not be echoed yet', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, 'uptime');
      s.echoed = 'upti';
      expect(t.enter(s, altScreen: false), 'uptime');
    });

    test('a leading space, an editor or a cancelled line keep nothing', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, ' export TOKEN=x');
      expect(t.enter(s, altScreen: false), isNull);

      s.echoed = '';
      _type(t, s, ':wq');
      expect(t.enter(s, altScreen: true), isNull);

      s.echoed = '';
      _type(t, s, 'rm -rf build');
      t.key(Hid.a + 2, Mods.ctrl, '', s); // Ctrl+C
      expect(t.enter(s, altScreen: false), isNull);
    });

    test('after Tab or the arrows, the screen says what ran', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, 'cd /va');
      t.key(Hid.tab, 0, '', s);
      s.echoed = 'cd /var/';
      expect(t.enter(s, altScreen: false), 'cd /var/');

      // Recalled from the shell's history.
      s.echoed = '';
      t.key(Hid.arrowUp, 0, '', s);
      s.echoed = 'make test';
      expect(t.enter(s, altScreen: false), 'make test');
    });

    test('leading-space exclusion survives editing and reconstruction', () {
      for (final hid in [Hid.tab, Hid.arrowLeft, Hid.arrowUp]) {
        final s = _Screen('\$ ');
        final t = LineTracker();
        _type(t, s, ' export TOKEN=private');
        t.key(hid, 0, '', s);
        expect(t.enter(s, altScreen: false), isNull);
        s.echoed = '';
        _type(t, s, 'echo public');
        expect(t.enter(s, altScreen: false), 'echo public');
      }
    });

    test('a leading space inserted at Home also excludes the edited line', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, 'export TOKEN=private');
      t.key(Hid.home, 0, '', s);
      t.text(' ', s);
      s.echoed = ' export TOKEN=private';
      expect(t.enter(s, altScreen: false), isNull);
    });

    test(
      'spaces after cursor-uncertain editing stay private conservatively',
      () {
        for (final key in [Hid.arrowUp, Hid.a, Hid.a + 20]) {
          final s = _Screen('\$ ');
          final t = LineTracker();
          _type(t, s, 'export TOKEN=private');
          t.key(key, key == Hid.arrowUp ? 0 : Mods.ctrl, '', s);
          t.text(' ', s);
          s.echoed = ' export TOKEN=private';
          expect(t.enter(s, altScreen: false), isNull);
        }
      },
    );

    test('private-line intent stays until Enter or cancellation', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, ' ');
      t.key(Hid.backspace, 0, '', s);
      s.echoed = '';
      _type(t, s, 'export TOKEN=private');
      t.key(Hid.tab, 0, '', s);
      expect(t.enter(s, altScreen: false), isNull);
      s.echoed = '';
      _type(t, s, ' private');
      t.key(Hid.a + 2, Mods.ctrl, '', s);
      s.echoed = '';
      _type(t, s, 'echo public');
      expect(t.enter(s, altScreen: false), 'echo public');
    });

    test('Ctrl+D, Ctrl+G and Ctrl+Z retain private-line intent', () {
      for (final key in [Hid.a + 3, Hid.a + 6, Hid.a + 25]) {
        final s = _Screen('\$ ');
        final t = LineTracker();
        _type(t, s, ' echo PRIVATE');
        t.key(key, Mods.ctrl, '', s);
        _type(t, s, 'SUFFIX');
        t.key(Hid.tab, 0, '', s);
        expect(t.enter(s, altScreen: false), isNull);
      }
    });

    test('text after the cursor makes an edited line unclear', () {
      final s = _Screen('\$ ')..after = '[12:00]';
      final t = LineTracker();
      t.key(Hid.arrowUp, 0, '', s);
      s.echoed = 'git push';
      // The prompt on the right was there before: still clear.
      expect(t.enter(s, altScreen: false), 'git push');

      s.echoed = '';
      t.key(Hid.arrowUp, 0, '', s);
      s.echoed = 'git pu';
      s.after = 'sh origin main';
      expect(t.enter(s, altScreen: false), isNull);
    });

    test('a screen that scrolled: the prompt a row up', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      _type(t, s, 'echo long');
      s.scrolled = 1;
      s.row = 4;
      t.key(Hid.arrowLeft, 0, '', s);
      expect(t.enter(s, altScreen: false), 'echo long');
    });

    test('a pasted newline or a history search keep nothing', () {
      final s = _Screen('\$ ');
      final t = LineTracker();
      t.text('one\ntwo', s);
      expect(t.enter(s, altScreen: false), isNull);
      t.key(Hid.a + 17, Mods.ctrl, '', s); // Ctrl+R
      s.echoed = 'ssh prod';
      expect(t.enter(s, altScreen: false), isNull);
    });

    test('a suggestion goes only where the screen shows what was typed', () {
      final s = _Screen('ana@web:~\$ ');
      final t = LineTracker();
      expect(t.plainTyped, isNull);
      _type(t, s, 'git st');
      expect(t.plainTyped, 'git st');
      expect(t.showsTyped(s), isTrue);
      // The shell suggests on its own: not ours as well.
      s.after = 'atus';
      expect(t.showsTyped(s), isFalse);
      s.after = '';
      // The echo is not there yet.
      t.text('a', s);
      expect(t.showsTyped(s), isFalse);
      s.echoed += 'a';
      expect(t.showsTyped(s), isTrue);
      // After an arrow, the line is the screen's to say.
      t.key(Hid.arrowLeft, 0, '', s);
      expect(t.plainTyped, isNull);
      t.enter(s, altScreen: false);

      final secret = _Screen('[sudo] password for ana: ');
      _type(t, secret, 'ls', echo: true);
      expect(t.plainTyped, isNull);
    });
  });

  group('suggestions', () {
    test('the first source that has one; the rest of it', () {
      final history = ['git status -sb', 'git stash'];
      final sources = [
        SuggestionSource(history),
        const SuggestionSource(['git switch main']),
        const SuggestionSource(commonCommands, minTyped: 2),
      ];
      expect(suggestFor('git st', sources), 'atus -sb');
      expect(suggestFor('git sw', sources), 'itch main');
      expect(suggestFor('d', sources), isNull, reason: 'too short for these');
      expect(suggestFor('df', sources), ' -h');
      // Nothing for what is complete, after a space in front, or empty.
      expect(suggestFor('git stash', sources), isNull);
      expect(suggestFor(' git', sources), isNull);
      expect(suggestFor('', sources), isNull);
      // Snippets of several lines are not suggested.
      expect(
        suggestFor('dep', [
          const SuggestionSource(['deploy\nrestart']),
        ]),
        isNull,
      );
      for (final hidden in ['\u001b', '\t', '\u202e', '\u200b']) {
        expect(
          suggestFor('git st', [
            SuggestionSource(['git status$hidden']),
          ]),
          isNull,
        );
      }
    });
  });

  group('history', () {
    test('old, absent and malformed provenance stay unknown', () {
      for (final provenance in [null, 'unexpected', 1]) {
        final old = HistoryEntry.fromJson({
          'command': 'echo old',
          'where': 'local',
          'at': 1,
          'origin': ?provenance,
        })!;
        expect(old.origin, CommandOrigin.unknown);
        expect(old.binding, isNull);
        expect(historyIsOwnHere(old, 'local', 'local'), isFalse);
      }
      const screen = HistoryEntry(
        command: 'echo screen',
        where: 'local',
        label: 'Local',
        at: 1,
        origin: CommandOrigin.screen,
        binding: 'local',
      );
      expect(
        HistoryEntry.fromJson(screen.toJson())!.origin,
        CommandOrigin.screen,
      );
    });
    late Directory dir;
    late ProviderContainer container;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ow-history');
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

    test('newest first, once per place, and kept in its file', () {
      final h = container.read(historyProvider.notifier);
      final local = _Place(label: 'Local');
      final web = _Place(label: 'web-1', hostId: 'h1');
      h.add('ls', local, now: DateTime(2026, 1, 1));
      h.add('uptime', web, now: DateTime(2026, 1, 2));
      h.add('ls', local, now: DateTime(2026, 1, 3));
      h.add('ls', web, now: DateTime(2026, 1, 4));
      final list = container.read(historyProvider);
      expect(
        [for (final e in list) '${e.command}@${e.where}'],
        ['ls@host:h1', 'ls@local', 'uptime@host:h1'],
      );
      expect(list[1].count, 2);

      // Read back by a new container, once written: a moment after the
      // last command, or now.
      expect(File('${dir.path}/history.json').existsSync(), isFalse);
      h.flush();
      final again = ProviderContainer(
        overrides: [
          settingsFileProvider.overrideWithValue(
            File('${dir.path}/settings.json'),
          ),
        ],
      );
      addTearDown(again.dispose);
      expect(again.read(historyProvider).map((e) => e.command), [
        'ls',
        'ls',
        'uptime',
      ]);

      h.clear();
      expect(File('${dir.path}/history.json').existsSync(), isFalse);
    });
  });

  test('palette matches the start, a word, anywhere, then in order', () {
    expect(matchScore('Dividir a la derecha', 'div'), 0);
    expect(matchScore('Dividir a la derecha', 'der'), 1);
    expect(matchScore('git status', 'tat'), 2);
    expect(matchScore('Nueva clave…', 'nc'), 3);
    expect(matchScore('Ajustes', 'xyz'), isNull);
  });
}

/// A session's place in the history, without a session.
class _Place extends Fake implements ConnectionController {
  _Place({required this.label, this.hostId});

  @override
  final String label;
  @override
  final String? hostId;
  @override
  QuickTarget? get target => null;
  @override
  ConnectedView? get connected => null;
}
