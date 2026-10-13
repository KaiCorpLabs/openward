import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/session.dart';
import '../terminal/controller.dart';

/// A question from the session (host key, passphrase, password, 2FA), over
/// its own tab: other tabs stay usable while it waits.
class PromptCard extends StatefulWidget {
  const PromptCard({super.key, required this.controller, required this.prompt});

  final TerminalController controller;
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

  String get _title => switch (_p.kind) {
    PromptKind.hostKey => 'Primera conexión con ${_p.label}',
    PromptKind.passphrase => 'Frase de la clave',
    PromptKind.password => 'Contraseña',
    PromptKind.keyboardInteractive =>
      _p.name.isNotEmpty ? _p.name : 'Verificación',
    null => '',
  };

  List<Widget> _body(ThemeData theme) {
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'Menlo');
    switch (_p.kind) {
      case PromptKind.hostKey:
        final where = _p.port == 22 ? _p.host : '${_p.host}:${_p.port}';
        return [
          Text(
            'OpenWard no conoce todavía la clave de $where. Compara la '
            'huella con la que te dé el administrador del servidor antes de '
            'confiar en ella.',
          ),
          const SizedBox(height: 12),
          SelectableText('${_p.algorithm}\n${_p.fingerprint}', style: mono),
        ];
      case PromptKind.passphrase:
        return [
          Text('La clave ${_p.key} está protegida.'),
          if (_p.retry) _retry(theme, 'Frase incorrecta.'),
          const SizedBox(height: 12),
          _field(0, 'Frase', obscure: true),
        ];
      case PromptKind.password:
        return [
          Text('${_p.user}@${_p.host}'),
          if (_p.retry) _retry(theme, 'Contraseña incorrecta.'),
          const SizedBox(height: 12),
          _field(0, 'Contraseña', obscure: true),
        ];
      case PromptKind.keyboardInteractive:
        return [
          Text('${_p.user}@${_p.host}'),
          if (_p.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_p.instructions),
          ],
          if (_p.retry) _retry(theme, 'Respuesta incorrecta.'),
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

  Widget _retry(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(color: theme.colorScheme.error)),
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
    final hostKey = _p.kind == PromptKind.hostKey;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _answer(AnswerKind.cancel),
      },
      child: Focus(
        autofocus: hostKey,
        child: Card(
          elevation: 8,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ..._body(theme),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _answer(AnswerKind.cancel),
                        child: Text(hostKey ? 'No confiar' : 'Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _answer(
                          hostKey ? AnswerKind.accept : AnswerKind.text,
                        ),
                        child: Text(
                          hostKey ? 'Confiar y conectar' : 'Continuar',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
