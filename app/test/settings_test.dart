import 'package:flutter_test/flutter_test.dart';
import 'package:openward/welcome/whats_new.dart';
import 'package:openward/core/settings.dart';
import 'package:openward/terminal/schemes.dart';

void main() {
  test('settings go to JSON and back', () {
    const s = Settings(
      fontSize: 15,
      theme: ThemeChoice.light,
      language: Language.en,
      welcomed: true,
    );
    expect(Settings.fromJson(s.toJson()), s);
  });

  test('an old file (no language, no guide) gets the defaults', () {
    final s = Settings.fromJson({'font_size': 14, 'theme': 'dark'});
    expect(s.language, Language.system);
    expect(s.welcomed, isFalse);
    expect(s.fontSize, 14);
  });

  test('unknown values fall back one by one', () {
    final s = Settings.fromJson({'language': 'klingon', 'welcomed': 'yes'});
    expect(s.language, Language.system);
    expect(s.welcomed, isFalse);
  });

  test('themes, layers, imported schemes and accessibility come back', () {
    final s =
        const Settings(
              lightTheme: 'nativo',
              darkTheme: 'fosforo',
              textScale: 1.25,
              lineHeight: 1.35,
              minimumContrast: false,
              motion: MotionChoice.reduce,
              cursor: CursorChoice.bar,
              cursorBlink: true,
              bellFlash: false,
            )
            .copyWith(schemes: [knownSchemes.first])
            .withOverrides(
              'fosforo',
              (o) => o.copyWith(
                colors: () => 'grafito',
                terminalFont: () => 'Fira Code',
                terminal: TerminalColors.scheme,
                scheme: () => 'nord',
              ),
            );
    final back = Settings.fromJson(s.toJson());
    expect(back, s);
    expect(back.overrides['fosforo']!.terminalFont, 'Fira Code');
    expect(back.schemes.single.name, 'Solarized Dark');
  });

  test('resetting a theme forgets its layers', () {
    final s = const Settings()
        .withOverrides('grafito', (o) => o.copyWith(shape: () => 'papel'))
        .withOverrides('grafito', (_) => const ThemeOverrides());
    expect(s.overrides, isEmpty);
  });

  test("a release's news is shown once, and not on a first run", () {
    expect(shouldShowNews(const Settings()), isFalse);
    const updated = Settings(welcomed: true);
    expect(shouldShowNews(updated), isTrue);
    final seen = updated.copyWith(seenNews: newsVersion);
    expect(shouldShowNews(seen), isFalse);
    expect(Settings.fromJson(seen.toJson()).seenNews, newsVersion);
    expect(updated.toJson().containsKey('seen_news'), isFalse);
  });

  test('the sidebar, the terminal margin and recent connections come back', () {
    const s = Settings(
      sidebar: SidebarMode.rail,
      sidebarOnSession: SidebarOnSession.hide,
      sidebarWidth: 320,
      terminalPadding: 8,
      recentConnections: false,
    );
    expect(Settings.fromJson(s.toJson()), s);
    // An older file: the defaults (open, as it is, 272 px, 12 px).
    final old = Settings.fromJson({'font_size': 13});
    expect(old.sidebar, SidebarMode.open);
    expect(old.sidebarOnSession, SidebarOnSession.keep);
    expect(old.sidebarWidth, Settings.defaultSidebarWidth);
    expect(old.terminalPadding, 12);
    expect(old.recentConnections, isTrue);
    // Out of range: the default.
    final wide = Settings.fromJson({
      'sidebar_width': 900,
      'terminal_padding': 40,
    });
    expect(wide.sidebarWidth, Settings.defaultSidebarWidth);
    expect(wide.terminalPadding, 12);
  });
}
