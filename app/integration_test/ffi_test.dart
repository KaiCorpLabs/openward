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
import 'package:openward/core/version.dart';
import 'package:openward/src/rust/api/app.dart';
import 'package:openward/src/rust/api/identities.dart';
import 'package:openward/src/rust/api/keychain.dart';
import 'package:openward/src/rust/api/known_hosts.dart';
import 'package:openward/src/rust/api/programs.dart';
import 'package:openward/src/rust/api/snippets.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/src/rust/api/tunnels.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/src/rust/api/workspaces.dart';
import 'package:openward/src/rust/frb_generated.dart';

/// A [VaultError] of `kind`: the app tells errors by kind, never by text.
Matcher isVault(VaultErrorKind kind) =>
    isA<VaultError>().having((e) => e.kind, 'kind', kind);

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

  /// The core built into the app is the version the app says it is: a
  /// stale library would not be.
  test('the core built in is the app\'s version', () {
    expect(coreVersion(), appVersion);
  });

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
      throwsA(isVault(VaultErrorKind.conflict)),
    );
    // With what it read, an edit made over a change of meanwhile (a star,
    // a system learned) goes in, and keeps that change.
    final read = app.host(id: id);
    await app.setFavorite(id: id, favorite: true);
    final s = read.spec;
    await app.updateHost(
      id: id,
      rev: read.rev,
      spec: HostSpec(
        label: 'web-2',
        address: s.address,
        groupId: s.groupId,
        tags: s.tags,
        notes: s.notes,
        settings: s.settings,
        favorite: s.favorite,
        systemCode: s.systemCode,
      ),
      base: s,
    );
    final merged = app.host(id: id).spec;
    expect((merged.label, merged.favorite), ('web-2', true));
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
    Compression yes
''');
    final report = await app.importSshConfig(file: config.path);
    expect((report.created, report.tunnels), (2, 1));
    expect(report.warnings.single.kind, ImportWarningKind.unsupported);
    expect(report.warnings.single.subject, 'Compression');
    final hosts = {for (final h in app.hosts()) h.label: h};
    expect(hosts['bastion']!.importedAlias, 'bastion');
    final route = app.host(id: hosts['app']!.id).spec.settings;
    expect(route.route, RouteKind.jump);
    expect(route.jumps.single.hostId, hosts['bastion']!.id);

    final tunnel = app.tunnels().single;
    expect(tunnel.spec.hostId, hosts['app']!.id);
    expect(tunnel.spec.kind, TunnelKind.local);
    expect((tunnel.spec.listenPort, tunnel.spec.destPort), (8080, 80));
    expect((tunnel.spec.autostart, tunnel.imported), (true, true));

    final again = await app.importSshConfig(file: config.path);
    expect((again.created, again.skipped, again.tunnels), (0, 2, 0));
  });

  test('previewing an ssh config and importing part of it', () async {
    final config = File('${dir.path}/config')
      ..writeAsStringSync('''
Host bastion
    HostName bastion.example.com
    User ops
Host app
    ProxyJump bastion
    Port 2222
