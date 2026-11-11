// Run with the SDK directly; no third-party test packages are needed.
import 'dart:io';

import 'bootstrap.dart' as bootstrap;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class Fixture {
  Fixture() {
    root = Directory.systemTemp.createTempSync('cargokit locked runner ');
    base = Directory.fromUri(root.uri.resolve('original tool/'))..createSync();
    temp = Directory.fromUri(root.uri.resolve('runner cache/'))..createSync();
    source = File.fromUri(base.uri.resolve('build_tool/lib/tool.dart'))
      ..parent.createSync(recursive: true);
    source.writeAsStringSync('original');
    File.fromUri(base.uri.resolve('build_tool/pubspec.yaml'))
        .writeAsStringSync('name: build_tool\nversion: 1.0.0\n');
    File.fromUri(base.uri.resolve('build_tool_runner.lock'))
        .writeAsStringSync('reviewed BUILD_TOOL_PATH');
  }
  late Directory root, base, temp;
  late File source;
  final calls = <List<String>>[];
  final failures = <String, List<int>>{};
  bool rewriteLock = false;
  File get stamp => File.fromUri(temp.uri.resolve('.reviewed_runner_state'));
  File get kernel =>
      File.fromUri(temp.uri.resolve('bin/build_tool_runner.dill'));
  File get lock => File.fromUri(temp.uri.resolve('pubspec.lock'));

  Future<int> execute(List<String> args, Directory dir) async {
    calls.add(args);
    final kind = args.first;
    final queue = failures[kind];
    final code = queue != null && queue.isNotEmpty ? queue.removeAt(0) : 0;
    if (kind == 'pub') {
      check(
        args.contains('--enforce-lockfile'),
        'every resolution must enforce the lock',
      );
      check(
        lock.readAsStringSync().startsWith('reviewed '),
        'reviewed lock must precede pub',
      );
      if (rewriteLock) lock.writeAsStringSync('unreviewed');
      if (code == 0) {
        File.fromUri(temp.uri.resolve('.dart_tool/package_config.json'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('{}');
      }
    } else if (kind == 'compile' && code == 0) {
      kernel.writeAsStringSync('compiled');
    }
    return code;
  }

  Future<int> run([List<String> args = const ['argument with spaces']]) =>
      bootstrap.runTool(base, temp, args, execute: execute);
  void dispose() => root.deleteSync(recursive: true);
}

Future<void> test(String name, Future<void> Function(Fixture) body) async {
  final f = Fixture();
  try {
    await body(f);
    stdout.writeln('PASS $name');
  } finally {
    f.dispose();
  }
}

Future<void> main() async {
  await test('cold cache and original package path', (f) async {
    check(await f.run() == 0, 'cold bootstrap failed');
    check(f.calls.length == 3, 'must resolve, compile, then execute');
    check(
      f.lock.readAsStringSync().contains('original tool/build_tool'),
      'path dependency moved',
    );
    check(f.calls.last.last == 'argument with spaces', 'arguments changed');
    check(f.stamp.existsSync(), 'successful compile must record state');
  });
  await test('warm cache runs without pub or compile', (f) async {
    await f.run();
    f.calls.clear();
    check(
      await f.run() == 0 && f.calls.length == 1,
      'warm offline cache rebuilt',
    );
  });
  await test('old unreviewed cache is rejected', (f) async {
    f.kernel
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('old');
    File.fromUri(f.temp.uri.resolve('.package_hash'))
        .writeAsStringSync('legacy');
    await f.run();
    check(f.calls.first.first == 'pub', 'legacy cache skipped enforcement');
  });
  await test('source bytes invalidate cache even with same timestamps', (
    f,
  ) async {
    await f.run();
    f.calls.clear();
    final time = f.source.lastModifiedSync();
    f.source.writeAsStringSync('changed!');
    f.source.setLastModifiedSync(time);
    await f.run();
    check(f.calls.first.first == 'pub', 'same-size source change not detected');
  });
  await test('tampered runner lock and missing kernel force resolution', (
    f,
  ) async {
    await f.run();
    f.calls.clear();
    f.lock.writeAsStringSync('tampered');
    await f.run();
    check(f.calls.first.first == 'pub', 'tampered lock reused');
    f.calls.clear();
    f.kernel.deleteSync();
    await f.run();
    check(
      f.calls.first.first == 'pub',
      'missing kernel bypassed locked resolution',
    );
  });
  for (final stage in ['pub', 'compile']) {
    await test('$stage failure never executes or marks a kernel', (f) async {
      f.failures[stage] = [42];
      check(await f.run() == 42, 'failure exit status lost');
      check(!f.stamp.existsSync(), 'failed build blessed cache');
      check(
        !f.calls.any((a) => a.first.endsWith('.dill')),
        'failed build executed',
      );
    });
    await test('snapshot retry $stage failure stops', (f) async {
      await f.run();
      f.calls.clear();
      f.failures['bin/build_tool_runner.dill'] = [253];
      f.failures[stage] = [42];
      check(await f.run() == 42, 'retry error lost');
      check(
        f.calls.where((a) => a.first.endsWith('.dill')).length == 1,
        'retry ran old kernel',
      );
      check(!f.stamp.existsSync(), 'retry failure blessed cache');
    });
  }
  await test('253 recovery enforces lock and retries only once', (f) async {
    f.failures['bin/build_tool_runner.dill'] = [253, 253];
    check(await f.run() == 253, 'second snapshot exit status lost');
    check(
      f.calls.where((a) => a.first == 'pub').length == 2,
      'retry skipped enforcement',
    );
    check(
      f.calls.where((a) => a.first.endsWith('.dill')).length == 2,
      'unbounded retry',
    );
  });
  await test('solver lock rewrite is never accepted', (f) async {
    f.rewriteLock = true;
    check(
      await f.run() != 0 && !f.stamp.existsSync(),
      'solver output accepted',
    );
    check(
      !f.calls.any((a) => a.first.endsWith('.dill')),
      'rewritten resolution executed',
    );
  });
}
