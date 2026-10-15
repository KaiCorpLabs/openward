import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The bundled fonts' licenses (OFL-1.1), listed with the packages' ones.
void registerFontLicenses() {
  const fonts = {
    'JetBrains Mono': 'assets/fonts/jetbrains-mono/OFL.txt',
    'IBM Plex': 'assets/fonts/ibm-plex/OFL.txt',
    'Instrument Sans': 'assets/fonts/instrument/OFL-InstrumentSans.txt',
    'Instrument Serif': 'assets/fonts/instrument/OFL-InstrumentSerif.txt',
    'Martian Mono': 'assets/fonts/martian-mono/OFL.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: name, value: path) in fonts.entries) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString(path));
    }
  });
}
