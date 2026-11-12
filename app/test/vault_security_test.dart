import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/security/boundary.dart';
import 'package:openward/src/rust/api/security.dart';

import 'fakes.dart';

class Core extends FakeOpenWard {
  bool rejectPassword = false;
  Completer<void>? native;
  Core() {
    security = view(VaultPhase.locked);
  }
  static SecurityView view(VaultPhase phase) => SecurityView(
    phase: phase,
    autoLockSeconds: BigInt.from(900),
    nativeEnabled: true,
    recoveryAvailable: true,
  );
  void phase(VaultPhase phase) {
    security = view(phase);
    securityEvents.add(security);
  }

  @override
  Future<void> unlockVault({required String password}) async {
    if (rejectPassword || password != 'test password') {
      throw StateError('authentication');
    }
    phase(VaultPhase.unlocked);
  }

  @override
  Future<void> unlockNative() async {
    if (native != null) await native!.future;
    throw StateError('cancelled');
  }
}

class PrivateView extends StatefulWidget {
  const PrivateView({super.key});
  @override
  State<PrivateView> createState() => _PrivateViewState();
}

class _PrivateViewState extends State<PrivateView> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('private-content $count'),
    ),
  );
}

Widget harness(Core core) => ProviderScope(
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
    builder: (context, child) => VaultBoundary(child: child!),
    home: const PrivateView(),
  ),
);
void main() {
  testWidgets(
    'locked content has no paint, focus or semantics; unlocking preserves its state',
    (tester) async {
      final core = Core();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(harness(core));
      await tester.pumpAndSettle();
      expect(find.text('private-content 0'), findsNothing);
      expect(find.text('Vault locked'), findsOneWidget);
      expect(find.bySemanticsLabel('private-content 0'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('vault.password')),
        'test password',
      );
      await tester.tap(find.byKey(const ValueKey('vault.unlock')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('private-content 0'));
      await tester.pump();
      expect(find.text('private-content 1'), findsOneWidget);
      await core.lockVault();
      await tester.pumpAndSettle();
      expect(find.text('private-content 1'), findsNothing);
      expect(find.bySemanticsLabel('private-content 1'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('vault.password')),
        'test password',
      );
      await tester.tap(find.byKey(const ValueKey('vault.unlock')));
      await tester.pumpAndSettle();
      expect(find.text('private-content 1'), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets(
    'wrong password and native cancellation retain the fallback without erasing the vault',
    (tester) async {
      final core = Core();
      await tester.pumpWidget(harness(core));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('vault.password')),
        'wrong',
      );
      await tester.tap(find.byKey(const ValueKey('vault.unlock')));
      await tester.pumpAndSettle();
      expect(core.security.phase, VaultPhase.locked);
      expect(find.textContaining('Your vault is preserved.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vault.password')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('Touch ID'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('System protection is unavailable'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vault.unlock')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets('native sleep locks and hides the previous content', (
    tester,
  ) async {
    final core = Core();
    core.phase(VaultPhase.unlocked);
    await tester.pumpWidget(harness(core));
    await tester.pumpAndSettle();
    final codec = const StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'openward/security',
      codec.encodeMethodCall(const MethodCall('suspend')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(core.security.phase, VaultPhase.locked);
    expect(find.text('private-content 0'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await core.securityEvents.close();
  });
}
