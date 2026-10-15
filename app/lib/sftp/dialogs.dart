// The browser's questions: what to do with files that exist, permissions,
// a name, and whether to delete.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/sftp.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'files.dart';
import 'format.dart';

/// Asks what to do with each source whose name `dest` already has. `where`
/// names the other side (a host, or this computer). A source left out of
/// the answer is not copied; null cancels them all.
Future<Map<String, ConflictChoice>?> askConflicts(
  BuildContext context, {
  required List<ConflictView> conflicts,
  required int total,
  required String where,
  required String dest,
}) {
  return showDialog<Map<String, ConflictChoice>>(
    context: context,
    builder: (_) => _ConflictDialog(
      conflicts: conflicts,
      total: total,
      where: where,
      dest: dest,
    ),
  );
}

/// What a row suggests: replace what is older, leave the rest; two folders
/// merge, replacing only older files.
ConflictChoice suggestedChoice(ConflictView c) {
  if (c.ours.isDir && c.theirs.isDir) return ConflictChoice.newer;
  if (c.ours.isDir != c.theirs.isDir) return ConflictChoice.skip;
  final ours = c.ours.modified, theirs = c.theirs.modified;
  if (ours != null && theirs != null && ours > theirs) {
    return ConflictChoice.replace;
  }
  return ConflictChoice.skip;
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({
    required this.conflicts,
    required this.total,
    required this.where,
    required this.dest,
  });

  final List<ConflictView> conflicts;
  final int total;
  final String where;
  final String dest;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  late final Map<String, ConflictChoice> _choices = {
    for (final c in widget.conflicts) c.source: suggestedChoice(c),
  };

  void _all(ConflictChoice choice) => setState(() {
    for (final c in widget.conflicts) {
      _choices[c.source] = choice == ConflictChoice.newer
          ? (c.ours.isDir ? ConflictChoice.newer : suggestedChoice(c))
          : choice;
    }
  });

  String _label(AppLocalizations l, ConflictChoice c) => switch (c) {
    ConflictChoice.replace => l.choiceReplace,
    ConflictChoice.skip => l.choiceSkip,
    ConflictChoice.newer => l.choiceNewer,
    ConflictChoice.keepBoth => l.choiceKeepBoth,
  };

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final rest = widget.total - widget.conflicts.length;
    final small = TextStyle(fontSize: 12, color: c.textMuted);
    String side(FileEntry e) => e.isDir
        ? l.conflictFolder
        : '${formatSize(l, e.size)} · ${formatDate(l, e.modified)}';
    (String, Color) verdict(ConflictView v) {
      if (v.ours.isDir && v.theirs.isDir) return (l.conflictMerge, c.textMuted);
      final ours = v.ours.modified, theirs = v.theirs.modified;
      if (ours == null || theirs == null) return ('', c.textMuted);
      if (ours > theirs) return (l.conflictYoursNewer, c.accentText);
      if (ours < theirs) return (l.conflictTheirsNewer(widget.where), c.warn);
      return v.ours.size == v.theirs.size
          ? (l.conflictSame, c.textMuted)
          : ('', c.textMuted);
    }

    Widget header(String text) => Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: c.textSubtle,
      ),
    );
    return AlertDialog(
      title: Text(
        widget.total == 1
            ? l.conflictTitleOne(widget.where)
            : l.conflictTitle(
                widget.conflicts.length,
                widget.total,
                widget.where,
              ),
      ),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: l.conflictIn),
                  TextSpan(
                    text: widget.dest,
                    style: monoStyle(context, color: c.text),
                  ),
                  TextSpan(
                    text: rest > 0 ? l.conflictRest(rest) : l.conflictChoose,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(ow.shape.radius),
              ),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.1),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                  3: FixedColumnWidth(170),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: c.sunken),
                    children: [
                      for (final h in [
                        l.conflictFile,
                        l.conflictYours,
                        l.conflictTheirs(widget.where),
                        l.conflictWhat,
                      ])
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: header(h),
                        ),
                    ],
                  ),
                  for (final v in widget.conflicts)
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: Row(
                            children: [
                              Icon(
                                v.ours.isDir
                                    ? Icons.folder_outlined
                                    : Icons.insert_drive_file_outlined,
                                size: 16,
                                color: c.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  v.ours.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          side(v.ours),
                          style: TextStyle(fontSize: 12, color: c.text),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              side(v.theirs),
                              style: TextStyle(fontSize: 12, color: c.text),
                            ),
                            if (verdict(v).$1.isNotEmpty)
                              Text(
                                verdict(v).$1,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: verdict(v).$2,
                                ),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: DropdownButtonFormField<ConflictChoice>(
                            key: ValueKey('conflict.${v.ours.name}'),
                            initialValue: _choices[v.source],
                            isDense: true,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            items: [
                              for (final choice in ConflictChoice.values)
                                if (choice != ConflictChoice.newer ||
                                    v.ours.isDir)
                                  DropdownMenuItem(
                                    value: choice,
                                    child: Text(
                                      _label(l, choice),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                            ],
                            onChanged: (choice) =>
                                setState(() => _choices[v.source] = choice!),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l.forAll, style: small),
                for (final choice in ConflictChoice.values)
                  OutlinedButton(
                    onPressed: () => _all(choice),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text(_label(l, choice)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Callout(
              tone: Tone.info,
              child: Text(
                l.partNote,
                style: const TextStyle(fontSize: 12, height: 1.45),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          // Only these are left out; the rest are copied.
          onPressed: () => Navigator.pop(context, <String, ConflictChoice>{}),
          child: Text(l.cancelThese(widget.conflicts.length)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _choices),
          child: Text(l.continueAction),
        ),
      ],
    );
  }
}

/// The permission bits of `entry`, to change; for a folder, also of what
/// it holds. Returns how many entries changed, or null if nothing did.
Future<int?> showPermissions(
  BuildContext context, {
  required FileEntry entry,
  required String path,
  required FileSystem fs,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _PermissionsDialog(entry: entry, path: path, fs: fs),
  );
}

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({
    required this.entry,
    required this.path,
    required this.fs,
  });

  final FileEntry entry;
  final String path;
  final FileSystem fs;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late int _mode = (widget.entry.mode ?? 0x1a4) & 0x1ff;
  late final _octal = TextEditingController(text: octal(_mode));
  bool _recursive = false;
  bool _busy = false;
  String? _error;

  void _set(int mode) => setState(() {
    _mode = mode & 0x1ff;
    final text = octal(_mode);
    if (_octal.text != text) {
      _octal.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  });

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await widget.fs.chmod(
        widget.path,
        _mode,
        recursive: _recursive,
      );
      if (mounted) Navigator.pop(context, n);
    } on FileError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = fileErrorText(context.l10n, e);
      });
    }
  }

  @override
  void dispose() {
    _octal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final e = widget.entry;
    final dir = e.isDir;
    final before = (e.mode ?? 0) & 0x1ff;
    Widget bit(int mask) => Checkbox(
      value: _mode & mask != 0,
      onChanged: (v) => _set(v == true ? _mode | mask : _mode & ~mask),
    );
    TableRow row(String who, String? name, int shift) => TableRow(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: who,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (name != null) ...[
                  const TextSpan(text: '  '),
                  TextSpan(text: name, style: monoStyle(context, size: 12)),
                ],
              ],
            ),
          ),
        ),
        Center(child: bit(4 << shift)),
        Center(child: bit(2 << shift)),
        Center(child: bit(1 << shift)),
      ],
    );
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: c.textSubtle,
    );
    return AlertDialog(
      icon: Icon(
        dir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
        color: c.textMuted,
      ),
      title: Text(l.permissionsOf(e.name)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(ow.shape.radius),
              ),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(),
                  1: FixedColumnWidth(76),
                  2: FixedColumnWidth(76),
                  3: FixedColumnWidth(76),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: c.sunken),
                    children: [
                      const SizedBox(),
                      for (final h in [
                        l.permRead,
                        l.permWrite,
                        dir ? l.permEnter : l.permExecute,
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            h.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: head,
                          ),
                        ),
                    ],
                  ),
                  row(l.permOwner, e.owner, 6),
                  row(l.permGroup, e.group, 3),
                  row(l.permOthers, null, 0),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(l.permOctal, style: TextStyle(color: c.textMuted)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 72,
                  child: TextField(
                    key: const ValueKey('perm.octal'),
                    controller: _octal,
                    style: monoStyle(context, size: 14, color: c.text),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-7]')),
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) {
                      if (v.length == 3) _set(int.parse(v, radix: 8));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text(formatMode(_mode), style: monoStyle(context, size: 12)),
                const Spacer(),
                if (e.mode != null)
                  Text(
                    l.permBefore(octal(before)),
                    style: TextStyle(fontSize: 12, color: c.textSubtle),
                  ),
              ],
            ),
            if (dir) ...[
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _recursive,
                onChanged: (v) => setState(() => _recursive = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.permRecursive),
                subtitle: Text(l.permRecursiveNote),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              l.permOwnerNote,
              style: TextStyle(fontSize: 12, color: c.textSubtle),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.danger)),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _apply, child: Text(l.apply)),
      ],
    );
  }
}

