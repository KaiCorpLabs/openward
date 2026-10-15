import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../terminal/controller.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// A question from the session (host key, passphrase, password, 2FA), over
/// its own tab: other tabs stay usable while it waits.
class PromptCard extends StatefulWidget {
  const PromptCard({super.key, required this.controller, required this.prompt});

  final ConnectionController controller;
  final PromptView prompt;

  @override
  State<PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<PromptCard> {
  late final List<TextEditingController> _fields = [
    for (var i = 0; i < _fieldCount; i++) TextEditingController(),
  ];

  PromptView get _p => widget.prompt;

  int get _fieldCount => switch (_p.kind) {
    PromptKind.passphrase || PromptKind.password => 1,
    PromptKind.keyboardInteractive => _p.questions.length,
    // The user too, when the settings name none.
    PromptKind.proxyLogin => _p.user.isEmpty ? 2 : 1,
    _ => 0,
  };

  @override
  void dispose() {
    // Dart cannot wipe strings; at least the fields let go of them now.
    for (final f in _fields) {
      f.clear();
      f.dispose();
    }
    super.dispose();
  }

  void _answer(AnswerKind kind) {
    final texts = kind == AnswerKind.text
        ? [for (final f in _fields) f.text]
        : <String>[];
    widget.controller.answer(_p, PromptAnswer(kind: kind, texts: texts));
  }

  String _title(AppLocalizations l) => switch (_p.kind) {
    PromptKind.hostKey => l.firstConnectionTo(_p.label),
    PromptKind.passphrase => l.passphraseTitle,
    PromptKind.password => l.passwordTitle,
    PromptKind.proxyLogin => l.proxyLoginTitle,
    PromptKind.keyboardInteractive =>
      _p.name.isNotEmpty
          ? _p.name
          // PAM asks for the password this way.
          : _p.questions.length == 1 &&
                _p.questions.single.text.toLowerCase().contains('password')
          ? l.passwordTitle
          : l.verificationTitle,
    null => '',
  };

  List<Widget> _body(BuildContext context, AppLocalizations l) {
    final ow = context.ow;
    switch (_p.kind) {
      case PromptKind.hostKey:
        final where = _p.port == 22 ? _p.host : '${_p.host}:${_p.port}';
        return [
          Text(
            l.hostKeyUnknownBody(where),
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ow.colors.sunken,
              borderRadius: BorderRadius.circular(ow.shape.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _p.algorithm,
                  style: TextStyle(fontSize: 11, color: ow.colors.textMuted),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  _p.fingerprint,
                  style: monoStyle(context, color: ow.colors.text),
                ),
              ],
            ),
          ),
        ];
      case PromptKind.passphrase:
        return [
          Text(l.keyProtected(_p.key)),
          if (_p.retry) _retry(context, l.wrongPassphrase),
          const SizedBox(height: 12),
          _field(0, l.passphraseField, obscure: true),
        ];
      case PromptKind.password:
        return [
          Text('${_p.user}@${_p.host}', style: monoStyle(context)),
          if (_p.retry) _retry(context, l.wrongPassword),
          const SizedBox(height: 12),
          _field(0, l.passwordTitle, obscure: true),
        ];
      case PromptKind.proxyLogin:
        return [
          Text(l.proxyLoginBody(_p.host), style: const TextStyle(height: 1.45)),
          if (_p.retry) _retry(context, l.wrongPassword),
          const SizedBox(height: 12),
          if (_p.user.isEmpty) ...[
            _field(0, l.proxyUser, obscure: false),
            const SizedBox(height: 12),
            _field(1, l.passwordTitle, obscure: true),
          ] else ...[
            Text(_p.user, style: monoStyle(context)),
            const SizedBox(height: 12),
            _field(0, l.passwordTitle, obscure: true),
          ],
        ];
      case PromptKind.keyboardInteractive:
        return [
          Text('${_p.user}@${_p.host}', style: monoStyle(context)),
          if (_p.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_p.instructions),
          ],
          if (_p.retry) _retry(context, l.wrongAnswer),
          for (var i = 0; i < _p.questions.length; i++) ...[
            const SizedBox(height: 12),
            _field(
              i,
              _p.questions[i].text.trim(),
              obscure: !_p.questions[i].echo,
            ),
          ],
        ];
      case null:
        return const [];
    }
  }

  Widget _retry(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(color: context.ow.colors.danger)),
  );

  Widget _field(int i, String label, {required bool obscure}) => TextField(
    controller: _fields[i],
    autofocus: i == 0,
    obscureText: obscure,
    enableSuggestions: !obscure,
    autocorrect: false,
    decoration: InputDecoration(labelText: label),
    onSubmitted: (_) {
      if (i == _fields.length - 1) _answer(AnswerKind.text);
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ow = context.ow;
    final l = context.l10n;
    final hostKey = _p.kind == PromptKind.hostKey;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _answer(AnswerKind.cancel),
      },
      child: Focus(
        autofocus: hostKey,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          decoration: BoxDecoration(
            color: hostKey ? ow.colors.infoSoft : ow.colors.raised,
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
            border: Border.all(
              color: hostKey ? ow.colors.infoLine : ow.colors.control,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title(l), style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ..._body(context, l),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _answer(AnswerKind.cancel),
                    child: Text(hostKey ? l.dontTrust : l.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        _answer(hostKey ? AnswerKind.accept : AnswerKind.text),
                    child: Text(hostKey ? l.trustAndConnect : l.continueLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
