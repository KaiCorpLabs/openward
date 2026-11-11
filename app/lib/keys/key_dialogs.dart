// Making a key, bringing one in, and putting a public key on a server.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/errors.dart';
import '../core/match.dart';
import '../core/providers.dart';
import '../hosts/host_actions.dart' show overSsh;
import '../l10n/l10n.dart';
import '../src/rust/api/keychain.dart';
import '../src/rust/api/vault.dart';
import '../tabs/connection_panels.dart';
import '../tabs/messages.dart';
import '../tabs/prompt_card.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'keys.dart';

Widget _labelled(BuildContext context, String text, Widget field) {
  final c = context.ow.colors;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(text, style: TextStyle(color: c.textMuted)),
      const SizedBox(height: 6),
      field,
    ],
  );
}

/// "Nueva clave": the key made, or null.
Future<SshKey?> showNewKeyDialog(BuildContext context) async {
  try {
    await ProviderScope.containerOf(context).read(keysProvider.future);
    if (!context.mounted) return null;
    return await showDialog<SshKey>(
      context: context,
      builder: (_) => const _NewKey(),
    );
  } catch (error) {
    if (context.mounted) await showErrorDetails(context, error);
    return null;
  }
}

class _NewKey extends ConsumerStatefulWidget {
  const _NewKey();

  @override
  ConsumerState<_NewKey> createState() => _NewKeyState();
}

class _NewKeyState extends ConsumerState<_NewKey> {
  SshKeyType _type = SshKeyType.ed25519;

  /// Made on a security key: the file holds no secret.
  bool _onKey = false;

  /// With [_onKey]: its PIN at every use (`verify-required`).
  bool _verify = false;
  final _pin = TextEditingController();
  late final _name = TextEditingController(text: _freeName());
  late final _comment = TextEditingController(
    text: ref.read(openWardProvider).keyComment(),
  );
  final _passphrase = TextEditingController();
  final _again = TextEditingController();
  bool _nameTouched = false;
  bool _busy = false;
  String? _error;

  /// The core's failure behind [_error], for «Detalles».
  SshKeyFailure? _cause;

