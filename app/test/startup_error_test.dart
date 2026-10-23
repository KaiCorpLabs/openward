import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/startup_error.dart';

void main() {
  testWidgets('a vault that does not open says why, not an empty window', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      const StartupErrorApp(
        error: 'the vault was written by a newer version',
        dataDir: '/tmp/openward-data',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('OpenWard no ha podido abrir sus datos'), findsOneWidget);
    expect(
      find.text('the vault was written by a newer version'),
      findsOneWidget,
    );
    expect(find.textContaining('/tmp/openward-data'), findsOneWidget);
    expect(find.text('Mostrar la carpeta de datos'), findsOneWidget);
  });
}
