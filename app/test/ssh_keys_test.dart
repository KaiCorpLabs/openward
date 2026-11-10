import 'package:flutter_test/flutter_test.dart';
import 'package:openward/keys/keys.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/src/rust/api/keychain.dart';
import 'package:openward/src/rust/api/session.dart';

void main() {
  test('new keys get a name no file has, _sk ones on a security key', () {
    expect(freeKeyName(SshKeyType.ed25519, const []), 'id_ed25519');
    expect(
      freeKeyName(SshKeyType.ed25519, const ['id_ed25519', 'id_ed25519_2']),
      'id_ed25519_3',
    );
    expect(
      freeKeyName(SshKeyType.ecdsa, const ['id_ecdsa'], securityKey: true),
      'id_ecdsa_sk',
    );
    expect(
      freeKeyName(SshKeyType.ed25519, const [
        'id_ed25519_sk',
      ], securityKey: true),
      'id_ed25519_sk_2',
    );
  });

  test('a security key that did not make the key says why, as a line', () {
    final l = AppLocalizationsEs();
    final text = keyFailureText(
      l,
      const SshKeyFailure(
        kind: SshKeyFailureKind.securityKey,
        message: 'security key: no security key is plugged in',
        securityKey: SecurityKeyKind.noKey,
      ),
      'id_ed25519_sk',
    );
    expect(text, isNot(contains('plugged')));
    expect(text[0], text[0].toUpperCase());
    expect(text, endsWith('.'));
  });
}
