import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'tokens.dart';

/// A filled button that deletes or loses something.
ButtonStyle dangerButtonStyle(OwColors c) => FilledButton.styleFrom(
  backgroundColor: c.danger,
  foregroundColor: c.onDanger,
);

/// A filled button that reaches more than it seems (several panes).
ButtonStyle warnButtonStyle(OwColors c) =>
    FilledButton.styleFrom(backgroundColor: c.warn, foregroundColor: c.onWarn);

/// Asks before doing something: true to go ahead. [action] names the
/// button that does it. Esc never does it. A [danger]ous one (it loses work
/// or cannot be undone) is in the danger color and Cancel has the focus,
/// so Enter keeps things as they are too; any other has the focus on its
/// action, so Enter does it.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  required String action,
  bool danger = false,
  IconData? icon,
  Key? actionKey,
}) async {
  final l = context.l10n;
  final c = context.ow.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: icon == null
          ? null
          : Icon(icon, color: danger ? c.danger : c.textMuted),
      title: Text(title),
      content:
          content ??
          (body == null
              ? null
              : SizedBox(
                  width: 420,
                  child: Text(body, style: const TextStyle(height: 1.45)),
                )),
      actions: [
        OutlinedButton(
          autofocus: danger,
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: actionKey,
          autofocus: !danger,
          style: danger ? dangerButtonStyle(c) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// [confirmAction] for something that deletes or cannot be undone.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  required String action,
  IconData? icon,
  Key? actionKey,
}) => confirmAction(
  context,
  title: title,
  body: body,
  content: content,
  action: action,
  danger: true,
  icon: icon,
  actionKey: actionKey,
);

/// Asks for a line of text, starting from [initial]: what was written
/// when [action] (or Enter) is pressed, null if cancelled. The field's
/// controller belongs to the dialog, so it lives as long as the field.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? hint,
  String? help,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    action: action,
    initial: initial,
    hint: hint,
    help: help,
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.action,
    required this.initial,
    this.hint,
    this.help,
  });

  final String title;
  final String action;
  final String initial;
  final String? hint;
  final String? help;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _text,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.help,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
