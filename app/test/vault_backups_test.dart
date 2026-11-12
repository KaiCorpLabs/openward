import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/security/backups.dart';
import 'package:openward/src/rust/api/backups.dart';
import 'package:openward/src/rust/api/security.dart';

import 'fakes.dart';

class Core extends FakeOpenWard {
  int exports = 0, restores = 0, previews = 0;
  bool empty = true;
  @override
  Future<void> exportVaultBackup({
    required String path,
    required BackupFormat format,
    required String password,
    required bool acknowledgePlaintext,
  }) async {
    expect(format, BackupFormat.json);
    expect(acknowledgePlaintext, isTrue);
    expect(password, 'current password');
    exports++;
  }

  @override
  Future<BackupPreview> previewVaultBackup({
    required String path,
    required String credential,
    required bool useKit,
  }) async {
    previews++;
    return BackupPreview(
      format: BackupFormat.encrypted,
      items: 3,
      secrets: 1,
      unreadable: 0,
      digest: 'checked-file',
      destinationEmpty: empty,
    );
  }

  @override
  Future<void> restoreVaultBackup({
    required String path,
    required String credential,
    required bool useKit,
    required String expectedDigest,
    required bool confirmed,
  }) async {
    expect(expectedDigest, 'checked-file');
    expect(confirmed, isTrue);
    restores++;
  }
}

Widget harness(Core core, {BackupFormat? format}) => ProviderScope(
  overrides: [openWardProvider.overrideWithValue(core)],
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) =>
                VaultBackupDialog(path: '/synthetic/backup', format: format),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);
void main() {
  testWidgets(
    'plaintext export requires the warning acknowledgement and current password',
    (t) async {
      final core = Core();
      await t.pumpWidget(harness(core, format: BackupFormat.json));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final submit = find.byKey(const ValueKey('backup.submit'));
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      expect(find.textContaining('Anyone who can read it'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('backup.confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('backup.confirm')));
      await t.pump();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.enterText(
        find.byKey(const ValueKey('backup.credential')),
        'current password',
      );
      await t.pump();
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(core.exports, 1);
      expect(core.restores, 0);
      await t.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets(
    'restore needs a checked file, empty destination and a separate confirmation',
    (t) async {
      final core = Core()..empty = false;
      await t.pumpWidget(harness(core));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final submit = find.byKey(const ValueKey('backup.submit'));
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.ensureVisible(find.byKey(const ValueKey('backup.preview')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('backup.preview')));
      await t.pumpAndSettle();
      expect(core.restores, 0);
      expect(find.textContaining('This vault is not empty'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('backup.confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('backup.confirm')));
      await t.pump();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      core.empty = true;
      await t.ensureVisible(find.byKey(const ValueKey('backup.preview')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('backup.preview')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('backup.credential')),
        'changed credential',
      );
      await t.pump();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.ensureVisible(find.byKey(const ValueKey('backup.preview')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('backup.preview')));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.ensureVisible(find.byKey(const ValueKey('backup.confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('backup.confirm')));
      await t.pump();
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(core.restores, 1);
      expect(core.previews, 3);
      await t.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets('backup controls are disabled for a legacy vault', (t) async {
    final core = Core();
    await t.pumpWidget(
      ProviderScope(
        overrides: [openWardProvider.overrideWithValue(core)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: VaultBackups()),
        ),
      ),
    );
    expect(core.securityState().phase, VaultPhase.legacy);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(
      t
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .every((b) => b.onPressed == null),
      isTrue,
    );
    await t.pumpWidget(const SizedBox());
    await core.securityEvents.close();
  });
}
