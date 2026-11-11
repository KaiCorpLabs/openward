import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/identities.dart';

typedef KeyInfoReader = Future<KeyView> Function(String, List<String>);

final keyInfoReaderProvider = Provider<KeyInfoReader>((ref) {
  final app = ref.watch(openWardProvider);
  return (path, certificates) =>
      app.keyInfo(path: path, certificateFiles: certificates);
});

/// A value key with a frozen certificate list; editing the form cannot
/// change the identity of an already pending inspection.
class KeyInspectionQuery {
  KeyInspectionQuery(this.path, Iterable<String> certificates)
    : certificates = List.unmodifiable(certificates);
  final String path;
  final List<String> certificates;

  @override
  bool operator ==(Object other) =>
      other is KeyInspectionQuery &&
      path == other.path &&
      listEquals(certificates, other.certificates);
  @override
  int get hashCode => Object.hash(path, Object.hashAll(certificates));
}

final keyInspectionProvider = FutureProvider.autoDispose
    .family<KeyView, KeyInspectionQuery>(
      (ref, query) =>
          ref.watch(keyInfoReaderProvider)(query.path, query.certificates),
    );
