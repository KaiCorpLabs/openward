// One chooser for files, vault keys and device-bound hardware references.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identities/identities.dart' show tildePath;
import '../l10n/l10n.dart';
import 'keys.dart';

Future<String?> showSshKeyPicker(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _Picker());

class _Picker extends ConsumerWidget {
  const _Picker();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final keys = ref.watch(keysProvider);
    return AlertDialog(
      title: Text(l.chooseSshKey),
      content: SizedBox(
        width: 540,
        height: 320,
        child: keys.when(
          data: (keys) => ListView(
            children: [
              for (final key in keys)
                ListTile(
                  key: ValueKey('sshKey.pick.${key.path}'),
                  isThreeLine: true,
                  leading: Icon(
                    key.path.startsWith('enclave:')
                        ? Icons.fingerprint
                        : Icons.key,
                  ),
                  title: Text(key.name),
                  subtitle: Text(
                    [
                      if (key.algorithm != null) key.algorithm!,
                      if (key.fingerprint != null) key.fingerprint!,
                      if (key.path.startsWith('enclave:'))
                        l.enclaveStored
                      else if (key.path.startsWith('vault:'))
                        l.vaultStoredKey
                      else
                        key.path,
                    ].join('\n'),
                  ),
                  onTap: () => Navigator.pop(context, key.path),
                ),
              if (keys.isEmpty) Text(l.noKeysYet),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text(l.keyFailed)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        OutlinedButton(
          key: const ValueKey('sshKey.chooseFile'),
          onPressed: () async {
            final home =
                Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'];
            final file = await openFile(
              initialDirectory: home == null
                  ? null
                  : '$home${Platform.pathSeparator}.ssh',
            );
            if (file != null && context.mounted) {
              Navigator.pop(context, tildePath(file.path));
            }
          },
          child: Text(l.chooseSshKeyFile),
        ),
      ],
    );
  }
}

/// References remain internal; the key's name is what the user selected.
class SshKeyLabel extends ConsumerWidget {
  const SshKeyLabel({super.key, required this.path, this.style});
  final String path;
  final TextStyle? style;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var label = path;
    if (path.startsWith('enclave:') || path.startsWith('vault:')) {
      label = path.startsWith('enclave:')
          ? context.l10n.enclaveStored
          : context.l10n.vaultStoredKey;
      final state = ref.watch(keysProvider);
      if (state case AsyncData(:final value)) {
        for (final key in value) {
          if (key.path == path) {
            label = key.name;
            break;
          }
        }
      }
    }
    return Text(label, style: style, overflow: TextOverflow.ellipsis);
  }
}