Host db
''');
    final preview = await app.previewSshConfig(file: config.path);
    expect(preview.map((p) => p.alias), ['bastion', 'app', 'db']);
    final appHost = preview[1];
    expect(appHost.jumps, ['bastion']);
    expect((appHost.port, appHost.existing), (2222, false));
    // The bastion comes along with the host that jumps through it.
    final report = await app.importSshConfig(file: config.path, only: ['app']);
    expect(report.created, 2);
    expect(app.hosts().map((h) => h.label).toSet(), {'bastion', 'app'});
    final after = await app.previewSshConfig(file: config.path);
    expect(after.where((p) => p.existing).map((p) => p.alias), [
      'bastion',
      'app',
    ]);
  });

  test('an identity on a group, where values come from, and its use', () async {
    final id = await app.createIdentity(
      spec: const IdentitySpec(
        label: 'deploy',
        user: 'deploy',
        identityFiles: ['~/.ssh/openward-test-missing'],
      ),
    );
    final group = await app.createGroup(
      spec: GroupSpec(
        name: 'prod',
        settings: SettingsSpec(
          user: 'ops',
          identity: IdentityChoice.use,
          identityId: id,
        ),
      ),
    );
    final web = await app.createHost(
      spec: HostSpec(label: 'web', address: 'web.example.com', groupId: group),
    );
    final db = await app.createHost(
      spec: const HostSpec(label: 'db', address: 'db.example.com'),
    );
    final detail = app.host(id: web);
    expect(detail.effective.user, 'deploy');
    final user = detail.origins.firstWhere((o) => o.field == 'user');
    expect((user.origin, user.identityId), (OriginKind.identity, id));
    final choice = detail.origins.firstWhere((o) => o.field == 'identity');
    expect((choice.origin, choice.groupId), (OriginKind.group, group));
    // What an editor shows for a host that would choose none.
    final none = app.inherited(
      groupId: group,
      identity: IdentityChoice.none,
      identityId: '',
    );
    expect(none.effective.user, 'ops');

    final view = (await app.identities()).single;
    expect(view.hostCount, 1);
    expect(view.groups, ['prod']);
    expect(view.keys.single.state, KeyStateKind.missing);
    expect(view.chooserIds, [group]);

    // The db too, in one go; the preview first.
    final rows = app.identityUse(identityId: id, choosers: [group, db]);
    final dbRow = rows.firstWhere((r) => r.label == 'db');
    expect((dbRow.after, dbRow.nowIsThis, dbRow.now), (true, false, null));
    expect(await app.useIdentity(identityId: id, choosers: [group, db]), 1);
    expect((await app.identity(id: id)).hostCount, 2);
    expect(app.hosts().firstWhere((h) => h.id == db).user, 'deploy');

    await app.delete(id: id);
    expect(await app.identities(), isEmpty);
    expect(app.host(id: web).effective.user, 'ops');
  });

  test('what a group passes down, for editors', () async {
    final group = await app.createGroup(
      spec: const GroupSpec(
        name: 'prod',
        settings: SettingsSpec(user: 'deploy'),
      ),
    );
    final inGroup = app.inherited(
      groupId: group,
      identity: null,
      identityId: '',
    );
    expect(inGroup.effective.user, 'deploy');
    final user = inGroup.origins.firstWhere((o) => o.field == 'user');
    expect((user.origin, user.groupId), (OriginKind.group, group));
    final top = app.inherited(identityId: '');
    expect(top.effective.port, 22);
    expect(
      top.origins.firstWhere((o) => o.field == 'port').origin,
      OriginKind.default_,
    );
    expect(app.reconnectAttempts(), 8);
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
      // `make ci` passes it: there a skip would pass untested.
      if (const bool.fromEnvironment('OPENWARD_REQUIRE_SERVERS')) {
        fail('S2 servers not running (spikes/s2-ssh/servers/up.sh)');
      }
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
    expect(
      (await app.knownHostRows(query: ''))
          .where((r) => r.source == KnownSourceKind.openWard),
      hasLength(1),
    );

    session.text(text: 'echo ssh-\$((6*7))\n');
    await until(() => session.screenText().contains('ssh-42'), 'the echo');
    session.close();
    await sub.cancel();
  });

  test('snippets: saved, what they ask, and filled in', () async {
    final id = await app.createSnippet(
      spec: const SnippetSpec(
        label: 'Logs',
        script: "journalctl -u {{servicio}} -n {{líneas}} --format '{{.X}}' # {{host}}\n",
        defaults: [SnippetValue(name: 'líneas', value: '20')],
      ),
    );
    final s = app.snippetsForExecution().single;
    expect(s.id, id);
    expect(s.spec.script, endsWith('# {{host}}'));
    expect(s.variables.asked, ['servicio', 'líneas']);
    expect(s.variables.builtins, ['host']);
    expect(s.spec.defaults.single.value, '20');
    expect(
      renderSnippet(
        script: s.spec.script,
        values: const [
          SnippetValue(name: 'servicio', value: 'nginx'),
          SnippetValue(name: 'líneas', value: '50'),
          SnippetValue(name: 'host', value: 'web-1'),
        ],
      ),
      "journalctl -u nginx -n 50 --format '{{.X}}' # web-1",
    );
    expect(snippetVariables(script: r'echo \{{x}} {{y}}').asked, ['y']);
    await app.updateSnippet(
      id: id,
      rev: s.rev,
      spec: const SnippetSpec(label: 'Logs', script: 'uptime', typeOnly: true),
    );
    expect(app.snippetsForExecution().single.spec.typeOnly, isTrue);
    await app.delete(id: id);
    expect(app.snippetsForExecution(), isEmpty);
  });

  test('known hosts: OpenWard\'s and the file\'s, a hashed line, forgetting', () async {
    const key =
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f';
    const other =
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJON9ypgHeCkesivXcy8heayyTUCM9gTjTKSUZit/91';
    const hashed =
        '|1|MDEyMzQ1Njc4OWFiY2RlZmdoaWo=|xBEZ8so+rs/llqU4DkVYMFhGsbE=';
    final ssh = Directory('${dir.path}/ssh')..createSync();
    final file = File('${ssh.path}/known_hosts')
      ..writeAsStringSync('# mine\n$hashed $other\n10.0.4.21 $key db\n');
    final own = await OpenWard.openWithSshDir(
      dataDir: '${dir.path}/own',
      sshDir: ssh.path,
    );
    await own.createHost(
      spec: const HostSpec(label: 'bastion', address: 'bastion.example.com'),
    );
    await own.trustHostKey(host: 'web.example.com', port: 2222, key: key);
    expect(own.knownHostsFile(), file.path);

    final rows = await own.knownHostRows(query: '');
    expect(await own.knownHostCount(), rows.length);
    expect(rows.map((r) => r.source), [
      KnownSourceKind.openWard,
      KnownSourceKind.file,
      KnownSourceKind.file,
    ]);
    expect(rows[0].hosts, '[web.example.com]:2222');
    expect(rows[0].addedMs, isNotNull);
    expect((rows[1].line, rows[1].hosts), (2, null));
    expect(rows[1].revealed, 'bastion.example.com');
    expect(rows[1].saved, ['bastion']);
    expect(rows[2].comment, 'db');
    final found = await own.knownHostRows(query: 'bastion.example.com');
    expect(found.single.line, 2);

    await own.forgetKnownHost(row: found.single);
    expect(file.readAsStringSync(), '# mine\n10.0.4.21 $key db\n');
    expect(File('${file.path}.old').readAsStringSync(), contains(hashed));
    // A stale row (the file moved on) is refused.
    await expectLater(
      own.forgetKnownHost(row: rows[2]),
      throwsA(isVault(VaultErrorKind.fileChanged)),
    );
    await own.forgetKnownHost(row: rows[0]);
    expect(
      (await own.knownHostRows(query: ''))
          .where((r) => r.source == KnownSourceKind.openWard),
      isEmpty,
    );
  });

  test('hosts from a CSV file, and again without repeating them', () async {
    final csv = File('${dir.path}/hosts.csv')
      ..writeAsStringSync(
        'Groups,Label,Tags,Hostname/IP,Protocol,Port,Username,Password\n'
        'Prod/Web,web-1,"prod,nginx",10.0.0.1,ssh,22,deploy,secret\n'
        'Prod,db,,db.example.com,ssh,2222,postgres,\n',
      );
    final read = await app.readProgram(path: csv.path);
    final data = read.data!;
    expect(data.program, ProgramKind.csv);
    final preview = app.previewProgram(data: data);
    final hosts = [
      for (final i in preview.items)
        if (!i.isGroup) i,
    ];
    expect(hosts.map((h) => h.label), ['web-1', 'db']);
    final report = await app.importProgramSelection(
      data: data,
      choice: ProgramChoice(
        hosts: [for (final h in hosts) h.id],
        groupName: 'CSV',
        saveKeys: const [],
      ),
    );
    expect(report.hosts, 2);
    final db = app.hosts().firstWhere((h) => h.label == 'db');
    expect((db.user, db.port), ('postgres', 2222));
    // Read again: what is in already is marked, and skipped.
    final again = await app.readProgram(path: csv.path);
    expect(
      app
          .previewProgram(data: again.data!)
          .items
          .where((i) => !i.isGroup)
          .every((i) => i.existing),
      isTrue,
    );
  });

  test('workspaces: saved, read back, changed and deleted', () async {
    final host = await app.createHost(
      spec: const HostSpec(
        label: 'web',
        address: '10.0.0.1',
        settings: SettingsSpec(),
      ),
    );
    const local = WorkspaceTarget();
    final spec = WorkspaceSpec(
      name: 'Prod',
      tabs: [
        WorkspaceTabSpec(
          title: 'web y local',
          panes: [
            const WorkspacePane(
              split: WorkspaceSplit(vertical: false, ratio: 0.4),
              active: false,
            ),
            WorkspacePane(target: WorkspaceTarget(hostId: host), active: true),
            const WorkspacePane(target: local, active: false),
          ],
        ),
        const WorkspaceTabSpec(
          panes: [],
          sftp: WorkspaceTarget(address: '10.0.0.9', user: 'ana', port: 2200),
        ),
      ],
      active: 1,
    );
    final id = await app.createWorkspace(spec: spec);
    var w = app.workspaces().single;
    expect(w.id, id);
    // Lists compare by identity in the generated classes: field by field.
    String shape(List<WorkspaceTabSpec> tabs) => [
      for (final t in tabs)
        '${t.title}|${t.sftp?.address}:${t.sftp?.port}|'
            '${t.panes.map((p) => '${p.split?.vertical}/${p.split?.ratio}/${p.target?.hostId}/${p.active}').join(',')}',
    ].join(';');
    expect((w.spec.name, w.spec.active), ('Prod', 1));
    expect(shape(w.spec.tabs), shape(spec.tabs));
    expect(w.sessions, 3);
    await app.renameWorkspace(id: id, rev: w.rev, name: 'Producción');
    w = app.workspaces().single;
    expect(w.spec.name, 'Producción');
    expect(shape(w.spec.tabs), shape(spec.tabs));
    // A host deleted later stays named in the workspace.
    await app.delete(id: host);
    expect(
      app.workspaces().single.spec.tabs.first.panes[1].target?.hostId,
      host,
    );
    await app.delete(id: id);
    expect(app.workspaces(), isEmpty);
  });

  test('keys: made, brought in, and their public half', () async {
    final home = Directory('${dir.path}/home')..createSync();
    final mine = await OpenWard.openWithHome(
      dataDir: '${dir.path}/keys-data',
      home: home.path,
    );
    expect(await mine.keys(), isEmpty);
    final made = await mine.generateKey(
      name: 'id_ed25519',
      kind: SshKeyType.ed25519,
      comment: 'ana@portatil',
      passphrase: 'frase larga',
    );
    expect(made.failure, isNull);
    expect(made.key!.encrypted, isTrue);
    expect(made.key!.fingerprint, startsWith('SHA256:'));
    final private = File('${home.path}/.ssh/id_ed25519');
    expect(private.statSync().modeString(), 'rw-------');
    final line = (await mine.publicKeyLine(path: '~/.ssh/id_ed25519'))!;
    expect(line, startsWith('ssh-ed25519 '));
    expect(line, endsWith(' ana@portatil'));

    // The same name again is refused; a copy under another name is not.
    final taken = await mine.generateKey(
      name: 'id_ed25519',
      kind: SshKeyType.rsa,
      comment: '',
    );
    expect(taken.failure!.kind, SshKeyFailureKind.exists);
    final copy = await mine.importKey(
      name: 'copia',
      text: private.readAsStringSync(),
    );
    expect(copy.key!.fingerprint, made.key!.fingerprint);
    final junk = await mine.importKey(name: 'otra', text: 'hola');
    expect(junk.failure!.kind, SshKeyFailureKind.notAKey);
    expect((await mine.keys()).map((k) => k.name), ['copia', 'id_ed25519']);
  });
}
