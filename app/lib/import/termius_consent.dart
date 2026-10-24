import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Before reading Termius: what comes and what does not, that the system
/// will ask to let OpenWard use Termius's key, and that this is not a
/// feature of Termius's. True to go on.
Future<bool> confirmTermius(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => const _TermiusConsent(),
    ) ??
    false;

class _TermiusConsent extends StatelessWidget {
  const _TermiusConsent();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    Widget list(String title, List<String> items, {required bool brings}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: OwSpace.s1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: OwSpace.s1),
                      child: Icon(
                        brings ? Icons.check : Icons.close,
                        size: 14,
                        color: brings ? c.accentText : c.textSubtle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(color: brings ? c.text : c.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
    return AlertDialog(
      title: Text(l.termiusTitle),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.termiusIntro,
                style: TextStyle(color: c.textMuted, height: 1.45),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: list(l.termiusBrings, [
                      l.termiusBringsHosts,
                      l.termiusBringsIdentities,
                      l.termiusBringsTunnels,
                      l.termiusBringsSnippets,
                    ], brings: true),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: list(l.termiusLeaves, [
                      l.termiusLeavesPasswords,
                      l.termiusLeavesKeys,
                      l.termiusLeavesChains,
                      l.termiusLeavesTelnet,
                    ], brings: false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Callout(
                tone: Tone.info,
                padding: const EdgeInsets.all(OwSpace.s6),
                child: Text(l.termiusReadOnly),
              ),
              const SizedBox(height: 8),
              Callout(
                tone: Tone.warn,
                padding: const EdgeInsets.all(OwSpace.s6),
                child: Text(l.termiusUnofficial),
              ),
            ],
          ),
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
          child: Text(l.continueLabel),
        ),
      ],
    );
  }
}
