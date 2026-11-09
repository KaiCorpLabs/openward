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

  /// AM-8: what was held back says what the file asked for.
  test('the agent and the open tunnel held back, in words', () {
    final l = AppLocalizationsEs();
    final agent = warningText(
      l,
      const ProgramWarning(
        subject: 'bastion',
        kind: ProgramWarningKind.agentForward,
        detail: '',
      ),
    );
    expect(agent, startsWith('bastion reenviaba el agente SSH'));
    final tunnel = warningText(
      l,
      const ProgramWarning(
        subject: 'SOCKS',
        kind: ProgramWarningKind.openTunnel,
        detail: '0.0.0.0',
      ),
    );
    expect(tunnel, startsWith('El túnel SOCKS escuchaba en 0.0.0.0'));
    expect(tunnel, contains(l.whoCanUse));
  });
}
