import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/errors.dart';
import 'core/fonts.dart';
import 'core/providers.dart';
import 'core/settings.dart';
import 'sftp/remote_edit.dart';
import 'src/rust/api/app.dart';
import 'src/rust/frb_generated.dart';
import 'startup_error.dart';
import 'ui/focus_ring.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeyboardMode.watch();
  registerLicenses();
  // OPENWARD_DATA: another data directory, to try things without touching
  // the real one.
  final dir =
      Platform.environment['OPENWARD_DATA'] ??
      (await getApplicationSupportDirectory()).path;
  final OpenWard app;
  try {
    await RustLib.init();
    app = await OpenWard.open(dataDir: dir);
  } catch (e) {
    // Rather than an empty window: what happened, and where the data is.
    return runApp(StartupErrorApp(error: e, dataDir: dir));
  }
  PlatformDispatcher.instance.onError = reportUncaught;
  // The copies of remote files an earlier run left open.
  unawaited(cleanStaleOpenCopies());
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
