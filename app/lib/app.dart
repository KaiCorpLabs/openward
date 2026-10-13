import 'package:flutter/material.dart';

import 'home.dart';

/// Dark by default, close to the terminal's own background; the light theme
/// and the choice come with settings (A5).
class OpenWardApp extends StatelessWidget {
  const OpenWardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2BB5A0),
      brightness: Brightness.dark,
      surface: const Color(0xFF16181D),
    );
    return MaterialApp(
      title: 'OpenWard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
      ),
      home: const Home(),
    );
  }
}
