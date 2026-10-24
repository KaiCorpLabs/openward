import 'package:flutter_test/flutter_test.dart';
import 'package:openward/import/programs.dart';
import 'package:openward/l10n/app_localizations_es.dart';
import 'package:openward/src/rust/api/programs.dart';

ProgramWarning _missing(MissingKind m, {String detail = ''}) => ProgramWarning(
  subject: 'web',
  kind: ProgramWarningKind.unsupported,
  detail: detail,
  missing: m,
);

void main() {
  /// Each thing that did not come has words of its own: none of them is
  /// the core's English.
  test('what did not come in, in words, by its kind', () {
    final l = AppLocalizationsEs();
    for (final m in MissingKind.values) {
      final text = warningText(l, _missing(m, detail: 'jumphost'));
      expect(text, startsWith('web: no se ha traído '), reason: '$m');
    }
    expect(
      warningText(l, _missing(MissingKind.proxy, detail: 'socks4a')),
      l.warnFeature('web', l.featureProxy('socks4a')),
    );
    expect(
      featureName(l, _missing(MissingKind.incompleteProxy)),
      l.featureIncompleteProxy,
    );
    expect(
      warningText(
        l,
        const ProgramWarning(kind: ProgramWarningKind.unreadable, detail: '3'),
      ),
      '3 elementos de los datos no se han podido leer.',
    );
  });
}
