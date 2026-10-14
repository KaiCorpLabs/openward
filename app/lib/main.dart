import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/settings.dart';
import 'src/rust/api/app.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // OPENWARD_DATA: another data directory, to try things without touching
  // the real one.
  final dir =
      Platform.environment['OPENWARD_DATA'] ??
      (await getApplicationSupportDirectory()).path;
  final app = await OpenWard.open(dataDir: dir);
  runApp(
    ProviderScope(
      overrides: [
        openWardProvider.overrideWithValue(app),
        settingsFileProvider.overrideWithValue(File('$dir/settings.json')),
      ],
      child: const OpenWardApp(),
    ),
  );
}
