// What was used lately on this device: the connections opened (when, and
// until when) and how often each palette action runs. In recent.json
// protected local storage owned by Rust, never synced.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection.dart';
import '../core/local_documents.dart';
import '../core/settings.dart';
import '../history/history.dart' show historyPlace;
import '../src/rust/api/session.dart' show PersistenceKind;

@immutable
class RecentConnection {
  const RecentConnection({
    required this.where,
    required this.label,
    required this.at,
    this.ended,
    this.tmux = false,
  });

  /// Where it went: `host:<id>` or `address:<user@host:port>`.
  final String where;

  /// The host's name, or the address, when it connected.
  final String label;

  /// When it connected, in ms since the epoch.
  final int at;

  /// When it closed; null while open (or if the app quit first).
  final int? ended;

  /// The shell ran in a persistent tmux session.
  final bool tmux;

  /// How long it lasted, once closed.
  Duration? get length =>
      ended == null ? null : Duration(milliseconds: ended! - at);

  /// The saved host's id, if it is one.
  String? get hostId => where.startsWith('host:') ? where.substring(5) : null;

  /// The address typed by hand, if it was not a saved host.
  String? get address =>
      where.startsWith('address:') ? where.substring(8) : null;

  RecentConnection endedAt(int ms, {bool tmux = false}) => RecentConnection(
    where: where,
    label: label,
    at: at,
    ended: ms,
    tmux: tmux,
  );

  Map<String, Object> toJson() => {
    'where': where,
    'label': label,
    'at': at,
    'ended': ?ended,
    if (tmux) 'tmux': true,
  };

  static RecentConnection? fromJson(Object? json) {
    if (json is! Map) return null;
    final where = json['where'];
    final at = json['at'];
    if (where is! String || at is! int) return null;
    final label = json['label'];
    final ended = json['ended'];
    return RecentConnection(
      where: where,
      label: label is String ? label : '',
      at: at,
      ended: ended is int ? ended : null,
      tmux: json['tmux'] == true,
    );
  }
}

@immutable
class Recent {
  const Recent({this.connections = const [], this.actions = const {}});

  /// Newest first, one per place.
  final List<RecentConnection> connections;

  /// Times each palette action ran, by its id.
  final Map<String, int> actions;
}

/// `recent.json`, beside the settings.
final recentFileProvider = Provider<File>(
  (ref) => File('${ref.watch(settingsFileProvider).parent.path}/recent.json'),
);

class RecentNotifier extends Notifier<Recent> {
  /// The oldest go beyond this many.
  static const limit = 50;

  late LocalDocuments _store;
  @override
  Recent build() {
    _store = ref.watch(localDocumentsProvider);
    try {
      final json = _store.read(LocalDocument.recent);
      if (json is Map) {
        final list = json['connections'];
        final actions = json['actions'];
        return Recent(
          connections: list is List
              ? [for (final e in list) ?RecentConnection.fromJson(e)]
              : const [],
          actions: actions is Map
              ? {
                  for (final MapEntry(:key, :value) in actions.entries)
                    if (key is String && value is int && value > 0) key: value,
                }
              : const {},
        );
      }
    } catch (_) {
      // Nothing yet, or not something this version reads: start anew.
    }
    return const Recent();
  }

  /// `c` connected: first in the list, once per place. Local shells are
  /// not kept.
  void connected(ConnectionController c, {DateTime? now}) {
    if (c.isLocal) return;
    add(historyPlace(c), c.label, now: now);
  }

  /// A connection to `where` (as [historyPlace] says) came up.
  void add(String where, String label, {DateTime? now}) {
    if (!_store.visible || !ref.read(settingsProvider).recentConnections) {
      return;
    }
    final entry = RecentConnection(
      where: where,
      label: label,
      at: (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
    state = Recent(
      connections: [
        entry,
        ...state.connections.where((e) => e.where != where),
      ].take(limit).toList(),
      actions: state.actions,
    );
    _save();
  }

  /// `c` closed: its entry gets when.
  void ended(ConnectionController c, {DateTime? now}) {
    if (c.isLocal) return;
    final p = c.persistent;
    end(
      historyPlace(c),
      now: now,
      tmux: p != null && p.state != PersistenceKind.noTmux,
    );
  }

  /// The open connection to `where` closed.
  void end(String where, {DateTime? now, bool tmux = false}) {
    if (!_store.visible) return;
    final at = state.connections.indexWhere(
      (e) => e.where == where && e.ended == null,
    );
    if (at < 0) return;
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    state = Recent(
      connections: [...state.connections]
        ..[at] = state.connections[at].endedAt(ms, tmux: tmux),
      actions: state.actions,
    );
    _save();
  }

  /// A palette action ran.
  void used(String action) {
    if (!_store.visible) return;
    state = Recent(
      connections: state.connections,
      actions: {...state.actions, action: (state.actions[action] ?? 0) + 1},
    );
    _save();
  }

  /// Forgets the connections (the actions' counts stay).
  void clear() {
    state = Recent(actions: state.actions);
    _save();
  }

  void _save() {
    if (!_store.visible) return;
    try {
      if (state.connections.isEmpty && state.actions.isEmpty) {
        _store.erase(LocalDocument.recent);
        return;
      }
      _store.write(LocalDocument.recent, {
        'version': 1,
        'connections': [for (final e in state.connections) e.toJson()],
        if (state.actions.isNotEmpty) 'actions': state.actions,
      });
    } catch (_) {
      // Kept for this run even if it cannot be saved.
    }
  }
}

final recentProvider = NotifierProvider<RecentNotifier, Recent>(
  RecentNotifier.new,
);