  SshKeyFailure? get _details => switch (_cause) {
    final f?
        when f.kind == SshKeyFailureKind.io ||
            f.kind == SshKeyFailureKind.make =>
      f,
    _ => null,
  };

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    _passphrase.dispose();
    _again.dispose();
    _pin.dispose();
    super.dispose();
  }

  String _freeName() => freeKeyName(
    _type,
    (ref.read(keysProvider).value ?? const <SshKey>[]).map((k) => k.name),
    securityKey: _onKey,
  );

  /// On a security key: it waits for the touch.
  Future<void> _makeOnKey() async {
    final l = context.l10n;
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _cause = null;
    });
    final r = await ref
        .read(openWardProvider)
        .generateSecurityKey(
          name: name,
          kind: _type == SshKeyType.ecdsa
              ? SecurityKeyType.ecdsa
              : SecurityKeyType.ed25519,
          comment: _comment.text.trim(),
          pin: _pin.text.isEmpty ? null : _pin.text,
          verify: _verify,
        );
    if (!mounted) return;
    _pin.clear();
    if (r.failure != null) {
      setState(() {
        _busy = false;
        _error = keyFailureText(l, r.failure!, name);
        _cause = r.failure;
      });
      return;
    }
    ref.read(keysProvider.notifier).refresh();
    Navigator.pop(context, r.key);
  }

  Future<void> _make() async {
    if (_onKey) return _makeOnKey();
    final l = context.l10n;
    final name = _name.text.trim();
    if (_passphrase.text != _again.text) {
      setState(() {
        _error = l.passphrasesDiffer;
        _cause = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _cause = null;
    });
    final r = await ref
        .read(openWardProvider)
        .generateKey(
          name: name,
          kind: _type,
          comment: _comment.text.trim(),
          passphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
        );
    if (!mounted) return;
    _passphrase.clear();
    _again.clear();
    if (r.failure != null) {
      setState(() {
        _busy = false;
        _error = keyFailureText(l, r.failure!, name);
        _cause = r.failure;
      });
      return;
    }
    ref.read(keysProvider.notifier).refresh();
    Navigator.pop(context, r.key);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final mono = monoStyle(context, size: 13, color: c.text);
    final name = _name.text.trim().isEmpty ? 'id_ed25519' : _name.text.trim();
    return AlertDialog(
      // A small window scrolls it.
      scrollable: true,
      title: Text(l.newKey),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const ValueKey('newKey.onKey'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.onSecurityKey),
              value: _onKey,
              onChanged: _busy
                  ? null
                  : (on) => setState(() {
                      _onKey = on;
                      // No RSA on security keys.
                      if (on && _type == SshKeyType.rsa) {
                        _type = SshKeyType.ed25519;
                      }
                      if (!_nameTouched) _name.text = _freeName();
                    }),
            ),
            const SizedBox(height: 8),
            _labelled(
              context,
              l.keyType,
              SegmentedButton<SshKeyType>(
                key: const ValueKey('newKey.type'),
                showSelectedIcon: false,
                segments: [
                  for (final t in SshKeyType.values)
                    if (!_onKey || t != SshKeyType.rsa)
                      ButtonSegment(value: t, label: Text(keyTypeLabel(t))),
                ],
                selected: {_type},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() {
                        _type = s.first;
                        if (!_nameTouched) _name.text = _freeName();
                      }),
              ),
            ),
            const SizedBox(height: 6),
            Text(switch ((_type, _onKey)) {
              (SshKeyType.ed25519, true) => l.keyTypeSecurityEd25519,
              (SshKeyType.ecdsa, true) => l.keyTypeSecurityEcdsa,
              (SshKeyType.ed25519, false) => l.keyTypeEd25519,
              (SshKeyType.ecdsa, false) => l.keyTypeEcdsa,
              (SshKeyType.rsa, _) => l.keyTypeRsa,
            }, style: TextStyle(fontSize: OwText.small, color: c.textMuted)),
            const SizedBox(height: 16),
            _labelled(
              context,
              l.fileName,
              TextField(
                key: const ValueKey('newKey.name'),
                controller: _name,
                enabled: !_busy,
                style: mono,
                onChanged: (_) => setState(() => _nameTouched = true),
                decoration: const InputDecoration(prefixText: '~/.ssh/'),
              ),
            ),
            const SizedBox(height: 16),
            _labelled(
              context,
              l.keyCommentLabel,
              TextField(
                key: const ValueKey('newKey.comment'),
                controller: _comment,
                enabled: !_busy,
                style: mono,
              ),
            ),
            const SizedBox(height: 16),
            if (_onKey) ...[
              _labelled(
                context,
                l.securityKeyPinOptional,
                TextField(
                  key: const ValueKey('newKey.pin'),
                  controller: _pin,
                  enabled: !_busy,
                  obscureText: true,
                  onSubmitted: (_) => _make(),
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('newKey.verify'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.verifyRequired),
                value: _verify,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _verify = v ?? false),
              ),
              Text(
                _busy ? l.touchKeyNow : l.onSecurityKeyNote,
                key: const ValueKey('newKey.touch'),
                style: TextStyle(
                  fontSize: OwText.small,
                  color: _busy ? c.accentText : c.textMuted,
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _labelled(
                      context,
                      l.passphraseOptional,
                      TextField(
                        key: const ValueKey('newKey.passphrase'),
                        controller: _passphrase,
                        enabled: !_busy,
                        obscureText: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _labelled(
                      context,
                      l.repeatPassphrase,
                      TextField(
                        key: const ValueKey('newKey.again'),
                        controller: _again,
                        enabled: !_busy,
                        obscureText: true,
                        onSubmitted: (_) => _make(),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              l.newKeyWhere('~/.ssh/$name', '~/.ssh/$name.pub'),
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.danger)),
              if (_details case final e?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DetailsButton(e),
                ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('newKey.make'),
          onPressed: _busy || _name.text.trim().isEmpty ? null : _make,
          child: _busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(l.makingKey),
                  ],
                )
              : Text(l.makeKey),
        ),
      ],
    );
  }
}

/// "Importar clave": the key saved, or null.
Future<SshKey?> showImportKeyDialog(BuildContext context) =>
    showDialog<SshKey>(context: context, builder: (_) => const _ImportKey());

class _ImportKey extends ConsumerStatefulWidget {
  const _ImportKey();

  @override
  ConsumerState<_ImportKey> createState() => _ImportKeyState();
}

class _ImportKeyState extends ConsumerState<_ImportKey> {
  final _name = TextEditingController();
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The core's failure behind [_error], for «Detalles».
  SshKeyFailure? _cause;

