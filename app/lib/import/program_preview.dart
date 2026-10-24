import 'package:flutter/material.dart';

import '../hosts/editors.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/programs.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'programs.dart';

/// What importing would bring, as a tree to pick from, with the keys and
/// where everything goes. The choice, or null if the user left.
Future<ProgramChoice?> showProgramPreview(
  BuildContext context,
  ProgramPreview preview,
) async {
  ProgramChoice? choice;
  await showSidePanel(
    context,
    (_) => _Preview(preview: preview, onImport: (c) => choice = c),
    width: 680,
  );
  return choice;
}

class _Preview extends StatefulWidget {
  const _Preview({required this.preview, required this.onImport});

  final ProgramPreview preview;
  final ValueChanged<ProgramChoice> onImport;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late final TextEditingController _group = TextEditingController(
    text: programName(widget.preview.program),
  );
  late final Set<String> _picked = {for (final h in _pickable) h.id};
  final Set<String> _saveKeys = {};
  final Set<String> _closed = {};

  ProgramPreview get _p => widget.preview;

  /// As a tree: each group followed by what is in it (its groups first),
  /// then the hosts outside any group.
  late final List<ProgramItem> _tree = () {
    final groups = {for (final i in _p.items.where((i) => i.isGroup)) i.id};
    String? parentOf(ProgramItem i) =>
        groups.contains(i.parent) ? i.parent : null;
    final out = <ProgramItem>[];
    void add(String? parent) {
      for (final g in _p.items.where(
        (i) => i.isGroup && parentOf(i) == parent,
      )) {
        out.add(g);
        add(g.id);
      }
      out.addAll(_p.items.where((i) => !i.isGroup && parentOf(i) == parent));
    }

    add(null);
    return out;
  }();
  Iterable<ProgramItem> get _hosts => _p.items.where((i) => !i.isGroup);
  Iterable<ProgramItem> get _pickable =>
      _hosts.where((h) => !h.existing && h.unsupported == null);

  ProgramItem? _byLabel(String label) =>
      _hosts.where((h) => h.label == label).firstOrNull;

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  /// The hosts under a group, all the way down.
  Iterable<ProgramItem> _under(String group) sync* {
    for (final i in _p.items) {
      if (i.parent != group) continue;
      if (i.isGroup) {
        yield* _under(i.id);
      } else {
        yield i;
      }
    }
  }

  void _pick(ProgramItem h, bool on) {
    setState(() {
      if (on) {
        // And what it jumps through.
        final queue = [h];
        while (queue.isNotEmpty) {
          final next = queue.removeLast();
          if (next.existing || next.unsupported != null) continue;
          if (!_picked.add(next.id) && !identical(next, h)) continue;
          queue.addAll(next.jumps.map(_byLabel).whereType<ProgramItem>());
        }
      } else {
        // And whatever jumps through it.
        final queue = [h];
        while (queue.isNotEmpty) {
          final gone = queue.removeLast();
          _picked.remove(gone.id);
          queue.addAll(
            _hosts.where(
              (o) => _picked.contains(o.id) && o.jumps.contains(gone.label),
            ),
          );
        }
      }
    });
  }

  bool? _state(Iterable<ProgramItem> hosts) {
    final open = hosts.where((h) => !h.existing && h.unsupported == null);
    if (open.isEmpty) return false;
    final n = open.where((h) => _picked.contains(h.id)).length;
    return n == 0
        ? false
        : n == open.length
        ? true
        : null;
  }

  void _pickAll(Iterable<ProgramItem> hosts, bool on) {
    for (final h in hosts.toList()) {
      if (!h.existing && h.unsupported == null) _pick(h, on);
    }
  }

  int _depth(ProgramItem i) {
    var d = 0;
    var parent = i.parent;
    while (parent != null) {
      d++;
      parent = _p.items
          .where((g) => g.isGroup && g.id == parent)
          .firstOrNull
          ?.parent;
    }
    return d;
  }

