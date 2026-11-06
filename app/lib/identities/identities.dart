import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/identities.dart';
import '../src/rust/api/vault.dart';
import '../ui/widgets.dart';

/// The identities, with their keys as this machine has them. Loaded again
/// with the library, whose hosts they count.
class IdentitiesNotifier extends Notifier<List<IdentityView>> {
  @override
  List<IdentityView> build() {
    ref.watch(libraryProvider);
    return ref.read(openWardProvider).identities();
  }

  void refresh() => state = ref.read(openWardProvider).identities();
}

final identitiesProvider =
    NotifierProvider<IdentitiesNotifier, List<IdentityView>>(
      IdentitiesNotifier.new,
    );

IdentityView? identityById(List<IdentityView> all, String id) =>
    all.where((i) => i.id == id).firstOrNull;

/// After an identity, or who uses one, changed: hosts show its user.
void identitiesChanged(WidgetRef ref) {
  ref.read(libraryProvider.notifier).refresh();
  ref.read(identitiesProvider.notifier).refresh();
}

/// `/Users/ana/.ssh/deploy` as `~/.ssh/deploy`, and on Windows
/// `C:\Users\ana\.ssh\deploy` (or with `/`) too. The core reads `~/` on
/// every system.
String tildePath(String path, {String? home}) {
  final h =
      home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (h == null || h.isEmpty) return path;
  final windows = h.contains(r'\') || RegExp('^[A-Za-z]:').hasMatch(h);
  String norm(String p) => windows ? p.replaceAll(r'\', '/') : p;
  final base = norm(h).replaceFirst(RegExp(r'/+$'), '');
  final full = norm(path);
  bool same(String a, String b) =>
      windows ? a.toLowerCase() == b.toLowerCase() : a == b;
  if (same(full, base)) return '~';
  if (full.length > base.length &&
      full[base.length] == '/' &&
      same(full.substring(0, base.length), base)) {
    return '~/${full.substring(base.length + 1)}';
  }
  return path;
}

/// The last part of a path: `deploy_ed25519`.
String baseName(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  return parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
}

/// `SHA256:4vQmT…Lk2c`.
String shortFingerprint(String fingerprint) {
  const tag = 'SHA256:';
  final body = fingerprint.startsWith(tag)
      ? fingerprint.substring(tag.length)
      : fingerprint;
  if (body.length <= 12) return fingerprint;
  return '$tag${body.substring(0, 5)}…${body.substring(body.length - 4)}';
}

/// What a key is, under its path: `Ed25519 · SHA256:4vQm…Lk2c · ana@laptop`,
/// or why that is not known.
String keyDetail(AppLocalizations l, KeyView k) => switch (k.state) {
  KeyStateKind.missing => l.keyMissing,
  KeyStateKind.noPublicHalf => l.keyNoPublicHalf,
  KeyStateKind.perHost => l.keyPerHost,
  KeyStateKind.found => [
    ?k.algorithm,
    if (k.fingerprint != null) shortFingerprint(k.fingerprint!),
    ?k.comment,
  ].join(' · '),
};

/// Days left to a certificate that runs out within a week (1 on its last
/// day); null if it has run out, never does, or has longer.
int? certificateDaysLeft(int? untilMs, {DateTime? now}) {
  if (untilMs == null) return null;
  final left = untilMs - (now ?? DateTime.now()).millisecondsSinceEpoch;
  if (left <= 0 || left > const Duration(days: 7).inMilliseconds) return null;
  return (left / Duration.millisecondsPerDay).ceil();
}

/// A key's certificate as a pill: `plain`, or in warm when it has run
/// out or runs out within a week.
Pill certificatePill(
  AppLocalizations l, {
  required bool expired,
  required int? untilMs,
  required String plain,
  PillTone tone = PillTone.accent,
}) {
  final soon = expired ? null : certificateDaysLeft(untilMs);
  return expired
      ? Pill(l.certificateExpired, tone: PillTone.warm)
      : soon != null
      ? Pill(l.certExpiresIn(soon), tone: PillTone.warm)
      : Pill(plain, tone: tone);
}

/// When a certificate runs out, as a date: `30 nov 2026`.
String certDate(AppLocalizations l, CertView c) {
  final ms = c.validBeforeMs;
  if (ms == null) return l.certForever;
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final months = l.monthsShort.split(',');
  final month = months.length == 12 ? months[d.month - 1] : '${d.month}';
  final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return '${d.day} $month$year';
}

String agentText(AppLocalizations l, IdentitySpec s) => switch (s.agent) {
  AgentKind.system => l.agentSystem,
  AgentKind.off => l.agentNone,
  AgentKind.socket => l.agentOtherSocket,
};

/// `deploy · deploy_ed25519 y 1 más`, for pickers.
String identitySummary(AppLocalizations l, IdentityView i) {
  final files = i.spec.identityFiles;
  final keys = switch (files.length) {
    0 => l.usualKeys,
    1 => baseName(files.first),
    _ => l.nameAndMore(baseName(files.first), files.length - 1),
  };
  return [?i.spec.user, keys].join(' · ');
}

/// The keys of `i` this machine does not have.
List<KeyView> missingKeys(IdentityView i) =>
    i.keys.where((k) => k.state == KeyStateKind.missing).toList();

/// `A`, `A y B`, `A, B y 3 más`.
String namesText(AppLocalizations l, List<String> names) =>
    switch (names.length) {
      0 => '',
      1 => names.first,
      2 => l.twoNames(names[0], names[1]),
      _ => l.namesAndMore('${names[0]}, ${names[1]}', names.length - 2),
    };

/// `Grupo Producción y bastion · 6 hosts`, or nobody.
String usedByText(AppLocalizations l, IdentityView i) {
  final names = [for (final g in i.groups) l.groupNamed(g), ...i.hosts];
  if (names.isEmpty) return l.usedByNobody;
  return '${namesText(l, names)} · ${l.hostCountText(i.hostCount)}';
}
