import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/app.dart';
import '../src/rust/api/vault.dart';
import 'connection.dart' show hostsChanged;
import 'match.dart';

/// The core, opened in `main` (or by a test) and injected with an override.
final openWardProvider = Provider<OpenWard>(
  (ref) => throw UnimplementedError('override openWardProvider'),
);

/// The `ssh_config` to import from; null for the user's `~/.ssh/config`.
/// Tests point it at a file of their own.
final sshConfigFileProvider = Provider<String?>((ref) => null);

/// Termius's key instead of the keychain's (tests).
final termiusKeyProvider = Provider<List<int>?>((ref) => null);

/// Saved hosts and groups, as the vault has them now. Looked up by id and
/// by group through indexes made once: with a thousand hosts, a scan per
/// row adds up.
class Library {
  Library({required this.hosts, required this.groups});

  final List<HostView> hosts;
  final List<GroupView> groups;

  late final Map<String, HostView> _hosts = {for (final h in hosts) h.id: h};
  late final Map<String, GroupView> _groups = {for (final g in groups) g.id: g};
  late final Map<String?, List<HostView>> _hostsIn = () {
    final out = <String?, List<HostView>>{};
    for (final h in hosts) {
      (out[h.groupId] ??= []).add(h);
    }
    return out;
  }();
  late final Map<String?, List<GroupView>> _groupsIn = () {
    final out = <String?, List<GroupView>>{};
    for (final g in groups) {
      (out[g.parentId] ??= []).add(g);
    }
    return out;
  }();
  final Map<String, int> _under = {};

  HostView? host(String id) => _hosts[id];

  GroupView? group(String id) => _groups[id];

  /// Hosts directly in `groupId` (null: at the top level).
  List<HostView> hostsIn(String? groupId) =>
      UnmodifiableListView(_hostsIn[groupId] ?? const <HostView>[]);

  List<GroupView> groupsIn(String? parentId) =>
      UnmodifiableListView(_groupsIn[parentId] ?? const <GroupView>[]);

  /// The favorites, in their order.
  List<HostView> get favorites =>
      hosts.where((h) => h.favorite != null).toList()
        ..sort((a, b) => a.favorite!.compareTo(b.favorite!));

  /// Hosts in the group and everything under it.
  int countUnder(String groupId) => _under[groupId] ??=
      (_hostsIn[groupId]?.length ?? 0) +
      (_groupsIn[groupId] ?? const <GroupView>[]).fold(
        0,
        (n, g) => n + countUnder(g.id),
      );
}

class LibraryNotifier extends Notifier<Library> {
  @override
  Library build() {
    // The core changed hosts by itself (a connection told their system).
    hostsChanged.addListener(refresh);
    ref.onDispose(() => hostsChanged.removeListener(refresh));
    return _load();
  }

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
  return HostMatcher(query, library).filter(library.hosts);
});
