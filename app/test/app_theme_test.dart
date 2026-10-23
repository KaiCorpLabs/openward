import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/app.dart';
import 'package:openward/core/settings.dart';

void main() {
  /// Folding the sidebar (⌘B) saves a setting; it must not make the themes
  /// again, which would rebuild the whole window, terminals included.
  test('the themes are made again only when a theme setting changes', () {
    final dir = Directory.systemTemp.createTempSync('app_theme');
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        settingsFileProvider.overrideWithValue(
          File('${dir.path}/settings.json'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final first = container.read(materialThemesProvider);
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(sidebar: SidebarMode.rail));
    expect(identical(container.read(materialThemesProvider), first), isTrue);
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(darkTheme: 'fosforo'));
    expect(identical(container.read(materialThemesProvider), first), isFalse);
  });
}
