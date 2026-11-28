import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import '../src/rust/frb_generated.dart';

const _probeSymbol =
    'frbgen_openward_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerLogPlayer';

/// Initializes [RustLib], preferring symbols linked into the main binary on
/// Apple platforms (SwiftPM static linking) before falling back to dynamic loading.
Future<void> initRustLib() {
  if ((Platform.isMacOS || Platform.isIOS) &&
      ffi.DynamicLibrary.process().providesSymbol(_probeSymbol)) {
    return RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  }
  return RustLib.init();
}
