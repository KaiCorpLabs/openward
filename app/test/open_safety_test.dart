import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/sftp/open_safety.dart';
import 'package:openward/sftp/remote_edit.dart';
import 'package:openward/terminal/visible_text.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Takes note of what it is asked to open, and opens nothing.
class _Launcher extends UrlLauncherPlatform {
  final opened = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

/// The Dart of the Flutter running the tests, to hold a lock from
/// another process; null if it cannot be found.
String? _dart() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return null;
  final dart = File(
    '$root/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
  );
  return dart.existsSync() ? dart.path : null;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ow-open-test-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// What each system runs instead of opening: asked about first (AM-2).
  test('the types that run when opened, as each system sees them', () {
    expect(runsWhenOpened('setup.exe', os: 'windows'), 'exe');
    expect(runsWhenOpened('SETUP.EXE', os: 'windows'), 'exe');
    expect(runsWhenOpened('factura.pdf.exe', os: 'windows'), 'exe');
    expect(
      runsWhenOpened('factura.exe. . ', os: 'windows'),
      'exe',
      reason: 'Windows drops the dots and spaces at the end',
    );
    expect(runsWhenOpened('deploy.ps1', os: 'windows'), 'ps1');
    expect(runsWhenOpened('acceso.lnk', os: 'windows'), 'lnk');
    expect(runsWhenOpened('informe.pdf', os: 'windows'), isNull);
    expect(runsWhenOpened('notas.txt', os: 'windows'), isNull);
    expect(runsWhenOpened('.bat', os: 'windows'), isNull, reason: 'no name');
    expect(runsWhenOpened('Makefile', os: 'windows'), isNull);

    expect(runsWhenOpened('instalar.command', os: 'macos'), 'command');
    expect(runsWhenOpened('app.pkg', os: 'macos'), 'pkg');
    expect(runsWhenOpened('x.exe.', os: 'macos'), isNull);
    expect(
      runsWhenOpened('deploy.sh', os: 'macos'),
      isNull,
      reason: 'it opens in an editor, and has no execute bit',
    );

    expect(runsWhenOpened('lanzador.desktop', os: 'linux'), 'desktop');
    expect(runsWhenOpened('herramienta.jar', os: 'linux'), 'jar');
    expect(runsWhenOpened('foto.png', os: 'linux'), isNull);
  });

  /// The disguise of AM-2: the name as the list shows it.
  test('a name shows what it hides, a line break too', () {
    const sneaky = 'factura\u202Efdp.exe';
    expect(visibleName(sneaky), 'factura⟨RLO⟩fdp.exe');
    expect(visibleName('informe.pdf\n.exe'), 'informe.pdf␊.exe');
    expect(visibleName('a\u2028b'), 'a⟨LS⟩b');
    expect(visibleName('normal.txt'), 'normal.txt');
    expect(hasHidden('a\tb'), isFalse, reason: 'a paste keeps its tabs');
    expect(hasHidden('a\tb', lines: false), isTrue);
  });

  /// The copy is marked as from outside, and does not run (AM-2).
  test('the copy loses its execute bits and carries the mark', () async {
    final file = File('${tmp.path}/script.command')
      ..writeAsStringSync('#!/bin/sh\necho hola\n');
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['755', file.path]);
    }
    await markFromOutside(file.path);
    if (Platform.isWindows) {
      final zone = File('${file.path}:Zone.Identifier').readAsStringSync();
      expect(zone, contains('ZoneId=3'));
    } else {
      expect(file.statSync().mode & 0x1ff, 0x1a4, reason: '0644');
    }
    if (Platform.isMacOS) {
      final mark = Process.runSync('/usr/bin/xattr', [
        '-p',
        'com.apple.quarantine',
        file.path,
      ]);
      expect(mark.exitCode, 0);
      expect('${mark.stdout}', matches(RegExp(r'^0081;[0-9a-f]+;OpenWard;')));
    }
    expect(file.readAsStringSync(), contains('echo hola'));
  });

  /// AM-1: the name reaches the system as a file, not as a command line.
  test('on Windows the path goes to ShellExecute as it is', () async {
    final before = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = before);
    const path =
        r'C:\Users\yo\AppData\Local\Temp\openward-open-x\1\a&calc #1.txt';
    await openWithSystem(path, os: 'windows');
    expect(launcher.opened, [path]);
  });

  /// AM-6: what an earlier run left goes, what an open one has stays.
  test('the copies a run left are deleted at the next start', () async {
    Directory folder(String name) {
      final d = Directory('${tmp.path}/$name')..createSync();
      if (!Platform.isWindows) Process.runSync('chmod', ['700', d.path]);
      File('${d.path}/copia.txt').writeAsStringSync('secreto');
      return d;
    }

    final free = folder('${openCopiesPrefix}free');
    File('${free.path}/.openward-lock').createSync();
    final old = folder('${openCopiesPrefix}old');
    final other = folder('otra-cosa');
    final open = folder('${openCopiesPrefix}open');
    final lock = File('${open.path}/.openward-lock')..createSync();
    Link? link;
    Directory? target;
    if (!Platform.isWindows) {
      target = folder('target');
      link = Link('${tmp.path}/${openCopiesPrefix}link')
        ..createSync(target.path);
    }

    // Another OpenWard, open, holds its folder's lock.
    final dart = _dart();
    Process? holder;
    if (dart != null) {
      final script = File('${tmp.path}/hold.dart')
        ..writeAsStringSync('''
import 'dart:io';
void main(List<String> args) {
  File(args.first).openSync(mode: FileMode.append).lockSync();
  stdout.writeln('held');
  stdin.listen((_) {});
}
''');
      holder = await Process.start(dart, [script.path, lock.path]);
      await holder.stdout
          .transform(utf8.decoder)
          .firstWhere((s) => s.contains('held'));
    }

    await cleanStaleOpenCopies(temp: tmp);
    expect(free.existsSync(), isFalse, reason: 'its lock is free');
    expect(old.existsSync(), isTrue, reason: 'no lock, but not a day old');
    expect(other.existsSync(), isTrue, reason: 'not ours');
    if (holder != null) {
      expect(open.existsSync(), isTrue, reason: 'its run is open');
      holder.kill();
      await holder.exitCode;
    }
    if (link != null) {
      expect(target!.existsSync(), isTrue, reason: 'a link is not followed');
      expect(File('${target.path}/copia.txt').existsSync(), isTrue);
    }

    // The next day; and the other run has ended.
    await cleanStaleOpenCopies(
      temp: tmp,
      now: DateTime.now().add(const Duration(days: 2)),
    );
    expect(old.existsSync(), isFalse, reason: 'a version before the lock');
    expect(open.existsSync(), isFalse, reason: 'its run ended');
    expect(other.existsSync(), isTrue);
    if (dart == null) markTestSkipped('no dart to hold a lock from');
  });
}
