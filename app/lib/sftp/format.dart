// Sizes, dates, permissions and times as the browser shows them.

import 'package:intl/intl.dart';

import '../l10n/l10n.dart';

const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// `68 B`, `184 KB`, `2,1 MB`: binary multiples, one decimal under 10.
String formatSize(AppLocalizations l, int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 10 ? 0 : 1;
  final number = NumberFormat.decimalPatternDigits(
    locale: l.localeName,
    decimalDigits: digits,
  ).format(value);
  return '$number ${_units[unit]}';
}

/// `hoy 10:02`, `ayer 18:40`, `12 oct`, or with the year if it is not this
/// one.
String formatDate(AppLocalizations l, int? secondsSinceEpoch, {DateTime? now}) {
  if (secondsSinceEpoch == null) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000);
  final today = now ?? DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(day).inDays;
  final time = DateFormat.Hm(l.localeName).format(t);
  if (days == 0) return l.todayAt(time);
  if (days == 1) return l.yesterdayAt(time);
  final pattern = t.year == today.year ? 'd MMM' : 'd MMM y';
  return DateFormat(pattern, l.localeName).format(t).replaceAll('.', '');
}

/// `rwxr-xr-x`.
String formatMode(int mode) {
  const letters = 'rwx';
  final b = StringBuffer();
  for (var i = 8; i >= 0; i--) {
    final executable = mode & (1 << i) != 0;
    if (i == 6 && mode & 0x800 != 0 || i == 3 && mode & 0x400 != 0) {
      b.write(executable ? 's' : 'S');
    } else if (i == 0 && mode & 0x200 != 0) {
      b.write(executable ? 't' : 'T');
    } else {
      b.write(executable ? letters[(8 - i) % 3] : '-');
    }
  }
  return b.toString();
}

/// `754`.
String octal(int mode) => (mode & 0xfff).toRadixString(8).padLeft(3, '0');

/// `19 s`, `1 min 5 s`, `2 h 3 min`.
String formatDuration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s s';
  if (s < 3600) {
    final rest = s % 60;
    return rest == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min $rest s';
  }
  return '${s ~/ 3600} h ${(s % 3600) ~/ 60} min';
}
