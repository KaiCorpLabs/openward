import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/src/rust/api/vault.dart';
import 'package:openward/startup_error.dart';

void main() {
  testWidgets('a vault that does not open says why, not an empty window', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      const StartupErrorApp(
        error: VaultError(
          kind: VaultErrorKind.newerFormat,
          message: 'the vault was written by a newer version (format 2)',
        ),
        dataDir: '/tmp/openward-data',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('OpenWard no ha podido abrir sus datos'), findsOneWidget);
    // Why, in words; the core's text under «Detalles».
    expect(
      find.textContaining('una versión más nueva de OpenWard'),
      findsOneWidget,
    );
    expect(
      find.text('the vault was written by a newer version (format 2)'),
      findsOneWidget,
    );
    expect(find.textContaining('/tmp/openward-data'), findsOneWidget);
    expect(find.text('Mostrar la carpeta de datos'), findsOneWidget);
  });

  testWidgets('another OpenWard with the same data says so', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      const StartupErrorApp(
        error: VaultError(
          kind: VaultErrorKind.openElsewhere,
          message: 'the vault is open in another OpenWard',
        ),
        dataDir: '/tmp/openward-data',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Otro OpenWard tiene abiertos'), findsOneWidget);
  });
}
