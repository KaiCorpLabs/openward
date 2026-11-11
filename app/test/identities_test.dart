import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/identities/identities.dart';
import 'package:openward/l10n/app_localizations.dart';
import 'package:openward/src/rust/api/identities.dart';

KeyView key(
  String path, {
  KeyStateKind state = KeyStateKind.found,
  String? algorithm = 'Ed25519',
  String? fingerprint = 'SHA256:4vQmTx9Zk0sPq2LwE1Yh7cRbNnLk2c',
  String? comment = 'ana@laptop',
}) => KeyView(
  path: path,
  state: state,
  algorithm: algorithm,
  fingerprint: fingerprint,
  comment: comment,
);

IdentityView identity({
  List<String> files = const ['~/.ssh/deploy_ed25519'],
  List<KeyView>? keys,
  List<String> groups = const [],
  List<String> hosts = const [],
  int hostCount = 0,
}) => IdentityView(
  id: '1',
  rev: BigInt.one,
  spec: IdentitySpec(label: 'deploy', user: 'deploy', identityFiles: files),
  keys: keys ?? [for (final f in files) key(f)],
  groups: groups,
  hosts: hosts,
  chooserIds: [
    for (final _ in [...groups, ...hosts]) 'x',
  ],
  hostCount: hostCount,
);

void main() {
  final l = lookupAppLocalizations(const Locale('es'));

  test('keys say what they are, or why that is not known', () {
    expect(
      keyDetail(l, key('~/.ssh/deploy')),
      'Ed25519 · SHA256:4vQmT…Lk2c · ana@laptop',
    );
    expect(
      keyDetail(l, key('~/.ssh/old', comment: null, algorithm: 'RSA 3072')),
      'RSA 3072 · SHA256:4vQmT…Lk2c',
    );
    expect(
      keyDetail(l, key('~/.ssh/gone', state: KeyStateKind.missing)),
      'No está en este equipo',
    );
    expect(shortFingerprint('SHA256:short'), 'SHA256:short');
    expect(baseName('~/.ssh/deploy_ed25519'), 'deploy_ed25519');
  });

  test('who uses an identity, and what it brings', () {
    expect(usedByText(l, identity()), 'Nadie la usa todavía');
    expect(
      usedByText(
        l,
        identity(groups: ['Producción'], hosts: ['bastion'], hostCount: 6),
      ),
      'Grupo Producción y bastion · 6 hosts',
    );
    expect(
      usedByText(l, identity(hosts: ['a', 'b', 'c', 'd'], hostCount: 4)),
      'a, b y 2 más · 4 hosts',
    );
    expect(identitySummary(l, identity()), 'deploy · deploy_ed25519');
    expect(
      identitySummary(l, identity(files: ['~/.ssh/a', '~/.ssh/b'])),
      'deploy · a y 1 más',
    );
    expect(identitySummary(l, identity(files: [])), 'deploy · las habituales');
    expect(
      missingKeys(
        identity(keys: [key('~/.ssh/gone', state: KeyStateKind.missing)]),
      ).single.path,
      '~/.ssh/gone',
    );
  });

  test('paths under the home folder are shown with ~', () {
    const mac = '/Users/ana';
    expect(tildePath('/Users/ana/.ssh/deploy', home: mac), '~/.ssh/deploy');
    expect(tildePath('/etc/ssh/key', home: mac), '/etc/ssh/key');
    expect(tildePath('/Users/anax/key', home: mac), '/Users/anax/key');
    expect(tildePath('/Users/ana', home: '/Users/ana/'), '~');
    // Windows: either separator, and any case.
    const win = r'C:\Users\ana';
    expect(tildePath(r'C:\Users\ana\.ssh\deploy', home: win), '~/.ssh/deploy');
    expect(tildePath('c:/users/ana/.ssh/deploy', home: win), '~/.ssh/deploy');
    expect(tildePath(r'D:\keys\deploy', home: win), r'D:\keys\deploy');
    // This machine's own home.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) {
      expect(tildePath('$home${Platform.pathSeparator}.ssh'), '~/.ssh');
    }
  });

  test('certificates end on a date', () {
    final year = DateTime.now().year;
    String until(DateTime d) => certDate(
      l,
      CertView(
        path: 'c',
        implicit: true,
        validBeforeMs: d.millisecondsSinceEpoch,
        expired: false,
        principals: const [],
      ),
    );
    expect(until(DateTime(year, 11, 30)), '30 nov');
    expect(until(DateTime(year + 1, 1, 2)), '2 ene ${year + 1}');
    expect(
      certDate(
        l,
        const CertView(
          path: 'c',
          implicit: true,
          expired: false,
          principals: [],
        ),
      ),
      'sin caducidad',
    );
  });

  test('a certificate is said to run out only in its last week', () {
    final now = DateTime(2026, 11, 6, 12);
    int? left(Duration d) =>
        certificateDaysLeft(now.add(d).millisecondsSinceEpoch, now: now);
    expect(left(const Duration(hours: 3)), 1);
    expect(left(const Duration(days: 2, hours: 1)), 3);
    expect(left(const Duration(days: 7)), 7);
    expect(left(const Duration(days: 8)), isNull);
    expect(left(const Duration(hours: -1)), isNull, reason: 'run out');
    expect(certificateDaysLeft(null, now: now), isNull, reason: 'never');
  });
}
