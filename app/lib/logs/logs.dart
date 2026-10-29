// Session logs as the app holds them: every session's entry, read again
// when the core says they changed, and how a day, a session and its moment
// are told (docs/plan/registros.md).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/providers.dart';
import '../home/start_page.dart' show durationText;
import '../l10n/app_localizations.dart';
import '../src/rust/api/logs.dart';
import '../src/rust/api/vault.dart' show EnvironmentView;

class LogsNotifier extends Notifier<List<LogEntry>> {
  StreamSubscription<bool>? _changes;

  /// A burst of changes (a session ending prunes others) reads once.
  Timer? _pending;

  @override
  List<LogEntry> build() {
    final app = ref.read(openWardProvider);
    _changes = app.watchLogs().listen((_) {
      _pending ??= Timer(const Duration(milliseconds: 50), () {
        _pending = null;
        refresh();
      });
    });
    ref.onDispose(() {
      _changes?.cancel();
      _pending?.cancel();
    });
    return app.logs();
  }

  /// Reads them again now.
  void refresh() => state = ref.read(openWardProvider).logs();
}

/// Every session, the newest first.
final logsProvider = NotifierProvider<LogsNotifier, List<LogEntry>>(
  LogsNotifier.new,
);

DateTime started(LogEntry e) =>
    DateTime.fromMillisecondsSinceEpoch(e.startedMs.toInt());

DateTime? ended(LogEntry e) => switch (e.endedMs) {
  final ms? => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
  null => null,
};

/// How long it lasted, or has lasted so far.
Duration logLength(LogEntry e, {DateTime? now}) =>
    (ended(e) ?? now ?? DateTime.now()).difference(started(e));

/// The host's mark when it began, as the vault's environment.
EnvironmentView? logEnv(LogEntry e) => switch (e.marking) {
  final m? => EnvironmentView(name: m.name, short: m.short, color: m.color),
  null => null,
};

/// The session's name: the host or address, or «Local».
String logLabel(AppLocalizations l, LogEntry e) =>
    e.place == LogPlace.local && e.label.isEmpty ? l.localShell : e.label;

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Sessions by the day they began, the newest day first; each day keeps
/// the order it was given (newest first).
List<(DateTime, List<LogEntry>)> byDay(Iterable<LogEntry> entries) {
  final days = <DateTime, List<LogEntry>>{};
  for (final e in entries) {
    days.putIfAbsent(_day(started(e)), () => []).add(e);
  }
  final out = days.entries.map((d) => (d.key, d.value)).toList()
    ..sort((a, b) => b.$1.compareTo(a.$1));
  return out;
}

/// «Hoy · miércoles 28», «Ayer · martes 27», «lunes 26»; another month
/// says it, another year too.
String dayTitle(AppLocalizations l, DateTime day, {DateTime? now}) {
  final today = _day(now ?? DateTime.now());
  final lang = l.localeName;
  final name = DateFormat('EEEE d', lang).format(day);
  if (day == today) return '${l.logsToday} · $name';
  if (day == today.subtract(const Duration(days: 1))) {
    return '${l.logsYesterday} · $name';
  }
  if (day.year != today.year) {
    return DateFormat('EEEE d MMM y', lang).format(day).replaceAll('.', '');
  }
  if (day.month != today.month) {
    return DateFormat('EEEE d MMM', lang).format(day).replaceAll('.', '');
  }
  return name;
}

/// «10:05 – 11:02», or «10:42 – ahora» while it goes on.
String timeRange(AppLocalizations l, LogEntry e) {
  final hm = DateFormat.Hm(l.localeName);
  final end = ended(e);
  return '${hm.format(started(e))} – '
      '${end == null ? l.logsNow : hm.format(end)}';
}

/// When it began, in a few words: «hoy, 10:05», «ayer, 18:10», «26 oct,
/// 11:05».
String whenText(AppLocalizations l, LogEntry e, {DateTime? now}) {
  final at = started(e);
  final today = _day(now ?? DateTime.now());
  final day = _day(at);
  final time = DateFormat.Hm(l.localeName).format(at);
  if (day == today) return '${l.logsToday.toLowerCase()}, $time';
  if (day == today.subtract(const Duration(days: 1))) {
    return '${l.logsYesterday.toLowerCase()}, $time';
  }
  final date = DateFormat('d MMM', l.localeName).format(at).replaceAll('.', '');
  return '$date, $time';
}

/// «42 min» or «1 h 45 min»; a session still going says so far.
String lengthText(AppLocalizations l, LogEntry e) =>
    durationText(l, logLength(e));

/// A moment of a recording: «6:52», «1:02:10».
String clockText(double seconds) {
  final s = seconds.isFinite ? seconds.floor().clamp(0, 1 << 31) : 0;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}
