import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Shows what `~/.ssh/config` has, lets the user pick, imports that, and
/// says what did not carry over.
Future<void> importSshConfig(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final app = ref.read(openWardProvider);
  final file = ref.read(sshConfigFileProvider);
  final previews = await app.previewSshConfig(file: file);
  if (!context.mounted) return;
  final only = await showDialog<List<String>>(
    context: context,
    builder: (context) => _PickDialog(previews: previews),
  );
  if (only == null || only.isEmpty || !context.mounted) return;
  final ImportReport report;
  try {
    report = await app.importSshConfig(file: file, only: only);
  } catch (e) {
    if (context.mounted) {
      showErrorNotice(
        ScaffoldMessenger.of(context),
        l.importFailed(errorReason(l, e)),
        e,
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showImportReport(context, report);
}

/// What came in; a dialog only when something did not.
Future<void> showImportReport(BuildContext context, ImportReport report) {
  final l = context.l10n;
  if (report.warnings.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(reportSummary(l, report))));
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    builder: (context) => _ReportDialog(report: report),
  );
}

String reportSummary(AppLocalizations l, ImportReport r) {
  final parts = [
    if (r.created > 0) l.reportCreated(r.created),
    if (r.tunnels > 0) l.reportTunnels(r.tunnels),
    if (r.skipped > 0) l.reportSkipped(r.skipped),
  ];
  return parts.isEmpty
      ? l.importNothing
      : '${parts.join('; ')}. ${l.reportWhere}';
}

String _warning(AppLocalizations l, ImportWarning w) {
  final at = w.line > 0 ? ' (${_short(w.file)}:${w.line})' : '';
  return switch (w.kind) {
    ImportWarningKind.unsupported => l.warnUnsupported(w.subject, at),
    ImportWarningKind.match => l.warnMatch(at),
    ImportWarningKind.badValue => l.warnBadValue(w.subject, at, w.detail),
    ImportWarningKind.stricter => l.warnStricter(at),
    ImportWarningKind.includeTooDeep => l.warnIncludeTooDeep(at),
    ImportWarningKind.unreadable => l.warnUnreadable(_short(w.file)),
    ImportWarningKind.denied => l.warnDenied(_short(w.file)),
    ImportWarningKind.jumpLossy => l.warnJumpLossy(w.subject, w.detail),
  };
}

String _short(String path) {
  final i = path.lastIndexOf('/.ssh/');
  return i < 0 ? path : '~${path.substring(i)}';
}

/// The hosts of a `~/.ssh/config` to pick from. Picking a host picks the
/// hosts it jumps through; leaving one out leaves out the hosts that need
/// it. Hosts imported before are shown but cannot be picked.
class ImportPicker extends StatefulWidget {
  const ImportPicker({
    super.key,
    required this.previews,
    required this.onChanged,
  });

  final List<ImportPreview> previews;

  /// The aliases picked, after every change (and once at the start).
  final ValueChanged<List<String>> onChanged;

  @override
  State<ImportPicker> createState() => _ImportPickerState();
}

class _ImportPickerState extends State<ImportPicker> {
  late final Set<String> _picked = {for (final p in _new) p.alias};
  bool _all = false;

  /// What can be picked: new hosts, and hosts imported before that bring
  /// tunnels they did not have.
  Iterable<ImportPreview> get _new => widget.previews.where(_pickable);

  bool _pickable(ImportPreview p) => !p.existing || p.tunnels > 0;

  ImportPreview? _find(String alias) =>
      widget.previews.where((p) => p.alias == alias).firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onChanged(_picked.toList()),
    );
  }

  void _pick(ImportPreview p, bool on) {
    setState(() {
      if (on) {
        // And what it jumps through, all the way.
        final queue = [p];
        while (queue.isNotEmpty) {
          final next = queue.removeLast();
          if ((next.existing && !identical(next, p)) ||
              !_picked.add(next.alias)) {
            continue;
          }
          queue.addAll(next.jumps.map(_find).whereType<ImportPreview>());
        }
      } else {
        // And whatever jumps through it.
        final queue = [p.alias];
        while (queue.isNotEmpty) {
          final gone = queue.removeLast();
          _picked.remove(gone);
          for (final other in widget.previews) {
            if (_picked.contains(other.alias) && other.jumps.contains(gone)) {
              queue.add(other.alias);
            }
          }
        }
      }
    });
    widget.onChanged(_picked.toList());
  }

  void _pickAll(bool on) {
    setState(() {
      _picked.clear();
      if (on) _picked.addAll(_new.map((p) => p.alias));
    });
    widget.onChanged(_picked.toList());
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final fresh = _new.length;
    final shown = _all ? widget.previews : widget.previews.take(6).toList();
    final rest = widget.previews.length - shown.length;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: c.sunken,
            child: CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _picked.isEmpty
                  ? false
                  : _picked.length == fresh
                  ? true
                  : null,
              tristate: true,
              onChanged: fresh == 0
                  ? null
                  : (_) => _pickAll(_picked.length != fresh),
              title: Text(
                l.selectAll,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              secondary: Text(
                l.selectedOf(_picked.length, fresh),
                style: TextStyle(color: c.textMuted),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [for (final p in shown) _row(context, p)],
            ),
          ),
          if (rest > 0)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: TextButton.icon(
                onPressed: () => setState(() => _all = true),
                icon: const Icon(Icons.expand_more, size: 16),
                label: Text(l.showRest(rest)),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(38),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ImportPreview p) {
    final c = context.ow.colors;
    final l = context.l10n;
    final where = [
      if (p.user != null) '${p.user}@',
      p.address,
      if (p.port != null && p.port != 22) ':${p.port}',
    ].join();
    final notes = [
      if (p.existing) l.alreadyImported,
      if (!p.existing && p.jumps.isNotEmpty) l.jumpsVia(p.jumps.join(' → ')),
      if (p.tunnels > 0) l.bringsTunnels(p.tunnels),
    ];
    final note = notes.isEmpty ? null : notes.join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: CheckboxListTile(
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: _pickable(p) && _picked.contains(p.alias),
        onChanged: _pickable(p) ? (v) => _pick(p, v ?? false) : null,
        title: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(
                p.alias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _pickable(p) ? c.text : c.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                where,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context),
              ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  note,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickDialog extends StatefulWidget {
  const _PickDialog({required this.previews});

  final List<ImportPreview> previews;

  @override
  State<_PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<_PickDialog> {
  List<String> _only = const [];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final empty = widget.previews.isEmpty;
    return AlertDialog(
      title: Text(l.importTitle),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              empty
                  ? l.importNothing
                  : '${l.importFound(widget.previews.length)} ${l.importKeepsFile}',
              style: TextStyle(color: c.textMuted, height: 1.45),
            ),
            if (!empty) ...[
              const SizedBox(height: 14),
              Flexible(
                child: ImportPicker(
                  previews: widget.previews,
                  onChanged: (only) => setState(() => _only = only),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l.importIntoGroup,
                style: TextStyle(fontSize: 12, color: c.textSubtle),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(empty ? l.close : l.cancel),
        ),
        if (!empty)
          FilledButton(
            onPressed: _only.isEmpty
                ? null
                : () => Navigator.pop(context, _only),
            child: Text(l.importN(_only.length)),
          ),
      ],
    );
  }
}

class _ReportDialog extends StatelessWidget {
  const _ReportDialog({required this.report});

  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.importTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reportSummary(l, report)),
            const SizedBox(height: 16),
            Text(l.reportNotEverything, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final w in report.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${_warning(l, w)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.ok),
        ),
      ],
    );
  }
}
