// Dependency-free bootstrap: no package code runs before locked resolution.
import 'dart:convert';
import 'dart:io';

const runner = '''import 'package:build_tool/build_tool.dart' as build_tool;
void main(List<String> args) {
  build_tool.runMain(args);
}
''';

Future<int> command(List<String> args, Directory directory) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    args,
    workingDirectory: directory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

void writeChanged(File file, String contents) {
  if (!file.existsSync() || file.readAsStringSync() != contents) {
    file.writeAsStringSync(contents);
  }
}

// Compare bytes, rather than directory timestamps. This also invalidates all
// kernels resolved before the runner lockfile became mandatory.
String state(Directory package, String manifest, String lockfile) {
  final files = <String, String>{};
  void visit(Directory dir) {
    final children = dir.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final child in children) {
      final name = child.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (child is Directory) {
        if (!{'.dart_tool', '.git', 'build'}.contains(name)) visit(child);
      } else if (child is File) {
        files[child.path.substring(package.path.length)] = base64.encode(
          child.readAsBytesSync(),
        );
      }
    }
  }

  visit(package);
  return jsonEncode({
    'format': 1,
    'sdk': Platform.version,
    'package': package.path,
    'manifest': manifest,
    'lockfile': lockfile,
    'sources': files,
  });
}

typedef Execute = Future<int> Function(List<String>, Directory);

Future<int> prepare(
  Directory base,
  Directory temp, {
  bool force = false,
  Execute execute = command,
}) async {
  final guard = File.fromUri(temp.uri.resolve('.bootstrap.lock'))
      .openSync(mode: FileMode.append);
  guard.lockSync(FileLock.blockingExclusive);
  try {
    final package = Directory.fromUri(base.uri.resolve('build_tool/'));
    final path = jsonEncode(package.path.replaceAll('\\', '/'));
    final manifest =
        '''name: build_tool_runner
version: 1.0.0
publish_to: none
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  build_tool:
    path: $path
''';
    final lockfile = File.fromUri(base.uri.resolve('build_tool_runner.lock'))
        .readAsStringSync()
        .replaceAll('BUILD_TOOL_PATH', path);
    final spec = File.fromUri(temp.uri.resolve('pubspec.yaml'));
    final lock = File.fromUri(temp.uri.resolve('pubspec.lock'));
    final config = File.fromUri(
      temp.uri.resolve('.dart_tool/package_config.json'),
    );
    final kernel = File.fromUri(temp.uri.resolve('bin/build_tool_runner.dill'));
    final stamp = File.fromUri(temp.uri.resolve('.reviewed_runner_state'));
    final expected = state(package, manifest, lockfile);
    final unchanged =
        spec.existsSync() &&
        spec.readAsStringSync() == manifest &&
        lock.existsSync() &&
        lock.readAsStringSync() == lockfile;
    if (!force &&
        unchanged &&
        config.existsSync() &&
        kernel.existsSync() &&
        stamp.existsSync() &&
        stamp.readAsStringSync() == expected) {
      return 0;
    }

    // A failed resolution or compile must never bless an old kernel.
    if (stamp.existsSync()) stamp.deleteSync();
    if (kernel.existsSync()) kernel.deleteSync();
    writeChanged(spec, manifest);
    writeChanged(lock, lockfile);
    Directory.fromUri(temp.uri.resolve('bin/')).createSync();
    writeChanged(
      File.fromUri(temp.uri.resolve('bin/build_tool_runner.dart')),
      runner,
    );
    var code = await execute([
      'pub',
      'get',
      '--no-precompile',
      '--enforce-lockfile',
    ], temp);
    if (code != 0) return code;
    // The lock is an input, never a solver output to silently accept.
    if (lock.readAsStringSync() != lockfile) {
      stderr.writeln(
        'Cargokit resolution changed the reviewed runner lockfile.',
      );
      return 1;
    }
    code = await execute([
      'compile',
      'kernel',
      'bin/build_tool_runner.dart',
    ], temp);
    if (code != 0) return code;
    stamp.writeAsStringSync(expected);
    return 0;
  } finally {
    guard.unlockSync();
    guard.closeSync();
  }
}

Future<int> runTool(
  Directory base,
  Directory temp,
  List<String> args, {
  Execute execute = command,
}) async {
  var code = await prepare(base, temp, execute: execute);
  if (code != 0) return code;
  // Release the setup lock before executing: Android's linker recursively
  // invokes this wrapper with the same tool directory.
  code = await execute(['bin/build_tool_runner.dill', ...args], temp);
  if (code == 253) {
    code = await prepare(base, temp, force: true, execute: execute);
    if (code == 0) {
      code = await execute(['bin/build_tool_runner.dill', ...args], temp);
    }
  }
  return code;
}

Future<void> main(List<String> args) async {
  try {
    final base = Directory.fromUri(Platform.script.resolve('.'));
    final location = Platform.environment['CARGOKIT_TOOL_TEMP_DIR'];
    if (location == null || location.isEmpty) {
      stderr.writeln('CARGOKIT_TOOL_TEMP_DIR must be set.');
      exitCode = 1;
      return;
    }
    final temp = Directory(location).absolute;
    temp.createSync(recursive: true);
    exitCode = await runTool(base, temp, args);
  } catch (error) {
    stderr.writeln('Cargokit bootstrap failed: $error');
    exitCode = 1;
  }
}
