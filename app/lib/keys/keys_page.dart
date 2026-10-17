// The «Claves» page: the private keys in ~/.ssh, with their type and
// fingerprint and who uses them; making and bringing in keys, and putting
// one on a server.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/keychain.dart';
import '../ui/announcer.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'key_dialogs.dart';
import 'keys.dart';

class KeysPage extends ConsumerStatefulWidget {
  const KeysPage({super.key});

  @override
  ConsumerState<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends ConsumerState<KeysPage> {
  final _query = TextEditingController();

  /// The key just made or brought in, marked for a moment.
  String? _fresh;
  String? _note;

  @override
  void initState() {
    super.initState();
    // Files change outside OpenWard: read them again on each visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(keysProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _added(SshKey? key) {
    if (key == null) return;
    setState(() {
      _fresh = key.path;
      _note = context.l10n.keyAdded(key.path);
    });
    announce(context, _note!);
  }

  void _copy(SshKey key) {
    final l = context.l10n;
    final line = publicLineOf(ref, key);
    if (line == null) {
      setState(() => _note = l.noPublicKey(key.name));
      return;
    }
    Clipboard.setData(ClipboardData(text: line));
    setState(() => _note = l.publicKeyCopied(key.name));
    announce(context, _note!);
  }

  Future<void> _upload(SshKey key) async {
    final line = publicLineOf(ref, key);
    if (line == null) {
      setState(() => _note = context.l10n.noPublicKey(key.name));
      return;
    }
    await showInstallKeyDialog(context, key, line);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final all = ref.watch(keysProvider);
    final q = _query.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : [
            for (final k in all)
              if ([
                k.name,
                k.comment ?? '',
                k.fingerprint ?? '',
                k.algorithm ?? '',
                ...k.usedBy,
              ].any((s) => s.toLowerCase().contains(q)))
                k,
          ];
    return ColoredBox(
      color: c.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(l.keys, style: theme.textTheme.titleLarge),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(
                        l.keysIntro,
                        style: TextStyle(color: c.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                key: const ValueKey('keys.import'),
                onPressed: () async =>
                    _added(await showImportKeyDialog(context)),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: Text(l.importKeyAction),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('keys.new'),
                onPressed: () async => _added(await showNewKeyDialog(context)),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.newKeyAction),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 340,
            height: 34,
            child: TextField(
              key: const ValueKey('keys.query'),
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: l.searchKeys,
                hintStyle: TextStyle(fontSize: 13, color: c.textSubtle),
                prefixIcon: Icon(Icons.search, size: 16, color: c.textSubtle),
              ),
            ),
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_note!, style: TextStyle(color: c.textMuted)),
            ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.key_outlined, size: 36, color: c.textSubtle),
                  const SizedBox(height: 12),
                  Text(
                    all.isEmpty ? l.noKeys : l.noKeyMatches,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (all.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      l.noKeysBody,
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

  static const _widths = [1.5, 1.9, 0.9, 1.2, 0.6];

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

  Widget _table(BuildContext context, List<SshKey> keys) {
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
                l.keyColumn,
                l.typeAndFingerprint,
                l.protection,
                l.usedBy,
                '',
              ])
                Text(h.toUpperCase(), style: head),
            ]),
          ),
          for (final k in keys) _row(context, k),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SshKey k) {
    final c = context.ow.colors;
    final l = context.l10n;
    final fresh = k.path == _fresh;
    return Container(
      key: ValueKey('key.${k.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: fresh ? c.accentSoft.withValues(alpha: 0.5) : null,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: _cells([
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k.path,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12, color: c.text),
            ),
            if (k.comment != null)
              Text(
                k.comment!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.textSubtle),
              ),
            if (k.certificate)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Pill(l.withCertificate, tone: PillTone.accent),
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k.algorithm ?? l.unknownKeyType),
            Text(
              k.fingerprint ?? l.fingerprintNeedsPublic,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 11, color: c.textSubtle),
            ),
          ],
        ),
        Row(
          children: [
            Icon(
              k.encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 13,
              color: k.encrypted ? c.text : c.textSubtle,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                k.encrypted ? l.withPassphrase : l.withoutPassphrase,
                style: TextStyle(color: k.encrypted ? c.text : c.textMuted),
              ),
            ),
          ],
        ),
        Text(
          k.usedBy.isEmpty ? '—' : k.usedBy.join(', '),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          style: TextStyle(color: k.usedBy.isEmpty ? c.textSubtle : c.text),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: ValueKey('key.copy.${k.name}'),
              tooltip: l.copyPublicKey,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => _copy(k),
            ),
            IconButton(
              key: ValueKey('key.upload.${k.name}'),
              tooltip: l.installKeyAction,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: () => _upload(k),
            ),
          ],
        ),
      ]),
    );
  }
}
