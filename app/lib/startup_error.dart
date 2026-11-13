import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/errors.dart';
import 'core/platform.dart';
import 'core/settings.dart';
import 'l10n/l10n.dart';
import 'src/rust/api/vault.dart' show VaultErrorKind;
import 'ui/themes.dart';
import 'ui/tokens.dart';
import 'ui/widgets.dart';

/// The window when OpenWard cannot open its data: a vault written by a
/// newer version (after going back to an older beta), a folder without
/// permission, a damaged file. Nothing is touched; the user can look at the
/// folder or quit.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
    required this.dataDir,
  });

  /// What opening threw: its kind picks the words, its text goes to
  /// «Detalles».
  final Object error;
  final String dataDir;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenWard',
      debugShowCheckedModeBanner: false,
      theme: materialTheme(resolveTheme(const Settings(), Brightness.light)),
      darkTheme: materialTheme(resolveTheme(const Settings(), Brightness.dark)),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (locales, supported) {
        for (final l in locales ?? const <Locale>[]) {
          for (final s in supported) {
            if (s.languageCode == l.languageCode) return s;
          }
        }
        return const Locale('en');
      },
      home: _StartupError(error: error, dataDir: dataDir),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.dataDir});

  final Object error;
  final String dataDir;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OwSpace.s16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 32, color: ow.colors.warn),
                const SizedBox(height: 12),
                Text(l.startupErrorTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  isVaultError(error, VaultErrorKind.newerFormat)
                      ? l.startupNewerBody(dataDir)
                      : isVaultError(error, VaultErrorKind.openElsewhere)
                      ? l.startupElsewhereBody(dataDir)
                      : l.startupErrorBody(dataDir),
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 16),
                Text(
                  l.startupErrorDetails,
                  style: TextStyle(
                    fontSize: OwText.small,
                    color: ow.colors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(OwSpace.s5),
                  decoration: BoxDecoration(
                    color: ow.colors.sunken,
                    borderRadius: BorderRadius.circular(ow.shape.radius),
                  ),
                  child: SelectableText(
                    errorDetails(error),
                    style: monoStyle(context),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => exit(1),
                      child: Text(l.startupQuit),
                    ),
                    // A phone's data folder is the app's own: nothing
                    // opens it.
                    if (Device.runsPrograms) ...[
                      const SizedBox(width: 8),
                      FilledButton(
                        autofocus: true,
                        onPressed: () => launchUrl(Uri.directory(dataDir)),
                        child: Text(l.startupShowFolder),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
