import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings.dart';
import 'home.dart';
import 'terminal/palette.dart';

/// The window chrome matches the terminal's own background in each theme.
ThemeData _theme(Brightness brightness) {
  final terminal = brightness == Brightness.dark
      ? TermPalette.darkTheme
      : TermPalette.lightTheme;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2BB5A0),
    brightness: brightness,
    surface: terminal.background,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    // Hints carry inherited values: dimmer than what is typed.
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

class OpenWardApp extends ConsumerWidget {
  const OpenWardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(settingsProvider.select((s) => s.theme));
    return MaterialApp(
      title: 'OpenWard',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: switch (choice) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light => ThemeMode.light,
      },
      home: const Home(),
    );
  }
}
