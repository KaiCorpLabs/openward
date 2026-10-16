// Runs an integration test with `flutter drive` and saves what it reports:
// the gallery's screenshots, which the test app sends here instead of
// writing them itself.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/gallery_test.dart -d linux

import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final shots = data?['screenshots'];
    if (shots is! Map) return;
    final dir = Directory(
      Platform.environment['OPENWARD_SHOTS'] ?? 'build/shots',
    );
    for (final MapEntry(:key, :value) in shots.entries) {
      final file = File('${dir.path}/$key.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(base64Decode(value as String));
    }
    stdout.writeln('${shots.length} screenshots in ${dir.path}');
  },
);
