// The «Hosts conocidos» page: the host keys OpenWard trusts and those of
// ~/.ssh/known_hosts, to look up and forget.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../identities/identities.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/known_hosts.dart';
import '../tabs/tabs.dart' show tabsProvider;
import '../ui/confirm.dart';
import '../ui/page.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../src/rust/api/vault.dart' show VaultErrorKind;

/// How many host keys are trusted, for the library's counter. Asked again
/// when a tab opens or closes (keys are trusted as connections come up) and
/// when one is forgotten; off the UI thread, without matching them to hosts.
final knownHostCountProvider = FutureProvider<int>((ref) {
  ref.watch(tabsProvider.select((s) => s.tabs.length));
  return ref.watch(openWardProvider).knownHostCount();
});

enum _Show { all, openWard, file }

class KnownHostsPage extends ConsumerStatefulWidget {
  const KnownHostsPage({super.key});

  @override
  ConsumerState<KnownHostsPage> createState() => _KnownHostsPageState();
}

class _KnownHostsPageState extends ConsumerState<KnownHostsPage> {
  final _query = TextEditingController();
  _Show _show = _Show.all;
  String? _error;

  /// What the core found for the query; null until it answers. It reads
  /// the file and matches hashed names, so off the UI thread, and a moment
  /// after the typing stops.
  List<KnownHostRow>? _rows;
  Timer? _search;

