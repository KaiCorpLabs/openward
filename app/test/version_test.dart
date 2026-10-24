import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/version.dart';

void main() {
  test('the version shown matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: *([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });

  /// The core's version is the workspace's (`coreVersion()` reads it from
  /// the build): the same as the app's.
  test("the core's version matches the app's", () {
    final cargo = File('../core/Cargo.toml').readAsStringSync();
    final core = RegExp(
      r'^version = "([^"]+)"',
      multiLine: true,
    ).firstMatch(cargo)!.group(1);
    expect(core, appVersion);
  });
}
