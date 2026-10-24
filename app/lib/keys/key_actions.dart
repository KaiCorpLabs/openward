// What can be done to a key from its row, besides copying and putting it
// on a server: renaming it, giving it another passphrase, exporting it,
// finding it in the file manager and deleting it.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/keychain.dart';
import '../ui/confirm.dart';
import '../ui/tokens.dart';
import 'keys.dart';

/// How the file manager is called here, for «Show in …».
String revealLabel(AppLocalizations l) => Platform.isMacOS
    ? l.revealInFinder
    : Platform.isWindows
    ? l.revealInExplorer
    : l.revealInFolder;

/// The key's file in the file manager: chosen, where the system can.
Future<void> revealKey(WidgetRef ref, SshKey k) async {
  final file = ref.read(openWardProvider).keyFilePath(path: k.path);
  if (Platform.isMacOS) {
    await Process.run('open', ['-R', file]);
  } else if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', file]);
  } else {
    await launchUrl(Uri.directory(File(file).parent.path));
  }
}

/// A copy of the private key where the user says, readable only by them.
Future<void> exportKey(BuildContext context, WidgetRef ref, SshKey k) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final to = await getSaveLocation(suggestedName: k.name);
  if (to == null) return;
  final from = ref.read(openWardProvider).keyFilePath(path: k.path);
  try {
    await File(from).copy(to.path);
    if (!Platform.isWindows) await Process.run('chmod', ['600', to.path]);
    messenger.showSnackBar(
      SnackBar(content: Text(l.keyExported(k.name, to.path))),
    );
  } catch (e) {
    showErrorNotice(messenger, l.keyFailed, e);
  }
}

/// Asks, saying who uses it, then deletes it.
Future<void> deleteKey(BuildContext context, WidgetRef ref, SshKey k) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final sure = await confirmDestructive(
    context,
    title: l.deleteKeyTitle(k.name),
    body: [
      l.deleteKeyBody(k.path),
      if (k.usedBy.isNotEmpty) l.deleteKeyUsed(k.usedBy.join(', ')),
    ].join('\n\n'),
    action: l.delete,
    actionKey: const ValueKey('key.delete.confirm'),
  );
  if (!sure) return;
  final failure = await ref.read(openWardProvider).deleteKey(path: k.path);
  ref.read(keysProvider.notifier).refresh();
  if (failure != null) {
    return showErrorNotice(
      messenger,
      keyFailureText(l, failure, k.name),
      failure,
    );
  }
  messenger.showSnackBar(SnackBar(content: Text(l.keyDeleted(k.name))));
}

/// A new name for the key; the hosts that use it follow.
Future<void> renameKey(BuildContext context, SshKey k) =>
    showDialog<void>(context: context, builder: (_) => _RenameKey(k));

/// Another passphrase for the key, or none.
Future<void> changeKeyPassphrase(BuildContext context, SshKey k) =>
    showDialog<void>(context: context, builder: (_) => _Passphrase(k));

class _RenameKey extends ConsumerStatefulWidget {
  const _RenameKey(this.k);

  final SshKey k;

  @override
  ConsumerState<_RenameKey> createState() => _RenameKeyState();
}

class _RenameKeyState extends ConsumerState<_RenameKey> {
  late final _name = TextEditingController(text: widget.k.name);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final name = _name.text.trim();
    if (name == widget.k.name) return Navigator.pop(context);
    setState(() => _busy = true);
    final r = await ref
        .read(openWardProvider)
        .renameKey(path: widget.k.path, name: name);
    if (!mounted) return;
    if (r.failure case final f?) {
      return setState(() {
        _busy = false;
        _error = keyFailureText(l, f, name);
      });
    }
    ref.read(keysProvider.notifier).refresh();
    ref.read(libraryProvider.notifier).refresh();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    return AlertDialog(
      title: Text(l.keyRenameTitle(widget.k.name)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('key.rename.name'),
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                prefixText: '~/.ssh/',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.keyRenameNote,
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('key.rename.save'),
          onPressed: _busy ? null : _save,
          child: Text(l.rename),
        ),
      ],
    );
  }
}

class _Passphrase extends ConsumerStatefulWidget {
  const _Passphrase(this.k);

  final SshKey k;

  @override
  ConsumerState<_Passphrase> createState() => _PassphraseState();
}

class _PassphraseState extends ConsumerState<_Passphrase> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    // Dart cannot wipe strings; the fields at least let go of them.
    for (final c in [_old, _new, _again]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_new.text != _again.text) {
      return setState(() => _error = l.passphrasesDiffer);
    }
    setState(() => _busy = true);
    final failure = await ref
        .read(openWardProvider)
        .changeKeyPassphrase(
          path: widget.k.path,
          old: widget.k.encrypted ? _old.text : null,
          new_: _new.text.isEmpty ? null : _new.text,
        );
    if (!mounted) return;
    if (failure != null) {
      return setState(() {
        _busy = false;
        _error = keyFailureText(l, failure, widget.k.name);
      });
    }
    final messenger = ScaffoldMessenger.of(context);
    ref.read(keysProvider.notifier).refresh();
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l.keyPassphraseChanged(widget.k.name))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    Widget field(TextEditingController controller, String label, Key key) =>
        TextField(
          key: key,
          controller: controller,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: label),
        );
    return AlertDialog(
      title: Text(l.keyPassphraseTitle(widget.k.name)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.k.encrypted) ...[
              field(
                _old,
                l.currentPassphrase,
                const ValueKey('key.passphrase.old'),
              ),
              const SizedBox(height: 10),
            ],
            field(_new, l.newPassphrase, const ValueKey('key.passphrase.new')),
            const SizedBox(height: 10),
            field(
              _again,
              l.repeatPassphrase,
              const ValueKey('key.passphrase.again'),
            ),
            const SizedBox(height: 10),
            Text(
              l.keyPassphraseEmpty,
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            if (_error case final e?) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(e, style: TextStyle(color: c.danger)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('key.passphrase.save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
