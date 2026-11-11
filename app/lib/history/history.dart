// The command history: commands typed in terminals, kept on this device
// only (history.json beside the settings, never in the vault), newest
// first, to find and send again.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection.dart';
import '../core/json_file.dart';
import '../core/settings.dart';
import 'origin.dart';

export 'origin.dart';

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.command,
    required this.where,
    required this.label,
    required this.at,
    this.count = 1,
    this.origin = CommandOrigin.unknown,
    this.binding,
  });

  final String command;

  /// Where it ran: `host:<id>`, `address:<user@host:port>` or `local`.
  final String where;

  /// That place's name when it ran.
  final String label;

  /// Last run, in ms since the epoch.
  final int at;

  /// Times run there.
  final int count;
  final CommandOrigin origin;

  /// The transport endpoint/key seen when it ran, or local. Missing context
  /// stays reviewable; an old entry is never promoted merely by loading it.
  final String? binding;

  Map<String, Object> toJson() => {
    'command': command,
    'where': where,
    'label': label,
    'at': at,
    if (count > 1) 'count': count,
    'origin': origin.name,
    'binding': ?binding,
  };

  static HistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final command = json['command'];
    final where = json['where'];
    final at = json['at'];
    if (command is! String || where is! String || at is! int) return null;
    final label = json['label'];
    final count = json['count'];
    return HistoryEntry(
      command: command,
      where: where,
      label: label is String ? label : '',
      at: at,
      count: count is int && count > 0 ? count : 1,
      origin:
          CommandOrigin.values
              .where((v) => v.name == json['origin'])
              .firstOrNull ??
          CommandOrigin.unknown,
      binding: json['binding'] is String ? json['binding'] as String : null,
    );
  }
}

/// Where a session runs, as the history keys it.
String historyPlace(ConnectionController c) {
  final hostId = c.hostId;
  if (hostId != null) return 'host:$hostId';
  final t = c.target;
  if (t != null) return 'address:${t.label}';
  return 'local';
}

String? historyBinding(ConnectionController c) {
  if (c.hostId == null && c.target == null) return 'local';
  final connected = c.connected;
  if (connected == null || connected.user == null) return null;
  return jsonEncode([
    connected.protocol.name,
    connected.host,
    connected.port,
    connected.fingerprint,
    connected.user,
  ]);
}

String historyLabel(ConnectionController c) {
  final connected = c.connected;
  if (connected == null) return c.label;
  final user = connected.user;
  return '${c.label} · ${user == null ? '' : '$user@'}${connected.host}:${connected.port}';
}

bool historyIsOwnHere(HistoryEntry entry, String where, String? binding) =>
    entry.origin == CommandOrigin.own &&
    entry.where == where &&
    binding != null &&
    entry.binding == binding;

/// `history.json`, beside the settings.
final historyFileProvider = Provider<File>(
  (ref) => File('${ref.watch(settingsFileProvider).parent.path}/history.json'),
);

class HistoryNotifier extends Notifier<List<HistoryEntry>> {
  /// The oldest go beyond this many.
  static const limit = 2000;

  /// Where it is written: read once, as `ref` cannot be read while the
  /// app goes and [flush] writes what was waiting.
  late File _file;

  @override
  List<HistoryEntry> build() {
    _file = ref.read(historyFileProvider);
    ref.onDispose(flush);
    try {
      final json = readJsonFile(_file);
      if (json is Map && json['commands'] is List) {
        return [
          for (final e in json['commands'] as List) ?HistoryEntry.fromJson(e),
        ];
      }
    } catch (_) {
      // No history yet, or not one this version reads: start anew.
    }
    return const [];
  }

  /// `command` ran in `c`: first in the list, once per place.
  void add(
    String command,
    ConnectionController c, {
    DateTime? now,
    CommandOrigin origin = CommandOrigin.unknown,
  }) {
    final where = historyPlace(c);
    final old = state.where((e) => e.command == command && e.where == where);
    final next = HistoryEntry(
      command: command,
      where: where,
      label: historyLabel(c),
      at: (now ?? DateTime.now()).millisecondsSinceEpoch,
      count: (old.firstOrNull?.count ?? 0) + 1,
      origin: origin,
      binding: historyBinding(c),
    );
    state = [
      next,
      ...state.where((e) => !(e.command == command && e.where == where)),
    ].take(limit).toList();
    _save();
  }

  void remove(HistoryEntry e) {
    state = [...state.where((x) => !identical(x, e))];
    _save();
  }

  /// Forgets every command, on disk too, at once.
  void clear() {
    state = const [];
    _save();
    flush();
  }

  /// Commands come in with every Enter: they are written a moment after
  /// the last one, not each time.
  Timer? _pending;

  void _save() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 500), flush);
  }

  /// Writes what is waiting to be written now.
  void flush() {
    if (_pending == null) return;
    _pending!.cancel();
    _pending = null;
    final file = _file;
    try {
      if (state.isEmpty) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      writeFileAtomically(
        file,
        jsonEncode({
          'version': 1,
          'commands': [for (final e in state) e.toJson()],
        }),
      );
    } catch (_) {
      // Kept for this run even if it cannot be saved.
    }
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<HistoryEntry>>(
  HistoryNotifier.new,
);
