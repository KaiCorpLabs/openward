// The Rust core through the generated bindings, end to end:
//
//   fvm flutter test integration_test/ffi_test.dart -d macos
//
// The SSH part runs when the S2 test servers are up
// (spikes/s2-ssh/servers/up.sh); otherwise it is skipped.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  late Directory dir;
  late OpenWard app;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('openward-ffi-');
    app = await OpenWard.open(dataDir: '${dir.path}/data');
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> until(bool Function() done, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('hosts, groups, inheritance and conflicts', () async {
    final group = await app.createGroup(
      spec: const GroupSpec(
        name: 'prod',
        settings: SettingsSpec(user: 'deploy', port: 2222),
      ),
    );
    final id = await app.createHost(
      spec: HostSpec(
        label: 'web',
        address: 'web.example.com',
        groupId: group,
        tags: const ['nginx'],
        settings: const SettingsSpec(port: 2200),
      ),
    );
    expect(app.hosts().single.user, 'deploy');
    expect(app.hosts().single.port, 2200);
    expect(app.search(query: 'prod nginx'), [id]);
    expect(app.tags().single.tag, 'nginx');

    final detail = app.host(id: id);
    expect(detail.spec.settings.user, isNull);
    expect(detail.effective.user, 'deploy');
    final origins = {for (final o in detail.origins) o.field: o};
    expect(origins['user']!.origin, OriginKind.group);
    expect(origins['user']!.groupId, group);
    expect(origins['port']!.origin, OriginKind.host);
    expect(origins['host_key_policy']!.origin, OriginKind.default_);

    final rev = await app.updateHost(
      id: id,
      rev: detail.rev,
      spec: HostSpec(
        label: 'web-1',
        address: 'web.example.com',
        groupId: group,
      ),
    );
    expect(rev, detail.rev + BigInt.one);
    // An edit made on the old revision is refused.
    await expectLater(
      app.updateHost(
        id: id,
        rev: detail.rev,
        spec: const HostSpec(label: 'stale', address: 'x'),
      ),
      throwsA(anything),
    );
    await app.delete(id: group);
    expect(app.hosts().single.groupId, isNull);
  });

  test('importing an ssh config', () async {
    final config = File('${dir.path}/config')
      ..writeAsStringSync('''
Host bastion
    HostName bastion.example.com
    User ops
Host app
    ProxyJump bastion
    LocalForward 8080 localhost:80
''');
    final report = await app.importSshConfig(file: config.path);
    expect(report.created, 2);
    expect(report.warnings.single.kind, ImportWarningKind.unsupported);
    expect(report.warnings.single.subject, 'LocalForward');
    final hosts = {for (final h in app.hosts()) h.label: h};
    expect(hosts['bastion']!.importedAlias, 'bastion');
    final route = app.host(id: hosts['app']!.id).spec.settings;
    expect(route.route, RouteKind.jump);
    expect(route.jumps.single.hostId, hosts['bastion']!.id);

    final again = await app.importSshConfig(file: config.path);
    expect((again.created, again.skipped), (0, 2));
  });

  test('a local shell', () async {
    final session = app.terminal(cols: 80, rows: 24, scrollback: 0);
    final events = <SessionEvent>[];
    final sub = app.openLocal(session: session).listen(events.add);
    // Input before the program starts goes nowhere.
    await until(
      () => events.any((e) => e.kind == SessionEventKind.started),
      'the shell to start',
    );
    session.text(text: 'echo ffi-\$((6*7)); exit 3\n');
    await until(() => session.screenText().contains('ffi-42'), 'the echo');
    await until(
      () => events.any((e) => e.kind == SessionEventKind.closed),
      'the shell to end',
    );
    final closed = events.firstWhere((e) => e.kind == SessionEventKind.closed);
    expect(closed.closed!.exitCode, 3);
    expect(closed.closed!.failure, isNull);
    expect(session.poll()?.frame, isNotEmpty);
    await sub.cancel();
  }, skip: Platform.isWindows);

  test('ssh: host key question and a shell', () async {
    final cache = Platform.isMacOS ? 'Library/Caches' : '.cache';
    final fixtures =
        Platform.environment['S2_FIXTURES'] ??
        '${Platform.environment['HOME']}/$cache/openward/s2-fixtures';
    final up =
        await Socket.connect(
              '127.0.0.1',
              22100,
              timeout: const Duration(milliseconds: 300),
            )
            .then((s) {
              s.destroy();
              return true;
            })
            .catchError((_) => false);
    if (!up || !File('$fixtures/id_ed25519').existsSync()) {
      markTestSkipped('S2 servers not running');
      return;
    }
    final id = await app.createHost(
      spec: HostSpec(
        label: 'bastion',
        address: '127.0.0.1',
        settings: SettingsSpec(
          user: 'demo',
          port: 22100,
          identityFiles: ['$fixtures/id_ed25519'],
          agent: AgentKind.off,
        ),
      ),
    );
    final session = app.terminal(cols: 80, rows: 24, scrollback: 0);
    final events = <SessionEvent>[];
    final sub = app.connect(session: session, hostId: id).listen((e) {
      events.add(e);
      final p = e.prompt;
      if (p != null && p.kind == PromptKind.hostKey) {
        app.answer(
          promptId: p.id,
          answer: const PromptAnswer(kind: AnswerKind.accept, texts: []),
        );
      }
    });
    await until(
      () => events.any(
        (e) =>
            e.kind == SessionEventKind.connected ||
            e.kind == SessionEventKind.closed,
      ),
      'the connection',
    );
    final connected = events.firstWhere(
      (e) => e.kind == SessionEventKind.connected,
      orElse: () =>
          fail('did not connect: ${events.last.closed?.failure?.message}'),
    );
    expect(connected.connected!.trust, TrustKind.new_);
    expect(connected.connected!.postQuantum, isTrue);
    expect(events.where((e) => e.kind == SessionEventKind.prompt).length, 1);
    expect(app.knownHosts(), hasLength(1));

    session.text(text: 'echo ssh-\$((6*7))\n');
    await until(() => session.screenText().contains('ssh-42'), 'the echo');
    session.close();
    await sub.cancel();
  });
}
