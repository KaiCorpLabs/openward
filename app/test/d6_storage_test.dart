import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/local_documents.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/history/history.dart';
import 'package:openward/home/recent.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/src/rust/api/security.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/tabs/prompt_card.dart';
import 'package:openward/terminal/controller.dart';

import 'package:openward/ui/themes.dart';

import 'fakes.dart';

class Core extends FakeOpenWard {
  final documents = <LocalDocument, String>{};
  final remembered = <PromptAnswer>[];
  bool failWrites = false;
  int writes = 0;
  void phase(VaultPhase phase) {
    security = SecurityView(
      phase: phase,
      autoLockSeconds: BigInt.from(900),
      nativeEnabled: false,
      recoveryAvailable: true,
    );
    securityEvents.add(security);
  }

  @override
  String? readLocalDocument({required LocalDocument kind}) => documents[kind];
  @override
  void writeLocalDocument({required LocalDocument kind, required String json}) {
    writes++;
    if (failWrites || security.phase == VaultPhase.locked) {
      throw StateError('protected storage unavailable');
    }
    documents[kind] = json;
  }

  @override
  void eraseLocalDocument({required LocalDocument kind}) =>
      documents.remove(kind);
  @override
  bool answerRemember({
    required BigInt promptId,
    required PromptAnswer answer,
  }) {
    remembered.add(answer);
    return true;
  }
}

PromptView prompt(PromptKind kind, {List<QuestionView> questions = const []}) =>
    PromptView(
      id: BigInt.one,
      kind: kind,
      label: 'fixture',
      host: 'fixture.example',
      port: 22,
      user: 'demo',
      algorithm: '',
      fingerprint: '',
      key: '',
      name: '',
      instructions: '',
      questions: questions,
      retry: false,
      knownTypes: const [],
    );
Widget harness(ConnectionController c, PromptView p) => MaterialApp(
  theme: ThemeData(extensions: [OwThemes.grafito]),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(
    body: Center(
      child: PromptCard(key: ValueKey(p.kind), controller: c, prompt: p),
    ),
  ),
);
void main() {
  test('local projections disappear on lock and never fall back to plaintext files', () async {
    final dir = Directory.systemTemp.createTempSync('d6-ui-');
    final core = Core()..phase(VaultPhase.unlocked);
    core.documents[LocalDocument.history] = '{"commands":[{"command":"private command","where":"local","label":"fixture","at":1}]}';
    core.documents[LocalDocument.recent] =
        '{"connections":[{"where":"host:1","label":"private host","at":1}]}';
    final c = ProviderContainer(
      overrides: [
        openWardProvider.overrideWithValue(core),
        settingsFileProvider.overrideWithValue(
          File('${dir.path}/settings.json'),
        ),
      ],
    );
    final h = c.listen(historyProvider, (_, _) {});
    final r = c.listen(recentProvider, (_, _) {});
    expect(c.read(historyProvider).single.command, 'private command');
    expect(c.read(recentProvider).connections.single.label, 'private host');
    core.phase(VaultPhase.locked);
    await pumpEventQueue();
    expect(c.read(historyProvider), isEmpty);
    expect(c.read(recentProvider).connections, isEmpty);
    final before = core.writes;
    c.read(recentProvider.notifier).add('host:2', 'blocked');
    expect(core.writes, before);
    core.phase(VaultPhase.unlocked);
    await pumpEventQueue();
    expect(c.read(historyProvider).single.command, 'private command');
    core.failWrites = true;
    c.read(recentProvider.notifier).add('host:3', 'unsaved');
    expect(File('${dir.path}/recent.json').existsSync(), isFalse);
    expect(core.documents[LocalDocument.recent], isNot(contains('unsaved')));
    h.close();
    r.close();
    c.dispose();
    await core.securityEvents.close();
    dir.deleteSync(recursive: true);
  });
  testWidgets(
    'password saving is opt in; PIN, OTP, proxy and legacy prompts do not offer it',
    (tester) async {
      final core = Core()..phase(VaultPhase.unlocked);
      final controller = TerminalController(app: core, label: 'fixture');
      var p = prompt(PromptKind.password);
      await tester.pumpWidget(harness(controller, p));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('prompt.remember')),
            )
            .value,
        isFalse,
      );
      await tester.enterText(find.byType(TextField), 'private-password');
      await tester.tap(find.byType(FilledButton));
      expect(core.remembered, isEmpty);
      await tester.tap(find.byKey(const ValueKey('prompt.remember')));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      expect(core.remembered.single.texts, ['private-password']);
      for (final kind in [
        PromptKind.securityKeyPin,
        PromptKind.proxyLogin,
        PromptKind.keyboardInteractive,
      ]) {
        p = prompt(
          kind,
          questions: const [QuestionView(text: 'OTP:', echo: false)],
        );
        await tester.pumpWidget(harness(controller, p));
        expect(find.byKey(const ValueKey('prompt.remember')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        harness(
          controller,
          prompt(
            PromptKind.keyboardInteractive,
            questions: const [QuestionView(text: 'Password:', echo: false)],
          ),
        ),
      );
      expect(find.byKey(const ValueKey('prompt.remember')), findsOneWidget);
      core.phase(VaultPhase.legacy);
      await tester.pumpWidget(harness(controller, prompt(PromptKind.password)));
      expect(find.byKey(const ValueKey('prompt.remember')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await core.securityEvents.close();
    },
  );
}
