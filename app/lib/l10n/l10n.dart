import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nContext on BuildContext {
  /// The texts in the interface's language.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
