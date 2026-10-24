// Asking before a paste: text that would run (more than one line), that
// hides characters, or that goes to every pane at once.

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../ui/confirm.dart';
import '../ui/tokens.dart';
import 'visible_text.dart';

int _lines(String text) => '\n'.allMatches(text.trimRight()).length + 1;

String _cut(String text, int max) =>
    text.length > max ? '${text.substring(0, max)}…' : text;

/// Asks before pasting `text` into one terminal: true to paste. Enter
/// pastes: it was pasted on purpose.
Future<bool> confirmPaste(
  BuildContext context,
  String text, {
  String? fontFamily,
}) async {
  final l = context.l10n;
  final ow = context.ow;
  final lines = _lines(text);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // On one line it asks only for what does not show.
      title: Text(
        lines > 1 || !hasHidden(text) ? l.pasteMultiTitle : l.pasteHiddenTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lines > 1 || !hasHidden(text)) Text(l.pasteMultiBody),
            const SizedBox(height: 12),
            PastePreview(_cut(text, 400), fontFamily: fontFamily),
            if (hasHidden(text)) _HiddenNote(color: ow.colors.warn),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.paste),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// With broadcast, a paste always asks first: where it goes, and what.
/// Null to paste nothing, false only `here`, true in every pane of
/// `names`. Enter pastes only here, the safe one of the two.
Future<bool?> confirmBroadcastPaste(
  BuildContext context,
  String text, {
  required String here,
  required List<String> names,
  String? fontFamily,
}) {
  final l = context.l10n;
  final c = context.ow.colors;
  final lines = text.split('\n').where((x) => x.isNotEmpty).length;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.podcasts, color: c.warn),
      title: Text(l.broadcastPasteTitle(names.length)),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.broadcastPasteBody(lines, names.join(', ')),
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: PastePreview(
                  _cut(text, 600),
                  fontFamily: fontFamily,
                  fontSize: OwText.small,
                ),
              ),
            ),
            if (hasHidden(text)) _HiddenNote(color: c.warn),
            const SizedBox(height: 10),
            Text(
              l.broadcastPasteAlways,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        OutlinedButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.pasteOnlyHere(here)),
        ),
        FilledButton(
          style: warnButtonStyle(c),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.pasteInPanes(names.length)),
        ),
      ],
    ),
  );
}

/// What is pasted, in the terminal's font and colors, with what would
/// not show marked.
class PastePreview extends StatelessWidget {
  const PastePreview(this.text, {super.key, this.fontFamily, this.fontSize});

  final String text;
  final String? fontFamily;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OwSpace.s5),
      decoration: BoxDecoration(
        color: ow.terminal.background,
        border: Border.all(color: ow.colors.border),
        borderRadius: BorderRadius.circular(ow.shape.radius),
      ),
      child: Text.rich(
        visibleText(
          text,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            color: ow.terminal.foreground,
          ),
          mark: TextStyle(color: ow.colors.warn, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _HiddenNote extends StatelessWidget {
  const _HiddenNote({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: OwSpace.s4),
    child: Text(
      context.l10n.pasteHasHidden,
      style: TextStyle(fontSize: OwText.small, color: color),
    ),
  );
}
