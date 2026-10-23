import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../hosts/import_ssh_config.dart';
import '../identities/identities.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/programs.dart';
import '../src/rust/api/vault.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'programs.dart';

/// «Import…»: from what is on this computer (Termius, `~/.ssh/config`,
/// Tabby…) or from a file another program exported; a file or folder can
/// also be dropped on it.
Future<void> showImport(
  BuildContext context,
  WidgetRef ref, {
  bool sshConfig = true,
}) async {
  final container = ProviderScope.containerOf(context);
  final app = container.read(openWardProvider);
  final found = await app.installedPrograms();
  final ssh = sshConfig
      ? await app.previewSshConfig(file: container.read(sshConfigFileProvider))
      : <ImportPreview>[];
  if (!context.mounted) return;
  final pick = await showDialog<ImportSource>(
    context: context,
    builder: (_) => _Origin(found: found, sshConfig: ssh),
  );
  if (pick == null || !context.mounted) return;
  await runImport(context, ref, pick);
}

/// Where to import from: `~/.ssh/config`, or a program's file or folder.
sealed class ImportSource {
  const ImportSource();
}

class SshConfigSource extends ImportSource {
  const SshConfigSource();
}

class ProgramSource extends ImportSource {
  const ProgramSource(this.path, [this.program]);

  final String path;

  /// Known when found on this computer; otherwise recognized on reading.
  final ProgramKind? program;
}

Future<void> runImport(
  BuildContext context,
  WidgetRef ref,
  ImportSource source,
) async {
  switch (source) {
    case SshConfigSource():
      await importSshConfig(context, ref);
    case ProgramSource(:final path, :final program):
      await importFromProgram(
        context,
        ProviderScope.containerOf(context),
        path: path,
        program: program,
      );
  }
}

/// A square with the program's initial: never the other program's logo.
class ProgramTile extends StatelessWidget {
  const ProgramTile(this.text, {super.key, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    return ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent ? c.accentSoft : c.sunken,
          borderRadius: BorderRadius.circular(ow.shape.radius),
          border: Border.all(color: c.border),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: accent ? c.accentText : c.text,
          ),
        ),
      ),
    );
  }
}

String programInitial(ProgramKind p) => switch (p) {
  ProgramKind.tabby => 'Ta',
  ProgramKind.kitty => 'K',
  _ => programName(p)[0],
};

/// What is on this computer, in a few words.
String foundText(AppLocalizations l, FoundProgram f) => switch (f.program) {
  ProgramKind.termius => l.foundTermius,
  ProgramKind.tabby => l.foundTabby(tildePath(f.path)),
  ProgramKind.putty || ProgramKind.kitty => l.foundSessions(tildePath(f.path)),
  ProgramKind.secureCrt => l.foundSessions(tildePath(f.path)),
  ProgramKind.mobaXterm => l.foundMobaXterm(tildePath(f.path)),
  ProgramKind.csv => tildePath(f.path),
};

class _Origin extends StatefulWidget {
  const _Origin({required this.found, required this.sshConfig});

  final List<FoundProgram> found;
  final List<ImportPreview> sshConfig;

  @override
  State<_Origin> createState() => _OriginState();
}

class _OriginState extends State<_Origin> {
  bool _dropping = false;

  Future<void> _choose(String label, List<String> extensions) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: extensions),
        const XTypeGroup(label: '*'),
      ],
    );
    if (file != null && mounted) {
      Navigator.pop(context, ProgramSource(file.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final ssh = widget.sshConfig;
    final existing = ssh.where((p) => p.existing).length;
    Widget row(Widget tile, String title, String sub, Widget action) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          tile,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 12, color: c.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
    final installed = [
      for (final f in widget.found)
        row(
          ProgramTile(programInitial(f.program)),
          programName(f.program),
          foundText(l, f),
          f.program == ProgramKind.termius
              ? FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, ProgramSource(f.path, f.program)),
                  child: Text(l.readTermius),
                )
              : OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, ProgramSource(f.path, f.program)),
                  child: Text(l.review),
                ),
        ),
      if (ssh.isNotEmpty)
        row(
          const ProgramTile('~', accent: true),
          '~/.ssh/config',
          l.foundSshConfig(ssh.length, existing),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, const SshConfigSource()),
            child: Text(l.review),
          ),
        ),
    ];
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.importIntro, style: TextStyle(color: c.textMuted)),
        if (installed.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionLabel(l.onThisComputer),
          ...installed,
        ],
        const SizedBox(height: 14),
        SectionLabel(l.fromExportedFile),
        row(
          const ProgramTile('P'),
          'PuTTY · KiTTY',
          l.howPutty,
          OutlinedButton(
            onPressed: () => _choose('PuTTY', ['reg']),
            child: Text(l.chooseFile),
          ),
        ),
        row(
          const ProgramTile('M'),
          'MobaXterm',
          l.howMobaXterm,
          OutlinedButton(
            onPressed: () => _choose('MobaXterm', ['mxtsessions', 'ini']),
            child: Text(l.chooseFile),
          ),
        ),
        row(
          const ProgramTile('S'),
          'SecureCRT',
          l.howSecureCrt,
          OutlinedButton(
            onPressed: () => _choose('SecureCRT', ['xml']),
            child: Text(l.chooseFile),
          ),
        ),
        row(
          const ProgramTile('Ta'),
          'Tabby',
          l.howTabby,
          OutlinedButton(
            onPressed: () => _choose('Tabby', ['yaml', 'yml']),
            child: Text(l.chooseFile),
          ),
        ),
        row(
          const ProgramTile('CSV'),
          l.csvSpreadsheet,
          l.howCsv,
          OutlinedButton(
            key: const ValueKey('import.csv'),
            onPressed: () => _choose('CSV', ['csv', 'tsv', 'txt']),
            child: Text(l.chooseFile),
          ),
        ),
        const SizedBox(height: 8),
        DropTarget(
          onDragEntered: (_) => setState(() => _dropping = true),
          onDragExited: (_) => setState(() => _dropping = false),
          onDragDone: (d) {
            setState(() => _dropping = false);
            if (d.files.isNotEmpty) {
              Navigator.pop(context, ProgramSource(d.files.first.path));
            }
          },
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _dropping ? c.accentSoft : null,
              border: Border.all(color: _dropping ? c.accent : c.control),
              borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.file_download_outlined,
                  size: 16,
                  color: c.textSubtle,
                ),
                const SizedBox(width: 8),
                Text(
                  l.dropToImport,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return AlertDialog(
      title: Text(l.importHostsTitle),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(child: content),
      ),
      actions: [
        Row(
          children: [
            Icon(Icons.lock_outline, size: 14, color: c.textSubtle),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l.passwordsNever,
                style: TextStyle(fontSize: 12, color: c.textSubtle),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.close),
            ),
          ],
        ),
      ],
    );
  }
}
