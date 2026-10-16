import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/app.dart';
import '../src/rust/api/vault.dart';

/// The core, opened in `main` (or by a test) and injected with an override.
final openWardProvider = Provider<OpenWard>(
  (ref) => throw UnimplementedError('override openWardProvider'),
);

/// The `ssh_config` to import from; null for the user's `~/.ssh/config`.
/// Tests point it at a file of their own.
final sshConfigFileProvider = Provider<String?>((ref) => null);

/// Termius's key instead of the keychain's (tests).
final termiusKeyProvider = Provider<List<int>?>((ref) => null);

/// Saved hosts and groups, as the vault has them now.
class Library {
  const Library({required this.hosts, required this.groups});

  final List<HostView> hosts;
  final List<GroupView> groups;

  HostView? host(String id) {
    for (final h in hosts) {
      if (h.id == id) return h;
    }
    return null;
  }

  GroupView? group(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Hosts directly in `groupId` (null: at the top level).
  List<HostView> hostsIn(String? groupId) =>
      hosts.where((h) => h.groupId == groupId).toList();

  List<GroupView> groupsIn(String? parentId) =>
      groups.where((g) => g.parentId == parentId).toList();

  /// Hosts in the group and everything under it.
  int countUnder(String groupId) =>
      hostsIn(groupId).length +
      groupsIn(groupId).fold(0, (n, g) => n + countUnder(g.id));
}

class LibraryNotifier extends Notifier<Library> {
  @override
  Library build() => _load();

  Library _load() {
    final app = ref.read(openWardProvider);
    return Library(hosts: app.hosts(), groups: app.groups());
  }

  /// After anything that changes the vault.
  void refresh() => state = _load();
}

final libraryProvider = NotifierProvider<LibraryNotifier, Library>(
  LibraryNotifier.new,
);

class SearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchProvider = NotifierProvider<SearchNotifier, String>(
  SearchNotifier.new,
);

/// Hosts matching the search, or null when there is no search.
final searchResultsProvider = Provider<List<HostView>?>((ref) {
  final query = ref.watch(searchProvider).trim();
  final library = ref.watch(libraryProvider);
  if (query.isEmpty) return null;
  final ids = ref.read(openWardProvider).search(query: query);
  return [for (final id in ids) ?library.host(id)];
});
