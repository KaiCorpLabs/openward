// The command history: commands typed in terminals, kept on this device
// only (history.json beside the settings, never in the vault), newest
// first, to find and send again.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection.dart';
import '../core/settings.dart';

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.command,
    required this.where,
    required this.label,
    required this.at,
    this.count = 1,
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

  Map<String, Object> toJson() => {
    'command': command,
    'where': where,
    'label': label,
    'at': at,
    if (count > 1) 'count': count,
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

/// `history.json`, beside the settings.
final historyFileProvider = Provider<File>(
  (ref) => File('${ref.watch(settingsFileProvider).parent.path}/history.json'),
);

class HistoryNotifier extends Notifier<List<HistoryEntry>> {
  /// The oldest go beyond this many.
  static const limit = 2000;

  @override
  List<HistoryEntry> build() {
    try {
      final json = jsonDecode(ref.read(historyFileProvider).readAsStringSync());
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
  void add(String command, ConnectionController c, {DateTime? now}) {
    final where = historyPlace(c);
    final old = state.where((e) => e.command == command && e.where == where);
    final next = HistoryEntry(
      command: command,
      where: where,
      label: c.label,
      at: (now ?? DateTime.now()).millisecondsSinceEpoch,
      count: (old.firstOrNull?.count ?? 0) + 1,
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

  void clear() {
    state = const [];
    _save();
  }

  void _save() {
    final file = ref.read(historyFileProvider);
    try {
      if (state.isEmpty) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
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
