import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/fonts.dart';

/// A path as the code writes it: Windows lists `assets\fonts`.
String _slashed(String path) => path.replaceAll(r'\', '/');

void main() {
  test('every bundled font has its license listed, and bundled', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final folders = Directory('assets/fonts')
        .listSync()
        .whereType<Directory>()
        .map((d) => _slashed(d.path))
        .toSet();
    final listed = bundledFonts.values
        .map((p) => _slashed(File(p).parent.path))
        .toSet();
    expect(listed, folders);
    for (final path in bundledFonts.values) {
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(pubspec, contains('- $path'), reason: path);
    }
  });

  test("the core's licenses: libghostty-vt and the crates", () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- $coreLicenses'),
    );
    final core = (jsonDecode(File(coreLicenses).readAsStringSync()) as List)
        .cast<Map<String, Object?>>();
    final packages = {
      for (final e in core) ...(e['packages']! as List).cast<String>(),
    };
    for (final p in [
      'libghostty-vt (Ghostty)',
      'simdutf',
      'Highway',
      'Wuffs',
      'uucode',
      'russh',
      'flutter_rust_bridge',
      'tokio',
    ]) {
      expect(packages, contains(p));
    }
    expect(packages.where((p) => p.startsWith('openward-')), isEmpty);
    expect(core.every((e) => (e['text']! as String).length > 100), isTrue);
  });
}
