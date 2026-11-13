import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/keys/key_dialogs.dart';
import 'package:openward/keys/key_picker.dart';
import 'package:openward/keys/keys_page.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/src/rust/api/keychain.dart';
import 'package:openward/src/rust/api/security.dart';
import 'package:openward/ui/themes.dart';

import 'fakes.dart';

const key = SshKey(
  path: 'enclave:019a7ed0-c040-73a6-a9ca-cd0680665dce',
  name: 'hardware-deploy',
  algorithm: 'ECDSA P-256 · Secure Enclave',
  fingerprint: 'SHA256:synthetic',
  comment: 'synthetic@fixture',
  encrypted: false,
  securityKey: false,
  hasPublic: true,
  certificate: false,
  usedBy: [],
);

class Core extends FakeOpenWard {
  Core() {
    security = SecurityView(
      phase: VaultPhase.unlocked,
      autoLockSeconds: BigInt.from(900),
      nativeEnabled: false,
      recoveryAvailable: true,
    );
  }
  bool reject = false;
  int made = 0;
  List<SshKey> saved = [];
  @override
  Future<List<SshKey>> keys() async => saved;
  @override
  String keyComment() => 'synthetic@fixture';
  @override
  Future<SshKeyResult> generateEnclaveKey({
    required String name,
    required String comment,
  }) async {
    made++;
    if (reject) {
      return const SshKeyResult(
        failure: SshKeyFailure(
          kind: SshKeyFailureKind.make,
          message: 'cancelled',
        ),
      );
    }
    saved = [key];
    return const SshKeyResult(key: key);
  }
}

Widget harness(Core core, {bool mac = true, bool page = false}) =>
    ProviderScope(
      overrides: [openWardProvider.overrideWithValue(core)],
      child: MaterialApp(
        theme: materialTheme(
          OwThemes.grafito,
        ).copyWith(platform: mac ? TargetPlatform.macOS : TargetPlatform.linux),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: page
              ? const KeysPage()
              : Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showNewKeyDialog(context),
                    child: const Text('new-key'),
                  ),
                ),
        ),
      ),
    );
Future<void> open(WidgetTester t, Core core, {bool mac = true}) async {
  t.view.physicalSize = const Size(1200, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(harness(core, mac: mac));
  await t.tap(find.text('new-key'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Secure Enclave creation fixes P-256, explains recovery and has no private export/passphrase',
    (t) async {
      final core = Core();
      await open(t, core);
      await t.tap(find.byKey(const ValueKey('newKey.enclave')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('newKey.passphrase')), findsNothing);
      expect(find.byKey(const ValueKey('newKey.pin')), findsNothing);
      expect(find.text('RSA 4096'), findsNothing);
      expect(find.text('Ed25519'), findsNothing);
      expect(
        find.textContaining('cannot recover the private key'),
        findsOneWidget,
      );
      await t.ensureVisible(find.byKey(const ValueKey('newKey.make')));
      await t.tap(find.byKey(const ValueKey('newKey.make')));
      await t.pumpAndSettle();
      expect(core.made, 1);
      expect(core.saved.single.path, startsWith('enclave:'));
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'native cancellation leaves creation open without showing a generated key',
    (t) async {
      final core = Core()..reject = true;
      await open(t, core);
      await t.tap(find.byKey(const ValueKey('newKey.enclave')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('newKey.make')));
      await t.tap(find.byKey(const ValueKey('newKey.make')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(core.saved, isEmpty);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('newKey.make')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('other desktops never offer Secure Enclave generation', (
    t,
  ) async {
    await open(t, Core(), mac: false);
    expect(find.byKey(const ValueKey('newKey.enclave')), findsNothing);
  });
  testWidgets(
    'hardware row exposes only public operations, rename and irreversible deletion',
    (t) async {
      final core = Core()..saved = [key];
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(harness(core, page: true));
      await t.pumpAndSettle();
      expect(find.text('hardware-deploy'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('key.menu.hardware-deploy')));
      await t.pumpAndSettle();
      expect(find.text('Export…'), findsNothing);
      expect(find.textContaining('passphrase'), findsNothing);
      expect(find.textContaining('Finder'), findsNothing);
      expect(find.text('Rename…'), findsOneWidget);
      await t.tap(find.text('Delete…'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('cannot be recovered from a vault backup'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('key.delete.confirm')), findsOneWidget);
    },
  );
  testWidgets(
    'managed SSH chooser selects the native reference by name without exposing its identifier',
    (t) async {
      final core = Core()..saved = [key];
      String? selected;
      await t.pumpWidget(
        ProviderScope(
          overrides: [openWardProvider.overrideWithValue(core)],
          child: MaterialApp(
            theme: materialTheme(OwThemes.grafito),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showSshKeyPicker(context);
                  },
                  child: const Text('choose-key'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('choose-key'));
      await t.pumpAndSettle();
      expect(find.text('hardware-deploy'), findsOneWidget);
      expect(find.textContaining('enclave:'), findsNothing);
      await t.tap(find.byKey(ValueKey('sshKey.pick.${key.path}')));
      await t.pumpAndSettle();
      expect(selected, key.path);
    },
  );
}
