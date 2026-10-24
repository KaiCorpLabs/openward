import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The bundled fonts' licenses (OFL-1.1), by family: one for every folder
/// of `assets/fonts` (a test checks).
const bundledFonts = {
  'JetBrains Mono': 'assets/fonts/jetbrains-mono/OFL.txt',
  'IBM Plex': 'assets/fonts/ibm-plex/OFL.txt',
  'Instrument Sans': 'assets/fonts/instrument/OFL-InstrumentSans.txt',
  'Instrument Serif': 'assets/fonts/instrument/OFL-InstrumentSerif.txt',
  'Martian Mono': 'assets/fonts/martian-mono/OFL.txt',
  'Share Tech Mono': 'assets/fonts/share-tech-mono/OFL.txt',
  'VT323': 'assets/fonts/vt323/OFL.txt',
};

/// The core's: its crates and libghostty-vt with what it builds in, as
/// `tool/licenses.sh` writes them.
const coreLicenses = 'assets/licenses/core.json';

/// What the app bundles besides the Dart packages, which Flutter lists by
/// itself: the fonts, and the core.
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: name, value: path) in bundledFonts.entries) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString(path));
    }
    final core = jsonDecode(await rootBundle.loadString(coreLicenses)) as List;
    for (final e in core.cast<Map<String, Object?>>()) {
      yield LicenseEntryWithLineBreaks(
        (e['packages']! as List).cast<String>(),
        e['text']! as String,
      );
    }
  });
}
