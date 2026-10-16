import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/programs.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'programs.dart';

/// What came in, and what to look at: keys that did not, hosts that
/// cannot come, settings left out.
Future<void> showProgramReport(
  BuildContext context,
  ProgramPreview preview,
  ProgramReport report,
  String groupName,
) => showDialog<void>(
  context: context,
  builder: (context) =>
      _Report(preview: preview, report: report, groupName: groupName),
);

/// The things to look at, as lines.
List<String> reportChecks(
  AppLocalizations l,
  ProgramPreview preview,
  ProgramReport report,
) => [
  for (final label in report.withoutKey) l.checkWithoutKey(label),
  for (final i in preview.items)
    if (!i.isGroup && i.unsupported != null)
      l.checkNotImported(i.label, protocolName(i.unsupported!)),
  for (final w in report.warnings) warningText(l, w),
];

class _Report extends StatelessWidget {
  const _Report({
    required this.preview,
    required this.report,
    required this.groupName,
  });

  final ProgramPreview preview;
  final ProgramReport report;
  final String groupName;

  List<(IconData, String)> _lines(AppLocalizations l) {
    final r = report;
    return [
      if (r.groups > 0) (Icons.folder_outlined, l.madeGroups(r.groups)),
      if (r.identities > 0)
        (Icons.badge_outlined, l.madeIdentities(r.identities)),
      if (r.tunnels > 0) (Icons.swap_horiz, l.madeTunnels(r.tunnels)),
      if (r.snippets > 0) (Icons.terminal, l.madeSnippets(r.snippets)),
      if (r.knownHosts > 0)
        (Icons.verified_user_outlined, l.madeKnownHosts(r.knownHosts)),
      for (final path in r.savedKeys) (Icons.key_outlined, l.madeKey(path)),
      if (r.skipped > 0) (Icons.history, l.madeSkipped(r.skipped)),
    ];
  }

  String _text(AppLocalizations l) {
    final checks = reportChecks(l, preview, report);
    return [
      _title(l),
      for (final (_, line) in _lines(l)) '- $line',
      if (checks.isNotEmpty) ...[
        '',
        l.checkTitle(checks.length),
        for (final c in checks) '- $c',
      ],
    ].join('\n');
  }

  String _title(AppLocalizations l) =>
      l.reportTitle(report.hosts, programName(preview.program));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final checks = reportChecks(l, preview, report);
    final group = preview.group ?? groupName;
    return AlertDialog(
      title: Text(_title(l)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (report.hosts > 0)
                Text(
                  l.reportWhere2(group),
                  style: TextStyle(color: c.textMuted),
                ),
              const SizedBox(height: 10),
              for (final (icon, line) in _lines(l))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 15, color: c.accentText),
                      const SizedBox(width: 10),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
              if (checks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Callout(
                  tone: Tone.warn,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.checkTitle(checks.length),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      for (final check in checks)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '• $check',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Callout(
                tone: Tone.info,
                padding: const EdgeInsets.all(12),
                child: Text(
                  l.reimportNote,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _text(l)));
            ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: Text(l.importReportCopied)));
          },
          child: Text(l.copyReport),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: Text(l.ok),
        ),
      ],
    );
  }
}
