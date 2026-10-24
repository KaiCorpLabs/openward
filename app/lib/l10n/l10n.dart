import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart';

import '../core/settings.dart' show Language;
import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nContext on BuildContext {
  /// The texts in the interface's language.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The texts in the `language` of the settings, where there is no context
/// (a tab's name as it is made): the system's when the app has it, else
/// English, as the app itself picks.
AppLocalizations stringsFor(Language language) {
  final code = switch (language) {
    Language.es => 'es',
    Language.en => 'en',
    Language.system =>
      PlatformDispatcher.instance.locales
          .map((l) => l.languageCode)
          .firstWhere(
            (c) => AppLocalizations.supportedLocales.any(
              (s) => s.languageCode == c,
            ),
            orElse: () => 'en',
          ),
  };
  return lookupAppLocalizations(Locale(code));
}
