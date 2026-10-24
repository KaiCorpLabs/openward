// The «Claves» page: the private keys in ~/.ssh, with their type and
// fingerprint and who uses them; making and bringing in keys, and putting
// one on a server.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/keychain.dart';
import '../ui/announcer.dart';
import '../ui/page.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'key_actions.dart';
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
        padding: pagePadding,
        children: [
          OwPageHeader(
            title: l.keys,
            intro: l.keysIntro,
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  onPressed: () async =>
                      _added(await showNewKeyDialog(context)),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l.newKeyAction),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OwFilterField(
            key: const ValueKey('keys.query'),
            controller: _query,
            hint: l.searchKeys,
            onChanged: (_) => setState(() {}),
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: OwSpace.s5),
              child: Text(_note!, style: TextStyle(color: c.textMuted)),
            ),
          const SizedBox(height: 12),
          if (all.isEmpty)
            OwEmptyState(
              icon: Icons.key_outlined,
              title: l.noKeys,
              body: l.noKeysBody,
            )
          else if (shown.isEmpty)
            OwEmptyState.noMatch(
              filter: _query.text.trim(),
              onClear: () => setState(_query.clear),
            )
          else
            OwDataTable(
              widths: _widths,
              headings: [
                l.keyColumn,
                l.typeAndFingerprint,
                l.protection,
                l.usedBy,
                '',
              ],
              hideBelow: const [null, null, 600, 700, null],
              rows: [for (final k in shown) _row(context, k)],
            ),
        ],
      ),
    );
  }

  static const _widths = [1.5, 1.9, 0.9, 1.2, 0.8];

  Widget _row(BuildContext context, SshKey k) {
    final c = context.ow.colors;
    final l = context.l10n;
    final fresh = k.path == _fresh;
    return OwTableRow(
      key: ValueKey('key.${k.name}'),
      color: fresh ? c.accentSoft.withValues(alpha: 0.5) : null,
      widths: _widths,
      cells: [
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
                style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
              ),
            if (k.certificate)
              Padding(
                padding: const EdgeInsets.only(top: OwSpace.s1),
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
              style: monoStyle(context, size: 12, color: c.textSubtle),
            ),
          ],
        ),
        Row(
          children: [
            // Open and in amber without a passphrase: a closed lock would
            // say the opposite.
            Icon(
              k.encrypted ? Icons.lock_outline : Icons.lock_open,
              size: 14,
              color: k.encrypted ? c.accentText : c.warn,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                k.encrypted ? l.withPassphrase : l.withoutPassphrase,
                style: TextStyle(color: k.encrypted ? c.text : c.warn),
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
        // Narrow, the buttons go on to a second line.
        Wrap(
          alignment: WrapAlignment.end,
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
            PopupMenuButton<VoidCallback>(
              key: ValueKey('key.menu.${k.name}'),
              tooltip: l.moreActions,
              iconSize: 15,
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                for (final (text, action) in [
                  (l.renameEllipsis, () => renameKey(context, k)),
                  (
                    l.keyPassphraseEllipsis,
                    () => changeKeyPassphrase(context, k),
                  ),
                  (l.exportEllipsis, () => exportKey(context, ref, k)),
                  (revealLabel(l), () => revealKey(ref, k)),
                  (l.deleteEllipsis, () => deleteKey(context, ref, k)),
                ])
                  PopupMenuItem(value: action, height: 36, child: Text(text)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
