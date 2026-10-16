import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../snippets/snippets.dart';
import '../src/rust/api/programs.dart';
import '../tunnels/tunnels.dart';
import 'program_preview.dart';
import 'program_report.dart';
import 'termius_consent.dart';

String programName(ProgramKind p) => switch (p) {
  ProgramKind.termius => 'Termius',
  ProgramKind.putty => 'PuTTY',
  ProgramKind.kitty => 'KiTTY',
  ProgramKind.mobaXterm => 'MobaXterm',
  ProgramKind.tabby => 'Tabby',
  ProgramKind.secureCrt => 'SecureCRT',
};

/// Reads another program's file or folder (Termius after saying what will
/// happen), shows what it has, and imports what the user picks.
Future<void> importFromProgram(
  BuildContext context,
  ProviderContainer container, {
  required String path,
  ProgramKind? program,
}) async {
  // The window's navigator: the page that started this (the first-run
  // guide, say) may be gone by the end.
  context = Navigator.of(context, rootNavigator: true).context;
  final l = context.l10n;
  if (program == ProgramKind.termius && !await confirmTermius(context)) {
    return;
  }
  if (!context.mounted) return;
  final app = container.read(openWardProvider);
  final key = container.read(termiusKeyProvider);
  final read = await withProgress(
    context,
    program == null ? l.readingFile : l.readingProgram(programName(program)),
    key == null
        ? app.readProgram(path: path)
        : app.readProgramWithKey(path: path, termiusKey: key),
  );
  if (!context.mounted) return;
  final data = read.data;
  if (data == null) {
    await showReadFailure(context, read.failure!);
    return;
  }
  final preview = app.previewProgram(data: data);
  final choice = await showProgramPreview(context, preview);
  if (choice == null || !context.mounted) return;
  final ProgramReport report;
  try {
    report = await app.importProgram(data: data, choice: choice);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.importFailed('$e'))));
    }
    return;
  }
  container.read(libraryProvider.notifier).refresh();
  container.read(snippetsProvider.notifier).refresh();
  container.read(tunnelBoardProvider).refresh();
  if (!context.mounted) return;
  await showProgramReport(context, preview, report, choice.groupName);
}

/// Runs `future` behind a dialog that says what is going on.
Future<T> withProgress<T>(
  BuildContext context,
  String text,
  Future<T> future,
) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Flexible(child: Text(text)),
          ],
        ),
      ),
    ),
  );
  try {
    return await future;
  } finally {
    nav.pop();
  }
}

String readFailureText(AppLocalizations l, ReadFailure f) {
  final program = f.program == null ? '' : programName(f.program!);
  return switch (f.kind) {
    ReadFailureKind.notRecognized => l.readNotRecognized,
    ReadFailureKind.unreadable => l.readUnreadable(f.message),
    ReadFailureKind.format => l.readFormat(program, f.message),
    ReadFailureKind.termiusNotFound => l.readTermiusNotFound,
    ReadFailureKind.termiusKeychain => l.readTermiusKeychain,
    ReadFailureKind.termiusNoKey => l.readTermiusNoKey,
    ReadFailureKind.termiusWrongKey => l.readTermiusWrongKey,
  };
}

Future<void> showReadFailure(BuildContext context, ReadFailure f) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.readFailedTitle),
      content: SizedBox(width: 460, child: Text(readFailureText(l, f))),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.ok),
        ),
      ],
    ),
  );
}

/// What a host that cannot come uses, as people call it.
String protocolName(String p) => switch (p) {
  'telnet' => 'Telnet',
  'mosh' => 'Mosh',
  'serial' => 'Serial',
  'rdp' ||
  'vnc' ||
  'ftp' ||
  'sftp' ||
  'rsh' ||
  'xdmcp' ||
  'wsl' => p.toUpperCase(),
  'aws s3' => 'AWS S3',
  _ => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1),
};

/// The core names what did not come in English; the common ones here in
/// the user's language.
String featureName(AppLocalizations l, String what) {
  final known = switch (what) {
    'X11 forwarding' => l.featureX11,
    'SOCKS4 proxy' => l.featureSocks4,
    'telnet proxy' => l.featureTelnetProxy,
    'hardware key' => l.featureHardwareKey,
    "a key in Tabby's vault" => l.featureTabbyVault,
    "SecureCRT's global key" => l.featureSecureCrtGlobalKey,
    'a stored MobaXterm credential' => l.featureMobaCredential,
    'a jump through a profile that is not SSH' => l.featureJumpNotSsh,
    _ => null,
  };
  if (known != null) return known;
  const through = 'a jump through ';
  if (what.startsWith(through)) {
    return l.featureJumpThrough(what.substring(through.length));
  }
  const firewall = "SecureCRT's firewall ";
  if (what.startsWith(firewall)) {
    return l.featureFirewall(what.substring(firewall.length));
  }
  final proxy = RegExp(r'^(?:a |proxy type )?(.+?)(?: proxy)?$')
      .firstMatch(what);
  if (what.contains('proxy') && proxy != null) {
    return l.featureProxy(proxy.group(1)!);
  }
  return what;
}

String warningText(AppLocalizations l, ProgramWarning w) {
  final who = w.subject ?? '';
  return switch (w.kind) {
    ProgramWarningKind.mosh => l.warnMosh(who),
    ProgramWarningKind.startupCommand => l.warnStartupCommand(who),
    ProgramWarningKind.unsupported =>
      who.isEmpty
          ? l.warnFeatureGeneral(featureName(l, w.detail))
          : l.warnFeature(who, featureName(l, w.detail)),
    ProgramWarningKind.badValue => () {
      final i = w.detail.indexOf('=');
      return l.warnValue(
        who,
        i < 0 ? w.detail : w.detail.substring(0, i),
        i < 0 ? '' : w.detail.substring(i + 1),
      );
    }(),
    ProgramWarningKind.shared => l.warnShared(int.tryParse(w.detail) ?? 0),
    ProgramWarningKind.hostChain => l.warnHostChain,
    ProgramWarningKind.unreadable => l.warnPartlyUnreadable(w.detail),
  };
}
