import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings.dart';
import 'home.dart';
import 'l10n/l10n.dart';
import 'ui/themes.dart';

/// The light and dark themes as the settings make them. Made again only
/// when what they come from changes: a new theme rebuilds everything under
/// it, terminals included, and most settings (the sidebar, ⌘B) have nothing
/// to do with it.
final materialThemesProvider = Provider<({ThemeData light, ThemeData dark})>((
  ref,
) {
  ref.watch(
    settingsProvider.select(
      (s) => (s.lightTheme, s.darkTheme, s.overrides, s.schemes),
    ),
  );
  final s = ref.read(settingsProvider);
  return (
    light: materialTheme(resolveTheme(s, Brightness.light)),
    dark: materialTheme(resolveTheme(s, Brightness.dark)),
  );
});

class OpenWardApp extends ConsumerWidget {
  const OpenWardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final choice = settings.theme;
    final language = settings.language;
    final themes = ref.watch(materialThemesProvider);
    return MaterialApp(
      title: 'OpenWard',
      debugShowCheckedModeBanner: false,
      // The themes chosen for light and for dark, with their layers.
      theme: themes.light,
      darkTheme: themes.dark,
      // Text size and fewer animations on top of what the system says.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(
              mq.textScaler.scale(1) * settings.textScale,
            ),
            disableAnimations: switch (settings.motion) {
              MotionChoice.system => mq.disableAnimations,
              MotionChoice.reduce => true,
              MotionChoice.full => false,
            },
          ),
          child: child!,
        );
      },
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
