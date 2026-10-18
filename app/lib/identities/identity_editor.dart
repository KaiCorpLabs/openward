import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../hosts/editors.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/identities.dart';
import '../src/rust/api/vault.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'identities.dart';

/// Creates (no `id`) or edits an identity in the side panel. Returns the
/// id of what was saved, or null.
Future<String?> showIdentityEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
}) async {
  String? saved;
  await showSidePanel(
    context,
    (_) => _IdentityEditor(id: id, onSaved: (s) => saved = s),
  );
  return saved;
}

class _IdentityEditor extends ConsumerStatefulWidget {
  const _IdentityEditor({this.id, required this.onSaved});

  final String? id;
  final ValueChanged<String> onSaved;

  @override
  ConsumerState<_IdentityEditor> createState() => _IdentityEditorState();
}

class _IdentityEditorState extends ConsumerState<_IdentityEditor> {
  late final IdentityView? _old = widget.id == null
      ? null
      : ref.read(openWardProvider).identity(id: widget.id!);
  late final _label = TextEditingController(text: _old?.spec.label ?? '');
  late final _user = TextEditingController(text: _old?.spec.user ?? '');
  late final _socket = TextEditingController(
    text: _old?.spec.agentSocket ?? '',
  );
  final _typed = TextEditingController();
  late final List<String> _keys = [...?_old?.spec.identityFiles];
  late final List<String> _certs = [...?_old?.spec.certificateFiles];
  late AgentKind _agent = _old?.spec.agent ?? AgentKind.system;
  late bool _only = _old?.spec.identitiesOnly ?? false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_label, _user, _socket, _typed]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _sshDir {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return '$home${Platform.pathSeparator}.ssh';
  }

  Future<String?> _pick() async {
    final file = await openFile(initialDirectory: _sshDir);
    return file == null ? null : tildePath(file.path);
  }

  Future<void> _addKey() async {
    final path = await _pick();
    if (path != null && !_keys.contains(path)) setState(() => _keys.add(path));
  }

  void _addTyped() {
    final path = tildePath(_typed.text.trim());
    if (path.isEmpty) return;
    setState(() {
      if (!_keys.contains(path)) _keys.add(path);
      _typed.clear();
    });
  }

  Future<void> _addCert() async {
    final path = await _pick();
    if (path != null && !_certs.contains(path)) {
      setState(() => _certs.add(path));
    }
  }

  IdentitySpec _spec() => IdentitySpec(
    label: _label.text.trim(),
    user: _user.text.trim().isEmpty ? null : _user.text.trim(),
    identityFiles: _keys,
    certificateFiles: _certs,
    identitiesOnly: _only,
    agent: _agent,
    agentSocket: _agent == AgentKind.socket ? _socket.text.trim() : '',
  );

  Future<void> _save() async {
    final l = context.l10n;
    if (_label.text.trim().isEmpty) {
      return setState(() => _error = l.identityNeedsName);
    }
    if (_agent == AgentKind.socket && _socket.text.trim().isEmpty) {
      return setState(() => _error = l.missingSocket);
    }
    final app = ref.read(openWardProvider);
    try {
      final old = _old;
      final String id;
      if (old == null) {
        id = await app.createIdentity(spec: _spec());
      } else {
        await app.updateIdentity(id: old.id, rev: old.rev, spec: _spec());
        id = old.id;
      }
      identitiesChanged(ref);
      widget.onSaved(id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(
        () => _error = '$e'.contains('changed since')
            ? l.changedMeanwhile
            : l.saveFailed('$e'),
      );
    }
  }

  Future<void> _delete() async {
    final old = _old;
    if (old == null) return;
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteIdentityTitle(old.spec.label)),
        content: Text(
          old.hostCount > 0
              ? l.deleteIdentityBody(old.hostCount)
              : l.deleteIdentityUnused,
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('identity.delete.confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: context.ow.colors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await ref.read(openWardProvider).delete(id: old.id);
    identitiesChanged(ref);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final app = ref.read(openWardProvider);
    final mono = monoStyle(context, size: 13, color: c.text);
    final old = _old;
    Widget labelled(String text, Widget field, {String? hint}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(text, style: TextStyle(color: c.textMuted)),
            if (hint != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
    return EditorFrame(
      title: old == null ? l.newIdentity : l.editIdentity,
      subtitle: old == null
          ? l.identityEditorHint
          : old.chooserIds.isEmpty
          ? l.usedByNobody
          : l.identityUsedBy(usedByText(l, old)),
      error: _error,
      onSave: _save,
      onDelete: old == null ? null : _delete,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: labelled(
                l.name,
                TextField(
                  key: const ValueKey('identity.label'),
                  controller: _label,
                  autofocus: old == null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 170,
              child: labelled(
                l.user,
                TextField(
                  key: const ValueKey('identity.user'),
                  controller: _user,
                  style: mono,
                  decoration: InputDecoration(hintText: l.localUser),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        labelled(
          l.keys,
          hint: _keys.length > 1 ? l.keysInOrder : null,
          _keys.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.sunken,
                    border: Border.all(color: c.control),
                    borderRadius: BorderRadius.circular(ow.shape.radius),
                  ),
                  child: Text(
                    l.noKeysYet,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                )
              : Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.sunken,
                    border: Border.all(color: c.control),
                    borderRadius: BorderRadius.circular(ow.shape.radius),
                  ),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _keys.length,
                    onReorderItem: (from, to) =>
                        setState(() => _keys.insert(to, _keys.removeAt(from))),
                    itemBuilder: (context, i) => _KeyItem(
                      key: ValueKey(_keys[i]),
                      index: i,
                      info: app.keyInfo(
                        path: _keys[i],
                        certificateFiles: _certs,
                      ),
                      onRemove: () => setState(() => _keys.removeAt(i)),
                      onAddCert: _addCert,
                      onRemoveCert: (path) =>
                          setState(() => _certs.remove(path)),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('identity.addKey'),
              onPressed: _addKey,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: Text(l.addKeyEllipsis),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('identity.keyPath'),
                controller: _typed,
                style: mono,
                onSubmitted: (_) => _addTyped(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.orTypeAPath,
                  hintStyle: TextStyle(
                    fontFamily: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.fontFamily,
                    fontSize: 12,
                    color: c.textSubtle,
                  ),
                  suffixIcon: IconButton(
                    tooltip: l.add,
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: _addTyped,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        labelled(
          l.agent,
          SegmentedButton<AgentKind>(
            key: const ValueKey('identity.agent'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AgentKind.system,
                label: Text(l.agentSystem),
              ),
              ButtonSegment(
                value: AgentKind.socket,
                label: Text(l.agentOtherSocket),
              ),
              ButtonSegment(value: AgentKind.off, label: Text(l.agentNone)),
            ],
            selected: {_agent},
            onSelectionChanged: (s) => setState(() => _agent = s.first),
          ),
        ),
        if (_agent == AgentKind.socket) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _socket,
            style: mono,
            decoration: const InputDecoration(
              hintText: '~/Library/Group Containers/…/agent.sock',
            ),
          ),
        ],
        const SizedBox(height: 16),
        Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.border),
            borderRadius: BorderRadius.circular(ow.shape.radius),
          ),
          child: SwitchListTile(
            key: const ValueKey('identity.only'),
            value: _only,
            onChanged: (v) => setState(() => _only = v),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l.offerOnlyTheseKeys),
            subtitle: Text(
              l.offerOnlyTheseKeysNote,
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Callout(
          tone: Tone.info,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 14, color: c.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  old != null && old.hostCount > 0
                      ? l.identitySaveChanges(old.hostCount)
                      : l.identityNewNote,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A key of the list: its path and what it is, its certificate, and a
/// handle to move it.
class _KeyItem extends StatelessWidget {
  const _KeyItem({
    super.key,
    required this.index,
    required this.info,
    required this.onRemove,
    required this.onAddCert,
    required this.onRemoveCert,
  });

  final int index;
  final KeyView info;
  final VoidCallback onRemove;
  final VoidCallback onAddCert;
  final ValueChanged<String> onRemoveCert;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final cert = info.certificate;
    final missing = info.state == KeyStateKind.missing;
    return Container(
      decoration: BoxDecoration(
        color: c.sunken,
        border: index == 0 ? null : Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: c.textSubtle,
                    ),
                  ),
                ),
              ),
              Icon(Icons.key_outlined, size: 16, color: c.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.path,
                      style: monoStyle(
                        context,
                        size: 12,
                        color: missing ? c.warn : c.text,
                      ),
                    ),
                    Text(
                      keyDetail(l, info),
                      style: TextStyle(
                        fontSize: 12,
                        color: missing ? c.warn : c.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l.removeKey,
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ],
          ),
          if (cert != null)
            Container(
              margin: const EdgeInsets.fromLTRB(30, 6, 4, 0),
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: BorderRadius.circular(ow.shape.radiusSmall),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 14,
                    color: c.accentText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.certificateTitle,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      baseName(cert.path),
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 12, color: c.text),
                    ),
                  ),
                  Text(
                    cert.expired
                        ? l.certExpiredOn(certDate(l, cert))
                        : cert.validBeforeMs == null
                        ? l.certForever
                        : l.certUntil(certDate(l, cert)),
                    style: TextStyle(
                      fontSize: 12,
                      color: cert.expired ? c.warn : c.accentText,
                    ),
                  ),
                  if (cert.implicit)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, right: 6),
                      child: Tooltip(
                        message: l.certNextToKey,
                        child: Icon(Icons.link, size: 14, color: c.textSubtle),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: l.removeCertificate,
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      icon: const Icon(Icons.close),
                      onPressed: () => onRemoveCert(cert.path),
                    ),
                ],
              ),
            )
          else if (info.state == KeyStateKind.found)
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: TextButton(
                onPressed: onAddCert,
                style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(l.addCertificate),
              ),
            ),
        ],
      ),
    );
  }
}
