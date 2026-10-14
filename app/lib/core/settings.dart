import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Light, dark, or as the system is.
enum ThemeChoice { system, dark, light }

/// How the app looks and behaves on this machine. Not in the vault: these
/// are preferences of the device, not data (ARCHITECTURE §4.1).
@immutable
class Settings {
  const Settings({
    this.fontSize = 13,
    this.theme = ThemeChoice.dark,
    this.optionAsAlt = false,
    this.scrollback = 10000,
  });

  /// Terminal font size, in logical pixels.
  final double fontSize;
  final ThemeChoice theme;

  /// macOS: Option sends Alt (Esc-prefixed keys) instead of typing symbols.
  final bool optionAsAlt;

  /// Lines of history for new terminals.
  final int scrollback;

  static const fontSizes = [
    10.0,
    11.0,
    12.0,
    13.0,
    14.0,
    15.0,
    16.0,
    18.0,
    20.0,
    24.0,
  ];
  static const scrollbacks = [1000, 10000, 50000, 100000];

  Settings copyWith({
    double? fontSize,
    ThemeChoice? theme,
    bool? optionAsAlt,
    int? scrollback,
  }) => Settings(
    fontSize: fontSize ?? this.fontSize,
    theme: theme ?? this.theme,
    optionAsAlt: optionAsAlt ?? this.optionAsAlt,
    scrollback: scrollback ?? this.scrollback,
  );

  Map<String, Object> toJson() => {
    'font_size': fontSize,
    'theme': theme.name,
    'option_as_alt': optionAsAlt,
    'scrollback': scrollback,
  };

  /// Unknown or broken values fall back to the defaults, one by one.
  factory Settings.fromJson(Map<String, Object?> json) {
    const d = Settings();
    final size = json['font_size'];
    final theme = json['theme'];
    final scroll = json['scrollback'];
    return Settings(
      fontSize: size is num && size >= 8 && size <= 40
          ? size.toDouble()
          : d.fontSize,
      theme: ThemeChoice.values.firstWhere(
        (t) => t.name == theme,
        orElse: () => d.theme,
      ),
      optionAsAlt: json['option_as_alt'] is bool
          ? json['option_as_alt']! as bool
          : d.optionAsAlt,
      scrollback: scroll is int && scroll >= 100 && scroll <= 1000000
          ? scroll
          : d.scrollback,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.fontSize == fontSize &&
      other.theme == theme &&
      other.optionAsAlt == optionAsAlt &&
      other.scrollback == scrollback;

  @override
  int get hashCode => Object.hash(fontSize, theme, optionAsAlt, scrollback);
}

/// Where the settings are kept: `settings.json` in the data directory,
/// set in `main` (or by a test).
final settingsFileProvider = Provider<File>(
  (ref) => throw UnimplementedError('override settingsFileProvider'),
);

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final file = ref.read(settingsFileProvider);
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map<String, Object?>) return Settings.fromJson(json);
    } catch (_) {
      // No file yet, or not ours to read: the defaults.
    }
    return const Settings();
  }

  void update(Settings Function(Settings) change) {
    final next = change(state);
    if (next == state) return;
    state = next;
    final file = ref.read(settingsFileProvider);
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(next.toJson()),
      );
    } catch (_) {
      // Kept for this run even if it cannot be saved.
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);
