import 'package:flutter_test/flutter_test.dart';
import 'package:openward/sftp/transfers.dart';
import 'package:openward/src/rust/api/sftp.dart';

import 'fakes.dart';

TransferView _job(
  int id,
  TransferState state, {
  int total = 100,
  int done = 0,
}) => TransferView(
  id: BigInt.from(id),
  direction: TransferDirection.upload,
  name: 'file$id',
  source: '/tmp/file$id',
  destDir: '/srv',
  host: 'web-1',
  isDir: false,
  files: 1,
  filesDone: 0,
  skipped: 0,
  total: total,
  done: done,
  rate: 0,
  state: state,
);

void main() {
  testWidgets('asked a few times a second while anything moves, and no '
      'more once nothing does', (tester) async {
    final app = FakeOpenWard()
      ..transferList = [
        _job(1, TransferState.running, total: 200, done: 50),
        _job(2, TransferState.queued, total: 200),
        _job(3, TransferState.failed),
        _job(4, TransferState.done, total: 10, done: 10),
      ];
    final q = TransferQueue(app);
    addTearDown(q.dispose);
    var told = 0;
    q.addListener(() => told++);
    q.poke();
    expect(q.moving, 2);
    expect(q.active, 3, reason: 'the failed one waits for the user');
    expect(q.progress, 50 / 400);

    await tester.pump(const Duration(milliseconds: 260));
    expect(told, 2, reason: 'asked again on its own');

    app.transferList = [_job(1, TransferState.done, total: 200, done: 200)];
    await tester.pump(const Duration(milliseconds: 260));
    expect(q.moving, 0);
    expect(q.progress, isNull);
    final quiet = told;
    await tester.pump(const Duration(seconds: 2));
    expect(told, quiet, reason: 'nothing moves: no more asking');
  });

  testWidgets('each action goes to the core, then asks again', (tester) async {
    final app = FakeOpenWard();
    final q = TransferQueue(app);
    addTearDown(q.dispose);
    final id = BigInt.from(9);
    q
      ..pause(id)
      ..resume(id)
      ..cancel(id)
      ..remove(id)
      ..pauseAll()
      ..clearFinished();
    expect(app.calls, [
      'pause 9',
      'resume 9',
      'cancel 9',
      'remove 9',
      'pause all',
      'clear finished',
    ]);
    expect(q.jobs, isEmpty);
  });
}
