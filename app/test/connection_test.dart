import 'package:flutter_test/flutter_test.dart';
import 'package:openward/src/rust/api/session.dart';
import 'package:openward/terminal/controller.dart';

import 'fakes.dart';

const _connected = ConnectedView(
  host: 'web-1.example.com',
  port: 22,
  kex: 'mlkem768x25519-sha256',
  postQuantum: true,
  cipher: 'chacha20-poly1305',
  hostKeyAlgorithm: 'ssh-ed25519',
  fingerprint: 'SHA256:abc',
  trust: TrustKind.known,
  ca: '',
  hops: 1,
  connectMs: 42,
);

PromptView _prompt(int id) => PromptView(
  id: BigInt.from(id),
  kind: PromptKind.password,
  label: 'web-1',
  host: 'web-1.example.com',
  port: 22,
  user: 'deploy',
  algorithm: '',
  fingerprint: '',
  key: '',
  name: '',
  instructions: '',
  questions: const [],
  retry: false,
  knownTypes: const [],
);

const _lost = FailureView(
  kind: FailureKind.network,
  message: 'no answer for 20 s',
  label: 'web-1',
  host: 'web-1.example.com',
  port: 22,
  user: 'deploy',
  algorithm: '',
  fingerprint: '',
  key: '',
  methods: [],
  reason: '',
  previous: [],
  seconds: 20,
);

HealthView _rtt(int ms) =>
    HealthView(stalled: false, silentMs: BigInt.zero, rttMs: ms);

void main() {
  late FakeOpenWard app;
  late TerminalController c;

  setUp(() {
    app = FakeOpenWard();
    c = TerminalController(app: app, label: 'web-1', hostId: 'h1');
    addTearDown(c.dispose);
  });

  Future<void> send(SessionEvent e) async {
    app.lastEvents.add(e);
    await pumpEventQueue();
  }

  test('from connecting to a running shell, a question on the way', () async {
    var told = 0;
    c.addListener(() => told++);
    c.start();
    expect(app.calls, ['connect h1']);
    expect(c.phase, Phase.connecting);

    await send(event(SessionEventKind.route, route: ['bastion', 'web-1']));
    expect(c.route, ['bastion', 'web-1']);
    await send(
      event(
        SessionEventKind.stage,
        stage: const StageView(
          hop: 1,
          hops: 2,
          label: 'web-1',
          stage: StageKind.authenticating,
        ),
      ),
    );
    expect(c.stage?.stage, StageKind.authenticating);

    await send(event(SessionEventKind.prompt, prompt: _prompt(7)));
    expect(c.prompts.single.id, BigInt.from(7));
    c.answer(
      c.prompts.single,
      const PromptAnswer(kind: AnswerKind.cancel, texts: []),
    );
    expect(c.prompts, isEmpty);
    expect(app.calls.last, 'answer 7');

    await send(event(SessionEventKind.connected, connected: _connected));
    expect(c.phase, Phase.connected);
    expect(c.stage, isNull);
    expect(c.everConnected, isTrue);
    await send(event(SessionEventKind.started));
    expect(c.phase, Phase.running);
    expect(told, greaterThanOrEqualTo(6));
  });

  test(
    'round trips: the last thirty kept, and one well above the usual',
    () async {
      c.start();
      for (var i = 0; i < 40; i++) {
        await send(event(SessionEventKind.health, health: _rtt(20)));
      }
      expect(c.rttHistory, hasLength(ConnectionController.rttKept));
      expect(c.usualRttMs, 20);
      expect(c.rttHigh, isFalse);
      await send(event(SessionEventKind.health, health: _rtt(150)));
      expect(c.rttMs, 150);
      expect(c.rttHigh, isTrue);
    },
  );

  test('stalled, lost and back: the time away is told, from when it '
      'stopped answering', () async {
    c.comebackLine = (at, away) => 'back after ${away.inSeconds} s';
    c.start();
    await send(event(SessionEventKind.connected, connected: _connected));
    await send(event(SessionEventKind.started));

    await send(
      event(
        SessionEventKind.health,
        health: HealthView(stalled: true, silentMs: BigInt.from(5000)),
      ),
    );
    final stalled = c.stalledSince!;
    expect(
      DateTime.now().difference(stalled).inSeconds,
      inInclusiveRange(4, 6),
    );

    await send(
      event(
        SessionEventKind.reconnecting,
        reconnecting: ReconnectingView(
          attempt: 1,
          delayMs: BigInt.from(1000),
          reason: _lost,
        ),
      ),
    );
    expect(c.phase, Phase.reconnecting);
    expect(c.stalledSince, isNull);
    expect(c.reconnectingSince, stalled);
    expect(c.reconnectAt, isNotNull);

    // A new shell after the cut: a line on the screen says so.
    await send(
      event(
        SessionEventKind.stage,
        stage: const StageView(
          hop: 0,
          hops: 1,
          label: 'web-1',
          stage: StageKind.openingShell,
        ),
      ),
    );
    expect(app.sessions.single.notes.single, contains('back after 5 s'));

    await send(event(SessionEventKind.connected, connected: _connected));
    expect(c.phase, Phase.connected);
    expect(c.lastOutage!.inSeconds, inInclusiveRange(4, 6));
    expect(c.reconnectingSince, isNull);
  });

  test('closed: questions go, and giving up stops the session', () async {
    c.start();
    await send(event(SessionEventKind.prompt, prompt: _prompt(1)));
    await send(
      event(SessionEventKind.closed, closed: const ClosedView(failure: _lost)),
    );
    expect(c.phase, Phase.closed);
    expect(c.prompts, isEmpty);
    expect(c.closed?.failure?.message, 'no answer for 20 s');

    c.start();
    expect(c.phase, Phase.connecting, reason: 'never connected');
    c.cancel();
    expect(c.cancelled, isTrue);
    expect(c.phase, Phase.closed);
    expect(app.sessions.single.closed, isTrue);
  });

  test('an error before the session starts is kept to be told', () async {
    c.start();
    app.lastEvents.addError(StateError('a loop of jumps'));
    await pumpEventQueue();
    expect(c.phase, Phase.closed);
    expect(c.error, contains('a loop of jumps'));
    expect(c.errorCause, isA<StateError>());
  });
}
