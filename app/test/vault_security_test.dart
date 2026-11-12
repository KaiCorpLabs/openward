import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/security/boundary.dart';
import 'package:openward/security/settings.dart';
import 'package:openward/security/onboarding.dart';
import 'package:openward/src/rust/api/security.dart';

import 'fakes.dart';

class Core extends FakeOpenWard {
  bool rejectPassword = false;
  bool rejectDevice = false;
  int deferred = 0;
  @override
  Future<void> deferVaultSetup({required bool linuxAck}) async {
    deferred++;
    if (rejectDevice) throw StateError('keyring unavailable');
    needsPassword = true;
    onboardingRequired = false;
    phase(VaultPhase.unlocked);
  }

  @override
  Future<void> unlockDeviceVault() async {
    if (rejectDevice) throw StateError('keyring unavailable');
    phase(VaultPhase.unlocked);
  }

  Completer<void>? native;
  Completer<void>? passwordWait;
  Completer<String>? preparation;
  int cancelledSetup = 0;
  @override
  Future<void> cancelVaultSetup() async {
    cancelledSetup++;
  }

  @override
  Future<int> passwordScore({required String password}) async => 4;
  @override
  Future<String> prepareVault({required String password}) =>
      preparation!.future;
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
    if (passwordWait != null) await passwordWait!.future;
  }

  @override
  Future<void> unlockNative() async {
    if (native != null) await native!.future;
    throw StateError('cancelled');
  }
}

class LinuxCore extends Core {
  @override
  NativeProtection nativeProtection() => NativeProtection.sessionKeyring;
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
    'Linux later requires explicit session protection acknowledgement',
    (tester) async {
      final core = LinuxCore()..onboardingRequired = true;
      core.phase(VaultPhase.legacy);
      await tester.pumpWidget(harness(core));
      await tester.pumpAndSettle();
      final later = find.byKey(const ValueKey('vault.onboarding.later'));
      expect(tester.widget<TextButton>(later).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(later).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets(
    'reminder and onboarding fit a narrow window at large text scale',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = Core()..onboardingRequired = true;
      core.phase(VaultPhase.legacy);
      await tester.pumpWidget(harness(core));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
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
            locale: const Locale('en'),
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(child: VaultReminder()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Password and recovery kit pending'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets(
    'mandatory onboarding hides legacy content and keyring failure stays gated',
    (tester) async {
      final core = Core()
        ..onboardingRequired = true
        ..rejectDevice = true;
      core.phase(VaultPhase.legacy);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(harness(core));
      await tester.pumpAndSettle();
      expect(find.text('Protect your vault'), findsOneWidget);
      expect(find.text('private-content 0'), findsNothing);
      expect(find.bySemanticsLabel('private-content 0'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('vault.onboarding.later')),
      );
      await tester.tap(find.byKey(const ValueKey('vault.onboarding.later')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Device key unavailable.'), findsOneWidget);
      expect(find.text('private-content 0'), findsNothing);
      core.rejectDevice = false;
      await tester.tap(find.byKey(const ValueKey('vault.onboarding.later')));
      await tester.pumpAndSettle();
      expect(core.needsPassword, isTrue);
      expect(core.deferred, 2);
      expect(find.text('private-content 0'), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets('device-only locked vault offers its actual unlock method', (
    tester,
  ) async {
    final core = Core()
      ..needsPassword = true
      ..rejectDevice = true;
    await tester.pumpWidget(harness(core));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vault.password')), findsNothing);
    await tester.tap(find.text('Unlock with this OS account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Device key unavailable.'), findsOneWidget);
    expect(find.text('private-content 0'), findsNothing);
    core.rejectDevice = false;
    await tester.tap(find.text('Unlock with this OS account'));
    await tester.pumpAndSettle();
    expect(find.text('private-content 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await core.securityEvents.close();
  });
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
    'password completion after unlock screen disposal touches no old controller',
    (tester) async {
      final core = Core();
      core.passwordWait = Completer<void>();
      await tester.pumpWidget(harness(core));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('vault.password')),
        'test password',
      );
      await tester.tap(find.byKey(const ValueKey('vault.unlock')));
      await tester.pumpAndSettle();
      expect(find.text('private-content 0'), findsOneWidget);
      core.passwordWait!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await core.securityEvents.close();
    },
  );
  testWidgets(
    'closed setup clears preparation even when the worker finishes later',
    (tester) async {
      final core = Core();
      core.preparation = Completer<String>();
      await tester.pumpWidget(
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
            locale: const Locale('en'),
            home: const Scaffold(body: VaultSetup()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'strong public test password');
      await tester.enterText(fields.at(1), 'strong public test password');
      await tester.tap(find.widgetWithText(FilledButton, 'Encrypt this vault'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      core.preparation!.complete('public test kit');
      await tester.pumpAndSettle();
      expect(core.cancelledSetup, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
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
  testWidgets('manual lock shortcut hides an active view', (tester) async {
    final core = Core();
    core.phase(VaultPhase.unlocked);
    await tester.pumpWidget(harness(core));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(core.security.phase, VaultPhase.locked);
    expect(find.text('private-content 0'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await core.securityEvents.close();
  });
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
