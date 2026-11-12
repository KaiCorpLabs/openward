import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/credentials.dart';
import '../src/rust/api/security.dart';
import 'state.dart';

final savedCredentialsProvider = FutureProvider<List<SavedCredential>>((
  ref,
) async {
  if (ref.watch(securityProvider).phase != VaultPhase.unlocked) return [];
  ref.watch(libraryProvider);
  return ref.read(openWardProvider).savedCredentials();
});

class StoredCredentials extends ConsumerWidget {
  const StoredCredentials({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (ref.watch(securityProvider).phase != VaultPhase.unlocked) {
      return const SizedBox.shrink();
    }
    return ref
        .watch(savedCredentialsProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Text(l.errStorage),
          data: (entries) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.vaultSavedCredentials,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(l.vaultCredentialExplain),
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.label),
                  subtitle: Text(
                    entry.kind == CredentialKind.password
                        ? l.vaultCredentialPassword
                        : l.vaultCredentialPassphrase,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l.delete,
                    onPressed: () async {
                      try {
                        await ref
                            .read(openWardProvider)
                            .forgetCredential(id: entry.id);
                        ref.invalidate(savedCredentialsProvider);
                      } on Object {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(l.errStorage)));
                        }
                      }
                    },
                  ),
                ),
            ],
          ),
        );
  }
}
