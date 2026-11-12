import 'dart:io';
import 'dart:convert';

import 'package:openward/core/local_documents.dart';
import 'package:openward/core/json_file.dart';

class FileLocalDocuments implements LocalDocuments {
  FileLocalDocuments(this.dir);
  final Directory dir;
  @override
  bool visible = true;
  File file(LocalDocument kind) => File('${dir.path}/${kind.name}.json');
  @override
  Object? read(LocalDocument kind) => visible ? readJsonFile(file(kind)) : null;
  @override
  void write(LocalDocument kind, Object data) {
    if (visible) writeFileAtomically(file(kind), jsonEncode(data));
  }

  @override
  void erase(LocalDocument kind) {
    if (visible && file(kind).existsSync()) file(kind).deleteSync();
  }
}