/// A name for a new folder, or a new name for `initial`. Null if cancelled.
Future<String?> askName(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, action: action, initial: initial),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      // Without the extension, as in the Finder.
      extentOffset: widget.initial.lastIndexOf('.') > 0
          ? widget.initial.lastIndexOf('.')
          : widget.initial.length,
    );

  String? get _problem {
    final name = _text.text.trim();
    if (name.isEmpty || name == '.' || name == '..') return '';
    if (name.contains('/')) return context.l10n.nameNoSlash;
    return null;
  }

  void _done() {
    if (_problem != null) return;
    Navigator.pop(context, _text.text.trim());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final problem = _problem;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          key: const ValueKey('name.field'),
          controller: _text,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _done(),
          decoration: InputDecoration(
            labelText: l.name,
            errorText: problem == null || problem.isEmpty ? null : problem,
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: problem == null ? _done : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Asks before deleting; `host` is null on this computer.
Future<bool> confirmDelete(
  BuildContext context, {
  required List<FileEntry> entries,
  String? host,
}) async {
  final l = context.l10n;
  final c = context.ow.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.delete_outline, color: c.danger),
      title: Text(
        entries.length == 1
            ? l.deleteOne(entries.first.name)
            : l.deleteMany(entries.length),
      ),
      content: SizedBox(
        width: 440,
        child: Text(
          host == null ? l.deleteLocalBody : l.deleteRemoteBody(host),
          style: const TextStyle(height: 1.45),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.danger,
            foregroundColor: c.surface,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A file error in words.
String fileErrorText(AppLocalizations l, FileError e) => switch (e.kind) {
  FileErrorKind.notFound => l.fileNotFound(e.path),
  FileErrorKind.denied => l.fileDenied(e.path),
  FileErrorKind.exists => l.fileExists(e.path),
  FileErrorKind.lost => l.fileLost,
  FileErrorKind.changed => l.fileChanged(e.path),
  FileErrorKind.other => e.message,
};
