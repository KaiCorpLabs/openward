// The «Hosts conocidos» page: the host keys OpenWard trusts and those of
// ~/.ssh/known_hosts, to look up and forget.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../identities/identities.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/known_hosts.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

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

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
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
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          file ? l.forgetFileKeyTitle(name, _file) : l.forgetKeyTitle(name),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
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
                      style: TextStyle(fontSize: 12, color: c.textMuted),
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
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('known.forget.confirm'),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(file ? l.removeTheLine : l.forgetAction),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(openWardProvider).forgetKnownHost(row: r);
      setState(() => _error = null);
    } catch (e) {
      setState(
        () => _error = '$e'.contains('file changed')
            ? l.knownHostsFileChanged
            : l.saveFailed('$e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final query = _query.text.trim();
    final rows = ref.read(openWardProvider).knownHostRows(query: query);
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
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        children: [
          Semantics(
            header: true,
            child: Text(l.knownHosts, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              l.knownHostsIntro(_file),
              style: TextStyle(color: c.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                height: 34,
                child: TextField(
                  key: const ValueKey('known.query'),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  style: monoStyle(context, size: 12, color: c.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.searchKnownHosts,
                    hintStyle: TextStyle(fontSize: 13, color: c.textSubtle),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: c.textSubtle,
                    ),
                  ),
                ),
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
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: c.danger)),
            ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 36,
                    color: c.textSubtle,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    query.isEmpty ? l.noKnownHosts : l.noKnownHostMatches,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (query.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      l.noKnownHostsBody,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted),
                    ),
                  ],
                ],
              ),
            )
          else
            _table(context, shown),
        ],
      ),
    );
  }

  static const _widths = [1.5, 1.7, 1.45, 0.8, 0.5];

  Widget _cells(List<Widget> cells) => Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        Expanded(
          flex: (_widths[i] * 100).round(),
          child: Padding(
            padding: EdgeInsets.only(right: i == cells.length - 1 ? 0 : 12),
            child: cells[i],
          ),
        ),
    ],
  );

  Widget _table(BuildContext context, List<KnownHostRow> rows) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: c.textSubtle,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        children: [
          Container(
            color: c.sunken,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _cells([
              for (final h in [
                l.host,
                l.keyColumn,
                l.whereItIs,
                l.savedHost,
                '',
              ])
                Text(h.toUpperCase(), style: head),
            ]),
          ),
          for (final r in rows) _row(context, r),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, KnownHostRow r) {
    final c = context.ow.colors;
    final l = context.l10n;
    final ours = r.source == KnownSourceKind.openWard;
    final (marker, tone) = switch (r.marker) {
      KnownMarkerKind.certAuthority => (l.markerCertAuthority, c.accentText),
      KnownMarkerKind.revoked => (l.markerRevoked, c.danger),
      null => (null, c.text),
    };
    return Container(
      key: ValueKey('known.${ours ? r.id : 'line${r.line}'}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: _cells([
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
                style: TextStyle(fontSize: 11, color: c.accentText),
              ),
            if (marker != null)
              Text(marker, style: TextStyle(fontSize: 11, color: tone)),
            if (r.comment != null)
              Text(
                r.comment!,
                style: TextStyle(fontSize: 11, color: c.textSubtle),
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
              style: monoStyle(context, size: 11, color: c.textSubtle),
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
              style: TextStyle(fontSize: 11, color: c.textSubtle),
            ),
          ],
        ),
        Text(
          r.saved.isEmpty ? '—' : r.saved.join(', '),
          style: TextStyle(color: r.saved.isEmpty ? c.textSubtle : c.text),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
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
      ]),
    );
  }
}
