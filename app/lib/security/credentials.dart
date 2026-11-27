import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/credentials.dart';
import '../src/rust/api/security.dart';
import '../ui/tokens.dart';
import 'state.dart';
import 'unlock.dart';

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
    final ow = owOf(context);
    final c = ow.colors;
    if (ref.watch(securityProvider).phase != VaultPhase.unlocked) {
      return const SizedBox.shrink();
    }
    return ref
        .watch(savedCredentialsProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) =>
              Text(l.errStorage, style: TextStyle(color: c.danger)),
          data: (entries) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.vaultSavedCredentials,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l.vaultCredentialExplain,
                style: TextStyle(color: c.textMuted),
              ),
              const SizedBox(height: 12),
              if (entries.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: OwSpace.s6,
                    vertical: OwSpace.s5,
                  ),
                  decoration: BoxDecoration(
                    color: c.sunken,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(ow.shape.radius),
                  ),
                  child: Text(
                    l.vaultCredentialsEmpty,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: c.textMuted,
                    ),
                  ),
                )
              else
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
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                      ),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.errStorage)),
                            );
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
