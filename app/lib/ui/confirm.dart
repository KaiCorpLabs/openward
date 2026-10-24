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