  /// Answers to older queries are dropped.
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final asked = ++_asked;
    final rows = await ref
        .read(openWardProvider)
        .knownHostRows(query: _query.text.trim());
    if (mounted && asked == _asked) setState(() => _rows = rows);
  }

  void _typed(String _) {
    _search?.cancel();
    _search = Timer(const Duration(milliseconds: 150), _load);
  }

  String get _file => tildePath(ref.read(openWardProvider).knownHostsFile());

  /// `confiada el 14 oct`, from a date in ms.
  String _date(AppLocalizations l, int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final months = l.monthsShort.split(',');
    final month = months.length == 12 ? months[d.month - 1] : '${d.month}';
    final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
    return '${d.day} $month$year';
  }

  Future<void> _forget(KnownHostRow r) async {
    final l = context.l10n;
    final c = context.ow.colors;
    final file = r.source == KnownSourceKind.file;
    final name = r.saved.firstOrNull ?? r.hosts ?? r.revealed ?? l.hashedName;
    final sure = await confirmDestructive(
      context,
      title: file ? l.forgetFileKeyTitle(name, _file) : l.forgetKeyTitle(name),
      action: file ? l.removeTheLine : l.forgetAction,
      actionKey: const ValueKey('known.forget.confirm'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(OwSpace.s5),
              decoration: BoxDecoration(
                color: c.sunken,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(context.ow.shape.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (file) l.lineNumber(r.line),
                      r.hosts ?? l.hashedName,
                      if (r.hosts == null && r.revealed != null)
                        l.matchesHost(r.revealed!),
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: c.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${r.algorithm} · ${r.fingerprint}',
                    style: monoStyle(context, size: 12, color: c.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(file ? l.forgetFileKeyBody : l.forgetKeyBody),
            const SizedBox(height: 8),
            Text(
              l.forgetKeyThen,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
    if (!sure) return;
    try {
      await ref.read(openWardProvider).forgetKnownHost(row: r);
      ref.invalidate(knownHostCountProvider);
      await _load();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      setState(
        () => _error = isVaultError(e, VaultErrorKind.fileChanged)
            ? l.knownHostsFileChanged
            : saveErrorText(l, e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final query = _query.text.trim();
    final rows = _rows ?? const <KnownHostRow>[];
    final ours = rows.where((r) => r.source == KnownSourceKind.openWard);
    final theirs = rows.where((r) => r.source == KnownSourceKind.file);
    final shown = switch (_show) {
      _Show.all => rows,
      _Show.openWard => ours.toList(),
      _Show.file => theirs.toList(),
    };
    return ColoredBox(
      color: c.surface,
      child: ListView(
        padding: pagePadding,
        children: [
          OwPageHeader(title: l.knownHosts, intro: l.knownHostsIntro(_file)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OwFilterField(
                key: const ValueKey('known.query'),
                controller: _query,
                hint: l.searchKnownHosts,
                onChanged: _typed,
                style: monoStyle(context, size: 12, color: c.text),
              ),
              SegmentedButton<_Show>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                    value: _Show.all,
                    label: Text(l.allCount(rows.length)),
                  ),
                  ButtonSegment(
                    value: _Show.openWard,
                    label: Text('OpenWard · ${ours.length}'),
                  ),
                  ButtonSegment(
                    value: _Show.file,
                    label: Text('$_file · ${theirs.length}'),
                  ),
                ],
                selected: {_show},
                onSelectionChanged: (s) => setState(() => _show = s.first),
              ),
              if (query.isNotEmpty)
                Text(
                  l.matchCount(rows.length),
                  style: TextStyle(fontSize: OwText.small, color: c.textMuted),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: OwSpace.s5),
              child: Text(_error!, style: TextStyle(color: c.danger)),
            ),
          const SizedBox(height: 12),
          if (shown.isNotEmpty)
            OwDataTable(
              widths: _widths,
              headings: [l.host, l.keyColumn, l.whereItIs, l.savedHost, ''],
              hideBelow: const [null, null, 680, 580, null],
              rows: [for (final r in shown) _row(context, r)],
            )
          else if (query.isNotEmpty)
            OwEmptyState.noMatch(
              filter: query,
              onClear: () {
                setState(_query.clear);
                _typed('');
              },
            )
          else
            OwEmptyState(
              icon: Icons.verified_user_outlined,
              title: l.noKnownHosts,
              body: l.noKnownHostsBody,
            ),
        ],
      ),
    );
  }

  static const _widths = [1.5, 1.7, 1.45, 0.8, 0.5];

  Widget _row(BuildContext context, KnownHostRow r) {
    final c = context.ow.colors;
    final l = context.l10n;
    final ours = r.source == KnownSourceKind.openWard;
    final (marker, tone) = switch (r.marker) {
      KnownMarkerKind.certAuthority => (l.markerCertAuthority, c.accentText),
      KnownMarkerKind.revoked => (l.markerRevoked, c.danger),
      null => (null, c.text),
    };
    return OwTableRow(
      key: ValueKey('known.${ours ? r.id : 'line${r.line}'}'),
      widths: _widths,
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.hosts != null)
              Text(r.hosts!, style: monoStyle(context, size: 12, color: c.text))
            else
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 12, color: c.textMuted),
                  const SizedBox(width: 6),
                  Text(l.hashedName, style: TextStyle(color: c.textMuted)),
                ],
              ),
            if (r.hosts == null && r.revealed != null)
              Text(
                l.matchesHost(r.revealed!),
                style: TextStyle(fontSize: OwText.small, color: c.accentText),
              ),
            if (marker != null)
              Text(
                marker,
                style: TextStyle(fontSize: OwText.small, color: tone),
              ),
            if (r.comment != null)
              Text(
                r.comment!,
                style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.algorithm),
            Text(
              r.fingerprint,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12, color: c.textSubtle),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ours
                      ? Icons.verified_user_outlined
                      : Icons.description_outlined,
                  size: 13,
                  color: c.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    ours ? 'OpenWard' : _file,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              ours
                  ? (r.addedMs == null ? '' : l.trustedOn(_date(l, r.addedMs!)))
                  : l.lineNumber(r.line),
              style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
            ),
          ],
        ),
        Text(
          r.saved.isEmpty ? '—' : r.saved.join(', '),
          style: TextStyle(color: r.saved.isEmpty ? c.textSubtle : c.text),
        ),
        // Narrow, the buttons go on to a second line.
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            IconButton(
              tooltip: l.copyFingerprint,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: r.fingerprint)),
            ),
            IconButton(
              key: ValueKey('known.forget.${ours ? r.id : 'line${r.line}'}'),
              tooltip: ours ? l.forgetAction : l.removeTheLine,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _forget(r),
            ),
          ],
        ),
      ],
    );
  }
}
