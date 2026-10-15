import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings.dart';
import 'home.dart';
import 'l10n/l10n.dart';
import 'ui/themes.dart';

class OpenWardApp extends ConsumerWidget {
  const OpenWardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(settingsProvider.select((s) => s.theme));
    final language = ref.watch(settingsProvider.select((s) => s.language));
    return MaterialApp(
      title: 'OpenWard',
      debugShowCheckedModeBanner: false,
      // As the system is: Papel when it is light, Grafito when dark.
      theme: materialTheme(OwThemes.papel),
      darkTheme: materialTheme(OwThemes.grafito),
      themeMode: switch (choice) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light => ThemeMode.light,
      },
      themeAnimationDuration: Duration.zero,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: switch (language) {
        Language.system => null,
        Language.es => const Locale('es'),
        Language.en => const Locale('en'),
      },
      // A system language other than these two gets English.
      localeListResolutionCallback: (locales, supported) {
        for (final l in locales ?? const <Locale>[]) {
          for (final s in supported) {
            if (s.languageCode == l.languageCode) return s;
          }
        }
        return const Locale('en');
      },
      home: const Home(),
    );
  }
}
