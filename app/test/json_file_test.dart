import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/json_file.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('json_file'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a write replaces the file whole, leaving nothing beside it', () {
    final file = File('${dir.path}/sub/settings.json');
    writeFileAtomically(file, '{"a": 1}');
    writeFileAtomically(file, '{"a": 2}');
    expect(readJsonFile(file), {'a': 2});
    expect(dir.listSync(recursive: true).whereType<File>().length, 1);
  });

  test('a file that does not parse is kept aside, not lost', () {
    final file = File('${dir.path}/settings.json')..writeAsStringSync('{"a":');
    expect(readJsonFile(file), isNull);
    expect(File('${file.path}.bad').readAsStringSync(), '{"a":');
    expect(readJsonFile(File('${dir.path}/none.json')), isNull);
  });
}
