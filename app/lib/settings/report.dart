import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/settings.dart';
import '../core/version.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/app.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// What a problem report carries: versions, the system, the look and how
/// much is saved. Never hosts, addresses, users or keys.
String reportText(WidgetRef ref, AppLocalizations l, String locale) {
  final app = ref.read(openWardProvider);
  final s = ref.read(settingsProvider);
  final library = ref.read(libraryProvider);
  final theme = switch (s.theme) {
    ThemeChoice.light => s.lightTheme,
    ThemeChoice.dark => s.darkTheme,
    ThemeChoice.system => '${s.lightTheme}/${s.darkTheme}',
  };
  return [
    'OpenWard $appVersion (${l.reportCore} ${coreVersion()})',
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion} · '
        '${Abi.current()} · $locale',
    '${l.reportTheme}: $theme (${s.theme.name}) · '
        '${l.reportText} ${(s.textScale * 100).round()} %',
    l.reportCounts(
      library.hosts.length,
      library.groups.length,
      app.tunnels().length,
      app.identities().length,
      app.snippets().length,
    ),
  ].join('\n');
}

/// Shows what a report would copy, and copies it.
Future<void> showReport(BuildContext context, WidgetRef ref) {
  final l = context.l10n;
  final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? '';
  final text = reportText(ref, l, locale);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final ow = context.ow;
      final c = ow.colors;
      return AlertDialog(
        title: Text(l.reportProblem),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.reportWhat, style: TextStyle(color: c.textMuted)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.sunken,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(ow.shape.radius),
                ),
                child: SelectableText(
                  text,
                  style: monoStyle(context, size: 12, color: c.text),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l.reportHow,
                style: TextStyle(fontSize: 12, color: c.textSubtle),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
          FilledButton(
            key: const ValueKey('report.copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text(l.reportCopied)));
            },
            child: Text(l.copyAction),
          ),
        ],
      );
    },
  );
}
