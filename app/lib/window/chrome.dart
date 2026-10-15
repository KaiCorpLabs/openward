// The window as the app draws it. On macOS the content goes under a
// transparent title bar (macos/Runner/MainFlutterWindow.swift): the app's
// top bar holds the window buttons, and dragging or double-clicking its
// empty parts does what a title bar does. Windows and Linux keep the
// system's title bar for now (docs/plan/v0.2.md).

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _channel = MethodChannel('openward/window');

/// The top bar's height, the same as in MainFlutterWindow.swift.
const double topBarHeight = 40;

/// Room on the left of the top bar for the window buttons.
const double windowButtonsWidth = 84;

/// The app draws the title bar itself.
bool get customTitleBar => Platform.isMacOS;

Future<void> _call(String method) async {
  try {
    await _channel.invokeMethod<void>(method);
  } on MissingPluginException {
    // Widget tests run without the native window.
  }
}

/// Whether the window fills the screen: the window buttons are hidden
/// then, and the top bar needs no room for them.
class FullScreenNotifier extends Notifier<bool> {
  @override
  bool build() {
    if (!customTitleBar) return false;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fullScreen') state = call.arguments == true;
    });
    _channel
        .invokeMethod<bool>('isFullScreen')
        .then((v) => state = v ?? false)
        .catchError((_) => false);
    return false;
  }
}

final fullScreenProvider = NotifierProvider<FullScreenNotifier, bool>(
  FullScreenNotifier.new,
);

/// Empty space in the top bar: dragging it moves the window and a double
/// click zooms it (or what the system is set to do).
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!customTitleBar) return child ?? const SizedBox.expand();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _call('drag'),
      onDoubleTap: () => _call('doubleClick'),
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// The room the window buttons need at the top of the sidebar.
class WindowButtonsSpace extends ConsumerWidget {
  const WindowButtonsSpace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!customTitleBar) return const SizedBox(height: 10);
    final full = ref.watch(fullScreenProvider);
    return SizedBox(
      height: full ? 10 : topBarHeight,
      child: const WindowDragArea(),
    );
  }
}
