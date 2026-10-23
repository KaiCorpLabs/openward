import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/connection.dart';
import 'package:openward/l10n/l10n.dart';
import 'package:openward/tabs/connection_motion.dart';
import 'package:openward/ui/themes.dart';

/// A connection with no answer since `stalledSince`.
class _Stalled extends Fake implements ConnectionController {
  _Stalled(this.stalledSince);

  @override
  DateTime? stalledSince;

  @override
  String get label => 'web-1';
}

void main() {
  /// «sin respuesta desde N s» counts up while it lasts: its timer ticks.
  testWidgets('the seconds without an answer go on counting', (tester) async {
    final since = DateTime.now().subtract(const Duration(seconds: 3));
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(OwThemes.grafito),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StalledNotice(controller: _Stalled(since))),
      ),
    );
    String seconds() => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((t) => t.text.toPlainText())
        .firstWhere((t) => t.contains('web-1'));
    final before = seconds();
    // Real time passes; the widget only shows it if its timer fires.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(seconds(), isNot(before));
    await tester.pumpWidget(const SizedBox());
  });
}