  SshKeyFailure? get _details => switch (_cause) {
    final f?
        when f.kind == SshKeyFailureKind.io ||
            f.kind == SshKeyFailureKind.make =>
      f,
    _ => null,
  };

  @override
  void dispose() {
    _name.dispose();
    // Dart cannot wipe strings; at least the field lets go of it now.
    _text.clear();
    _text.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final file = await openFile();
    if (file == null || !mounted) return;
    try {
      final text = await File(file.path).readAsString();
      final taken = (await ref.read(keysProvider.future))
          .map((k) => k.name)
          .toSet();
      if (!mounted) return;
      setState(() {
        _text.text = text;
        if (_name.text.trim().isEmpty) {
          var name = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._@-]'), '_');
          if (name.endsWith('.pem') || name.endsWith('.ppk')) {
            name = name.substring(0, name.length - 4);
          }
          var n = name;
          for (var i = 2; taken.contains(n); i++) {
            n = '${name}_$i';
          }
          _name.text = n;
        }
        _error = null;
        _cause = null;
      });
    } catch (_) {
      setState(() {
        _error = context.l10n.keyNotReadable;
        _cause = null;
      });
    }
  }

  Future<void> _import() async {
    final l = context.l10n;
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _cause = null;
    });
    final r = await ref
        .read(openWardProvider)
        .importKey(name: name, text: _text.text);
    if (!mounted) return;
    if (r.failure != null) {
      setState(() {
        _busy = false;
        _error = keyFailureText(l, r.failure!, name);
        _cause = r.failure;
      });
      return;
    }
    ref.read(keysProvider.notifier).refresh();
    Navigator.pop(context, r.key);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final mono = monoStyle(context, size: 12, color: c.text);
    final ready = _name.text.trim().isNotEmpty && _text.text.trim().isNotEmpty;
    return AlertDialog(
      scrollable: true,
      title: Text(l.importKey),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.importKeyIntro, style: TextStyle(color: c.textMuted)),
            const SizedBox(height: 16),
            _labelled(
              context,
              l.privateKey,
              TextField(
                key: const ValueKey('importKey.text'),
                controller: _text,
                enabled: !_busy,
                minLines: 6,
                maxLines: 10,
                style: mono.copyWith(height: 1.4),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                  hintStyle: monoStyle(context, size: 12, color: c.textSubtle),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(l.chooseFile),
              ),
            ),
            const SizedBox(height: 8),
            _labelled(
              context,
              l.saveAs,
              TextField(
                key: const ValueKey('importKey.name'),
                controller: _name,
                enabled: !_busy,
                style: monoStyle(context, size: 13, color: c.text),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixText: '~/.ssh/'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.danger)),
              if (_details case final e?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DetailsButton(e),
                ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('importKey.save'),
          onPressed: _busy || !ready ? null : _import,
          child: Text(l.importAction),
        ),
      ],
    );
  }
}

/// "Subir a un servidor": picks a saved host (or an address) and puts the
/// key's public half in its `~/.ssh/authorized_keys`.
Future<void> showInstallKeyDialog(
  BuildContext context,
  SshKey key,
  String line,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _InstallKey(sshKey: key, line: line),
);

class _InstallKey extends ConsumerStatefulWidget {
  const _InstallKey({required this.sshKey, required this.line});

  final SshKey sshKey;
  final String line;

  @override
  ConsumerState<_InstallKey> createState() => _InstallKeyState();
}

class _InstallKeyState extends ConsumerState<_InstallKey> {
  final _query = TextEditingController();
  KeyInstall? _install;
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    _install?.removeListener(_changed);
    _install?.cancel();
    _install?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<HostView> _hosts() {
    final library = ref.read(libraryProvider);
    final matcher = HostMatcher(_query.text, library);
    // A key goes over SSH.
    final hosts = library.hosts.where(overSsh).toList();
    return matcher.isEmpty ? hosts : matcher.filter(hosts);
  }

  void _start({HostView? host, QuickTarget? target}) {
    final install = startKeyInstall(
      ref.read(openWardProvider),
      widget.line,
      hostId: host?.id,
      target: target,
      label: host?.label ?? target!.address,
    );
    install.addListener(_changed);
    setState(() => _install = install);
  }

  void _again() {
    _install?.removeListener(_changed);
    _install?.dispose();
    setState(() => _install = null);
  }

