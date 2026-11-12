// Rust owns local persistence. A failed/locked core never falls back to JSON
// writes from Dart. Only the UI projection exists here while visible.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/state.dart';
import '../src/rust/api/app.dart';
import '../src/rust/api/local_data.dart';
import 'providers.dart';
export '../src/rust/api/local_data.dart' show LocalDocument;

abstract interface class LocalDocuments {
  bool get visible;
  Object? read(LocalDocument kind);
  void write(LocalDocument kind, Object data);
  void erase(LocalDocument kind);
}

class NativeLocalDocuments implements LocalDocuments {
  NativeLocalDocuments(this.app, this.visible);
  final OpenWard app;
  @override
  final bool visible;
  @override
  Object? read(LocalDocument kind) {
    if (!visible) return null;
    final text = app.readLocalDocument(kind: kind);
    return text == null ? null : jsonDecode(text);
  }

  @override
  void write(LocalDocument kind, Object data) {
    if (!visible) return;
    app.writeLocalDocument(kind: kind, json: jsonEncode(data));
  }

  @override
  void erase(LocalDocument kind) {
    if (!visible) return;
    app.eraseLocalDocument(kind: kind);
  }
}

final localDocumentsProvider = Provider<LocalDocuments>(
  (ref) => NativeLocalDocuments(
    ref.read(openWardProvider),
    vaultVisible(ref.watch(securityProvider)),
  ),
);
