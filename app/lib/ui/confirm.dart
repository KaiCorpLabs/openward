import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'tokens.dart';

/// Asks before something that loses work or cannot be undone: true to go
/// ahead. [action] names the button that does it; Cancel has the focus,
/// so Enter and Esc both keep things as they are.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? body,
  required String action,
  bool danger = false,
}) async {
  final l = context.l10n;
  final c = context.ow.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null
          ? null
          : SizedBox(
              width: 420,
              child: Text(body, style: const TextStyle(height: 1.45)),
            ),
      actions: [
        OutlinedButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: c.danger,
                  foregroundColor: c.surface,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