  @override
  Widget build(BuildContext context) {
    final install = _install;
    final Widget body;
    if (install == null) {
      body = _pick(context);
    } else if (install.prompts.isNotEmpty) {
      final prompt = install.prompts.first;
      body = PromptCard(
        key: ObjectKey(prompt),
        controller: install,
        prompt: prompt,
      );
    } else {
      body = switch (install.step) {
        InstallStep.connecting => ConnectingCard(controller: install),
        InstallStep.installing => _working(context, install),
        InstallStep.done || InstallStep.failed => _result(context, install),
      };
    }
    return Center(
      child: Material(type: MaterialType.transparency, child: body),
    );
  }

  Widget _pick(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final hosts = _hosts();
    final typed = QuickTarget.parse(_query.text);
    final pick = hosts.isEmpty
        ? null
        : hosts[_selected.clamp(0, hosts.length - 1)];
    void go() {
      if (pick != null) {
        _start(host: pick);
      } else if (typed != null) {
        _start(target: typed);
      }
    }

    return OverlayPanel(
      width: 480,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(context),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
            () =>
                _selected = hosts.isEmpty ? 0 : (_selected + 1) % hosts.length,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(
            () => _selected = hosts.isEmpty
                ? 0
                : (_selected - 1 + hosts.length) % hosts.length,
          ),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.installKeyTitle(widget.sshKey.name),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(l.installKeyIntro, style: TextStyle(color: c.textMuted)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('installKey.query'),
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() => _selected = 0),
              onSubmitted: (_) => go(),
              decoration: InputDecoration(
                isDense: true,
                hintText: l.installKeySearch,
                prefixIcon: Icon(Icons.search, size: 16, color: c.textSubtle),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, h) in hosts.indexed)
                    Material(
                      color: i == _selected ? c.selected : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        context.ow.shape.radius,
                      ),
                      child: InkWell(
                        key: ValueKey('installKey.host.${h.label}'),
                        borderRadius: BorderRadius.circular(
                          context.ow.shape.radius,
                        ),
                        onTap: () => _start(host: h),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: OwSpace.s5,
                            vertical: OwSpace.s3,
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(h.label)),
                              Text(
                                '${h.user.isEmpty ? '' : '${h.user}@'}'
                                '${h.address}${h.port == 22 ? '' : ':${h.port}'}',
                                style: monoStyle(
                                  context,
                                  size: 12,
                                  color: c.textSubtle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (hosts.isEmpty && typed != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.lan_outlined, size: 18),
                      title: Text(l.installKeyToAddress(_query.text.trim())),
                      onTap: go,
                    ),
                  if (hosts.isEmpty && typed == null)
                    Padding(
                      padding: const EdgeInsets.all(OwSpace.s5),
                      child: Text(
                        l.installKeyNoHosts,
                        style: TextStyle(color: c.textMuted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _working(BuildContext context, KeyInstall install) {
    final l = context.l10n;
    return OverlayPanel(
      width: 420,
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l.installingKey(install.label))),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, KeyInstall install) {
    final l = context.l10n;
    final c = context.ow.colors;
    final ok = install.step == InstallStep.done;
    final failure = install.closed?.failure;
    final why = install.writeError != null
        ? l.installKeyWriteFailed(errorReason(l, install.writeError!))
        : failure != null
        ? failureText(l, failure)
        : install.errorCause != null
        ? l.statusError(errorReason(l, install.errorCause!))
        : install.cancelled
        ? l.cancelled
        : '';
    final details = install.writeError ?? failure ?? install.errorCause;
    return OverlayPanel(
      width: 460,
      child: Column(
        key: ValueKey(ok ? 'installKey.done' : 'installKey.failed'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 20,
                color: ok ? c.accentText : c.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok
                      ? (install.added
                            ? l.installKeyAdded(install.label)
                            : l.installKeyWasThere(install.label))
                      : l.installKeyFailed(install.label),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ok ? l.installKeyNext : why,
            style: TextStyle(color: c.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!ok && details != null) ...[
                DetailsButton(details),
                const Spacer(),
              ],
              if (!ok) ...[
                OutlinedButton(onPressed: _again, child: Text(l.tryAnother)),
                const SizedBox(width: 8),
              ],
              FilledButton(
                key: const ValueKey('installKey.close'),
                onPressed: () => Navigator.pop(context),
                child: Text(l.close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
