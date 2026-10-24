import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/errors.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/ui/themes.dart';

void main() {
  /// Every kind the core sends has words, and none of them is English.
  test('a vault error in words, by its kind and not its text', () {
    final l = AppLocalizationsEs();
    for (final kind in VaultErrorKind.values) {
      final e = VaultError(kind: kind, message: 'item 1 changed since …');
      final reason = errorReason(l, e);
      expect(reason, isNot(contains('changed since')), reason: '$kind');
      expect(reason, isNotEmpty);
      expect(errorDetails(e), 'item 1 changed since …');
    }
    const conflict = VaultError(
      kind: VaultErrorKind.conflict,
      message: 'item x changed since revision 1 (now 2)',
    );
    expect(saveErrorText(l, conflict), l.changedMeanwhile);
    const storage = VaultError(
      kind: VaultErrorKind.storage,
      message: 'storage: disk I/O error',
    );
    expect(saveErrorText(l, storage), l.saveFailed(l.errStorage));
    // Anything else: inside OpenWard, with the details.
    expect(errorReason(l, StateError('boom')), l.errInternal);
  });

  /// A change that fails says so, in words, with the core's own under
  /// «Detalles»; the caller hears it failed.
  testWidgets('runAction says what failed', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.grafito),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await runAction(
                context,
                () async => throw const VaultError(
                  kind: VaultErrorKind.storage,
                  message: 'storage: disk I/O error',
                ),
              ),
              child: const Text('Guardar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(
      find.text('No se ha podido guardar: el disco no lo ha aceptado'),
      findsOneWidget,
    );
    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();
    expect(find.text('storage: disk I/O error'), findsOneWidget);
  });

  /// «Detalles» next to a connection that failed: the core's words.
  testWidgets('the details of a failure are the core\'s words', (tester) async {
    const f = FailureView(
      kind: FailureKind.other,
      message: 'opening the shell: no pty',
      label: '',
      host: '',
      port: 0,
      user: '',
      algorithm: '',
      fingerprint: '',
      key: '',
      methods: [],
      reason: 'opening the shell: no pty',
      previous: [],
      seconds: 0,
    );
    expect(errorDetails(f), 'opening the shell: no pty');
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.grafito),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DetailsButton(f)),
      ),
    );
    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();
    expect(find.text('opening the shell: no pty'), findsOneWidget);
  });
}