  bool _hidden(ProgramItem i) {
    var parent = i.parent;
    while (parent != null) {
      if (_closed.contains(parent)) return true;
      parent = _p.items
          .where((g) => g.isGroup && g.id == parent)
          .firstOrNull
          ?.parent;
    }
    return false;
  }

  void _import() {
    widget.onImport(
      ProgramChoice(
        hosts: _picked.toList(),
        groupName: _group.text.trim().isEmpty
            ? programName(_p.program)
            : _group.text.trim(),
        saveKeys: _saveKeys.toList(),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final hosts = _hosts.length;
    final groups = _p.items.where((i) => i.isGroup).length;
    final extras =
        _p.newSnippets + _p.newKnownHosts + _p.newTunnels + _p.newIdentities;
    final canImport = _picked.isNotEmpty || extras > 0;
    return EditorFrame(
      title: l.previewTitle(programName(_p.program)),
      subtitle: l.previewSubtitle(hosts, groups),
      error: null,
      onSave: _import,
      saveLabel: l.importN(_picked.length),
      saveEnabled: canImport,
      children: [
        Row(
          children: [
            Text(l.previewIntoGroup, style: TextStyle(color: c.text)),
            const SizedBox(width: 10),
            if (_p.group != null)
              Expanded(
                child: Text(
                  l.previewIntoExisting(_p.group!),
                  style: TextStyle(color: c.textMuted),
                ),
              )
            else
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _group,
                  style: fieldTextStyle(context),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l.previewIntoGroup,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Pill(l.previewHostsOf(_picked.length, _pickable.length)),
            if (_p.identities > 0)
              Pill(l.previewIdentities(_p.identities), tone: PillTone.neutral),
            if (_p.newTunnels > 0)
              Pill(l.previewTunnels(_p.newTunnels), tone: PillTone.neutral),
            if (_p.newSnippets > 0)
              Pill(l.previewSnippets(_p.newSnippets), tone: PillTone.neutral),
            if (_p.newKnownHosts > 0)
              Pill(
                l.previewKnownHosts(_p.newKnownHosts),
                tone: PillTone.neutral,
              ),
          ],
        ),
        const SizedBox(height: 12),
        _box(context, [
          _row(
            context,
            depth: 0,
            header: true,
            value: _state(_hosts),
            onChanged: _pickable.isEmpty
                ? null
                : (_) => _pickAll(_hosts, _state(_hosts) != true),
            title: l.selectAll,
            trailing: l.previewSubtitle(hosts, groups),
          ),
          for (final i in _tree)
            if (!_hidden(i)) _item(context, i),
        ]),
        if (_p.keys.isNotEmpty) ...[
          const SizedBox(height: 16),
          _box(context, [
            Container(
              color: c.sunken,
              padding: const EdgeInsets.fromLTRB(
                OwSpace.s6,
                OwSpace.s4,
                OwSpace.s6,
                OwSpace.s4,
              ),
              child: SectionLabel(l.previewKeys),
            ),
            for (final k in _p.keys) _key(context, k),
          ]),
        ],
        if (_p.passwords + _p.passphrases > 0) ...[
          const SizedBox(height: 16),
          Callout(
            tone: Tone.info,
            padding: const EdgeInsets.all(OwSpace.s6),
            child: Text(l.previewNoPasswords(_p.passwords + _p.passphrases)),
          ),
        ],
      ],
    );
  }

  Widget _box(BuildContext context, List<Widget> children) {
    final ow = context.ow;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: ow.colors.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _item(BuildContext context, ProgramItem i) {
    final l = context.l10n;
    if (i.isGroup) {
      final under = _under(i.id).toList();
      final closed = _closed.contains(i.id);
      return _row(
        context,
        depth: _depth(i),
        value: _state(under),
        onChanged:
            _state(under) == false &&
                under.every((h) => h.existing || h.unsupported != null)
            ? null
            : (_) => _pickAll(under, _state(under) != true),
        title: i.label,
        group: true,
        open: !closed,
        onToggle: () =>
            setState(() => closed ? _closed.remove(i.id) : _closed.add(i.id)),
        trailing: '${under.length}',
        badges: [if (i.existing) l.alreadyImported],
      );
    }
    final open = !i.existing && i.unsupported == null;
    return _row(
      context,
      depth: _depth(i),
      value: open && _picked.contains(i.id),
      onChanged: open ? (v) => _pick(i, v ?? false) : null,
      title: i.label,
      subtitle: i.unsupported != null
          ? l.previewCannotImport(protocolName(i.unsupported!))
          : i.address,
      mono: i.unsupported == null,
      badges: [
        if (i.existing) l.alreadyImported,
        if (!i.existing && i.jumps.isNotEmpty) l.jumpsVia(i.jumps.join(' → ')),
        if (i.tunnels > 0) l.bringsTunnels(i.tunnels),
        for (final t in i.tags) t,
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required int depth,
    required bool? value,
    required ValueChanged<bool?>? onChanged,
    required String title,
    String? subtitle,
    bool mono = false,
    bool header = false,
    bool group = false,
    bool open = true,
    VoidCallback? onToggle,
    String? trailing,
    List<String> badges = const [],
  }) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final enabled = onChanged != null;
    return Container(
      decoration: BoxDecoration(
        color: header ? c.sunken : null,
        border: header ? null : Border(top: BorderSide(color: c.border)),
      ),
      padding: EdgeInsets.only(left: 4.0 + depth * 22, right: OwSpace.s6),
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          if (group)
            IconButton(
              tooltip: open ? l.collapse : l.expand,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(open ? Icons.expand_more : Icons.chevron_right),
              onPressed: onToggle,
            )
          else
            const SizedBox(width: 8),
          Checkbox(
            tristate: header || group,
            value: value,
            onChanged: onChanged,
            semanticLabel: title,
          ),
          if (group)
            Padding(
              padding: const EdgeInsets.only(right: OwSpace.s3),
              child: Icon(Icons.folder_outlined, size: 15, color: c.textSubtle),
            ),
          Flexible(
            flex: 0,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: header || group ? FontWeight.w600 : FontWeight.w500,
                color: enabled || header ? c.text : c.textMuted,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono
                    ? monoStyle(context, size: 12)
                    : TextStyle(fontSize: OwText.small, color: c.textSubtle),
              ),
            ),
          ] else
            const Spacer(),
          for (final b in badges)
            Padding(
              padding: const EdgeInsets.only(left: OwSpace.s3),
              child: Pill(b, tone: PillTone.neutral),
            ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: OwSpace.s4),
              child: Text(trailing, style: monoStyle(context, size: 12)),
            ),
        ],
      ),
    );
  }

  Widget _key(BuildContext context, ProgramKey k) {
    final l = context.l10n;
    final c = context.ow.colors;
    final kind = [k.algorithm, k.fingerprint].whereType<String>().join(' · ');
    final found = k.found;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s6,
        OwSpace.s5,
        OwSpace.s6,
        OwSpace.s5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: OwSpace.s1),
            child: Icon(
              found != null ? Icons.check : Icons.warning_amber_rounded,
              size: 15,
              color: found != null ? c.accentText : c.warn,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: k.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (kind.isNotEmpty)
                        TextSpan(
                          text: '  $kind',
                          style: monoStyle(context, size: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  found != null
                      ? l.previewKeyFound(found)
                      : l.previewKeyMissing(k.usedBy),
                  style: TextStyle(fontSize: OwText.small, color: c.textMuted),
                ),
                if (found == null)
                  Padding(
                    padding: const EdgeInsets.only(top: OwSpace.s2),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _saveKeys.contains(k.id),
                      onChanged: (v) => setState(
                        () => v == true
                            ? _saveKeys.add(k.id)
                            : _saveKeys.remove(k.id),
                      ),
                      title: Text(
                        l.previewSaveKey(k.saveAs),
                        style: const TextStyle(fontSize: OwText.small),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
