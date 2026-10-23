import 'dart:convert';
import 'dart:io';

/// The JSON in `file`, or null when there is none. Text that does not
/// parse is copied to `<name>.bad` first, so the next save does not lose
/// what was there.
Object? readJsonFile(File file) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    try {
      file.copySync('${file.path}.bad');
    } on FileSystemException {
      // Nothing more to keep it with.
    }
    return null;
  }
}

/// Writes `text` to `file` whole or not at all: to a file beside it, then
/// renamed over it. A cut halfway leaves the previous file as it was.
void writeFileAtomically(File file, String text) {
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.tmp');
  temporary.writeAsStringSync(text, flush: true);
  temporary.renameSync(file.path);
}
