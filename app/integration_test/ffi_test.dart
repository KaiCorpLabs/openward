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
import 'package:openward/src/rust/api/backups.dart';
import 'package:openward/src/rust/api/identities.dart';
import 'package:openward/src/rust/api/keychain.dart';
import 'package:openward/src/rust/api/known_hosts.dart';
import 'package:openward/src/rust/api/local_data.dart';
import 'package:openward/src/rust/api/programs.dart';
import 'package:openward/src/rust/api/snippets.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/src/rust/api/security.dart';
import 'package:openward/src/rust/api/sftp.dart';
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
    app = await OpenWard.open(
      dataDir: '${dir.path}/data',
      requireOnboarding: false,
    );
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
  test('D8 mandatory onboarding gates legacy data and enables independent recovery', () async {
    final targetDir = await Directory.systemTemp.createTemp('openward-d8-');
    final target = await OpenWard.openWithHome(
      dataDir: '${targetDir.path}/data',
      home: '${targetDir.path}/home',
      requireOnboarding: true,
    );
    try {
      expect(target.vaultOnboardingRequired(), isTrue);
      expect(target.hosts(), isEmpty);
      await expectLater(
        target.createHost(
          spec: const HostSpec(label: 'denied', address: 'denied.invalid'),
        ),
        throwsA(isVault(VaultErrorKind.locked)),
      );
      const password = 'Meteor-7-Parchment-Unfurl-Quartz-92!';
      final kit = await target.prepareVault(password: password);
      expect(await target.preparedRecoveryQr(), isNotEmpty);
      expect(target.vaultOnboardingRequired(), isTrue);
      final groups = kit.split('-');
      await target.completeVaultSetup(group3: groups[3], group12: groups[12]);
      expect(target.vaultOnboardingRequired(), isFalse);
      expect(target.vaultNeedsPassword(), isFalse);
      final id = await target.createHost(
        spec: const HostSpec(label: 'D8 protected', address: 'd8.invalid'),
      );
      await target.lockVault();
      expect(target.hosts(), isEmpty);
      await target.recoverVault(kit: kit);
      expect(target.host(id: id).spec.label, 'D8 protected');
    } finally {
      target.dispose();
      await targetDir.delete(recursive: true);
    }
  });

  test('the core built in is the app\'s version', () {
    expect(coreVersion(), appVersion);
  });

  test('encrypted vault lifecycle crosses the generated bridge and rejects locked actions', () async {
    final id = await app.createHost(
      spec: const HostSpec(label: 'private host', address: 'private.example'),
    );
    final terminal = app.terminal(cols: 80, rows: 24, scrollback: 100);
    final browser = app.sftp();
    final phases = <VaultPhase>[];
    final subscription = app.watchSecurity().listen(
      (view) => phases.add(view.phase),
    );
    try {
      const password = 'Meteor-7-Parchment-Unfurl-Quartz-92!';
      expect(
        await app.passwordScore(password: password),
        greaterThanOrEqualTo(3),
      );
      final kit = await app.prepareVault(password: password);
      final groups = kit.split('-');
      await app.completeVaultSetup(group3: groups[3], group12: groups[12]);
      expect(app.securityState().phase, VaultPhase.unlocked);
      expect(app.securityState().recoveryAvailable, isTrue);
      expect(app.securityState().nativeEnabled, isFalse);
      expect(app.host(id: id).spec.label, 'private host');
      await app.lockVault();
      await until(
        () => phases.contains(VaultPhase.locked),
        'locked notification',
      );
      expect(app.hosts(), isEmpty);
      expect(terminal.screenText(), isEmpty);
      await expectLater(
        browser.list(path: '/'),
        throwsA(
          isA<FileError>().having((e) => e.kind, 'kind', FileErrorKind.locked),
        ),
      );
      final serial = await app
          .openSerial(
            session: terminal,
            path: '/never-open-this-test-device',
            line: const SerialLineSpec(
              baud: 115200,
              dataBits: 8,
              parity: ParityKind.none,
              stopBits: 1,
              flow: FlowKind.none,
            ),
          )
          .first;
      expect(serial.kind, SessionEventKind.closed);
      expect(serial.closed!.failure!.message, contains('unlock'));
      final ssh = await app.connect(session: terminal, hostId: id).first;
      expect(ssh.kind, SessionEventKind.closed);
      expect(ssh.closed!.failure!.message, contains('unlock'));
      final sftp = await app.connectSftp(browser: browser, hostId: id).first;
      expect(sftp.kind, SessionEventKind.closed);
      expect(sftp.closed!.failure!.message, contains('unlock'));
      await expectLater(
        app.unlockVault(password: 'wrong password'),
        throwsA(isA<VaultError>()),
      );
      expect(app.securityState().phase, VaultPhase.locked);
      await app.recoverVault(kit: kit);
      expect(app.host(id: id).spec.label, 'private host');
      await app.setAutoLock(seconds: BigInt.from(60));
      expect(app.securityState().autoLockSeconds, BigInt.from(60));
      await app.lockVault();
      await app.unlockVault(password: password);
      expect(app.host(id: id).spec.label, 'private host');
    } finally {
      terminal.close();
      browser.close();
      // The native observer belongs to App; release its owner before waiting
      // for the Rust sink to finish the subscription cancellation handshake.
      final cancelled = subscription.cancel();
      terminal.dispose();
      browser.dispose();
      app.dispose();
      await cancelled;
    }
  });

  test(
    'recovery rotation, PDF and password changes cross the generated bridge',
    () async {
      const oldPassword = 'Meteor-7-Parchment-Unfurl-Quartz-92!';
      const newPassword = 'Orchid-49-Cabin-Helium-Ripple-73!';
      try {
        final id = await app.createHost(
          spec: const HostSpec(
            label: 'recovery fixture',
            address: 'fixture.example',
          ),
        );
        final kit = await app.prepareVault(password: oldPassword);
        final groups = kit.split('-');
        final qr = await app.preparedRecoveryQr();
        expect(qr, isNotEmpty);
        final pdf = '${dir.path}/recovery.pdf';
        await app.exportPreparedRecovery(path: pdf);
        expect(await File(pdf).readAsString(), startsWith('%PDF-1.4'));
        await expectLater(
          app.exportPreparedRecovery(path: pdf),
          throwsA(isA<VaultError>()),
        );
        await app.completeVaultSetup(group3: groups[3], group12: groups[12]);
        await expectLater(
          app.changeVaultPassword(
            authorization: 'wrong',
            useKit: false,
            password: newPassword,
          ),
          throwsA(isA<VaultError>()),
        );
        await app.changeVaultPassword(
          authorization: oldPassword,
          useKit: false,
          password: newPassword,
        );
        await app.lockVault();
        await expectLater(
          app.unlockVault(password: oldPassword),
          throwsA(isA<VaultError>()),
        );
        await app.recoverVault(kit: kit);
        final next = await app.prepareRecoveryKit(password: newPassword);
        await app.cancelVaultSetup();
        await app.lockVault();
        await expectLater(
          app.recoverVault(kit: next),
          throwsA(isA<VaultError>()),
        );
        await app.recoverVault(kit: kit);
        final replacement = await app.prepareRecoveryKit(password: newPassword);
        final parts = replacement.split('-');
        await app.completeVaultSetup(group3: parts[3], group12: parts[12]);
        await app.lockVault();
        await expectLater(
          app.recoverVault(kit: kit),
          throwsA(isA<VaultError>()),
        );
        await app.recoverVault(kit: replacement);
        await app.changeVaultPassword(
          authorization: replacement,
          useKit: true,
          password: oldPassword,
        );
        expect(app.host(id: id).spec.label, 'recovery fixture');
        await app.lockVault();
        await app.unlockVault(password: oldPassword);
        expect(app.host(id: id).spec.label, 'recovery fixture');
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'D6 secrets and protected local documents cross the generated bridge',
    () async {
      const password = 'Meteor-7-Parchment-Unfurl-Quartz-92!';
      const nextPassword = 'Larch-93-Quietly-Orbit-Parchment-72!';
      try {
        final kit = await app.prepareVault(password: password);
        final groups = kit.split('-');
        await app.completeVaultSetup(group3: groups[3], group12: groups[12]);
        final made = await app.generateVaultKey(
          name: 'D6 private key',
          kind: SshKeyType.ed25519,
          comment: 'fixture',
        );
        expect(made.failure, isNull);
        final key = made.key!;
        expect(key.path, startsWith('vault:'));
        final public = await app.publicKeyLine(path: key.path);
        expect(public, startsWith('ssh-ed25519 '));
        expect(
          await app.savedCredentials(),
          isEmpty,
        ); // metadata API excludes private keys
        final exported = '${dir.path}/exported';
        await app.exportVaultKey(path: key.path, to: exported);
        await expectLater(
          app.exportVaultKey(path: key.path, to: exported),
          throwsA(isA<VaultError>()),
        );
        final imported = await app.importVaultKeyFile(
          name: 'D6 imported',
          path: exported,
        );
        expect(imported.failure, isNull);
        expect(await app.publicKeyLine(path: imported.key!.path), public);
        final copy = '${dir.path}/copy-key';
        await File(exported).copy(copy);
        final copied = await app.storeKeyFile(path: copy, removeSource: false);
        expect(copied.failure, isNull);
        expect(File(copy).existsSync(), isTrue);
        final movedFile = '${dir.path}/move-key';
        await File(exported).copy(movedFile);
        final moved = await app.storeKeyFile(
          path: movedFile,
          removeSource: true,
        );
        expect(moved.failure, isNull);
        expect(File(movedFile).existsSync(), isFalse);
        app.writeLocalDocument(
          kind: LocalDocument.history,
          json: '{"commands":["private-command-D6"]}',
        );
        app.writeLocalDocument(
          kind: LocalDocument.recent,
          json: '{"connections":["private-host-D6"]}',
        );
        for (final name in ['history', 'recent']) {
          final bytes = await File('${dir.path}/data/$name.json').readAsBytes();
          expect(bytes.take(5), [79, 87, 76, 68, 1]);
          expect(String.fromCharCodes(bytes), isNot(contains('private-')));
        }
        await app.lockVault();
        expect(await app.keys(), isEmpty);
        expect(await app.savedCredentials(), isEmpty);
        expect(
          () => app.readLocalDocument(kind: LocalDocument.history),
          throwsA(isVault(VaultErrorKind.locked)),
        );
        expect(
          () => app.writeLocalDocument(kind: LocalDocument.recent, json: '{}'),
          throwsA(isVault(VaultErrorKind.locked)),
        );
        await expectLater(
          app.exportVaultKey(path: key.path, to: '${dir.path}/blocked'),
          throwsA(isVault(VaultErrorKind.locked)),
        );
        expect(File('${dir.path}/blocked').existsSync(), isFalse);
        await app.recoverVault(kit: kit);
        expect(
          app.readLocalDocument(kind: LocalDocument.history),
          contains('private-command-D6'),
        );
        await app.changeVaultPassword(
          authorization: password,
          useKit: false,
          password: nextPassword,
        );
        await app.lockVault();
        await app.unlockVault(password: nextPassword);
        expect(await app.publicKeyLine(path: key.path), public);
        expect(
          app.readLocalDocument(kind: LocalDocument.recent),
          contains('private-host-D6'),
        );
        expect(await app.deleteKey(path: key.path), isNull);
        expect((await app.keys()).any((k) => k.path == key.path), isFalse);
        app.eraseLocalDocument(kind: LocalDocument.history);
        expect(File('${dir.path}/data/history.json').existsSync(), isFalse);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'D7 portable backups restore into independent vaults by kit and JSON',
    () async {
      const sourcePassword = 'Meteor-7-Parchment-Unfurl-Quartz-92!';
      const targetPassword = 'Larch-93-Quietly-Orbit-Parchment-72!';
      final targets = <OpenWard>[];
      try {
        final kit = await app.prepareVault(password: sourcePassword);
        final groups = kit.split('-');
        await app.completeVaultSetup(group3: groups[3], group12: groups[12]);
        final id = await app.createHost(
          spec: const HostSpec(label: 'D7 host', address: 'backup.invalid'),
        );
        final made = await app.generateVaultKey(
          name: 'D7 private key',
          kind: SshKeyType.ed25519,
          comment: 'public fixture',
        );
        expect(made.failure, isNull);
        final public = await app.publicKeyLine(path: made.key!.path);
        final archive = '${dir.path}/copy.owvault';
        final json = '${dir.path}/copy.json';
        await app.exportVaultBackup(
          path: archive,
          format: BackupFormat.encrypted,
          password: '',
          acknowledgePlaintext: false,
        );
        await expectLater(
          app.exportVaultBackup(
            path: json,
            format: BackupFormat.json,
            password: 'wrong',
            acknowledgePlaintext: true,
          ),
          throwsA(isA<VaultError>()),
        );
        expect(File(json).existsSync(), isFalse);
        await app.exportVaultBackup(
          path: json,
          format: BackupFormat.json,
          password: sourcePassword,
          acknowledgePlaintext: true,
        );
        final original = await File(archive).readAsBytes();
        for (final mode in [BackupFormat.encrypted, BackupFormat.json]) {
          final target = await OpenWard.openWithHome(
            dataDir: '${dir.path}/restore-${mode.name}/data',
            home: '${dir.path}/restore-${mode.name}',
          );
          targets.add(target);
          final targetKit = await target.prepareVault(password: targetPassword);
          final parts = targetKit.split('-');
          await target.completeVaultSetup(group3: parts[3], group12: parts[12]);
          final path = mode == BackupFormat.encrypted ? archive : json;
          final credential = mode == BackupFormat.encrypted ? kit : '';
          final view = await target.previewVaultBackup(
            path: path,
            credential: credential,
            useKit: true,
          );
          expect(view.items, 2);
          expect(view.secrets, 1);
          expect(view.destinationEmpty, isTrue);
          expect(target.hosts(), isEmpty);
          await expectLater(
            target.restoreVaultBackup(
              path: path,
              credential: credential,
              useKit: true,
              expectedDigest: view.digest,
              confirmed: false,
            ),
            throwsA(isA<VaultError>()),
          );
          if (mode == BackupFormat.encrypted) {
            final changed = List<int>.of(original);
            changed[changed.length - 1] ^= 1;
            await File(path).writeAsBytes(changed);
            await expectLater(
              target.restoreVaultBackup(
                path: path,
                credential: credential,
                useKit: true,
                expectedDigest: view.digest,
                confirmed: true,
              ),
              throwsA(isA<VaultError>()),
            );
            expect(target.hosts(), isEmpty);
            await File(path).writeAsBytes(original);
          }
          await target.restoreVaultBackup(
            path: path,
            credential: credential,
            useKit: true,
            expectedDigest: view.digest,
            confirmed: true,
          );
          expect(target.host(id: id).spec.label, 'D7 host');
          expect(await target.publicKeyLine(path: made.key!.path), public);
          await expectLater(
            target.restoreVaultBackup(
              path: path,
              credential: credential,
              useKit: true,
              expectedDigest: view.digest,
              confirmed: true,
            ),
            throwsA(isA<VaultError>()),
          );
          await target.lockVault();
          await expectLater(
            target.unlockVault(password: sourcePassword),
            throwsA(isA<VaultError>()),
          );
          await target.recoverVault(kit: targetKit);
          expect(target.host(id: id).spec.address, 'backup.invalid');
        }
      } finally {
        for (final target in targets) {
          target.dispose();
        }
        app.dispose();
      }
    },
  );

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
