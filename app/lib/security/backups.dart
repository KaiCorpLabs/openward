import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../keys/keys.dart';
import '../src/rust/api/backups.dart';
import '../src/rust/api/security.dart';
import 'state.dart';

class VaultBackups extends ConsumerWidget {
  const VaultBackups({super.key});
  Future<void> open(BuildContext context, {BackupFormat? format}) async {
    final path = format == null
        ? (await openFile(
            acceptedTypeGroups: const [
              XTypeGroup(label: 'OpenWard', extensions: ['owvault', 'json']),
            ],
          ))?.path
        : (await getSaveLocation(
            suggestedName: format == BackupFormat.encrypted
                ? 'openward.owvault'
                : 'openward.json',
          ))?.path;
    if (path == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VaultBackupDialog(path: path, format: format),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final unlocked = ref.watch(securityProvider).phase == VaultPhase.unlocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.backupTitle, style: Theme.of(context).textTheme.titleMedium),
        Text(l.backupScope),
        if (!unlocked) Text(l.backupUnlockFirst),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: unlocked
                  ? () => open(context, format: BackupFormat.encrypted)
                  : null,
              child: Text(l.backupExportEncrypted),
            ),
            OutlinedButton(
              onPressed: unlocked
                  ? () => open(context, format: BackupFormat.json)
                  : null,
              child: Text(l.backupExportJson),
            ),
            OutlinedButton(
              onPressed: unlocked ? () => open(context) : null,
              child: Text(l.backupRestore),
            ),
          ],
        ),
      ],
    );
  }
}

/// `format == null` previews/restores; otherwise exports. Contents stay in Rust.
class VaultBackupDialog extends ConsumerStatefulWidget {
  const VaultBackupDialog({required this.path, this.format, super.key});
  final String path;
  final BackupFormat? format;
  @override
  ConsumerState<VaultBackupDialog> createState() => _VaultBackupDialogState();
}

class _VaultBackupDialogState extends ConsumerState<VaultBackupDialog> {
  final credential = TextEditingController();
  bool useKit = false, ack = false, busy = false;
  BackupPreview? preview;
  String? error;
  bool get restoring => widget.format == null;
  bool get plaintext => widget.format == BackupFormat.json;
  @override
  void dispose() {
    credential.clear();
    credential.dispose();
    super.dispose();
  }

  Future<void> act({bool inspect = false}) async {
    setState(() {
      busy = true;
      error = null;
      if (inspect) {
        preview = null;
        ack = false;
      }
    });
    final app = ref.read(openWardProvider);
    try {
      if (inspect) {
        final result = await app.previewVaultBackup(
          path: widget.path,
          credential: credential.text,
          useKit: useKit,
        );
        if (mounted) setState(() => preview = result);
      } else {
        if (restoring) {
          await app.restoreVaultBackup(
            path: widget.path,
            credential: credential.text,
            useKit: useKit,
            expectedDigest: preview!.digest,
            confirmed: ack,
          );
          ref.invalidate(libraryProvider);
          ref.invalidate(keysProvider);
        } else {
          await app.exportVaultBackup(
            path: widget.path,
            format: widget.format!,
            password: credential.text,
            acknowledgePlaintext: ack,
          );
        }
        if (mounted) {
          final message = restoring
              ? context.l10n.backupRestored
              : context.l10n.backupExported;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } on Object {
      if (mounted) setState(() => error = context.l10n.backupFailed);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ready = restoring
        ? preview != null && preview!.destinationEmpty && ack
        : !plaintext || ack && credential.text.isNotEmpty;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          restoring
              ? l.backupRestore
              : plaintext
              ? l.backupExportJson
              : l.backupExportEncrypted,
        ),
        scrollable: true,
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.backupScope),
              const SizedBox(height: 12),
              if (plaintext) Text(l.backupPlaintextWarning),
              if (restoring) ...[
                Text(l.backupRestoreExplain),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.backupUseKit),
                  value: useKit,
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          useKit = v;
                          preview = null;
                          ack = false;
                        }),
                ),
                Text(l.backupCredentialExplain),
              ],
              if (plaintext || restoring)
                TextField(
                  key: const ValueKey('backup.credential'),
                  controller: credential,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: restoring
                        ? l.backupSourceCredential
                        : l.vaultCurrentPassword,
                  ),
                  onChanged: (_) => setState(() {
                    if (restoring) {
                      preview = null;
                      ack = false;
                    }
                  }),
                ),
              if (restoring)
                TextButton(
                  key: const ValueKey('backup.preview'),
                  onPressed: busy ? null : () => act(inspect: true),
                  child: Text(l.backupPreview),
                ),
              if (preview case final p?) ...[
                Text(l.backupSummary(p.items, p.secrets, p.unreadable)),
                if (!p.destinationEmpty)
                  Text(
                    l.backupNeedsEmpty,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (p.format == BackupFormat.json)
                  Text(l.backupPlaintextWarning),
              ],
              if (plaintext || restoring && preview != null)
                CheckboxListTile(
                  key: const ValueKey('backup.confirm'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    restoring ? l.backupConfirmRestore : l.backupAcknowledge,
                  ),
                  value: ack,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => ack = v ?? false),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('backup.submit'),
            onPressed: busy || !ready ? null : () => act(),
            child: Text(restoring ? l.backupRestore : l.backupSave),
          ),
        ],
      ),
    );
  }
}
