import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/security/recovery.dart';
import 'package:openward/security/settings.dart';

import 'fakes.dart';

class RecoveryCore extends FakeOpenWard {
  static const kit =
      'OWRK1-0001-0002-0003-0004-0005-0006-0007-0008-0009-000A-000B-000C-000D-000E-000F-0010-12345678';
  @override
  Future<int> passwordScore({required String password}) async => 4;
  int cancelled = 0;
  int confirmed = 0;
  int changes = 0;
  bool reject = false;
  bool? usedKit;
  Completer<void>? waiting;
  @override
  Future<String> prepareRecoveryKit({required String password}) async {
    if (password != 'current public password') {
      throw StateError('authorization');
    }
    return kit;
  }

  @override
  Future<Uint8List> preparedRecoveryQr() async =>
      Uint8List.fromList([1, 0, 1, 0, 1, 0, 1, 0, 1]);
  @override
  Future<void> cancelVaultSetup() async {
    cancelled++;
  }

  @override
  Future<void> completeVaultSetup({
    required String group3,
    required String group12,
  }) async {
    if (group3 != '0003' || group12 != '000C') throw StateError('confirmation');
    confirmed++;
  }

  @override
  Future<void> changeVaultPassword({
    required String authorization,
    required bool useKit,
    required String password,
  }) async {
    changes++;
    usedKit = useKit;
    if (waiting != null) await waiting!.future;
    if (reject) throw StateError('authorization');
  }
}

Widget harness(RecoveryCore core, Widget child) => ProviderScope(
  overrides: [openWardProvider.overrideWithValue(core)],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);
void main() {
  testWidgets(
    'replacement requires password and saved-kit proof before activation',
    (tester) async {
      final core = RecoveryCore();
      await tester.pumpWidget(
        harness(core, const VaultSetup(regenerate: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Regenerate recovery kit'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryQr), findsNothing);
      await tester.enterText(find.byType(TextField), 'current public password');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Regenerate recovery kit'),
      );
      await tester.pumpAndSettle();
      expect(find.text(RecoveryCore.kit), findsOneWidget);
      expect(find.byType(RecoveryQr), findsOneWidget);
      expect(core.confirmed, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'I have saved it'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'I have saved it'));
      await tester.pumpAndSettle();
      expect(find.text(RecoveryCore.kit), findsNothing);
      expect(find.byType(RecoveryQr), findsNothing);
      expect(core.confirmed, 0);
      await tester.enterText(find.byType(TextField).at(0), '0003');
      await tester.enterText(find.byType(TextField).at(1), '000C');
      await tester.tap(find.widgetWithText(FilledButton, 'Activate new kit'));
      await tester.pumpAndSettle();
      expect(core.confirmed, 1);
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets(
    'password mismatch stays local; rejection clears authorization; kit can authorize a retry',
    (tester) async {
      final core = RecoveryCore()..reject = true;
      await tester.pumpWidget(harness(core, const VaultPasswordChange()));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'current public password');
      await tester.enterText(fields.at(1), 'strong new public password');
      await tester.enterText(fields.at(2), 'different');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(core.changes, 0);
      await tester.enterText(fields.at(2), 'strong new public password');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(core.changes, 1);
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, isEmpty);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(0), RecoveryCore.kit);
      core.reject = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(core.changes, 2);
      expect(core.usedKit, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets(
    'late password change completion does not use disposed controllers',
    (tester) async {
      final core = RecoveryCore()..waiting = Completer<void>();
      await tester.pumpWidget(harness(core, const VaultPasswordChange()));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'current public password');
      await tester.enterText(fields.at(1), 'strong new public password');
      await tester.enterText(fields.at(2), 'strong new public password');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      core.waiting!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await core.securityEvents.close();
    },
  );
}
